# external clock-data packs: content-addressed qs2 files fetched on demand

MC_DEFAULT_RELEASE_REPO <- "hhp94/methylCIPHERv2"

mc_external_groups <- function() {
  assets <- mc_provenance[["external_assets"]]
  if (is.null(assets)) character(0) else names(assets)
}

# one provenance row for an external group
mc_asset <- function(group_id) {
  row <- mc_provenance[["external_assets"]][[group_id]]
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

# "all" or a vector of known group ids
mc_resolve_groups <- function(groups) {
  if (is.null(groups) || identical(groups, "all") || !length(groups)) {
    return(mc_external_groups())
  }
  groups <- unique(as.character(groups))
  for (g in groups) {
    mc_asset(g)
  } # errors on any unknown id
  groups
}

# public release-asset URL (option override for forks/testing)
mc_asset_url <- function(row) {
  repo <- getOption("mc.release_repo", MC_DEFAULT_RELEASE_REPO)
  sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    repo,
    row[["release_tag"]],
    row[["file"]]
  )
}

# CRAN-sanctioned per-user cache directory
mc_default_cache_dir <- function() {
  as.character(fs::path_expand(
    tools::R_user_dir("methylCIPHERv2", which = "cache")
  ))
}

# a usable path setting: one non-empty, non-NA string
is_path_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

# active cache dir: assets arg, session option, env, then default
mc_cache_dir <- function(assets = NULL) {
  if (!is.null(assets)) {
    if (!is_path_string(assets)) {
      stop(
        "`assets` must be NULL or a single cache-dir path; got ",
        class(assets)[[1L]],
        " of length ",
        length(assets),
        ".\nA loaded pack names no cache dir -- pass one only to load_mc_assets().",
        call. = FALSE
      )
    }
    return(as.character(fs::path_expand(assets)))
  }
  opt <- getOption("mc.cache_dir")
  if (is_path_string(opt)) {
    return(as.character(fs::path_expand(opt)))
  }
  env <- Sys.getenv("MC_CACHE_DIR", unset = "")
  if (is_path_string(env)) {
    return(as.character(fs::path_expand(env)))
  }
  mc_default_cache_dir()
}

# cache paths for a set of provenance rows, in order
mc_pack_paths <- function(dir, rows) {
  if (!length(rows)) {
    return(character(0))
  }
  files <- vapply(rows, function(r) r[["file"]], character(1))
  as.character(fs::path(dir, files))
}

# aligned "<label>  <size>" block for the consent prompts, with a total when
# there is more than one row
mc_manifest <- function(labels, sizes) {
  if (!length(labels)) {
    return("")
  }
  sizes <- as.numeric(sizes)
  cells <- format(fs::fs_bytes(c(sizes, sum(sizes))))
  w <- max(nchar(labels), nchar("total"))
  rows <- sprintf("  %-*s  %s", w, labels, cells[seq_along(labels)])
  if (length(labels) > 1L) {
    rows <- c(rows, sprintf("  %-*s  %s", w, "total", cells[[length(cells)]]))
  }
  paste(rows, collapse = "\n")
}

# fetch one pack: stage, validate by reading, atomic rename -- returns path + payload
mc_fetch <- function(row, dir) {
  fs::dir_create(dir)
  url <- mc_asset_url(row)
  dest <- fs::path(dir, row[["file"]])
  tmp <- paste0(as.character(dest), ".part")
  on.exit(if (fs::file_exists(tmp)) fs::file_delete(tmp), add = TRUE)

  old_to <- options(timeout = max(getOption("timeout", 60L), 1800L))
  on.exit(options(old_to), add = TRUE)

  status <- tryCatch(
    utils::download.file(
      url,
      destfile = tmp,
      mode = "wb",
      quiet = !interactive()
    ),
    error = function(e) {
      stop(
        "Download failed for ",
        row[["group_id"]],
        ": ",
        conditionMessage(e),
        "\nURL: ",
        url,
        call. = FALSE
      )
    }
  )
  # download.file also fails via status code
  if (!identical(as.integer(status), 0L)) {
    stop(
      "Download failed for ",
      row[["group_id"]],
      " (status ",
      status,
      ").\nURL: ",
      url,
      call. = FALSE
    )
  }
  payload <- qs2::qs_read(tmp, validate_checksum = TRUE)
  fs::file_move(tmp, dest) # errors if the rename fails
  list(path = as.character(dest), payload = payload)
}

# consent for downloading missing packs, or stop
mc_consent <- function(rows, dir, ask) {
  if (!length(rows) || !ask) {
    return(invisible(TRUE))
  }
  ids <- vapply(rows, function(r) r[["group_id"]], character(1))
  sizes <- vapply(rows, function(r) as.numeric(r[["size_bytes"]]), numeric(1))
  manifest <- mc_manifest(ids, sizes)

  if (!interactive()) {
    stop(
      "Refusing to download ",
      length(rows),
      " clock-data pack(s) into\n  ",
      dir,
      "\nwithout confirmation in a non-interactive session.\n\n",
      manifest,
      "\n\nPass `ask = FALSE` to consent, or pre-stage the file(s) and point ",
      "`assets` at them.",
      call. = FALSE
    )
  }
  ok <- utils::askYesNo(paste0(
    "Download ",
    length(rows),
    " clock-data pack(s) into\n  ",
    dir,
    "\n\n",
    manifest,
    "\n\nProceed?"
  ))
  if (!isTRUE(ok)) {
    stop(
      "Download declined for ",
      paste(ids, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# pre-fetch packs into the cache (skips already-present files)
mc_data_download <- function(groups = "all", assets = NULL, ask = TRUE) {
  checkmate::assert_flag(ask)
  groups <- mc_resolve_groups(groups)
  dir <- mc_cache_dir(assets)
  rows <- lapply(groups, mc_asset)
  files <- mc_pack_paths(dir, rows)
  missing <- unname(!fs::file_exists(files))
  if (any(missing)) {
    mc_consent(rows[missing], dir, ask)
    for (i in which(missing)) {
      files[[i]] <- mc_fetch(rows[[i]], dir)[["path"]]
    }
  }
  invisible(stats::setNames(files, groups))
}

# which packs are present in the cache (query only), named by group id
mc_cached_files <- function(groups = "all", assets = NULL) {
  groups <- mc_resolve_groups(groups)
  files <- mc_pack_paths(mc_cache_dir(assets), lapply(groups, mc_asset))
  files <- stats::setNames(files, groups)
  files[fs::file_exists(files)]
}

# canonicalize assets: NULL (open), cache-dir path, or loaded pack registry
mc_canonicalize_assets <- function(assets) {
  if (is.null(assets)) {
    return(NULL)
  }
  if (is.character(assets)) {
    if (!is_path_string(assets)) {
      stop("`assets` path must be a single non-empty string.", call. = FALSE)
    }
    return(assets)
  }
  is_pack <- function(x) is.list(x) && !is.null(x[["group_id"]])
  if (is_pack(assets)) {
    return(stats::setNames(list(assets), assets[["group_id"]]))
  }
  if (
    is.list(assets) &&
      length(assets) &&
      all(vapply(assets, is_pack, logical(1)))
  ) {
    return(stats::setNames(
      assets,
      vapply(assets, function(p) as.character(p[["group_id"]]), character(1))
    ))
  }
  stop(
    "`assets` must be NULL, a cache-dir path, a loaded pack, or a list of loaded packs.",
    call. = FALSE
  )
}

# load packs for needed groups (open set may download, closed set never does)
load_mc_assets <- function(groups, assets = NULL, ask = TRUE) {
  checkmate::assert_flag(ask)
  groups <- unique(as.character(groups))
  groups <- groups[nzchar(groups)]
  if (identical(groups, "all")) {
    groups <- mc_external_groups()
  }
  if (!length(groups)) {
    return(stats::setNames(list(), character(0)))
  }
  rows <- lapply(groups, mc_asset) # errors on any unknown id

  canon <- mc_canonicalize_assets(assets)

  if (is.list(canon)) {
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

  # path = closed set (no download), NULL = open set
  closed <- !is.null(canon)
  dir <- mc_cache_dir(canon)
  files <- mc_pack_paths(dir, rows)
  missing <- unname(!fs::file_exists(files))
  packs <- vector("list", length(groups))

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
      got <- mc_fetch(rows[[i]], dir)
      files[[i]] <- got[["path"]]
      packs[[i]] <- got[["payload"]] # the fetch already validated this read
    }
  }

  unread <- vapply(packs, is.null, logical(1))
  packs[unread] <- lapply(files[unread], qs2::qs_read, validate_checksum = TRUE)
  stats::setNames(packs, groups)
}

# consent for deleting cached packs -- TRUE = go ahead, FALSE = user declined
mc_consent_delete <- function(files, dir, ask) {
  if (!ask) {
    return(TRUE)
  }
  sizes <- as.numeric(fs::file_size(files))
  # prefer group-id labels over content-addressed filenames
  labels <- names(files)
  if (is.null(labels)) {
    labels <- as.character(fs::path_file(files))
  }
  manifest <- mc_manifest(labels, sizes)

  if (!interactive()) {
    stop(
      "Refusing to delete ",
      length(files),
      " cached clock-data pack(s) from\n  ",
      dir,
      "\nwithout confirmation in a non-interactive session.\n\n",
      manifest,
      "\n\nPass `ask = FALSE` to consent.",
      call. = FALSE
    )
  }
  isTRUE(utils::askYesNo(paste0(
    "Delete ",
    length(files),
    " cached clock-data pack(s) from\n  ",
    dir,
    "\n\n",
    manifest,
    "\n\nProceed?"
  )))
}

# remove cached external packs -- never deletes unprompted
clear_mc_cache <- function(groups = "all", assets = NULL, ask = TRUE) {
  checkmate::assert_flag(ask)
  dir <- mc_cache_dir(assets)
  files <- mc_cached_files(groups, assets)
  if (!length(files)) {
    message("No cached clock data to clear in ", dir, ".")
    return(invisible(character(0)))
  }
  if (!mc_consent_delete(files, dir, ask)) {
    message("Deletion declined; nothing removed from ", dir, ".")
    return(invisible(character(0)))
  }
  freed <- sum(as.numeric(fs::file_size(files)))
  fs::file_delete(files)
  failed <- files[fs::file_exists(files)]
  if (length(failed)) {
    stop(
      "Could not remove cached clock data:\n  ",
      paste(failed, collapse = "\n  "),
      call. = FALSE
    )
  }
  message(
    "Removed ",
    length(files),
    " cached clock-data pack(s) (",
    format(fs::fs_bytes(freed)),
    ") from ",
    dir,
    "."
  )
  invisible(files)
}
