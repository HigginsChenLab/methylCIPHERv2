# GrimAgeV1/V2: Cox stack of surrogates + Age/Female, then rescale to years
score_GrimAge <- function(
  id,
  cpgs,
  results,
  usable,
  DNAm,
  partial_cache = NULL,
  pheno = NULL
) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  group_id <- clock_group_bundle(id)[["group_id"]]
  cox <- grimage_cox_coef(id)
  comps <- clock_components(id)
  stack_names <- names(cox)

  X <- matrix(
    0,
    nrow = n,
    ncol = length(stack_names),
    dimnames = list(sample_id, stack_names)
  )
  for (nm in stack_names) {
    if (nm %in% c("Age", "Female")) {
      if (is.null(pheno) || !nm %in% names(pheno)) {
        cli::cli_abort(
          c(
            "{.val {id}} needs pheno column {.field {nm}}.",
            "i" = "Add it to {.arg pheno}."
          ),
          call = NULL
        )
      }
      X[, nm] <- as.numeric(pheno[[nm]])
    } else if (startsWith(nm, "_internal_")) {
      comp <- Filter(function(c) identical(c[["name"]], nm), comps)
      if (length(comp) != 1L) {
        cli::cli_abort(
          "{.val {id}} is missing internal surrogate {.val {nm}}.",
          call = NULL
        )
      }
      comp <- comp[[1]]
      coef <- bundle_tensor(group_id, comp[["file"]])
      intercept <- if (is.null(comp[["intercept"]])) 0 else comp[["intercept"]]
      lp <- linear_predictor(
        coef = coef,
        intercept = intercept,
        cov_coefs = covariate_coefs_from(comp[["covariates"]]),
        score_present = intersect(names(coef), usable),
        DNAm = DNAm,
        partial_cache = partial_cache,
        pheno = pheno,
        id = nm
      )
      X[, nm] <- lp$linpred
    } else {
      r <- results[[nm]]
      if (is.null(r)) {
        cli::cli_abort(
          "{.val {id}} depends on {.val {nm}}, which was not scored upstream.",
          call = NULL
        )
      }
      X[, nm] <- as.numeric(r$score)
    }
  }

  cox_score <- X[, stack_names, drop = FALSE] %*% cox
  score <- score_matrix(
    grimage_rescale(cox_score, grimage_rescale_params(id)),
    sample_id,
    id
  )

  cached <- cached_cols(cpgs$score_present, partial_cache)
  sample_miss <- count_sample_miss(DNAm, cached)

  coverage <- list(
    clock_id = id,
    policy = clock_impute(id)[["policy"]],
    score_needed = length(cpgs$score_needed),
    score_present = length(cpgs$score_present),
    score_used = length(cpgs$score_present),
    score_imputed_partial = sum(sample_miss),
    score_imputed_full = 0L,
    score_dropped = length(cpgs$score_absent),
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = cpgs$score_absent
  )

  list(score = score, coverage = coverage, sample_miss = sample_miss)
}

# Cox scale -> years
grimage_rescale <- function(cox_score, params) {
  (cox_score - params[["m_cox"]]) /
    params[["sd_cox"]] *
    params[["sd_age"]] +
    params[["m_age"]]
}
