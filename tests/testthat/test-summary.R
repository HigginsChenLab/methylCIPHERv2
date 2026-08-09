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
  # neither half collapses two notes onto one row. by_sample is the spread,
  # so its identity carries the sample count as well as the clock count.
  expect_equal(sum(out[["by_clock"]][["n_samples"]]), nrow(noted))
  expect_equal(
    sum(out[["by_sample"]][["n_clocks"]] * out[["by_sample"]][["n_samples"]]),
    nrow(noted)
  )
  # the spread states no sample id: that is what samples_coverage() is for
  expect_false("id" %in% names(out[["by_sample"]]))
  expect_equal(
    sort(unique(out[["by_clock"]][["note"]])),
    sort(unique(noted[["note"]]))
  )
  # the request and what it pulled in sum to the score columns, which is the
  # count the header states. a requested count alone never reconciled with it.
  expect_equal(
    length(out[["requested"]]) + length(out[["dependencies"]]),
    out[["n_clocks"]]
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
  expect_equal(
    sort(out[["batches"]][["mc_batch_id"]]),
    sort(unique(cov[["mc_batch_id"]]))
  )
  expect_equal(sum(out[["batches"]][["n_samples"]]), 8L)
  # never totalled across batches: each row keeps its own matrix
  expect_equal(nrow(unique(out[["input"]])), 2L)
})

# a column the gate refused is a failed clock, not a scored one, and the
# refusal is reported once rather than again by every read of the frame.
test_that("a clock that scored nothing is failed, and is refused once", {
  skip_on_cran()
  clocks <- c("Horvath1", "Hannum")
  sim <- sim_DNAm(clocks, n = 6L)
  # hole only Hannum, so the two clocks end the run in different states
  own <- setdiff(clock_scoring_cpgs("Hannum"), clock_scoring_cpgs("Horvath1"))
  DNAm <- sim[["DNAm"]]
  DNAm <- DNAm[, setdiff(colnames(DNAm), utils::head(own, 50L)), drop = FALSE]

  expect_warning(res <- calc_clocks(DNAm, clocks))
  expect_true(all(is.na(res[["scores"]][, "Hannum"])))

  out <- summary(res)
  expect_equal(out[["failed"]], "Hannum")
  expect_equal(out[["scored"]], "Horvath1")
  # both clocks were asked for, so neither is a dependency
  expect_equal(out[["dependencies"]], character(0))
  # the column gate already said so, so the frame does not say it again
  expect_no_warning(samples_coverage(res))
})

test_that("the printed digest carries the key to everything it shortens", {
  skip_on_cran()
  clocks <- c("Horvath1", "Hannum")
  mk <- function(sfx) {
    sim <- sim_DNAm(clocks, n = 6L, suffix = sfx)
    own <- setdiff(clock_scoring_cpgs("Hannum"), clock_scoring_cpgs("Horvath1"))
    DNAm <- sim[["DNAm"]]
    DNAm <- DNAm[, setdiff(colnames(DNAm), utils::head(own, 50L)), drop = FALSE]
    suppressWarnings(calc_clocks(DNAm, clocks))
  }
  out <- suppressWarnings(summary(suppressMessages(rbind(mk("_a"), mk("_b")))))
  txt <- utils::capture.output(print(out))

  # explanation trails the counts, and the batch key still ends the row
  expect_equal(
    names(out$by_clock),
    c("clock_id", "panel", "note", "n_samples", "explanation", "mc_batch_id")
  )
  # one batch at a time, so a capped table is never a mix of the two
  seq_batch <- match(out$by_clock$mc_batch_id, out$batches$mc_batch_id)
  expect_false(is.unsorted(seq_batch))

  # every token that printed has its phrase in the same output, stated once
  # rather than on each row it applies to
  phrase <- MC_NOTES[[unique(out$by_clock$note)[[1L]]]]
  expect_equal(sum(grepl(phrase, txt, fixed = TRUE)), 1L)

  # a shortened label is never the only form of itself on screen
  full <- out$batches$mc_batch_id
  expect_true(all(vapply(
    full,
    function(b) any(grepl(b, txt, fixed = TRUE)),
    logical(1L)
  )))
  expect_true(any(grepl(
    paste0(substr(full[[1L]], 1L, 7L), "..."),
    txt,
    fixed = TRUE
  )))
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
  expect_false(any(
    c("min_val", "max_val", "any_inf") %in% names(out[["input"]])
  ))
  expect_no_error(utils::capture.output(print(out)))
})
