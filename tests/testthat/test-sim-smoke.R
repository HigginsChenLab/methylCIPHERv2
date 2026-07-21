# Broad crash-smoke: every bundled, supported clock scores end-to-end on random betas
# without error. Complements the per-scorer value goldens and the cohort parity gate.
# External clocks are excluded -- sim_DNAm() has no scoring CpGs for them (pack-only).
# Age + Female are always supplied; clocks that do not need them ignore the extra columns.

bundled_smoke_clocks <- function() {
  ids <- names(mc_catalog)
  ids <- ids[!vapply(ids, clock_is_external, logical(1))]
  ids[vapply(ids, score_type, character(1)) != "unsupported"]
}

for (id in bundled_smoke_clocks()) {
  local({
    clock_id <- id
    test_that(paste0("sim_DNAm smoke: ", clock_id), {
      sim <- sim_DNAm(clock_id, n = 4L, Age = TRUE, Female = TRUE)
      expect_no_error(
        suppressWarnings(calc_clocks(sim$DNAm, clock_id, pheno = sim$pheno))
      )
    })
  })
}
