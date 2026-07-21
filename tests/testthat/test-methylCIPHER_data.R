# External clock-data cache. Download path uses file://; live network is opt-in.

test_that("mc_cache_dir() resolves option > env > R_user_dir", {
  withr::local_options(methylCIPHER.cache_dir = NULL)
  withr::local_envvar(METHYLCIPHER_CACHE_DIR = NA)
  expect_equal(
    as.character(mc_cache_dir()),
    as.character(fs::path_expand(tools::R_user_dir("methylCIPHER", "cache")))
  )

  withr::local_envvar(METHYLCIPHER_CACHE_DIR = "from-env")
  expect_equal(as.character(mc_cache_dir()), as.character(fs::path_expand("from-env")))

  withr::local_options(methylCIPHER.cache_dir = "from-option")
  expect_equal(as.character(mc_cache_dir()), as.character(fs::path_expand("from-option")))
})

test_that("mc_cache_dir() is a pure query unless create = TRUE", {
  dir <- fs::path(withr::local_tempdir(), "not-yet")
  withr::local_options(methylCIPHER.cache_dir = as.character(dir))

  expect_false(fs::dir_exists(mc_cache_dir()))
  expect_true(fs::dir_exists(mc_cache_dir(create = TRUE)))
})

test_that("the shipped registry covers the three external groups", {
  expect_setequal(mc_external_groups(), c("SystemsAge", "PCClocks", "PCBrainAge"))
  for (gid in mc_external_groups()) {
    row <- mc_asset_row(gid)
    expect_identical(row$group_id, gid)
    # Filename and release_tag are <group>-<hash>; bare hex tags are rejected by GitHub.
    expect_identical(row$file, sprintf("%s-%s.qs2", tolower(gid), row$payload_hash))
    expect_identical(row$release_tag, sprintf("%s-%s", tolower(gid), row$payload_hash))
    expect_match(row$file_sha256, "^[0-9a-f]{64}$")
    expect_gt(row$size_bytes, 0)
  }
})

test_that("registry lookups reject unknown ids", {
  expect_error(mc_asset_row("NotAClockGroup"), "Unknown external clock group")
  expect_error(mc_asset_row(c("PCClocks", "SystemsAge")), "single non-empty string")
  expect_error(mc_asset_row(NA_character_), "single non-empty string")
  expect_error(mc_asset_row(character(0)), "single non-empty string")
  # Bad ids in a vector are reported by name.
  expect_error(mc_resolve_groups(c("PCClocks", "Nope")), "Nope")
  expect_setequal(mc_resolve_groups("all"), mc_external_groups())
  expect_setequal(mc_resolve_groups(NULL), mc_external_groups())
})

test_that("a malformed registry row is fatal, never silently degraded", {
  good <- mc_asset_row("PCBrainAge")
  expect_identical(mc_validate_row(good, "PCBrainAge")$file, good$file)

  # Missing/malformed checksum must not disable verification.
  expect_error(mc_validate_row(utils::modifyList(good, list(file_sha256 = NULL)), "PCBrainAge"), "file_sha256")
  expect_error(mc_validate_row(utils::modifyList(good, list(file_sha256 = "abc")), "PCBrainAge"), "not a sha256")
  expect_error(
    mc_validate_row(utils::modifyList(good, list(file_sha256 = toupper(good$file_sha256))), "PCBrainAge"),
    "not a sha256"
  )
  # Filename is a cache key; path separators would escape the cache dir.
  expect_error(mc_validate_row(utils::modifyList(good, list(file = "../evil.qs2")), "PCBrainAge"), "bare filename")
  expect_error(mc_validate_row(utils::modifyList(good, list(size_bytes = 0)), "PCBrainAge"), "positive number")
  expect_error(mc_validate_row(utils::modifyList(good, list(release_tag = "")), "PCBrainAge"), "non-empty")
  expect_error(mc_validate_row(good, "SomeOtherGroup"), "carries group_id")
})

test_that("option and argument scalars are validated", {
  withr::local_options(methylCIPHER.cache_dir = c("a", "b"))
  expect_error(mc_cache_dir(), "single non-empty string")

  withr::local_options(methylCIPHER.cache_dir = NULL)
  expect_error(mc_cache_status(path = c("a", "b")), "single non-empty string")

  withr::local_options(methylCIPHER.release_repo = "not-a-slug")
  expect_error(mc_release_repo(), "owner/repo")
  withr::local_options(methylCIPHER.release_repo = "https://github.com/o/r")
  expect_error(mc_release_repo(), "owner/repo")

  # Empty option falls through to the next source.
  withr::local_options(methylCIPHER.release_repo = character(0))
  withr::local_envvar(METHYLCIPHER_RELEASE_REPO = NA)
  expect_identical(mc_release_repo(), MC_RELEASE_REPO)
})

test_that("mc_asset_url() composes the release URL and honours the repo override", {
  row <- mc_asset_row("PCBrainAge")
  withr::local_options(methylCIPHER.release_repo = NULL)
  withr::local_envvar(METHYLCIPHER_RELEASE_REPO = NA)
  expect_equal(
    mc_asset_url(row),
    sprintf(
      "https://github.com/%s/releases/download/%s/%s",
      MC_RELEASE_REPO, row$release_tag, row$file
    )
  )

  withr::local_options(methylCIPHER.release_repo = "someone/fork")
  expect_match(mc_asset_url(row), "^https://github\\.com/someone/fork/releases/")
})

test_that("mc_confirm() refuses to act unprompted in a non-interactive session", {
  # Non-interactive without ask=FALSE must error, never silent write.
  skip_if(interactive())
  expect_error(mc_confirm("proceed?", ask = TRUE, action = "a download"), "non-interactive")
  expect_true(mc_confirm("proceed?", ask = FALSE))
})

test_that("the user-facing verbs inherit the consent gate", {
  skip_if(interactive())
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  expect_error(mc_data_download(path = cache), "non-interactive")
  expect_false(mc_cache_status(path = cache)$cached)

  # Clear also requires consent.
  fs::file_copy(row$.src, fs::path(cache, row$file))
  expect_error(mc_data_clear(path = cache), "non-interactive")
  expect_true(mc_cache_status(path = cache)$cached)
})

test_that("mc_cache_status() reports the expected file and tracks presence", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  st <- mc_cache_status(path = cache)
  expect_s3_class(st, "data.frame")
  expect_identical(
    names(st),
    c("group_id", "file", "cached", "size_bytes", "n_clocks", "path")
  )
  expect_identical(st$file, row$file)
  expect_false(st$cached)

  fs::file_copy(row$.src, fs::path(cache, row$file))
  expect_true(mc_cache_status(path = cache)$cached)
})

test_that("mc_data_download() fetches, verifies, and leaves no scratch files", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  paths <- suppressMessages(mc_data_download(path = cache, ask = FALSE, quiet = TRUE))
  expect_identical(unname(basename(paths)), row$file)
  expect_true(fs::file_exists(fs::path(cache, row$file)))
  expect_equal(as.numeric(fs::file_size(fs::path(cache, row$file))), row$size_bytes)
  # Staging .part-<pid> must never survive.
  expect_false(any(grepl(".part", fs::path_file(fs::dir_ls(cache)), fixed = TRUE)))
})

test_that("mc_data_download() is idempotent unless force = TRUE", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  suppressMessages(mc_data_download(path = cache, ask = FALSE, quiet = TRUE))
  # quiet=FALSE so the skip notice is observable.
  expect_message(mc_data_download(path = cache, ask = FALSE), "already cached")

  # force re-fetches and still verifies.
  suppressMessages(mc_data_download(path = cache, ask = FALSE, force = TRUE, quiet = TRUE))
  expect_identical(external_pack("FakeGroup", path = cache), row$.payload)
})

test_that("a checksum mismatch aborts and leaves the cache untouched", {
  # Truncated/substituted download must never land under the real filename.
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  row$file_sha256 <- strrep("0", 64)
  local_fake_registry(row)

  expect_error(
    suppressMessages(mc_data_download(path = cache, ask = FALSE, quiet = TRUE)),
    "Checksum mismatch"
  )
  expect_length(fs::dir_ls(cache), 0)
})

test_that("a download failure is reported with the URL and leaves nothing behind", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  fs::file_delete(row$.src) # the "server" 404s

  expect_error(
    suppressWarnings(suppressMessages(
      mc_data_download(path = cache, ask = FALSE, quiet = TRUE)
    )),
    "Download failed"
  )
  expect_length(fs::dir_ls(cache), 0)
})

test_that("mc_data_clear() removes superseded packs, not just the current one", {
  # Clear must sweep the whole <group>-*.qs2 prefix (superseded packs too).
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  suppressMessages(mc_data_download(path = cache, ask = FALSE, quiet = TRUE))

  stale <- paste0("fakegroup-", strrep("0", 32), ".qs2")
  fs::file_create(fs::path(cache, stale))
  # Files that only share a loose prefix must survive.
  mine <- fs::path(cache, "fakegroup-my-own-cohort.qs2")
  unrelated <- fs::path(cache, "keep-me.txt")
  fs::file_create(mine)
  fs::file_create(unrelated)

  gone <- suppressMessages(mc_data_clear(path = cache, ask = FALSE))
  expect_setequal(fs::path_file(gone), c(row$file, stale))
  expect_true(fs::file_exists(mine))
  expect_true(fs::file_exists(unrelated))
  expect_false(mc_cache_status(path = cache)$cached)
})

test_that("mc_data_clear() is a no-op on an empty or absent cache", {
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  empty <- withr::local_tempdir()
  expect_message(mc_data_clear(path = empty, ask = FALSE), "Nothing to clear")

  absent <- fs::path(withr::local_tempdir(), "never-created")
  expect_message(mc_data_clear(path = absent, ask = FALSE), "does not exist")
  expect_false(fs::dir_exists(absent))
})

test_that("external_pack() never downloads; it errors with the command to run", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  expect_error(external_pack("FakeGroup", path = cache), "is not downloaded")
  expect_error(external_pack("FakeGroup", path = cache), 'mc_data_download\\("FakeGroup"\\)')
  expect_length(fs::dir_ls(cache), 0)
})

test_that("external_pack() round-trips the payload exactly", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  suppressMessages(mc_data_download(path = cache, ask = FALSE, quiet = TRUE))

  expect_identical(external_pack("FakeGroup", path = cache), row$.payload)
})

test_that("external_pack() rejects a corrupt file and a payload that is not ours", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  # Right name, unreadable bytes -> qs2 checksum fails.
  writeLines("not a qs2 file", fs::path(cache, row$file))
  expect_error(external_pack("FakeGroup", path = cache), "Failed to read cached clock data")

  # Right name, valid qs2, wrong object.
  qs2::qs_save(list(bogus = TRUE), fs::path(cache, row$file))
  expect_error(external_pack("FakeGroup", path = cache), "group_id")
})

test_that("external_pack() checks each identity field of the decoded pack", {
  # Each structural identity field must actually reject a stale pack.
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  tamper <- function(...) {
    p <- utils::modifyList(row$.payload, list(...))
    qs2::qs_save(p, fs::path(cache, row$file))
  }

  tamper(encoding_version = 99L)
  expect_error(external_pack("FakeGroup", path = cache), "encoding_version")

  tamper(encoding = "something_else")
  expect_error(external_pack("FakeGroup", path = cache), "encoding")

  tamper(cpgs = "cg00000029")
  expect_error(external_pack("FakeGroup", path = cache), "n_cpgs")

  tamper(group_id = "OtherGroup")
  expect_error(external_pack("FakeGroup", path = cache), "group_id")

  # Untampered pack still loads.
  qs2::qs_save(row$.payload, fs::path(cache, row$file))
  expect_identical(external_pack("FakeGroup", path = cache), row$.payload)
})

test_that("the real PCBrainAge release asset downloads and verifies", {
  skip_on_cran()
  skip_if_offline()
  skip_if_not(
    nzchar(Sys.getenv("METHYLCIPHER_TEST_NETWORK")),
    "set METHYLCIPHER_TEST_NETWORK=1 to run live download tests"
  )

  cache <- withr::local_tempdir()
  suppressMessages(mc_data_download("PCBrainAge", path = cache, ask = FALSE, quiet = TRUE))
  expect_true(mc_cache_status("PCBrainAge", path = cache)$cached)

  pack <- external_pack("PCBrainAge", path = cache)
  row <- mc_asset_row("PCBrainAge")
  expect_length(pack$cpgs, row$n_cpgs)
  expect_identical(nrow(pack$coefficient_matrix), row$n_cpgs)
  expect_identical(pack$encoding, row$encoding)
  expect_identical(pack$encoding_version, row$encoding_version)
})
