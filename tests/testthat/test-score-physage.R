# PhysAge pack: vendor-mean fill + the cohort_zscore composites. The vendor-fill and structural
# checks are self-contained (synthetic betas over the group's CpG union, bundled sysdata). The
# numeric author-parity check is cohort-gated and skips when the EPIC fixture is absent (CRAN).

# synthetic_betas() lives in helper-sim.R (a seeded wrapper over random_betas()).
physage_union <- function() {
  members <- mc_groups[["PhysAge"]]$members
  unique(unlist(lapply(members, clock_scoring_cpgs)))
}

test_that("surrogate members reduce by mean, and absent CpGs vendor-fill by offset", {
  DNAm <- synthetic_betas(physage_union())
  co <- clock_coefs("DNAmCRP")
  ic <- clock_intercept("DNAmCRP")

  # all present: mean of coef*beta plus intercept
  full <- calc_clocks(DNAm, "DNAmCRP")$scores[, "DNAmCRP"]
  mean_form <- ic + as.numeric(DNAm[, names(co)] %*% co) / length(co)
  expect_equal(unname(full), unname(mean_form), tolerance = 1e-10)

  # drop 5 CpGs that have a vendor mean: they contribute coef * ref as a constant offset
  ref <- clock_impute_ref("DNAmCRP")
  drop <- intersect(names(co), names(ref))[1:5]
  DNAm2 <- DNAm[, setdiff(colnames(DNAm), drop), drop = FALSE]
  res2 <- calc_clocks(DNAm2, "DNAmCRP")
  present <- setdiff(names(co), drop)
  filled <- ic +
    (as.numeric(DNAm2[, present] %*% co[present]) + sum(co[drop] * ref[drop])) /
      length(co)
  expect_equal(unname(res2$scores[, "DNAmCRP"]), unname(filled), tolerance = 1e-10)

  cov <- res2$coverage$per_clock[["DNAmCRP"]]
  expect_identical(cov$score_imputed_full, 5L)
  expect_identical(cov$score_dropped, 0L)
})

test_that("PhysAge composites run, are batch-stamped, and need >= 2 samples", {
  DNAm <- synthetic_betas(physage_union(), n = 6L)
  res <- calc_clocks(DNAm, c("DNAmPhysAge", "DNAmPhysAge_years"))

  expect_true(all(c("DNAmPhysAge", "DNAmPhysAge_years") %in% colnames(res$scores)))
  expect_true(all(is.finite(res$scores[, "DNAmPhysAge"])))
  expect_true(all(is.finite(res$scores[, "DNAmPhysAge_years"])))
  # batch-dependent -> a frozen batch id is stamped
  expect_false(is.null(res$provenance$batch_set_id))

  one <- synthetic_betas(physage_union(), n = 1L)
  expect_error(calc_clocks(one, "DNAmPhysAge"), "at least|>= 2|needs", ignore.case = TRUE)
})

test_that("non-batch requests carry no batch_set_id", {
  DNAm <- synthetic_betas(clock_coefs("Hannum") |> names())
  res <- calc_clocks(DNAm, "Hannum")
  expect_null(res$provenance$batch_set_id)
})

# Both composites in one call (they share the surrogate deps); the per-clock parity sweep in
# test-fixtures-parity.R covers each individually. Cohort plumbing lives in helper-fixtures.R.
test_that("PhysAge composites match the author fixtures on the EPIC cohort", {
  skip_if_no_cohort()
  DNAm <- cohort_betas(cohort_con(), physage_union())
  res <- calc_clocks(DNAm, c("DNAmPhysAge", "DNAmPhysAge_years"))
  expect_parity(res$scores[, "DNAmPhysAge"], "DNAmPhysAge")
  expect_parity(res$scores[, "DNAmPhysAge_years"], "DNAmPhysAge_years")
})
