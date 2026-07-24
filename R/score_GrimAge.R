# GrimAgeV1/V2: Cox stack of surrogates + Age/Female, then rescale to years
score_GrimAge <- function(
  id,
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
      comp <- only_one(
        comps,
        function(c) identical(c[["name"]], nm),
        paste0("internal surrogate '", nm, "'"),
        id
      )
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
      X[, nm] <- as.numeric(r)
    }
  }

  cox_score <- X[, stack_names, drop = FALSE] %*% cox
  score_matrix(
    grimage_rescale(cox_score, grimage_rescale_params(id)),
    sample_id,
    id
  )
}

# Cox scale -> years
grimage_rescale <- function(cox_score, params) {
  (cox_score - params[["m_cox"]]) /
    params[["sd_cox"]] *
    params[["sd_age"]] +
    params[["m_age"]]
}
