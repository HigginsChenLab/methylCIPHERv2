# Reproducible surrogate betas for the self-contained scorer tests. A thin, seeded wrapper over the
# package-internal random_betas() (R/sim_DNAm.R), so the matrix construction lives in exactly one
# place. The signature stays cpg-vector-first on purpose: these tests pass explicit CpG sets (e.g.
# names(clock_coefs(id))) and drop specific columns, which sim_DNAm()'s clock-token entry point does
# not offer. Default seed = 1L keeps the exact-equality assertions deterministic.
synthetic_betas <- function(cpgs, n = 6L, seed = 1L) {
  random_betas(cpgs, n = n, seed = seed)
}
