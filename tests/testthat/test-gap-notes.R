# samples_coverage()$note: every NA score gets exactly one note, derived
# from the finished record and never stored.

# the rows that carry a note, in the shape the assertions below read
gaps_of <- function(res) {
  sc <- suppressWarnings(suppressMessages(samples_coverage(res)))
  out <- sc[!is.na(sc[["note"]]), c("id", "clock_id", "note")]
  rownames(out) <- NULL
  out
}

test_that("a gap propagates through the clocks calculated from it", {
  sim <- sim_DNAm("DNAmFitAge", n = 4L)
  DNAm <- sim$DNAm
  # gate one GrimAge surrogate. DNAmFitAge reads it two levels down.
  hole <- thin_panel(clock_scoring_cpgs("DNAmGDF15"), 0.6)
  DNAm <- DNAm[, setdiff(colnames(DNAm), hole), drop = FALSE]
  pheno <- mc_pheno(
    rownames(DNAm),
    Age = mc_ages(4L),
    Female = c(1L, 1L, 0L, 0L)
  )

  res <- suppressWarnings(calc_clocks(DNAm, "DNAmFitAge", pheno = pheno))
  gaps <- gaps_of(res)

  note_for <- function(id) unique(gaps$note[gaps$clock_id == id])
  expect_equal(note_for("DNAmGDF15"), "clock_coverage")
  # a clock that reads no CpGs of its own still gets a row to be explained on
  expect_equal(note_for("GrimAgeV1"), "dependency")
  expect_equal(note_for("DNAmFitAge"), "dependency")

  # one note per NA cell, and only for the clocks that lost one
  expect_equal(nrow(gaps), sum(is.na(res$scores)))
  expect_equal(
    sort(unique(gaps$clock_id)),
    sort(colnames(res$scores)[apply(is.na(res$scores), 2, any)])
  )
})

test_that("the notes are told apart, and a covariate outranks a floor", {
  cpgs <- clock_scoring_cpgs("DNAmVO2max_Female")
  DNAm <- random_betas(cpgs, n = 4L)
  # sample 1 loses half its panel, sample 3 has no known sex
  DNAm[1, seq_len(round(0.5 * ncol(DNAm)))] <- NA
  pheno <- mc_pheno(
    rownames(DNAm),
    Age = mc_ages(4L),
    Female = c(1L, 1L, NA, 1L)
  )

  res <- suppressWarnings(calc_clocks(DNAm, "DNAmVO2max", pheno = pheno))
  gaps <- gaps_of(res)
  note <- stats::setNames(gaps$note, gaps$id)
  expect_equal(note[["sample1"]], "sample_coverage")
  expect_equal(note[["sample3"]], "covariate")

  # under both a covariate gap and the clock floor, the covariate is reported
  res <- suppressWarnings(calc_clocks(
    DNAm[, seq_len(round(0.5 * ncol(DNAm)))],
    "DNAmVO2max",
    pheno = pheno
  ))
  gaps <- gaps_of(res)
  expect_true(all(is.na(res$scores[, "DNAmVO2max"])))
  expect_equal(gaps$note[gaps$id == "sample3"], "covariate")
  expect_equal(gaps$note[gaps$id == "sample1"], "clock_coverage")
})

# a score that is not a finite number is something that happened to the cell,
# so it carries a note like any other missing score.
test_that("a score that is not a finite number is noted", {
  skip_on_cran()
  # an all-zero row has no spread, so the sample z-score is 0/0, which is NaN.
  DNAm <- random_betas(clock_scoring_cpgs("Zhang2019EN"), n = 4L)
  DNAm[2, ] <- 0

  expect_warning(res <- suppressMessages(calc_clocks(DNAm, "Zhang2019EN")))
  expect_true(is.nan(res$scores[2, "Zhang2019EN"]))

  gaps <- gaps_of(res)
  expect_equal(nrow(gaps), 1L)
  expect_equal(gaps$id, "sample2")
  expect_equal(gaps$note, "not_finite")
})

# an infinite score is not NA at all, so the cell set has to reach past is.na()
test_that("an infinite score is noted", {
  skip_on_cran()
  # a constant row has no spread either, and divides to Inf rather than NaN
  DNAm <- random_betas(clock_scoring_cpgs("Zhang2019EN"), n = 4L)
  DNAm[2, ] <- 0.5

  expect_warning(res <- suppressMessages(calc_clocks(DNAm, "Zhang2019EN")))
  expect_true(is.infinite(res$scores[2, "Zhang2019EN"]))
  expect_equal(gaps_of(res)$note, "not_finite")
})

test_that("a sample the moments cannot describe is reported as a fit failure", {
  skip_on_cran()
  # one observed value leaves the per-sample sd NA. both floors are open, so
  # neither gate can explain the gap and only the branch's own note can.
  DNAm <- random_betas(clock_scoring_cpgs("Zhang2019EN"), n = 4L)
  DNAm[2, -1] <- NA_real_

  # the branch says so as well as noting it, like score_DNAmSex_Wang()
  expect_warning(
    res <- suppressMessages(calc_clocks(
      DNAm,
      "Zhang2019EN",
      min_clocks_coverage = 0,
      min_samples_coverage = 0
    ))
  )
  expect_true(is.na(res$scores[2, "Zhang2019EN"]))
  expect_equal(
    res$provenance$scoring_failures$Zhang2019EN,
    rownames(DNAm)[[2L]]
  )
  expect_equal(gaps_of(res)$note, "fit")
})

test_that("the column is present with no gaps, and sits before the label", {
  cpgs <- clock_scoring_cpgs("Hannum")
  full <- random_betas(cpgs, n = 4L)
  res <- calc_clocks(full, "Hannum")
  sc <- samples_coverage(res)
  expect_true("note" %in% names(sc))
  expect_true(all(is.na(sc$note)))

  # one batch scored, one gated. only the gated batch's samples get a note.
  short <- random_betas(thin_panel(cpgs, 0.5), n = 4L)
  rownames(short) <- paste0(rownames(short), "b")
  bound <- suppressMessages(rbind(res, suppressWarnings(calc_clocks(
    short,
    "Hannum"
  ))))
  sc <- suppressWarnings(suppressMessages(samples_coverage(bound)))
  # mc_batch_id is the join key and stays last, so note goes in front of it
  expect_equal(utils::tail(names(sc), 2L), c("note", "mc_batch_id"))
  expect_setequal(sc$id[!is.na(sc$note)], rownames(short))
})
