# scale_scores: a clock's finished score scaled across the cohort (meta sec 4c).
# MultiAgeEpi is the first clock to declare one. These tests make Hannum declare
# it through a mock, so the path is tested apart from any one clock's weights.

# Hannum declares a cohort z-score, on or off by default
mock_scaling <- function(default = TRUE, ids = "Hannum") {
  function(id) {
    if (id %in% ids) list(op = "cohort_zscore", default = default) else NULL
  }
}

hannum_betas <- function(n = 8L) {
  random_betas(clock_cpgs("Hannum"), n = n)
}

test_that("a clock scaled by default returns its raw score as a z-score", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(TRUE))
  DNAm <- hannum_betas()
  raw <- calc_clocks(DNAm, "Hannum", scale_scores = FALSE)
  res <- calc_clocks(DNAm, "Hannum")

  want <- as.numeric(scale(raw$scores[, "Hannum"]))
  expect_equal(unname(res$scores[, "Hannum"]), want, tolerance = 1e-12)
  expect_equal(mean(res$scores[, "Hannum"]), 0, tolerance = 1e-12)
  expect_equal(stats::sd(res$scores[, "Hannum"]), 1, tolerance = 1e-12)
  expect_identical(res$provenance$scaled, "Hannum")
  expect_identical(raw$provenance$scaled, character(0))
})

test_that("every opt-out form returns the raw score", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(TRUE))
  DNAm <- hannum_betas()
  raw <- calc_clocks(DNAm, "Hannum", scale_scores = FALSE)$scores
  expect_equal(
    calc_clocks(DNAm, "Hannum", scale_scores = c(Hannum = FALSE))$scores,
    raw
  )
  # the raw score is the ordinary linear score: nothing else changes
  local_mocked_bindings(clock_score_scaling = function(id) NULL)
  expect_equal(calc_clocks(DNAm, "Hannum")$scores, raw)
})

test_that("a clock declared off by default scales only when asked", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(FALSE))
  DNAm <- hannum_betas()
  raw <- calc_clocks(DNAm, "Hannum")
  expect_identical(raw$provenance$scaled, character(0))
  for (form in list(TRUE, "Hannum", c(Hannum = TRUE))) {
    res <- calc_clocks(DNAm, "Hannum", scale_scores = form)
    expect_equal(
      unname(res$scores[, "Hannum"]),
      as.numeric(scale(raw$scores[, "Hannum"])),
      tolerance = 1e-12
    )
  }
})

test_that("a bare TRUE leaves a clock without a declaration unscaled", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(FALSE))
  DNAm <- random_betas(clock_cpgs(c("Hannum", "Horvath1")), n = 6L)
  res <- calc_clocks(DNAm, c("Hannum", "Horvath1"), scale_scores = TRUE)
  expect_identical(res$provenance$scaled, "Hannum")
})

test_that("scale_scores refuses what it cannot do", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(TRUE))
  DNAm <- hannum_betas()
  # a clock that declares no scaled score cannot be turned on
  expect_error(
    calc_clocks(
      random_betas(clock_cpgs("Horvath1"), n = 4L),
      "Horvath1",
      scale_scores = c(Horvath1 = TRUE)
    ),
    "Cannot turn on"
  )
  # a name the call does not score
  expect_error(
    calc_clocks(DNAm, "Hannum", scale_scores = c(Horvath1 = FALSE)),
    "not being scored"
  )
  # more than one unnamed value
  expect_error(
    calc_clocks(DNAm, "Hannum", scale_scores = c(TRUE, FALSE)),
    "unnamed values"
  )
  expect_error(calc_clocks(DNAm, "Hannum", scale_scores = NA))
})

test_that("one sample has no cohort z-score, and says why", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(TRUE))
  one <- hannum_betas(1L)
  res <- calc_clocks(one, "Hannum")
  expect_true(is.na(res$scores[, "Hannum"]))
  expect_equal(
    res$provenance$scoring_failures$Hannum$fit_reduce,
    rownames(one)
  )
})

test_that("a flat score scales to NA, the same on every platform", {
  skip_on_cran()
  raws <- matrix(
    rep(0.1, 6),
    ncol = 1L,
    dimnames = list(paste0("s", 1:6), "x")
  )
  out <- scale_score("x", raws, list(op = "cohort_zscore", default = TRUE))
  expect_true(all(is.na(out[, 1L])))
  expect_identical(rownames(out), rownames(raws))
})

test_that("rbind keeps batch values, and refinalize_clocks scales the cohort", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(TRUE))
  DNAm <- hannum_betas(12L)
  a <- calc_clocks(DNAm[1:6, , drop = FALSE], "Hannum")
  b <- calc_clocks(DNAm[7:12, , drop = FALSE], "Hannum")
  bound <- suppressMessages(rbind(a, b))
  expect_identical(bound$provenance$scaled, "Hannum")

  whole <- calc_clocks(DNAm, "Hannum")
  again <- suppressMessages(refinalize_clocks(bound))
  expect_equal(
    again$scores[rownames(DNAm), "Hannum"],
    whole$scores[rownames(DNAm), "Hannum"],
    tolerance = 1e-12
  )
})

test_that("rbind refuses batches that disagree on scaling", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(TRUE))
  DNAm <- hannum_betas(8L)
  a <- calc_clocks(DNAm[1:4, , drop = FALSE], "Hannum")
  b <- calc_clocks(DNAm[5:8, , drop = FALSE], "Hannum", scale_scores = FALSE)
  expect_error(rbind(a, b), "scaled clocks")
})

test_that("list_clocks reports the declaration and the batch dependence", {
  skip_on_cran()
  local_mocked_bindings(clock_score_scaling = mock_scaling(TRUE))
  lc <- list_clocks(all_columns = TRUE)
  row <- lc[lc$clock_id == "Hannum", ]
  expect_true(row$scale_scores)
  expect_true(row$batch_dependent)
  expect_false(any(lc$scale_scores[lc$clock_id != "Hannum"]))
})

test_that("a scaled clock cannot be another clock's input", {
  skip_on_cran()
  local_mocked_bindings(
    clock_score_scaling = mock_scaling(TRUE, ids = "Hannum"),
    clock_depends_on = function(id) {
      if (id == "Horvath1") "Hannum" else character(0)
    }
  )
  expect_error(mc_spec(c("Hannum", "Horvath1")), "whose score is scaled")
})
