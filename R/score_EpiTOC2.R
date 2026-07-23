# EpiTOC2 (tnsc): mean of 2*(beta-beta0)/(delta*(1-beta0)) over present CpGs
score_EpiTOC2 <- function(id, cpgs, DNAm, partial_cache = NULL) {
  sample_id <- rownames(DNAm)

  params <- epitoc2_params(id)
  present <- cpgs$score_present
  delta <- params$delta[present]
  beta0 <- params$beta0[present]
  coef <- 1 / (delta * (1 - beta0))

  lp <- linear_predictor(
    coef = coef,
    intercept = 0,
    cov_coefs = numeric(0),
    score_present = present,
    DNAm = DNAm,
    partial_cache = partial_cache,
    id = id
  )

  ground <- sum(coef * beta0)
  score <- score_matrix(
    2 * (as.numeric(lp$cpg_contrib) - ground) / length(present),
    sample_id,
    id
  )

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
