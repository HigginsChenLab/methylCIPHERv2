# summary.mc_result(): the digest built from samples_coverage().

test_that("the problem tables count the same notes two ways", {
  skip_on_cran()
  sim <- sim_DNAm("DNAmFitAge", n = 4L)
  DNAm <- sim[["DNAm"]]
  # gate one GrimAge surrogate, and leave one sample without a sex
  hole <- thin_panel(clock_scoring_cpgs("DNAmGDF15"), 0.6)
  DNAm <- DNAm[, setdiff(colnames(DNAm), hole), drop = FALSE]
  pheno <- mc_pheno(
    rownames(DNAm),
    Age = mc_ages(4L),
    Female = c(NA, 1L, 0L, 0L)
  )

  res <- suppressWarnings(calc_clocks(DNAm, "DNAmFitAge", pheno = pheno))
  out <- suppressWarnings(summary(res))
  cov <- suppressWarnings(samples_coverage(res))
  noted <- cov[!is.na(cov[["note"]]), , drop = FALSE]

  expect_s3_class(out, "mc_summary")
  # both halves are long, so neither collapses two notes onto one row
  expect_equal(sum(out[["by_clock"]][["n_samples"]]), nrow(noted))
  expect_equal(sum(out[["by_sample"]][["n_clocks"]]), nrow(noted))
  expect_equal(
    sort(unique(out[["by_clock"]][["note"]])),
    sort(unique(noted[["note"]]))
  )
  # a digest of one run states no batch it cannot name
  expect_null(out[["batches"]])
  expect_false("mc_batch_id" %in% names(out[["by_clock"]]))
})

test_that("the batch column appears with the frame it is derived from", {
  skip_on_cran()
  clocks <- c("Horvath1", "Hannum")
  one <- sim_DNAm(clocks, n = 4L, suffix = "_a")
  two <- sim_DNAm(clocks, n = 4L, suffix = "_b")
  res <- rbind(
    calc_clocks(one[["DNAm"]], clocks),
    calc_clocks(two[["DNAm"]], clocks)
  )

  out <- summary(res)
  cov <- samples_coverage(res)
  # the frame decides, and every table in the digest follows it
  expect_true("mc_batch_id" %in% names(cov))
  expect_equal(nrow(out[["input"]]), 2L)
  expect_equal(nrow(out[["arguments"]]), 2L)
  expect_equal(sort(out[["batches"]][["mc_batch_id"]]), sort(unique(cov[["mc_batch_id"]])))
  expect_equal(sum(out[["batches"]][["n_samples"]]), 8L)
  # never totalled across batches: each row keeps its own matrix
  expect_equal(nrow(unique(out[["input"]])), 2L)
})

test_that("a clean run reports no problems and no value columns", {
  skip_on_cran()
  clocks <- c("Horvath1", "Hannum")
  sim <- sim_DNAm(clocks, n = 5L)
  out <- summary(calc_clocks(sim[["DNAm"]], clocks))

  expect_equal(nrow(out[["by_clock"]]), 0L)
  expect_equal(nrow(out[["by_sample"]]), 0L)
  # min_val and max_val are seeded at the beta bounds, so they would read
  # 0 and 1 here and say nothing about the data
  expect_false(any(c("min_val", "max_val", "any_inf") %in% names(out[["input"]])))
  expect_no_error(utils::capture.output(print(out)))
})
