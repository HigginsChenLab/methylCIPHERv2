# Vendor methylCIPHER-meta -> R package snapshot.
#
#   source("data-raw/sync.R")
#   sync()                              # fetch default tip, materialize
#   sync(dry_run = TRUE)
#   sync(force = TRUE)                  # ignore lockfile
#   sync(source_git_sha = "dc543a7b...") # pin a specific commit
#   sync(upload = TRUE)                 # also publish external qs2 to GitHub Releases
#
# Outputs:
#   R/sysdata.rda                    catalog + group sidecars + small tensor bundles
#                                    (+ mc_provenance$external_assets registry)
#   data-raw/assets/*.qs2            SystemsAge / PCClocks / PCBrainAge (content-addressed)
#   data-raw/lockfile.json           pin + manifest_key + external asset hashes
#   inst/bibliography/clocks.bib     vendored paper library (overwritten each sync)
#
# External assets are identified by rlang::hash of the stable in-memory pack (not the
# meta git SHA). Release tag on the package repo = that payload_hash.

# --- setup -------------------------------------------------------------------

for (pkg in c("jsonlite", "qs2", "usethis", "digest", "rlang")) {
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

# Canonical remote. Local cache is always data-raw/methylCIPHER-meta
META_REMOTE <- "https://github.com/hhp94/methylCIPHER-meta.git"

# External families: ship the rest. These three go to release assets due to size.
EXTERNAL_GROUPS <- c("SystemsAge", "PCClocks", "PCBrainAge")

# Bump when the in-memory pack layout changes (forces new payload_hash).
EXTERNAL_ENCODING_VERSION <- 1L

# Pin-only fields: never part of the hashed / published pack (would defeat content-addressing).
EXTERNAL_PIN_FIELDS <- c("source_git_sha", "manifest_generated_at_sha")

# Valid verification_status values from the release manifest.
VERIFICATION_STATUS <- c("", "pending", "verified", "disputed", "skipped")

# A bundle input is a whole string that is a repo-relative path under weights/.
# Anchored at both ends so prose that merely mentions a path ("coef = weights/x.csv, ...")
# never matches, and so papers/ (gitignored corpus) and scripts/ (producer tooling) are
# structurally excluded rather than excluded by a blocklist.
WEIGHTS_REF_RE <- "^weights/.+\\.(csv\\.gz|csv|[Rr])$"

# --- field registries (meta JSON -> shipped catalog) -------------------------
# Upstream weights/*.meta.json carries producer provenance (raw_source, notes, by/date,
# sha256 side-hashes, fixture parity novels, ...). The R package only needs the scoring
# contract + a thin license/fixture stub. Everything else is pruned at catalog build.
# Nested allowlists prune *inside* kept objects; unknown future top-level keys are dropped
# by FIELD_REGISTRY (allowlist), not by a drop-list that would have to grow forever.

# Top-level clock fields retained from each *.meta.json.
FIELD_REGISTRY <- c(
  # identity / dispatch
  "clock_id", "group_id", "weights_format", "computation_type",
  # citation join key (clock_id -> pmid -> inst/bibliography/clocks.bib); not user fluff
  "pmid",
  # scoring
  "output_transform", "normalization", "imputation", "intercept",
  "covariates", "recipe", "components", "shared",
  "external", "probe_sets", "code_ref", "definition",
  "depends_on_clocks", "n_cpgs_normalization",
  # user-facing (stripped to license only; n_cpgs/array_type/units/access dropped)
  "license"
)

# Package-side BibTeX library path (overwritten every successful sync).
BIB_INST_PATH <- file.path("inst", "bibliography", "clocks.bib")

# Top-level group sidecar fields retained from each _group.meta.json.
GROUP_FIELD_REGISTRY <- c(
  "group_id", "members", "shared_tensors"
)

# Nested allowlists inside kept objects.
IMPUTATION_FIELDS <- c("policy", "ref")
COMPONENT_FIELDS <- c(
  "name", "file", "row_key", "col_key", "intercept", "covariates"
)
SHARED_FIELDS <- c("name", "file")
PROBE_SET_FIELDS <- c("name", "role", "file", "n")
EXTERNAL_FIELDS <- c(
  "r_package", "github", "commit", "function", "model_key", "depends"
)
# Thin fixture stub for test wiring (not scoring). Full parity/server prose stays upstream.
FIXTURE_FIELDS <- c(
  "expected", "oracle", "parity_policy", "parity_metric"
)
# recipe steps vary by op; drop free-text only.
RECIPE_STEP_DROP <- c("note")

# Keep named fields; preserves explicit JSON nulls (e.g. imputation$ref = null).
# Use out[f] <- list(...) rather than out[[f]] <- NULL, which *drops* the name.
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
  if (!length(out)) {
    return(NULL)
  }
  out
}

# list-of-objects (components, shared, probe_sets)
keep_fields_each <- function(xs, fields) {
  if (is.null(xs)) {
    return(NULL)
  }
  if (!is.list(xs)) {
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

# thin fixture: hoist parity.policy/metric; drop server_*, dates, notes, hashes.
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
  # drop pure-nulls so external_package (no expected) stays small
  stub <- stub[!vapply(stub, is.null, logical(1L))]
  if (!length(stub)) {
    return(NULL)
  }
  stub
}

# Prune one raw clock meta to the shipped scoring contract.
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
  # covariates kept raw (name list OR coef map); no nested prune
  out
}

prune_group_meta <- function(gmeta) {
  keep_fields(gmeta, GROUP_FIELD_REGISTRY) %||% list()
}

# --- bibliography (join at build; library file under inst/) ------------------
# SoT: methylCIPHER-meta/bibliography/. Integrity is enforced upstream
# (validate_bibliography.py); this package only vendors clocks.bib and joins
# pmid -> bib_key from papers.csv in memory. papers.csv is never exported.

read_papers_csv <- function(repo_path) {
  path <- file.path(repo_path, "bibliography", "papers.csv")
  if (!file.exists(path)) {
    stop("bibliography/papers.csv not found under ", repo_path, call. = FALSE)
  }
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  need <- c("pmid", "bib_key")
  missing <- setdiff(need, names(df))
  if (length(missing)) {
    stop(
      "bibliography/papers.csv missing columns: ",
      paste(missing, collapse = ", "),
      call. = FALSE
    )
  }
  df$pmid <- trimws(df$pmid)
  df$bib_key <- trimws(df$bib_key)
  if (any(!nzchar(df$pmid)) || anyDuplicated(df$pmid)) {
    stop("bibliography/papers.csv: pmid must be unique non-empty", call. = FALSE)
  }
  if (any(!nzchar(df$bib_key))) {
    stop("bibliography/papers.csv: bib_key must be non-empty for every row", call. = FALSE)
  }
  list(
    bib_key = stats::setNames(df$bib_key, df$pmid),
    n = nrow(df)
  )
}

# Overwrite inst/bibliography/clocks.bib from the resolved meta snapshot.
# Git tracks the package-side pin; no lockfile hash for bib (SoT owns integrity).
vendor_bibliography <- function(repo_path) {
  src <- file.path(repo_path, "bibliography", "clocks.bib")
  if (!file.exists(src)) {
    stop("bibliography/clocks.bib not found under ", repo_path, call. = FALSE)
  }
  dest_dir <- dirname(BIB_INST_PATH)
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  }
  ok <- file.copy(src, BIB_INST_PATH, overwrite = TRUE)
  if (!isTRUE(ok)) {
    stop("Failed to copy ", src, " -> ", BIB_INST_PATH, call. = FALSE)
  }
  sz <- file.info(BIB_INST_PATH)$size
  message(sprintf("sync: wrote %s (%.1f KB)", BIB_INST_PATH, sz / 1024))
  invisible(list(path = BIB_INST_PATH, size_bytes = sz))
}

# --- lockfile ----------------------------------------------------------------

read_lockfile <- function(path = lockfile_path) {
  empty <- list(source_git_sha = NA_character_, manifest_key = NA_character_)
  if (!file.exists(path)) {
    return(empty)
  }
  lock <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  if (is.null(lock$source_git_sha) || !nzchar(lock$source_git_sha)) {
    stop("Lockfile exists but source_git_sha is missing: ", path, call. = FALSE)
  }
  # Lockfiles written before the manifest_key scheme cannot answer the skip question;
  # treat them as unknown rather than guessing from the old SHA-compare semantics.
  if (is.null(lock$manifest_key) || !nzchar(lock$manifest_key)) {
    message("sync: lockfile predates manifest_key -- treating as out of date")
    lock$manifest_key <- NA_character_
  }
  lock
}

write_lockfile <- function(
  source_git_sha,
  manifest_key,
  manifest_generated_at_sha = NULL,
  schema_version = NULL,
  external_assets = NULL,
  n_clocks = NULL,
  path = lockfile_path
) {
  if (!dir.exists(dirname(path))) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  }
  payload <- list(
    # the commit we actually read and bundled -- the consumer pin
    source_git_sha = source_git_sha,
    # skip key: sha256 over schema_version + clocks[] (release.py `_substantive`)
    manifest_key = manifest_key,
    # provenance only: manifest.json's own stamp, which lags one commit by design
    manifest_generated_at_sha = manifest_generated_at_sha,
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
  # stderr goes to its own sink: git writes progress/hints there even on success, and
  # folding it into stdout would make it indistinguishable from the value we asked for.
  err_file <- tempfile("git-stderr-")
  on.exit(unlink(err_file), add = TRUE)
  out <- system2("git", args, stdout = TRUE, stderr = err_file)
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop(
      "git ",
      paste(args, collapse = " "),
      " failed:\n",
      paste(readLines(err_file, warn = FALSE), collapse = "\n"),
      call. = FALSE
    )
  }
  out
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
      git_value("symbolic-ref", "--short", "refs/remotes/origin/HEAD", dir = meta_dir),
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

  sha <- git_value("rev-parse", "HEAD", dir = path)
  if (!grepl("^[0-9a-f]{40}$", sha)) {
    stop("git rev-parse HEAD did not return a full commit sha: ", sha, call. = FALSE)
  }
  list(path = path, source_git_sha = sha)
}

# Fixture cohort DuckDB (gitignored, regenerable). Self-contained: tables `beta` + `pheno`.
# Not a sync bundle input -- local testthat reads it under the meta clone. Warn when missing.
# See migration-plan "Fixture cohort" and meta fixtures/build_cohort.R.
warn_if_missing_fixture_duckdb <- function(repo_path) {
  duckdb_rel <- file.path("fixtures", "cohort_EPIC", "beta.duckdb")
  duckdb_abs <- file.path(repo_path, duckdb_rel)
  if (file.exists(duckdb_abs)) {
    return(invisible(TRUE))
  }
  # Paths relative to package root (sync is run from there via source("data-raw/sync.R")).
  meta_fixtures <- file.path("data-raw", "methylCIPHER-meta", "fixtures")
  cohort_dir <- file.path(meta_fixtures, "cohort_EPIC")
  warning(
    "Fixture cohort DuckDB not found at ",
    file.path("data-raw", "methylCIPHER-meta", duckdb_rel),
    " (gitignored; regenerable; embeds beta + pheno).\n",
    "  Generate it:\n",
    "    cd ", meta_fixtures, "\n",
    "    Rscript build_cohort.R\n",
    "  Or copy an existing beta.duckdb into ", cohort_dir, ".",
    call. = FALSE
  )
  invisible(FALSE)
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

# Skip key over the manifest's substantive part -- the mirror of release.py `_substantive`,
# which is {schema_version, clocks} and deliberately excludes source_git_sha. Sorted so the
# key depends on content, not on the order release.py happened to emit.
manifest_key <- function(man) {
  rows <- vapply(
    man$clocks,
    function(c) {
      paste(
        as.character(c$clock_id %||% ""),
        as.character(c$meta_hash %||% ""),
        as.character(c$out_sha256 %||% ""),
        as.character(c$verification_status %||% ""),
        sep = "\x1f"
      )
    },
    character(1L)
  )
  payload <- paste(
    c(paste0("schema_version=", man$schema_version), sort(rows)),
    collapse = "\x1e"
  )
  digest::digest(payload, algo = "sha256", serialize = FALSE)
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

  # any key ending in "covariates": plain `covariates` plus the sex-stratified
  # `female_covariates` / `male_covariates` that linear_sex steps carry instead.
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

  # sex_params.{female,male}.covariates restates the same terms outside the recipe
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
    entry <- prune_group_meta(gmeta)
    # members / shared_tensors arrive as JSON arrays; normalize to character
    if (!is.null(entry$members)) {
      entry$members <- unlist(entry$members, use.names = FALSE)
    }
    if (!is.null(entry$shared_tensors)) {
      entry$shared_tensors <- unlist(entry$shared_tensors, use.names = FALSE)
    }
    # packaging path (not in upstream meta; needed for debugging)
    entry$path <- rel_from_repo(gp, repo_path)
    groups[[gid]] <- entry
  }

  # papers.csv is read in-memory only: join pmid -> bib_key onto catalog entries.
  # It is never written into sysdata / inst / lockfile (clocks.bib is the shipped library).
  papers <- read_papers_csv(repo_path)

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

    # meta_hash is sha256 over the raw bytes of this meta (release.py). Verifying it is
    # not tensor rehashing -- it is the cheap check that manifest.json actually describes
    # the tree we checked out. Upstream's release.py --check is producer-side; without
    # this, a weights/ commit that skipped release.py would bundle silently against a
    # stale manifest, and out_sha256 inside each meta means this covers tensors too.
    actual_meta_hash <- digest::digest(file = mp, algo = "sha256")
    declared_meta_hash <- as.character(man_row$meta_hash %||% NA_character_)
    if (!is.na(declared_meta_hash) && !identical(actual_meta_hash, declared_meta_hash)) {
      stop(
        "manifest.json is stale for clock ",
        cid,
        ":\n  manifest meta_hash = ",
        declared_meta_hash,
        "\n  actual meta_hash   = ",
        actual_meta_hash,
        "\nRe-run `uv run python scripts/release.py` upstream and commit the manifest.",
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

    # derive from the *full* upstream meta before pruning
    wf <- as.character(meta$weights_format %||% NA_character_)
    batch_ops <- extract_batch_ops(meta)
    covs <- extract_covariates(meta)

    # default cpg_coefficient tensor: weights/{group_id}/{clock_id}.csv.gz
    default_coef <- file.path("weights", gid, paste0(cid, ".csv.gz"))
    has_default_coef <- file.exists(file.path(repo_path, default_coef))

    # scoring contract from FIELD_REGISTRY (+ nested allowlists)
    entry <- prune_clock_meta(meta)

    # normalize a few shapes for R consumers
    if (!is.null(entry$normalization)) {
      entry$normalization <- unlist(entry$normalization, use.names = FALSE)
    }
    if (!is.null(entry$output_transform)) {
      entry$output_transform <- as.character(entry$output_transform)
    } else {
      entry$output_transform <- "identity"
    }
    if (!is.null(entry$computation_type)) {
      entry$computation_type <- as.character(entry$computation_type)
    }
    if (!is.null(entry$depends_on_clocks)) {
      entry$depends_on_clocks <- unlist(entry$depends_on_clocks, use.names = FALSE)
    }
    # pmid is the citation join key; normalize JSON number -> character digits
    if (!is.null(entry$pmid)) {
      entry$pmid <- as.character(entry$pmid)
    } else {
      stop("Clock ", cid, " missing pmid after prune", call. = FALSE)
    }
    bk <- unname(papers$bib_key[entry$pmid])
    if (length(bk) != 1L || is.na(bk) || !nzchar(bk)) {
      stop(
        "Clock ",
        cid,
        " pmid=",
        entry$pmid,
        " has no row in bibliography/papers.csv",
        call. = FALSE
      )
    }
    # derived join result (not in FIELD_REGISTRY); papers.csv itself is not shipped
    entry$bib_key <- bk

    # packaging / derived fields (not in FIELD_REGISTRY; added after prune)
    entry$imputation_policy <- as.character(
      entry$imputation$policy %||% meta$imputation$policy %||% NA_character_
    )
    entry$covariates_required <- covs
    entry$batch_ops <- batch_ops
    entry$batch_dependent <- length(batch_ops) > 0L
    entry$external_group <- gid %in% EXTERNAL_GROUPS
    entry$meta_hash <- meta_hash
    entry$out_sha256 <- out_sha256
    entry$verification_status <- vstatus
    entry$fixture <- prune_fixture(meta$fixture)
    entry$meta_path <- rel_from_repo(mp, repo_path)
    entry$coef_path <- if (identical(wf, "cpg_coefficient") && has_default_coef) {
      default_coef
    } else {
      NULL
    }

    clocks[[cid]] <- entry
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
    # left NA here on purpose: only sync() knows the commit we resolved, and
    # manifest$source_git_sha is the parent stamp, not the identity of this tree.
    source_git_sha = NA_character_,
    schema_version = manifest$schema_version,
    n_clocks = length(clocks)
  )
}

# --- tensor IO ---------------------------------------------------------------

# read weights/*.csv.gz into a compact R object (no hashing, no scoring)
# returns: named numeric | character vector | data.frame
#
# read.csv(stringsAsFactors = FALSE) already types each column from its own contents, and
# that typing is authoritative. Do NOT re-coerce by column position: tables like
# DNAmFitAge/kdm_params.csv.gz (sex,component,weight,center,scale) carry a character key in
# column 2, and coercing "rest of the columns" to numeric silently NAs it away.
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
  # two-column key/value (cpg,coefficient / cpg,value / component,coefficient); only when
  # the value column really is numeric -- a character second column means this is a lookup
  # table (cpg,module), which stays a data.frame with its types intact.
  if (ncol(df) == 2L && is.numeric(df[[2L]])) {
    key <- as.character(df[[1L]])
    if (anyDuplicated(key)) {
      stop(
        "Duplicate keys in ",
        path,
        " -- a named vector would silently collapse them",
        call. = FALSE
      )
    }
    return(stats::setNames(df[[2L]], key))
  }
  df
}

# every weights/ path a meta references, wherever it sits in the JSON.
#
# Whitelisting parent keys (components[].file, shared[].file, ...) misses any container the
# schema grows later -- CellDRIFT's top-level module_membership.file was already invisible
# that way. Walk the whole document instead and keep whatever *is* a weights/ path, so
# discovery is driven by the value's shape rather than by a list we have to maintain.
# WEIGHTS_REF_RE anchors both ends, so papers/ (gitignored corpus), scripts/ (producer
# tooling) and prose that merely mentions a path are all excluded structurally.
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

# all tensor / code paths referenced by a catalog clock entry
collect_file_refs <- function(entry, repo_path) {
  meta_abs <- resolve_repo_rel(repo_path, entry$meta_path)
  if (!file.exists(meta_abs)) {
    stop("Clock meta vanished: ", entry$meta_path, call. = FALSE)
  }
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
      # every shared_tensors entry upstream is already a weights/ path; the anchor is
      # applied for consistency with clock-level refs, not to fix a known offender.
      rels <- c(rels, collect_weights_refs(gside$shared_tensors))
    }

    tensors <- list()
    for (rel in unique(rels)) {
      abs <- resolve_repo_rel(repo_path, rel)
      if (!file.exists(abs)) {
        # every weights/ ref in the SoT resolves; a miss means the snapshot is broken, and
        # warning-and-skipping would ship a clock with no weights and still write a
        # lockfile that makes the next run skip the rebuild.
        stop(
          "Referenced tensor missing from snapshot: ",
          rel,
          " (group ",
          gid,
          ")",
          call. = FALSE
        )
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

# External assets: one probe-order carrier per group ($cpgs), cpg-aligned values as
# matrices / doubles with NO names. Rownames are NOT put on matrices -- that would
# re-duplicate names if more than one matrix shares the order (SystemsAge).
#
#   PCClocks:
#     cpgs, coefficient_matrix [n x k] (colnames = clock ids), impute [n]
#   SystemsAge:
#     cpgs, organs [n x 11], systems [n x 11], age [n], impute [n],
#     tensors = leftover small systems_pca/*
#   PCBrainAge:
#     cpgs, coefficient_matrix [n x 1], impute [n]
#
# qs_save uses low compress_level for load speed; memoise at runtime for re-use.

# named numeric -> double[n] in cpgs order (errors if probe set differs)
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
  # deliberately no rownames -- $cpgs is the sole name carrier
  mat
}

# Resolve the single probe order for a bundle: prefer explicit CpGs list, else first big named vec.
resolve_cpgs <- function(tensors, group_id) {
  is_named_num <- vapply(
    tensors,
    function(x) {
      is.numeric(x) && !is.null(names(x)) && length(x) > 0L && is.null(dim(x))
    },
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

  coef_rels <- grep(
    "^weights/PCClocks/PC[^/]+\\.csv\\.gz$",
    names(tensors),
    value = TRUE
  )
  if (!length(coef_rels)) {
    stop(gid, ": no PC*.csv.gz coefficient tensors found", call. = FALSE)
  }
  # stable column order: basename without extension
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
  "Blood", "Brain", "Heart", "Hormone", "Immune", "Inflammation",
  "Kidney", "Liver", "Lung", "Metabolic", "MusculoSkeletal"
)

encode_systemsage <- function(bundle) {
  tensors <- bundle$tensors
  gid <- "SystemsAge"
  resolved <- resolve_cpgs(tensors, gid)
  cpgs <- resolved$cpgs

  organ_rels <- file.path("weights", "SystemsAge", paste0(SYSTEMSAGE_ORGANS, ".csv.gz"))
  system_rels <- file.path(
    "weights", "SystemsAge", "systems", paste0(SYSTEMSAGE_ORGANS, ".csv.gz")
  )
  # normalize separators
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

  used <- c(
    organ_rels, system_rels, age_rel, impute_rel, cpgs_rel, resolved$drop_lists
  )
  bundle$cpgs <- cpgs
  bundle$organs <- cbind_aligned(tensors, organ_rels, cpgs, SYSTEMSAGE_ORGANS)
  bundle$systems <- cbind_aligned(tensors, system_rels, cpgs, SYSTEMSAGE_ORGANS)
  bundle$age <- align_double(tensors[[age_rel]], cpgs, age_rel)
  bundle$impute <- align_double(tensors[[impute_rel]], cpgs, impute_rel)
  # small PCA tensors stay under tensors/
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
  # 1-column matrix: same as a vector plus dim; colnames keep the clock id
  bundle$coefficient_matrix <- cbind_aligned(
    tensors, coef_rel, cpgs, "PCBrainAge"
  )
  bundle$impute <- align_double(tensors[[impute_rel]], cpgs, impute_rel)
  bundle$tensors <- residual_tensors(tensors, used)
  bundle$encoding <- "canonical_matrices"
  bundle
}

encode_external_asset <- function(bundle) {
  gid <- bundle$group_id %||% NA_character_
  # JSON paths use /; file.path on Windows may inject \ -- normalize once
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

# Runtime-facing registry row (also embedded in mc_provenance). No upload state.
external_asset_registry_row <- function(a) {
  list(
    group_id = a$group_id,
    payload_hash = a$payload_hash,
    release_tag = a$release_tag %||% a$payload_hash,
    file = a$file,
    file_sha256 = a$file_sha256,
    size_bytes = a$size_bytes,
    encoding = a$encoding,
    encoding_version = a$encoding_version,
    n_clocks = a$n_clocks,
    n_cpgs = a$n_cpgs
  )
}

# Maintainer lockfile row (same identity fields; pin is package-level).
external_asset_lock_row <- function(a) {
  external_asset_registry_row(a)
}

build_sysdata <- function(repo_path, catalog, ship_groups, external_assets = NULL) {
  message(
    "sync: building shipped bundles for ",
    length(ship_groups),
    " groups..."
  )
  bundles <- build_group_bundles(repo_path, catalog, ship_groups)

  mc_catalog <- catalog$clocks
  mc_groups <- catalog$groups
  mc_bundles <- bundles
  ext_reg <- NULL
  if (!is.null(external_assets) && length(external_assets)) {
    ext_reg <- lapply(external_assets, external_asset_registry_row)
  }
  mc_provenance <- list(
    # identity of the tree these bytes came from
    source_git_sha = catalog$source_git_sha,
    # manifest.json's own stamp (parent commit) -- provenance, never an identity
    manifest_generated_at_sha = catalog$manifest_generated_at_sha,
    manifest_key = catalog$manifest_key,
    schema_version = catalog$schema_version,
    n_clocks = catalog$n_clocks,
    n_ship_groups = length(ship_groups),
    ship_groups = ship_groups,
    external_groups = EXTERNAL_GROUPS,
    # expected payload_hash / file_sha256 for download + integrity (runtime)
    external_assets = ext_reg
  )

  # internal = TRUE -> R/sysdata.rda
  usethis::use_data(
    mc_catalog,
    mc_groups,
    mc_bundles,
    mc_provenance,
    internal = TRUE,
    overwrite = TRUE
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

# Low ZSTD level + no shuffle: prioritize decompress/load speed over size.
# Matrix packing + single $cpgs already removes most bulk; memoise at runtime.
QS2_COMPRESS_LEVEL <- 1L
QS2_SHUFFLE <- FALSE

# Canonical in-memory pack for hash + qs_save. Includes catalog (intercepts, out_sha256,
# …) so scoring contract and tensors move together. Excludes pin-only fields so a new
# meta checkout with identical packs does not force a new release.
stable_external_payload <- function(bundle) {
  for (f in EXTERNAL_PIN_FIELDS) {
    bundle[[f]] <- NULL
  }

  tensors <- bundle$tensors %||% list()
  if (length(tensors) && !is.null(names(tensors))) {
    tensors <- tensors[sort(names(tensors))]
  }

  catalog <- bundle$catalog %||% list()
  if (length(catalog) && !is.null(names(catalog))) {
    catalog <- catalog[sort(names(catalog))]
  }

  clocks <- as.character(bundle$clocks %||% character())
  if (length(clocks)) {
    clocks <- sort(unique(clocks))
  }

  # Fixed field order; drop pure-nulls so PC* and SystemsAge share one schema.
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
  out <- out[!vapply(out, is.null, logical(1L))]
  out
}

payload_hash_of <- function(payload) {
  rlang::hash(payload)
}

file_sha256_of <- function(path) {
  digest::digest(file = path, algo = "sha256")
}

# --- package GitHub remote (release target) ----------------------------------

# Parse owner/repo from a git remote URL (https or ssh).
parse_github_owner_repo <- function(url) {
  url <- trimws(as.character(url %||% ""))
  if (!nzchar(url)) {
    return(NULL)
  }
  url <- sub("\\.git$", "", url)
  # https://github.com/owner/repo or git@github.com:owner/repo
  m <- regexec(
    "(?:github\\.com[:/])([^/]+)/([^/]+)$",
    url,
    perl = TRUE
  )
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
  url <- tryCatch(
    git_value("remote", "get-url", "origin"),
    error = function(e) NA_character_
  )
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
  br <- tryCatch(
    git_value("rev-parse", "--abbrev-ref", "HEAD"),
    error = function(e) NA_character_
  )
  if (is.na(br) || !nzchar(br) || identical(br, "HEAD")) {
    return(git_value("rev-parse", "HEAD"))
  }
  br
}

github_token <- function() {
  tok <- Sys.getenv("GH_TOKEN", unset = "")
  if (!nzchar(tok)) {
    tok <- Sys.getenv("GITHUB_TOKEN", unset = "")
  }
  tok
}

# Prefer gh CLI; fall back to curl + GitHub REST API.
gh_cli_available <- function() {
  nzchar(Sys.which("gh"))
}

curl_cli <- function() {
  w <- Sys.which("curl")
  if (!nzchar(w)) {
    stop("Neither 'gh' nor 'curl' is on PATH; cannot upload release assets.", call. = FALSE)
  }
  w
}

# GET GitHub API JSON; returns parsed list or NULL on 404.
github_api_get <- function(path, token) {
  if (gh_cli_available()) {
    args <- c("api", path, "-H", "Accept: application/vnd.github+json")
    err_file <- tempfile("gh-api-")
    on.exit(unlink(err_file), add = TRUE)
    out <- system2("gh", args, stdout = TRUE, stderr = err_file)
    status <- attr(out, "status")
    if (!is.null(status) && status != 0L) {
      err <- paste(readLines(err_file, warn = FALSE), collapse = "\n")
      if (grepl("404|Not Found", err, ignore.case = TRUE)) {
        return(NULL)
      }
      stop("gh api ", path, " failed:\n", err, call. = FALSE)
    }
    return(jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE))
  }

  url <- paste0("https://api.github.com", path)
  hdr_file <- tempfile("curl-hdr-")
  body_file <- tempfile("curl-body-")
  on.exit(unlink(c(hdr_file, body_file)), add = TRUE)
  args <- c(
    "-sS", "-D", hdr_file, "-o", body_file,
    "-H", "Accept: application/vnd.github+json"
  )
  if (nzchar(token)) {
    args <- c(args, "-H", paste0("Authorization: Bearer ", token))
  }
  args <- c(args, url)
  status <- system2(curl_cli(), args)
  if (!is.null(attr(status, "status"))) {
    status <- attr(status, "status")
  }
  hdr <- paste(readLines(hdr_file, warn = FALSE), collapse = "\n")
  body <- paste(readLines(body_file, warn = FALSE), collapse = "\n")
  code <- sub("(?s).*HTTP/[0-9.]+\\s+([0-9]+).*", "\\1", hdr, perl = TRUE)
  if (!grepl("^[0-9]+$", code)) {
    code <- if (is.numeric(status) && status != 0) "000" else "200"
  }
  if (identical(code, "404")) {
    return(NULL)
  }
  if (!identical(code, "200") && !identical(code, "201")) {
    stop("GitHub API GET ", path, " failed (HTTP ", code, "):\n", body, call. = FALSE)
  }
  jsonlite::fromJSON(body, simplifyVector = FALSE)
}

github_api_post_json <- function(path, payload, token) {
  body_json <- jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null")
  in_file <- tempfile("gh-body-", fileext = ".json")
  on.exit(unlink(in_file), add = TRUE)
  writeLines(body_json, in_file, useBytes = TRUE)

  if (gh_cli_available()) {
    err_file <- tempfile("gh-post-")
    on.exit(unlink(err_file), add = TRUE)
    args <- c(
      "api", "--method", "POST", path,
      "-H", "Accept: application/vnd.github+json",
      "-H", "Content-Type: application/json",
      "--input", in_file
    )
    out <- system2("gh", args, stdout = TRUE, stderr = err_file)
    status <- attr(out, "status")
    if (!is.null(status) && status != 0L) {
      stop(
        "gh api POST ", path, " failed:\n",
        paste(readLines(err_file, warn = FALSE), collapse = "\n"),
        call. = FALSE
      )
    }
    return(jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE))
  }

  if (!nzchar(token)) {
    stop(
      "GITHUB_TOKEN or GH_TOKEN required for release upload when 'gh' is not installed.",
      call. = FALSE
    )
  }
  out_file <- tempfile("curl-out-")
  on.exit(unlink(out_file), add = TRUE)
  args <- c(
    "-sS", "-o", out_file, "-w", "%{http_code}",
    "-X", "POST",
    "-H", "Accept: application/vnd.github+json",
    "-H", paste0("Authorization: Bearer ", token),
    "-H", "Content-Type: application/json",
    "--data-binary", paste0("@", in_file),
    paste0("https://api.github.com", path)
  )
  code <- system2(curl_cli(), args, stdout = TRUE)
  body <- paste(readLines(out_file, warn = FALSE), collapse = "\n")
  if (!code %in% c("200", "201")) {
    stop("GitHub API POST ", path, " failed (HTTP ", code, "):\n", body, call. = FALSE)
  }
  jsonlite::fromJSON(body, simplifyVector = FALSE)
}

github_release_by_tag <- function(slug, tag, token) {
  github_api_get(paste0("/repos/", slug, "/releases/tags/", utils::URLencode(tag, reserved = TRUE)), token)
}

github_create_release <- function(slug, tag, target_commitish, name, body, token) {
  github_api_post_json(
    paste0("/repos/", slug, "/releases"),
    list(
      tag_name = tag,
      target_commitish = target_commitish,
      name = name,
      body = body,
      draft = FALSE,
      prerelease = FALSE
    ),
    token
  )
}

github_upload_release_asset <- function(slug, release, file_path, asset_name, token) {
  if (!file.exists(file_path)) {
    stop("Cannot upload missing file: ", file_path, call. = FALSE)
  }
  # Skip if an asset with this name already exists on the release.
  assets <- release$assets %||% list()
  existing_names <- vapply(
    assets,
    function(a) as.character(a$name %||% ""),
    character(1L)
  )
  if (asset_name %in% existing_names) {
    message("sync: release asset already present: ", asset_name, " (tag ", release$tag_name %||% "?", ")")
    return(invisible(TRUE))
  }

  if (gh_cli_available()) {
    # gh release upload TAG FILE --repo slug --clobber
    tag <- as.character(release$tag_name %||% "")
    args <- c(
      "release", "upload", tag, file_path,
      "--repo", slug,
      "--clobber"
    )
    err_file <- tempfile("gh-up-")
    on.exit(unlink(err_file), add = TRUE)
    out <- system2("gh", args, stdout = TRUE, stderr = err_file)
    status <- attr(out, "status")
    if (!is.null(status) && status != 0L) {
      stop(
        "gh release upload failed:\n",
        paste(readLines(err_file, warn = FALSE), collapse = "\n"),
        call. = FALSE
      )
    }
    return(invisible(TRUE))
  }

  if (!nzchar(token)) {
    stop("GITHUB_TOKEN or GH_TOKEN required for asset upload without 'gh'.", call. = FALSE)
  }
  upload_url <- as.character(release$upload_url %||% "")
  if (!nzchar(upload_url)) {
    stop("Release response missing upload_url", call. = FALSE)
  }
  # upload_url is like https://uploads.github.com/.../assets{?name,label}
  base <- sub("\\{.*$", "", upload_url)
  url <- paste0(base, "?name=", utils::URLencode(asset_name, reserved = TRUE))
  out_file <- tempfile("curl-up-")
  on.exit(unlink(out_file), add = TRUE)
  args <- c(
    "-sS", "-o", out_file, "-w", "%{http_code}",
    "-X", "POST",
    "-H", "Accept: application/vnd.github+json",
    "-H", paste0("Authorization: Bearer ", token),
    "-H", "Content-Type: application/octet-stream",
    "--data-binary", paste0("@", normalizePath(file_path, winslash = "/", mustWork = TRUE)),
    url
  )
  code <- system2(curl_cli(), args, stdout = TRUE)
  body <- paste(readLines(out_file, warn = FALSE), collapse = "\n")
  if (!code %in% c("200", "201")) {
    stop(
      "GitHub asset upload failed for ", asset_name, " (HTTP ", code, "):\n", body,
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Publish one content-addressed asset. Tag = payload_hash (stable identity).
upload_one_external_asset <- function(a, repo, target_commitish, token) {
  tag <- as.character(a$payload_hash %||% "")
  if (!nzchar(tag)) {
    stop("Asset missing payload_hash: ", a$group_id %||% "?", call. = FALSE)
  }
  fpath <- a$path %||% file.path(asset_dir, a$file)
  if (!file.exists(fpath)) {
    stop(
      "Staged asset missing for ", a$group_id, ": ", fpath,
      "\nRe-run sync() to rebuild before upload.",
      call. = FALSE
    )
  }
  # Verify staged file still matches lock/registry checksum when present.
  if (!is.null(a$file_sha256) && nzchar(a$file_sha256)) {
    actual <- file_sha256_of(fpath)
    if (!identical(actual, a$file_sha256)) {
      stop(
        "Staged file sha256 mismatch for ", a$group_id, ":\n  expected ", a$file_sha256,
        "\n  actual   ", actual,
        call. = FALSE
      )
    }
  }

  slug <- repo$slug
  rel <- github_release_by_tag(slug, tag, token)
  if (is.null(rel)) {
    message("sync: creating GitHub release tag ", tag, " on ", slug, " @ ", target_commitish)
    rel <- github_create_release(
      slug = slug,
      tag = tag,
      target_commitish = target_commitish,
      name = sprintf("methylCIPHER external asset %s", a$group_id %||% tag),
      body = paste0(
        "Content-addressed external clock pack.\n\n",
        "- group_id: `", a$group_id %||% "", "`\n",
        "- payload_hash (rlang::hash): `", tag, "`\n",
        "- file_sha256: `", a$file_sha256 %||% "", "`\n",
        "- encoding: `", a$encoding %||% "", "` v", a$encoding_version %||% "", "\n",
        "\nRuntime resolves by payload_hash; package pin (source_git_sha) is separate.\n"
      ),
      token = token
    )
  } else {
    message("sync: release tag ", tag, " already exists on ", slug)
  }
  github_upload_release_asset(slug, rel, fpath, a$file, token)
  message("sync: uploaded ", a$file, " -> ", slug, " @ tag ", tag)
  invisible(TRUE)
}

upload_external_assets <- function(assets) {
  if (!length(assets)) {
    message("sync: no external assets to upload")
    return(invisible(list()))
  }
  repo <- package_release_repo()
  target <- package_release_target_commitish()
  token <- github_token()
  if (!gh_cli_available() && !nzchar(token)) {
    stop(
      "upload=TRUE needs the GitHub CLI (`gh`) or GITHUB_TOKEN/GH_TOKEN for API upload.",
      call. = FALSE
    )
  }
  message(
    "sync: uploading ", length(assets), " external asset(s) to ", repo$slug,
    " (target_commitish=", target, ")"
  )
  for (a in assets) {
    upload_one_external_asset(a, repo, target, token)
  }
  invisible(assets)
}

# Normalize lockfile external_assets (JSON object or data.frame) to named list of lists.
lockfile_external_assets_list <- function(lock) {
  a <- lock$external_assets
  if (is.null(a)) {
    return(list())
  }
  if (is.data.frame(a)) {
    # fromJSON simplifyVector=TRUE can give a data.frame
    out <- list()
    nms <- a$group_id
    for (i in seq_len(nrow(a))) {
      row <- lapply(a, function(col) col[[i]])
      gid <- as.character(row$group_id %||% nms[[i]] %||% paste0("row", i))
      row$path <- file.path(asset_dir, as.character(row$file %||% ""))
      out[[gid]] <- row
    }
    return(out)
  }
  if (!is.list(a)) {
    return(list())
  }
  # already list of lists; ensure names + path
  if (!is.null(names(a)) && all(nzchar(names(a)))) {
    out <- a
  } else {
    out <- list()
    for (item in a) {
      gid <- as.character(item$group_id %||% NA_character_)
      if (nzchar(gid) && !is.na(gid)) {
        out[[gid]] <- item
      }
    }
  }
  for (gid in names(out)) {
    if (is.null(out[[gid]]$path) || !nzchar(out[[gid]]$path %||% "")) {
      out[[gid]]$path <- file.path(asset_dir, as.character(out[[gid]]$file %||% ""))
    }
  }
  out
}

build_external_assets <- function(repo_path, catalog, external_groups, prior_assets = NULL) {
  if (!dir.exists(asset_dir)) {
    dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)
  }
  assets <- list()
  prior <- prior_assets %||% list()

  for (gid in external_groups) {
    message("sync: building external asset for ", gid, "...")
    bundle <- build_group_bundles(repo_path, catalog, gid)[[gid]]
    bundle <- encode_external_asset(bundle)
    bundle$schema_version <- catalog$schema_version
    bundle$encoding_version <- EXTERNAL_ENCODING_VERSION
    bundle$catalog <- catalog$clocks[bundle$clocks]
    bundle$group <- catalog$groups[[gid]]
    # Pin fields intentionally omitted from pack (see stable_external_payload).

    payload <- stable_external_payload(bundle)
    phash <- payload_hash_of(payload)
    fname <- sprintf("%s-%s.qs2", tolower(gid), phash)
    fpath <- file.path(asset_dir, fname)

    reuse <- FALSE
    prev <- prior[[gid]]
    if (
      !is.null(prev) &&
        identical(as.character(prev$payload_hash %||% ""), phash) &&
        file.exists(fpath)
    ) {
      actual_sha <- file_sha256_of(fpath)
      if (identical(as.character(prev$file_sha256 %||% ""), actual_sha)) {
        reuse <- TRUE
        message(
          "sync: ", gid, " payload_hash unchanged (", phash, ") -- reusing staged ", fname
        )
      }
    }

    if (!reuse) {
      qs2::qs_save(
        payload,
        fpath,
        compress_level = QS2_COMPRESS_LEVEL,
        shuffle = QS2_SHUFFLE
      )
    }

    sz <- file.info(fpath)$size
    fsha <- file_sha256_of(fpath)
    n_cpgs <- length(payload$cpgs %||% character())
    shape_bits <- character()
    if (!is.null(payload$coefficient_matrix)) {
      shape_bits <- c(
        shape_bits,
        sprintf("coef=%s", paste(dim(payload$coefficient_matrix), collapse = "x"))
      )
    }
    if (!is.null(payload$organs)) {
      shape_bits <- c(
        shape_bits,
        sprintf("organs=%s", paste(dim(payload$organs), collapse = "x")),
        sprintf("systems=%s", paste(dim(payload$systems), collapse = "x"))
      )
    }
    message(
      sprintf(
        "sync: %s %s (%.2f MB; payload_hash=%s; file_sha256=%s; n_cpgs=%s%s)",
        if (reuse) "kept" else "wrote",
        fpath,
        sz / 1e6,
        phash,
        fsha,
        n_cpgs,
        if (length(shape_bits)) paste0("; ", paste(shape_bits, collapse = "; ")) else ""
      )
    )
    assets[[gid]] <- list(
      group_id = gid,
      path = fpath,
      file = fname,
      payload_hash = phash,
      release_tag = phash,
      file_sha256 = fsha,
      size_bytes = as.integer(sz),
      n_clocks = length(payload$clocks %||% character()),
      n_cpgs = n_cpgs,
      encoding = payload$encoding %||% "canonical_matrices",
      encoding_version = as.integer(payload$encoding_version %||% EXTERNAL_ENCODING_VERSION)
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
  warn_if_missing_fixture_duckdb(src$path)
  man <- read_manifest(src$path)

  # The pin is the commit we actually read. manifest$source_git_sha names the *parent*
  # commit (release.py stamps HEAD before the manifest is committed), so using it would
  # label these bytes with a tree that does not contain them.
  current_sha <- src$source_git_sha
  stamped_sha <- as.character(man$source_git_sha %||% NA_character_)
  mkey <- manifest_key(man)

  lock <- read_lockfile()
  up_to_date <- !is.na(lock$manifest_key) && identical(lock$manifest_key, mkey)

  if (isTRUE(dry_run)) {
    files <- list_meta_files(src$path)
    verdict <- if (up_to_date && !isTRUE(force)) {
      "would SKIP rebuild (manifest unchanged)"
    } else if (up_to_date) {
      "would REBUILD (up to date, but force = TRUE)"
    } else if (is.na(lock$manifest_key)) {
      "would BUILD (no usable lockfile)"
    } else {
      "would REBUILD (manifest changed)"
    }
    if (isTRUE(upload)) {
      verdict <- paste0(verdict, "; would UPLOAD external assets (tag = payload_hash)")
    }
    message(
      "sync: ",
      verdict,
      " @ ",
      current_sha,
      "\n  manifest_key = ",
      mkey,
      "\n  lockfile key = ",
      if (is.na(lock$manifest_key)) "<none>" else lock$manifest_key,
      "\n  clock metas=",
      length(files$clock),
      ", group metas=",
      length(files$group),
      ", manifest clocks=",
      length(man$clock_ids)
    )
    return(invisible(list(
      skipped = up_to_date && !isTRUE(force),
      dry_run = TRUE,
      upload = isTRUE(upload),
      source_git_sha = current_sha,
      manifest_key = mkey,
      manifest_generated_at_sha = stamped_sha,
      n_clock_metas = length(files$clock),
      n_group_metas = length(files$group),
      n_manifest_clocks = length(man$clock_ids)
    )))
  }

  if (!isTRUE(force) && up_to_date) {
    message("sync: manifest unchanged since lockfile (", current_sha, ") -- skip rebuild")
    assets <- lockfile_external_assets_list(lock)
    if (isTRUE(upload)) {
      if (!length(assets)) {
        stop(
          "upload=TRUE but lockfile has no external_assets. Run sync(force = TRUE) first.",
          call. = FALSE
        )
      }
      upload_external_assets(assets)
    }
    return(invisible(list(
      skipped = TRUE,
      source_git_sha = as.character(lock$source_git_sha %||% current_sha),
      manifest_key = mkey,
      assets = assets,
      uploaded = isTRUE(upload)
    )))
  }

  message("sync: building catalog @ ", current_sha)
  catalog <- build_catalog(src$path, man)
  catalog$source_git_sha <- current_sha
  catalog$manifest_generated_at_sha <- stamped_sha
  catalog$manifest_key <- mkey

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

  prior_assets <- lockfile_external_assets_list(lock)
  assets <- build_external_assets(
    src$path, catalog, external, prior_assets = prior_assets
  )
  # sysdata after assets so mc_provenance carries the runtime registry
  sys <- build_sysdata(src$path, catalog, ship, external_assets = assets)
  bib <- vendor_bibliography(src$path)

  write_lockfile(
    source_git_sha = current_sha,
    manifest_key = mkey,
    manifest_generated_at_sha = stamped_sha,
    schema_version = catalog$schema_version,
    n_clocks = catalog$n_clocks,
    external_assets = lapply(assets, external_asset_lock_row)
  )

  if (isTRUE(upload)) {
    upload_external_assets(assets)
  } else {
    message(
      "sync: staged ", length(assets),
      " external asset(s) under data-raw/assets/ (upload=FALSE; content-addressed by payload_hash)"
    )
  }

  message("sync: done @ ", current_sha)
  invisible(list(
    skipped = FALSE,
    source_git_sha = current_sha,
    manifest_key = mkey,
    manifest_generated_at_sha = stamped_sha,
    n_clocks = catalog$n_clocks,
    ship_groups = ship,
    external_groups = external,
    sysdata = sys,
    bibliography = bib,
    assets = assets,
    uploaded = isTRUE(upload),
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
    "  sync(upload = TRUE)\n",
    "  sync(source_git_sha = \"dc543a7b...\")"
  )
}
