# dnamPhysAge: physage_raws (per-sample) then finalize_PhysAge (cohort reduce)

# per-sample half: n x n_surrogate reverse-coded raws
physage_raws <- function(id, cpgs, block, results) {
  sample_id <- block[["sample_id"]]
  n <- length(sample_id)
  surrogates <- physage_surrogates(id)

  cols <- lapply(surrogates, function(s) {
    coef <- s[["coef"]]
    label <- paste0(id, " surrogate ", s[["name"]])
    # mean over present CpGs only
    raw <- component_linpred(
      id,
      coef,
      component_present(coef, cpgs, label),
      block,
      label = label,
      reduction = "mean"
    )
    if (s[["negate"]]) -raw else raw
  })

  # hand-built matrix so a 1-row block keeps dim and rownames
  matrix(
    unlist(cols, use.names = FALSE),
    nrow = n,
    dimnames = list(
      sample_id,
      vapply(surrogates, function(s) s[["name"]], character(1))
    )
  )
}

# cohort z-score. scale() ignores NA, so a masked sample leaves the moments
# alone, and a surrogate constant across the cohort scores NA.
zscore_raws <- function(raws) {
  z <- scale(raws)
  # the divisor scale() actually used.
  sds <- attr(z, "scaled:scale")
  flat <- !is.finite(sds) | sds == 0
  if (any(flat)) {
    z[, flat] <- NA_real_
  }
  z
}

# cohort reduction (years branch reduces twice before the poly)
finalize_PhysAge <- function(id, raws) {
  phys <- rowSums(zscore_raws(raws))

  poly <- physage_poly_coef(id)
  score_vec <- if (is.null(poly)) {
    phys
  } else {
    poly_eval(as.numeric(scale(phys)), poly)
  }

  score_matrix(score_vec, rownames(raws), id)
}

# ordered surrogates: each {name, coef, negate}
physage_surrogates <- function(id) {
  recipe <- clock_entry(id)[["recipe"]]

  order <- stack_operands(stack_step(id))

  zs <- pick_one(
    recipe,
    function(s) {
      identical(s[["op"]], "cohort_zscore") && identical(s[["in"]], "raws")
    },
    "cohort_zscore ops over 'raws'",
    id
  )
  negate_set <- as.character(unlist(zs[["negate"]]))

  lm_ops <- Filter(function(s) identical(s[["op"]], "linear_mean"), recipe)
  by_out <- stats::setNames(
    lm_ops,
    vapply(lm_ops, function(s) s[["out"]], character(1))
  )

  lapply(order, function(raw_name) {
    # a stack input with no linear_mean op fails the component lookup
    op <- by_out[[raw_name]]
    list(
      name = raw_name,
      coef = component_tensor_named(id, op[["coef"]]),
      negate = raw_name %in% negate_set
    )
  })
}

# poly coef for DNAmPhysAge_years, or NULL
physage_poly_coef <- function(id) {
  step <- Filter(
    function(s) identical(s[["op"]], "poly"),
    clock_entry(id)[["recipe"]]
  )
  if (!length(step)) {
    return(NULL)
  }
  as.numeric(unlist(step[[1]][["coef"]]))
}
