# External clock-data cache (SystemsAge, PCClocks, PCBrainAge). Content-addressed qs2 packs.
# No silent download; no write without consent. Identity is the payload hash.

MC_RELEASE_REPO <- "hhp94/methylCIPHER"

# --- validation ---

# Lowercase hex hash: 32 (payload) or 64 (sha256).
MC_HEX_RE <- "^[0-9a-f]{32}$|^[0-9a-f]{64}$"

mc_chr1 <- function(x, what) {
  if (length(x) != 1L || is.na(x) || !nzchar(as.character(x))) {
    stop(what, " must be a single non-empty string.", call. = FALSE)
  }
  as.character(x)[[1L]]
}

mc_num1 <- function(x, what) {
  x <- suppressWarnings(as.numeric(x))
  if (length(x) != 1L || is.na(x) || x <= 0) {
    stop(what, " must be a single positive number.", call. = FALSE)
  }
  x
}

# Validate a registry row as a wire contract; never skip file_sha256.
mc_validate_row <- function(row, group_id) {
  if (!is.list(row)) {
    stop("Malformed asset registry entry for ", group_id, ".", call. = FALSE)
  }
  where <- function(f) paste0("external_assets[[\"", group_id, "\"]]$", f)

  row$group_id <- mc_chr1(row$group_id, where("group_id"))
  if (!identical(row$group_id, group_id)) {
    stop(
      "Asset registry entry for ",
      group_id,
      " carries group_id '",
      row$group_id,
      "'.",
      call. = FALSE
    )
  }
  row$release_tag <- mc_chr1(row$release_tag, where("release_tag"))
  row$file <- mc_chr1(row$file, where("file"))
  if (!identical(row$file, basename(row$file)) || grepl("[/\\\\]", row$file)) {
    stop(where("file"), " must be a bare filename, got: ", row$file, call. = FALSE)
  }
  row$file_sha256 <- mc_chr1(row$file_sha256, where("file_sha256"))
  if (!grepl("^[0-9a-f]{64}$", row$file_sha256)) {
    stop(
      where("file_sha256"),
      " is not a sha256 (64 lowercase hex chars): ",
      row$file_sha256,
      call. = FALSE
    )
  }
  row$size_bytes <- mc_num1(row$size_bytes, where("size_bytes"))
  row
}

# --- registry ---

mc_external_groups <- function() {
  assets <- mc_provenance$external_assets
  if (is.null(assets)) character(0) else names(assets)
}

# One validated registry row, or a clear error.
mc_asset_row <- function(group_id) {
  group_id <- mc_chr1(group_id, "group id")
  row <- mc_provenance$external_assets[[group_id]]
  if (is.null(row)) {
    stop(
      "Unknown external clock group: ",
      group_id,
      "\nKnown groups: ",
      paste(mc_external_groups(), collapse = ", "),
      call. = FALSE
    )
  }
  mc_validate_row(row, group_id)
}

# "all" or a vector of known group ids; reports every bad id at once.
mc_resolve_groups <- function(groups) {
  if (is.null(groups) || identical(groups, "all") || !length(groups)) {
    return(mc_external_groups())
  }
  groups <- unique(as.character(groups))
  unknown <- setdiff(groups, mc_external_groups())
  if (length(unknown)) {
    stop(
      "Unknown external clock group(s): ",
      paste(unknown, collapse = ", "),
      "\nKnown groups: ",
      paste(mc_external_groups(), collapse = ", "),
      call. = FALSE
    )
  }
  groups
}

# Release slug: option > env > compiled default.
mc_release_repo <- function() {
  slug <- getOption("methylCIPHER.release_repo")
  if (is.null(slug) || !length(slug) || is.na(slug[[1L]]) || !nzchar(slug[[1L]])) {
    slug <- Sys.getenv("METHYLCIPHER_RELEASE_REPO", unset = "")
  }
  if (!nzchar(slug[[1L]])) {
    slug <- MC_RELEASE_REPO
  }
  slug <- mc_chr1(slug, "The release repo")
  if (!grepl("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", slug)) {
    stop(
      "Release repo must look like 'owner/repo', got: ",
      slug,
      call. = FALSE
    )
  }
  slug
}

# Public release-asset URL from the registry row (no API/auth).
mc_asset_url <- function(row) {
  sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    mc_release_repo(),
    row$release_tag,
    row$file
  )
}

# --- cache location ---

# Cache dir: option methylCIPHER.cache_dir > METHYLCIPHER_CACHE_DIR > R_user_dir.
# create=TRUE makes the directory (download path only, after consent).
mc_cache_dir <- function(create = FALSE) {
  path <- getOption("methylCIPHER.cache_dir")
  if (is.null(path) || !length(path) || is.na(path[[1L]]) || !nzchar(path[[1L]])) {
    path <- Sys.getenv("METHYLCIPHER_CACHE_DIR", unset = "")
  }
  if (!nzchar(path[[1L]])) {
    path <- tools::R_user_dir("methylCIPHER", which = "cache")
  }
  path <- fs::path_expand(mc_chr1(path, "The cache directory"))
  if (isTRUE(create)) {
    fs::dir_create(path)
  }
  path
}

# NULL path -> resolved cache dir.
mc_cache_path_arg <- function(path, create = FALSE) {
  if (is.null(path)) {
    return(mc_cache_dir(create = create))
  }
  path <- fs::path_expand(mc_chr1(path, "`path`"))
  if (isTRUE(create)) {
    fs::dir_create(path)
  }
  path
}

# --- consent ---

# Consent gate for filesystem side effects. ask=FALSE asserts consent; non-interactive refuses.
mc_confirm <- function(prompt, ask, action = "this operation") {
  if (!isTRUE(ask)) {
    return(TRUE)
  }
  if (!interactive()) {
    stop(
      "Refusing to run ",
      action,
      " without confirmation in a non-interactive session.\n",
      "Pass ask = FALSE to consent explicitly (e.g. in a script or CI job).",
      call. = FALSE
    )
  }
  answer <- utils::askYesNo(prompt, default = FALSE)
  isTRUE(answer)
}

mc_bytes <- function(x) {
  format(structure(as.numeric(x), class = "object_size"), units = "auto")
}

# --- status ---

# Query which external packs are cached. Never downloads or writes.
mc_cache_status <- function(groups = "all", path = NULL) {
  groups <- mc_resolve_groups(groups)
  dir <- mc_cache_path_arg(path)
  rows <- lapply(groups, function(gid) {
    row <- mc_asset_row(gid)
    fp <- fs::path(dir, row$file)
    data.frame(
      group_id = gid,
      file = row$file,
      cached = fs::file_exists(fp),
      size_bytes = row$size_bytes,
      n_clocks = if (is.null(row$n_clocks)) {
        NA_integer_
      } else {
        as.integer(row$n_clocks)
      },
      path = as.character(fp),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# --- download ---

# Fetch one asset to a same-dir staging file, verify sha256, then atomic rename.
mc_download_one <- function(row, dir, quiet = FALSE) {
  url <- mc_asset_url(row)
  dest <- fs::path(dir, row$file)
  tmp <- fs::path(dir, paste0(row$file, ".part-", Sys.getpid()))
  withr::defer(try(fs::file_delete(tmp), silent = TRUE))

  # Large packs need more than download.file()'s default 60s whole-transfer timeout.
  withr::local_options(list(timeout = max(getOption("timeout", 60L), 1800L)))

  if (!quiet) {
    message(
      "Downloading ",
      row$group_id,
      " (",
      mc_bytes(row$size_bytes),
      ") from ",
      url
    )
  }

  status <- tryCatch(
    utils::download.file(url, destfile = tmp, mode = "wb", quiet = quiet),
    error = function(e) e
  )
  if (inherits(status, "condition")) {
    stop(
      "Download failed for ",
      row$group_id,
      ": ",
      conditionMessage(status),
      "\nURL: ",
      url,
      call. = FALSE
    )
  }
  if (!fs::file_exists(tmp)) {
    stop("Download produced no file for ", row$group_id, call. = FALSE)
  }

  actual <- digest::digest(file = tmp, algo = "sha256")
  if (!identical(actual, row$file_sha256)) {
    stop(
      "Checksum mismatch for ",
      row$group_id,
      " -- the downloaded file is not the one this version of methylCIPHER expects.\n",
      "  expected sha256: ",
      row$file_sha256,
      "\n  actual   sha256: ",
      actual,
      "\nThe partial file was discarded. Retry, or report this if it persists.",
      call. = FALSE
    )
  }

  fs::file_move(tmp, dest)
  dest
}

# Download external clock packs into the cache (sha256-verified, content-addressed).
# ask=FALSE consents without a prompt (required non-interactively).
mc_data_download <- function(
  groups = "all",
  path = NULL,
  force = FALSE,
  ask = TRUE,
  quiet = FALSE
) {
  groups <- mc_resolve_groups(groups)
  dir <- mc_cache_path_arg(path)

  status <- mc_cache_status(groups, path = dir)
  todo <- if (isTRUE(force)) status else status[!status$cached, , drop = FALSE]

  if (!nrow(todo)) {
    if (!quiet) {
      message(
        "All requested clock data already cached in ",
        dir,
        " (use force = TRUE to re-download)."
      )
    }
    return(invisible(stats::setNames(status$path, status$group_id)))
  }

  ok <- mc_confirm(
    prompt = paste0(
      "methylCIPHER will download ",
      nrow(todo),
      " clock data file(s) (",
      mc_bytes(sum(todo$size_bytes, na.rm = TRUE)),
      ") to:\n  ",
      dir,
      "\nProceed?"
    ),
    ask = ask,
    action = "a download"
  )
  if (!ok) {
    message("Download cancelled. Nothing was written.")
    return(invisible(stats::setNames(character(0), character(0))))
  }

  fs::dir_create(dir)

  for (gid in todo$group_id) {
    mc_download_one(mc_asset_row(gid), dir = dir, quiet = quiet)
    if (!quiet) {
      message("Cached ", gid)
    }
  }

  final <- mc_cache_status(groups, path = dir)
  invisible(stats::setNames(final$path, final$group_id))
}

# --- clear ---

# Delete cached external packs for the given groups (including superseded hashes).
# ask=FALSE consents without a prompt (required non-interactively).
mc_data_clear <- function(groups = "all", path = NULL, ask = TRUE) {
  groups <- mc_resolve_groups(groups)
  dir <- mc_cache_path_arg(path)
  none <- stats::setNames(character(0), NULL)

  if (!fs::dir_exists(dir)) {
    message("Nothing to clear: ", dir, " does not exist.")
    return(invisible(none))
  }

  # Match <group>-<hex>.qs2 only (including superseded packs), never a loose prefix glob.
  present <- fs::dir_ls(dir, type = "file")
  stems <- tolower(fs::path_file(present))
  keep <- Reduce(
    `|`,
    lapply(groups, function(gid) {
      grepl(
        paste0("^", tolower(gid), "-([0-9a-f]{32}|[0-9a-f]{64})\\.qs2$"),
        stems
      )
    }),
    init = rep(FALSE, length(stems))
  )
  victims <- unique(as.character(present[keep]))

  if (!length(victims)) {
    message("Nothing to clear for: ", paste(groups, collapse = ", "))
    return(invisible(none))
  }

  total <- sum(as.numeric(fs::file_size(victims)))
  ok <- mc_confirm(
    prompt = paste0(
      "Delete ",
      length(victims),
      " cached file(s) (",
      mc_bytes(total),
      ") from:\n  ",
      dir,
      "\n  ",
      paste(fs::path_file(victims), collapse = "\n  "),
      "\nProceed?"
    ),
    ask = ask,
    action = "a delete"
  )
  if (!ok) {
    message("Nothing was deleted.")
    return(invisible(none))
  }

  fs::file_delete(victims)
  message("Deleted ", length(victims), " file(s) from ", dir)
  invisible(victims)
}

# --- load ---

# Load an external pack from cache; never downloads. Errors with the install command if missing.
external_pack <- function(group_id, path = NULL) {
  row <- mc_asset_row(group_id)
  dir <- mc_cache_path_arg(path)
  fp <- fs::path(dir, row$file)
  if (!fs::file_exists(fp)) {
    stop(
      "Clock data for ",
      group_id,
      " is not downloaded.\n",
      "Run:  mc_data_download(\"",
      group_id,
      "\")\n",
      "Expected file: ",
      fp,
      " (",
      mc_bytes(row$size_bytes),
      ")",
      call. = FALSE
    )
  }

  pack <- tryCatch(
    qs2::qs_read(fp, validate_checksum = TRUE),
    error = function(e) {
      stop(
        "Failed to read cached clock data for ",
        group_id,
        " (",
        fp,
        "): ",
        conditionMessage(e),
        "\nThe file may be corrupt. Re-download with:\n",
        "  mc_data_download(\"",
        group_id,
        "\", force = TRUE)",
        call. = FALSE
      )
    }
  )

  # Structural identity check on the decoded pack (not a re-hash of the R object).
  mismatch <- function(field, expected, actual) {
    stop(
      "Clock data for ",
      group_id,
      " does not match what this version of methylCIPHER expects (",
      field,
      ": expected ",
      expected,
      ", found ",
      actual,
      ").\nRe-download with:\n  mc_data_clear(\"",
      group_id,
      "\", ask = FALSE)\n  mc_data_download(\"",
      group_id,
      "\", ask = FALSE)",
      call. = FALSE
    )
  }
  checks <- list(
    group_id = list(row$group_id, pack$group_id),
    encoding = list(row$encoding, pack$encoding),
    encoding_version = list(row$encoding_version, pack$encoding_version),
    n_cpgs = list(row$n_cpgs, length(pack$cpgs))
  )
  for (field in names(checks)) {
    expected <- checks[[field]][[1L]]
    actual <- checks[[field]][[2L]]
    if (is.null(expected)) {
      next
    }
    if (is.null(actual)) {
      mismatch(field, expected, "<absent>")
    }
    if (!identical(as.character(expected), as.character(actual))) {
      mismatch(field, expected, actual)
    }
  }

  pack
}
