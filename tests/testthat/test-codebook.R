test_that("codebook describes clocks, a result, and refuses anything else", {
  cb <- codebook(c("Horvath1", "Hannum"))

  expect_equal(names(cb), c("column", "description"))
  expect_equal(cb[["column"]][1:2], c("meta_version", "clock_id"))
  expect_true(nzchar(cb[["description"]][[1L]]))
  expect_setequal(cb[["column"]][-(1:2)], c("Horvath1", "Hannum"))
  expect_false(anyNA(cb[["description"]]))

  sim <- sim_DNAm("Hannum", n = 3)
  res <- calc_clocks(sim[["DNAm"]], "Hannum")
  expect_equal(
    codebook(res)[["column"]],
    c("meta_version", "clock_id", "Hannum")
  )

  # a clock the descriptor table does not cover keeps NA, never a donor's value
  alias <- codebook("DNAmFitAge")
  expect_true(all(is.na(alias[["description"]][-(1:2)])))

  expect_error(codebook(42))
})
