# External cpg_coefficient clocks (PCClocks, PCBrainAge) score on the shared linear engine
# from a loaded pack. These drive calc_clocks() end-to-end with an in-memory pack (closed
# set -> no disk, no network), so they are CRAN-safe and need no fixtures. PCBrainAge is the
# vehicle: one member, no covariates, sum reduction, identity transform, vendor_mean impute.

# A synthetic PCBrainAge pack over the clock's real scoring CpGs with chosen coefficients.
fake_pcbrainage_pack <- function(coef_vec, impute_vec = NULL) {
  cpgs <- clock_scoring_cpgs("PCBrainAge")
  if (is.null(impute_vec)) {
    impute_vec <- rep(0, length(cpgs))
  }
  list(
    group_id = "PCBrainAge",
    cpgs = cpgs,
    coefficient_matrix = matrix(
      coef_vec,
      ncol = 1L,
      dimnames = list(NULL, "PCBrainAge")
    ),
    impute = impute_vec
  )
}

test_that("calc_clocks() scores an external clock from an in-memory pack (closed set)", {
  cpgs <- clock_scoring_cpgs("PCBrainAge")
  coef_vec <- withr::with_seed(42, stats::rnorm(length(cpgs)))
  pack <- fake_pcbrainage_pack(coef_vec)
  DNAm <- synthetic_betas(cpgs, n = 3L)

  res <- calc_clocks(DNAm, "PCBrainAge", assets = pack)
  got <- res$scores[, "PCBrainAge"]

  # Full coverage -> no impute; sum reduction, identity transform.
  expected <- clock_intercept("PCBrainAge") + as.numeric(DNAm[, cpgs] %*% coef_vec)
  expect_equal(unname(got), unname(expected), tolerance = 1e-9)
  # No absent CpGs were vendor-filled.
  expect_identical(res$coverage$per_clock$PCBrainAge$score_imputed_full, 0L)
})

test_that("calc_clocks() vendor-fills absent external CpGs from the pack $impute vector", {
  cpgs <- clock_scoring_cpgs("PCBrainAge")
  coef_vec <- withr::with_seed(7, stats::rnorm(length(cpgs)))
  impute_vec <- withr::with_seed(8, stats::runif(length(cpgs)))
  names(coef_vec) <- cpgs
  names(impute_vec) <- cpgs
  pack <- fake_pcbrainage_pack(unname(coef_vec), unname(impute_vec))

  # Drop a handful of CpGs from the input so they must be vendor-filled.
  drop <- cpgs[1:5]
  present <- setdiff(cpgs, drop)
  DNAm <- synthetic_betas(cpgs, n = 3L)[, present, drop = FALSE]

  res <- calc_clocks(DNAm, "PCBrainAge", assets = pack)
  got <- res$scores[, "PCBrainAge"]

  expected <- clock_intercept("PCBrainAge") +
    as.numeric(DNAm[, present] %*% coef_vec[present]) +
    sum(coef_vec[drop] * impute_vec[drop])
  expect_equal(unname(got), unname(expected), tolerance = 1e-9)
  expect_identical(res$coverage$per_clock$PCBrainAge$score_imputed_full, 5L)
})

test_that("calc_clocks() on an external clock errors (closed set) when its pack is absent", {
  cpgs <- clock_scoring_cpgs("PCBrainAge")
  DNAm <- synthetic_betas(cpgs, n = 2L)
  # A closed set that carries the wrong group cannot satisfy PCBrainAge; no download.
  wrong <- list(
    group_id = "PCClocks",
    cpgs = "cg0001",
    coefficient_matrix = matrix(1, 1, dimnames = list(NULL, "PCADM")),
    impute = 0
  )
  expect_error(calc_clocks(DNAm, "PCBrainAge", assets = wrong))
})

# --- SystemsAge (Sehgal 2024): organ sub-clocks + Age_prediction + composite ------
# Scored from an in-memory pack (closed set -> no disk, no network). The recipe math
# is re-derived in-test for the golden; real cohort parity is the science gate
# (test-fixtures-parity.R, pack-gated).

test_that("calc_clocks() scores a SystemsAge organ sub-clock via the pack $organs column", {
  cpgs <- clock_scoring_cpgs("SystemsAge")
  pack <- fake_systemsage_pack(cpgs)
  DNAm <- synthetic_betas(cpgs, n = 3L)

  res <- calc_clocks(DNAm, "Blood", assets = pack)
  got <- res$scores[, "Blood"]

  # Organ member is plain linear: intercept + sum(coef * beta), full coverage.
  expected <- clock_intercept("Blood") +
    as.numeric(DNAm[, cpgs] %*% pack$organs[, "Blood"])
  expect_equal(unname(got), unname(expected), tolerance = 1e-9)
  expect_identical(res$coverage$per_clock$Blood$score_imputed_full, 0L)
})

test_that("calc_clocks() scores Age_prediction (age-linear front + quadratic) from the pack", {
  cpgs <- clock_scoring_cpgs("SystemsAge")
  pack <- fake_systemsage_pack(cpgs)
  DNAm <- synthetic_betas(cpgs, n = 3L)

  res <- calc_clocks(DNAm, "Age_prediction", assets = pack)
  got <- res$scores[, "Age_prediction"]

  L <- systemsage_age_intercept("Age_prediction") +
    as.numeric(DNAm[, cpgs] %*% pack$age)
  poly <- systemsage_poly("Age_prediction", "score")
  expected <- poly[1] + poly[2] * L + poly[3] * L^2
  expect_equal(unname(got), unname(expected), tolerance = 1e-9)
})

# The full systems_PCA composite recipe is exercised by cohort parity (test-fixtures-parity.R),
# the science gate. Here we only smoke that the whole group scores; see the next test.

test_that("calc_clocks('SystemsAge') scores the whole group (13 columns) in one closed-set call", {
  cpgs <- clock_scoring_cpgs("SystemsAge")
  pack <- fake_systemsage_pack(cpgs)
  DNAm <- synthetic_betas(cpgs, n = 3L)

  res <- calc_clocks(DNAm, "SystemsAge", assets = pack)
  members <- mc_index$clock_id[mc_index$group_id == "SystemsAge"]
  expect_setequal(colnames(res$scores), members)
  expect_equal(nrow(res$scores), 3L)
  expect_false(anyNA(res$scores))
})

test_that("calc_clocks() vendor-fills absent SystemsAge CpGs from the pack $impute vector", {
  cpgs <- clock_scoring_cpgs("SystemsAge")
  pack <- fake_systemsage_pack(cpgs)
  drop <- cpgs[1:4]
  present <- setdiff(cpgs, drop)
  DNAm <- synthetic_betas(cpgs, n = 3L)[, present, drop = FALSE]

  res <- calc_clocks(DNAm, "Age_prediction", assets = pack)
  got <- res$scores[, "Age_prediction"]

  ref <- stats::setNames(pack$impute, cpgs)
  age <- stats::setNames(pack$age, cpgs)
  L <- systemsage_age_intercept("Age_prediction") +
    as.numeric(DNAm[, present] %*% age[present]) +
    sum(age[drop] * ref[drop])
  poly <- systemsage_poly("Age_prediction", "score")
  expected <- poly[1] + poly[2] * L + poly[3] * L^2
  expect_equal(unname(got), unname(expected), tolerance = 1e-9)
  expect_identical(res$coverage$per_clock$Age_prediction$score_imputed_full, 4L)
})

# The closed-set "wrong pack -> error, no download" contract is covered once by the
# PCBrainAge case above; not re-asserted per external group.
