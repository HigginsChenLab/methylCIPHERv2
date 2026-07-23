# DNAmFitAge engine wiring (synthetic betas).

fitage_pheno <- function(ids, female, age = NULL) {
  ph <- data.frame(
    ID = ids,
    Female = as.integer(female),
    stringsAsFactors = FALSE
  )
  if (!is.null(age)) {
    ph$Age <- age
  }
  ph
}

# Hand-compute one member (intercept + betas %*% coef + Age).
member_expected <- function(id, DNAm, rows, age) {
  coef <- clock_coefs(id)
  cov <- clock_covariate_coefs(id)
  out <- clock_intercept(id) +
    as.numeric(DNAm[rows, names(coef), drop = FALSE] %*% coef)
  if (length(cov)) {
    out <- out + cov[["Age"]] * age[rows]
  }
  out
}

test_that("the alias routes each sample to its own sex's model", {
  fem <- clock_coefs("DNAmGrip_wAge_Female")
  mal <- clock_coefs("DNAmGrip_wAge_Male")
  DNAm <- random_betas(union(names(fem), names(mal)), n = 6L)
  female <- c(1, 1, 1, 0, 0, 0)
  age <- seq(45, 70, length.out = 6)
  pheno <- fitage_pheno(rownames(DNAm), female, age)

  expect_identical(names(clock_covariate_coefs("DNAmGrip_wAge_Female")), "Age")

  got <- calc_clocks(DNAm, "DNAmGrip_wAge", pheno = pheno)$scores
  f <- which(female == 1)
  m <- which(female == 0)

  expected <- numeric(6)
  expected[f] <- member_expected("DNAmGrip_wAge_Female", DNAm, f, age)
  expected[m] <- member_expected("DNAmGrip_wAge_Male", DNAm, m, age)
  expect_equal(
    unname(got[, "DNAmGrip_wAge"]),
    unname(expected),
    tolerance = 1e-9
  )

  expect_true(all(is.na(got[m, "DNAmGrip_wAge_Female"])))
  expect_true(all(is.finite(got[f, "DNAmGrip_wAge_Female"])))
  expect_true(all(is.na(got[f, "DNAmGrip_wAge_Male"])))
  expect_true(all(is.finite(got[m, "DNAmGrip_wAge_Male"])))
})

test_that("coverage lands on the members, never on the alias", {
  fem <- clock_coefs("DNAmGrip_wAge_Female")
  mal <- clock_coefs("DNAmGrip_wAge_Male")
  DNAm <- random_betas(union(names(fem), names(mal)), n = 4L)
  pheno <- fitage_pheno(rownames(DNAm), c(1, 1, 0, 0), rep(50, 4))

  res <- calc_clocks(DNAm, "DNAmGrip_wAge", pheno = pheno)
  cov <- res$coverage$per_clock

  # Alias has no coverage; members do.
  expect_null(cov[["DNAmGrip_wAge"]])
  expect_true(all(is.na(res$coverage$sample_miss[, "DNAmGrip_wAge"])))

  expect_identical(cov[["DNAmGrip_wAge_Female"]]$score_needed, length(fem))
  expect_identical(cov[["DNAmGrip_wAge_Male"]]$score_needed, length(mal))
  expect_false(length(fem) == length(mal))
})

test_that("routed members are not directly callable and name their alias", {
  expect_true("DNAmGrip_wAge" %in% resolve_clocks("all"))
  expect_false("DNAmGrip_wAge_Female" %in% resolve_clocks("all"))
  expect_false(any(grepl("_(Female|Male)$", resolve_clocks("DNAmFitAge"))))
  expect_error(resolve_clocks("DNAmGrip_wAge_Female"), "DNAmGrip_wAge")
})

test_that("absent member CpGs vendor-fill from that sex's medians", {
  id <- "DNAmGait_noAge_Female"
  coef <- clock_coefs(id)
  medians <- clock_impute_ref(id)
  full <- union(names(coef), names(clock_coefs("DNAmGait_noAge_Male")))
  DNAm <- random_betas(full, n = 4L)
  pheno <- fitage_pheno(rownames(DNAm), rep(1L, 4L))

  drop <- intersect(names(coef), names(medians))[1:5]
  DNAm2 <- DNAm[, setdiff(colnames(DNAm), drop), drop = FALSE]
  res <- calc_clocks(DNAm2, "DNAmGait_noAge", pheno = pheno)

  present <- setdiff(names(coef), drop)
  expected <- clock_intercept(id) +
    as.numeric(DNAm2[, present, drop = FALSE] %*% coef[present]) +
    sum(coef[drop] * medians[drop])
  expect_equal(
    unname(res$scores[, "DNAmGait_noAge"]),
    unname(expected),
    tolerance = 1e-9
  )

  cov <- res$coverage$per_clock[[id]]
  expect_identical(cov$score_imputed_full, 5L)
  expect_identical(cov$score_dropped, 0L)
})


test_that("DNAmFitAge mixes same-sex members by KDM and carries no batch stamp", {
  seq_ids <- resolve_clocks_sequence(resolve_clocks("DNAmFitAge"))
  DNAm <- random_betas(panels_union(clock_panels(seq_ids)), n = 6L)
  female <- c(1, 1, 1, 0, 0, 0)
  pheno <- fitage_pheno(rownames(DNAm), female, seq(40, 65, length.out = 6))

  res <- calc_clocks(DNAm, "DNAmFitAge", pheno = pheno)
  sc <- res$scores
  expect_true(all(is.finite(sc[, "DNAmFitAge"])))

  expect_true(all(is.finite(sc[, "GrimAgeV1"])))

  expected <- rep(NA_real_, nrow(sc))
  for (sx in c("female", "male")) {
    member <- clock_routing("DNAmFitAge")[[sx]]
    rows <- if (sx == "female") which(female == 1) else which(female == 0)
    kdm <- fitage_kdm_params(member)
    acc <- numeric(length(rows))
    for (i in seq_len(nrow(kdm))) {
      acc <- acc +
        kdm$weight[i] *
          (sc[rows, kdm$component[i]] - kdm$center[i]) /
          kdm$scale[i]
    }
    expected[rows] <- acc
  }
  expect_equal(unname(sc[, "DNAmFitAge"]), unname(expected), tolerance = 1e-9)
  expect_null(res$provenance$batch_set_id)
})

test_that("the composite panel is its own inputs, not the family prep panel", {
  for (id in c("DNAmFitAge_Female", "DNAmFitAge_Male")) {
    n <- length(clock_scoring_cpgs(id))
    expect_lt(n, 627)
    expect_gt(n, 0)
  }

  expect_identical(clock_covariates_required("DNAmFitAge"), "Female")
  expect_identical(clock_covariates_required("DNAmFitAge_Female"), character(0))
})
