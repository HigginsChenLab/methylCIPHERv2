# External clock-data packs (SystemsAge, PCClocks, PCBrainAge): content-addressed qs2
# files fetched on demand. No silent download; no write without consent. The shipped
# provenance (mc_provenance$external_assets) names each pack; qs2's own checksum
# (validate_checksum) guards transfer integrity.

MC_RELEASE_REPO <- "hhp94/methylCIPHER"

# --- registry (our own compiled provenance, not untrusted input) ---

mc_external_groups <- function() {
  assets <- mc_provenance$external_assets
  if (is.null(assets)) character(0) else names(assets)
}

# One provenance row: $file, $payload_hash, $release_tag, $size_bytes, ...
mc_asset <- function(group_id) {
  row <- mc_provenance$external_assets[[group_id]]
  if (is.null(row)) {
    stop(
      "Not an external clock group: ",
      group_id,
      "\nKnown groups: ",
      paste(mc_external_groups(), collapse = ", "),
      call. = FALSE
    )
  }
  row
}

# "all" or a vector of known group ids.
mc_resolve_groups <- function(groups) {
  if (is.null(groups) || identical(groups, "all") || !length(groups)) {
    return(mc_external_groups())
  }
  groups <- unique(as.character(groups))
  for (g in groups) mc_asset(g) # errors on any unknown id
  groups
}

# Public release-asset URL (option override for forks/testing).
mc_asset_url <- function(row) {
  repo <- getOption("methylCIPHER.release_repo", MC_RELEASE_REPO)
  sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    repo,
    row$release_tag,
    row$file
  )
}

# --- cache location ---

# CRAN-sanctioned per-user cache directory.
mc_default_cache_dir <- function() {
  path.expand(tools::R_user_dir("methylCIPHER", which = "cache"))
}

nz1 <- function(x) length(x) == 1L && !is.na(x) && nzchar(x)

# Active cache dir. Precedence: `assets` arg > session option > env > default.
mc_cache_dir <- function(assets = NULL) {
  if (nz1(assets)) {
    return(path.expand(assets))
  }
  opt <- getOption("methylCIPHER.cache_dir")
  if (nz1(opt)) {
    return(path.expand(opt))
  }
  env <- Sys.getenv("METHYLCIPHER_CACHE_DIR", unset = "")
  if (nz1(env)) {
    return(path.expand(env))
  }
  mc_default_cache_dir()
}

# Set the cache dir for the rest of the session; returns the previous value.
mc_set_cache_dir <- function(path) {
  old <- getOption("methylCIPHER.cache_dir")
  options(
    methylCIPHER.cache_dir = if (is.null(path)) NULL else path.expand(path)
  )
  invisible(old)
}

# --- helpers ---

mc_bytes <- function(x) {
  format(structure(as.numeric(x), class = "object_size"), units = "auto")
}

# Stable content hash; mirrors sync's payload_hash_of() (version 2, xdr).
mc_payload_hash <- function(x) {
  digest::digest(
    serialize(x, connection = NULL, version = 2L, xdr = TRUE),
    algo = "sha256",
    serialize = FALSE
  )
}

# Which packs are present in the cache. Pure query; never downloads or writes.
mc_cached_files <- function(groups = "all", assets = NULL) {
  groups <- mc_resolve_groups(groups)
  dir <- mc_cache_dir(assets)
  files <- vapply(groups, function(g) file.path(dir, mc_asset(g)$file), character(1))
  files[file.exists(files)]
}

# --- download ---

# Pure fetch of one pack: stage -> validate via qs2 checksum -> atomic rename. No prompting.
mc_fetch <- function(row, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  url <- mc_asset_url(row)
  dest <- file.path(dir, row$file)
  tmp <- paste0(dest, ".part")
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)

  # Big packs exceed download.file()'s default 60s whole-transfer timeout.
  old_to <- options(timeout = max(getOption("timeout", 60L), 1800L))
  on.exit(options(old_to), add = TRUE)

  tryCatch(
    utils::download.file(url, destfile = tmp, mode = "wb"),
    error = function(e) {
      stop(
        "Download failed for ",
        row$group_id,
        ": ",
        conditionMessage(e),
        "\nURL: ",
        url,
        call. = FALSE
      )
    }
  )
  # A corrupt/truncated transfer fails the checksum here, before it counts as cached.
  qs2::qs_read(tmp, validate_checksum = TRUE)
  file.rename(tmp, dest)
  dest
}

# Consent for downloading a set of missing packs (one batched prompt), or stop.
# ask = TRUE prompts interactively and refuses non-interactively; ask = FALSE consents.
mc_consent <- function(rows, dir, ask) {
  if (!length(rows) || !isTRUE(ask)) {
    return(invisible(TRUE))
  }
  labels <- vapply(
    rows,
    function(r) sprintf("%s (%s)", r$group_id, mc_bytes(r$size_bytes)),
    character(1)
  )
  total <- mc_bytes(sum(vapply(rows, function(r) as.numeric(r$size_bytes), numeric(1))))
  if (!interactive()) {
    stop(
      "Refusing to download ",
      paste(labels, collapse = ", "),
      " [", total, " total] without confirmation in a non-interactive session.\n",
      "Pass ask = FALSE to consent, or pre-stage the file(s) and point `assets` at them.",
      call. = FALSE
    )
  }
  ok <- utils::askYesNo(sprintf(
    "Download %d clock-data pack(s) [%s total] to\n  %s\n  %s\n?",
    length(rows),
    total,
    dir,
    paste(labels, collapse = "\n  ")
  ))
  if (!isTRUE(ok)) {
    stop(
      "Download declined for ",
      paste(vapply(rows, function(r) r$group_id, character(1)), collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Pre-fetch packs into the cache (nothing is re-downloaded if already present).
mc_data_download <- function(groups = "all", assets = NULL, ask = TRUE) {
  groups <- mc_resolve_groups(groups)
  dir <- mc_cache_dir(assets)
  rows <- lapply(groups, mc_asset)
  files <- vapply(rows, function(r) file.path(dir, r$file), character(1))
  missing <- !file.exists(files)
  if (any(missing)) {
    mc_consent(rows[missing], dir, ask)
    for (i in which(missing)) {
      files[i] <- mc_fetch(rows[[i]], dir)
    }
  }
  invisible(files)
}

# --- load ---

# Read a pack (qs2-verified) and warn (never stop) if its content hash drifts.
mc_read_pack <- function(file, row) {
  pack <- qs2::qs_read(file, validate_checksum = TRUE)
  if (!identical(mc_payload_hash(pack), row$payload_hash)) {
    warning(
      "External pack '",
      row$group_id,
      "' content hash differs from this package's provenance.\n",
      "Scores may not match this version of methylCIPHER; ",
      "re-download to refresh (see ?clear_clock_cache).",
      call. = FALSE
    )
  }
  pack
}

# Canonicalize `assets` -> NULL (open: cache + consent download) or a closed set:
# a cache-dir path (character), or a registry (named list of packs keyed by group_id).
mc_canonicalize_assets <- function(assets) {
  if (is.null(assets)) {
    return(NULL)
  }
  if (is.character(assets)) {
    if (length(assets) != 1L || !nzchar(assets)) {
      stop("`assets` path must be a single non-empty string.", call. = FALSE)
    }
    return(assets)
  }
  is_pack <- function(x) is.list(x) && !is.null(x$group_id)
  if (is_pack(assets)) {
    return(stats::setNames(list(assets), assets$group_id))
  }
  if (is.list(assets) && length(assets) && all(vapply(assets, is_pack, logical(1)))) {
    return(stats::setNames(
      assets,
      vapply(assets, function(p) as.character(p$group_id), character(1))
    ))
  }
  stop(
    "`assets` must be NULL, a cache-dir path, a loaded pack, or a list of loaded packs.",
    call. = FALSE
  )
}

# Resolve the external groups a plan needs to a named list of loaded packs (keyed by
# group_id). assets = NULL -> read from the cache dir, downloading missing packs on
# consent (open set). assets provided (path or loaded pack[s]) -> closed set: resolve only
# from what is given, never download; a needed group not covered is a hard error.
load_mc_assets <- function(groups, assets = NULL, ask = TRUE) {
  groups <- unique(as.character(groups))
  groups <- groups[nzchar(groups)]
  if (!length(groups)) {
    return(stats::setNames(list(), character(0)))
  }
  for (g in groups) mc_asset(g) # errors on any unknown id

  canon <- mc_canonicalize_assets(assets)

  # Closed set from in-memory pack(s): satisfy from the given registry, never touch disk.
  if (is.list(canon)) {
    # Resolve needed groups first (a missing one is fatal), then warn about extras.
    packs <- lapply(groups, function(g) {
      pack <- canon[[g]]
      if (is.null(pack)) {
        stop(
          "load_mc_assets(): external group '",
          g,
          "' is needed but not present in `assets` (closed set; no download).",
          call. = FALSE
        )
      }
      pack
    })
    extra <- setdiff(names(canon), groups)
    if (length(extra)) {
      warning(
        "load_mc_assets(): ignoring provided asset(s) not needed by the plan: ",
        paste(extra, collapse = ", "),
        call. = FALSE
      )
    }
    return(stats::setNames(packs, groups))
  }

  # Path (closed) or NULL (open): both read from a cache dir; only open may download.
  closed <- !is.null(canon)
  dir <- mc_cache_dir(canon)
  rows <- lapply(groups, mc_asset)
  files <- vapply(rows, function(r) file.path(dir, r$file), character(1))
  missing <- !file.exists(files)

  if (any(missing)) {
    if (closed) {
      stop(
        "load_mc_assets(): external group(s) ",
        paste(groups[missing], collapse = ", "),
        " not found in `assets` dir '",
        dir,
        "' (closed set; no download).",
        call. = FALSE
      )
    }
    mc_consent(rows[missing], dir, ask)
    for (i in which(missing)) {
      files[i] <- mc_fetch(rows[[i]], dir)
    }
  }

  packs <- Map(mc_read_pack, files, rows)
  stats::setNames(packs, groups)
}

# --- clear (stub: reports what is cached; deletion is always consent-gated) ---

# TODO: interactive delete flow to be designed. Never unlinks automatically.
clear_clock_cache <- function(groups = "all", assets = NULL) {
  files <- mc_cached_files(groups, assets)
  if (!length(files)) {
    message("No cached clock data to clear in ", mc_cache_dir(assets), ".")
    return(invisible(character(0)))
  }
  message(
    "Cached clock data (",
    mc_bytes(sum(file.size(files))),
    ") in ",
    mc_cache_dir(assets),
    ":\n  ",
    paste(basename(files), collapse = "\n  "),
    "\nDeletion is not yet wired up; remove these files manually for now."
  )
  invisible(files)
}
