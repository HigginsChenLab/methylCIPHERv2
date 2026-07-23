# Crash-smoke: every bundled, supported clock scores on random betas without error.

bundled_smoke_clocks <- function() {
  # The callable pool, not the catalog: routed members are internal machinery
  # and are exercised here as their alias's dependencies.
  ids <- resolve_clocks("all")
  ids <- ids[!vapply(ids, clock_is_external, logical(1))]
  ids[vapply(ids, score_type, character(1)) != "unsupported"]
}

# betanorm soft dep for QN clocks.
betanorm_installed <- requireNamespace("betanorm", quietly = TRUE)

for (id in bundled_smoke_clocks()) {
  local({
    clock_id <- id
    # QN clocks need betanorm.
    needs_betanorm <- identical(clock_norm_scheme(clock_id), "quantile")
    test_that(paste0("sim_DNAm smoke: ", clock_id), {
      if (needs_betanorm) {
        skip_if_not(betanorm_installed, "betanorm not installed")
      }
      sim <- sim_DNAm(clock_id, n = 4L, Age = TRUE, Female = TRUE)
      expect_no_error(
        suppressWarnings(calc_clocks(sim$DNAm, clock_id, pheno = sim$pheno))
      )
    })
  })
}
