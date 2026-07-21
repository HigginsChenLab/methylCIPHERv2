# DNAmFitAge engine wiring (self-contained synthetic betas; CRAN-safe).
# Author parity is test-fixtures-parity.R (currently skip-listed).

member_models <- function(id) {
  op <- fitage_score_op(id)
  list(
    op = op,
    female = fitage_component_tensor(id, op$female_coef),
    male = fitage_component_tensor(id, op$male_coef)
  )
}

fitage_pheno <- function(ids, female, age = NULL) {
  ph <- data.frame(ID = ids, Female = as.integer(female), stringsAsFactors = FALSE)
  if (!is.null(age)) {
    ph$Age <- age
  }
  ph
}

test_that("a linear_sex member routes each sex to its own model and reduces by sum", {
  m <- member_models("DNAmGait_noAge") # noAge -> Female is the splitter, no model covariate
  cpgs <- union(names(m$female), names(m$male))
  DNAm <- synthetic_betas(cpgs, n = 6L)
  ids <- rownames(DNAm)
  female <- c(1, 1, 1, 0, 0, 0)
  pheno <- fitage_pheno(ids, female)

  got <- calc_clocks(DNAm, "DNAmGait_noAge", pheno = pheno)$scores[, "DNAmGait_noAge"]

  fem <- which(female == 1)
  mal <- which(female == 0)
  expected <- numeric(6)
  expected[fem] <- m$op$female_intercept +
    as.numeric(DNAm[fem, names(m$female), drop = FALSE] %*% m$female)
  expected[mal] <- m$op$male_intercept +
    as.numeric(DNAm[mal, names(m$male), drop = FALSE] %*% m$male)

  expect_equal(unname(got[ids]), unname(expected), tolerance = 1e-9)

  # Unselected sex must not leak its intercept into the other sex.
  expect_false(isTRUE(all.equal(unname(got[fem][1]), unname(got[mal][1]))))
})

test_that("absent member CpGs vendor-fill by sex median (offset, never dropped)", {
  m <- member_models("DNAmGait_noAge")
  medians <- fitage_sex_medians("DNAmGait_noAge")
  cpgs <- union(names(m$female), names(m$male))
  DNAm <- synthetic_betas(cpgs, n = 4L)
  ids <- rownames(DNAm)
  pheno <- fitage_pheno(ids, female = rep(1L, 4L)) # all female -> one model, easy to reconstruct

  # Drop 5 female-model CpGs; they re-enter as coef * median.
  drop <- intersect(names(m$female), names(medians$female))[1:5]
  DNAm2 <- DNAm[, setdiff(colnames(DNAm), drop), drop = FALSE]
  res <- calc_clocks(DNAm2, "DNAmGait_noAge", pheno = pheno)

  present <- setdiff(names(m$female), drop)
  expected <- m$op$female_intercept +
    as.numeric(DNAm2[, present, drop = FALSE] %*% m$female[present]) +
    sum(m$female[drop] * medians$female[drop])
  expect_equal(
    unname(res$scores[, "DNAmGait_noAge"]),
    unname(expected),
    tolerance = 1e-9
  )

  cov <- res$coverage$per_clock[["DNAmGait_noAge"]]
  expect_identical(cov$score_imputed_full, 5L)
  expect_identical(cov$score_dropped, 0L)
})

test_that("a FitAge member requires the Female covariate", {
  m <- member_models("DNAmGait_noAge")
  DNAm <- synthetic_betas(union(names(m$female), names(m$male)), n = 3L)
  expect_error(
    calc_clocks(DNAm, "DNAmGait_noAge", pheno = NULL),
    "Female",
    ignore.case = TRUE
  )
})

# Full plan (members + GrimAgeV1): dep expansion, KDM mix, no batch stamp.
test_that("DNAmFitAge expands deps, mixes them by KDM, and carries no batch stamp", {
  cpgs <- needed_cpgs_union(resolve_clocks_sequence(resolve_clocks("DNAmFitAge")))
  DNAm <- synthetic_betas(cpgs, n = 6L)
  ids <- rownames(DNAm)
  female <- c(1, 1, 1, 0, 0, 0)
  pheno <- fitage_pheno(ids, female, age = seq(40, 65, length.out = 6))

  res <- calc_clocks(DNAm, "DNAmFitAge", pheno = pheno)
  sc <- res$scores

  # Composite deps are auto-added as their own columns.
  expect_true(all(
    c("DNAmFitAge", "DNAmGait_noAge", "DNAmGrip_noAge", "DNAmVO2max", "GrimAgeV1") %in%
      colnames(sc)
  ))
  expect_true(all(is.finite(sc[, "DNAmFitAge"])))

  # Reconstruct composite via KDM params (reuses upstream score columns).
  kdm <- fitage_kdm_params("DNAmFitAge")
  grim <- fitage_grim_dep("DNAmFitAge")
  col_of <- function(comp) if (identical(comp, "DNAmGrimAge")) grim else comp
  fem_by_id <- stats::setNames(as.integer(pheno$Female), pheno$ID)[rownames(sc)]

  expected <- rep(NA_real_, nrow(sc))
  for (sx in c("female", "male")) {
    rows <- if (sx == "female") which(fem_by_id == 1) else which(fem_by_id == 0)
    if (!length(rows)) next
    krows <- kdm[kdm$sex == sx, , drop = FALSE]
    acc <- numeric(length(rows))
    for (i in seq_len(nrow(krows))) {
      cv <- sc[rows, col_of(krows$component[i])]
      acc <- acc + krows$weight[i] * (cv - krows$center[i]) / krows$scale[i]
    }
    expected[rows] <- acc
  }
  expect_equal(unname(sc[, "DNAmFitAge"]), unname(expected), tolerance = 1e-9)

  # DNAmFitAge is not batch-dependent.
  expect_null(res$provenance$batch_set_id)
})
