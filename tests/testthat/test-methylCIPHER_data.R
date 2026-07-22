# External clock-data cache. Download path uses file://; live network is opt-in.

# Fake external pack on disk (tiny qs2 over file://, never the network); returns the
# provenance row it corresponds to.
fake_asset <- function(dir, group = "FakeGroup", payload = NULL) {
  if (is.null(payload)) {
    payload <- list(
      group_id = group,
      encoding = "canonical_matrices",
      encoding_version = 3L,
      cpgs = c("cg00000029", "cg00000108"),
      coefficient_matrix = matrix(1:4, 2)
    )
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  # Content hash matches the package's mc_payload_hash(): no drift warning on load.
  phash <- mc_payload_hash(payload)
  file <- sprintf("%s-%s.qs2", tolower(group), phash)
  rtag <- sub("\\.qs2$", "", file) # tag = filename stem; bare hex tags rejected by GitHub.
  src <- file.path(dir, file)
  qs2::qs_save(payload, src)
  list(
    group_id = group,
    payload_hash = phash,
    release_tag = rtag,
    file = file,
    size_bytes = as.numeric(file.size(src)),
    encoding = payload$encoding,
    encoding_version = payload$encoding_version,
    n_clocks = 1L,
    n_cpgs = length(payload$cpgs),
    .payload = payload,
    .src = as.character(src)
  )
}

# Mock the provenance registry + file:// download URLs for the calling test.
local_fake_registry <- function(rows, .env = parent.frame()) {
  if (!is.null(rows$group_id)) {
    rows <- stats::setNames(list(rows), rows$group_id)
  }
  testthat::local_mocked_bindings(
    mc_external_groups = function() names(rows),
    mc_asset = function(group_id) {
      row <- rows[[group_id]]
      if (is.null(row)) {
        stop("Not an external clock group: ", group_id, call. = FALSE)
      }
      row
    },
    # mustWork=FALSE so a deleted source still yields a URL and the download 404s.
    mc_asset_url = function(row) {
      paste0(
        "file:///",
        normalizePath(row$.src, winslash = "/", mustWork = FALSE)
      )
    },
    .env = .env
  )
  invisible(rows)
}

test_that("mc_cache_dir() resolves a default and honours the option override", {
  withr::local_options(methylCIPHER.cache_dir = NULL)
  withr::local_envvar(METHYLCIPHER_CACHE_DIR = NA)
  expect_identical(mc_cache_dir(), mc_default_cache_dir())

  withr::local_options(methylCIPHER.cache_dir = "from-option")
  expect_identical(mc_cache_dir(), path.expand("from-option"))
})

test_that("the shipped registry covers the three external groups", {
  expect_setequal(
    mc_external_groups(),
    c("SystemsAge", "PCClocks", "PCBrainAge")
  )
  for (gid in mc_external_groups()) {
    row <- mc_asset(gid)
    expect_identical(row$group_id, gid)
    expect_gt(row$size_bytes, 0)
  }
})

test_that("registry lookups reject unknown ids and resolve group sets", {
  expect_error(mc_asset("NotAClockGroup"))
  expect_error(mc_resolve_groups(c("PCClocks", "Nope")))
  expect_setequal(mc_resolve_groups("all"), mc_external_groups())
  expect_setequal(mc_resolve_groups(NULL), mc_external_groups())
})

test_that("load_mc_assets() refuses to fetch unprompted in a non-interactive session", {
  skip_if(interactive())
  cache <- withr::local_tempdir()
  withr::local_options(methylCIPHER.cache_dir = cache)
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  # Open set (assets = NULL) + ask = TRUE default + non-interactive must refuse, never write.
  expect_error(load_mc_assets("FakeGroup"))
  expect_length(list.files(cache), 0)
})

test_that("mc_data_download() fetches, verifies, and leaves no scratch files", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  paths <- suppressMessages(mc_data_download(assets = cache, ask = FALSE))
  expect_identical(unname(basename(paths)), row$file)
  expect_true(file.exists(file.path(cache, row$file)))
  # Staging .part must never survive.
  expect_false(any(grepl(".part", list.files(cache), fixed = TRUE)))

  # Idempotent: an already-cached pack is not re-fetched (source can vanish).
  file.remove(row$.src)
  expect_silent(suppressMessages(mc_data_download(assets = cache, ask = FALSE)))
})

test_that("a download failure is reported with the URL and leaves nothing behind", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  file.remove(row$.src) # the "server" 404s

  expect_error(suppressWarnings(mc_data_download(assets = cache, ask = FALSE)))
  expect_length(list.files(cache), 0)
})

test_that("load_mc_assets() downloads missing packs on consent and returns a named registry", {
  cache <- withr::local_tempdir()
  withr::local_options(methylCIPHER.cache_dir = cache)
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  packs <- suppressMessages(load_mc_assets("FakeGroup", ask = FALSE))
  expect_named(packs, "FakeGroup")
  expect_identical(packs[["FakeGroup"]], row$.payload)
  expect_true(file.exists(file.path(cache, row$file)))
})

test_that("load_mc_assets() warns (never stops) when the content hash drifts", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  row$payload_hash <- strrep("0", 64) # provenance now disagrees with the bytes.
  local_fake_registry(row)
  suppressMessages(mc_data_download(assets = cache, ask = FALSE))

  # Read the staged pack back as a closed set (explicit path -> no download).
  expect_warning(packs <- load_mc_assets("FakeGroup", assets = cache))
  # Warn-only: the pack is still returned.
  expect_identical(packs[["FakeGroup"]], row$.payload)
})

test_that("load_mc_assets() rejects a corrupt cached file via the qs2 checksum", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  writeLines("not a qs2 file", file.path(cache, row$file))
  expect_error(load_mc_assets("FakeGroup", assets = cache))
})

test_that("load_mc_assets() with an explicit path is a closed set: no download, missing is fatal", {
  cache <- withr::local_tempdir() # deliberately empty
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  expect_error(load_mc_assets("FakeGroup", assets = cache, ask = FALSE))
  # Nothing was fetched into the closed dir.
  expect_length(list.files(cache), 0)
})

test_that("load_mc_assets() resolves in-memory pack(s) without touching disk", {
  dir <- withr::local_tempdir()
  a <- fake_asset(dir, group = "GroupA")
  b <- fake_asset(dir, group = "GroupB")
  local_fake_registry(stats::setNames(list(a, b), c("GroupA", "GroupB")))

  # A single pack and a list of packs both key by their own group_id.
  expect_identical(
    load_mc_assets("GroupA", assets = a$.payload)[["GroupA"]],
    a$.payload
  )
  expect_identical(
    suppressWarnings(
      load_mc_assets("GroupA", assets = list(a$.payload, b$.payload))
    )[["GroupA"]],
    a$.payload
  )
  # A needed group absent from the provided assets is a hard error.
  expect_error(load_mc_assets("GroupB", assets = a$.payload))
  # An asset the plan does not need is warned and ignored.
  expect_warning(
    res <- load_mc_assets("GroupA", assets = list(a$.payload, b$.payload))
  )
  expect_named(res, "GroupA")
})

test_that("clear_clock_cache() reports what is cached and never deletes automatically", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  expect_message(clear_clock_cache(assets = cache))

  suppressMessages(mc_data_download(assets = cache, ask = FALSE))
  reported <- suppressMessages(clear_clock_cache(assets = cache))
  expect_identical(basename(reported), row$file)
  # Nothing was removed.
  expect_true(file.exists(file.path(cache, row$file)))
})

test_that("the real PCBrainAge release asset downloads and verifies", {
  skip_on_cran()
  skip_if_offline()
  skip_if_not(
    nzchar(Sys.getenv("METHYLCIPHER_TEST_NETWORK")),
    "set METHYLCIPHER_TEST_NETWORK=1 to run live download tests"
  )

  cache <- withr::local_tempdir()
  withr::local_options(methylCIPHER.cache_dir = cache)
  packs <- suppressMessages(load_mc_assets("PCBrainAge", ask = FALSE))
  pack <- packs[["PCBrainAge"]]
  row <- mc_asset("PCBrainAge")
  expect_length(pack$cpgs, row$n_cpgs)
  expect_identical(nrow(pack$coefficient_matrix), row$n_cpgs)
  expect_identical(mc_payload_hash(pack), row$payload_hash)
})
