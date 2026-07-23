# external clock-data packs (content-addressed qs2, fetched on demand)

MC_DEFAULT_RELEASE_REPO <- "hhp94/methylCIPHERv2"

mc_external_groups <- function() {
  assets <- mc_provenance[["external_assets"]]
  if (is.null(assets)) character(0) else names(assets)
}

# provenance row for one external group
mc_asset <- function(group_id) {
  row <- mc_provenance[["external_assets"]][[group_id]]
  if (is.null(row)) {
    cli::cli_abort(
      c(
        "{.val {group_id}} is not an external clock group.",
        "i" = "Known groups: {.val {mc_external_groups()}}."
      ),
      call = NULL
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
  }
  groups
}

# public release-asset URL
mc_asset_url <- function(row) {
  repo <- getOption("mc.release_repo", MC_DEFAULT_RELEASE_REPO)
  sprintf(
    "https://github.com/%s/releases/download/%s/%s",
    repo,
    row[["release_tag"]],
    row[["file"]]
  )
}

# default per-user cache dir
mc_default_cache_dir <- function() {
  as.character(fs::path_expand(
    tools::R_user_dir("methylCIPHERv2", which = "cache")
  ))
}

# single non-empty path string
is_path_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

# active cache dir: assets arg, option, env, then default
mc_cache_dir <- function(assets = NULL) {
  if (!is.null(assets)) {
    if (!is_path_string(assets)) {
      cli::cli_abort(
        c(
          "{.arg assets} must be {.code NULL} or a single cache-dir path
           (got {class(assets)[[1L]]} of length {length(assets)}).",
          "i" = "A loaded pack is not a cache dir -- pass packs only to
                 {.fn load_mc_assets}."
        ),
        call = NULL
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

# cache paths for provenance rows, in order
mc_pack_paths <- function(dir, rows) {
  if (!length(rows)) {
    return(character(0))
  }
  files <- vapply(rows, function(r) r[["file"]], character(1))
  as.character(fs::path(dir, files))
}

# label + size block for consent prompts
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

# stage, validate, atomic rename -- returns path + payload
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
      cli::cli_abort(
        c(
          "Download failed for {.val {row[['group_id']]}}:
           {conditionMessage(e)}.",
          "i" = "URL: {.url {url}}"
        ),
        call = NULL
      )
    }
  )
  if (!identical(as.integer(status), 0L)) {
    cli::cli_abort(
      c(
        "Download failed for {.val {row[['group_id']]}}
         (status {status}).",
        "i" = "URL: {.url {url}}"
      ),
      call = NULL
    )
  }
  payload <- qs2::qs_read(tmp, validate_checksum = TRUE)
  fs::file_move(tmp, dest)
  list(path = as.character(dest), payload = payload)
}

# consent for downloading missing packs
mc_consent <- function(rows, dir, ask) {
  if (!length(rows) || !ask) {
    return(invisible(TRUE))
  }
  ids <- vapply(rows, function(r) r[["group_id"]], character(1))
  sizes <- vapply(rows, function(r) as.numeric(r[["size_bytes"]]), numeric(1))
  manifest <- mc_manifest(ids, sizes)

  if (!interactive()) {
    cli::cli_abort(
      c(
        "Can't download {length(rows)} clock-data pack{?s} without
         confirmation in a non-interactive session.",
        "i" = "Cache dir: {.path {dir}}",
        " " = "{manifest}",
        "i" = "Pass {.code ask = FALSE} to consent, or pre-stage the files
               and point {.arg assets} at them."
      ),
      call = NULL
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
    cli::cli_abort(
      "Download declined for {.val {ids}}.",
      call = NULL
    )
  }
  invisible(TRUE)
}

# pre-fetch packs into the cache
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

# packs present in the cache, named by group id
mc_cached_files <- function(groups = "all", assets = NULL) {
  groups <- mc_resolve_groups(groups)
  files <- mc_pack_paths(mc_cache_dir(assets), lapply(groups, mc_asset))
  files <- stats::setNames(files, groups)
  files[fs::file_exists(files)]
}

# NULL (open), cache-dir path, or loaded pack registry
mc_canonicalize_assets <- function(assets) {
  if (is.null(assets)) {
    return(NULL)
  }
  if (is.character(assets)) {
    if (!is_path_string(assets)) {
      cli::cli_abort(
        "{.arg assets} path must be a single non-empty string.",
        call = NULL
      )
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
  cli::cli_abort(
    "{.arg assets} must be {.code NULL}, a cache-dir path, a loaded pack,
     or a list of loaded packs.",
    call = NULL
  )
}

# load packs for needed groups
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
  rows <- lapply(groups, mc_asset)

  canon <- mc_canonicalize_assets(assets)

  if (is.list(canon)) {
    packs <- lapply(groups, function(g) {
      pack <- canon[[g]]
      if (is.null(pack)) {
        cli::cli_abort(
          c(
            "Need pack {.val {g}}, but it is not in {.arg assets}.",
            "i" = "Closed set -- no download. Include it in {.arg assets}
                   or pass a cache dir / {.code NULL}."
          ),
          call = NULL
        )
      }
      pack
    })
    extra <- setdiff(names(canon), groups)
    if (length(extra)) {
      cli::cli_warn(
        "Ignoring unused pack{?s} in {.arg assets}: {.val {extra}}.",
        call = NULL
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
      cli::cli_abort(
        c(
          "Pack{?s} {.val {groups[missing]}} not found in
           {.path {dir}}.",
          "i" = "Closed set -- no download. Stage the file{?s} there, or
                 pass {.code assets = NULL} to allow download."
        ),
        call = NULL
      )
    }
    mc_consent(rows[missing], dir, ask)
    for (i in which(missing)) {
      got <- mc_fetch(rows[[i]], dir)
      files[[i]] <- got[["path"]]
      packs[[i]] <- got[["payload"]]
    }
  }

  unread <- vapply(packs, is.null, logical(1))
  packs[unread] <- lapply(files[unread], qs2::qs_read, validate_checksum = TRUE)
  stats::setNames(packs, groups)
}

# consent for deleting cached packs
mc_consent_delete <- function(files, dir, ask) {
  if (!ask) {
    return(TRUE)
  }
  sizes <- as.numeric(fs::file_size(files))
  labels <- names(files)
  if (is.null(labels)) {
    labels <- as.character(fs::path_file(files))
  }
  manifest <- mc_manifest(labels, sizes)

  if (!interactive()) {
    cli::cli_abort(
      c(
        "Can't delete {length(files)} cached pack{?s} without confirmation
         in a non-interactive session.",
        "i" = "Cache dir: {.path {dir}}",
        " " = "{manifest}",
        "i" = "Pass {.code ask = FALSE} to consent."
      ),
      call = NULL
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

# remove cached external packs
clear_mc_cache <- function(groups = "all", assets = NULL, ask = TRUE) {
  checkmate::assert_flag(ask)
  dir <- mc_cache_dir(assets)
  files <- mc_cached_files(groups, assets)
  if (!length(files)) {
    cli::cli_inform("No cached clock data to clear in {.path {dir}}.")
    return(invisible(character(0)))
  }
  if (!mc_consent_delete(files, dir, ask)) {
    cli::cli_inform("Deletion declined -- nothing removed from {.path {dir}}.")
    return(invisible(character(0)))
  }
  freed <- sum(as.numeric(fs::file_size(files)))
  fs::file_delete(files)
  failed <- files[fs::file_exists(files)]
  if (length(failed)) {
    cli::cli_abort(
      c(
        "Could not remove {length(failed)} cached file{?s}:",
        bullets(failed)
      ),
      call = NULL
    )
  }
  cli::cli_inform(
    "Removed {length(files)} cached pack{?s}
     ({format(fs::fs_bytes(freed))}) from {.path {dir}}."
  )
  invisible(files)
}
