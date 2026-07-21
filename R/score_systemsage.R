# SystemsAge (Sehgal 2024): organ sub-clocks are plain linear (scored by linear_score
# via clock_coefs -> pack$organs). The two composites are scored here:
#   Age_prediction: L = age-linear predictor; score = quadratic(L).
#   SystemsAge:     11 raw system predictors + quadratic-scaled age -> systems_PCA -> linear head.
# Absent CpGs are vendor-mean filled from the pack $impute vector (shared across stages).

# Vendor-mean-filled linear predictor (n-vector) for one pack coef column over the
# clock's present/absent CpG split. Reuses the shared linear kernel.
sa_linpred <- function(coef, intercept, cpgs, DNAm, partial_cache, ref) {
  lp <- linear_predictor(
    coef = coef,
    intercept = intercept,
    cov_coefs = numeric(0),
    score_present = cpgs$score_present,
    DNAm = DNAm,
    partial_cache = partial_cache,
    pheno = NULL,
    id = "SystemsAge"
  )
  absent <- cpgs$score_absent
  if (length(absent)) {
    miss <- setdiff(absent, names(ref))
    if (length(miss)) {
      stop(
        "score_systemsage(): absent CpG(s) lack a vendor mean (cannot fill): ",
        paste(utils::head(miss, 5L), collapse = ", "),
        call. = FALSE
      )
    }
    return(list(
      value = as.numeric(lp$linpred) + sum(coef[absent] * ref[absent]),
      cached = lp$cached
    ))
  }
  list(value = as.numeric(lp$linpred), cached = lp$cached)
}

# c0 + c1*L + c2*L^2 (poly coef ascending in L).
sa_poly <- function(L, coef) {
  out <- rep(0, length(L))
  for (k in seq_along(coef)) {
    out <- out + coef[[k]] * L^(k - 1L)
  }
  out
}

score_systemsage <- function(
  id,
  cpgs,
  DNAm,
  partial_cache = NULL,
  pheno = NULL,
  packs = NULL
) {
  pack <- clock_pack(id, packs)
  ref <- stats::setNames(as.numeric(pack$impute), pack$cpgs)
  age_coef <- stats::setNames(as.numeric(pack$age), pack$cpgs)
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  # Both composites share the PC-linear age front L = intercept + sum(age_pc_coef * beta).
  age <- sa_linpred(
    age_coef,
    systemsage_age_intercept(id),
    cpgs,
    DNAm,
    partial_cache,
    ref
  )
  cached <- age$cached

  if (identical(id, "Age_prediction")) {
    score_vec <- sa_poly(age$value, systemsage_poly(id, "score"))
  } else {
    # Composite: 11 raw system predictors + poly-scaled age, stacked in recipe order,
    # centered/scaled and projected through systems_PCA, then a linear head over the PCs.
    raw_int <- systemsage_raw_intercepts(id)
    order <- systemsage_stack_order(id)
    ap_scaled <- sa_poly(age$value, systemsage_poly(id, "ap_scaled"))

    stages <- vector("list", length(order))
    names(stages) <- order
    stages[["Age_prediction"]] <- ap_scaled
    for (org in setdiff(order, "Age_prediction")) {
      coef <- stats::setNames(as.numeric(pack$systems[, org]), pack$cpgs)
      stages[[org]] <- sa_linpred(
        coef,
        raw_int[[org]],
        cpgs,
        DNAm,
        partial_cache,
        ref
      )$value
    }
    sysscores <- do.call(cbind, stages[order]) # n x 12, columns in stack order

    pca <- systemsage_pca(id, packs, order)
    cs <- sweep(sweep(sysscores, 2L, pca$center, "-"), 2L, pca$scale, "/")
    pcs <- cs %*% pca$rotation
    score_vec <- as.numeric(systemsage_final_intercept(id) + pcs %*% pca$model)
  }

  score <- matrix(
    as.numeric(score_vec),
    nrow = n,
    ncol = 1L,
    dimnames = list(sample_id, id)
  )

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

  list(score = score, coverage = coverage, sample_miss = sample_miss)
}
