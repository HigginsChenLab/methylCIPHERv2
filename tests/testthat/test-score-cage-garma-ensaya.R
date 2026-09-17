# cAge, Garma, Ensaya: squared terms, two routers, a row mean.
# parity scores clean panels that sit well away from every cutoff, so it cannot
# see a squared fill, a tie, or a missing input.

# absent CpGs fill with the vendor mean, and a squared term squares the fill.
test_that("cAge squares after the fill, and keeps the model its age score picks", {
  skip_on_cran()
  gt <- "cAge_gt_20"
  le <- "cAge_le_20"
  tensors <- function(id) {
    list(
      coef = component_tensor_named(id, "coef"),
      sq = component_tensor_named(id, "coef_sq"),
      intercept = recipe_step_op(id, "linear")[["intercept"]]
    )
  }
  age <- tensors(gt)
  logage <- tensors(le)

  DNAm <- random_betas(clock_cpgs("cAge"), n = 4L)
  # one sample the age model puts far under 20, so both models are kept once
  weight <- c(age$coef, age$sq)
  DNAm[1, ] <- 0
  DNAm[1, names(weight)[weight < 0]] <- 1

  # held out: squared-only CpGs, CpGs with both weights, and linear ones
  sq_only <- setdiff(names(age$sq), names(age$coef))
  drop <- unique(c(
    sq_only[1:3],
    intersect(names(age$sq), names(age$coef))[1:3],
    names(logage$coef)[1:3]
  ))
  expect_true(length(sq_only) > 0L)

  full <- DNAm
  full[, drop] <- rep(clock_impute_ref(gt)[drop], each = nrow(full))
  model <- function(m) {
    m$intercept +
      as.numeric(full[, names(m$coef)] %*% m$coef) +
      as.numeric(full[, names(m$sq)]^2 %*% m$sq)
  }
  age_score <- model(age)
  years <- exp(model(logage))
  expect_true(any(age_score > 20) && any(age_score <= 20))

  res <- calc_clocks(DNAm[, setdiff(colnames(DNAm), drop)], "cAge")
  # the two models are pieces of cAge: scored and counted, never a column
  expect_equal(colnames(res$scores), "cAge")
  expect_equal(
    unname(res$scores[, "cAge"]),
    ifelse(age_score > 20, age_score, years),
    tolerance = 1e-10
  )
  expect_error(calc_clocks(DNAm, gt))
  expect_false(any(c(gt, le) %in% list_clocks()$clock_id))

  # each model counts its own panel, and the router counts nothing
  per_clock <- res$coverage$per_clock[[1]]
  for (id in c(gt, le)) {
    expect_equal(
      per_clock[[id]]$score_imputed_full,
      length(intersect(drop, clock_scoring_cpgs(id)))
    )
  }
  expect_null(per_clock[["cAge"]])
})

# the break and its tie come from the recipe: exactly 20 is the log(age) model
test_that("an age score at the cAge break follows the declared tie", {
  skip_on_cran()
  router <- c(19, 20, 20.5, NA, Inf)
  ids <- paste0("s", seq_along(router))
  results <- list(
    cAge_gt_20 = score_matrix(router, ids, "cAge_gt_20"),
    cAge_le_20 = score_matrix(1, ids, "cAge_le_20")
  )
  got <- score_cAge("cAge", NULL, list(sample_id = ids), results)
  # an age score that is not finite picks no model
  expect_equal(as.numeric(got), c(1, 1, 20.5, NA, NA))
})

# the breaks and ties come from the recipe: at most 36 is young, 59 and up is old
test_that("a Garma putative age at a break follows the declared tie", {
  skip_on_cran()
  router <- c(36, 36.5, 58.5, 59, NA, Inf)
  ids <- paste0("s", seq_along(router))
  results <- list(
    GarmaGeneral = score_matrix(router, ids, "GarmaGeneral"),
    GarmaYoung = score_matrix(1, ids, "GarmaYoung"),
    GarmaMiddle = score_matrix(2, ids, "GarmaMiddle"),
    GarmaOld = score_matrix(3, ids, "GarmaOld")
  )
  got <- score_Garma("Garma", NULL, list(sample_id = ids), results)
  # a putative age that is not finite picks no model
  expect_equal(as.numeric(got), c(1, 2, 2, 3, NA, NA))
})

# only the model a sample was routed to can cost it its cAge, and so its Ensaya
test_that("a gated cAge model matters only to the samples routed to it", {
  skip_on_cran()
  panel <- function(id) clock_scoring_cpgs(id)
  DNAm <- random_betas(clock_cpgs("Ensaya"), n = 4L)
  # every sample an adult: the age model's positive weights at 1, the rest at 0
  weight <- c(
    component_tensor_named("cAge_gt_20", "coef"),
    component_tensor_named("cAge_gt_20", "coef_sq")
  )
  DNAm[, names(weight)] <- 0
  DNAm[, names(weight)[weight > 0]] <- 1
  others <- union(panel("GarmaYoung"), panel("PAYA"))
  # sample 1 loses the log(age) model, sample 2 the age model
  DNAm[1, setdiff(panel("cAge_le_20"), c(panel("cAge_gt_20"), others))] <- NA_real_
  DNAm[2, setdiff(panel("cAge_gt_20"), c(panel("cAge_le_20"), others))] <- NA_real_

  expect_warning(res <- calc_clocks(DNAm, "Ensaya"))
  sc <- res$scores
  # the log(age) model is nobody's pick, so losing it costs sample 1 nothing
  expect_true(all(sc[-2, "cAge"] > 20))
  expect_true(all(is.finite(sc[-2, "Ensaya"])))
  expect_true(all(is.na(sc[2, c("cAge", "Ensaya")])))

  expect_warning(cov <- samples_coverage(res))
  cell <- function(sample, id) {
    cov[
      cov$id == rownames(DNAm)[sample] &
        cov$clock_id == id &
        cov$panel == "score",
    ]
  }
  # the counts stay on the model rows, and the note sits on a returned column.
  # cAge takes its model's own note: the model is not a column to point at.
  expect_true(cell(1, "cAge_le_20")$coverage < 0.75)
  expect_true(cell(2, "cAge_gt_20")$coverage < 0.75)
  expect_true(is.na(cell(1, "cAge")$note))
  expect_equal(cell(2, "cAge")$note, "sample_coverage")
  expect_equal(cell(2, "Ensaya")$note, "dependency")
})

test_that("Garma and Ensaya are assembled from the input columns they return", {
  skip_on_cran()
  DNAm <- random_betas(clock_cpgs(c("Garma", "Ensaya")), n = 6L)
  # one sample with no PAYA panel: a missing input is a missing mean
  bad <- 2L
  DNAm[bad, clock_cpgs("PAYA")] <- NA_real_

  expect_warning(res <- calc_clocks(DNAm, c("Garma", "Ensaya")))
  sc <- res$scores
  g <- sc[, "GarmaGeneral"]
  routed <- ifelse(
    g <= 36,
    sc[, "GarmaYoung"],
    ifelse(g < 59, sc[, "GarmaMiddle"], sc[, "GarmaOld"])
  )
  expect_equal(sc[, "Garma"], routed)
  expect_equal(sc[, "Ensaya"], rowMeans(sc[, c("cAge", "GarmaYoung", "PAYA")]))
  expect_true(is.na(sc[bad, "Ensaya"]))
  expect_true(all(is.finite(sc[-bad, "Ensaya"])))

  # neither composite counts CpGs, and the gap is explained by its input
  expect_null(res$coverage$per_clock[[1]][["Garma"]])
  expect_null(res$coverage$per_clock[[1]][["Ensaya"]])
  expect_warning(cov <- samples_coverage(res))
  note <- cov$note[cov$clock_id == "Ensaya" & cov$id == rownames(DNAm)[bad]]
  expect_equal(note, "dependency")
})
