# crash-smoke: every bundled callable clock scores on random betas without error

bundled_smoke_clocks <- function() {
  # callable pool only (routed members exercise via their alias)
  ids <- resolve_clocks("all")
  ids[!vapply(ids, clock_is_external, logical(1))]
}

for (id in bundled_smoke_clocks()) {
  local({
    clock_id <- id

    test_that(paste0("sim_DNAm smoke: ", clock_id), {
      sim <- sim_DNAm(clock_id, n = 4L, Age = TRUE, Female = TRUE)
      expect_no_error(
        suppressMessages(calc_clocks(sim$DNAm, clock_id, pheno = sim$pheno))
      )
    })
  })
}
