# Engine reduction (sum vs mean) + linear_mean regression (synthetic betas; CRAN-safe).

test_that("clock_reduction reads the recipe: linear_mean -> mean, else sum", {
  expect_identical(clock_reduction("EpiTOC"), "mean")
  expect_identical(clock_reduction("HypoClock"), "mean")
  expect_identical(clock_reduction("DNAmCRP"), "mean")
  expect_identical(clock_reduction("Hannum"), "sum")
  expect_identical(clock_reduction("GrimAgeV1"), "sum")
})

test_that("linear_mean clocks reduce by mean, not sum (EpiTOC regression)", {
  co <- clock_coefs("EpiTOC")
  ic <- clock_intercept("EpiTOC")
  DNAm <- synthetic_betas(names(co))

  got <- calc_clocks(DNAm, "EpiTOC")$scores[, "EpiTOC"]
  mean_form <- ic + as.numeric(DNAm[, names(co)] %*% co) / length(co)
  expect_equal(unname(got), unname(mean_form), tolerance = 1e-10)

  # Guard against regression to the old sum reduction.
  sum_form <- ic + as.numeric(DNAm[, names(co)] %*% co)
  expect_false(isTRUE(all.equal(unname(got), unname(sum_form))))
})

test_that("plain linear clocks still reduce by sum (unchanged)", {
  co <- clock_coefs("Hannum")
  ic <- clock_intercept("Hannum")
  DNAm <- synthetic_betas(names(co)) # all present -> no absent, policy irrelevant

  got <- calc_clocks(DNAm, "Hannum")$scores[, "Hannum"]
  sum_form <- ic + as.numeric(DNAm[, names(co)] %*% co)
  expect_equal(unname(got), unname(sum_form), tolerance = 1e-10)
})

test_that("every catalog clock maps to a known score_type tag", {
  # Every catalog clock maps to an implemented scorer tag or deliberate "unsupported".
  known <- c(
    "linear", "grimage", "fitage_member", "fitage_composite",
    "physage", "unsupported"
  )
  tags <- vapply(mc_index$clock_id, score_type, character(1))
  expect_true(all(tags %in% known))
  expect_setequal(
    unique(tags[mc_index$group_id == "PhysAge"]),
    c("linear", "physage")
  )
})
