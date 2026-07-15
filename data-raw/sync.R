# Vendor methylCIPHER-meta -> R package snapshot.
#
# Doctrine (see dev/migration-plan.md):
#   - Canonical pin = source_git_sha (full commit), not a git tag.
#   - Lockfile exists so re-runs skip re-bundle / re-upload when SHA unchanged.
#   - Skip = one string compare: lockfile$source_git_sha == manifest$source_git_sha.
#   - Never rehash tensors in R; never read control/; never score clocks here.
#   - Arithmetic-free: parse / restructure / serialize only.
#   - Product gate is golden fixtures, not this script.
#
# Interactive only. Run from the package root.
# Always clones/fetches github.com/hhp94/methylCIPHER-meta into
# data-raw/methylCIPHER-meta, then builds package snapshot from that tree.
#
#   source("data-raw/sync.R")
#   sync()                              # fetch default tip, materialize
#   sync(dry_run = TRUE)
#   sync(force = TRUE)                  # ignore lockfile
#   sync(source_git_sha = "dc543a7b...") # pin a specific commit
#
# Outputs:
#   R/sysdata.rda              catalog + group sidecars + small tensor bundles
#   data-raw/assets/*.qs2      SystemsAge / PCClocks / PCBrainAge (staged)
#   data-raw/lockfile.json     last successful source_git_sha

# --- setup -------------------------------------------------------------------

for (pkg in c("jsonlite", "qs2", "usethis")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package '", pkg, "'. Install it first.", call. = FALSE)
  }
}

`%||%` <- function(x, y) {
  if (is.null(x) || (length(x) == 1L && is.na(x))) y else x
}

lockfile_path <- file.path("data-raw", "lockfile.json")
asset_dir <- file.path("data-raw", "assets")
meta_dir <- file.path("data-raw", "methylCIPHER-meta")

# Canonical remote; local cache is always data-raw/methylCIPHER-meta
META_REMOTE <- "https://github.com/hhp94/methylCIPHER-meta.git"

# External families: ship the rest; these three go to release assets.
EXTERNAL_GROUPS <- c("SystemsAge", "PCClocks", "PCBrainAge")

# Valid verification_status values from the release manifest.
VERIFICATION_STATUS <- c("", "pending", "verified", "disputed", "skipped")

# --- lockfile ----------------------------------------------------------------

read_lockfile <- function(path = lockfile_path) {
  if (!file.exists(path)) {
    return(list(source_git_sha = NA_character_))
  }
  lock <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  if (is.null(lock$source_git_sha) || !nzchar(lock$source_git_sha)) {
    stop("Lockfile exists but source_git_sha is missing: ", path, call. = FALSE)
  }
  lock
}

write_lockfile <- function(
  source_git_sha,
  schema_version = NULL,
  external_assets = NULL,
  n_clocks = NULL,
  path = lockfile_path
) {
  if (!dir.exists(dirname(path))) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  }
  payload <- list(
    source_git_sha = source_git_sha,
    schema_version = schema_version,
    n_clocks = n_clocks,
    external_assets = external_assets
  )
  payload <- payload[!vapply(payload, is.null, logical(1L))]
  jsonlite::write_json(
    payload,
    path = path,
    auto_unbox = TRUE,
    pretty = TRUE
  )
  invisible(path)
}

# --- resolve SoT (GitHub -> data-raw/methylCIPHER-meta) ----------------------

git_exec <- function(..., dir = NULL) {
  if (!nzchar(Sys.which("git"))) {
    stop(
      "git is not on PATH (needed to clone/fetch ",
      META_REMOTE,
      ").",
      call. = FALSE
    )
  }
  args <- c(...)
  if (!is.null(dir)) {
    args <- c("-C", dir, args)
  }
  out <- system2("git", args, stdout = TRUE, stderr = TRUE)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop(
      "git ",
      paste(args, collapse = " "),
      " failed:\n",
      paste(out, collapse = "\n"),
      call. = FALSE
    )
  }
  out
}

# Always clone/fetch from GitHub into meta_dir, then checkout a commit.
# source_git_sha = NULL means origin's default branch tip after fetch.
resolve_source <- function(source_git_sha = NULL) {
  if (!is.null(source_git_sha) && nzchar(source_git_sha) && nchar(source_git_sha) < 7L) {
    stop(
      "source_git_sha must be a full or long commit SHA, got: ",
      source_git_sha,
      call. = FALSE
    )
  }

  if (!dir.exists(dirname(meta_dir))) {
    dir.create(dirname(meta_dir), recursive = TRUE, showWarnings = FALSE)
  }

  if (!dir.exists(meta_dir)) {
    message("sync: cloning ", META_REMOTE, " -> ", meta_dir)
    git_exec("clone", "--filter=blob:none", META_REMOTE, meta_dir)
  } else {
    message("sync: fetching ", META_REMOTE, " into ", meta_dir)
    # ensure origin points at the canonical remote
    git_exec("remote", "set-url", "origin", META_REMOTE, dir = meta_dir)
    git_exec("fetch", "--all", "--tags", dir = meta_dir)
  }

  if (!is.null(source_git_sha) && nzchar(source_git_sha)) {
    message("sync: checkout ", source_git_sha)
    git_exec("checkout", "--detach", source_git_sha, dir = meta_dir)
  } else {
    # default branch tip (origin/HEAD -> e.g. origin/master)
    ref <- tryCatch(
      trimws(git_exec("symbolic-ref", "--short", "refs/remotes/origin/HEAD", dir = meta_dir)),
      error = function(e) NA_character_
    )
    if (is.na(ref) || !nzchar(ref)) {
      ref <- "origin/master"
    }
    message("sync: checkout ", ref)
    git_exec("checkout", "--detach", ref, dir = meta_dir)
  }

  path <- normalizePath(meta_dir, winslash = "/", mustWork = TRUE)
  if (!dir.exists(file.path(path, "weights"))) {
    stop(meta_dir, " has no weights/ after checkout", call. = FALSE)
  }
  if (!file.exists(file.path(path, "manifest.json"))) {
    stop(meta_dir, " has no manifest.json after checkout", call. = FALSE)
  }

  sha <- trimws(git_exec("rev-parse", "HEAD", dir = path))
  list(path = path, source_git_sha = sha)
}

# --- manifest ----------------------------------------------------------------

read_manifest <- function(repo_path) {
  path <- file.path(repo_path, "manifest.json")
  if (!file.exists(path)) {
    stop("manifest.json not found at repo root: ", path, call. = FALSE)
  }
  man <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  required_top <- c("schema_version", "source_git_sha", "clocks")
  missing_top <- setdiff(required_top, names(man))
  if (length(missing_top)) {
    stop(
      "manifest.json missing fields: ",
      paste(missing_top, collapse = ", "),
      call. = FALSE
    )
  }
  if (!is.list(man$clocks) || !length(man$clocks)) {
    stop("manifest.json clocks[] is empty or not a list", call. = FALSE)
  }
  clock_ids <- vapply(
    man$clocks,
    function(c) as.character(c$clock_id %||% NA_character_),
    character(1L)
  )
  if (anyNA(clock_ids) || any(!nzchar(clock_ids))) {
    stop("manifest clocks[] entries must each have `clock_id`", call. = FALSE)
  }
  if (anyDuplicated(clock_ids)) {
    stop("manifest clocks[] has duplicate `clock_id` values", call. = FALSE)
  }
  man$by_id <- stats::setNames(man$clocks, clock_ids)
  man$clock_ids <- clock_ids
  man
}

# --- catalog crawl -----------------------------------------------------------

# recurse weights/; discriminate clock vs group meta by basename, never depth
list_meta_files <- function(repo_path) {
  weights <- file.path(repo_path, "weights")
  if (!dir.exists(weights)) {
    stop("weights/ not found under ", repo_path, call. = FALSE)
  }
  metas <- list.files(
    weights,
    pattern = "\\.meta\\.json$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (!length(metas)) {
    stop("No *.meta.json under weights/", call. = FALSE)
  }
  basenames <- basename(metas)
  list(
    clock = metas[basenames != "_group.meta.json"],
    group = metas[basenames == "_group.meta.json"]
  )
}

# collect covariate names from recipe + top-level field + sex-keyed impute refs
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
      # object form {"Age": <coef>}
      if (!is.null(nms) && any(nzchar(nms))) {
        return(nms[nzchar(nms)])
      }
      # array form ["Age","Female"] (jsonlite simplifyVector=FALSE)
      return(as.character(unlist(x, use.names = FALSE)))
    }
    character()
  }

  covs <- flatten_names(meta$covariates)
  for (step in meta$recipe %||% list()) {
    covs <- c(covs, flatten_names(step$covariates))
    if (identical(step$op, "linear_sex")) {
      covs <- c(covs, "Female")
    }
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

# relative path from repo root (forward slashes)
rel_from_repo <- function(abs_path, repo_path) {
  abs_path <- normalizePath(abs_path, winslash = "/", mustWork = FALSE)
  repo_path <- normalizePath(repo_path, winslash = "/", mustWork = TRUE)
  if (startsWith(abs_path, repo_path)) {
    sub(paste0("^", repo_path, "/?"), "", abs_path)
  } else {
    abs_path
  }
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
    if (!nzchar(gid) || is.na(gid)) {
      stop("Group meta missing group_id: ", gp, call. = FALSE)
    }
    groups[[gid]] <- list(
      group_id = gid,
      members = unlist(gmeta$members %||% list(), use.names = FALSE),
      shared_tensors = unlist(
        gmeta$shared_tensors %||% list(),
        use.names = FALSE
      ),
      pmid = gmeta$pmid,
      notes = gmeta$notes %||% NULL,
      path = rel_from_repo(gp, repo_path)
    )
  }

  clocks <- list()
  for (mp in files$clock) {
    meta <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
    cid <- as.character(meta$clock_id %||% NA_character_)
    gid <- as.character(meta$group_id %||% NA_character_)
    if (!nzchar(cid) || is.na(cid)) {
      stop("Clock meta missing clock_id: ", mp, call. = FALSE)
    }
    if (!nzchar(gid) || is.na(gid)) {
      stop("Clock meta missing group_id: ", mp, call. = FALSE)
    }

    man_row <- manifest$by_id[[cid]]
    if (is.null(man_row)) {
      stop(
        "Clock ",
        cid,
        " present under weights/ but missing from manifest.json",
        call. = FALSE
      )
    }

    vstatus <- as.character(man_row$verification_status %||% "")
    if (!vstatus %in% VERIFICATION_STATUS) {
      warning(
        "Clock ",
        cid,
        " has unexpected verification_status=",
        vstatus,
        call. = FALSE
      )
    }

    # prefer manifest hashes; meta out_sha256 is secondary provenance
    meta_hash <- as.character(man_row$meta_hash %||% NA_character_)
    out_sha256 <- man_row$out_sha256
    if (is.null(out_sha256)) {
      out_sha256 <- meta$out_sha256 %||% NULL
    }

    wf <- as.character(meta$weights_format %||% NA_character_)
    batch_ops <- extract_batch_ops(meta)
    covs <- extract_covariates(meta)

    # default cpg_coefficient tensor: weights/{group_id}/{clock_id}.csv.gz
    default_coef <- file.path("weights", gid, paste0(cid, ".csv.gz"))
    has_default_coef <- file.exists(file.path(repo_path, default_coef))

    # lightweight fixture summary for test wiring (not scoring)
    fx <- meta$fixture
    fixture <- if (is.null(fx)) {
      NULL
    } else {
      parity <- fx$parity %||% list()
      list(
        expected = fx$expected %||% NA_character_,
        expected_sha256 = fx$expected_sha256 %||% NA_character_,
        oracle = fx$oracle %||% NA_character_,
        parity_policy = parity$policy %||% NA_character_,
        parity_metric = parity$metric %||% NA_character_
      )
    }

    clocks[[cid]] <- list(
      clock_id = cid,
      group_id = gid,
      weights_format = wf,
      computation_type = as.character(meta$computation_type %||% NA_character_),
      output_transform = as.character(meta$output_transform %||% "identity"),
      normalization = unlist(
        meta$normalization %||% list("none"),
        use.names = FALSE
      ),
      imputation_policy = as.character(meta$imputation$policy %||% NA_character_),
      imputation = meta$imputation,
      intercept = meta$intercept %||% NULL,
      n_cpgs = meta$n_cpgs %||% NULL,
      array_type = meta$array_type %||% NULL,
      units = meta$units %||% NULL,
      pmid = meta$pmid %||% NULL,
      license = meta$license %||% NULL,
      access = meta$access %||% NULL,
      covariates_required = covs,
      batch_ops = batch_ops,
      batch_dependent = length(batch_ops) > 0L,
      external_group = gid %in% EXTERNAL_GROUPS,
      recipe = meta$recipe,
      components = meta$components,
      shared = meta$shared,
      external = meta$external,
      definition = meta$definition %||% NULL,
      code_ref = meta$code_ref %||% NULL,
      covers = unlist(meta$covers %||% list(), use.names = FALSE),
      depends_on_clocks = unlist(
        meta$depends_on_clocks %||% list(),
        use.names = FALSE
      ),
      meta_hash = meta_hash,
      out_sha256 = out_sha256,
      verification_status = vstatus,
      fixture = fixture,
      meta_path = rel_from_repo(mp, repo_path),
      coef_path = if (identical(wf, "cpg_coefficient") && has_default_coef) {
        default_coef
      } else {
        NULL
      }
    )
  }

  missing_meta <- setdiff(manifest$clock_ids, names(clocks))
  if (length(missing_meta)) {
    stop(
      "manifest clocks missing meta files under weights/: ",
      paste(missing_meta, collapse = ", "),
      call. = FALSE
    )
  }

  list(
    clocks = clocks,
    groups = groups,
    source_git_sha = as.character(manifest$source_git_sha),
    schema_version = manifest$schema_version,
    n_clocks = length(clocks)
  )
}

# --- tensor IO ---------------------------------------------------------------

# read weights/*.csv.gz into a compact R object (no hashing, no scoring)
# returns: named numeric | character vector | data.frame
read_tensor_csv <- function(path) {
  if (!file.exists(path)) {
    stop("Tensor file not found: ", path, call. = FALSE)
  }
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (!nrow(df)) {
    return(df)
  }
  # single column: probe ID list
  if (ncol(df) == 1L) {
    return(as.character(df[[1L]]))
  }
  # two-column key/value (cpg,coefficient / cpg,value / component,coefficient)
  if (ncol(df) == 2L) {
    key <- as.character(df[[1L]])
    val <- df[[2L]]
    if (
      is.numeric(val) ||
        all(grepl("^[-+0-9.eE]+$", as.character(val)) | is.na(val))
    ) {
      return(stats::setNames(as.numeric(val), key))
    }
  }
  # multi-column: data.frame; first col character, rest numeric
  for (j in seq_along(df)) {
    if (j == 1L) {
      df[[j]] <- as.character(df[[j]])
    } else if (!is.numeric(df[[j]])) {
      suppressWarnings(df[[j]] <- as.numeric(df[[j]]))
    }
  }
  df
}

# all tensor / code paths referenced by a catalog clock entry
collect_file_refs <- function(entry, repo_path) {
  paths <- character()
  if (!is.null(entry$coef_path)) {
    paths <- c(paths, entry$coef_path)
  }
  for (comp in entry$components %||% list()) {
    if (!is.null(comp$file)) {
      paths <- c(paths, as.character(comp$file))
    }
  }
  for (sh in entry$shared %||% list()) {
    if (!is.null(sh$file)) {
      paths <- c(paths, as.character(sh$file))
    }
  }
  ref <- entry$imputation$ref
  if (is.character(ref) && nzchar(ref)) {
    paths <- c(paths, ref)
  } else if (is.list(ref)) {
    for (v in ref) {
      if (is.character(v) && nzchar(v)) {
        paths <- c(paths, v)
      }
    }
  }

  # re-open meta for probe_sets / code_ref flattened out of the catalog entry
  meta_abs <- resolve_repo_rel(repo_path, entry$meta_path)
  if (file.exists(meta_abs)) {
    raw <- jsonlite::fromJSON(meta_abs, simplifyVector = FALSE)
    for (ps in raw$probe_sets %||% list()) {
      if (!is.null(ps$file)) {
        paths <- c(paths, as.character(ps$file))
      }
    }
    if (
      !is.null(raw$code_ref) && grepl("\\.(csv\\.gz|csv|R|r)$", raw$code_ref)
    ) {
      paths <- c(paths, as.character(raw$code_ref))
    }
  }

  unique(paths[nzchar(paths) & !is.na(paths)])
}

# --- materialize -------------------------------------------------------------

# per-group tensor payload for a set of group_ids
build_group_bundles <- function(repo_path, catalog, group_ids) {
  bundles <- list()
  for (gid in group_ids) {
    member_ids <- names(catalog$clocks)[
      vapply(
        catalog$clocks,
        function(c) identical(c$group_id, gid),
        logical(1L)
      )
    ]
    members <- catalog$clocks[member_ids]
    rels <- character()
    for (entry in members) {
      rels <- c(rels, collect_file_refs(entry, repo_path))
    }
    gside <- catalog$groups[[gid]]
    if (!is.null(gside$shared_tensors)) {
      rels <- c(rels, gside$shared_tensors)
    }

    tensors <- list()
    for (rel in unique(rels)) {
      abs <- resolve_repo_rel(repo_path, rel)
      if (!file.exists(abs)) {
        warning("Referenced tensor missing (skipped): ", rel, call. = FALSE)
        next
      }
      if (grepl("\\.[Rr]$", rel)) {
        tensors[[rel]] <- list(
          type = "r_source",
          text = readLines(abs, warn = FALSE)
        )
      } else {
        tensors[[rel]] <- read_tensor_csv(abs)
      }
    }

    bundles[[gid]] <- list(
      group_id = gid,
      clocks = member_ids,
      tensors = tensors
    )
  }
  bundles
}

# PCClocks: shared probe set -> one coefficient matrix (double, not float32)
encode_pcclocks_matrix <- function(bundle) {
  coef_rels <- grep(
    "weights/PCClocks/PC[^/]+\\.csv\\.gz$",
    names(bundle$tensors),
    value = TRUE
  )
  if (!length(coef_rels)) {
    return(bundle)
  }

  coefs <- lapply(coef_rels, function(rel) bundle$tensors[[rel]])
  names(coefs) <- sub("\\.csv\\.gz$", "", basename(coef_rels))

  probes <- names(coefs[[1L]])
  for (nm in names(coefs)) {
    if (!identical(names(coefs[[nm]]), probes)) {
      stop(
        "PCClocks member ",
        nm,
        " probe set differs from the shared set",
        call. = FALSE
      )
    }
  }

  mat <- do.call(cbind, lapply(coefs, as.numeric))
  rownames(mat) <- probes
  colnames(mat) <- names(coefs)
  storage.mode(mat) <- "double"

  keep <- setdiff(names(bundle$tensors), coef_rels)
  bundle$tensors <- bundle$tensors[keep]
  bundle$coefficient_matrix <- mat
  bundle$encoding <- "shared_probe_matrix"
  bundle
}

build_sysdata <- function(repo_path, catalog, ship_groups) {
  message(
    "sync: building shipped bundles for ",
    length(ship_groups),
    " groups..."
  )
  bundles <- build_group_bundles(repo_path, catalog, ship_groups)

  mc_catalog <- catalog$clocks
  mc_groups <- catalog$groups
  mc_bundles <- bundles
  mc_provenance <- list(
    source_git_sha = catalog$source_git_sha,
    schema_version = catalog$schema_version,
    n_clocks = catalog$n_clocks,
    n_ship_groups = length(ship_groups),
    ship_groups = ship_groups,
    external_groups = EXTERNAL_GROUPS
  )

  # internal = TRUE -> R/sysdata.rda
  usethis::use_data(
    mc_catalog,
    mc_groups,
    mc_bundles,
    mc_provenance,
    internal = TRUE,
    overwrite = TRUE,
    compress = "xz"
  )

  path <- file.path("R", "sysdata.rda")
  sz <- file.info(path)$size
  message(sprintf("sync: wrote %s (%.1f KB)", path, sz / 1024))
  invisible(list(
    path = path,
    size_bytes = sz,
    objects = c("mc_catalog", "mc_groups", "mc_bundles", "mc_provenance")
  ))
}

build_external_assets <- function(repo_path, catalog, external_groups) {
  if (!dir.exists(asset_dir)) {
    dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)
  }
  assets <- list()

  for (gid in external_groups) {
    message("sync: building external asset for ", gid, "...")
    bundle <- build_group_bundles(repo_path, catalog, gid)[[gid]]
    if (identical(gid, "PCClocks")) {
      bundle <- encode_pcclocks_matrix(bundle)
    } else {
      bundle$encoding <- "per_tensor"
    }
    bundle$source_git_sha <- catalog$source_git_sha
    bundle$schema_version <- catalog$schema_version
    bundle$catalog <- catalog$clocks[bundle$clocks]
    bundle$group <- catalog$groups[[gid]]

    fname <- sprintf("%s-%s.qs2", tolower(gid), catalog$source_git_sha)
    fpath <- file.path(asset_dir, fname)
    qs2::qs_save(bundle, fpath)
    sz <- file.info(fpath)$size
    message(sprintf("sync: wrote %s (%.2f MB)", fpath, sz / 1e6))
    assets[[gid]] <- list(
      group_id = gid,
      path = fpath,
      file = fname,
      size_bytes = sz,
      source_git_sha = catalog$source_git_sha,
      n_clocks = length(bundle$clocks),
      encoding = bundle$encoding %||% "per_tensor"
    )
  }
  assets
}

# --- main --------------------------------------------------------------------

sync <- function(
  source_git_sha = NULL,
  force = FALSE,
  dry_run = FALSE,
  upload = FALSE
) {
  src <- resolve_source(source_git_sha = source_git_sha)
  man <- read_manifest(src$path)

  # manifest stamp is the release pin; resolved commit is secondary
  current_sha <- as.character(man$source_git_sha %||% src$source_git_sha)
  if (!nzchar(current_sha) || nchar(current_sha) < 7L) {
    stop(
      "Could not determine source_git_sha from manifest or checkout",
      call. = FALSE
    )
  }

  if (isTRUE(dry_run)) {
    files <- list_meta_files(src$path)
    message(
      "sync: would materialize @ ",
      current_sha,
      " (clock metas=",
      length(files$clock),
      ", group metas=",
      length(files$group),
      ", manifest clocks=",
      length(man$clock_ids),
      ")"
    )
    return(invisible(list(
      skipped = FALSE,
      dry_run = TRUE,
      source_git_sha = current_sha,
      n_clock_metas = length(files$clock),
      n_group_metas = length(files$group),
      n_manifest_clocks = length(man$clock_ids)
    )))
  }

  lock <- read_lockfile()
  if (
    !isTRUE(force) &&
      !is.na(lock$source_git_sha) &&
      identical(as.character(lock$source_git_sha), current_sha)
  ) {
    message("sync: lockfile SHA matches (", current_sha, ") -- skip")
    return(invisible(list(skipped = TRUE, source_git_sha = current_sha)))
  }

  message("sync: building catalog @ ", current_sha)
  catalog <- build_catalog(src$path, man)
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

  sys <- build_sysdata(src$path, catalog, ship)
  assets <- build_external_assets(src$path, catalog, external)

  # upload is local staging only for now (no silent network)
  if (isTRUE(upload)) {
    stop(
      "upload=TRUE is not configured yet. Stage assets from data-raw/assets/ ",
      "to a GitHub Release keyed by source_git_sha.",
      call. = FALSE
    )
  }
  message(
    "sync: upload skipped (local staging only). ",
    length(assets),
    " asset(s) under data-raw/assets/ for source_git_sha=",
    current_sha
  )
  uploaded <- lapply(assets, function(a) {
    a$uploaded <- FALSE
    a
  })

  write_lockfile(
    source_git_sha = current_sha,
    schema_version = catalog$schema_version,
    n_clocks = catalog$n_clocks,
    external_assets = lapply(uploaded, function(a) {
      list(
        group_id = a$group_id,
        file = a$file,
        size_bytes = a$size_bytes,
        encoding = a$encoding,
        uploaded = isTRUE(a$uploaded)
      )
    })
  )

  message("sync: done @ ", current_sha)
  invisible(list(
    skipped = FALSE,
    source_git_sha = current_sha,
    n_clocks = catalog$n_clocks,
    ship_groups = ship,
    external_groups = external,
    sysdata = sys,
    assets = uploaded,
    lockfile = lockfile_path
  ))
}

if (interactive()) {
  message(
    "sync.R loaded. Clones/fetches ", META_REMOTE, "\n",
    "  into data-raw/methylCIPHER-meta, then materializes package data.\n",
    "  sync(dry_run = TRUE)\n",
    "  sync()\n",
    "  sync(force = TRUE)\n",
    "  sync(source_git_sha = \"dc543a7b...\")"
  )
}
