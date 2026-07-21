# External clock-data cache for SystemsAge, PCClocks, PCBrainAge (content-addressed qs2 packs).
# No silent download; no write outside user cache without consent. Identity is the payload hash.

MC_RELEASE_REPO <- "hhp94/methylCIPHER"

# No session memoisation: load packs once per calc_clocks() call and pass them down.
# ===========================================================================
# validation
# ===========================================================================
# Everything below funnels through mc_asset_row() / the `path` and option readers, so scalar
# checks live here and nowhere else. Without them a character(0) option or an NA registry
# field surfaces as an opaque `if` / list-index error three frames deep.

# A hash written as lowercase hex: 32 for the current payload_hash, 64 for a sha256. Used
# both to validate registry fields and to recognise our own cache filenames.
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

# A registry row is a wire contract compiled into sysdata: if any of it is malformed the
# package cannot safely download or verify anything, so this throws rather than degrading.
# In particular a missing file_sha256 must NEVER silently disable verification -- that would
# turn the one guarantee the download path makes into a no-op.
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
  # The filename is the cache key; a path separator in it would escape the cache dir.
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

# ===========================================================================
# registry
# ===========================================================================

# The external group ids this package version knows about, in registry order.
mc_external_groups <- function() {
  assets <- mc_provenance$external_assets
  if (is.null(assets)) character(0) else names(assets)
}

# One VALIDATED registry row, or a clear error. Every path below starts here, so an id typo
# fails once, early, with the valid set -- never as a 404 or a mystery cache miss -- and a
# malformed row fails before it can be used to fetch or verify anything.
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

# "all" -> every registered group; otherwise validate against the registry. Kept separate
# from mc_asset_row() because the user-facing verbs take a VECTOR and should report every
# bad id at once rather than dying on the first.
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

# Release slug: option > env (same var sync.R uses) > compiled-in default. The option/env
# hooks exist so a fork or a mirror can be pointed at without patching the package.
mc_release_repo <- function() {
  slug <- getOption("methylCIPHER.release_repo")
  if (is.null(slug) || !length(slug) || is.na(slug[[1L]]) || !nzchar(slug[[1L]])) {
    slug <- Sys.getenv("METHYLCIPHER_RELEASE_REPO", unset = "")
  }
  if (!nzchar(slug[[1L]])) {
    slug <- MC_RELEASE_REPO
  }
  slug <- mc_chr1(slug, "The release repo")
  # An override goes straight into a URL, so require the owner/repo shape rather than
  # letting a stray value produce a nonsense request.
  if (!grepl("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", slug)) {
    stop(
      "Release repo must look like 'owner/repo', got: ",
      slug,
      call. = FALSE
    )
  }
  slug
}

# Release tag is the filename stem <group>-<hash> (a bare 40/64-hex tag is rejected by GitHub;
# sync.R sets this), so the URL is fully determined by the registry row. No API call, no listing,
# no auth: a plain public asset GET.
mc_asset_url <- function(row) {
  sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    mc_release_repo(),
    row$release_tag,
    row$file
  )
}

# ===========================================================================
# cache location
# ===========================================================================

#' Location of the methylCIPHER data cache
#'
#' Where the large external clock packs (SystemsAge, PCClocks, PCBrainAge) are stored on
#' disk. Resolution order:
#'
#' 1. `getOption("methylCIPHER.cache_dir")`
#' 2. the `METHYLCIPHER_CACHE_DIR` environment variable
#' 3. `tools::R_user_dir("methylCIPHER", "cache")`, the standard per-user cache location
#'
#' To make a custom location permanent, put
#' `options(methylCIPHER.cache_dir = "/my/path")` in your `.Rprofile`, or set
#' `METHYLCIPHER_CACHE_DIR` in `.Renviron`.
#'
#' @param create Create the directory if it does not exist? Defaults to `FALSE` -- this
#'   function is a pure query unless you ask otherwise. [mc_data_download()] is the only
#'   caller that passes `TRUE`, and only after consent.
#'
#' @return The cache directory path, as an [fs::path()].
#' @export
#' @seealso [mc_data_download()], [mc_data_clear()], [mc_cache_status()]
#' @examples
#' mc_cache_dir()
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

# Normalize the `path =` argument shared by the verbs below: NULL -> the resolved cache dir.
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

# ===========================================================================
# consent
# ===========================================================================

# The single consent gate for every filesystem side effect (create dir, download, delete).
# Interactive -> a real prompt, default NO. Non-interactive -> refuse and name the argument
# that grants consent, rather than silently proceeding: a script must SAY it may write.
# `ask = FALSE` is the caller asserting consent and is honoured in both modes.
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

# ===========================================================================
# status
# ===========================================================================

#' Status of the cached external clock packs
#'
#' Reports, for each external clock group, the exact file this package version expects and
#' whether it is present in the cache. Purely a query: it never downloads, deletes, or
#' creates anything.
#'
#' @param groups Character vector of group ids, or `"all"` (default) for every external
#'   group.
#' @param path Cache directory. `NULL` (default) uses [mc_cache_dir()].
#'
#' @return A `data.frame` with one row per group: `group_id`, `file`, `cached` (logical),
#'   `size_bytes` (expected download size), `n_clocks`, and `path` (where the file is or
#'   would be).
#' @export
#' @seealso [mc_data_download()], [mc_data_clear()]
#' @examples
#' mc_cache_status()
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

# ===========================================================================
# download
# ===========================================================================

# Fetch one asset to a scratch file, verify, then move into place. The staging file lives in
# the DESTINATION directory, not tempdir(), so the final step is a same-filesystem rename --
# atomic, so a killed download can never leave a truncated file under the real name that a
# later run would happily accept as cached. withr::defer cleans the scratch file on every
# exit path, error or not.
mc_download_one <- function(row, dir, quiet = FALSE) {
  url <- mc_asset_url(row)
  dest <- fs::path(dir, row$file)
  tmp <- fs::path(dir, paste0(row$file, ".part-", Sys.getpid()))
  withr::defer(try(fs::file_delete(tmp), silent = TRUE))

  # download.file()'s default 60s timeout is measured over the WHOLE transfer, so a 24 MB
  # pack on a slow link fails at 60s through no fault of the server. Raise it locally only.
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

  # Unconditional: mc_validate_row() has already guaranteed a well-formed sha256, so there
  # is no "no checksum recorded" branch that could quietly skip verification.
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

#' Download the external clock data packs
#'
#' The SystemsAge, PCClocks, and PCBrainAge clocks depend on weight matrices far too large
#' to ship inside a CRAN package, so they are published as release assets and downloaded
#' once into a local cache. Everything else in methylCIPHER works without this.
#'
#' Files are content-addressed: the name carries a hash of the pack contents, and every
#' download is verified against the SHA-256 recorded in the package. A file that is already
#' present is left alone unless `force = TRUE`.
#'
#' @param groups Character vector of group ids to download, or `"all"` (default). See
#'   [mc_cache_status()] for the available groups.
#' @param path Destination directory. `NULL` (default) uses [mc_cache_dir()].
#' @param force Re-download packs that are already cached? Defaults to `FALSE`.
#' @param ask Ask for confirmation before writing to disk? Defaults to `TRUE`. In a
#'   non-interactive session this errors instead of prompting -- pass `ask = FALSE` to
#'   consent explicitly from a script.
#' @param quiet Suppress progress messages.
#'
#' @return Invisibly, a named character vector of cached file paths (one per requested
#'   group).
#' @export
#' @seealso [mc_cache_status()], [mc_data_clear()], [mc_cache_dir()]
#' @examples
#' \dontrun{
#' # everything, with a confirmation prompt
#' mc_data_download()
#'
#' # one group, no prompt (scripts / CI)
#' mc_data_download("SystemsAge", ask = FALSE)
#' }
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

# ===========================================================================
# clear
# ===========================================================================

#' Remove cached external clock data
#'
#' Deletes the downloaded clock packs from the cache. This is the counterpart to
#' [mc_data_download()]: nothing methylCIPHER writes to disk survives it.
#'
#' Files from older package versions are removed too. Because pack filenames carry a
#' content hash, upgrading methylCIPHER leaves the previous pack behind as dead weight;
#' clearing a group removes every `<group>-*.qs2` in the cache, not only the file the
#' current version expects.
#'
#' @param groups Character vector of group ids to clear, or `"all"` (default).
#' @param path Cache directory. `NULL` (default) uses [mc_cache_dir()].
#' @param ask Ask for confirmation before deleting? Defaults to `TRUE`. In a
#'   non-interactive session this errors instead of prompting -- pass `ask = FALSE` to
#'   consent explicitly.
#'
#' @return Invisibly, a character vector of the deleted file paths.
#' @export
#' @seealso [mc_data_download()], [mc_cache_status()]
#' @examples
#' \dontrun{
#' mc_data_clear("PCClocks")
#' mc_data_clear(ask = FALSE)
#' }
mc_data_clear <- function(groups = "all", path = NULL, ask = TRUE) {
  groups <- mc_resolve_groups(groups)
  dir <- mc_cache_path_arg(path)
  none <- stats::setNames(character(0), NULL)

  if (!fs::dir_exists(dir)) {
    message("Nothing to clear: ", dir, " does not exist.")
    return(invisible(none))
  }

  # Match the group prefix rather than the CURRENT filename, so superseded packs go too --
  # but only files that match our content-addressed naming exactly (<group>-<hex>.qs2). A
  # loose "<group>-*.qs2" would delete a user's own systemsage-my-cohort.qs2 if they pointed
  # the cache at a shared directory. Filtering on the basename rather than globbing the full
  # path also keeps a cache directory with glob metacharacters in its name harmless.
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

# ===========================================================================
# load (the runtime entry point)
# ===========================================================================

# Load an external group's pack. Never downloads -- errors with the install command if missing.
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

  # Identity check on the DECODED pack. Deliberately structural rather than a re-hash of the
  # object (see the header note on payload_hash): these four fields are what a scorer
  # actually relies on, they are stable across R and rlang versions, and they catch the
  # failure that matters -- a file that is readable and correctly named but is not the pack
  # this package version was built against. Bit rot is already covered by qs2's own checksum
  # above, and substitution by the sha256 check at download time.
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
