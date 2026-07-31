# finalizer output: as.data.frame(mc_result) and clocks_accel()

# GrimAgeV1 requires Age + Female, so the record's pheno carries both.
# Hannum requires neither, so the two exercise the same fit from either side
ACCEL_CLOCKS <- c("GrimAgeV1", "Hannum")

# collect every warning an expression raises. a call that legitimately raises
# three of them cannot be read through nested expect_warning()
warnings_of <- function(expr) {
  msgs <- character(0)
  value <- withCallingHandlers(
    expr,
    warning = function(w) {
      msgs <<- c(msgs, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = value, msgs = msgs)
}

accel_fixture <- function(n = 12L) {
  DNAm <- random_betas(clock_cpgs(ACCEL_CLOCKS), n = n)
  pheno <- data.frame(
    ID = rownames(DNAm),
    Age = stats::rnorm(n, 45, 8),
    Female = rep(c(0, 1), length.out = n),
    stringsAsFactors = FALSE
  )
  list(
    DNAm = DNAm,
    pheno = pheno,
    res = calc_clocks(DNAm, ACCEL_CLOCKS, pheno = pheno)
  )
}

test_that("as.data.frame long and wide carry the same scores", {
  fx <- accel_fixture()
  wide <- as.data.frame(fx$res, long = FALSE)
  long <- as.data.frame(fx$res)
  clocks <- colnames(as.matrix(fx$res))

  # id first on both shapes. one batch, so no batch column
  expect_equal(names(wide), c("ID", clocks))
  expect_equal(names(long), c("ID", "clock_id", "score"))

  # wide is as.matrix() with an id column bolted on
  expect_equal(
    unname(as.matrix(wide[, clocks, drop = FALSE])),
    unname(as.matrix(fx$res))
  )
  # long is the same cells, clock-major
  expect_equal(long$score, as.vector(as.matrix(fx$res)))
  expect_equal(nrow(long), nrow(wide) * length(clocks))
  expect_equal(long$ID, rep(fx$pheno$ID, times = length(clocks)))

  # keyed by the id column only -- no row names
  expect_equal(attr(wide, "row.names"), seq_len(nrow(wide)))
  expect_equal(attr(long, "row.names"), seq_len(nrow(long)))
})

test_that("accel matches residuals(lm()) on the same samples", {
  fx <- accel_fixture()
  acc <- clocks_accel(fx$res, long = FALSE)
  scores <- as.matrix(fx$res)

  for (id in colnames(scores)) {
    d <- data.frame(y = scores[, id], Age = fx$pheno$Age)
    expect_equal(acc[[id]], unname(residuals(lm(y ~ Age, data = d))))
  }
})

test_that("formula sets the rhs and changes the answer", {
  fx <- accel_fixture()
  one <- clocks_accel(fx$res, long = FALSE)
  two <- clocks_accel(fx$res, ~ Age + Female, data = fx$pheno, long = FALSE)

  d <- data.frame(
    y = as.matrix(fx$res)[, "GrimAgeV1"],
    Age = fx$pheno$Age,
    Female = fx$pheno$Female
  )
  expect_equal(two$GrimAgeV1, unname(residuals(lm(y ~ Age + Female, data = d))))
  expect_false(isTRUE(all.equal(one$GrimAgeV1, two$GrimAgeV1)))
})

test_that("diff is the raw difference, and is stable under subsetting", {
  fx <- accel_fixture()
  half <- calc_clocks(
    fx$DNAm[1:6, , drop = FALSE],
    ACCEL_CLOCKS,
    pheno = fx$pheno[1:6, ]
  )

  d_full <- clocks_accel(fx$res, type = "diff", long = FALSE)
  d_half <- clocks_accel(half, type = "diff", long = FALSE)
  expect_equal(
    d_full$GrimAgeV1,
    unname(as.matrix(fx$res)[, "GrimAgeV1"] - fx$pheno$Age)
  )
  # the per-sample property: dropping samples does not move a diff
  expect_equal(d_half$GrimAgeV1, d_full$GrimAgeV1[1:6])

  # accel is cohort-relative, so it does move
  a_full <- clocks_accel(fx$res, long = FALSE)
  a_half <- clocks_accel(half, long = FALSE)
  expect_false(isTRUE(all.equal(a_half$GrimAgeV1, a_full$GrimAgeV1[1:6])))
})

test_that("diff constrains the age slope where accel estimates it", {
  fx <- accel_fixture()

  # an rhs that spans Age absorbs the constraint: subtracting a column of the
  # design changes the coefficients, never the residuals
  expect_equal(
    clocks_accel(fx$res, ~Age, type = "diff", long = FALSE)$GrimAgeV1,
    clocks_accel(fx$res, ~Age, type = "accel", long = FALSE)$GrimAgeV1
  )

  # an rhs that does not span Age keeps the two apart
  a <- clocks_accel(fx$res, ~Female, type = "accel", long = FALSE)
  b <- clocks_accel(fx$res, ~Female, type = "diff", long = FALSE)
  expect_false(isTRUE(all.equal(a$GrimAgeV1, b$GrimAgeV1)))
  d <- data.frame(
    y = as.matrix(fx$res)[, "GrimAgeV1"] - fx$pheno$Age,
    Female = fx$pheno$Female
  )
  expect_equal(b$GrimAgeV1, unname(residuals(lm(y ~ Female, data = d))))
})

test_that("an NA covariate drops that sample from every clock's fit", {
  fx <- accel_fixture()
  ph <- fx$pheno
  ph$Age[c(2L, 5L)] <- NA_real_
  expect_warning(res <- calc_clocks(fx$DNAm, ACCEL_CLOCKS, pheno = ph))

  # the pheno NA count is reported, not silent
  expect_warning(acc <- clocks_accel(res, long = FALSE))
  expect_true(all(is.na(acc$GrimAgeV1[c(2L, 5L)])))
  expect_equal(sum(!is.na(acc$GrimAgeV1)), nrow(ph) - 2L)

  # and the fit is over the surviving samples only
  keep <- !is.na(ph$Age)
  d <- data.frame(y = as.matrix(res)[, "GrimAgeV1"], Age = ph$Age)[keep, ]
  expect_equal(acc$GrimAgeV1[keep], unname(residuals(lm(y ~ Age, data = d))))
})

test_that("the NA drop is scoped to the formula's variables", {
  fx <- accel_fixture()
  ph <- fx$pheno
  ph$Female[c(1L, 3L)] <- NA_real_
  expect_warning(res <- calc_clocks(fx$DNAm, ACCEL_CLOCKS, pheno = ph))

  # Hannum needs no covariate, so every NA below comes from the pheno drop
  expect_equal(sum(is.na(clocks_accel(res, ~Age, long = FALSE)$Hannum)), 0L)
  expect_warning(both <- clocks_accel(res, ~ Age + Female, long = FALSE))
  expect_equal(which(is.na(both$Hannum)), c(1L, 3L))
})

test_that("data adds a column but may never change one", {
  fx <- accel_fixture()

  # the modal workflow: the same Age back, plus the new column
  expect_no_warning(clocks_accel(fx$res, ~ Age + Female, data = fx$pheno))
  # storage is not disagreement
  as_int <- fx$pheno
  as_int$Age <- round(as_int$Age)
  ok <- fx$pheno
  ok$Age <- as.integer(round(ok$Age))
  int_res <- calc_clocks(fx$DNAm, ACCEL_CLOCKS, pheno = as_int)
  expect_no_warning(clocks_accel(int_res, ~ Age + Female, data = ok))

  # a genuinely different Age is a different pheno, not a supplement
  bad <- fx$pheno
  bad$Age[[1L]] <- bad$Age[[1L]] + 5
  expect_error(clocks_accel(fx$res, ~ Age + Female, data = bad))

  # so is filling a gap the record was scored around
  gap <- fx$pheno
  gap$Age[[2L]] <- NA_real_
  expect_warning(res2 <- calc_clocks(fx$DNAm, ACCEL_CLOCKS, pheno = gap))
  expect_error(clocks_accel(res2, ~Age, data = fx$pheno))

  expect_error(clocks_accel(fx$res, ~Age, data = rbind(fx$pheno, fx$pheno)))
  expect_error(clocks_accel(
    fx$res,
    ~Age,
    data = fx$pheno[, "Age", drop = FALSE]
  ))
})

test_that("a covariate the record does not carry errors, and data fixes it", {
  n <- 8L
  DNAm <- random_betas(clock_scoring_cpgs("Hannum"), n = n)
  res <- calc_clocks(DNAm, "Hannum")
  # Hannum requires no covariates, so the record kept the id column alone
  expect_equal(names(res$pheno), "ID")

  expect_error(clocks_accel(res))
  # diff needs Age too, whatever the rhs says
  expect_error(clocks_accel(res, type = "diff"))

  ph <- data.frame(ID = rownames(DNAm), Age = stats::rnorm(n, 45, 8))
  expect_no_error(clocks_accel(res, data = ph))
  expect_error(clocks_accel(res, ~ Age + Smoking, data = ph))
  # a two-sided formula is not an rhs
  expect_error(clocks_accel(res, score ~ Age, data = ph))
})

test_that("too few samples to fit gives NA and one warning, not an error", {
  fx <- accel_fixture(n = 2L)
  clocks <- colnames(as.matrix(fx$res))
  expect_warning(acc <- clocks_accel(fx$res, long = FALSE))

  # every column is present and every one of them is NA
  expect_equal(names(acc), c("ID", clocks))
  expect_equal(nrow(acc), 2L)
  expect_true(all(is.na(as.matrix(acc[, clocks, drop = FALSE]))))
})

test_that("clocks with different missingness patterns each fit their own rows", {
  cl <- c("DNAmFitAge", "Hannum")
  n <- 12L
  DNAm <- random_betas(clock_cpgs(cl), n = n)
  ph <- data.frame(
    ID = rownames(DNAm),
    Age = stats::rnorm(n, 45, 8),
    Female = rep(c(0, 1), length.out = n),
    stringsAsFactors = FALSE
  )
  ph$Female[c(2L, 7L)] <- NA_real_
  expect_warning(res <- calc_clocks(DNAm, cl, pheno = ph))

  # ~ Age drops no rows, so the groups are the score NAs alone: the sex-routed
  # clocks are NA where Female is, Hannum is complete
  scores <- as.matrix(res)
  expect_true(all(is.na(scores[c(2L, 7L), "DNAmFitAge"])))
  expect_false(anyNA(scores[, "Hannum"]))

  acc <- clocks_accel(res, ~Age, long = FALSE)
  d <- data.frame(y = scores[, "Hannum"], Age = ph$Age)
  expect_equal(acc$Hannum, unname(residuals(lm(y ~ Age, data = d))))

  # the short group fits over the 10 rows it scored, and stays NA elsewhere
  fit <- !is.na(scores[, "DNAmFitAge"])
  d2 <- data.frame(y = scores[, "DNAmFitAge"], Age = ph$Age)[fit, ]
  expect_equal(acc$DNAmFitAge[fit], unname(residuals(lm(y ~ Age, data = d2))))
  expect_true(all(is.na(acc$DNAmFitAge[!fit])))
})

test_that("data may differ in storage but not in type", {
  fx <- accel_fixture()

  # integer against double is storage
  as_int <- fx$pheno
  as_int$Female <- as.integer(as_int$Female)
  expect_no_error(clocks_accel(fx$res, ~ Age + Female, data = as_int))

  # character against double is not, and neither is factor against double
  chr <- fx$pheno
  chr$Age <- as.character(chr$Age)
  expect_error(clocks_accel(fx$res, ~Age, data = chr))
  fct <- fx$pheno
  fct$Female <- factor(fct$Female)
  expect_error(clocks_accel(fx$res, ~ Age + Female, data = fct))
})

test_that("a sample data has no row for is reported, not silently NA-filled", {
  n <- 8L
  DNAm <- random_betas(clock_scoring_cpgs("Hannum"), n = n)
  res <- calc_clocks(DNAm, "Hannum")

  # ids that match nothing at all -- the case that used to warn only about
  # missing covariates, sending the user after phenotype data that is fine
  wrong <- data.frame(
    ID = sub("^sample", "Sample", rownames(DNAm)),
    Age = stats::rnorm(n, 45, 8),
    stringsAsFactors = FALSE
  )
  got <- warnings_of(clocks_accel(res, data = wrong, long = FALSE))
  # pinned because three warnings fire here and only one is this behaviour
  expect_true(any(grepl("no row for", got$msgs)))
  expect_true(all(is.na(got$value$Hannum)))

  # a complete data says nothing
  right <- data.frame(
    ID = rownames(DNAm),
    Age = stats::rnorm(n, 45, 8),
    stringsAsFactors = FALSE
  )
  expect_no_warning(clocks_accel(res, data = right))
})

test_that("mc_batch_id is a formula variable and is reserved against data", {
  n <- 10L
  mk <- function(tag) {
    m <- random_betas(clock_scoring_cpgs("Hannum"), n = n)
    rownames(m) <- paste0(rownames(m), "_", tag)
    m
  }
  m1 <- mk("T1")
  m2 <- mk("T2")
  both <- rbind(calc_clocks(m1, "Hannum"), calc_clocks(m2, "Hannum"))
  ph <- data.frame(
    ID = both$provenance$sample_id,
    Age = stats::rnorm(2L * n, 45, 8),
    stringsAsFactors = FALSE
  )

  # the record's own label, without the caller rebuilding it from provenance
  acc <- clocks_accel(both, ~ Age + mc_batch_id, data = ph, long = FALSE)
  d <- data.frame(
    y = as.matrix(both)[, "Hannum"],
    Age = ph$Age,
    b = both$provenance$mc_batch_id
  )
  expect_equal(acc$Hannum, unname(residuals(lm(y ~ Age + b, data = d))))

  # and it is a real model term, not decoration
  pooled <- clocks_accel(both, ~Age, data = ph, long = FALSE)
  expect_false(isTRUE(all.equal(acc$Hannum, pooled$Hannum)))

  # the name belongs to the record
  clash <- ph
  clash$mc_batch_id <- "mine"
  expect_error(clocks_accel(both, ~Age, data = clash))
})

test_that("a cohort-mean fill across batches is reported, never injected", {
  n <- 10L
  mk <- function(tag, na_frac) {
    m <- random_betas(clock_scoring_cpgs("Hannum"), n = n)
    rownames(m) <- paste0(rownames(m), "_", tag)
    if (na_frac > 0) {
      m[sample.int(length(m), floor(length(m) * na_frac))] <- NA_real_
    }
    m
  }
  ph <- function(x) {
    data.frame(
      ID = x$provenance$sample_id,
      Age = stats::rnorm(nrow(x$scores), 45, 8),
      stringsAsFactors = FALSE
    )
  }

  # filled in both batches -> the offset is real, so say so
  dirty <- rbind(
    calc_clocks(mk("A", 0.05), "Hannum"),
    calc_clocks(mk("B", 0.05), "Hannum")
  )
  expect_message(clocks_accel(dirty, ~Age, data = ph(dirty)))
  # naming it in the rhs is the fix, so the note stops
  expect_no_message(
    clocks_accel(dirty, ~ Age + mc_batch_id, data = ph(dirty))
  )

  # nothing was filled -> the batches are numerically irrelevant, so stay quiet
  clean <- rbind(
    calc_clocks(mk("C", 0), "Hannum"),
    calc_clocks(mk("D", 0), "Hannum")
  )
  expect_no_message(clocks_accel(clean, ~Age, data = ph(clean)))

  # and a single-batch record never has anything to say
  one <- calc_clocks(mk("E", 0.05), "Hannum")
  expect_no_message(clocks_accel(one, ~Age, data = ph(one)))
})

test_that("both finalizers re-finalize a bound cross-sample clock", {
  cl <- c("DNAmPhysAge", "Hannum")
  n <- 10L
  mk <- function(tag) {
    m <- random_betas(clock_cpgs(cl), n = n)
    rownames(m) <- paste0(rownames(m), "_", tag)
    m
  }
  r1 <- calc_clocks(mk("A"), cl)
  r2 <- calc_clocks(mk("B"), cl)
  expect_message(both <- rbind(r1, r2))
  expect_true("DNAmPhysAge" %in% names(both$provenance$pending))

  # the record still holds the per-batch reductions -- rbind never re-finalizes
  expect_message(df <- as.data.frame(both, long = FALSE))
  expect_message(done <- refinalize_clocks(both))
  expect_equal(df$DNAmPhysAge, unname(done$scores[, "DNAmPhysAge"]))
  expect_false(isTRUE(all.equal(
    df$DNAmPhysAge,
    unname(both$scores[, "DNAmPhysAge"])
  )))

  # accel too, so the two finalizers cannot disagree
  ph <- data.frame(
    ID = both$provenance$sample_id,
    Age = stats::rnorm(2L * n, 45, 8),
    stringsAsFactors = FALSE
  )
  expect_message(acc <- clocks_accel(both, ~Age, data = ph, long = FALSE))
  d <- data.frame(y = done$scores[, "DNAmPhysAge"], Age = ph$Age)
  expect_equal(acc$DNAmPhysAge, unname(residuals(lm(y ~ Age, data = d))))

  # a record with nothing pending says nothing
  expect_no_message(as.data.frame(r1))
})

test_that("accel long and wide agree, and long spans the full grid", {
  fx <- accel_fixture()
  wide <- clocks_accel(fx$res, long = FALSE)
  long <- clocks_accel(fx$res)
  clocks <- colnames(as.matrix(fx$res))

  expect_equal(names(long), c("ID", "clock_id", "accel"))
  expect_equal(nrow(long), nrow(wide) * length(clocks))
  expect_equal(long$accel, as.vector(as.matrix(wide[, clocks, drop = FALSE])))
  # the value column is named accel for both types
  expect_true("accel" %in% names(clocks_accel(fx$res, type = "diff")))
})
