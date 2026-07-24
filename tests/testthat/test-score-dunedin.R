# Dunedin: degraded-coverage and PACE QN paths not covered by parity.

# Vendor fill for fully-absent model CpGs.
test_that("DunedinPoAm38 vendor-fills fully-absent CpGs (score_imputed_full)", {
  cpgs <- clock_scoring_cpgs("DunedinPoAm38")
  keep <- cpgs[seq_len(length(cpgs) - 2L)] # drop 2 of 46 -> still >= 80% covered
  DNAm <- random_betas(keep, n = 5L)
  res <- calc_clocks(DNAm, "DunedinPoAm38")

  cov <- res$coverage$per_clock$DunedinPoAm38
  expect_equal(cov$score_imputed_full, 2L)
  expect_false(anyNA(res$scores[, "DunedinPoAm38"]))

  coef <- clock_coefs("DunedinPoAm38")
  ref <- clock_impute_ref("DunedinPoAm38")
  absent <- setdiff(names(coef), keep)
  golden <- as.numeric(
    clock_intercept("DunedinPoAm38") +
      DNAm[, keep] %*% coef[keep] +
      sum(coef[absent] * ref[absent])
  )
  expect_equal(as.numeric(res$scores[, "DunedinPoAm38"]), golden)
})

# PACE QN golden (parity skip-listed).
test_that("DunedinPACE quantile-normalizes the gold panel before the linear score", {
  skip_if_not_installed("betanorm")
  gold <- dunedin_gold_means("DunedinPACE")
  panel <- names(gold)
  DNAm <- random_betas(panel, n = 5L) # full gold-panel coverage, no gates/fill
  res <- calc_clocks(DNAm, "DunedinPACE")

  norm <- betanorm::quantile_norm(
    DNAm[, panel, drop = FALSE],
    target = as.numeric(gold[panel])
  )
  colnames(norm) <- panel
  coef <- clock_coefs("DunedinPACE")
  golden <- as.numeric(
    clock_intercept("DunedinPACE") + norm[, names(coef)] %*% coef
  )
  expect_equal(as.numeric(res$scores[, "DunedinPACE"]), golden)

  linear <- as.numeric(
    clock_intercept("DunedinPACE") + DNAm[, names(coef)] %*% coef
  )
  expect_false(isTRUE(all.equal(golden, linear)))
})

# A normalizing clock counts partial fills over BOTH panels, kept apart: the
# score-panel count for DunedinPACE was not computed before the per-panel widen.
test_that("DunedinPACE reports score and norm panel miss separately", {
  skip_if_not_installed("betanorm")
  norm_panel <- names(dunedin_gold_means("DunedinPACE"))
  score_panel <- clock_scoring_cpgs("DunedinPACE")
  norm_only <- setdiff(norm_panel, score_panel)

  DNAm <- random_betas(norm_panel, n = 4L)
  DNAm[1, norm_only[1]] <- NA_real_ # norm panel only
  DNAm[2, score_panel[1]] <- NA_real_ # in both panels (score subset of norm)

  res <- calc_clocks(DNAm, "DunedinPACE", min_row_coverage = 0)
  sm <- res$coverage$sample_miss
  expect_identical(colnames(sm$score), "DunedinPACE")
  expect_identical(colnames(sm$norm), "DunedinPACE")

  expect_identical(unname(sm$norm[, "DunedinPACE"]), c(1L, 1L, 0L, 0L))
  expect_identical(unname(sm$score[, "DunedinPACE"]), c(0L, 1L, 0L, 0L))

  cov <- res$coverage$per_clock$DunedinPACE
  expect_true(cov$normalizes)
  expect_identical(cov$score_imputed_partial, 1L) # sample 2 only
  expect_identical(cov$norm_imputed_partial, 2L) # samples 1 and 2
})

test_that("whole-clock coverage stops upfront", {
  cpgs <- clock_scoring_cpgs("DunedinPoAm38")
  keep <- cpgs[seq_len(round(0.6 * length(cpgs)))] # ~60% < 80%
  DNAm <- random_betas(keep, n = 5L)
  expect_error(calc_clocks(DNAm, "DunedinPoAm38"))
})

# An under-covered sample warns and keeps its score -- Dunedin no longer NA-s
# rows, so it behaves like every other clock.
test_that("an under-covered sample warns but still scores", {
  cpgs <- clock_scoring_cpgs("DunedinPoAm38")
  DNAm <- random_betas(cpgs, n = 5L)
  DNAm[1, seq_len(round(0.5 * ncol(DNAm)))] <- NA # sample 1 ~50% present
  expect_warning(res <- calc_clocks(DNAm, "DunedinPoAm38"))
  expect_false(anyNA(res$scores[, "DunedinPoAm38"]))

  expect_silent(calc_clocks(DNAm, "DunedinPoAm38", min_row_coverage = 0))
})

# The floors gate different axes: a missing column stops upfront, a sparse
# sample only warns.
test_that("min_col_coverage = 0 leaves the row gate warning", {
  cpgs <- clock_scoring_cpgs("DunedinPoAm38")
  keep <- cpgs[seq_len(round(0.6 * length(cpgs)))]
  DNAm <- random_betas(keep, n = 5L)
  expect_warning(
    res <- calc_clocks(DNAm, "DunedinPoAm38", min_col_coverage = 0)
  )
  expect_false(anyNA(res$scores[, "DunedinPoAm38"]))

  expect_silent(calc_clocks(
    DNAm,
    "DunedinPoAm38",
    min_col_coverage = 0,
    min_row_coverage = 0
  ))
})
