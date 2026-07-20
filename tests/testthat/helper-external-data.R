# Fixture for the external-data cache tests.
#
# The real packs are 7-23 MB release assets, so the unit tests must never touch the network.
# Instead we build a tiny qs2 payload, compute its real payload_hash + file_sha256 exactly as
# sync.R does, and mock the two registry accessors (mc_asset_row / mc_external_groups) plus
# mc_asset_url so the download path fetches it over file://. Everything downstream --
# filename construction, sha verification, atomic move, qs2 read, payload-hash check -- runs
# unmodified against real bytes on a real filesystem.

# Build one fake pack on disk; returns the registry row it corresponds to. The payload
# carries the same identity fields a real pack does (group_id / encoding / encoding_version /
# cpgs) so external_pack()'s structural check runs for real rather than being vacuous.
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
  # 32 lowercase hex, matching the shape of the real payload_hash.
  phash <- digest::digest(payload, algo = "md5")
  file <- sprintf("%s-%s.qs2", tolower(group), phash)
  src <- fs::path(dir, file)
  qs2::qs_save(payload, src)
  list(
    group_id = group,
    payload_hash = phash,
    release_tag = phash,
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

# Install a fake registry of one or more assets for the duration of the calling test, served
# from a local directory over file://. Returns the rows, invisibly named by group.
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
    # mustWork = FALSE so a deliberately-deleted source still yields a URL and the
    # download itself 404s -- that is the failure path under test, not an argument error.
    mc_asset_url = function(row) {
      paste0("file:///", normalizePath(row$.src, winslash = "/", mustWork = FALSE))
    },
    .env = .env
  )
  invisible(rows)
}
