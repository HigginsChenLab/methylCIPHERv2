# DNAmFitAge: sex-split biomarker members + Klemera-Doubal composite.

# One fitness biomarker (sex-split on Female; DNAmVO2max shares one model).
score_fitage_member <- function(
  id,
  cpgs,
  DNAm,
  partial_cache = NULL,
  pheno = NULL
) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  if (is.null(pheno) || !"Female" %in% names(pheno)) {
    stop(
      "score_fitage_member(): '",
      id,
      "' needs covariate 'Female' but it is absent from `pheno`.",
      call. = FALSE
    )
  }
  female <- as.numeric(pheno[["Female"]])

  medians <- fitage_sex_medians(id)
  op <- fitage_score_op(id)

  models <- if (identical(op$op, "linear_sex")) {
    list(
      female = list(
        coef = fitage_component_tensor(id, op$female_coef),
        intercept = op$female_intercept,
        cov = covariate_coefs_from(op$female_covariates)
      ),
      male = list(
        coef = fitage_component_tensor(id, op$male_coef),
        intercept = op$male_intercept,
        cov = covariate_coefs_from(op$male_covariates)
      )
    )
  } else if (identical(op$op, "linear")) {
    shared <- list(
      coef = fitage_component_tensor(id, op$coef),
      intercept = if (is.null(op$intercept)) 0 else op$intercept,
      cov = covariate_coefs_from(op$covariates)
    )
    list(female = shared, male = shared)
  } else {
    stop(
      "score_fitage_member(): '",
      id,
      "' has unexpected scoring op '",
      op$op,
      "'.",
      call. = FALSE
    )
  }

  score <- rep(NA_real_, n)
  sample_miss <- integer(n)
  names(sample_miss) <- sample_id

  sexes <- list(
    list(
      rows = which(female == 1),
      model = models$female,
      med = medians$female
    ),
    list(rows = which(female == 0), model = models$male, med = medians$male)
  )
  for (grp in sexes) {
    rows <- grp$rows
    if (!length(rows)) {
      next
    }
    m <- grp$model
    present <- intersect(names(m$coef), cpgs$score_present)
    absent <- setdiff(names(m$coef), present)

    miss_ref <- setdiff(absent, names(grp$med))
    if (length(miss_ref)) {
      stop(
        "score_fitage_member(): '",
        id,
        "' absent CpG(s) lack a sex median (cannot vendor-fill): ",
        paste(utils::head(miss_ref, 5L), collapse = ", "),
        call. = FALSE
      )
    }

    lp <- linear_predictor(
      coef = m$coef,
      intercept = m$intercept,
      cov_coefs = m$cov,
      score_present = present,
      DNAm = DNAm[rows, present, drop = FALSE],
      partial_cache = if (is.null(partial_cache)) {
        NULL
      } else {
        partial_cache[rows, , drop = FALSE]
      },
      pheno = if (is.null(pheno)) NULL else pheno[rows, , drop = FALSE],
      id = id
    )
    offset <- if (length(absent)) sum(m$coef[absent] * grp$med[absent]) else 0
    score[rows] <- as.numeric(lp$linpred) + offset

    if (length(lp$cached)) {
      sample_miss[rows] <- slideimp::mat_miss(
        DNAm[rows, lp$cached, drop = FALSE],
        col = FALSE
      )
    }
  }

  score_mat <- matrix(
    score,
    nrow = n,
    ncol = 1L,
    dimnames = list(sample_id, id)
  )

  coverage <- list(
    clock_id = id,
    policy = clock_impute(id)$policy,
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

  list(score = score_mat, coverage = coverage, sample_miss = sample_miss)
}

# DNAmFitAge composite: KDM mix of member + GrimAgeV1 scores from results.
score_fitage_composite <- function(
  id,
  cpgs,
  results,
  DNAm,
  partial_cache = NULL,
  pheno = NULL
) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  if (is.null(pheno) || !"Female" %in% names(pheno)) {
    stop(
      "score_fitage_composite(): '",
      id,
      "' needs covariate 'Female' but it is absent from `pheno`.",
      call. = FALSE
    )
  }
  female <- as.numeric(pheno[["Female"]])

  kdm <- fitage_kdm_params(id)
  grim_dep <- fitage_grim_dep(id)

  # "DNAmGrimAge" resolves to the GrimAge dependency clock.
  comp_vec <- function(component) {
    src <- if (identical(component, "DNAmGrimAge")) grim_dep else component
    r <- results[[src]]
    if (is.null(r)) {
      stop(
        "score_fitage_composite(): ",
        id,
        " needs component '",
        src,
        "' but it was not computed upstream.",
        call. = FALSE
      )
    }
    as.numeric(r$score)
  }

  score <- rep(NA_real_, n)
  for (sx in c("female", "male")) {
    rows <- if (sx == "female") which(female == 1) else which(female == 0)
    if (!length(rows)) {
      next
    }
    krows <- kdm[kdm$sex == sx, , drop = FALSE]
    acc <- numeric(length(rows))
    for (i in seq_len(nrow(krows))) {
      cv <- comp_vec(krows$component[i])[rows]
      acc <- acc + krows$weight[i] * (cv - krows$center[i]) / krows$scale[i]
    }
    score[rows] <- acc
  }
  score_mat <- matrix(
    score,
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
    policy = clock_impute(id)$policy,
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
