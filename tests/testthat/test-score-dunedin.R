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

# PACE QN golden while parity is skip-listed.
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

  # QN must move the score off the plain-linear value it would otherwise take.
  linear <- as.numeric(
    clock_intercept("DunedinPACE") + DNAm[, names(coef)] %*% coef
  )
  expect_false(isTRUE(all.equal(golden, linear)))
})

test_that("whole-clock coverage gate returns all-NA", {
  cpgs <- clock_scoring_cpgs("DunedinPoAm38")
  keep <- cpgs[seq_len(round(0.6 * length(cpgs)))] # ~60% < 80%
  DNAm <- random_betas(keep, n = 5L)
  res <- suppressWarnings(calc_clocks(DNAm, "DunedinPoAm38"))
  expect_true(all(is.na(res$scores[, "DunedinPoAm38"])))
})

test_that("per-sample coverage gate NA-s only under-covered samples", {
  cpgs <- clock_scoring_cpgs("DunedinPoAm38")
  DNAm <- random_betas(cpgs, n = 5L)
  DNAm[1, seq_len(round(0.5 * ncol(DNAm)))] <- NA # sample 1 ~50% present
  res <- suppressWarnings(calc_clocks(DNAm, "DunedinPoAm38"))
  got <- res$scores[, "DunedinPoAm38"]
  expect_true(is.na(got[1]))
  expect_false(anyNA(got[-1]))
})

test_that("min_coverage = 0 disables the NA-gates", {
  cpgs <- clock_scoring_cpgs("DunedinPoAm38")
  keep <- cpgs[seq_len(round(0.6 * length(cpgs)))]
  DNAm <- random_betas(keep, n = 5L)
  res <- calc_clocks(DNAm, "DunedinPoAm38", min_coverage = 0)
  expect_false(anyNA(res$scores[, "DunedinPoAm38"]))
})
