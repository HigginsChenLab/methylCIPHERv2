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
  DNAm <- random_betas(cpgs, n = 3L)

  res <- calc_clocks(DNAm, "PCBrainAge", assets = pack)
  got <- res$scores[, "PCBrainAge"]

  # Full coverage -> no impute; sum reduction, identity transform.
  expected <- clock_intercept("PCBrainAge") +
    as.numeric(DNAm[, cpgs] %*% coef_vec)
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
  DNAm <- random_betas(cpgs, n = 3L)[, present, drop = FALSE]

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
  DNAm <- random_betas(cpgs, n = 2L)
  # A closed set that carries the wrong group cannot satisfy PCBrainAge; no download.
  wrong <- list(
    group_id = "PCClocks",
    cpgs = "cg0001",
    coefficient_matrix = matrix(1, 1, dimnames = list(NULL, "PCADM")),
    impute = 0
  )
  expect_error(calc_clocks(DNAm, "PCBrainAge", assets = wrong))
})

# --- PCClocks: the batched multi-member matmul --------------------------------------
# The whole PCClocks group scores in one shared subset + one gemm over all columns,
# with per-clock intercept, covariate term, and output transform (anti.trafo for the
# Horvath members). Golden = the per-clock linear formula computed in-test per column.

# Synthetic PCClocks pack over the shared panel: a coef column per member, vendor means.
fake_pcclocks_pack <- function(cpgs, seed = 3L) {
  members <- mc_index$clock_id[mc_index$group_id == "PCClocks"]
  withr::with_seed(seed, {
    M <- matrix(
      stats::rnorm(length(cpgs) * length(members)),
      length(cpgs),
      length(members),
      dimnames = list(NULL, members)
    )
    impute_vec <- stats::runif(length(cpgs))
  })
  list(
    group_id = "PCClocks",
    cpgs = cpgs,
    coefficient_matrix = M,
    impute = impute_vec
  )
}

test_that("calc_clocks('PCClocks') batches all members and matches the per-clock formula", {
  members <- mc_index$clock_id[mc_index$group_id == "PCClocks"]
  cpgs <- clock_scoring_cpgs("PCADM") # shared panel
  pack <- fake_pcclocks_pack(cpgs)
  DNAm <- random_betas(cpgs, n = 4L)
  pheno <- data.frame(
    ID = rownames(DNAm),
    Age = c(40, 55, 63, 71),
    Female = c(1L, 0L, 1L, 0L)
  )

  res <- calc_clocks(DNAm, "PCClocks", pheno = pheno, assets = pack)
  expect_setequal(colnames(res$scores), members)

  for (id in members) {
    lin <- clock_intercept(id) +
      as.numeric(DNAm[, cpgs] %*% pack$coefficient_matrix[, id])
    cov <- clock_covariate_coefs(id)
    if (length(cov)) {
      lin <- lin + as.numeric(as.matrix(pheno[, names(cov), drop = FALSE]) %*% cov)
    }
    tf <- if (identical(clock_output_transform(id), "anti.trafo")) {
      anti_trafo
    } else {
      identity
    }
    expect_equal(
      unname(res$scores[, id]),
      unname(tf(lin)),
      tolerance = 1e-8,
      info = id
    )
  }
})

test_that("requesting a subset of PCClocks returns only those columns (no expansion)", {
  cpgs <- clock_scoring_cpgs("PCADM")
  pack <- fake_pcclocks_pack(cpgs)
  DNAm <- random_betas(cpgs, n = 3L)
  pheno <- data.frame(
    ID = rownames(DNAm),
    Age = c(50, 60, 70),
    Female = c(0L, 1L, 1L)
  )

  sub <- calc_clocks(DNAm, c("PCHorvath1", "PCADM"), pheno = pheno, assets = pack)
  full <- calc_clocks(DNAm, "PCClocks", pheno = pheno, assets = pack)

  expect_setequal(colnames(sub$scores), c("PCHorvath1", "PCADM"))
  expect_equal(
    sub$scores[, c("PCHorvath1", "PCADM")],
    full$scores[, c("PCHorvath1", "PCADM")]
  )
})

# --- SystemsAge (Sehgal 2024): organ sub-clocks + Age_prediction + composite ------
# Scored from an in-memory pack (closed set -> no disk, no network). The recipe math
# is re-derived in-test for the golden; real cohort parity is the science gate
# (test-fixtures-parity.R, pack-gated).

# Synthetic SystemsAge pack over `cpgs`: organ/system coef columns, an age vector, and
# vendor means, plus a small self-consistent systems_PCA tensor tree keyed by the
# catalog's component file paths. Values are deterministic (seeded); goldens are the
# recipe math computed in-test. Mirrors the real encode_systemsage() layout.
fake_systemsage_pack <- function(cpgs, seed = 1L) {
  order <- systemsage_stack_order("SystemsAge") # 12 labels, stack order
  organs <- setdiff(order, "Age_prediction") # 11 organ labels
  ncpg <- length(cpgs)
  pcs <- paste0("PC", seq_len(12L))
  comp_file <- function(name) {
    comp <- Filter(
      function(x) identical(x$name, name),
      clock_components("SystemsAge")
    )
    comp[[1]]$file
  }
  withr::with_seed(seed, {
    organs_mat <- matrix(
      stats::rnorm(ncpg * 11L),
      ncpg,
      11L,
      dimnames = list(NULL, organs)
    )
    systems_mat <- matrix(
      stats::rnorm(ncpg * 11L),
      ncpg,
      11L,
      dimnames = list(NULL, organs)
    )
    age_vec <- stats::rnorm(ncpg)
    impute_vec <- stats::runif(ncpg)
    rot <- matrix(stats::rnorm(144L), 12L, 12L)
    center <- stats::setNames(stats::rnorm(12L), order)
    scale <- stats::setNames(stats::runif(12L, 0.5, 1.5), order)
    model <- stats::setNames(stats::rnorm(12L), pcs)
  })
  rot_df <- cbind(
    data.frame(system = order, stringsAsFactors = FALSE),
    stats::setNames(as.data.frame(rot), pcs)
  )
  list(
    group_id = "SystemsAge",
    cpgs = cpgs,
    organs = organs_mat,
    systems = systems_mat,
    age = age_vec,
    impute = impute_vec,
    tensors = stats::setNames(
      list(center, scale, rot_df, model),
      c(
        comp_file("systems_pca_center"),
        comp_file("systems_pca_scale"),
        comp_file("systems_pca_rotation"),
        comp_file("systems_model")
      )
    )
  )
}

test_that("calc_clocks() scores a SystemsAge organ sub-clock via the pack $organs column", {
  cpgs <- clock_scoring_cpgs("SystemsAge")
  pack <- fake_systemsage_pack(cpgs)
  DNAm <- random_betas(cpgs, n = 3L)

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
  DNAm <- random_betas(cpgs, n = 3L)

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
  DNAm <- random_betas(cpgs, n = 3L)

  res <- calc_clocks(DNAm, "SystemsAge", assets = pack)
  members <- mc_index$clock_id[mc_index$group_id == "SystemsAge"]
  expect_setequal(colnames(res$scores), members)
  expect_equal(nrow(res$scores), 3L)
  expect_false(anyNA(res$scores))
})

test_that("calc_clocks('SystemsAge') composite matches the re-derived systems_PCA recipe", {
  cpgs <- clock_scoring_cpgs("SystemsAge")
  pack <- fake_systemsage_pack(cpgs)
  DNAm <- random_betas(cpgs, n = 3L)

  res <- calc_clocks(DNAm, "SystemsAge", assets = pack)
  got <- res$scores[, "SystemsAge"]

  # Re-derive: age front -> poly-scaled Age_prediction column + 11 raw system predictors,
  # stacked in recipe order, centered/scaled, projected through systems_PCA, linear head.
  L <- systemsage_age_intercept("SystemsAge") +
    as.numeric(DNAm[, cpgs] %*% pack$age)
  ap_scaled <- sa_poly(L, systemsage_poly("SystemsAge", "ap_scaled"))
  order <- systemsage_stack_order("SystemsAge")
  organs_pca <- setdiff(order, "Age_prediction")
  raw_int <- systemsage_raw_intercepts("SystemsAge")
  sys <- vapply(
    organs_pca,
    function(org) raw_int[[org]] + as.numeric(DNAm[, cpgs] %*% pack$systems[, org]),
    numeric(nrow(DNAm))
  )
  stacked <- matrix(0, nrow(DNAm), length(order), dimnames = list(NULL, order))
  stacked[, "Age_prediction"] <- ap_scaled
  stacked[, organs_pca] <- sys
  pca <- systemsage_pca("SystemsAge", list(SystemsAge = pack), order)
  cs <- sweep(sweep(stacked, 2L, pca$center, "-"), 2L, pca$scale, "/")
  expected <- as.numeric(
    systemsage_final_intercept("SystemsAge") + (cs %*% pca$rotation) %*% pca$model
  )
  expect_equal(unname(got), unname(expected), tolerance = 1e-8)
})

test_that("calc_clocks() vendor-fills absent SystemsAge CpGs from the pack $impute vector", {
  cpgs <- clock_scoring_cpgs("SystemsAge")
  pack <- fake_systemsage_pack(cpgs)
  drop <- cpgs[1:4]
  present <- setdiff(cpgs, drop)
  DNAm <- random_betas(cpgs, n = 3L)[, present, drop = FALSE]

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
