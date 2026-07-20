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
#

# --- setup -------------------------------------------------------------------

for (pkg in c("jsonlite", "qs2", "usethis", "digest", "rlang")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Missing package '", pkg, "'. Install it first.", call. = FALSE)
  }
}

if (getRversion() < "4.4.0") {
  `%||%` <- function(x, y) {
    if (is.null(x) || (length(x) == 1L && is.na(x))) y else x
  }
}

lockfile_path <- file.path("data-raw", "lockfile.json")
asset_dir <- file.path("data-raw", "assets")
meta_dir <- file.path("data-raw", "methylCIPHER-meta")
sysdata_path <- file.path("R", "sysdata.rda")
# Hashed into build_key(): this script is an input to the artifacts it produces.
SYNC_SCRIPT_PATH <- file.path("data-raw", "sync.R")

# Canonical remote. Local cache is always data-raw/methylCIPHER-meta
META_REMOTE <- "https://github.com/hhp94/methylCIPHER-meta.git"

# External families: ship the rest. These three go to release assets due to size.
EXTERNAL_GROUPS <- c("SystemsAge", "PCClocks", "PCBrainAge")

# Bump when the in-memory pack layout changes (forces new payload_hash).
# v2 (2026-07-18): embedded catalog trimmed to the scoring contract -- build-only fields
# (covers/shared) and provenance/identity/path fields no longer ride into the hashed pack.
EXTERNAL_ENCODING_VERSION <- 2L

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
  "clock_id",
  "group_id",
  "weights_format",
  "computation_type",
  # citation join key (clock_id -> pmid -> inst/bibliography/clocks.bib); not user fluff
  "pmid",
  # scoring
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
  # user-facing (stripped to license only; n_cpgs/array_type/units/access dropped)
  "license"
)

# Kept in FIELD_REGISTRY only so the build-time resolver can read `covers` (resolve_scoring_cpgs);
# stripped from every clock entry after resolution in build_sysdata(), never shipped.
# Why not shipped: DECISIONS.md 2026-07-17 (covers/shared runtime-catalog trim).
CATALOG_BUILD_ONLY_FIELDS <- c("covers", "shared")

# Additional fields stripped from the catalog *embedded in a content-addressed external
# pack* (stable_external_payload): maintainer-side release identity + status keys and local
# provenance paths. They are volatile or path-like, so leaving them in the hashed payload
# defeats content-addressing -- a no-op meta commit whose scoring tensors are byte-identical
# must reuse the same qs2. The shipped mc_catalog keeps coef_path (accessor reads it at
# R/accessors.R), so this extra trim is asset-only, layered on the shared build-only trim.
CATALOG_PACK_DROP_FIELDS <- c(
  "bundle_hash",
  "out_sha256",
  "verification_status",
  "meta_path",
  "coef_path"
)

# Single source of truth for the build-only catalog trim. Applied to BOTH the shipped
# mc_catalog (build_sysdata) and the catalog embedded in each external pack
# (stable_external_payload) so the two can never drift apart.
trim_build_only_fields <- function(clocks) {
  lapply(clocks, function(e) {
    e[CATALOG_BUILD_ONLY_FIELDS] <- NULL
    e
  })
}

# Package-side BibTeX library path (overwritten every successful sync).
BIB_INST_PATH <- file.path("inst", "bibliography", "clocks.bib")

# Top-level group sidecar fields retained from each _group.meta.json.
GROUP_FIELD_REGISTRY <- c(
  "group_id",
  "members",
  "shared_tensors"
)

# Nested allowlists inside kept objects.
IMPUTATION_FIELDS <- c("policy", "ref")
COMPONENT_FIELDS <- c(
  "name",
  "file",
  "row_key",
  "col_key",
  "intercept",
  "covariates"
)
SHARED_FIELDS <- c("name", "file")
PROBE_SET_FIELDS <- c("name", "role", "file", "n")
EXTERNAL_FIELDS <- c(
  "r_package",
  "github",
  "commit",
  "function",
  "model_key",
  "depends"
)
# Thin fixture stub for test wiring (not scoring). Full parity/server prose stays upstream.
FIXTURE_FIELDS <- c(
  "expected",
  "oracle",
  "parity_policy",
  "parity_metric"
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
  df <- utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    colClasses = "character"
  )
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
    stop(
      "bibliography/papers.csv: pmid must be unique non-empty",
      call. = FALSE
    )
  }
  if (any(!nzchar(df$bib_key))) {
    stop(
      "bibliography/papers.csv: bib_key must be non-empty for every row",
      call. = FALSE
    )
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
  empty <- list(
    source_git_sha = NA_character_,
    manifest_key = NA_character_,
    build_key = NA_character_
  )
  if (!file.exists(path)) {
    return(empty)
  }
  lock <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  if (is.null(lock$source_git_sha) || !nzchar(lock$source_git_sha)) {
    stop("Lockfile exists but source_git_sha is missing: ", path, call. = FALSE)
  }
  if (is.null(lock$manifest_key) || !nzchar(lock$manifest_key)) {
    lock$manifest_key <- NA_character_
  }
  # Lockfiles written before the build_key scheme cannot answer the skip question (their
  # manifest_key covered too few inputs); treat them as unknown rather than trusting a key
  # that never saw the bibliography, the group metas, or this script.
  if (is.null(lock$build_key) || !nzchar(lock$build_key)) {
    message("sync: lockfile predates build_key -- treating as out of date")
    lock$build_key <- NA_character_
  }
  lock
}

write_lockfile <- function(
  source_git_sha,
  manifest_key,
  build_key = NULL,
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
    # THE skip key: sha256 over every build input (see build_key())
    build_key = build_key,
    # informational: sha256 over schema_version + clocks[] (release.py `_substantive`),
    # i.e. "did the weights change" -- a component of build_key, not the decision itself
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
  if (
    !is.null(source_git_sha) &&
      nzchar(source_git_sha) &&
      nchar(source_git_sha) < 7L
  ) {
    stop(
      "source_git_sha must be a full or long commit SHA, got: ",
      source_git_sha,
      call. = FALSE
    )
  }

  if (!dir.exists(dirname(meta_dir))) {
    dir.create(dirname(meta_dir), recursive = TRUE, showWarnings = FALSE)
  }

  # Clone-vs-fetch is decided by a real .git, not merely by the directory existing: an
  # interrupted clone or a stray extraction leaves meta_dir present but not a repo, and
  # every `git -C` below would then fail opaquely. A dir that is not a valid repo is
  # discarded and re-cloned -- the mirror is gitignored and disposable.
  is_repo <- dir.exists(file.path(meta_dir, ".git"))
  if (dir.exists(meta_dir) && !is_repo) {
    message(
      "sync: ",
      meta_dir,
      " exists but is not a git repo -- removing and re-cloning"
    )
    unlink(meta_dir, recursive = TRUE, force = TRUE)
  }

  if (!is_repo) {
    # Clone into a temp sibling then rename into place, so a clone that dies partway never
    # leaves a poisoned meta_dir that the next run would try (and fail) to fetch into.
    message("sync: cloning ", META_REMOTE, " -> ", meta_dir)
    tmp <- paste0(meta_dir, ".tmp-", Sys.getpid())
    unlink(tmp, recursive = TRUE, force = TRUE)
    git_exec("clone", "--filter=blob:none", META_REMOTE, tmp)
    if (!file.rename(tmp, meta_dir)) {
      unlink(tmp, recursive = TRUE, force = TRUE)
      stop("Failed to move fresh clone ", tmp, " -> ", meta_dir, call. = FALSE)
    }
  } else {
    message("sync: fetching ", META_REMOTE, " into ", meta_dir)
    # ensure origin points at the canonical remote
    git_exec("remote", "set-url", "origin", META_REMOTE, dir = meta_dir)
    # single remote, so target it explicitly (not --all); --prune drops deleted upstream refs
    git_exec("fetch", "origin", "--tags", "--prune", dir = meta_dir)
  }

  if (!is.null(source_git_sha) && nzchar(source_git_sha)) {
    ref <- source_git_sha
  } else {
    # default branch tip (origin/HEAD -> e.g. origin/master)
    ref <- tryCatch(
      git_value(
        "symbolic-ref",
        "--short",
        "refs/remotes/origin/HEAD",
        dir = meta_dir
      ),
      error = function(e) NA_character_
    )
    if (is.na(ref) || !nzchar(ref)) {
      ref <- "origin/master"
    }
  }
  message("sync: checkout ", ref)
  # -f: the mirror is disposable (gitignored), so force a pristine tree. Without it a
  # hand-edit to a tracked file in the clone makes `checkout --detach` refuse and sync
  # dies opaquely -- or, worse, bundles a modified weights/ tree.
  git_exec("checkout", "-f", "--detach", ref, dir = meta_dir)

  path <- normalizePath(meta_dir, winslash = "/", mustWork = TRUE)
  if (!dir.exists(file.path(path, "weights"))) {
    stop(meta_dir, " has no weights/ after checkout", call. = FALSE)
  }
  if (!file.exists(file.path(path, "manifest.json"))) {
    stop(meta_dir, " has no manifest.json after checkout", call. = FALSE)
  }

  sha <- git_value("rev-parse", "HEAD", dir = path)
  if (!grepl("^[0-9a-f]{40}$", sha)) {
    stop(
      "git rev-parse HEAD did not return a full commit sha: ",
      sha,
      call. = FALSE
    )
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
    "    cd ",
    meta_fixtures,
    "\n",
    "    Rscript build_cohort.R\n",
    "  Or copy an existing beta.duckdb into ",
    cohort_dir,
    ".",
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
        as.character(c$bundle_hash %||% ""),
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

# Bump when the SHIPPED layout changes in a way the inputs below cannot see -- a new
# sysdata object, a changed catalog field set, a different index column. Forces one rebuild.
BUILD_SCHEMA_VERSION <- 1L

# The actual skip key. manifest_key() above covers only four fields per clock (clock_id,
# bundle_hash, out_sha256, verification_status), which is the right notion of "did the WEIGHTS
# change" but far too narrow to decide "can we skip the build": a bibliography correction, a
# group-meta edit, an encoder-version bump, or an edit to this script all change the artifacts
# while leaving the manifest key identical. Hashing git TREE ids (not commit shas) keeps the
# property that a no-op commit -- one that touches nothing we read -- still skips.
build_key <- function(repo_path, man, source_git_sha) {
  # A tree/blob id for a path in the snapshot; NA when the path is absent at that commit.
  tree_id <- function(path) {
    tryCatch(
      git_value("rev-parse", paste0(source_git_sha, ":", path), dir = repo_path),
      error = function(e) NA_character_
    )
  }
  parts <- c(
    build_schema = as.character(BUILD_SCHEMA_VERSION),
    external_encoding = as.character(EXTERNAL_ENCODING_VERSION),
    # the weights themselves, via the manifest's own substantive key
    manifest = manifest_key(man),
    # everything the manifest key does NOT see: group metas live under weights/, and the
    # bibliography feeds both bib_key in the catalog and the vendored clocks.bib
    weights_tree = tree_id("weights"),
    bibliography_tree = tree_id("bibliography"),
    manifest_blob = tree_id("manifest.json"),
    # the build implementation is an input to its own outputs
    sync_sha256 = tryCatch(
      file_sha256_of(SYNC_SCRIPT_PATH),
      error = function(e) NA_character_
    )
  )
  digest::digest(
    paste(names(parts), parts, sep = "=", collapse = "\x1e"),
    algo = "sha256",
    serialize = FALSE
  )
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

# Lexical validation of a meta-declared repo-relative path. The upstream repo is trusted, but
# these strings come out of JSON and are pasted onto a filesystem root, so containment is
# asserted here rather than assumed: a "weights/../../etc/passwd" would otherwise sail through
# WEIGHTS_REF_RE (which only anchors the prefix and the extension) and be read.
assert_repo_rel <- function(rel) {
  if (grepl("\\\\", rel)) {
    stop(
      "Repo-relative path must use forward slashes: ",
      rel,
      call. = FALSE
    )
  }
  if (grepl("^([A-Za-z]:|[/~])", rel)) {
    stop("Repo-relative path must not be absolute: ", rel, call. = FALSE)
  }
  parts <- strsplit(rel, "/", fixed = TRUE)[[1L]]
  if (any(parts %in% c("", ".", ".."))) {
    stop(
      "Repo-relative path must not contain empty, '.' or '..' segments: ",
      rel,
      call. = FALSE
    )
  }
  invisible(rel)
}

# meta-declared repo-relative path (weights/...) -> absolute, verified to stay inside the
# checked-out snapshot. The normalized comparison is what catches a SYMLINK pointing out of
# the repo, which the lexical check above cannot see.
resolve_repo_rel <- function(repo_path, rel) {
  if (is.null(rel) || !nzchar(rel)) {
    return(NA_character_)
  }
  assert_repo_rel(rel)
  abs <- file.path(repo_path, rel)
  root <- normalizePath(repo_path, winslash = "/", mustWork = TRUE)
  real <- normalizePath(abs, winslash = "/", mustWork = FALSE)
  if (!startsWith(real, paste0(root, "/"))) {
    stop(
      "Repo-relative path escapes the snapshot root:\n  rel:  ",
      rel,
      "\n  root: ",
      root,
      "\n  real: ",
      real,
      call. = FALSE
    )
  }
  abs
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

    # man_row is looked up only to assert structural alignment (every manifest clock has a meta
    # and vice versa; see missing_meta check below) and to validate verification_status. The
    # release.py identity keys (bundle_hash / out_sha256) are neither recomputed nor shipped --
    # see DECISIONS.md 2026-07-17 (F1).
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
      entry$depends_on_clocks <- unlist(
        entry$depends_on_clocks,
        use.names = FALSE
      )
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
    # bundle_hash / out_sha256 / verification_status are intentionally absent from the catalog
    # (validated maintainer-side only) -- DECISIONS.md 2026-07-17 (F1/F2, reconciliation).
    entry$fixture <- prune_fixture(meta$fixture)
    entry$meta_path <- rel_from_repo(mp, repo_path)
    entry$coef_path <- if (
      identical(wf, "cpg_coefficient") && has_default_coef
    ) {
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

# --- scoring CpG resolution (ship groups only; role-based, format-independent) ----------------
#
# Every consumer (clock_cpgs(), the future calc_clocks()) needs one question answered the same
# way for every clock regardless of weights_format: "which CpGs does this clock's SCORING step
# need?" Rather than branch on weights_format at each call site (unreadable, and silently wrong
# for a clock shaped unlike whatever the branch author had in mind -- entry$coef_path is only
# ever set for cpg_coefficient, so every other format used to fall back to unioning the WHOLE
# group bundle), this resolves it ONCE per clock here and stores the answer as a materialized
# entry$probe_sets list of {name, role, cpgs} -- cpgs an actual character vector, never a file
# pointer. Mirrors methylCIPHER-meta's own sec 4b resolver contract
# (scoring_cpgs(clock) = probe_sets[role=scoring] if present else the coef/tensor file's CpGs),
# but as a build-time materialization: this is a denormalized convenience view, deliberately NOT
# pushed upstream into the meta repo, which enforces exactly one CpG source of truth per clock.

# Row labels of one loaded tensor, whatever shape read_tensor_csv() gave it: a named numeric
# vector (2-col cpg,value), a bare character vector (1-col probe list), or a data.frame (3+
# columns, e.g. EpiTOC2's cpg,delta,beta0). The row-key column is always named `cpg` per the
# tensor CSV schema (methylCIPHER-meta sec 3); fall back to the first column if renamed.
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

# Turn one upstream probe_sets entry ({name, role, file, n}) into {name, role, cpgs} by reading
# the file it points at out of the already-loaded bundle tensors. Any role, not just scoring --
# e.g. DunedinPACE's quantile_normalization_background entry materializes the same way, so a
# future consumer never needs to open a tensor file itself either.
# Validated at build time, because every failure here is silent at runtime: an unresolvable
# file pointer used to yield cpgs = character(0), which still counts as a role=="scoring"
# entry downstream and therefore SUPPRESSES the tiered fallback -- shipping a clock that
# scores nothing. Better to break the maintainer's sync than the user's scores.
materialize_probe_set <- function(ps, tensors, cid = NA_character_) {
  where <- paste0(
    "probe_set '",
    ps$name %||% "?",
    "' (role ",
    ps$role %||% "?",
    ") of clock ",
    cid
  )
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
  if (anyNA(cpgs) || any(!nzchar(cpgs))) {
    stop(where, " contains missing or empty CpG ids: ", ps$file, call. = FALSE)
  }
  if (anyDuplicated(cpgs)) {
    stop(
      where,
      " contains ",
      sum(duplicated(cpgs)),
      " duplicate CpG id(s): ",
      ps$file,
      call. = FALSE
    )
  }
  # Upstream declares the expected count; a mismatch means the meta and the tensor have
  # drifted apart, which no downstream consumer could detect.
  if (!is.null(ps$n) && !is.na(suppressWarnings(as.integer(ps$n)))) {
    n <- as.integer(ps$n)
    if (n != length(cpgs)) {
      stop(
        where,
        " declares n = ",
        n,
        " but ",
        ps$file,
        " has ",
        length(cpgs),
        " CpGs.",
        call. = FALSE
      )
    }
  }
  list(name = ps$name, role = ps$role, cpgs = cpgs)
}

# Tier 3: union of a clock's OWN cpg-keyed components. Covers single-tensor clocks (EpiTOC2),
# sex-split clocks with more than one cpg-keyed component (DNAmFitAge's DNAmGait_wAge: separate
# female_model/male_model), and composites that inline their own cpg-keyed pieces directly
# (GrimAgeV2's _internal_* surrogates; PhysAge's own coef_DNAm* components) -- none of those need
# any recursion.
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

# Tier 4: a group-level shared_tensors entry that is itself a bare one-column probe list (not a
# value-bearing table) -- covers a composite whose own component isn't cpg-keyed but whose group
# ships an explicit canonical list (DNAmFitAge's _shared/AllCpGs.csv.gz, SystemsAge's
# _shared/CpGs.csv.gz).
group_shared_cpg_list <- function(gside, tensors) {
  for (rel in gside$shared_tensors %||% character()) {
    t <- tensors[[rel]]
    if (is.character(t) && is.null(dim(t)) && length(t) > 0L) {
      return(as.character(t))
    }
  }
  character()
}

# Tiers 2-6 for one clock. Tier 1 (an upstream role=="scoring" probe_sets entry, e.g.
# external_package) is checked by the driver before this is ever called, so a real upstream
# declaration always wins untouched. `seen` guards a covers-list cycle (a composite always lists
# itself in its own `covers`); in practice recursion never runs deep here because every member a
# composite covers resolves via tier 2/3 before it would ever need its own covers list.
resolve_scoring_cpgs <- function(
  cid,
  catalog,
  tensors,
  gside,
  seen = character()
) {
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

  # tier 5: recursive union over this clock's own `covers` list -- composites with no cpg-keyed
  # tensor of their own and no group shared list (e.g. GrimAgeV1, whose own component is the
  # 8-surrogate Cox combo, row_key == "component", not "cpg").
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

  character() # tier 6: genuinely unresolved (custom, e.g. MiAge -- frozen code, no tensor)
}

# Driver, called once per ship group from build_sysdata() right after its bundle is built. Two
# passes: (1) materialize every clock's own upstream probe_sets (any role) from file pointers
# into actual CpG vectors; (2) synthesize a role=="scoring" entry for any clock that still
# doesn't have one, via the tiered resolver above.
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
      # NON-EMPTY is the test, not merely present: an upstream scoring entry that resolved
      # to nothing must fall through to the tiered resolver rather than block it. (With the
      # validation in materialize_probe_set() that state is now unreachable from a file
      # pointer; this keeps the invariant true for any future synthesized entry too.)
      has_scoring <- length(Filter(
        function(p) identical(p$role, "scoring") && length(p$cpgs) > 0L,
        entry$probe_sets %||% list()
      )) >
        0L
      if (has_scoring) {
        next
      }
      cpgs <- resolve_scoring_cpgs(cid, catalog, tensors, gside)
      if (length(cpgs)) {
        catalog$clocks[[cid]]$probe_sets <- c(
          entry$probe_sets %||% list(),
          list(list(
            name = "scoring_derived",
            role = "scoring",
            cpgs = unique(cpgs)
          ))
        )
      }
    }
  }
  catalog
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
      stop(
        "Missing tensor for matrix column ",
        col_names[[i]],
        ": ",
        rel,
        call. = FALSE
      )
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
    stop(
      group_id,
      ": no named numeric tensors to resolve cpgs from",
      call. = FALSE
    )
  }
  lens <- vapply(named_rels, function(r) length(tensors[[r]]), integer(1L))
  ref <- names(tensors[[named_rels[which.max(lens)]]])
  for (r in named_rels[lens == max(lens)]) {
    if (!setequal(names(tensors[[r]]), ref)) {
      stop(
        group_id,
        ": probe set mismatch among cpg-aligned tensors (",
        r,
        ")",
        call. = FALSE
      )
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
  bundle$coefficient_matrix <- cbind_aligned(
    tensors,
    coef_rels,
    cpgs,
    col_names
  )
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

  organ_rels <- file.path(
    "weights",
    "SystemsAge",
    paste0(SYSTEMSAGE_ORGANS, ".csv.gz")
  )
  system_rels <- file.path(
    "weights",
    "SystemsAge",
    "systems",
    paste0(SYSTEMSAGE_ORGANS, ".csv.gz")
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
    organ_rels,
    system_rels,
    age_rel,
    impute_rel,
    cpgs_rel,
    resolved$drop_lists
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
    tensors,
    coef_rel,
    cpgs,
    "PCBrainAge"
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

# Flat per-clock index derived from the catalog. One row per clock, scalar dispatch/discovery
# fields only (+ a covariates list-col). This is the shape list_clocks() filters over and the
# clock_id -> group_id map resolve_clocks / dispatch need, so neither has to vapply across the
# ragged mc_catalog. Pure derived data: rebuilt from catalog every sync, never hand-edited.
build_index <- function(catalog) {
  clocks <- catalog$clocks
  ids <- names(clocks)

  # first scalar of a per-clock field, or `default` when absent/empty
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
  # variable-length per clock -> list-col; empty character() means "no covariates"
  idx$covariates_required <- unname(lapply(clocks, function(e) {
    as.character(e$covariates_required %||% character())
  }))
  idx$n_covariates <- lengths(idx$covariates_required)

  idx
}

build_sysdata <- function(
  repo_path,
  catalog,
  ship_groups,
  external_assets = NULL
) {
  message(
    "sync: building shipped bundles for ",
    length(ship_groups),
    " groups..."
  )
  bundles <- build_group_bundles(repo_path, catalog, ship_groups)
  catalog <- resolve_group_scoring_probe_sets(catalog, bundles)

  # Drop the build-only fields (see CATALOG_BUILD_ONLY_FIELDS) before packaging.
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
    # Build provenance: which meta commit produced these bytes (honest, written only on rebuild).
    # manifest_key is NOT shipped here -- lockfile only. See DECISIONS.md 2026-07-17 (F2).
    source_git_sha = catalog$source_git_sha,
    # manifest.json's own stamp (parent commit) -- provenance, never an identity
    manifest_generated_at_sha = catalog$manifest_generated_at_sha,
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
    mc_index,
    mc_provenance,
    internal = TRUE,
    overwrite = TRUE
  )

  path <- file.path("R", "sysdata.rda")
  sz <- file.info(path)$size
  message(sprintf(
    "sync: wrote %s (%.1f KB; %d clocks indexed)",
    path,
    sz / 1024,
    nrow(mc_index)
  ))
  invisible(list(
    path = path,
    size_bytes = sz,
    objects = c(
      "mc_catalog",
      "mc_groups",
      "mc_bundles",
      "mc_index",
      "mc_provenance"
    )
  ))
}

# Low ZSTD level + no shuffle: prioritize decompress/load speed over size.
# Matrix packing + single $cpgs already removes most bulk; memoise at runtime.
QS2_COMPRESS_LEVEL <- 1L
QS2_SHUFFLE <- FALSE

# Canonical in-memory pack for hash + qs_save. Includes catalog (intercepts, ...) so scoring
# contract and tensors move together. Excludes pin-only fields so a new meta checkout with
# identical packs does not force a new release.
stable_external_payload <- function(bundle) {
  for (f in EXTERNAL_PIN_FIELDS) {
    bundle[[f]] <- NULL
  }

  tensors <- bundle$tensors %||% list()
  if (length(tensors) && !is.null(names(tensors))) {
    tensors <- tensors[sort(names(tensors))]
  }

  # Embed only the scoring contract: the shared build-only trim (identical to the shipped
  # mc_catalog) plus the asset-only provenance/identity/path drop, so a no-op meta commit
  # cannot perturb the pack hash. See CATALOG_BUILD_ONLY_FIELDS / CATALOG_PACK_DROP_FIELDS.
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

  # Fixed field order; drop pure-nulls so PC* and SystemsAge share one schema.
  out <- list(
    encoding_version = as.integer(
      bundle$encoding_version %||% EXTERNAL_ENCODING_VERSION
    ),
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
  list(
    owner = parts[[2L]],
    repo = parts[[3L]],
    slug = paste0(parts[[2L]], "/", parts[[3L]])
  )
}

# Release target: env METHYLCIPHER_RELEASE_REPO, else package origin remote.
package_release_repo <- function() {
  env <- Sys.getenv("METHYLCIPHER_RELEASE_REPO", unset = "")
  if (nzchar(env)) {
    if (grepl("/", env) && !grepl("github\\.com", env)) {
      return(list(
        owner = sub("/.*", "", env),
        repo = sub(".*/", "", env),
        slug = env
      ))
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

# Uploads go through PyGithub (declared in pyproject.toml), invoked as
#   uv run python data-raw/gh_upload.py
# with the asset manifest piped on stdin. This replaces the old `gh` CLI path and
# its Windows argv-quoting workarounds. A non-upload sync never touches any of this.
GH_UPLOAD_PY <- file.path("data-raw", "gh_upload.py")

uv_bin <- function() {
  w <- Sys.which("uv")
  if (!nzchar(w)) {
    stop(
      "`uv` not found on PATH (needed to run ",
      GH_UPLOAD_PY,
      " for uploads).",
      call. = FALSE
    )
  }
  w
}

# Publish all staged external assets to GitHub Releases via PyGithub. Identity is
# already fixed in R (tag = payload_hash, sha256 = file hash); this only verifies
# the staged bytes, then hands a manifest to data-raw/gh_upload.py over stdin.
upload_external_assets <- function(assets) {
  if (!length(assets)) {
    message("sync: no external assets to upload")
    return(invisible(list()))
  }
  if (!nzchar(Sys.getenv("GITHUB_TOKEN")) && !nzchar(Sys.getenv("GH_TOKEN"))) {
    stop(
      "upload=TRUE requires a GitHub token in GITHUB_TOKEN (or GH_TOKEN). ",
      "Create a PAT with Contents:read/write on the package repo and set it ",
      "(e.g. in ~/.Renviron).",
      call. = FALSE
    )
  }
  if (!file.exists(GH_UPLOAD_PY)) {
    stop("Upload helper not found: ", GH_UPLOAD_PY, call. = FALSE)
  }

  repo <- package_release_repo()
  target <- package_release_target_commitish()

  # Verify each staged file against its recorded hash, then build the upload manifest.
  items <- lapply(assets, function(a) {
    tag <- as.character(a$payload_hash %||% "")
    if (!nzchar(tag)) {
      stop("Asset missing payload_hash: ", a$group_id %||% "?", call. = FALSE)
    }
    fpath <- a$path %||% file.path(asset_dir, a$file)
    if (!file.exists(fpath)) {
      stop(
        "Staged asset missing for ",
        a$group_id,
        ": ",
        fpath,
        "\nRe-run sync() to rebuild before upload.",
        call. = FALSE
      )
    }
    if (!is.null(a$file_sha256) && nzchar(a$file_sha256)) {
      actual <- file_sha256_of(fpath)
      if (!identical(actual, a$file_sha256)) {
        stop(
          "Staged file sha256 mismatch for ",
          a$group_id,
          ":\n  expected ",
          a$file_sha256,
          "\n  actual   ",
          actual,
          call. = FALSE
        )
      }
    }
    list(
      group_id = as.character(a$group_id %||% ""),
      tag = tag,
      path = normalizePath(fpath, winslash = "/", mustWork = TRUE),
      name = as.character(a$file %||% basename(fpath)),
      sha256 = as.character(a$file_sha256 %||% "")
    )
  })

  req <- list(
    slug = repo$slug,
    target_commitish = target,
    assets = unname(items)
  )
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
  err_file <- tempfile("uv-gh-")
  on.exit(unlink(err_file), add = TRUE)
  out <- system2(
    uv_bin(),
    c("run", "python", GH_UPLOAD_PY),
    input = json,
    stdout = TRUE,
    stderr = err_file
  )
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop(
      GH_UPLOAD_PY,
      " failed:\n",
      paste(readLines(err_file, warn = FALSE), collapse = "\n"),
      call. = FALSE
    )
  }

  # Python emits a single {"results":[...]} object on stdout; surface each action.
  res <- tryCatch(
    jsonlite::fromJSON(paste(out, collapse = "\n"), simplifyVector = FALSE),
    error = function(e) NULL
  )
  for (r in res$results %||% list()) {
    message(
      "sync: ",
      r$action,
      " ",
      r$name,
      " -> ",
      repo$slug,
      " @ tag ",
      r$tag
    )
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
      out[[gid]]$path <- file.path(
        asset_dir,
        as.character(out[[gid]]$file %||% "")
      )
    }
  }
  out
}

# Why a matching key is NOT sufficient to skip: the key describes the INPUTS, while the
# things a skip preserves are the OUTPUTS -- and those live partly outside git.
# data-raw/assets/ is gitignored, so a fresh clone has a matching lockfile and no packs at
# all; deleting R/sysdata.rda or inst/bibliography/clocks.bib is likewise invisible to any
# input hash. Verify the artifacts exist and still match what the lockfile recorded, and
# report exactly which one forced the rebuild.
missing_outputs <- function(lock) {
  problems <- character()

  if (!file.exists(sysdata_path)) {
    problems <- c(problems, paste0(sysdata_path, " missing"))
  } else {
    # Cheap structural read: a truncated or hand-edited sysdata must not pass as current.
    prov <- tryCatch(
      {
        env <- new.env(parent = emptyenv())
        load(sysdata_path, envir = env)
        env$mc_provenance
      },
      error = function(e) NULL
    )
    if (is.null(prov)) {
      problems <- c(problems, paste0(sysdata_path, " unreadable or has no mc_provenance"))
    } else if (
      !is.na(lock$source_git_sha) &&
        !identical(as.character(prov$source_git_sha), as.character(lock$source_git_sha))
    ) {
      problems <- c(
        problems,
        sprintf(
          "%s was built from %s, lockfile says %s",
          sysdata_path,
          prov$source_git_sha,
          lock$source_git_sha
        )
      )
    }
  }

  if (!file.exists(BIB_INST_PATH)) {
    problems <- c(problems, paste0(BIB_INST_PATH, " missing"))
  }

  for (a in lockfile_external_assets_list(lock)) {
    gid <- as.character(a$group_id %||% "?")
    p <- as.character(a$path %||% "")
    if (!nzchar(p) || !file.exists(p)) {
      problems <- c(problems, paste0("external asset missing: ", gid, " (", p, ")"))
      next
    }
    want <- as.character(a$file_sha256 %||% "")
    if (nzchar(want) && !identical(file_sha256_of(p), want)) {
      problems <- c(problems, paste0("external asset sha256 mismatch: ", gid, " (", p, ")"))
    }
  }

  problems
}

build_external_assets <- function(
  repo_path,
  catalog,
  external_groups,
  prior_assets = NULL
) {
  if (!dir.exists(asset_dir)) {
    dir.create(asset_dir, recursive = TRUE, showWarnings = FALSE)
  }
  assets <- list()
  prior <- prior_assets %||% list()

  for (gid in external_groups) {
    message("sync: building external asset for ", gid, "...")
    raw_bundle <- build_group_bundles(repo_path, catalog, gid)[[gid]]
    # Resolve scoring probe sets BEFORE encoding: encode_external_asset() restructures the
    # group's tensors into canonical matrices, after which the file pointers the resolver
    # reads are gone. Skipping this used to leave every external clock with NO probe_sets at
    # all -- so clock_scoring_cpgs() returned character(0) for all 28 of them, and the
    # catalog-only needed_cpgs_union() step in calc_clocks() silently contributed nothing for
    # an external clock. The resolved catalog is threaded back out of this function so the
    # shipped mc_catalog and the pack's embedded catalog are the same object.
    catalog <- resolve_group_scoring_probe_sets(
      catalog,
      stats::setNames(list(raw_bundle), gid)
    )
    bundle <- encode_external_asset(raw_bundle)
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
          "sync: ",
          gid,
          " payload_hash unchanged (",
          phash,
          ") -- reusing staged ",
          fname
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
        sprintf(
          "coef=%s",
          paste(dim(payload$coefficient_matrix), collapse = "x")
        )
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
        if (length(shape_bits)) {
          paste0("; ", paste(shape_bits, collapse = "; "))
        } else {
          ""
        }
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
      encoding_version = as.integer(
        payload$encoding_version %||% EXTERNAL_ENCODING_VERSION
      )
    )
  }

  # Drop superseded local staging files: for every group we just built, remove sibling
  # {group}-*.qs2 whose hash isn't the current payload_hash. Only the local asset_dir is
  # pruned -- published releases (tag = payload_hash) are never touched, so older package
  # versions can still fetch their pinned asset. Scoped per built group, so a group not
  # built this run keeps all its files.
  for (gid in external_groups) {
    keep <- as.character(assets[[gid]]$file %||% "")
    siblings <- list.files(
      asset_dir,
      pattern = paste0("^", tolower(gid), "-[0-9a-f]+\\.qs2$")
    )
    for (f in setdiff(siblings, keep)) {
      unlink(file.path(asset_dir, f))
      message("sync: pruned superseded staging asset ", f)
    }
  }

  # `catalog` carries the probe sets resolved for every external group above; the caller
  # must build sysdata from THIS copy, not the one it passed in.
  list(assets = assets, catalog = catalog)
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
  bkey <- build_key(src$path, man, current_sha)

  lock <- read_lockfile()
  # Two independent conditions: the inputs are unchanged AND the outputs are still there.
  inputs_same <- !is.na(lock$build_key) && identical(lock$build_key, bkey)
  gaps <- if (inputs_same) missing_outputs(lock) else character()
  up_to_date <- inputs_same && !length(gaps)
  if (inputs_same && length(gaps)) {
    message(
      "sync: build inputs unchanged but artifacts are missing/stale -- rebuilding:\n  - ",
      paste(gaps, collapse = "\n  - ")
    )
  }

  if (isTRUE(dry_run)) {
    files <- list_meta_files(src$path)
    verdict <- if (up_to_date && !isTRUE(force)) {
      "would SKIP rebuild (build inputs unchanged, artifacts present)"
    } else if (up_to_date) {
      "would REBUILD (up to date, but force = TRUE)"
    } else if (is.na(lock$build_key)) {
      "would BUILD (no usable lockfile)"
    } else if (inputs_same) {
      paste0(
        "would REBUILD (inputs unchanged, artifacts missing/stale: ",
        paste(gaps, collapse = "; "),
        ")"
      )
    } else {
      "would REBUILD (build inputs changed)"
    }
    if (isTRUE(upload)) {
      verdict <- paste0(
        verdict,
        "; would UPLOAD external assets (tag = payload_hash)"
      )
    }
    message(
      "sync: ",
      verdict,
      " @ ",
      current_sha,
      "\n  build_key    = ",
      bkey,
      "\n  lockfile key = ",
      if (is.na(lock$build_key)) "<none>" else lock$build_key,
      "\n  manifest_key = ",
      mkey,
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
      build_key = bkey,
      manifest_key = mkey,
      manifest_generated_at_sha = stamped_sha,
      n_clock_metas = length(files$clock),
      n_group_metas = length(files$group),
      n_manifest_clocks = length(man$clock_ids)
    )))
  }

  if (!isTRUE(force) && up_to_date) {
    message(
      "sync: build inputs unchanged and artifacts present (",
      current_sha,
      ") -- skip rebuild"
    )
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
      build_key = bkey,
      manifest_key = mkey,
      assets = assets,
      uploaded = isTRUE(upload)
    )))
  }

  message("sync: building catalog @ ", current_sha)
  catalog <- build_catalog(src$path, man)
  catalog$source_git_sha <- current_sha
  catalog$manifest_generated_at_sha <- stamped_sha
  # manifest_key stays maintainer-side (mkey -> write_lockfile below); not stamped onto the
  # shipped catalog / mc_provenance -- see F2, DECISIONS 2026-07-17 (plan sec 9.1).

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
  ext <- build_external_assets(
    src$path,
    catalog,
    external,
    prior_assets = prior_assets
  )
  assets <- ext$assets
  # External groups resolve their scoring probe sets inside build_external_assets() (their
  # tensors are gone after encoding), so adopt the catalog it returns -- otherwise the
  # shipped mc_catalog would disagree with the catalog embedded in the packs.
  catalog <- ext$catalog
  # sysdata after assets so mc_provenance carries the runtime registry
  sys <- build_sysdata(src$path, catalog, ship, external_assets = assets)
  bib <- vendor_bibliography(src$path)

  write_lockfile(
    source_git_sha = current_sha,
    manifest_key = mkey,
    build_key = bkey,
    manifest_generated_at_sha = stamped_sha,
    schema_version = catalog$schema_version,
    n_clocks = catalog$n_clocks,
    external_assets = lapply(assets, external_asset_lock_row)
  )

  if (isTRUE(upload)) {
    upload_external_assets(assets)
  } else {
    message(
      "sync: staged ",
      length(assets),
      " external asset(s) under data-raw/assets/ (upload=FALSE; content-addressed by payload_hash)"
    )
  }

  message("sync: done @ ", current_sha)
  invisible(list(
    skipped = FALSE,
    source_git_sha = current_sha,
    build_key = bkey,
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
    "sync.R loaded. Clones/fetches ",
    META_REMOTE,
    "\n",
    "  into data-raw/methylCIPHER-meta, then materializes package data.\n",
    "  sync(dry_run = TRUE)\n",
    "  sync()\n",
    "  sync(force = TRUE)\n",
    "  sync(upload = TRUE)\n",
    "  sync(source_git_sha = \"dc543a7b...\")"
  )
}
