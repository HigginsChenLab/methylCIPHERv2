# declaration resolution: recipe operand reaches its tensor by declared pointer.

catalog_ids <- function() names(mc_catalog)

scale_ids <- function() {
  ids <- catalog_ids()
  ids[vapply(ids, function(i) length(sample_scale_steps(i)) > 0L, logical(1))]
}

test_that("some clock declares a sample_scale step", {
  # the two tests below are vacuous otherwise
  expect_gt(length(scale_ids()), 0L)
})

test_that("full-panel is exactly a sample_scale step with no declared ref", {
  for (id in scale_ids()) {
    expect_equal(
      clock_needs_full_panel(id),
      is.null(clock_sample_scale_ref(id))
    )
  }
})

test_that("a declared sample_scale ref resolves to its CpG set", {
  ids <- scale_ids()
  refs <- lapply(ids, clock_sample_scale_ref)
  names(refs) <- ids
  has_ref <- ids[!vapply(refs, is.null, logical(1))]
  skip_if(!length(has_ref), "no clock declares a sample_scale ref")

  for (id in has_ref) {
    ref <- refs[[id]]
    expect_type(ref, "character")
    expect_gt(length(ref), 0L)
    expect_false(anyNA(ref))
    # a declared moment set is closed, so it is not a full-panel clock
    expect_false(clock_needs_full_panel(id))
  }
})

test_that("a clock with no sample_scale step has neither fact", {
  plain <- setdiff(catalog_ids(), scale_ids())
  expect_gt(length(plain), 0L)
  id <- plain[[1]]
  expect_false(clock_needs_full_panel(id))
  expect_null(clock_sample_scale_ref(id))
})

test_that("the moment domain follows the same ref split", {
  for (id in scale_ids()) {
    d <- clock_moment_domain(id)
    expect_type(d[["key"]], "character")
    ref <- clock_sample_scale_ref(id)
    if (is.null(ref)) {
      # nothing declares the set, so there is one whole-matrix domain
      expect_equal(d[["key"]], "full")
      expect_null(d[["cpgs"]])
    } else {
      # derived from the declaration, so it is never the whole-matrix key
      expect_match(d[["key"]], ":", fixed = TRUE)
      expect_equal(d[["cpgs"]], ref)
    }
  }
})

test_that("a clock with no sample_scale step declares no domain", {
  plain <- setdiff(catalog_ids(), scale_ids())
  expect_null(clock_moment_domain(plain[[1]]))
})

test_that("clocks sharing a ref collapse to one domain", {
  expect_equal(resolve_moment_domains(character(0)), list())
  # a ref-less clock spells its domain "full", with no CpGs to declare
  full <- resolve_moment_domains(c("Zhang2019EN", "Zhang2019BLUP"))
  expect_equal(names(full), "full")
  expect_null(full[["full"]])

  # two clocks on one ref are one domain. a third on another adds a second
  shared_ref <- scale_ids()[vapply(
    scale_ids(),
    function(i) !is.null(clock_sample_scale_ref(i)),
    logical(1)
  )]
  skip_if(length(shared_ref) < 2L, "fewer than two clocks declare a ref")
  keys <- vapply(shared_ref, function(i) clock_moment_domain(i)[["key"]], "")
  got <- resolve_moment_domains(c("Zhang2019EN", shared_ref))
  expect_equal(names(got), c("full", unique(unname(keys))))
})

test_that("an unresolvable shared name errors rather than searching", {
  entry <- list(shared = list(a = list(name = "a", file = "weights/a.csv.gz")))
  expect_equal(shared_named(entry, "a", "X")[["file"]], "weights/a.csv.gz")
  expect_error(shared_named(entry, "missing", "X"))
  expect_error(shared_named(list(), "a", "X"))
})

test_that("a full-panel clock still announces that it reads every column", {
  expect_message(say_full_panel_clocks("Zhang2019EN"))
  expect_equal(
    suppressMessages(say_full_panel_clocks("Zhang2019EN")),
    "Zhang2019EN"
  )
})
