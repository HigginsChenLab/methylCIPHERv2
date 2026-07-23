# Upfront coverage gate: a clock that cannot be scored stops before any scoring.

# A panel sharing no CpG with `ids`.
foreign_panel <- function(ids) {
  setdiff(clock_scoring_cpgs("PedBE"), unlist(lapply(ids, clock_scoring_cpgs)))
}

test_that("under-covered clocks stop instead of scoring", {
  cpgs <- clock_scoring_cpgs("Hannum")
  keep <- cpgs[seq_len(round(0.5 * length(cpgs)))]
  expect_error(calc_clocks(random_betas(keep, n = 4L), "Hannum"))


  # columns now clear; every row is still half-imputed, so the row gate warns
  expect_warning(
    res <- calc_clocks(
      random_betas(keep, n = 4L),
      "Hannum",
      min_col_coverage = 0.4
    )
  )
  expect_true(all(is.finite(res$scores[, "Hannum"])))
})

test_that("zero observed CpGs stops even at min_col_coverage = 0", {
  DNAm <- random_betas(foreign_panel(c("Hannum", "Horvath1", "EpiTOC")), n = 4L)
  for (id in c("Hannum", "Horvath1", "EpiTOC")) {
    expect_error(calc_clocks(DNAm, id, min_col_coverage = 0))
  }
})

test_that("a failing clock stops the call before other clocks score", {
  ok <- clock_scoring_cpgs("Hannum")
  bad <- clock_scoring_cpgs("PedBE")
  keep <- c(ok, bad[seq_len(round(0.3 * length(bad)))])
  DNAm <- random_betas(keep, n = 4L)

  expect_error(calc_clocks(DNAm, c("Hannum", "PedBE")))

  res <- calc_clocks(DNAm, "Hannum")
  expect_true(all(is.finite(res$scores[, "Hannum"])))
})

test_that("a sparse normalization panel warns but still scores (does not stop)", {
  skip_if_not_installed("betanorm")
  gold <- names(dunedin_gold_means("DunedinPACE"))
  model <- clock_scoring_cpgs("DunedinPACE")

  keep <- union(model, gold[seq_len(round(0.5 * length(gold)))])
  expect_warning(res <- calc_clocks(random_betas(keep, n = 4L), "DunedinPACE"))
  expect_true(all(is.finite(res$scores[, "DunedinPACE"])))
})

test_that("min_col_coverage does not gate clocks that clear it", {
  DNAm <- random_betas(clock_scoring_cpgs("Hannum"), n = 4L)
  expect_no_error(calc_clocks(DNAm, "Hannum", min_col_coverage = 1))
})

test_that("clearing min_col_coverage by under 10% warns instead of stopping", {
  cpgs <- clock_scoring_cpgs("Hannum")

  keep <- cpgs[seq_len(round(0.78 * length(cpgs)))]
  DNAm <- random_betas(keep, n = 4L)

  expect_warning(res <- calc_clocks(DNAm, "Hannum"))
  expect_true(all(is.finite(res$scores[, "Hannum"])))


  expect_silent(calc_clocks(random_betas(cpgs, n = 4L), "Hannum"))
})

# The row gate is not Dunedin-specific: it reads the record every branch
# returns, so any clock reporting coverage is checked.
test_that("an under-covered sample warns on an ordinary linear clock", {
  cpgs <- clock_scoring_cpgs("Hannum")
  DNAm <- random_betas(cpgs, n = 4L)
  DNAm[1, seq_len(round(0.5 * ncol(DNAm)))] <- NA

  expect_warning(res <- calc_clocks(DNAm, "Hannum"))
  expect_true(all(is.finite(res$scores[, "Hannum"])))

  expect_silent(calc_clocks(DNAm, "Hannum", min_row_coverage = 0))
})

test_that("the warn band scales with min_col_coverage and never fires at full coverage", {
  cpgs <- clock_scoring_cpgs("Hannum")
  keep <- cpgs[seq_len(round(0.78 * length(cpgs)))]
  DNAm <- random_betas(keep, n = 4L)

  expect_silent(calc_clocks(DNAm, "Hannum", min_col_coverage = 0.5))
  expect_silent(calc_clocks(
    random_betas(cpgs, n = 4L),
    "Hannum",
    min_col_coverage = 1
  ))
})
