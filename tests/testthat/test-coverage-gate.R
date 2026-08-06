# coverage gates: neither floor aborts. both decide what does not get a number.

# a panel sharing no CpG with `ids`.
foreign_panel <- function(ids) {
  out <- setdiff(
    clock_scoring_cpgs("PedBE"),
    unlist(lapply(ids, clock_scoring_cpgs))
  )
  # a donor swallowed by the request would make every caller vacuous
  stopifnot(length(out) > 0L)
  out
}

test_that("under-covered clocks score NA instead of stopping", {
  cpgs <- clock_scoring_cpgs("Hannum")
  keep <- thin_panel(cpgs, 0.5)
  expect_warning(res <- calc_clocks(random_betas(keep, n = 4L), "Hannum"))
  expect_true(all(is.na(res$scores[, "Hannum"])))

  # a failing clock takes its own column, not the whole call
  bad <- thin_panel(clock_scoring_cpgs("PedBE"), 0.3)
  expect_warning(
    res <- calc_clocks(random_betas(c(cpgs, bad), n = 4L), c("Hannum", "PedBE"))
  )
  expect_true(all(is.finite(res$scores[, "Hannum"])))
  expect_true(all(is.na(res$scores[, "PedBE"])))

  # the two floors are independent. the column clears at 0.4, and every row is
  # still half-imputed, so the row gate blanks the same column on its own.
  expect_warning(
    res <- calc_clocks(
      random_betas(keep, n = 4L),
      "Hannum",
      min_clocks_coverage = 0.4
    )
  )
  expect_true(all(is.na(res$scores[, "Hannum"])))
})

test_that("zero observed CpGs is NA even at min_clocks_coverage = 0", {
  # the floor cannot express this: 0 < 0 is FALSE at every policy
  for (id in c("Hannum", "DNAmCRP")) {
    DNAm <- random_betas(foreign_panel(id), n = 4L)
    res <- suppressWarnings(calc_clocks(
      DNAm,
      id,
      min_clocks_coverage = 0,
      min_samples_coverage = 0
    ))
    expect_true(all(is.na(res$scores[, id])))
  }
})

test_that("the gate names a clock the caller is allowed to request", {
  skip_on_cran()
  routed <- sex_routed_members()
  member <- names(routed$alias)[[1]]
  alias <- routed$alias[[member]]

  # thin matrix on the alias must not print any member id.
  DNAm <- random_betas(thin_panel(clock_scoring_cpgs(member), 0.3), n = 4L)
  pheno <- mc_pheno(
    rownames(DNAm),
    Age = mc_ages(4L),
    Female = c(1L, 0L, 1L, 0L)
  )
  msg <- conditionMessage(tryCatch(
    calc_clocks(DNAm, alias, pheno = pheno),
    warning = function(w) w
  ))
  # it must be the coverage gate talking, not a missing-pheno abort
  expect_true(grepl("min_clocks_coverage", msg, fixed = TRUE))
  expect_true(grepl(alias, msg, fixed = TRUE))
  for (nm in names(routed$alias)) {
    expect_false(grepl(nm, msg, fixed = TRUE))
  }
})

test_that("a sparse normalization panel warns but still scores", {
  skip_if_not_installed("betanorm")
  gold <- names(clock_norm_target("DunedinPACE"))
  model <- clock_scoring_cpgs("DunedinPACE")

  keep <- union(model, thin_panel(gold, 0.5))
  # two distinct warnings: thin background (column) and the row gate below it
  expect_warning(
    expect_warning(
      res <- calc_clocks(random_betas(keep, n = 4L), "DunedinPACE")
    )
  )
  # the score panel is whole, so the clock itself is not gated out
  expect_true(all(is.na(res$scores[, "DunedinPACE"])))
  expect_no_warning(
    res <- calc_clocks(
      random_betas(keep, n = 4L),
      "DunedinPACE",
      min_clocks_coverage = 0.4,
      min_samples_coverage = 0.4
    )
  )
  expect_true(all(is.finite(res$scores[, "DunedinPACE"])))
})

test_that("a warn band sits above each floor, and both are silent at full", {
  cpgs <- clock_scoring_cpgs("Hannum")
  keep <- thin_panel(cpgs, 0.78)
  DNAm <- random_betas(keep, n = 4L)

  # clearing a floor by under 10% warns instead of blanking. one band each,
  # so pin the other floor out of the way to read them apart.
  expect_warning(
    res <- calc_clocks(DNAm, "Hannum", min_samples_coverage = 0)
  )
  expect_true(all(is.finite(res$scores[, "Hannum"])))
  expect_warning(res <- calc_clocks(DNAm, "Hannum", min_clocks_coverage = 0))
  expect_true(all(is.finite(res$scores[, "Hannum"])))

  # the bands move with their floors, and neither fires on a full panel
  expect_silent(calc_clocks(
    DNAm,
    "Hannum",
    min_clocks_coverage = 0.5,
    min_samples_coverage = 0.5
  ))
  expect_silent(calc_clocks(random_betas(cpgs, n = 4L), "Hannum"))
})

test_that("a gated clock does not break the clocks scored beside it", {
  cpgs <- clock_scoring_cpgs("Hannum")
  bad <- thin_panel(setdiff(clock_scoring_cpgs("PedBE"), cpgs), 0.3)
  DNAm <- random_betas(c(cpgs, bad), n = 12L)
  pheno <- mc_pheno(rownames(DNAm), Age = mc_ages(12L))

  expect_warning(
    res <- calc_clocks(DNAm, c("Hannum", "PedBE"), pheno = pheno)
  )
  expect_true(all(is.na(res$scores[, "PedBE"])))

  # an all-NA column is a reachable state now, and the two verbs answer it
  # differently on purpose: one row per sample stays, one row per clock goes.
  expect_warning(accel <- calc_accel(res, data = pheno))
  expect_true(all(is.finite(accel$accel[accel$clock_id == "Hannum"])))
  expect_true(all(is.na(accel$accel[accel$clock_id == "PedBE"])))
  expect_equal(score_associations(res, age = pheno$Age)$clock_id, "Hannum")
})

# row gate reads every branch's coverage record, not just Dunedin
test_that("an under-covered sample is NA on an ordinary linear clock", {
  cpgs <- clock_scoring_cpgs("Hannum")
  DNAm <- random_betas(cpgs, n = 4L)
  DNAm[1, seq_len(round(0.5 * ncol(DNAm)))] <- NA

  expect_warning(res <- calc_clocks(DNAm, "Hannum"))
  expect_true(is.na(res$scores[1, "Hannum"]))
  expect_true(all(is.finite(res$scores[-1, "Hannum"])))

  expect_silent(calc_clocks(DNAm, "Hannum", min_samples_coverage = 0))
})
