# Fake external packs for unit tests: tiny qs2 over file://, never the network.

# Build one fake pack on disk; returns the registry row it corresponds to.
fake_asset <- function(dir, group = "FakeGroup", payload = NULL) {
  if (is.null(payload)) {
    payload <- list(
      group_id = group,
      encoding = "canonical_matrices",
      encoding_version = 2L,
      cpgs = c("cg00000029", "cg00000108"),
      coefficient_matrix = matrix(1:4, 2)
    )
  }
  fs::dir_create(dir)
  phash <- digest::digest(payload, algo = "md5")
  file <- sprintf("%s-%s.qs2", tolower(group), phash)
  # Tag = filename stem; bare hex tags are rejected by GitHub.
  rtag <- sub("\\.qs2$", "", file)
  src <- fs::path(dir, file)
  qs2::qs_save(payload, src)
  list(
    group_id = group,
    payload_hash = phash,
    release_tag = rtag,
    file = file,
    file_sha256 = digest::digest(file = src, algo = "sha256"),
    size_bytes = as.numeric(fs::file_size(src)),
    encoding = payload$encoding,
    encoding_version = payload$encoding_version,
    n_clocks = 1L,
    n_cpgs = length(payload$cpgs),
    .payload = payload,
    .src = as.character(src)
  )
}

# Mock registry + file:// download URLs for the duration of the calling test.
local_fake_registry <- function(rows, .env = parent.frame()) {
  if (!is.null(rows$group_id)) {
    rows <- stats::setNames(list(rows), rows$group_id)
  }
  testthat::local_mocked_bindings(
    mc_external_groups = function() names(rows),
    mc_asset_row = function(group_id) {
      row <- rows[[group_id]]
      if (is.null(row)) {
        stop("Unknown external clock group: ", group_id, call. = FALSE)
      }
      row
    },
    # mustWork=FALSE so a deleted source still yields a URL and the download 404s.
    mc_asset_url = function(row) {
      paste0("file:///", normalizePath(row$.src, winslash = "/", mustWork = FALSE))
    },
    .env = .env
  )
  invisible(rows)
}
