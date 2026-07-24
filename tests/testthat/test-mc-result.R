# mc_result S3 verb behavior

test_that("rbind refuses -- records cannot be stacked", {
  DNAm <- random_betas(clock_scoring_cpgs("Hannum"), n = 3L)
  res <- calc_clocks(DNAm, "Hannum")

  expect_s3_class(res, "mc_result")
  expect_error(rbind(res, res))
})
