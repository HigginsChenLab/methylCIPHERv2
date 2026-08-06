# physAge: vendor-mean fill + cohort_zscore composites (synthetic).

# fill offset lands inside the mean's divisor. parity cannot see this.
test_that("absent surrogate CpGs vendor-fill by offset under mean reduction", {
  skip_on_cran()
  DNAm <- random_betas(clock_scoring_cpgs("DNAmPhysAge"), n = 6L)
  co <- clock_coefs("DNAmCRP")
  ic <- clock_intercept("DNAmCRP")

  ref <- clock_impute_ref("DNAmCRP")
  drop <- intersect(names(co), names(ref))[1:5]
  DNAm2 <- DNAm[, setdiff(colnames(DNAm), drop), drop = FALSE]
  res2 <- calc_clocks(DNAm2, "DNAmCRP")
  present <- setdiff(names(co), drop)
  filled <- ic +
    (as.numeric(DNAm2[, present] %*% co[present]) + sum(co[drop] * ref[drop])) /
      length(co)
  expect_equal(
    unname(res2$scores[, "DNAmCRP"]),
    unname(filled),
    tolerance = 1e-10
  )

  cov <- res2$coverage$per_clock[[1]][["DNAmCRP"]]
  expect_equal(cov$score_imputed_full, 5L)
  expect_equal(cov$score_dropped, 0L)
})

# the cross-sample (`pending`) route: reduces over the cohort, so n = 1 refuses
test_that("PhysAge composites run, and one sample has no cohort z-score", {
  skip_on_cran()
  DNAm <- random_betas(clock_scoring_cpgs("DNAmPhysAge"), n = 6L)
  cols <- c("DNAmPhysAge", "DNAmPhysAge_years")
  res <- calc_clocks(DNAm, cols)

  expect_true(all(is.finite(res$scores[, cols])))

  # a z-score needs a cohort. one sample yields NA, and says why.
  one <- random_betas(clock_scoring_cpgs("DNAmPhysAge"), n = 1L)
  res1 <- calc_clocks(one, "DNAmPhysAge")
  expect_true(is.na(res1$scores[, "DNAmPhysAge"]))
  expect_equal(
    res1$provenance$scoring_failures$DNAmPhysAge,
    rownames(one)
  )
})

test_that("a surrogate that goes constant NAs the clock, not the cohort", {
  skip_on_cran()
  # blank a small surrogate: scale() NaN must not spread through rowSums.
  surr <- physage_surrogates("DNAmPhysAge")
  coefs <- lapply(surr, `[[`, "coef")
  flat <- names(coefs[[which.min(lengths(coefs))]])

  panel <- setdiff(clock_scoring_cpgs("DNAmPhysAge"), flat)
  DNAm <- random_betas(panel, n = 6L)
  res <- suppressWarnings(calc_clocks(DNAm, "DNAmPhysAge"))

  expect_true(all(is.na(res$scores[, "DNAmPhysAge"])))
  expect_equal(
    res$provenance$scoring_failures$DNAmPhysAge,
    rownames(DNAm)
  )
})
