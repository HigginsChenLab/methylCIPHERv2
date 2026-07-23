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
  score <- score_matrix(clock_intercept(id) + z_sum, sample_id, id)

  sample_miss <- count_sample_miss(DNAm, lp$cached)

  coverage <- list(
    clock_id = id,
    policy = clock_impute(id)[["policy"]],
    score_needed = length(cpgs$score_needed),
    score_present = length(present),
    score_used = length(lp$used_cols),
    score_imputed_partial = sum(sample_miss),
    score_imputed_full = 0L,
    score_dropped = length(cpgs$score_absent),
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = cpgs$score_absent
  )

  list(score = score, coverage = coverage, sample_miss = sample_miss)
}
