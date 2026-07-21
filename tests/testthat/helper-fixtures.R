# Cohort parity fixtures: shared plumbing for the cohort-gated golden-parity tests.
#
# The golden cohort (GSE286313 / EPICv1, 71 samples) lives in the methylCIPHER-meta clone under
# data-raw/methylCIPHER-meta/fixtures/ -- gitignored, regenerable via fixtures/build_cohort.R, and
# never committed into the package. So every reader here sits behind skip_if_no_cohort() and CRAN
# never runs it. Betas are raw (there is no local BMIQ twin): local scoring always starts from the
# raw `beta` table (see fixtures/cohort_EPIC/beta_schema.md).

# Absolute path into the meta clone (or a subpath of it), from the test working dir.
meta_clone_path <- function(...) {
  testthat::test_path("..", "..", "data-raw", "methylCIPHER-meta", ...)
}

# Absolute path into the meta clone's fixtures/ tree.
meta_fixtures_path <- function(...) {
  meta_clone_path("fixtures", ...)
}

# The on-disk cohort beta store. character(1); may be absent (skip gate below).
cohort_beta_db <- function() {
  meta_fixtures_path("cohort_EPIC", "beta.duckdb")
}

# Skip the calling test unless duckdb/DBI are installed and the cohort beta store is staged.
skip_if_no_cohort <- function() {
  testthat::skip_if_not_installed("duckdb")
  testthat::skip_if_not_installed("DBI")
  testthat::skip_if_not(file.exists(cohort_beta_db()), "EPIC cohort fixture not present")
}

# One read-only duckdb connection, memoized for the whole test run and closed at file teardown.
# The parity sweep opens ~76 clocks against the same 475 MB store, so a per-clock reconnect would
# be wasteful; the singleton keeps it to a single open. Safe to call from any parity test.
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

# Pull the requested CpGs from the tall `beta` table and return them samples x CpGs (the logical
# scoring orientation calc_clocks() wants). CpGs absent from the store simply do not appear -- the
# scorer's impute path then handles them, exactly as it would on real data. `con` from cohort_con().
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

# Canonical covariate surface for the cohort, from the committed pheno.csv (no duckdb needed).
# Maps the fixture's sample_id/age/sex onto the package pheno contract: an ID column plus the
# canonical Age / Female (0/1) covariates. Column names match calc_clocks(pheno_id = "ID").
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

# One clock's golden scores as data.frame(sample_id, value), 71 rows. The path comes from the
# clock's fixture stub ($expected, relative to the meta clone root) -- not a guessed filename.
expected_scores <- function(id) {
  rel <- clock_fixture(id)$expected
  if (is.null(rel)) {
    stop("Clock '", id, "' has no fixture$expected path.", call. = FALSE)
  }
  utils::read.csv(gzfile(meta_clone_path(rel)), stringsAsFactors = FALSE)
}

# Provisional exact-parity bound and correlation floor. The exact-tolerance *policy* is still under
# development (clocks that only miss a strict float-accumulation bound are skip-listed in
# test-fixtures-parity.R rather than pinned to a number here); this constant just keeps the clocks
# that already agree to float precision green.
PARITY_EXACT_TOL <- 1e-6
PARITY_COR_MIN <- 0.99

# Assert a clock's scores against its golden fixture, honoring the fixture's parity_policy:
#   exact       -> max_abs_diff < PARITY_EXACT_TOL
#   correlation -> cor(got, expected) > PARITY_COR_MIN
#   skipped     -> skip()
# `got` is the clock's named score vector (names = sample_id); it is aligned onto the fixture's
# sample order before comparison, and a missing sample is a failure (not a silent NA).
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
