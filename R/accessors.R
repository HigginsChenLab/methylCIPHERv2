# Executable schema: scorers read clocks only through these accessors, never raw mc_catalog lists.
# Coefs resolve via mc_catalog[[id]]$coef_path -> mc_bundles[[group_id]]$tensors.

# One catalog entry, or a clear error.
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

# Map a weights/ path to its named numeric tensor (single lookup site for all scorers).
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

# Scoring CpGs for one clock (terms that enter the weighted sum).
clock_scoring_cpgs <- function(id) {
  probe_sets_cpgs(clock_entry(id), "scoring")
}

# Normalization / background panel; character(0) when none.
clock_norm_cpgs <- function(id) {
  probe_sets_cpgs(clock_entry(id), "quantile_normalization_background")
}

# Array-normalization scheme the paper assumed (none/BMIQ/quantile/noob). Annotation only; never executed.
clock_norm_scheme <- function(id) {
  scheme <- clock_entry(id)$normalization
  if (is.null(scheme)) {
    return(character(0))
  }
  as.character(scheme)
}

# Parity fixture stub: list(expected, oracle, parity_policy, parity_metric), or NULL when the
# clock has no committed golden. `expected` is a path relative to the methylCIPHER-meta clone
# root ("fixtures/expected/{id}.csv.gz"); the cohort-gated parity tests resolve it there. Test
# metadata only -- scorers never read it; kept here so the fixture surface stays part of the
# executable schema (helper-fixtures.R / test-fixtures-parity.R read clocks only through this).
clock_fixture <- function(id) {
  clock_entry(id)$fixture
}

# Imputation policy + ref: list(policy, ref). Sex-keyed refs need Female at score time.
clock_impute <- function(id) {
  clock_entry(id)$imputation
}

# Vendor-mean reference vector (named cpg->mean) for absent-CpG fill under policy vendor_mean.
# Only for a scalar `ref` path (the common case); sex-keyed FitAge refs use fitage_sex_medians().
clock_impute_ref <- function(id) {
  imp <- clock_impute(id)
  ref <- imp$ref
  if (is.null(ref) || !is.character(ref) || length(ref) != 1L || !nzchar(ref)) {
    stop(
      "clock_impute_ref(): '",
      id,
      "' has no scalar vendor-mean ref path (policy '",
      if (is.null(imp$policy)) NA else imp$policy,
      "').",
      call. = FALSE
    )
  }
  bundle_tensor(clock_entry(id)$group_id, ref)
}

# CpG reduction for a linear work unit: "sum" (intercept + X %*% coef) or "mean"
# (intercept + rowMeans of X*coef). Recipe op `linear_mean` -> mean (EpiTOC, HypoClock,
# PhysAge surrogates); everything else reduces by sum. Read via a narrow recipe scan, same
# pattern as the fitage_/grimage_ recipe accessors -- not a general interpreter.
clock_reduction <- function(id) {
  ops <- vapply(clock_entry(id)$recipe, function(s) as.character(s$op), character(1))
  if ("linear_mean" %in% ops) "mean" else "sum"
}

# TRUE for cohort/sample batch-dependent clocks (PhysAge cohort_zscore, Zhang sample_scale):
# scores depend on which samples are scored together, so results carry a frozen batch_set_id.
clock_batch_dependent <- function(id) {
  isTRUE(clock_entry(id)$batch_dependent)
}

# Named cpg->coef vector for clocks that reduce to one linear weight vector.
# Also covers single-cpg-component GrimAge surrogates; composites use their orchestrator.
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

# {name: coef} list -> named numeric; numeric(0) if empty or name-less.
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

# Covariate weights (named numeric); numeric(0) when none.
clock_covariate_coefs <- function(id) {
  covariate_coefs_from(clock_entry(id)$covariates)
}

# Covariate names required for prepare/pheno checks (not the weights).
clock_covariates_required <- function(id) {
  covs <- clock_entry(id)$covariates_required
  if (is.null(covs) || length(covs) == 0) character(0) else as.character(covs)
}

# Clock ids this clock consumes as compute inputs (deps for resolve_clocks_sequence).
clock_depends_on <- function(id) {
  deps <- clock_entry(id)$depends_on_clocks
  if (is.null(deps) || length(deps) == 0) character(0) else as.character(deps)
}

# Model intercept; 0 when unset.
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

# Catalog output_transform name ("identity" or "anti.trafo"); defaults to "identity".
clock_output_transform <- function(id) {
  ot <- clock_entry(id)$output_transform
  if (is.null(ot)) "identity" else as.character(ot)
}

# weights_format: cpg_coefficient | component_matrices | external_package | custom.
clock_weights_format <- function(id) {
  weights_format <- clock_entry(id)$weights_format
  if (is.null(weights_format)) {
    stop("Unexpected Error: all `weights_format` should be not `NULL`")
  } else {
    weights_format
  }
}

# TRUE for external groups (SystemsAge, PCClocks, PCBrainAge) whose weights are not in mc_bundles.
clock_is_external <- function(id) {
  isTRUE(clock_entry(id)$external_group)
}

# Shipped group bundle: $group_id, $clocks, $tensors.
clock_group_bundle <- function(id) {
  group_id <- clock_entry(id)$group_id
  bundle <- mc_bundles[[group_id]]
  if (is.null(bundle)) {
    stop("No shipped bundle for group: ", group_id, call. = FALSE)
  }
  bundle
}

# Family label used for pack dispatch (e.g. "GrimAge" -> score_grimage).
clock_group_id <- function(id) {
  gid <- clock_entry(id)$group_id
  if (is.null(gid)) {
    stop("Unexpected Error: clock '", id, "' has no group_id", call. = FALSE)
  }
  gid
}

# GrimAge pack accessors -- pieces score_grimage() needs from $components / rescale params.

clock_components <- function(id) {
  comps <- clock_entry(id)$components
  if (is.null(comps)) list() else comps
}

# GrimAge Cox coef vector; names drive the surrogate stack (Age/Female/deps/_internal_*).
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

# grimage_rescale params: m_cox, sd_cox, m_age, sd_age.
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

# DNAmFitAge pack accessors -- pieces score_fitage_*() needs (sex-split + KDM params).

# FitAge member scoring op (out == "score"): linear or linear_sex with intercepts/covariates.
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

# Resolve a named FitAge component to its coef tensor.
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

# KDM params table (sex, component, weight, center, scale) for the FitAge composite.
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

# GrimAge dep id for the FitAge composite (exactly one expected).
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

# Sex-specific vendor medians for absent-CpG fill: list(female=, male=).
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

# DNAmPhysAge pack accessors -- pieces score_physage() needs (surrogate coefs + zscore/poly recipe).

# Ordered surrogate list for the PhysAge composite: each is {name (raw_*), coef (named cpg->weight),
# negate (reverse-code before cohort z-score)}. Order follows the recipe's `stack` inputs so the
# raws matrix column order is stable and reproducible.
physage_surrogates <- function(id) {
  entry <- clock_entry(id)
  recipe <- entry$recipe

  stack_step <- Filter(function(s) identical(s$op, "stack"), recipe)
  if (length(stack_step) != 1L) {
    stop(
      "physage_surrogates(): ",
      id,
      " has ",
      length(stack_step),
      " stack op(s) (expected 1).",
      call. = FALSE
    )
  }
  order <- as.character(unlist(stack_step[[1]]$inputs))

  zs <- Filter(
    function(s) identical(s$op, "cohort_zscore") && identical(s$`in`, "raws"),
    recipe
  )
  if (length(zs) != 1L) {
    stop(
      "physage_surrogates(): ",
      id,
      " has ",
      length(zs),
      " cohort_zscore op(s) over 'raws' (expected 1).",
      call. = FALSE
    )
  }
  negate_set <- as.character(unlist(zs[[1]]$negate))

  # Each linear_mean op names its coef component and its `out` (raw_*); map out -> component tensor.
  lm_ops <- Filter(function(s) identical(s$op, "linear_mean"), recipe)
  by_out <- stats::setNames(lm_ops, vapply(lm_ops, function(s) s$out, character(1)))

  lapply(order, function(raw_name) {
    op <- by_out[[raw_name]]
    if (is.null(op)) {
      stop(
        "physage_surrogates(): ",
        id,
        " stack input '",
        raw_name,
        "' has no matching linear_mean op.",
        call. = FALSE
      )
    }
    comp <- Filter(function(c) identical(c$name, op$coef), entry$components)
    if (length(comp) != 1L) {
      stop(
        "physage_surrogates(): ",
        id,
        " component '",
        op$coef,
        "' resolves to ",
        length(comp),
        " tensor(s) (expected 1).",
        call. = FALSE
      )
    }
    list(
      name = raw_name,
      coef = bundle_tensor(entry$group_id, comp[[1]]$file),
      negate = raw_name %in% negate_set
    )
  })
}

# The DNAmPhysAge_years rescale: poly coef [c0, c1, ...] applied to the z-scored composite
# (years = c0 + c1*z for the length-2 author coef). NULL when the clock has no poly step.
physage_poly_coef <- function(id) {
  step <- Filter(function(s) identical(s$op, "poly"), clock_entry(id)$recipe)
  if (!length(step)) {
    return(NULL)
  }
  if (length(step) != 1L) {
    stop(
      "physage_poly_coef(): ",
      id,
      " has ",
      length(step),
      " poly op(s) (expected 0 or 1).",
      call. = FALSE
    )
  }
  as.numeric(unlist(step[[1]]$coef))
}
