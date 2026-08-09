# covariates=: point a canonical covariate at the caller's own column

# grip_fixture()'s pheno, with the covariate columns renamed away
renamed_pheno <- function(fx, Age = "age_yrs", Female = "sex_f") {
  ph <- fx[["pheno"]]
  names(ph)[names(ph) == "Age"] <- Age
  names(ph)[names(ph) == "Female"] <- Female
  ph
}

test_that("covariates= refuses a map it cannot honor", {
  fx <- grip_fixture()
  ph <- renamed_pheno(fx)
  score <- function(...) calc_clocks(fx[["DNAm"]], "DNAmGrip_wAge", ...)

  # unnamed: nothing says which covariate the column holds
  expect_error(score(pheno = ph, covariates = c("age_yrs", "sex_f")))
  expect_error(score(pheno = ph, covariates = c(Age = "age_yrs", "sex_f")))
  # a covariate this run does not read
  expect_error(score(pheno = ph, covariates = c(Age = "age_yrs", Cell = "cd8")))
  # a column that is not in pheno, named with the caller's own word
  expect_error(score(pheno = ph, covariates = c(Age = "no_such_column")))
  # nothing to point at
  expect_error(score(covariates = c(Age = "age_yrs")))
  # one covariate cannot be pointed at two columns
  expect_error(score(pheno = ph, covariates = c(Age = "age_yrs", Age = "sex_f")))

  # a run that reads no covariate has nothing to point
  expect_error(calc_clocks(
    random_betas(clock_cpgs("Hannum"), n = 4L),
    "Hannum",
    pheno = ph,
    covariates = c(Age = "age_yrs")
  ))

  # renaming onto a column that is already there would make two of one name
  both <- fx[["pheno"]]
  both[["age_yrs"]] <- both[["Age"]]
  expect_error(score(pheno = both, covariates = c(Age = "age_yrs")))
})

test_that("a pointed column scores as if it had been renamed", {
  skip_on_cran()
  fx <- grip_fixture()
  want <- calc_clocks(fx[["DNAm"]], "DNAmGrip_wAge", pheno = fx[["pheno"]])
  got <- calc_clocks(
    fx[["DNAm"]],
    "DNAmGrip_wAge",
    pheno = renamed_pheno(fx),
    covariates = c(Age = "age_yrs", Female = "sex_f")
  )

  expect_equal(got[["scores"]], want[["scores"]])
  # canonicalized, not restored: the record keeps one set of names
  expect_equal(names(got[["pheno"]]), names(want[["pheno"]]))
})

# the rename runs above check_pheno(), so the pheno gates still see the column.
# renaming lower down would silence exactly the callers who used the map.
test_that("pointing a column does not disarm the checks that read it", {
  skip_on_cran()
  fx <- grip_fixture()
  score <- function(ph) {
    calc_clocks(
      fx[["DNAm"]],
      "DNAmGrip_wAge",
      pheno = ph,
      covariates = c(Age = "age_yrs", Female = "sex_f")
    )
  }

  # Female outside 0/1 is still refused
  bad_sex <- renamed_pheno(fx)
  bad_sex[["sex_f"]] <- rep(2L, nrow(bad_sex))
  expect_error(score(bad_sex))

  # the age-units warning still fires
  months <- renamed_pheno(fx)
  months[["age_yrs"]] <- months[["age_yrs"]] * 12
  expect_warning(score(months))

  # and so does the missing-covariate warning
  gappy <- renamed_pheno(fx)
  gappy[["age_yrs"]][[1L]] <- NA_real_
  expect_warning(score(gappy))
})

test_that("calc_accel points its own data at a covariate", {
  skip_on_cran()
  DNAm <- random_betas(clock_cpgs("Hannum"), n = 6L)
  res <- calc_clocks(DNAm, "Hannum")
  ages <- mc_ages(6L)

  want <- calc_accel(res, data = mc_pheno(rownames(DNAm), Age = ages))
  ph <- mc_pheno(rownames(DNAm), Age = ages)
  names(ph)[names(ph) == "Age"] <- "age_yrs"
  got <- calc_accel(res, data = ph, covariates = c(Age = "age_yrs"))

  # the output column name comes from the formula, so it stays canonical
  expect_equal(got, want)

  # the units gate reads the canonical column here too
  months <- ph
  months[["age_yrs"]] <- ages * 12
  expect_warning(calc_accel(res, data = months, covariates = c(Age = "age_yrs")))
})

# predict_sex reads Female itself, and the clocks it scores read no covariate,
# so the map has to be resolved here rather than forwarded to calc_clocks().
test_that("predict_sex points its own pheno at the recorded sex", {
  skip_on_cran()
  sim <- sim_DNAm("DNAmSex_Wang", n = 6L, Female = TRUE)
  ph <- sim[["pheno"]]
  names(ph)[names(ph) == "Female"] <- "sex_f"

  want <- suppressMessages(predict_sex(sim[["DNAm"]], sim[["pheno"]]))
  got <- suppressMessages(predict_sex(
    sim[["DNAm"]],
    ph,
    covariates = c(Female = "sex_f")
  ))
  expect_equal(got, want)
  expect_true(all(c("recorded_sex", "sex_mismatch") %in% names(got)))

  # a covariate this call does not read is still refused
  expect_error(predict_sex(sim[["DNAm"]], ph, covariates = c(Age = "sex_f")))
  # and so is a column that is not there
  expect_error(predict_sex(
    sim[["DNAm"]],
    ph,
    covariates = c(Female = "no_such_column")
  ))
})
