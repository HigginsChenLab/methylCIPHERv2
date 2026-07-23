# DNAmPhysAge: surrogate means, reverse-code, cohort z-score, row sum
score_PhysAge <- function(id, cpgs, DNAm, partial_cache = NULL) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)
  if (n < 2L) {
    stop(
      "score_PhysAge(): '",
      id,
      "' is batch-dependent (cohort z-score) and needs >= 2 samples; got ",
      n,
      ".",
      call. = FALSE
    )
  }

  surrogates <- physage_surrogates(id)
  ref <- clock_impute_ref(id)

  raws <- vapply(
    surrogates,
    function(s) {
      coef <- s$coef
      present <- intersect(names(coef), cpgs$score_present)
      absent <- setdiff(names(coef), present)
      absent_offset <- vendor_offset(
        coef,
        absent,
        ref,
        paste0(id, " surrogate ", s$name)
      )
      lp <- linear_predictor(
        coef = coef,
        intercept = 0,
        cov_coefs = numeric(0),
        score_present = present,
        DNAm = DNAm,
        partial_cache = partial_cache,
        id = s$name
      )
      raw <- (as.numeric(lp$cpg_contrib) + absent_offset) / length(coef)
      if (s$negate) -raw else raw
    },
    numeric(n)
  )

  z <- scale(raws)
  phys <- rowSums(z)

  poly <- physage_poly_coef(id)
  score_vec <- if (is.null(poly)) {
    phys
  } else {
    poly_eval(as.numeric(scale(phys)), poly)
  }

  score <- score_matrix(score_vec, sample_id, id)

  cached <- cached_cols(cpgs$score_present, partial_cache)
  sample_miss <- count_sample_miss(DNAm, cached)

  coverage <- list(
    clock_id = id,
    policy = clock_impute(id)[["policy"]],
    score_needed = length(cpgs$score_needed),
    score_present = length(cpgs$score_present),
    score_used = length(cpgs$score_needed),
    score_imputed_partial = sum(sample_miss),
    score_imputed_full = length(cpgs$score_absent),
    score_dropped = 0L,
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = cpgs$score_absent
  )

  list(score = score, coverage = coverage, sample_miss = sample_miss)
}

# y = sum_k coef[k+1] * x^k (lowest degree first)
poly_eval <- function(x, coef) {
  powers <- vapply(seq_along(coef) - 1L, function(k) x^k, numeric(length(x)))
  as.numeric(powers %*% coef)
}
