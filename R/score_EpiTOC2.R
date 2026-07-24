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
  score_matrix(
    2 * (as.numeric(lp$cpg_contrib) - ground) / length(present),
    sample_id,
    id
  )
}
