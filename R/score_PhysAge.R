# DNAmPhysAge: surrogate means, reverse-code, cohort z-score, row sum
score_PhysAge <- function(id, cpgs, DNAm, partial_cache = NULL) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)
  if (n < 2L) {
    cli::cli_abort(
      c(
        "{.val {id}} needs at least 2 samples (cohort z-score), got {n}.",
        "i" = "Score it with a larger DNAm matrix."
      ),
      call = NULL
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

  score_matrix(score_vec, sample_id, id)
}

# y = sum_k coef[k+1] * x^k (lowest degree first)
poly_eval <- function(x, coef) {
  powers <- vapply(seq_along(coef) - 1L, function(k) x^k, numeric(length(x)))
  as.numeric(powers %*% coef)
}
