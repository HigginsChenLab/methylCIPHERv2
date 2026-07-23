# DNAmFitAge_{Sex}: Klemera-Doubal mix of upstream member scores
score_DNAmFitAge <- function(
  id,
  cpgs,
  results,
  DNAm,
  partial_cache = NULL
) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  kdm <- fitage_kdm_params(id)

  comp_score <- function(component) {
    r <- results[[component]]
    if (is.null(r)) {
      stop(
        "score_DNAmFitAge(): ",
        id,
        " needs component '",
        component,
        "' but it was not computed upstream.",
        call. = FALSE
      )
    }
    as.numeric(r[["score"]])
  }

  score_vec <- numeric(n)
  for (i in seq_len(nrow(kdm))) {
    cv <- comp_score(kdm[["component"]][i])
    score_vec <- score_vec +
      kdm[["weight"]][i] * (cv - kdm[["center"]][i]) / kdm[["scale"]][i]
  }

  score_mat <- score_matrix(score_vec, sample_id, id)

  cached <- cached_cols(cpgs$score_present, partial_cache)
  sample_miss <- count_sample_miss(DNAm, cached)

  coverage <- list(
    clock_id = id,
    policy = clock_impute(id)[["policy"]],
    score_needed = length(cpgs$score_needed),
    score_present = length(cpgs$score_present),
    score_used = length(cpgs$score_present),
    score_imputed_partial = sum(sample_miss),
    score_imputed_full = length(cpgs$score_absent),
    score_dropped = 0L,
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = cpgs$score_absent
  )

  list(score = score_mat, coverage = coverage, sample_miss = sample_miss)
}
