# zhang2019: full-matrix sample z-score, then linear sum. both arms
score_Zhang2019 <- function(id, cpgs, block, results) {
  coef <- clock_coefs(id, block[["packs"]])
  present <- cpgs[["score_present"]]

  # sample_scale over the full input matrix, banked by mc_cohort()
  mom <- block_domain_moments(block, id)
  m <- mom[["mean"]]
  s <- mom[["sd"]]

  lp <- linear_predictor(
    coef = coef,
    intercept = 0,
    cov_coefs = numeric(0),
    score_present = present,
    score_idx = cpgs[["score_present_idx"]],
    block = block
  )
  csum <- sum(coef[present])
  z_sum <- (as.numeric(lp[["cpg_contrib"]]) - m * csum) / s

  # the sample_scale domain is every column of DNAm, not this clock's panel, so
  # a sample needs 2 observed values in the whole matrix or its sd is NA.
  # same shape as score_DNAmSex_Wang(), and gap_reasons() reads the note.
  failed <- block[["sample_id"]][is.na(s)]
  note_scoring_failure(block, id, failed)
  say_moment_failure(id, failed)

  score_matrix(clock_intercept(id) + z_sum, block[["sample_id"]], id)
}
