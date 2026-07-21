# Cohort parity helpers. Golden cohort lives in data-raw/methylCIPHER-meta/fixtures/
# (gitignored); every reader sits behind skip_if_no_cohort() so CRAN never runs it.

meta_clone_path <- function(...) {
  testthat::test_path("..", "..", "data-raw", "methylCIPHER-meta", ...)
}

meta_fixtures_path <- function(...) {
  meta_clone_path("fixtures", ...)
}

cohort_beta_db <- function() {
  meta_fixtures_path("cohort_EPIC", "beta.duckdb")
}

skip_if_no_cohort <- function() {
  testthat::skip_if_not_installed("duckdb")
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not(file.exists(cohort_beta_db()), "EPIC cohort fixture not present")
}

# One read-only duckdb connection for the whole test run.
.cohort_env <- new.env(parent = emptyenv())
cohort_con <- function() {
  if (is.null(.cohort_env$con)) {
    .cohort_env$con <- DBI::dbConnect(
      duckdb::duckdb(),
      cohort_beta_db(),
      read_only = TRUE
    )
    withr::defer(
      {
        try(DBI::dbDisconnect(.cohort_env$con, shutdown = TRUE), silent = TRUE)
        .cohort_env$con <- NULL
      },
      envir = testthat::teardown_env()
    )
  }
  .cohort_env$con
}

# Samples x CpGs from the tall beta table. Absent CpGs are omitted (scorer imputes).
cohort_betas <- function(con, cpgs) {
  raw <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT * FROM beta WHERE cpg IN (%s)",
      paste0("'", cpgs, "'", collapse = ",")
    )
  )
  mat <- as.matrix(raw[, setdiff(names(raw), "cpg"), drop = FALSE])
  rownames(mat) <- raw$cpg
  t(mat)
}

# Cohort pheno: ID + Age + Female (0/1).
cohort_pheno <- function() {
  ph <- utils::read.csv(
    meta_fixtures_path("cohort_EPIC", "pheno.csv"),
    stringsAsFactors = FALSE
  )
  data.frame(
    ID = ph$sample_id,
    Age = ph$age,
    Female = as.integer(tolower(ph$sex) == "female"),
    stringsAsFactors = FALSE
  )
}

# Golden scores from the clock's fixture$expected path.
expected_scores <- function(id) {
  rel <- clock_fixture(id)$expected
  if (is.null(rel)) {
    stop("Clock '", id, "' has no fixture$expected path.", call. = FALSE)
  }
  utils::read.csv(gzfile(meta_clone_path(rel)), stringsAsFactors = FALSE)
}

PARITY_EXACT_TOL <- 1e-6
PARITY_COR_MIN <- 0.99

# Assert scores vs golden: exact, correlation, or skipped per fixture parity_policy.
expect_parity <- function(got, id) {
  policy <- clock_fixture(id)$parity_policy
  if (identical(policy, "skipped")) {
    testthat::skip(paste0("fixture parity_policy = 'skipped' for ", id))
  }
  exp <- expected_scores(id)
  aligned <- as.numeric(got[exp$sample_id])
  testthat::expect_false(
    anyNA(aligned),
    label = paste0(id, ": scored samples missing for some fixture ids")
  )
  if (identical(policy, "exact")) {
    mad <- max(abs(aligned - exp$value))
    testthat::expect_lt(mad, PARITY_EXACT_TOL, label = paste0(id, " max_abs_diff"))
  } else if (identical(policy, "correlation")) {
    cr <- suppressWarnings(stats::cor(aligned, exp$value))
    testthat::expect_gt(cr, PARITY_COR_MIN, label = paste0(id, " correlation"))
  } else {
    stop("Unknown parity_policy '", policy, "' for ", id, ".", call. = FALSE)
  }
}
