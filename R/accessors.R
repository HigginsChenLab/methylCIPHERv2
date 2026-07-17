# The executable schema: calc_clocks() code reads clocks ONLY through these, never
# through raw nested mc_catalog / mc_bundles lists. A sysdata shape change breaks
# here (and, later, the structural test) rather than deep in a scorer.
#
# Backing objects (in R/sysdata.rda):
#   mc_index    flat data.frame, 1 row/clock  (discovery/filter columns)
#   mc_catalog  named list by clock_id        (per-clock meta; NO weights)
#   mc_bundles  named list by group_id        ($tensors: weight-path -> named vec)
#   mc_groups   named list by group_id        (members, shared_tensors)
#   mc_provenance                             (sync meta, external_assets)
# Coefficients are NOT in the catalog entry: mc_catalog[[id]]$coef_path is a
# pointer resolved against mc_bundles[[group_id]]$tensors (bundle_tensor()).
# foundation: validated lookups

# One catalog entry, or a clear error. Everything below builds on this.
clock_entry <- function(id) {
  if (length(id) != 1L) {
    stop("clock_entry() takes a single clock id, got ", length(id), call. = FALSE)
  }
  entry <- mc_catalog[[id]]
  if (is.null(entry)) {
    stop("Unknown clock id: ", id, call. = FALSE)
  }
  entry
}

# The single place that maps a `weights/...` path -> named numeric coef vector.
# Every scorer (linear, sex-split, pack) resolves tensors through here, so tensor
# lookup lives in exactly one place.
bundle_tensor <- function(group_id, path) {
  bundle <- mc_bundles[[group_id]]
  if (is.null(bundle)) {
    stop("No shipped bundle for group: ", group_id,
      " (external/unshipped group?)", call. = FALSE)
  }
  tensor <- bundle$tensors[[path]]
  if (is.null(tensor)) {
    stop("Tensor not in bundle ", group_id, ": ", path, call. = FALSE)
  }
  tensor
}

# Scoring CpGs for one clock: the terms that enter the weighted sum. The PRECISE
# per-clock accessor -- distinct from the loose sim-only clock_cpgs() in
# sim_DNAm.R (which unions across many ids for random-matrix generation).
clock_scoring_cpgs <- function(id) {
  probe_sets_cpgs(clock_entry(id), "scoring")
}

# Normalization / background panel (quantile-normalization clocks); character(0)
# when the clock has none. norm_needed in coverage (detail-plan §4).
clock_norm_cpgs <- function(id) {
  probe_sets_cpgs(clock_entry(id), "quantile_normalization_background")
}

# The array-normalization SCHEME a clock's paper assumed: one of "none" / "BMIQ" / "quantile" /
# "noob" (`normalization` catalog field); character(0) when unset. The package NEVER executes any
# of these -- array norm is upstream (sesame/minfi), Horvath BMIQ deliberately skipped (detail-plan
# §2.4a). This is a coverage/provenance ANNOTATION only (feeds norm_needed), not a check and not a
# compute step. NB: distinct from the in-recipe `sample_scale` transform (Zhang, whose scheme is
# "none") -- see clock_needs_full_panel().
clock_norm_scheme <- function(id) {
  scheme <- clock_entry(id)$normalization
  if (is.null(scheme)) {
    return(character(0))
  }
  as.character(scheme)
}

probe_sets_cpgs <- function(entry, role) {
  hits <- Filter(function(p) identical(p$role, role), entry$probe_sets)
  if (!length(hits)) {
    return(character(0))
  }
  unique(unlist(lapply(hits, function(p) p$cpgs), use.names = FALSE))
}

# list(policy = <chr>, ref = <NULL | path | list(female=, male=)>). Read once by
# the linear engine to drive the partial(cohort) / absent(vendor) fork. Sex-keyed
# refs (DNAmFitAge family) carry $female / $male weight-paths, resolved via
# bundle_tensor() at score time, requiring Female first.
clock_impute <- function(id) {
  clock_entry(id)$imputation
}

# Named numeric weight vector (names = CpG ids) for a single-tensor cpg_coefficient clock.
# Routes on the upstream-canonical weights_format, not a coef_path proxy: pack / external /
# custom formats (component_matrices, external_package, custom) resolve multiple tensors through
# clock_group_bundle() + bundle_tensor() in their own scorers, not here. NB: computation_type
# (reference_code_required, linear_transformed, ...) is the router's concern -- this only
# guarantees the weights are one cpg->coef vector, not that plain linear scoring is correct.
clock_coefs <- function(id) {
  entry <- clock_entry(id)
  if (!identical(entry$weights_format, "cpg_coefficient")) {
    stop("clock_coefs(): ", id, " is weights_format='", entry$weights_format,
      "', not cpg_coefficient; use clock_group_bundle() + bundle_tensor().",
      call. = FALSE)
  }
  path <- entry$coef_path
  if (length(path) != 1L || !nzchar(path)) {
    stop("clock_coefs(): ", id, " is cpg_coefficient but has no coef tensor path.",
      call. = FALSE)
  }
  bundle_tensor(entry$group_id, path)
}

# Covariate coefficients as a named numeric vector, e.g. c(Age = -0.107) -- the covariate*coef
# terms a clock adds on top of the CpG sum (GrimAge surrogates, DNAmFitAge, ...). numeric(0)
# when none. Distinct from mc_index$covariates_required, which lists the covariate NAMES a clock
# needs (for prepare_inputs), not their weights. $covariates is the object form {name: coef};
# a bare-array requirement form (names absent) yields numeric(0).
clock_covariate_coefs <- function(id) {
  cov <- clock_entry(id)$covariates
  empty <- stats::setNames(numeric(0), character(0))
  if (is.null(cov) || !length(cov)) {
    return(empty)
  }
  nms <- names(cov)
  if (is.null(nms) || !all(nzchar(nms))) {
    return(empty)
  }
  stats::setNames(vapply(cov, as.numeric, numeric(1)), nms)
}

# The covariate NAMES a clock requires (character vector, e.g. c("Age", "Female"); character(0)
# when none). The prepare path UNIONS this across all resolved clocks to validate `pheno` exactly
# once (feeds check_pheno(extra_columns=)). Distinct from clock_covariate_coefs() above, which
# returns the {name: coef} WEIGHTS applied at score time -- names here, weights there. Sourced
# from the flattened `covariates_required` catalog field (sync's extract_covariates()).
clock_covariates_required <- function(id) {
  covs <- clock_entry(id)$covariates_required
  if (is.null(covs) || length(covs) == 0) character(0) else as.character(covs)
}

# Model intercept; 0 when unset. Separate from clock_coefs() to match the
# linear_score(coefs, intercept) signature (calc_clocks-scaffold.R).
clock_intercept <- function(id) {
  intercept <- clock_entry(id)$intercept
  if (is.null(intercept)) 0 else intercept
}


# The whole shipped bundle for a clock's group: $group_id, $clocks,
# $tensors (weight-path -> named vector). Sex-split and pack orchestrators pull
# arbitrary named tensors (female/male, kdm_params, shared medians) from here.
clock_group_bundle <- function(id) {
  group_id <- clock_entry(id)$group_id
  bundle <- mc_bundles[[group_id]]
  if (is.null(bundle)) {
    stop("No shipped bundle for group: ", group_id, call. = FALSE)
  }
  bundle
}
