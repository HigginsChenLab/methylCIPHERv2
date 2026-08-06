# score_gaps(): every NA score gets exactly one reason, derived from the record

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
  gaps <- suppressMessages(score_gaps(res))

  reason_for <- function(id) unique(gaps$reason[gaps$clock_id == id])
  expect_equal(reason_for("DNAmGDF15"), "clock_coverage")
  expect_equal(reason_for("GrimAgeV1"), "dependency")
  expect_equal(reason_for("DNAmFitAge"), "dependency")

  # one row per NA cell, and only for the clocks that lost one
  expect_equal(nrow(gaps), sum(is.na(res$scores)))
  expect_equal(
    sort(unique(gaps$clock_id)),
    sort(colnames(res$scores)[apply(is.na(res$scores), 2, any)])
  )
})

test_that("the reasons are told apart, and a covariate outranks a floor", {
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
  gaps <- suppressMessages(score_gaps(res))
  reason <- stats::setNames(gaps$reason, gaps$id)
  expect_equal(reason[["sample1"]], "sample_coverage")
  expect_equal(reason[["sample3"]], "covariate")

  # under both a covariate gap and the clock floor, the covariate is reported
  res <- suppressWarnings(calc_clocks(
    DNAm[, seq_len(round(0.5 * ncol(DNAm)))],
    "DNAmVO2max",
    pheno = pheno
  ))
  gaps <- suppressMessages(score_gaps(res))
  expect_true(all(is.na(res$scores[, "DNAmVO2max"])))
  expect_equal(gaps$reason[gaps$id == "sample3"], "covariate")
  expect_equal(gaps$reason[gaps$id == "sample1"], "clock_coverage")
})

test_that("the frame keeps its shape with no gaps, and labels a bind", {
  cpgs <- clock_scoring_cpgs("Hannum")
  full <- random_betas(cpgs, n = 4L)
  res <- calc_clocks(full, "Hannum")
  gaps <- score_gaps(res)
  expect_equal(nrow(gaps), 0L)
  expect_equal(names(gaps), c("id", "clock_id", "reason"))

  # one batch scored, one gated. only the gated batch's samples get rows.
  short <- random_betas(thin_panel(cpgs, 0.5), n = 4L)
  rownames(short) <- paste0(rownames(short), "b")
  bound <- suppressMessages(rbind(res, suppressWarnings(calc_clocks(
    short,
    "Hannum"
  ))))
  gaps <- suppressMessages(score_gaps(bound))
  expect_equal(names(gaps), c("id", "clock_id", "reason", "mc_batch_id"))
  expect_equal(sort(gaps$id), sort(rownames(short)))
  expect_equal(length(unique(gaps$mc_batch_id)), 1L)
})
