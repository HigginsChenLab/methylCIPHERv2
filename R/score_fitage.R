# DNAmFitAge: the Klemera-Doubal composite. The fitness biomarkers are
# sex-resolved clock_ids over one tensor each, so they score on the shared
# linear engine and have no branch here.

# DNAmFitAge_{Sex}: KDM mix of the same-sex member scores plus GrimAgeV1,
# all read from upstream results.
score_fitage_composite <- function(
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
        "score_fitage_composite(): ",
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

  score_mat <- matrix(
    score_vec,
    nrow = n,
    ncol = 1L,
    dimnames = list(sample_id, id)
  )

  # Coverage over the composite's CpG union.
  cached <- if (is.null(partial_cache)) {
    character(0)
  } else {
    intersect(cpgs$score_present, colnames(partial_cache))
  }
  sample_miss <- if (length(cached)) {
    slideimp::mat_miss(DNAm[, cached, drop = FALSE], col = FALSE)
  } else {
    integer(n)
  }
  names(sample_miss) <- sample_id

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
