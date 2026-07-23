# PhysAge: vendor-mean fill + cohort_zscore composites (synthetic).

physage_union <- function() {
  members <- mc_groups[["PhysAge"]]$members
  unique(unlist(lapply(members, clock_scoring_cpgs)))
}

test_that("surrogate members reduce by mean, and absent CpGs vendor-fill by offset", {
  DNAm <- random_betas(physage_union(), n = 6L)
  co <- clock_coefs("DNAmCRP")
  ic <- clock_intercept("DNAmCRP")

  full <- calc_clocks(DNAm, "DNAmCRP")$scores[, "DNAmCRP"]
  mean_form <- ic + as.numeric(DNAm[, names(co)] %*% co) / length(co)
  expect_equal(unname(full), unname(mean_form), tolerance = 1e-10)

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

  cov <- res2$coverage$per_clock[["DNAmCRP"]]
  expect_identical(cov$score_imputed_full, 5L)
  expect_identical(cov$score_dropped, 0L)
})

test_that("PhysAge composites run, are batch-stamped, and need >= 2 samples", {
  DNAm <- random_betas(physage_union(), n = 6L)
  res <- calc_clocks(DNAm, c("DNAmPhysAge", "DNAmPhysAge_years"))

  expect_true(all(
    c("DNAmPhysAge", "DNAmPhysAge_years") %in% colnames(res$scores)
  ))
  expect_true(all(is.finite(res$scores[, "DNAmPhysAge"])))
  expect_true(all(is.finite(res$scores[, "DNAmPhysAge_years"])))

  expect_false(is.null(res$provenance$batch_set_id))

  one <- random_betas(physage_union(), n = 1L)
  expect_error(calc_clocks(one, "DNAmPhysAge"))
})

test_that("non-batch requests carry no batch_set_id", {
  DNAm <- random_betas(clock_coefs("Hannum") |> names(), n = 6L)
  res <- calc_clocks(DNAm, "Hannum")
  expect_null(res$provenance$batch_set_id)
})
