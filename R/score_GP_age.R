# gp_age: gaussian process regression, age = k(x, X) %*% alpha. sync builds
# alpha once per member and ships it in the pack under `derived`.

# one member's model (X, kernel, fill) with its alpha attached
gp_age_model <- function(id, packs) {
  pack <- clock_pack(id, packs)
  model <- pack[["models"]][[id]]
  alpha <- pack[["derived"]][[id]][["alpha"]]
  if (is.null(model) || is.null(alpha)) {
    catalog_bug("Pack %s has no GP model for %s.", clock_group_id(id), id)
  }
  model[["alpha"]] <- alpha
  model
}

score_GP_age <- function(id, cpgs, block, results) {
  model <- gp_age_model(id, block[["packs"]])
  panel <- model[["cpgs"]]
  present <- cpgs[["score_present"]]
  absent <- cpgs[["score_absent"]]
  sample_id <- block[["sample_id"]]
  n <- length(sample_id)

  # n x p in the model's column order: observed (cohort-mean filled) betas,
  # the vendor mean for an absent CpG
  obs <- observed_panel(present, cpgs[["score_present_idx"]], block)
  x <- matrix(NA_real_, n, length(panel), dimnames = list(NULL, panel))
  x[, obs[["cols"]]] <- obs[["values"]]
  if (length(absent)) {
    x[, absent] <- rep(model[["fill"]][absent], each = n)
  }

  # rbf kernel between samples and training rows, squared distance clipped at 0
  X <- model[["X"]]
  d <- outer(rowSums(x^2), rowSums(X^2), "+") - 2 * tcrossprod(x, X)
  d[d < 0] <- 0
  k <- model[["variance"]] * exp(-0.5 * d / model[["lengthscale"]]^2)
  score_matrix(k %*% model[["alpha"]], sample_id, id)
}
