# external clock-data cache tests (file://, live network opt-in)

# fake external pack on disk, returns its provenance row
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

  phash <- digest::digest(payload, algo = "sha256")
  file <- sprintf("%s-%s.qs2", tolower(group), phash)
  rtag <- sub("\\.qs2$", "", file) # tag = filename stem; bare hex tags rejected by GitHub.
  src <- file.path(dir, file)
  qs2::qs_save(payload, src)
  list(
    group_id = group,
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

# mock provenance registry + file:// download URLs
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
  withr::local_options(mc.cache_dir = NULL)
  withr::local_envvar(MC_CACHE_DIR = NA)
  expect_identical(mc_cache_dir(), mc_default_cache_dir())

  withr::local_options(mc.cache_dir = "from-option")
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
  withr::local_options(mc.cache_dir = cache)
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

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
  expect_false(any(grepl(".part", list.files(cache), fixed = TRUE)))

  file.remove(row$.src)
  expect_silent(suppressMessages(mc_data_download(assets = cache, ask = FALSE)))
})

test_that("a download failure is reported with the URL and leaves nothing behind", {
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  file.remove(row$.src) # the "server" 404s

  expect_error(mc_data_download(assets = cache, ask = FALSE))
  expect_length(list.files(cache), 0)
})

test_that("load_mc_assets() downloads missing packs on consent and returns a named registry", {
  cache <- withr::local_tempdir()
  withr::local_options(mc.cache_dir = cache)
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  packs <- suppressMessages(load_mc_assets("FakeGroup", ask = FALSE))
  expect_named(packs, "FakeGroup")
  expect_identical(packs[["FakeGroup"]], row$.payload)
  expect_true(file.exists(file.path(cache, row$file)))
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
  expect_length(list.files(cache), 0)
})

test_that("load_mc_assets() resolves in-memory pack(s) without touching disk", {
  dir <- withr::local_tempdir()
  a <- fake_asset(dir, group = "GroupA")
  b <- fake_asset(dir, group = "GroupB")
  local_fake_registry(stats::setNames(list(a, b), c("GroupA", "GroupB")))

  expect_identical(
    load_mc_assets("GroupA", assets = a$.payload)[["GroupA"]],
    a$.payload
  )
  expect_error(load_mc_assets("GroupB", assets = a$.payload))
  expect_warning(
    res <- load_mc_assets("GroupA", assets = list(a$.payload, b$.payload))
  )
  expect_named(res, "GroupA")
  expect_identical(res[["GroupA"]], a$.payload)
})

test_that("clear_mc_cache() removes cached packs only on explicit consent", {
  skip_if(interactive())
  cache <- withr::local_tempdir()
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)

  # nothing cached: reports and is a no-op
  expect_message(clear_mc_cache(assets = cache))

  suppressMessages(mc_data_download(assets = cache, ask = FALSE))
  # unprompted deletion is refused non-interactively (file survives)
  expect_error(clear_mc_cache(assets = cache))
  expect_true(file.exists(file.path(cache, row$file)))

  removed <- suppressMessages(clear_mc_cache(assets = cache, ask = FALSE))
  expect_identical(basename(removed), row$file)
  expect_false(file.exists(file.path(cache, row$file)))
})

test_that("download -> load -> clear round trips and leaves the cache empty", {
  skip_if(interactive())
  cache <- withr::local_tempdir()
  withr::local_options(mc.cache_dir = cache)
  a <- fake_asset(withr::local_tempdir(), group = "GroupA")
  b <- fake_asset(withr::local_tempdir(), group = "GroupB")
  local_fake_registry(stats::setNames(list(a, b), c("GroupA", "GroupB")))

  paths <- suppressMessages(mc_data_download(ask = FALSE))
  expect_true(all(file.exists(paths)))
  expect_false(any(grepl(".part", list.files(cache), fixed = TRUE)))

  # cached: loads from disk, needs no consent even with ask = TRUE
  packs <- load_mc_assets("all")
  expect_named(packs, c("GroupA", "GroupB"))
  expect_identical(packs[["GroupA"]], a$.payload)
  expect_identical(packs[["GroupB"]], b$.payload)

  removed <- suppressMessages(clear_mc_cache(ask = FALSE))
  expect_setequal(basename(removed), c(a$file, b$file))
  expect_false(any(file.exists(paths)))
  expect_length(mc_cached_files("all"), 0)
  expect_length(list.files(cache), 0)

  # really gone: the next load would have to download, so it refuses
  expect_error(load_mc_assets("all"))

  # an empty request stays empty (it is not "all")
  expect_length(load_mc_assets(character(0)), 0)
})

test_that("a non-path `assets` errors instead of silently hitting the cache dir", {
  cache <- withr::local_tempdir()
  withr::local_options(mc.cache_dir = cache)
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  suppressMessages(mc_data_download(assets = cache, ask = FALSE))
  staged <- file.path(cache, row$file)
  expect_true(file.exists(staged))

  # a loaded pack names no directory -- cache verbs must reject it
  pack <- row$.payload
  expect_error(clear_mc_cache(assets = pack, ask = FALSE))
  expect_error(mc_data_download(assets = pack, ask = FALSE))
  expect_error(mc_cached_files("all", assets = pack))
  expect_error(mc_cache_dir(5))
  expect_error(mc_cache_dir(c("a", "b")))
  expect_error(mc_cache_dir(""))
  expect_true(file.exists(staged))
})

test_that("`ask` is a strict flag -- only FALSE consents", {
  skip_if(interactive())
  cache <- withr::local_tempdir()
  withr::local_options(mc.cache_dir = cache)
  row <- fake_asset(withr::local_tempdir())
  local_fake_registry(row)
  bad_flags <- list(NA, NULL, "yes", 1, c(TRUE, TRUE))

  for (bad in bad_flags) {
    expect_error(mc_data_download(ask = bad))
    expect_error(load_mc_assets("FakeGroup", ask = bad))
  }
  expect_length(list.files(cache), 0) # nothing fetched under a bad flag

  suppressMessages(mc_data_download(ask = FALSE))
  staged <- file.path(cache, row$file)
  for (bad in bad_flags) {
    expect_error(clear_mc_cache(ask = bad))
  }
  expect_true(file.exists(staged)) # and nothing deleted under one either
})

test_that("the real PCBrainAge release asset downloads and verifies", {
  skip_on_cran()
  skip_if_offline()
  skip_if_not(
    nzchar(Sys.getenv("MC_TEST_NETWORK")),
    "set MC_TEST_NETWORK=1 to run live download tests"
  )

  cache <- withr::local_tempdir()
  withr::local_options(mc.cache_dir = cache)
  packs <- suppressMessages(load_mc_assets("PCBrainAge", ask = FALSE))
  pack <- packs[["PCBrainAge"]]
  row <- mc_asset("PCBrainAge")
  expect_length(pack$cpgs, row$n_cpgs)
  expect_identical(nrow(pack$coefficient_matrix), row$n_cpgs)
})
