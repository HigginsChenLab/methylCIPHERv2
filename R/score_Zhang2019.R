# Zhang2019: full-matrix sample z-score, then linear sum over present EN CpGs
score_Zhang2019 <- function(id, cpgs, DNAm, partial_cache = NULL) {
  sample_id <- rownames(DNAm)
  coef <- clock_coefs(id)
  present <- cpgs$score_present

  # moments over every available probe (not the EN subset)
  m <- matrixStats::rowMeans2(DNAm, na.rm = TRUE)
  s <- matrixStats::rowSds(DNAm, na.rm = TRUE)

  lp <- linear_predictor(
    coef = coef,
    intercept = 0,
    cov_coefs = numeric(0),
    score_present = present,
    DNAm = DNAm,
    partial_cache = partial_cache,
    id = id
  )
  csum <- sum(coef[present])
  z_sum <- (as.numeric(lp$cpg_contrib) - m * csum) / s
  score_matrix(clock_intercept(id) + z_sum, sample_id, id)
}
