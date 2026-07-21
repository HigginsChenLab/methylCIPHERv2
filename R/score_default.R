# Scorers: one work unit -> list(score, coverage, sample_miss).
# linear and linear_transformed share one engine; they differ only by output_transform.

# Horvath age back-transform (adult.age = 20); catalog stores the name only.
anti_trafo <- function(x, adult.age = 20) {
  ifelse(x < 0, (1 + adult.age) * exp(x) - 1, (1 + adult.age) * x + adult.age)
}

resolve_output_transform <- function(name) {
  switch(
    name,
    identity = function(x) x,
    anti.trafo = anti_trafo,
    stop(
      "Unknown output_transform '", name, "' -- add it to the registry in score.R.",
      call. = FALSE
    )
  )
}

# Shared numeric core: linpred = intercept + sum(coef * beta) + covariates.
# Reads cohort-filled columns from partial_cache when present; otherwise raw DNAm.
linear_predictor <- function(
  coef,
  intercept,
  cov_coefs,
  score_present,
  DNAm,
  partial_cache = NULL,
  pheno = NULL,
  id = "<component>"
) {
  n <- nrow(DNAm)

  cached <- if (is.null(partial_cache)) {
    character(0)
  } else {
    intersect(score_present, colnames(partial_cache))
  }
  raw <- setdiff(score_present, cached)
  used_cols <- c(cached, raw)

  if (length(used_cols)) {
    sub <- cbind(
      partial_cache[, cached, drop = FALSE],
      DNAm[, raw, drop = FALSE]
    )
    cpg_contrib <- sub %*% coef[used_cols]
  } else {
    cpg_contrib <- matrix(0, nrow = n, ncol = 1L)
  }

  cov_contrib <- 0
  if (length(cov_coefs)) {
    need <- names(cov_coefs)
    if (is.null(pheno) || !all(need %in% names(pheno))) {
      stop(
        "linear_predictor(): '",
        id,
        "' needs covariate(s) ",
        paste(need, collapse = ", "),
        " but they are absent from `pheno`.",
        call. = FALSE
      )
    }
    cov_mat <- as.matrix(pheno[, need, drop = FALSE])
    cov_contrib <- cov_mat %*% cov_coefs[need]
  }

  linpred <- cpg_contrib + cov_contrib + intercept
  # cpg_contrib / cov_contrib are exposed so callers can reduce by mean (divide the CpG term by
  # its count, then re-add intercept + covariates) or add a vendor offset before combining.
  list(
    linpred = linpred,
    cpg_contrib = cpg_contrib,
    cov_contrib = cov_contrib,
    used_cols = used_cols,
    cached = cached
  )
}

# Shared linear engine for one cpg_coefficient clock (linear or linear_transformed).
# Reduction: "sum" (intercept + X %*% coef) or "mean" (intercept + rowMeans(X*coef)).
# Impute split: present-but-NA -> cohort cache; completely absent -> vendor-mean offset
# (policy vendor_mean) or dropped from the reduction (policy omit/drop).
linear_score <- function(cpgs, DNAm, partial_cache = NULL, pheno = NULL) {
  id <- cpgs$clock_id
  policy <- clock_impute(id)$policy
  reduction <- clock_reduction(id)
  coef <- clock_coefs(id)
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  absent <- cpgs$score_absent
  vendor_mean <- length(absent) && identical(policy, "vendor_mean")
  if (length(absent) && !policy %in% c("omit", "drop", "vendor_mean")) {
    stop(
      "linear_score(): clock '",
      id,
      "' has unsupported imputation policy '",
      policy,
      "' for ",
      length(absent),
      " absent CpG(s).",
      call. = FALSE
    )
  }

  lp <- linear_predictor(
    coef = coef,
    intercept = clock_intercept(id),
    cov_coefs = clock_covariate_coefs(id),
    score_present = cpgs$score_present,
    DNAm = DNAm,
    partial_cache = partial_cache,
    pheno = pheno,
    id = id
  )

  # Absent CpGs: vendor-mean fill contributes a per-clock constant offset (coef * ref mean),
  # exactly like the FitAge sex-median branch; omit/drop contributes nothing.
  if (vendor_mean) {
    ref <- clock_impute_ref(id)
    miss_ref <- setdiff(absent, names(ref))
    if (length(miss_ref)) {
      stop(
        "linear_score(): '",
        id,
        "' absent CpG(s) lack a vendor mean (cannot fill): ",
        paste(utils::head(miss_ref, 5L), collapse = ", "),
        call. = FALSE
      )
    }
    absent_offset <- sum(coef[absent] * ref[absent])
    vendor_filled <- absent
    dropped <- character(0)
  } else {
    absent_offset <- 0
    vendor_filled <- character(0)
    dropped <- absent
  }

  # Combine. Sum: reuse linpred (intercept + covariates folded in) + vendor offset. Mean: reduce
  # only the CpG term over its included-term count (present + vendor-filled), then re-add the
  # intercept and covariates so they are not divided.
  if (identical(reduction, "mean")) {
    n_terms <- length(cpgs$score_present) + length(vendor_filled)
    cpg_num <- lp$cpg_contrib + absent_offset
    linpred <- cpg_num / n_terms + lp$cov_contrib + clock_intercept(id)
  } else {
    linpred <- lp$linpred + absent_offset
  }

  transform <- resolve_output_transform(clock_output_transform(id))
  score <- matrix(
    as.numeric(transform(linpred)),
    nrow = n,
    ncol = 1L,
    dimnames = list(sample_id, id)
  )

  # per-sample partial-NA count on raw (pre-fill) cached columns
  sample_miss <- if (length(lp$cached)) {
    slideimp::mat_miss(DNAm[, lp$cached, drop = FALSE], col = FALSE)
  } else {
    integer(n)
  }
  names(sample_miss) <- sample_id

  coverage <- list(
    clock_id = id,
    policy = policy,
    score_needed = length(cpgs$score_needed),
    score_present = length(cpgs$score_present),
    score_used = length(lp$used_cols) + length(vendor_filled),
    score_imputed_partial = sum(sample_miss),
    score_imputed_full = length(vendor_filled),
    score_dropped = length(dropped),
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = absent
  )

  list(score = score, coverage = coverage, sample_miss = sample_miss)
}
