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
    stop(
      "clock_entry() takes a single clock id, got ",
      length(id),
      call. = FALSE
    )
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
    stop(
      "No shipped bundle for group: ",
      group_id,
      " (external/unshipped group?)",
      call. = FALSE
    )
  }
  tensor <- bundle$tensors[[path]]
  if (is.null(tensor)) {
    stop("Tensor not in bundle ", group_id, ": ", path, call. = FALSE)
  }
  tensor
}

probe_sets_cpgs <- function(entry, role) {
  hits <- Filter(function(p) identical(p$role, role), entry$probe_sets)
  if (!length(hits)) {
    return(character(0))
  }
  unique(unlist(lapply(hits, function(p) p$cpgs), use.names = FALSE))
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

# list(policy = <chr>, ref = <NULL | path | list(female=, male=)>). Read once by
# the linear engine to drive the partial(cohort) / absent(vendor) fork. Sex-keyed
# refs (DNAmFitAge family) carry $female / $male weight-paths, resolved via
# bundle_tensor() at score time, requiring Female first.
clock_impute <- function(id) {
  clock_entry(id)$imputation
}

# Named numeric weight vector (names = CpG ids) for a clock that reduces to ONE cpg->coef vector.
# Two shapes qualify, and the linear engine treats them identically:
#   * weights_format 'cpg_coefficient' -- the vector lives at $coef_path.
#   * weights_format 'component_matrices' with EXACTLY ONE cpg-keyed component (row_key "cpg") --
#     the GrimAge protein/lifestyle SURROGATES (DNAmADM, DNAmlogA1C, ...): a single cpg->coef
#     matrix, so they score through linear_score() exactly like a cpg_coefficient clock. The vector
#     lives at that component's $file. The composite GrimAgeV1/V2 do NOT qualify (their components
#     carry a `component`-keyed Cox model and, for V2, eight `_internal` cpg matrices) -> rejected
#     here; they route to score_grimage(). external / custom formats resolve their many tensors via
#     clock_group_bundle() + bundle_tensor() in their own scorers.
# NB: computation_type (reference_code_required, linear_transformed, ...) is the router's concern --
# this only guarantees the weights are one cpg->coef vector, not that plain linear scoring is correct.
clock_coefs <- function(id) {
  entry <- clock_entry(id)
  wf <- entry$weights_format
  if (identical(wf, "cpg_coefficient")) {
    path <- entry$coef_path
    if (length(path) != 1L || !nzchar(path)) {
      stop(
        "clock_coefs(): ",
        id,
        " is cpg_coefficient but has no coef tensor path.",
        call. = FALSE
      )
    }
    return(bundle_tensor(entry$group_id, path))
  }
  if (identical(wf, "component_matrices")) {
    cpg_comps <- Filter(
      function(c) identical(c$row_key, "cpg"),
      entry$components
    )
    if (length(cpg_comps) == 1L) {
      return(bundle_tensor(entry$group_id, cpg_comps[[1]]$file))
    }
  }
  stop(
    "clock_coefs(): ",
    id,
    " is weights_format='",
    wf,
    "' and does not reduce to a single cpg->coef vector; ",
    "use clock_group_bundle() + bundle_tensor() (or its family orchestrator).",
    call. = FALSE
  )
}

# Turn a {name: coef} covariate list -- as carried on a clock entry ($covariates) OR a single
# component entry (a GrimAge surrogate's $covariates) -- into a named numeric vector; numeric(0)
# when empty or name-less. Shared so clock-level and component-level covariate terms resolve
# identically. The object form {name: coef} yields weights; a bare-array requirement form (names
# absent) yields numeric(0).
covariate_coefs_from <- function(cov) {
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

# Covariate coefficients as a named numeric vector, e.g. c(Age = -0.107) -- the covariate*coef
# terms a clock adds on top of the CpG sum (GrimAge surrogates, DNAmFitAge, ...). numeric(0)
# when none. Distinct from mc_index$covariates_required, which lists the covariate NAMES a clock
# needs (for prepare_inputs), not their weights.
clock_covariate_coefs <- function(id) {
  covariate_coefs_from(clock_entry(id)$covariates)
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

# The clock ids this clock consumes as inputs (character vector; character(0) when none). Only
# composites declare any: GrimAgeV1/V2 (their CpG-surrogate components) and DNAmFitAge
# (gait/grip/vo2max + GrimAgeV1, which crosses the GrimAge group). resolve_clocks_sequence() walks
# this to expand a requested set into a dependency-satisfying COMPUTE order -- it is a compute
# input, NOT a scoring coefficient. `depends_on_clocks` is the flattened catalog field (sync).
clock_depends_on <- function(id) {
  deps <- clock_entry(id)$depends_on_clocks
  if (is.null(deps) || length(deps) == 0) character(0) else as.character(deps)
}

# Model intercept; 0 when unset. Separate from clock_coefs() to match the
# linear_score(coefs, intercept) signature (calc_clocks-scaffold.R).
clock_intercept <- function(id) {
  intercept <- clock_entry(id)$intercept
  if (is.null(intercept)) 0 else intercept
}

clock_type <- function(id) {
  computation_type <- clock_entry(id)$computation_type
  if (is.null(computation_type)) {
    stop("Unexpected Error: all `computation_type` should be not `NULL`")
  } else {
    computation_type
  }
}

# The output transform a clock applies to its linear predictor: the catalog `output_transform` NAME
# only ("identity" for the 93 plain-linear clocks, "anti.trafo" for the 8 Horvath-family age
# back-transform clocks). No params live in the catalog -- resolved to a function by the scorer's
# registry (resolve_output_transform() in score.R). `linear` and `linear_transformed` are the SAME
# engine; this string is the only thing that differs. Defaults to "identity" when unset.
clock_output_transform <- function(id) {
  ot <- clock_entry(id)$output_transform
  if (is.null(ot)) "identity" else as.character(ot)
}

# The upstream-canonical weights encoding: one of "cpg_coefficient", "component_matrices",
# "external_package", "custom". calc_clocks() routes the scorer on the PAIR (weights_format,
# computation_type) -- computation_type alone is ambiguous (e.g. GrimAge surrogates are
# computation_type "linear" but weights_format "component_matrices", so they are NOT the plain
# cpg_coefficient linear engine). Never NULL in a well-formed catalog.
clock_weights_format <- function(id) {
  weights_format <- clock_entry(id)$weights_format
  if (is.null(weights_format)) {
    stop("Unexpected Error: all `weights_format` should be not `NULL`")
  } else {
    weights_format
  }
}

# TRUE when the clock belongs to an external group (SystemsAge, PCClocks, PCBrainAge) whose weights
# ship as content-addressed qs2 release assets, NOT in mc_bundles. calc_clocks() routes these to the
# (unwritten) external adapter, never the in-package linear engine -- even PCClocks members carry
# weights_format 'cpg_coefficient', but their coefs are not in a shipped bundle, so linear_score()
# would fail in bundle_tensor(). FALSE for every in-package clock.
clock_is_external <- function(id) {
  isTRUE(clock_entry(id)$external_group)
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

# The group_id a clock belongs to. calc_clocks() routes FAMILY orchestrators on it (group_id
# "GrimAge" -> score_grimage()), so the pack dispatch keys on the catalog's own family label rather
# than a hardcoded id list. Never NULL in a well-formed catalog.
clock_group_id <- function(id) {
  gid <- clock_entry(id)$group_id
  if (is.null(gid)) {
    stop("Unexpected Error: clock '", id, "' has no group_id", call. = FALSE)
  }
  gid
}

# ===========================================================================
# GrimAge pack accessors (detail-plan §2.5)
# ===========================================================================
# The composite GrimAgeV1/V2 are weights_format 'component_matrices' whose $components list mixes
# cpg-keyed surrogate matrices with one `component`-keyed Cox model. These read exactly the pieces
# score_grimage() needs, keeping the raw nested structure behind the schema layer -- there is NO
# generic recipe walker; the ONE recipe field consulted is the grimage_rescale params below.

# The full $components list for a clock (list(); never NULL error). score_grimage() scans it to find
# a V2 `_internal_*` surrogate's coef file + intercept + covariates.
clock_components <- function(id) {
  comps <- clock_entry(id)$components
  if (is.null(comps)) list() else comps
}

# The GrimAge Cox coefficient vector for GrimAgeV1/V2: the single $components entry with row_key
# "component" (the model over the stacked surrogate columns), resolved to its named numeric tensor.
# Its NAMES are the stack column spec score_grimage() builds against -- "_internal_*" (V2 surrogates
# computed inline), "Age"/"Female" (from pheno), or a dependency component clock id (V1 surrogates,
# V2 DNAmlogA1C/DNAmlogCRP). This name-driven dispatch is what keeps V1 on V1 surrogate columns and
# V2 on the retrained `_internal` columns without interpreting the recipe.
grimage_cox_coef <- function(id) {
  entry <- clock_entry(id)
  model <- Filter(function(c) identical(c$row_key, "component"), entry$components)
  if (length(model) != 1L) {
    stop(
      "grimage_cox_coef(): ",
      id,
      " has ",
      length(model),
      " component-keyed model matrices (expected exactly 1).",
      call. = FALSE
    )
  }
  bundle_tensor(entry$group_id, model[[1]]$file)
}

# The grimage_rescale parameters (m_cox, sd_cox, m_age, sd_age) that convert a GrimAge Cox linear
# predictor to years: years = (cox - m_cox)/sd_cox * sd_age + m_age. Stored on the clock's transform
# recipe step -- the ONLY recipe field the GrimAge scorer reads (a targeted lookup, not a recipe
# interpreter). Returned as a named numeric vector in (m_cox, sd_cox, m_age, sd_age) order.
grimage_rescale_params <- function(id) {
  recipe <- clock_entry(id)$recipe
  step <- Filter(
    function(s) identical(s$op, "transform") && identical(s$name, "grimage_rescale"),
    recipe
  )
  if (length(step) != 1L) {
    stop(
      "grimage_rescale_params(): ",
      id,
      " has no unique grimage_rescale transform step.",
      call. = FALSE
    )
  }
  p <- step[[1]]$params
  need <- c("m_cox", "sd_cox", "m_age", "sd_age")
  miss <- setdiff(need, names(p))
  if (length(miss)) {
    stop(
      "grimage_rescale_params(): ",
      id,
      " transform is missing param(s) ",
      paste(miss, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  vapply(p[need], as.numeric, numeric(1))
}

# ===========================================================================
# DNAmFitAge pack accessors (detail-plan §2.5; sex-split + Klemera-Doubal)
# ===========================================================================
# The DNAmFitAge family is weights_format 'component_matrices': six fitness biomarker MEMBERS (five
# sex-split female/male coef matrices + the shared-model DNAmVO2max) and one COMPOSITE (DNAmFitAge, a
# KDM weighted mix of three members + GrimAgeV1). Like the GrimAge accessors these read exactly the
# pieces score_fitage_*() needs, keeping the raw nested structure behind the schema. There is NO
# recipe walker; the only recipe field consulted is the scoring op (which carries the sex-split
# members' intercepts + covariate coefs -- they live NOWHERE else, since $intercept is the sentinel
# "in_object").

# The scoring recipe op for a FitAge MEMBER: the step whose $out == "score" (the leading 'impute'
# step is skipped). Its $op is "linear" (DNAmVO2max, shared model) or "linear_sex" (female/male
# models). For sex-split members it is the sole carrier of female_intercept/male_intercept and
# female_covariates/male_covariates.
fitage_score_op <- function(id) {
  recipe <- clock_entry(id)$recipe
  step <- Filter(function(s) identical(s$out, "score"), recipe)
  if (length(step) != 1L) {
    stop(
      "fitage_score_op(): ",
      id,
      " has ",
      length(step),
      " scoring op(s) with out='score' (expected 1).",
      call. = FALSE
    )
  }
  step[[1]]
}

# Resolve a $components entry by NAME to its coef tensor (named numeric). The scoring op names a coef
# component ("female_model"/"male_model" for linear_sex, "model" for linear); components map that name
# to a weight-path resolved via bundle_tensor().
fitage_component_tensor <- function(id, comp_name) {
  entry <- clock_entry(id)
  comp <- Filter(function(c) identical(c$name, comp_name), entry$components)
  if (length(comp) != 1L) {
    stop(
      "fitage_component_tensor(): ",
      id,
      " has ",
      length(comp),
      " component(s) named '",
      comp_name,
      "' (expected 1).",
      call. = FALSE
    )
  }
  bundle_tensor(entry$group_id, comp[[1]]$file)
}

# The Klemera-Doubal params table for the DNAmFitAge composite: a data.frame with columns
# sex, component, weight, center, scale (one row per component x sex). The single $components entry
# with row_key "sex". Drives the weighted, sex-specific combination in score_fitage_composite().
fitage_kdm_params <- function(id) {
  entry <- clock_entry(id)
  comp <- Filter(function(c) identical(c$row_key, "sex"), entry$components)
  if (length(comp) != 1L) {
    stop(
      "fitage_kdm_params(): ",
      id,
      " has ",
      length(comp),
      " sex-keyed component(s) (expected 1).",
      call. = FALSE
    )
  }
  bundle_tensor(entry$group_id, comp[[1]]$file)
}

# The GrimAge dependency a FitAge composite consumes as its KDM "DNAmGrimAge" input. depends_on_clocks
# carries the concrete id (GrimAgeV1); grep keeps the mapping robust to V1/V2 naming without a
# hardcoded lookup. Exactly one GrimAge dep is expected.
fitage_grim_dep <- function(id) {
  dep <- grep("^GrimAge", clock_depends_on(id), value = TRUE)
  if (length(dep) != 1L) {
    stop(
      "fitage_grim_dep(): ",
      id,
      " has ",
      length(dep),
      " GrimAge dependency (expected 1).",
      call. = FALSE
    )
  }
  dep
}

# Sex-specific vendor medians for absent-CpG imputation: list(female=, male=) named numeric vectors
# over the group's AllCpGs. clock_impute()$ref carries the $female / $male weight-paths (the sex-keyed
# ref shape flagged in clock_impute()'s header); resolved to tensors here. Needs Female at score time
# to pick each sample's median.
fitage_sex_medians <- function(id) {
  entry <- clock_entry(id)
  ref <- entry$imputation$ref
  if (is.null(ref) || is.null(ref$female) || is.null(ref$male)) {
    stop(
      "fitage_sex_medians(): ",
      id,
      " imputation ref lacks female/male median paths.",
      call. = FALSE
    )
  }
  list(
    female = bundle_tensor(entry$group_id, ref$female),
    male = bundle_tensor(entry$group_id, ref$male)
  )
}
