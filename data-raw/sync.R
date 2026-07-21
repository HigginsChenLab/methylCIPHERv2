# Vendor methylCIPHER-meta -> R package snapshot.
#
#   source("data-raw/sync.R")
#   sync()                               # fetch default tip, materialize
#   sync(source_git_sha = "dc543a7b...") # pin a specific commit
#   sync(upload = TRUE)                  # also publish external qs2 to GitHub Releases
#
# Outputs:
#   R/sysdata.rda                    catalog + group sidecars + small tensor bundles
#                                    (+ mc_provenance$external_assets registry)
#   data-raw/assets/*.qs2            SystemsAge / PCClocks / PCBrainAge (content-addressed)
#
# Setup:
#   uv sync .
#   For upload=TRUE: create a fine-grained GitHub PAT with Contents:read/write on the
#   package repo and set it as METHYLCIPHER_UPLOAD_PAT in ~/.Renviron. Keep it OUT of
#   GITHUB_PAT/GITHUB_TOKEN so it does not shadow remotes::install_github()'s broad token.
#
# Upstream provenance/integrity is owned by methylCIPHER-meta; this script only consumes.

# --- setup -------------------------------------------------------------------

for (pkg in c("jsonlite", "qs2", "usethis", "digest", "processx", "fs", "rlang")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package '", pkg, "'. Install it first.", call. = FALSE)
  }
}

`%||%` <- rlang::`%||%`

asset_dir <- file.path("data-raw", "assets")
meta_dir <- file.path("data-raw", "methylCIPHER-meta")

META_REMOTE <- "https://github.com/hhp94/methylCIPHER-meta.git"

# External families ship as release assets due to size; the rest ride in sysdata.
EXTERNAL_GROUPS <- c("SystemsAge", "PCClocks", "PCBrainAge")

# Bump when the in-memory pack layout changes (forces a new payload_hash). See dev/DECISIONS.md.
EXTERNAL_ENCODING_VERSION <- 3L

# Never part of the hashed pack -- leaking a pin field would defeat content-addressing.
EXTERNAL_PIN_FIELDS <- c("source_git_sha", "manifest_generated_at_sha")

# A weights/ tensor reference: anchored both ends so prose/other trees never match.
WEIGHTS_REF_RE <- "^weights/.+\\.(csv\\.gz|csv|[Rr])$"

# --- field registries (meta JSON -> shipped catalog) -------------------------
# Keep only the scoring contract + a thin license/fixture stub; drop upstream provenance.

FIELD_REGISTRY <- c(
  "clock_id",
  "group_id",
  "weights_format",
  "computation_type",
  "pmid",
  "output_transform",
  "normalization",
  "imputation",
  "intercept",
  "covariates",
  "recipe",
  "components",
  "shared",
  "external",
  "probe_sets",
  "code_ref",
  "definition",
  "depends_on_clocks",
  "n_cpgs_normalization",
  "covers",
  "license"
)

# Build-time only (resolve_scoring_cpgs); stripped after resolution, never shipped.
CATALOG_BUILD_ONLY_FIELDS <- c("covers", "shared")

# Derived local paths stripped from the catalog embedded in a content-addressed pack.
CATALOG_PACK_DROP_FIELDS <- c("meta_path", "coef_path")

trim_build_only_fields <- function(clocks) {
  lapply(clocks, function(e) {
    e[CATALOG_BUILD_ONLY_FIELDS] <- NULL
    e
  })
}

BIB_INST_PATH <- file.path("inst", "bibliography", "clocks.bib")

GROUP_FIELD_REGISTRY <- c("group_id", "members", "shared_tensors")

IMPUTATION_FIELDS <- c("policy", "ref")
COMPONENT_FIELDS <- c("name", "file", "row_key", "col_key", "intercept", "covariates")
SHARED_FIELDS <- c("name", "file")
PROBE_SET_FIELDS <- c("name", "role", "file", "n")
EXTERNAL_FIELDS <- c("r_package", "github", "commit", "function", "model_key", "depends")
FIXTURE_FIELDS <- c("expected", "oracle", "parity_policy", "parity_metric")
RECIPE_STEP_DROP <- c("note")

# Keep named fields; preserves explicit JSON nulls (imputation$ref = null).
keep_fields <- function(x, fields) {
  if (is.null(x) || !is.list(x)) {
    return(NULL)
  }
  out <- list()
  for (f in fields) {
    if (f %in% names(x)) {
      out[f] <- list(x[[f]])
    }
  }
  if (!length(out)) NULL else out
}

keep_fields_each <- function(xs, fields) {
  if (is.null(xs) || !is.list(xs)) {
    return(NULL)
  }
  lapply(xs, function(item) keep_fields(item, fields))
}

prune_recipe <- function(recipe) {
  if (is.null(recipe)) {
    return(NULL)
  }
  lapply(recipe, function(step) {
    if (!is.list(step)) {
      return(step)
    }
    drop <- intersect(RECIPE_STEP_DROP, names(step))
    if (length(drop)) {
      step[drop] <- NULL
    }
    step
  })
}

prune_fixture <- function(fx) {
  if (is.null(fx) || !is.list(fx)) {
    return(NULL)
  }
  parity <- fx$parity %||% list()
  stub <- list(
    expected = fx$expected %||% NULL,
    oracle = fx$oracle %||% NULL,
    parity_policy = parity$policy %||% NULL,
    parity_metric = parity$metric %||% NULL
  )
  stub <- stub[!vapply(stub, is.null, logical(1L))]
  if (!length(stub)) NULL else stub
}

# probe_sets only for external_package; other weights_formats drop it even if present.
prune_clock_meta <- function(meta) {
  wf <- as.character(meta$weights_format %||% NA_character_)
  keep <- FIELD_REGISTRY
  if (!identical(wf, "external_package")) {
    keep <- setdiff(keep, "probe_sets")
  }
  out <- keep_fields(meta, keep)
  if (is.null(out)) {
    return(list())
  }
  if ("imputation" %in% names(out)) {
    out$imputation <- keep_fields(out$imputation, IMPUTATION_FIELDS)
  }
  if ("components" %in% names(out)) {
    out$components <- keep_fields_each(out$components, COMPONENT_FIELDS)
  }
  if ("shared" %in% names(out)) {
    out$shared <- keep_fields_each(out$shared, SHARED_FIELDS)
  }
  if ("probe_sets" %in% names(out)) {
    out$probe_sets <- keep_fields_each(out$probe_sets, PROBE_SET_FIELDS)
  }
  if ("external" %in% names(out)) {
    out$external <- keep_fields(out$external, EXTERNAL_FIELDS)
  }
  if ("recipe" %in% names(out)) {
    out$recipe <- prune_recipe(out$recipe)
  }
  out
}

prune_group_meta <- function(gmeta) {
  keep_fields(gmeta, GROUP_FIELD_REGISTRY) %||% list()
}

# --- bibliography ------------------------------------------------------------
# clocks.bib is vendored as-is; pmid -> bib_key is joined in memory (papers.csv never ships).

read_papers_csv <- function(repo_path) {
  path <- file.path(repo_path, "bibliography", "papers.csv")
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  list(
    bib_key = stats::setNames(trimws(df$bib_key), trimws(df$pmid)),
    n = nrow(df)
  )
}

vendor_bibliography <- function(repo_path) {
  src <- file.path(repo_path, "bibliography", "clocks.bib")
  fs::dir_create(dirname(BIB_INST_PATH))
  fs::file_copy(src, BIB_INST_PATH, overwrite = TRUE)
  sz <- file.info(BIB_INST_PATH)$size
  message(sprintf("sync: wrote %s (%.1f KB)", BIB_INST_PATH, sz / 1024))
  invisible(list(path = BIB_INST_PATH, size_bytes = sz))
}

# --- resolve SoT (GitHub -> data-raw/methylCIPHER-meta) ----------------------

git_exec <- function(..., dir = NULL) {
  args <- c(...)
  if (!is.null(dir)) {
    args <- c("-C", dir, args)
  }
  # processx captures stdout/stderr/status; git's stderr progress/hints stay out of the answer.
  res <- processx::run("git", args, error_on_status = FALSE)
  if (res$status != 0L) {
    stop("git ", paste(args, collapse = " "), " failed:\n", res$stderr, call. = FALSE)
  }
  # Preserve the historical stdout-lines contract (system2(stdout = TRUE) returned a vector).
  if (nzchar(res$stdout)) strsplit(res$stdout, "\r?\n")[[1]] else character()
}

# git_exec for commands whose stdout IS the answer; asserts exactly one line back.
git_value <- function(..., dir = NULL) {
  out <- trimws(git_exec(..., dir = dir))
  out <- out[nzchar(out)]
  if (length(out) != 1L) {
    stop(
      "git returned ",
      length(out),
      " lines where one value was expected:\n",
      paste(out, collapse = "\n"),
      call. = FALSE
    )
  }
  out
}

# Clone/fetch into meta_dir, checkout a commit. NULL = origin's default branch tip.
resolve_source <- function(source_git_sha = NULL) {
  fs::dir_create(dirname(meta_dir))

  # A dir that is not a valid repo (interrupted clone, stray extraction) is discarded
  # and re-cloned -- the mirror is gitignored and disposable.
  is_repo <- dir.exists(file.path(meta_dir, ".git"))
  if (dir.exists(meta_dir) && !is_repo) {
    unlink(meta_dir, recursive = TRUE, force = TRUE)
  }

  if (!is_repo) {
    # Clone into a temp sibling then rename, so a clone that dies partway never poisons meta_dir.
    message("sync: cloning ", META_REMOTE, " -> ", meta_dir)
    tmp <- paste0(meta_dir, ".tmp-", Sys.getpid())
    unlink(tmp, recursive = TRUE, force = TRUE)
    git_exec("clone", "--filter=blob:none", META_REMOTE, tmp)
    file.rename(tmp, meta_dir)
  } else {
    message("sync: fetching ", META_REMOTE, " into ", meta_dir)
    git_exec("remote", "set-url", "origin", META_REMOTE, dir = meta_dir)
    git_exec("fetch", "origin", "--tags", "--prune", dir = meta_dir)
  }

  if (!is.null(source_git_sha) && nzchar(source_git_sha)) {
    ref <- source_git_sha
  } else {
    ref <- tryCatch(
      git_value("symbolic-ref", "--short", "refs/remotes/origin/HEAD", dir = meta_dir),
      error = function(e) NA_character_
    )
    if (is.na(ref) || !nzchar(ref)) {
      ref <- "origin/master"
    }
  }
  message("sync: checkout ", ref)
  # -f: the mirror is disposable; force a pristine tree so a stray edit can't refuse or ride along.
  git_exec("checkout", "-f", "--detach", ref, dir = meta_dir)

  path <- as.character(fs::path_real(meta_dir))
  sha <- git_value("rev-parse", "HEAD", dir = path)
  list(path = path, source_git_sha = sha)
}

# --- manifest ----------------------------------------------------------------

read_manifest <- function(repo_path) {
  jsonlite::fromJSON(file.path(repo_path, "manifest.json"), simplifyVector = FALSE)
}

# --- catalog crawl -----------------------------------------------------------

# recurse weights/; discriminate clock vs group meta by basename, never depth
list_meta_files <- function(repo_path) {
  metas <- list.files(
    file.path(repo_path, "weights"),
    pattern = "\\.meta\\.json$",
    recursive = TRUE,
    full.names = TRUE
  )
  basenames <- basename(metas)
  list(
    clock = metas[basenames != "_group.meta.json"],
    group = metas[basenames == "_group.meta.json"]
  )
}

# covariate names from recipe + top-level field + sex-keyed impute refs
extract_covariates <- function(meta) {
  flatten_names <- function(x) {
    if (is.null(x)) {
      return(character())
    }
    if (is.character(x)) {
      return(x)
    }
    if (is.list(x)) {
      nms <- names(x)
      if (!is.null(nms) && any(nzchar(nms))) {
        return(nms[nzchar(nms)])
      }
      return(as.character(unlist(x, use.names = FALSE)))
    }
    character()
  }

  covariate_keys <- function(x) {
    nms <- names(x)
    if (is.null(nms)) {
      return(character())
    }
    nms[grepl("covariates$", nms)]
  }

  covs <- flatten_names(meta$covariates)
  for (step in meta$recipe %||% list()) {
    for (k in covariate_keys(step)) {
      covs <- c(covs, flatten_names(step[[k]]))
    }
    if (identical(step$op, "linear_sex")) {
      covs <- c(covs, "Female")
    }
  }

  for (sp in meta$sex_params %||% list()) {
    covs <- c(covs, flatten_names(sp$covariates))
  }
  if (isTRUE(meta$sex_stratified)) {
    covs <- c(covs, "Female")
  }

  ref <- meta$imputation$ref
  if (is.list(ref) && any(c("female", "male") %in% names(ref))) {
    covs <- c(covs, "Female")
  }

  unique(covs[nzchar(covs) & !is.na(covs)])
}

# batch-dependent ops: scoring a subset != subset of full-cohort scores
extract_batch_ops <- function(meta) {
  ops <- vapply(
    meta$recipe %||% list(),
    function(s) as.character(s$op %||% NA_character_),
    character(1L)
  )
  intersect(ops[!is.na(ops)], c("cohort_zscore", "sample_scale"))
}

# relative path from repo root (forward slashes); callers only ever pass in-repo paths
rel_from_repo <- function(abs_path, repo_path) {
  as.character(fs::path_rel(abs_path, start = repo_path))
}

# meta-declared repo-relative path (weights/...) -> absolute
resolve_repo_rel <- function(repo_path, rel) {
  if (is.null(rel) || !nzchar(rel)) {
    return(NA_character_)
  }
  file.path(repo_path, rel)
}

build_catalog <- function(repo_path, manifest) {
  files <- list_meta_files(repo_path)

  groups <- list()
  for (gp in files$group) {
    gmeta <- jsonlite::fromJSON(gp, simplifyVector = FALSE)
    gid <- as.character(gmeta$group_id %||% NA_character_)
    entry <- prune_group_meta(gmeta)
    if (!is.null(entry$members)) {
      entry$members <- unlist(entry$members, use.names = FALSE)
    }
    if (!is.null(entry$shared_tensors)) {
      entry$shared_tensors <- unlist(entry$shared_tensors, use.names = FALSE)
    }
    entry$path <- rel_from_repo(gp, repo_path)
    groups[[gid]] <- entry
  }

  papers <- read_papers_csv(repo_path)

  clocks <- list()
  for (mp in files$clock) {
    meta <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
    cid <- as.character(meta$clock_id %||% NA_character_)
    gid <- as.character(meta$group_id %||% NA_character_)

    wf <- as.character(meta$weights_format %||% NA_character_)
    batch_ops <- extract_batch_ops(meta)
    covs <- extract_covariates(meta)

    default_coef <- file.path("weights", gid, paste0(cid, ".csv.gz"))
    has_default_coef <- file.exists(file.path(repo_path, default_coef))

    entry <- prune_clock_meta(meta)

    if (!is.null(entry$normalization)) {
      entry$normalization <- unlist(entry$normalization, use.names = FALSE)
    }
    entry$output_transform <- as.character(entry$output_transform %||% "identity")
    if (!is.null(entry$computation_type)) {
      entry$computation_type <- as.character(entry$computation_type)
    }
    if (!is.null(entry$depends_on_clocks)) {
      entry$depends_on_clocks <- unlist(entry$depends_on_clocks, use.names = FALSE)
    }
    entry$pmid <- as.character(entry$pmid %||% NA_character_)
    entry$bib_key <- unname(papers$bib_key[entry$pmid])

    entry$imputation_policy <- as.character(
      entry$imputation$policy %||% meta$imputation$policy %||% NA_character_
    )
    entry$covariates_required <- covs
    entry$batch_ops <- batch_ops
    entry$batch_dependent <- length(batch_ops) > 0L
    entry$external_group <- gid %in% EXTERNAL_GROUPS
    entry$fixture <- prune_fixture(meta$fixture)
    entry$meta_path <- rel_from_repo(mp, repo_path)
    entry$coef_path <- if (identical(wf, "cpg_coefficient") && has_default_coef) {
      default_coef
    } else {
      NULL
    }

    clocks[[cid]] <- entry
  }

  list(
    clocks = clocks,
    groups = groups,
    source_git_sha = NA_character_,
    schema_version = manifest$schema_version,
    n_clocks = length(clocks)
  )
}

# --- tensor IO ---------------------------------------------------------------

# weights/*.csv.gz -> named numeric | character vector | data.frame.
# read.csv types each column from its contents; never re-coerce by position (a character key
# column, e.g. DNAmFitAge/kdm_params.csv.gz col 2, would be silently NA'd).
read_tensor_csv <- function(path) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!nrow(df)) {
    return(df)
  }
  if (ncol(df) == 1L) {
    return(as.character(df[[1L]]))
  }
  # two-column key/value only when the value column really is numeric; a character second
  # column is a lookup table (cpg,module) and stays a data.frame with its types intact.
  if (ncol(df) == 2L && is.numeric(df[[2L]])) {
    key <- as.character(df[[1L]])
    if (anyDuplicated(key)) {
      stop("Duplicate keys in ", path, " -- a named vector would silently collapse them", call. = FALSE)
    }
    return(stats::setNames(df[[2L]], key))
  }
  df
}

# every weights/ path a meta references, wherever it sits in the JSON. Walk the whole document
# and keep whatever IS a weights/ path (value-shape driven, not a maintained parent-key list).
collect_weights_refs <- function(x) {
  found <- character()
  walk <- function(node) {
    if (is.character(node)) {
      found <<- c(found, node[grepl(WEIGHTS_REF_RE, node)])
    } else if (is.list(node)) {
      lapply(node, walk)
    }
    invisible(NULL)
  }
  walk(x)
  unique(found[nzchar(found) & !is.na(found)])
}

collect_file_refs <- function(entry, repo_path) {
  meta_abs <- resolve_repo_rel(repo_path, entry$meta_path)
  raw <- jsonlite::fromJSON(meta_abs, simplifyVector = FALSE)
  paths <- collect_weights_refs(raw)
  if (!is.null(entry$coef_path)) {
    paths <- c(paths, entry$coef_path)
  }
  unique(paths[nzchar(paths) & !is.na(paths)])
}

# --- materialize -------------------------------------------------------------

# per-group tensor payload for a set of group_ids
build_group_bundles <- function(repo_path, catalog, group_ids) {
  bundles <- list()
  for (gid in group_ids) {
    member_ids <- names(catalog$clocks)[
      vapply(catalog$clocks, function(c) identical(c$group_id, gid), logical(1L))
    ]
    members <- catalog$clocks[member_ids]
    rels <- character()
    for (entry in members) {
      rels <- c(rels, collect_file_refs(entry, repo_path))
    }
    gside <- catalog$groups[[gid]]
    if (!is.null(gside$shared_tensors)) {
      rels <- c(rels, collect_weights_refs(gside$shared_tensors))
    }

    tensors <- list()
    for (rel in unique(rels)) {
      abs <- resolve_repo_rel(repo_path, rel)
      # A missing ref would silently ship a clock with no weights (intercept-only scores).
      if (!file.exists(abs)) {
        stop("Referenced tensor missing from snapshot: ", rel, " (group ", gid, ")", call. = FALSE)
      }
      if (grepl("\\.[Rr]$", rel)) {
        tensors[[rel]] <- list(type = "r_source", text = readLines(abs, warn = FALSE))
      } else {
        tensors[[rel]] <- read_tensor_csv(abs)
      }
    }

    bundles[[gid]] <- list(group_id = gid, clocks = member_ids, tensors = tensors)
  }
  bundles
}

# --- scoring CpG resolution (ship groups; role-based, format-independent) -----
# Resolve "which CpGs does this clock's SCORING step need?" once per clock and store the answer
# as materialized probe_sets {name, role, cpgs} -- cpgs an actual vector, never a file pointer.

# Row labels of one loaded tensor. Row-key column is named `cpg`; fall back to the first column.
tensor_row_keys <- function(t) {
  if (is.null(t)) {
    return(character())
  }
  if (is.data.frame(t)) {
    col <- if ("cpg" %in% names(t)) "cpg" else 1L
    return(as.character(t[[col]]))
  }
  if (is.numeric(t) && !is.null(names(t))) {
    return(names(t))
  }
  if (is.character(t) && is.null(dim(t))) {
    return(t)
  }
  character()
}

# One upstream probe_sets entry ({name, role, file, n}) -> {name, role, cpgs}. A pointer that
# resolves to nothing is a scoring hazard: it counts as role=="scoring" and suppresses the tiered
# fallback, shipping a clock that scores nothing -- so break the sync here instead.
materialize_probe_set <- function(ps, tensors, cid = NA_character_) {
  where <- paste0("probe_set '", ps$name %||% "?", "' (role ", ps$role %||% "?", ") of clock ", cid)
  if (is.null(ps$file) || !nzchar(as.character(ps$file))) {
    stop(where, " has no `file` pointer.", call. = FALSE)
  }
  if (is.null(tensors[[ps$file]])) {
    stop(where, " points at a tensor absent from the bundle: ", ps$file, call. = FALSE)
  }
  cpgs <- tensor_row_keys(tensors[[ps$file]])
  if (!length(cpgs)) {
    stop(where, " resolved to zero CpGs from ", ps$file, call. = FALSE)
  }
  if (anyDuplicated(cpgs)) {
    stop(where, " contains duplicate CpG id(s): ", ps$file, call. = FALSE)
  }
  list(name = ps$name, role = ps$role, cpgs = cpgs)
}

# Tier 3: union of a clock's OWN cpg-keyed components.
own_component_cpgs <- function(entry, tensors) {
  cpgs <- character()
  for (comp in entry$components %||% list()) {
    if (!identical(comp$row_key, "cpg")) {
      next
    }
    cpgs <- c(cpgs, tensor_row_keys(tensors[[comp$file]]))
  }
  unique(cpgs[nzchar(cpgs) & !is.na(cpgs)])
}

# Tier 4: a group shared_tensors entry that is itself a bare one-column probe list.
group_shared_cpg_list <- function(gside, tensors) {
  for (rel in gside$shared_tensors %||% character()) {
    t <- tensors[[rel]]
    if (is.character(t) && is.null(dim(t)) && length(t) > 0L) {
      return(as.character(t))
    }
  }
  character()
}

# Tiers 2-6 for one clock. Tier 1 (an upstream role=="scoring" entry) is handled by the driver.
# `seen` guards a covers-list cycle (a composite always lists itself in its own `covers`).
resolve_scoring_cpgs <- function(cid, catalog, tensors, gside, seen = character()) {
  entry <- catalog$clocks[[cid]]
  if (is.null(entry) || cid %in% seen) {
    return(character())
  }
  seen <- c(seen, cid)

  # tier 2: cpg_coefficient's own tensor.
  if (!is.null(entry$coef_path)) {
    cpgs <- tensor_row_keys(tensors[[entry$coef_path]])
    if (length(cpgs)) {
      return(cpgs)
    }
  }

  # tier 3: union of the clock's own cpg-keyed components.
  own <- own_component_cpgs(entry, tensors)
  if (length(own)) {
    return(own)
  }

  # tier 4: group-level shared bare CpG list.
  shared <- group_shared_cpg_list(gside, tensors)
  if (length(shared)) {
    return(shared)
  }

  # tier 5: recursive union over this clock's own `covers` list.
  covers <- setdiff(as.character(entry$covers %||% character()), cid)
  if (length(covers)) {
    out <- character()
    for (member in covers) {
      out <- c(out, resolve_scoring_cpgs(member, catalog, tensors, gside, seen))
    }
    if (length(out)) {
      return(unique(out))
    }
  }

  character() # tier 6: genuinely unresolved (custom, e.g. MiAge)
}

# Two passes per ship group: (1) materialize each clock's upstream probe_sets from file pointers;
# (2) synthesize a role=="scoring" entry for any clock still missing one, via the tiered resolver.
resolve_group_scoring_probe_sets <- function(catalog, bundles) {
  for (gid in names(bundles)) {
    tensors <- bundles[[gid]]$tensors
    gside <- catalog$groups[[gid]]
    member_ids <- bundles[[gid]]$clocks

    for (cid in member_ids) {
      entry <- catalog$clocks[[cid]]
      if (length(entry$probe_sets)) {
        catalog$clocks[[cid]]$probe_sets <- lapply(
          entry$probe_sets,
          materialize_probe_set,
          tensors = tensors,
          cid = cid
        )
      }
    }

    for (cid in member_ids) {
      entry <- catalog$clocks[[cid]]
      # NON-EMPTY is the test: a scoring entry that resolved to nothing must fall through.
      has_scoring <- length(Filter(
        function(p) identical(p$role, "scoring") && length(p$cpgs) > 0L,
        entry$probe_sets %||% list()
      )) > 0L
      if (has_scoring) {
        next
      }
      cpgs <- resolve_scoring_cpgs(cid, catalog, tensors, gside)
      if (length(cpgs)) {
        catalog$clocks[[cid]]$probe_sets <- c(
          entry$probe_sets %||% list(),
          list(list(name = "scoring_derived", role = "scoring", cpgs = unique(cpgs)))
        )
      }
    }
  }
  catalog
}

# --- external asset encoding -------------------------------------------------
# One probe-order carrier per group ($cpgs); cpg-aligned values as UNNAMED matrices/doubles
# ($cpgs is the sole name carrier, so a shared order isn't re-duplicated across matrices).

# named numeric -> double[n] in cpgs order (errors if the probe set differs)
align_double <- function(x, cpgs, label) {
  if (!is.numeric(x) || !is.null(dim(x))) {
    stop(label, ": expected a named numeric vector", call. = FALSE)
  }
  if (is.null(names(x))) {
    if (length(x) != length(cpgs)) {
      stop(label, ": unnamed vector length != n_cpgs", call. = FALSE)
    }
    return(as.double(x))
  }
  if (!setequal(names(x), cpgs)) {
    stop(label, ": probe set differs from canonical cpgs", call. = FALSE)
  }
  if (identical(names(x), cpgs)) {
    as.double(unname(x))
  } else {
    as.double(unname(x[cpgs]))
  }
}

# cbind named numeric tensors -> double matrix [n x k], colnames = col_names
cbind_aligned <- function(tensors, rels, cpgs, col_names) {
  if (length(rels) != length(col_names)) {
    stop("cbind_aligned: rels and col_names length mismatch", call. = FALSE)
  }
  cols <- vector("list", length(rels))
  for (i in seq_along(rels)) {
    rel <- rels[[i]]
    if (is.null(tensors[[rel]])) {
      stop("Missing tensor for matrix column ", col_names[[i]], ": ", rel, call. = FALSE)
    }
    cols[[i]] <- align_double(tensors[[rel]], cpgs, rel)
  }
  mat <- do.call(cbind, cols)
  storage.mode(mat) <- "double"
  colnames(mat) <- col_names
  mat
}

# Resolve the single probe order for a bundle: the longest named vec, cross-checked for agreement.
resolve_cpgs <- function(tensors, group_id) {
  is_named_num <- vapply(
    tensors,
    function(x) is.numeric(x) && !is.null(names(x)) && length(x) > 0L && is.null(dim(x)),
    logical(1L)
  )
  is_probe_list <- vapply(
    tensors,
    function(x) is.character(x) && length(x) > 0L && is.null(dim(x)),
    logical(1L)
  )
  named_rels <- names(tensors)[is_named_num]
  probe_list_rels <- names(tensors)[is_probe_list]
  if (!length(named_rels)) {
    stop(group_id, ": no named numeric tensors to resolve cpgs from", call. = FALSE)
  }
  lens <- vapply(named_rels, function(r) length(tensors[[r]]), integer(1L))
  ref <- names(tensors[[named_rels[which.max(lens)]]])
  for (r in named_rels[lens == max(lens)]) {
    if (!setequal(names(tensors[[r]]), ref)) {
      stop(group_id, ": probe set mismatch among cpg-aligned tensors (", r, ")", call. = FALSE)
    }
  }
  cpgs <- ref
  drop_lists <- character()
  for (r in probe_list_rels) {
    pl <- as.character(unname(tensors[[r]]))
    if (setequal(pl, ref)) {
      cpgs <- pl
      drop_lists <- c(drop_lists, r)
    }
  }
  list(cpgs = as.character(cpgs), drop_lists = unique(drop_lists))
}

# leftover tensors that are not cpg-aligned bulk (small PCA, etc.)
residual_tensors <- function(tensors, used_rels) {
  keep <- setdiff(names(tensors), used_rels)
  if (!length(keep)) {
    return(list())
  }
  tensors[keep]
}

encode_pcclocks <- function(bundle) {
  tensors <- bundle$tensors
  gid <- "PCClocks"
  resolved <- resolve_cpgs(tensors, gid)
  cpgs <- resolved$cpgs

  coef_rels <- grep("^weights/PCClocks/PC[^/]+\\.csv\\.gz$", names(tensors), value = TRUE)
  if (!length(coef_rels)) {
    stop(gid, ": no PC*.csv.gz coefficient tensors found", call. = FALSE)
  }
  col_names <- sub("\\.csv\\.gz$", "", basename(coef_rels))
  ord <- order(col_names)
  coef_rels <- coef_rels[ord]
  col_names <- col_names[ord]

  impute_rel <- "weights/PCClocks/_shared/imputeMissingCpGs.csv.gz"
  if (is.null(tensors[[impute_rel]])) {
    stop(gid, ": missing ", impute_rel, call. = FALSE)
  }

  used <- c(coef_rels, impute_rel, resolved$drop_lists)
  bundle$cpgs <- cpgs
  bundle$coefficient_matrix <- cbind_aligned(tensors, coef_rels, cpgs, col_names)
  bundle$impute <- align_double(tensors[[impute_rel]], cpgs, impute_rel)
  bundle$tensors <- residual_tensors(tensors, used)
  bundle$encoding <- "canonical_matrices"
  bundle
}

# 11 organ/system columns shared by organs + systems matrices
SYSTEMSAGE_ORGANS <- c(
  "Blood",
  "Brain",
  "Heart",
  "Hormone",
  "Immune",
  "Inflammation",
  "Kidney",
  "Liver",
  "Lung",
  "Metabolic",
  "MusculoSkeletal"
)

encode_systemsage <- function(bundle) {
  tensors <- bundle$tensors
  gid <- "SystemsAge"
  resolved <- resolve_cpgs(tensors, gid)
  cpgs <- resolved$cpgs

  organ_rels <- file.path("weights", "SystemsAge", paste0(SYSTEMSAGE_ORGANS, ".csv.gz"))
  system_rels <- file.path("weights", "SystemsAge", "systems", paste0(SYSTEMSAGE_ORGANS, ".csv.gz"))
  organ_rels <- gsub("\\\\", "/", organ_rels)
  system_rels <- gsub("\\\\", "/", system_rels)
  age_rel <- "weights/SystemsAge/age/age_pc_coef.csv.gz"
  impute_rel <- "weights/SystemsAge/_shared/imputeMissingCpGs.csv.gz"
  cpgs_rel <- "weights/SystemsAge/_shared/CpGs.csv.gz"

  for (r in c(organ_rels, system_rels, age_rel, impute_rel)) {
    if (is.null(tensors[[r]])) {
      stop(gid, ": missing tensor ", r, call. = FALSE)
    }
  }

  used <- c(organ_rels, system_rels, age_rel, impute_rel, cpgs_rel, resolved$drop_lists)
  bundle$cpgs <- cpgs
  bundle$organs <- cbind_aligned(tensors, organ_rels, cpgs, SYSTEMSAGE_ORGANS)
  bundle$systems <- cbind_aligned(tensors, system_rels, cpgs, SYSTEMSAGE_ORGANS)
  bundle$age <- align_double(tensors[[age_rel]], cpgs, age_rel)
  bundle$impute <- align_double(tensors[[impute_rel]], cpgs, impute_rel)
  bundle$tensors <- residual_tensors(tensors, used)
  bundle$encoding <- "canonical_matrices"
  bundle
}

encode_pcbrainage <- function(bundle) {
  tensors <- bundle$tensors
  gid <- "PCBrainAge"
  resolved <- resolve_cpgs(tensors, gid)
  cpgs <- resolved$cpgs

  coef_rel <- "weights/PCBrainAge/PCBrainAge.csv.gz"
  impute_rel <- "weights/PCBrainAge/imputeMissingCpGs.csv.gz"
  for (r in c(coef_rel, impute_rel)) {
    if (is.null(tensors[[r]])) {
      stop(gid, ": missing ", r, call. = FALSE)
    }
  }

  used <- c(coef_rel, impute_rel, resolved$drop_lists)
  bundle$cpgs <- cpgs
  bundle$coefficient_matrix <- cbind_aligned(tensors, coef_rel, cpgs, "PCBrainAge")
  bundle$impute <- align_double(tensors[[impute_rel]], cpgs, impute_rel)
  bundle$tensors <- residual_tensors(tensors, used)
  bundle$encoding <- "canonical_matrices"
  bundle
}

encode_external_asset <- function(bundle) {
  gid <- bundle$group_id %||% NA_character_
  if (length(bundle$tensors)) {
    names(bundle$tensors) <- gsub("\\\\", "/", names(bundle$tensors))
  }
  if (identical(gid, "PCClocks")) {
    encode_pcclocks(bundle)
  } else if (identical(gid, "SystemsAge")) {
    encode_systemsage(bundle)
  } else if (identical(gid, "PCBrainAge")) {
    encode_pcbrainage(bundle)
  } else {
    stop("No external encoding for group_id=", gid, call. = FALSE)
  }
}

# Runtime-facing registry row (embedded in mc_provenance). file_sha256 gates download integrity.
external_asset_registry_row <- function(a) {
  list(
    group_id = a$group_id,
    payload_hash = a$payload_hash,
    # Fall back to the filename stem, NEVER the bare payload_hash: a raw 64-hex tag is rejected by
    # GitHub, so the registry must record the same <group>-<hash> tag the upload actually creates.
    release_tag = a$release_tag %||% sub("\\.qs2$", "", a$file %||% ""),
    file = a$file,
    file_sha256 = a$file_sha256,
    size_bytes = a$size_bytes,
    encoding = a$encoding,
    encoding_version = a$encoding_version,
    n_clocks = a$n_clocks,
    n_cpgs = a$n_cpgs
  )
}

# --- sysdata -----------------------------------------------------------------

# Flat per-clock index: scalar dispatch/discovery fields (+ a covariates list-col). The shape
# list_clocks() filters over; rebuilt from catalog every sync, never hand-edited.
build_index <- function(catalog) {
  clocks <- catalog$clocks
  ids <- names(clocks)

  scal <- function(field, default = NA_character_) {
    unname(vapply(
      clocks,
      function(e) {
        v <- e[[field]]
        if (is.null(v) || !length(v)) default else as.character(v)[[1L]]
      },
      character(1L)
    ))
  }
  lgl <- function(field) {
    unname(vapply(clocks, function(e) isTRUE(e[[field]]), logical(1L)))
  }

  idx <- data.frame(
    clock_id = ids,
    group_id = scal("group_id"),
    weights_format = scal("weights_format"),
    computation_type = scal("computation_type"),
    output_transform = scal("output_transform", "identity"),
    imputation_policy = scal("imputation_policy"),
    batch_dependent = lgl("batch_dependent"),
    external_group = lgl("external_group"),
    bib_key = scal("bib_key"),
    pmid = scal("pmid"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  idx$covariates_required <- unname(lapply(clocks, function(e) {
    as.character(e$covariates_required %||% character())
  }))
  idx$n_covariates <- lengths(idx$covariates_required)

  idx
}

build_sysdata <- function(repo_path, catalog, ship_groups, external_assets = NULL) {
  message("sync: building shipped bundles for ", length(ship_groups), " groups...")
  bundles <- build_group_bundles(repo_path, catalog, ship_groups)
  catalog <- resolve_group_scoring_probe_sets(catalog, bundles)
  catalog$clocks <- trim_build_only_fields(catalog$clocks)

  mc_catalog <- catalog$clocks
  mc_groups <- catalog$groups
  mc_bundles <- bundles
  mc_index <- build_index(catalog)
  ext_reg <- NULL
  if (!is.null(external_assets) && length(external_assets)) {
    ext_reg <- lapply(external_assets, external_asset_registry_row)
  }
  mc_provenance <- list(
    source_git_sha = catalog$source_git_sha,
    schema_version = catalog$schema_version,
    n_clocks = catalog$n_clocks,
    n_ship_groups = length(ship_groups),
    ship_groups = ship_groups,
    external_groups = EXTERNAL_GROUPS,
    external_assets = ext_reg
  )

  usethis::use_data(
    mc_catalog,
    mc_groups,
    mc_bundles,
    mc_index,
    mc_provenance,
    internal = TRUE,
    overwrite = TRUE
  )

  path <- file.path("R", "sysdata.rda")
  sz <- file.info(path)$size
  message(sprintf("sync: wrote %s (%.1f KB; %d clocks indexed)", path, sz / 1024, nrow(mc_index)))
  invisible(list(
    path = path,
    size_bytes = sz,
    objects = c("mc_catalog", "mc_groups", "mc_bundles", "mc_index", "mc_provenance")
  ))
}

# --- content-addressed external packs ----------------------------------------

# Low ZSTD level + no shuffle: prioritize decompress/load speed over size.
QS2_COMPRESS_LEVEL <- 1L
QS2_SHUFFLE <- FALSE

# Canonical in-memory pack for hash + qs_save. Excludes pin-only fields so a no-op meta commit
# with byte-identical tensors reuses the same qs2 (content-addressing).
stable_external_payload <- function(bundle) {
  for (f in EXTERNAL_PIN_FIELDS) {
    bundle[[f]] <- NULL
  }

  tensors <- bundle$tensors %||% list()
  if (length(tensors) && !is.null(names(tensors))) {
    tensors <- tensors[sort(names(tensors))]
  }

  catalog <- bundle$catalog %||% list()
  if (length(catalog)) {
    catalog <- trim_build_only_fields(catalog)
    catalog <- lapply(catalog, function(e) {
      e[CATALOG_PACK_DROP_FIELDS] <- NULL
      e
    })
  }
  if (length(catalog) && !is.null(names(catalog))) {
    catalog <- catalog[sort(names(catalog))]
  }

  clocks <- as.character(bundle$clocks %||% character())
  if (length(clocks)) {
    clocks <- sort(unique(clocks))
  }

  out <- list(
    encoding_version = as.integer(bundle$encoding_version %||% EXTERNAL_ENCODING_VERSION),
    encoding = as.character(bundle$encoding %||% "canonical_matrices"),
    group_id = as.character(bundle$group_id %||% NA_character_),
    clocks = clocks,
    schema_version = bundle$schema_version,
    catalog = if (length(catalog)) catalog else NULL,
    group = bundle$group,
    cpgs = bundle$cpgs,
    coefficient_matrix = bundle$coefficient_matrix,
    organs = bundle$organs,
    systems = bundle$systems,
    age = bundle$age,
    impute = bundle$impute,
    tensors = if (length(tensors)) tensors else NULL
  )
  out[!vapply(out, is.null, logical(1L))]
}

# Version-pinned serialization so the content-address is stable across R upgrades: version = 2L
# predates ALTREP (object written fully expanded) and xdr = TRUE fixes endianness. See dev/DECISIONS.md.
payload_hash_of <- function(payload) {
  digest::digest(
    serialize(payload, connection = NULL, version = 2L, xdr = TRUE),
    algo = "sha256",
    serialize = FALSE
  )
}

file_sha256_of <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

# --- GitHub release target ---------------------------------------------------

parse_github_owner_repo <- function(url) {
  url <- trimws(as.character(url %||% ""))
  if (!nzchar(url)) {
    return(NULL)
  }
  url <- sub("\\.git$", "", url)
  m <- regexec("(?:github\\.com[:/])([^/]+)/([^/]+)$", url, perl = TRUE)
  parts <- regmatches(url, m)[[1L]]
  if (length(parts) != 3L) {
    return(NULL)
  }
  list(owner = parts[[2L]], repo = parts[[3L]], slug = paste0(parts[[2L]], "/", parts[[3L]]))
}

# Release target: env METHYLCIPHER_RELEASE_REPO, else package origin remote.
package_release_repo <- function() {
  env <- Sys.getenv("METHYLCIPHER_RELEASE_REPO", unset = "")
  if (nzchar(env)) {
    if (grepl("/", env) && !grepl("github\\.com", env)) {
      return(list(owner = sub("/.*", "", env), repo = sub(".*/", "", env), slug = env))
    }
    parsed <- parse_github_owner_repo(env)
    if (!is.null(parsed)) {
      return(parsed)
    }
  }
  url <- tryCatch(git_value("remote", "get-url", "origin"), error = function(e) NA_character_)
  parsed <- parse_github_owner_repo(url)
  if (is.null(parsed)) {
    stop(
      "Cannot resolve package GitHub repo for releases. Set METHYLCIPHER_RELEASE_REPO=owner/repo ",
      "or configure git remote origin.",
      call. = FALSE
    )
  }
  parsed
}

package_release_target_commitish <- function() {
  env <- Sys.getenv("METHYLCIPHER_RELEASE_TARGET", unset = "")
  if (nzchar(env)) {
    return(env)
  }
  br <- tryCatch(git_value("rev-parse", "--abbrev-ref", "HEAD"), error = function(e) NA_character_)
  if (is.na(br) || !nzchar(br) || identical(br, "HEAD")) {
    return(git_value("rev-parse", "HEAD"))
  }
  br
}

# Uploads go through PyGithub, invoked as `uv run python data-raw/gh_upload.py` with the asset
# manifest on stdin. gh_upload.py is idempotent by tag=release_tag (<group>-<hash>), so an unchanged
# asset is skipped.
GH_UPLOAD_PY <- file.path("data-raw", "gh_upload.py")

uv_bin <- function() {
  w <- Sys.which("uv")
  if (!nzchar(w)) {
    stop("`uv` not found on PATH (needed to run ", GH_UPLOAD_PY, " for uploads).", call. = FALSE)
  }
  w
}

# Upload PAT lives in its OWN variable so it never shadows the broad token that
# remotes::install_github()/gh read from GITHUB_PAT. METHYLCIPHER_UPLOAD_PAT is
# canonical; GITHUB_TOKEN/GH_TOKEN stay honored as a back-compat fallback.
upload_pat <- function() {
  for (v in c("METHYLCIPHER_UPLOAD_PAT", "GITHUB_TOKEN", "GH_TOKEN")) {
    pat <- Sys.getenv(v, unset = "")
    if (nzchar(pat)) return(pat)
  }
  ""
}

upload_external_assets <- function(assets) {
  if (!length(assets)) {
    message("sync: no external assets to upload")
    return(invisible(list()))
  }
  pat <- upload_pat()
  if (!nzchar(pat)) {
    stop(
      "upload=TRUE requires a GitHub token in METHYLCIPHER_UPLOAD_PAT ",
      "(a fine-grained PAT with Contents:read/write on the package repo). ",
      "Set it in ~/.Renviron, and keep it OUT of GITHUB_PAT/GITHUB_TOKEN so it ",
      "does not shadow the broad token remotes::install_github() reads. ",
      "(GITHUB_TOKEN/GH_TOKEN remain honored as a fallback.)",
      call. = FALSE
    )
  }

  repo <- package_release_repo()
  target <- package_release_target_commitish()

  items <- lapply(assets, function(a) {
    fpath <- a$path %||% file.path(asset_dir, a$file)
    list(
      group_id = as.character(a$group_id %||% ""),
      tag = as.character(a$release_tag %||% ""),
      path = as.character(fs::path_real(fpath)),
      name = as.character(a$file %||% basename(fpath)),
      sha256 = as.character(a$file_sha256 %||% "")
    )
  })

  req <- list(slug = repo$slug, target_commitish = target, assets = unname(items))
  json <- jsonlite::toJSON(req, auto_unbox = TRUE, null = "null")

  message(
    "sync: uploading ",
    length(items),
    " external asset(s) to ",
    repo$slug,
    " (target_commitish=",
    target,
    ") via PyGithub"
  )
  # gh_upload.py reads the manifest on stdin and a token from the env. processx feeds the
  # PAT straight into the child's env (cross-platform, unlike system2(env=) on Windows) and
  # never touches this session -- so the upload PAT can't leak into interactive
  # remotes::install_github()/gh sessions. run()'s stdin takes a file, so stage the JSON.
  req_file <- tempfile("uv-gh-req-", fileext = ".json")
  on.exit(unlink(req_file), add = TRUE)
  writeLines(json, req_file)

  proc <- processx::run(
    uv_bin(),
    c("run", "python", GH_UPLOAD_PY),
    stdin = req_file,
    env = c("current", GITHUB_TOKEN = pat, GH_TOKEN = pat),
    error_on_status = FALSE
  )
  if (proc$status != 0L) {
    stop(GH_UPLOAD_PY, " failed:\n", proc$stderr, call. = FALSE)
  }

  res <- tryCatch(
    jsonlite::fromJSON(proc$stdout, simplifyVector = FALSE),
    error = function(e) NULL
  )
  for (r in res$results %||% list()) {
    message("sync: ", r$action, " ", r$name, " -> ", repo$slug, " @ tag ", r$tag)
  }
  invisible(assets)
}

# Build + stage the external qs2 packs. Content-addressed: filename = <group>-<payload_hash>.qs2
# and release tag = <group>-<payload_hash>, so an unchanged pack keeps its identity and the
# (idempotent) upload skips it.
build_external_assets <- function(repo_path, catalog, external_groups) {
  fs::dir_create(asset_dir)
  assets <- list()

  for (gid in external_groups) {
    message("sync: building external asset for ", gid, "...")
    raw_bundle <- build_group_bundles(repo_path, catalog, gid)[[gid]]
    # Resolve probe sets BEFORE encoding restructures the tensors away, and thread the resolved
    # catalog back out so the shipped mc_catalog and the pack's embedded catalog match.
    catalog <- resolve_group_scoring_probe_sets(catalog, stats::setNames(list(raw_bundle), gid))
    bundle <- encode_external_asset(raw_bundle)
    bundle$schema_version <- catalog$schema_version
    bundle$encoding_version <- EXTERNAL_ENCODING_VERSION
    bundle$catalog <- catalog$clocks[bundle$clocks]
    bundle$group <- catalog$groups[[gid]]

    payload <- stable_external_payload(bundle)
    phash <- payload_hash_of(payload)
    fname <- sprintf("%s-%s.qs2", tolower(gid), phash)
    fpath <- file.path(asset_dir, fname)
    # Release/git tag = filename stem (<group>-<hash>). NOT the bare payload_hash: GitHub's
    # pre-receive hook rejects any tag name that is exactly 40 or 64 hex chars (ambiguous with a
    # SHA-1/SHA-256 commit ref), which a raw sha256 payload_hash always is. The group prefix keeps
    # it content-addressed while making it a legal ref. See dev/DECISIONS.md.
    rtag <- sub("\\.qs2$", "", fname)

    qs2::qs_save(payload, fpath, compress_level = QS2_COMPRESS_LEVEL, shuffle = QS2_SHUFFLE)

    sz <- file.info(fpath)$size
    fsha <- file_sha256_of(fpath)
    n_cpgs <- length(payload$cpgs %||% character())
    message(sprintf(
      "sync: wrote %s (%.2f MB; payload_hash=%s; n_cpgs=%s)",
      fpath,
      sz / 1e6,
      phash,
      n_cpgs
    ))
    assets[[gid]] <- list(
      group_id = gid,
      path = fpath,
      file = fname,
      payload_hash = phash,
      release_tag = rtag,
      file_sha256 = fsha,
      size_bytes = as.integer(sz),
      n_clocks = length(payload$clocks %||% character()),
      n_cpgs = n_cpgs,
      encoding = payload$encoding %||% "canonical_matrices",
      encoding_version = as.integer(payload$encoding_version %||% EXTERNAL_ENCODING_VERSION)
    )
  }

  # Drop superseded local staging files ({group}-*.qs2 whose hash isn't current). Published
  # releases (tag = <group>-<hash>) are never touched, so older package versions still resolve.
  for (gid in external_groups) {
    keep <- as.character(assets[[gid]]$file %||% "")
    siblings <- list.files(asset_dir, pattern = paste0("^", tolower(gid), "-[0-9a-f]+\\.qs2$"))
    for (f in setdiff(siblings, keep)) {
      unlink(file.path(asset_dir, f))
      message("sync: pruned superseded staging asset ", f)
    }
  }

  list(assets = assets, catalog = catalog)
}

# --- main --------------------------------------------------------------------

sync <- function(source_git_sha = NULL, upload = FALSE) {
  src <- resolve_source(source_git_sha = source_git_sha)
  current_sha <- src$source_git_sha

  message("sync: building catalog @ ", current_sha)
  catalog <- build_catalog(src$path, read_manifest(src$path))
  catalog$source_git_sha <- current_sha

  gids <- unique(vapply(catalog$clocks, function(c) c$group_id, character(1L)))
  external <- sort(intersect(gids, EXTERNAL_GROUPS))
  ship <- sort(setdiff(gids, EXTERNAL_GROUPS))
  message(
    "sync: ",
    catalog$n_clocks,
    " clocks; ship groups=",
    length(ship),
    "; external=",
    paste(external, collapse = ", ")
  )

  ext <- build_external_assets(src$path, catalog, external)
  assets <- ext$assets
  # Adopt the catalog build_external_assets returns -- it carries the external groups' resolved
  # probe sets, so the shipped mc_catalog matches the catalog embedded in each pack.
  catalog <- ext$catalog
  sys <- build_sysdata(src$path, catalog, ship, external_assets = assets)
  bib <- vendor_bibliography(src$path)

  if (isTRUE(upload)) {
    upload_external_assets(assets)
  } else {
    message(
      "sync: staged ",
      length(assets),
      " external asset(s) under data-raw/assets/ (upload=FALSE)"
    )
  }

  message("sync: done @ ", current_sha)
  invisible(list(
    source_git_sha = current_sha,
    n_clocks = catalog$n_clocks,
    ship_groups = ship,
    external_groups = external,
    sysdata = sys,
    bibliography = bib,
    assets = assets,
    uploaded = isTRUE(upload)
  ))
}

if (interactive()) {
  message(
    "sync.R loaded. Clones/fetches ",
    META_REMOTE,
    "\n",
    "  into data-raw/methylCIPHER-meta, then materializes package data.\n",
    "  sync()\n",
    "  sync(upload = TRUE)\n",
    "  sync(source_git_sha = \"dc543a7b...\")"
  )
}
