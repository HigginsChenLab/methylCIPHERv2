# Engine reduction (sum vs mean) via calc_clocks() output.

test_that("linear_mean clocks reduce by mean, not sum (EpiTOC regression)", {
  co <- clock_coefs("EpiTOC")
  ic <- clock_intercept("EpiTOC")
  DNAm <- random_betas(names(co), n = 6L)

  got <- calc_clocks(DNAm, "EpiTOC")$scores[, "EpiTOC"]
  mean_form <- ic + as.numeric(DNAm[, names(co)] %*% co) / length(co)
  expect_equal(unname(got), unname(mean_form), tolerance = 1e-10)

  # Guard against sum reduction regression.
  sum_form <- ic + as.numeric(DNAm[, names(co)] %*% co)
  expect_false(isTRUE(all.equal(unname(got), unname(sum_form))))
})

test_that("plain linear clocks still reduce by sum (unchanged)", {
  co <- clock_coefs("Hannum")
  ic <- clock_intercept("Hannum")
  DNAm <- random_betas(names(co), n = 6L) # all present -> no absent, policy irrelevant

  got <- calc_clocks(DNAm, "Hannum")$scores[, "Hannum"]
  sum_form <- ic + as.numeric(DNAm[, names(co)] %*% co)
  expect_equal(unname(got), unname(sum_form), tolerance = 1e-10)
})

test_that("every catalog clock maps to a known score_type tag", {
  # Every catalog clock maps to an implemented scorer tag or deliberate "unsupported".
  known <- c(
    "linear",
    "grimage",
    "fitage_composite",
    "physage",
    "pack_linear",
    "pack_systemsage",
    "dunedin",
    "epitoc2",
    "miage",
    "sex_routed",
    "unsupported"
  )
  tags <- vapply(mc_index$clock_id, score_type, character(1))
  expect_true(all(tags %in% known))
})
