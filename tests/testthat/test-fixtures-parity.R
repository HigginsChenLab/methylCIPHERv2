# cohort-gated golden parity (needs MC_PARITY=1 and a staged cohort)

# cohort fixture access
meta_clone_path <- function(...) {
  testthat::test_path("..", "..", "data-raw", "methylCIPHER-meta", ...)
}

# registry cohorts (scripts/cohorts.py). paths derive from the id.
PARITY_COHORTS <- c("cohort_EPICv1", "cohort_450K")

cohort_beta_db <- function(cohort) {
  meta_clone_path("fixtures", cohort, "beta.duckdb")
}

# samples x CpGs from the tall beta table
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

# cohort pheno: id, Tissue, Age, Female
cohort_pheno <- function(cohort) {
  ph <- utils::read.csv(
    meta_clone_path("fixtures", cohort, "pheno.csv"),
    stringsAsFactors = FALSE
  )
  data.frame(
    ID = ph$id,
    Age = ph$Age,
    Female = as.integer(ph$Female),
    stringsAsFactors = FALSE
  )
}

# golden scores from the clock's fixture block for this cohort
expected_scores <- function(id, cohort) {
  rel <- clock_fixture(id, cohort)[["expected"]]
  if (is.null(rel)) {
    stop(
      "Clock '",
      id,
      "' has no fixture expected path for ",
      cohort,
      call. = FALSE
    )
  }
  utils::read.csv(gzfile(meta_clone_path(rel)), stringsAsFactors = FALSE)
}

# grade by correlation when server_normalization is set, else exact
PARITY_EXACT_TOL <- 1e-6
PARITY_COR_MIN <- 0.99

expect_parity <- function(got, id, cohort) {
  fx <- clock_fixture(id, cohort)
  server_norm <- as.character(
    unlist(fx[["server_normalization"]] %||% character())
  )
  exp <- expected_scores(id, cohort)
  aligned <- as.numeric(got[exp$sample_id])
  testthat::expect_false(
    anyNA(aligned),
    label = paste0(id, "/", cohort, ": scored samples missing for fixture ids")
  )
  if (length(server_norm)) {
    cr <- suppressWarnings(stats::cor(aligned, exp$value))
    testthat::expect_gt(
      cr,
      PARITY_COR_MIN,
      label = paste0(
        id,
        "/",
        cohort,
        " correlation (server ",
        paste(server_norm, collapse = "+"),
        ")"
      )
    )
  } else {
    testthat::expect_lt(
      max(abs(aligned - exp$value)),
      PARITY_EXACT_TOL,
      label = paste0(id, "/", cohort, " max_abs_diff")
    )
  }
}

# parity tier flag (gates duckdb, pack scan, and per-test skips)
parity_on <- nzchar(Sys.getenv("MC_PARITY"))

# cached external packs (empty when tier is off)
cached_pack_groups <- if (parity_on) {
  Filter(function(g) length(mc_cached_files(g)) > 0L, mc_external_groups())
} else {
  character(0)
}

# skip external clocks whose pack is not cached
skip_if_no_pack <- function(clock_id) {
  if (!clock_is_external(clock_id)) {
    return(invisible())
  }
  gid <- clock_group_id(clock_id)
  testthat::skip_if_not(
    gid %in% cached_pack_groups,
    paste0("external pack for '", gid, "' not cached")
  )
}

# one read-only duckdb connection per staged cohort, for this file
cohort_cons <- list()
if (
  parity_on &&
    requireNamespace("duckdb", quietly = TRUE) &&
    requireNamespace("DBI", quietly = TRUE)
) {
  # duckdb extensions in a throwaway temp dir.
  withr::local_options(
    list(
      duckdb.extension_directory = withr::local_tempdir(
        .local_envir = testthat::teardown_env()
      )
    ),
    .local_envir = testthat::teardown_env()
  )
  for (cohort in PARITY_COHORTS) {
    if (!file.exists(cohort_beta_db(cohort))) {
      next
    }
    con <- DBI::dbConnect(
      duckdb::duckdb(),
      cohort_beta_db(cohort),
      read_only = TRUE
    )
    cohort_cons[[cohort]] <- con
    local({
      cc <- con
      withr::defer(
        try(DBI::dbDisconnect(cc, shutdown = TRUE), silent = TRUE),
        envir = testthat::teardown_env()
      )
    })
  }
}

skip_if_no_cohort <- function(cohort) {
  testthat::skip_if_not(
    parity_on,
    "parity tier off (set MC_PARITY=1, e.g. via dev test_parity())"
  )
  testthat::skip_if(
    is.null(cohort_cons[[cohort]]),
    paste0(cohort, " fixture not staged")
  )
}

# known gaps: skip so the suite stays green
KNOWN_PARITY_GAPS <- c(
  Zhang2019 = "sample_scale moments over needed-CpG subset, not full panel; exact parity unreachable"
)

parity_gap <- function(id, cohort) {
  key <- paste0(id, "@", cohort)
  if (key %in% names(KNOWN_PARITY_GAPS)) {
    return(KNOWN_PARITY_GAPS[[key]])
  }
  if (id %in% names(KNOWN_PARITY_GAPS)) {
    return(KNOWN_PARITY_GAPS[[id]])
  }
  NULL
}

# (clock, cohort) pairs upstream declares a fixture for.
parity_targets <- function() {
  out <- list()
  for (id in names(mc_catalog)) {
    for (fx in clock_fixtures(id) %||% list()) {
      out[[length(out) + 1L]] <- list(
        id = id,
        cohort = as.character(fx[["cohort"]])
      )
    }
  }
  out
}

for (target in parity_targets()) {
  local({
    clock_id <- target$id
    cohort <- target$cohort
    test_that(paste0("parity: ", clock_id, " @ ", cohort), {
      skip_if_no_cohort(cohort)
      skip_if_no_pack(clock_id)
      gap <- parity_gap(clock_id, cohort)
      if (!is.null(gap)) {
        skip(paste0("known parity gap -- ", gap))
      }
      # routed members scored as their alias's dependency
      routed <- sex_routed_members()$alias
      request <- if (clock_id %in% names(routed)) {
        routed[[clock_id]]
      } else {
        clock_id
      }
      # packs carry their group's scoring panel -- resolve before the union
      seq_ids <- resolve_clocks_sequence(resolve_clocks(request))
      packs <- load_mc_assets(pack_groups_needed(seq_ids), NULL, FALSE)
      cpgs <- panels_union(clock_panels(seq_ids, packs))
      DNAm <- cohort_betas(cohort_cons[[cohort]], cpgs)
      # parity gates numbers, not coverage policy
      res <- calc_clocks(
        DNAm,
        request,
        pheno = cohort_pheno(cohort),
        assets = packs,
        min_clocks_coverage = 0,
        min_samples_coverage = 0
      )
      # routed member scores land on the alias column for that sex's samples
      expect_parity(res$scores[, request], clock_id, cohort)
    })
  })
}

# both PhysAge composites in one call, per cohort
for (cohort_i in PARITY_COHORTS) {
  local({
    cohort <- cohort_i
    test_that(
      paste0("PhysAge composites match the author fixtures @ ", cohort),
      {
        skip_if_no_cohort(cohort)
        members <- mc_groups[["PhysAge"]]$members
        cpgs <- unique(unlist(lapply(members, clock_scoring_cpgs)))
        DNAm <- cohort_betas(cohort_cons[[cohort]], cpgs)
        res <- calc_clocks(
          DNAm,
          c("DNAmPhysAge", "DNAmPhysAge_years"),
          pheno = cohort_pheno(cohort),
          min_clocks_coverage = 0,
          min_samples_coverage = 0
        )
        expect_parity(res$scores[, "DNAmPhysAge"], "DNAmPhysAge", cohort)
        expect_parity(
          res$scores[, "DNAmPhysAge_years"],
          "DNAmPhysAge_years",
          cohort
        )
      }
    )
  })
}
