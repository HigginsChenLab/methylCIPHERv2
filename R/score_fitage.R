# DNAmFitAge family orchestrator (detail-plan §2.5; sex-split + Klemera-Doubal). The group is
# weights_format 'component_matrices' with two scorer shapes:
#
#   * score_fitage_member()    -- the six fitness biomarkers (DNAmGait/Grip/FEV1 _no/wAge, DNAmVO2max).
#     SEX-SPLIT on Female: female / male samples get their OWN coef vector + intercept + covariate
#     coefs (recipe op 'linear_sex'), except DNAmVO2max which shares one model across sexes ('linear').
#     The intercepts and covariate coefs of the sex-split members live in the RECIPE op, NOT in
#     $intercept (which is the sentinel "in_object") -- fitage_score_op() reads them.
#
#   * score_fitage_composite() -- DNAmFitAge itself: a Klemera-Doubal weighted combination of
#     DNAmGait_noAge, DNAmGrip_noAge, DNAmVO2max and GrimAgeV1 (the KDM "DNAmGrimAge" input). Each
#     component is standardized (value - center)/scale then weighted, with sex-specific weight/center/
#     scale from kdm_params. It reads the member + GrimAge SCORES out of `results` (deps precede it in
#     the plan, like GrimAge's surrogates), never CpGs directly.
#
# The load-bearing missingness split (detail-plan §2.3, never crossed) runs per sex here:
#   - present-but-partial-NA scoring CpG -> the shared cohort cache (partial branch, built once in
#     calc_clocks) -- identical fill for every clock sharing the CpG.
#   - completely-ABSENT scoring CpG -> VENDOR fill from that sample's sex-specific training MEDIAN
#     (the group's Female_Medians / Male_Medians). This is the first vendor_mean policy wired up
#     (linear_score() still gates it off). Because the model is linear, a vendor-filled absent CpG
#     contributes a per-sex CONSTANT offset sum(coef_absent * median_absent) -- arithmetically identical
#     to materializing the fill and multiplying, but with no n x p copy (matches legacy's median-fill +
#     colMean fallback exactly: partial columns cohort-mean, absent columns sex-median).
#
# Samples whose Female is neither 1 nor 0 (NA) cannot pick a sex model/median and score NA -- exactly
# the legacy complete.cases behavior. Every scorer returns the usual list(score, coverage, sample_miss).

# One fitness biomarker member. `cpgs` is resolve_cpgs()$per_clock[[id]] (the member's scoring CpG
# skeleton over its female+male coef union); its $score_present is the usable universe, so a per-sex
# coef's present set is intersect(names(coef), cpgs$score_present) and the rest is vendor-filled.
score_fitage_member <- function(id, cpgs, DNAm, partial_cache = NULL, pheno = NULL) {
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

  medians <- fitage_sex_medians(id) # list(female=, male=) named numeric over AllCpGs
  op <- fitage_score_op(id) # the 'linear' / 'linear_sex' scoring step

  # per-sex model. 'linear_sex' carries distinct female/male coef+intercept+covariates; 'linear'
  # (DNAmVO2max) shares one model across sexes -- but imputation still forks by sex below.
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
    list(rows = which(female == 1), model = models$female, med = medians$female),
    list(rows = which(female == 0), model = models$male, med = medians$male)
  )
  for (grp in sexes) {
    rows <- grp$rows
    if (!length(rows)) {
      next
    }
    m <- grp$model
    present <- intersect(names(m$coef), cpgs$score_present) # == names(coef) ∩ usable
    absent <- setdiff(names(m$coef), present) # -> sex-median vendor fill

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
      DNAm = DNAm[rows, , drop = FALSE],
      partial_cache = if (is.null(partial_cache)) {
        NULL
      } else {
        partial_cache[rows, , drop = FALSE]
      },
      pheno = if (is.null(pheno)) NULL else pheno[rows, , drop = FALSE],
      id = id
    )
    # vendor branch: absent CpGs contribute a per-sex constant (coef * sex median).
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
    score_used = length(cpgs$score_needed), # present scored + absent vendor-filled
    score_imputed_partial = sum(sample_miss),
    score_imputed_full = length(cpgs$score_absent), # absent -> sex-median vendor fill
    score_dropped = 0L, # vendor policy fills, never drops
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = cpgs$score_absent
  )

  list(score = score_mat, coverage = coverage, sample_miss = sample_miss)
}

# The DNAmFitAge composite (Klemera-Doubal weighted mix). `cpgs` is the composite's scoring CpG
# skeleton (the group's ~627-CpG panel union); `results` holds the already-scored member + GrimAge
# outputs it stacks.
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

  kdm <- fitage_kdm_params(id) # data.frame: sex, component, weight, center, scale
  grim_dep <- fitage_grim_dep(id) # the GrimAge dep behind the "DNAmGrimAge" input

  # component name -> per-sample score vector; "DNAmGrimAge" resolves to the GrimAge dependency clock.
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

  # coverage over the composite's scoring CpG union. It reads member SCORES not CpGs, so (as in
  # score_grimage) the per-sample partial count is over the cohort-cached present CpGs of that union.
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
