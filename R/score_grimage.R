# GrimAge family orchestrator (detail-plan §2.5). GrimAgeV1 and GrimAgeV2 are weights_format
# 'component_matrices' + computation_type 'linear_transformed': a Cox linear predictor over a STACK
# of protein / lifestyle SURROGATE columns plus Age and Female, then rescaled from the Cox scale to
# years. Too special for the generic linear engine -> its own scorer. It reuses linear_predictor()
# as the inner sub-step for the V2 `_internal` surrogates and consumes the already-scored standalone
# surrogate clocks (the V1 surrogates, and V2's DNAmlogA1C / DNAmlogCRP) out of `results`.
#
# The single load-bearing distinction (product policy, DECISIONS / detail-plan §2.5):
#   * GrimAgeV1 stacks the V1 surrogate columns  = the STANDALONE component clocks (DNAmADM, ...),
#     which are exactly what a user gets when asking for that component (weights/GrimAge/v1/...).
#   * GrimAgeV2 stacks the `_internal` surrogate columns = the RETRAINED V2 coefficients
#     (weights/GrimAge/v2/_internal/...), computed inline here and NEVER surfaced as standalone
#     clocks, plus the two new standalone V2 surrogates DNAmlogA1C / DNAmlogCRP.
# So the SAME protein (e.g. ADM) enters V1 via its V1 standalone score and V2 via a distinct
# `_internal` V2 score, and a bare `calc_clocks(DNAm, "DNAmADM")` returns the V1 one.
#
# What drives that split is the Cox coef vector's NAMES (grimage_cox_coef()): iterating them builds
# the stack column by column --
#   name == "Age" / "Female"      -> take the covariate column from pheno.
#   name starts with "_internal_" -> compute the V2 surrogate inline (its own cpg matrix + intercept
#                                    + covariates, via linear_predictor()).
#   any other name                -> a dependency surrogate CLOCK id, already scored upstream in the
#                                    calc_clocks() loop (deps precede the composite in the plan) and
#                                    read from results[[name]]$score.
# No recipe interpreter: the only recipe field consulted is the grimage_rescale params.
#
# Inputs mirror linear_score()'s prepared context, plus two the composite needs:
#   cpgs          resolve_cpgs()$per_clock[[id]] for the COMPOSITE -- its scoring CpG skeleton (the
#                 union over every surrogate, materialized in the catalog) for coverage.
#   results       the per-clock scorer outputs accumulated so far; holds the dependency surrogate
#                 scores this composite stacks.
#   usable        scan_missing_cpgs()$usable_cols -- the present, non-all-NA needed column universe.
#                 The inline `_internal` surrogates intersect their CpGs against this (their columns
#                 are not in resolve_cpgs(), being sub-clock, so they resolve present/absent here).
#   DNAm, partial_cache, pheno  as in linear_score().
#
# Returns the same list(score, coverage, sample_miss) shape every scorer returns.
score_grimage <- function(
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

  group_id <- clock_group_bundle(id)$group_id # validates the shipped bundle exists
  cox <- grimage_cox_coef(id) # named numeric; names ARE the stack column spec
  comps <- clock_components(id)
  stack_names <- names(cox)

  # Build the n x k stack, one column per Cox coef name, in the coef's own order.
  X <- matrix(
    0,
    nrow = n,
    ncol = length(stack_names),
    dimnames = list(sample_id, stack_names)
  )
  for (nm in stack_names) {
    if (nm %in% c("Age", "Female")) {
      if (is.null(pheno) || !nm %in% names(pheno)) {
        stop(
          "score_grimage(): '",
          id,
          "' needs covariate '",
          nm,
          "' but it is absent from `pheno`.",
          call. = FALSE
        )
      }
      X[, nm] <- as.numeric(pheno[[nm]])
    } else if (startsWith(nm, "_internal_")) {
      # V2 retrained surrogate: score inline from its own cpg matrix. Not a catalog clock, so its
      # present CpGs are resolved here against `usable` (absent -> dropped, GrimAge's omit policy).
      comp <- Filter(function(c) identical(c$name, nm), comps)
      if (length(comp) != 1L) {
        stop(
          "score_grimage(): ",
          id,
          " is missing internal surrogate '",
          nm,
          "'.",
          call. = FALSE
        )
      }
      comp <- comp[[1]]
      coef <- bundle_tensor(group_id, comp$file)
      intercept <- if (is.null(comp$intercept)) 0 else comp$intercept
      lp <- linear_predictor(
        coef = coef,
        intercept = intercept,
        cov_coefs = covariate_coefs_from(comp$covariates),
        score_present = intersect(names(coef), usable),
        DNAm = DNAm,
        partial_cache = partial_cache,
        pheno = pheno,
        id = nm
      )
      X[, nm] <- lp$linpred
    } else {
      # Dependency surrogate clock (V1 surrogates, or V2 DNAmlogA1C / DNAmlogCRP): already scored.
      r <- results[[nm]]
      if (is.null(r)) {
        stop(
          "score_grimage(): ",
          id,
          " depends on surrogate '",
          nm,
          "' but it was not computed upstream.",
          call. = FALSE
        )
      }
      X[, nm] <- as.numeric(r$score)
    }
  }

  # Cox linear predictor (no intercept), then rescale to years. Columns align to `cox` by name.
  cox_score <- X[, stack_names, drop = FALSE] %*% cox
  score <- matrix(
    as.numeric(grimage_rescale(cox_score, grimage_rescale_params(id))),
    nrow = n,
    ncol = 1L,
    dimnames = list(sample_id, id)
  )

  # Coverage over the COMPOSITE's scoring CpG union (cpgs skeleton). tier-2 partial-NA counts come
  # from whichever of those present CpGs were cohort-cached (same rule as linear_score).
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
    score_imputed_full = 0L,
    score_dropped = length(cpgs$score_absent),
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = cpgs$score_absent
  )

  list(score = score, coverage = coverage, sample_miss = sample_miss)
}

# GrimAge Cox-scale -> years rescale (detail-plan §2.5). params = grimage_rescale_params(id) =
# c(m_cox, sd_cox, m_age, sd_age): years = (cox - m_cox) / sd_cox * sd_age + m_age. This is the
# transform recipe step, applied to the composite Cox linear predictor (not an output_transform:
# GrimAgeV1/V2 carry output_transform 'identity').
grimage_rescale <- function(cox_score, params) {
  (cox_score - params[["m_cox"]]) / params[["sd_cox"]] *
    params[["sd_age"]] +
    params[["m_age"]]
}
