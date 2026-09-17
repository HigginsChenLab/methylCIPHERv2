# cAge, Garma, Ensaya: squared terms, a threshold pick, a router, a row mean.
# parity scores clean panels that sit well away from every cutoff, so it cannot
# see a squared fill, a tie, or a missing input.

# absent CpGs fill with the vendor mean, and a squared term squares the fill.
test_that("cAge squares after the fill, and keeps the model its age score picks", {
  skip_on_cran()
  id <- "cAge"
  tensor <- function(name) component_tensor_named(id, name)
  age <- list(coef = tensor("age_coef"), sq = tensor("age_sq_coef"))
  logage <- list(coef = tensor("logage_coef"), sq = tensor("logage_sq_coef"))
  rec <- clock_entry(id)[["recipe"]]

  DNAm <- random_betas(clock_cpgs(id), n = 4L)
  # one sample the age model puts far under 20, so both models are kept once
  weight <- c(age$coef, age$sq)
  DNAm[1, ] <- 0
  DNAm[1, names(weight)[weight < 0]] <- 1

  # held out: squared-only CpGs, CpGs with both weights, and linear ones
  sq_only <- setdiff(names(age$sq), names(age$coef))
  drop <- c(
    sq_only[1:3],
    intersect(names(age$sq), names(age$coef))[1:3],
    names(logage$coef)[1:3]
  )
  expect_true(length(sq_only) > 0L)

  full <- DNAm
  full[, drop] <- rep(clock_impute_ref(id)[drop], each = nrow(full))
  model <- function(m, out) {
    rec[[out]][["intercept"]] +
      as.numeric(full[, names(m$coef)] %*% m$coef) +
      as.numeric(full[, names(m$sq)]^2 %*% m$sq)
  }
  age_score <- model(age, "age_score")
  want <- ifelse(age_score > 20, age_score, exp(model(logage, "logage_score")))
  expect_true(any(age_score > 20) && any(age_score <= 20))

  res <- calc_clocks(DNAm[, setdiff(colnames(DNAm), drop)], id)
  expect_equal(unname(res$scores[, id]), want, tolerance = 1e-10)
  expect_equal(
    res$coverage$per_clock[[1]][[id]]$score_imputed_full,
    length(unique(drop))
  )
})

test_that("an age score of exactly 20 takes the log(age) model", {
  skip_on_cran()
  expect_equal(threshold_select(c(20, 20.5, NA), c(1, 2, 3), 20), c(1, 20.5, NA))
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
