# Upfront coverage gate: a clock that cannot be scored stops before any scoring.

# A panel sharing no CpG with `ids`.
foreign_panel <- function(ids) {
  setdiff(clock_scoring_cpgs("PedBE"), unlist(lapply(ids, clock_scoring_cpgs)))
}

test_that("under-covered clocks stop instead of scoring", {
  cpgs <- clock_scoring_cpgs("Hannum")
  keep <- cpgs[seq_len(round(0.5 * length(cpgs)))]
  expect_error(calc_clocks(random_betas(keep, n = 4L), "Hannum"))

  # Same data passes once the threshold drops below actual coverage.
  res <- calc_clocks(random_betas(keep, n = 4L), "Hannum", min_coverage = 0.4)
  expect_true(all(is.finite(res$scores[, "Hannum"])))
})

test_that("zero observed CpGs stops even at min_coverage = 0", {
  DNAm <- random_betas(foreign_panel(c("Hannum", "Horvath1", "EpiTOC")), n = 4L)
  for (id in c("Hannum", "Horvath1", "EpiTOC")) {
    expect_error(calc_clocks(DNAm, id, min_coverage = 0))
  }
})

test_that("a failing clock stops the call before other clocks score", {
  ok <- clock_scoring_cpgs("Hannum")
  bad <- clock_scoring_cpgs("PedBE")
  keep <- c(ok, bad[seq_len(round(0.3 * length(bad)))])
  DNAm <- random_betas(keep, n = 4L)

  expect_error(calc_clocks(DNAm, c("Hannum", "PedBE")))
  # Hannum alone is fully covered by the same matrix.
  res <- calc_clocks(DNAm, "Hannum")
  expect_true(all(is.finite(res$scores[, "Hannum"])))
})

test_that("the gate covers the normalization panel, not just the scoring panel", {
  skip_if_not_installed("betanorm")
  gold <- names(dunedin_gold_means("DunedinPACE"))
  model <- clock_scoring_cpgs("DunedinPACE")
  # Full model panel, half the QN panel -> only the norm ratio fails.
  keep <- union(model, gold[seq_len(round(0.5 * length(gold)))])
  expect_error(calc_clocks(random_betas(keep, n = 4L), "DunedinPACE"))
})

test_that("min_coverage does not gate clocks that clear it", {
  DNAm <- random_betas(clock_scoring_cpgs("Hannum"), n = 4L)
  expect_no_error(calc_clocks(DNAm, "Hannum", min_coverage = 1))
})

# Coverage just above the floor scores, but says so.
test_that("clearing min_coverage by under 10% warns instead of stopping", {
  cpgs <- clock_scoring_cpgs("Hannum")
  # ~78% present: over the 0.75 floor, under the 0.825 warn line.
  keep <- cpgs[seq_len(round(0.78 * length(cpgs)))]
  DNAm <- random_betas(keep, n = 4L)

  expect_warning(res <- calc_clocks(DNAm, "Hannum"))
  expect_true(all(is.finite(res$scores[, "Hannum"])))

  # Comfortably clear -> silent.
  expect_silent(calc_clocks(random_betas(cpgs, n = 4L), "Hannum"))
})

test_that("the warn band scales with min_coverage and never fires at full coverage", {
  cpgs <- clock_scoring_cpgs("Hannum")
  keep <- cpgs[seq_len(round(0.78 * length(cpgs)))]
  DNAm <- random_betas(keep, n = 4L)

  # Same data, lower floor -> 0.78 is no longer marginal.
  expect_silent(calc_clocks(DNAm, "Hannum", min_coverage = 0.5))
  # Full coverage is never marginal, however high the floor.
  expect_silent(calc_clocks(random_betas(cpgs, n = 4L), "Hannum", min_coverage = 1))
})
