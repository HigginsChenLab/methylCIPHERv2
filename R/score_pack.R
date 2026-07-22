# Batched scorers for external packs (PCClocks, PCBrainAge, SystemsAge). Every member
# of a pack scores on one shared CpG panel, so the expensive DNAm subset is done once
# and reused across a single matmul over all requested columns -- instead of one subset
# + matvec per clock. Results are numerically identical to the per-clock linear engine.

# One shared design over a pack's CpG panel: the partial-cache/DNAm substituted matrix
# (built once), the present/absent split, the vendor ref, and per-sample partial-miss.
# Panel members share this, so every coefficient block reuses it.
pack_design <- function(pack, usable, DNAm, partial_cache) {
  panel <- pack$cpgs
  present <- panel[panel %in% usable]
  absent <- panel[!(panel %in% usable)]
  cached <- if (is.null(partial_cache)) {
    character(0)
  } else {
    present[present %in% colnames(partial_cache)]
  }
  raw <- present[!(present %in% cached)]
  X <- cbind(
    if (length(cached)) partial_cache[, cached, drop = FALSE] else NULL,
    if (length(raw)) DNAm[, raw, drop = FALSE] else NULL
  )
  if (is.null(X)) {
    X <- matrix(0, nrow = nrow(DNAm), ncol = 0L)
  }
  sample_miss <- if (length(cached)) {
    slideimp::mat_miss(DNAm[, cached, drop = FALSE], col = FALSE)
  } else {
    integer(nrow(DNAm))
  }
  names(sample_miss) <- rownames(DNAm)
  list(
    present = present,
    absent = absent,
    cached = cached,
    used = c(cached, raw),
    X = X,
    ref = stats::setNames(as.numeric(pack$impute), pack$cpgs),
    sample_miss = sample_miss
  )
}

# Vendor-mean-filled linear predictors (n x length(cols)) for coef matrix M (rows named
# by pack cpgs) over `cols`, reusing a shared pack_design. No intercept/covariates.
pack_linpred <- function(design, M, cols) {
  contrib <- design$X %*% M[design$used, cols, drop = FALSE]
  if (length(design$absent)) {
    off <- as.numeric(
      design$ref[design$absent] %*% M[design$absent, cols, drop = FALSE]
    )
    contrib <- sweep(contrib, 2L, off, "+")
  }
  colnames(contrib) <- cols
  contrib
}

# Per-clock covariate contributions as one n x k matrix (0 when no clock needs any).
# Mirrors linear_predictor()'s covariate term, batched over the requested columns.
pack_cov_contrib <- function(ids, pheno, n) {
  cc <- lapply(ids, clock_covariate_coefs)
  need <- unique(unlist(lapply(cc, names), use.names = FALSE))
  if (!length(need)) {
    return(matrix(0, nrow = n, ncol = length(ids)))
  }
  if (is.null(pheno) || !all(need %in% names(pheno))) {
    stop(
      "pack scorer: clock(s) need covariate(s) ",
      paste(need, collapse = ", "),
      " but they are absent from `pheno`.",
      call. = FALSE
    )
  }
  Cmat <- matrix(0, length(need), length(ids), dimnames = list(need, ids))
  for (j in seq_along(ids)) {
    v <- cc[[j]]
    if (length(v)) {
      Cmat[names(v), ids[j]] <- v
    }
  }
  as.matrix(pheno[, need, drop = FALSE]) %*% Cmat
}

# Coverage record for a vendor-mean linear pack member (matches linear_score()).
pack_linear_coverage <- function(cpgs, sample_miss) {
  list(
    clock_id = cpgs$clock_id,
    policy = "vendor_mean",
    score_needed = length(cpgs$score_needed),
    score_present = length(cpgs$score_present),
    score_used = length(cpgs$score_present) + length(cpgs$score_absent),
    score_imputed_partial = sum(sample_miss),
    score_imputed_full = length(cpgs$score_absent),
    score_dropped = 0L,
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = cpgs$score_absent
  )
}

# Dispatch a pack group to its batched scorer.
score_pack_group <- function(
  group_id,
  ids,
  cpg_list,
  usable,
  DNAm,
  partial_cache,
  pheno,
  packs
) {
  if (identical(group_id, "SystemsAge")) {
    score_systemsage_group(
      ids, cpg_list, usable, DNAm, partial_cache, pheno, packs
    )
  } else {
    score_linear_pack(
      ids, cpg_list, usable, DNAm, partial_cache, pheno, packs
    )
  }
}

# Batched scorer for coefficient_matrix packs (PCClocks, PCBrainAge): one shared subset,
# one gemm over the requested columns, then per-clock intercept + covariate + output
# transform. Numerically matches per-clock linear_score() (vendor_mean, sum reduction).
score_linear_pack <- function(
  ids,
  cpg_list,
  usable,
  DNAm,
  partial_cache,
  pheno,
  packs
) {
  pack <- clock_pack(ids[[1]], packs)
  for (id in ids) {
    if (!identical(clock_impute(id)$policy, "vendor_mean")) {
      stop("score_linear_pack(): '", id, "' policy != vendor_mean.", call. = FALSE)
    }
    if (!identical(clock_reduction(id), "sum")) {
      stop("score_linear_pack(): '", id, "' reduction != sum.", call. = FALSE)
    }
  }

  M <- pack$coefficient_matrix
  rownames(M) <- pack$cpgs
  design <- pack_design(pack, usable, DNAm, partial_cache)

  linpred <- sweep(
    pack_linpred(design, M, ids),
    2L,
    vapply(ids, clock_intercept, numeric(1)),
    "+"
  ) +
    pack_cov_contrib(ids, pheno, nrow(DNAm))

  sample_id <- rownames(DNAm)
  out <- vector("list", length(ids))
  names(out) <- ids
  for (id in ids) {
    tf <- resolve_output_transform(clock_output_transform(id))
    score <- matrix(
      as.numeric(tf(linpred[, id])),
      ncol = 1L,
      dimnames = list(sample_id, id)
    )
    out[[id]] <- list(
      score = score,
      coverage = pack_linear_coverage(cpg_list$per_clock[[id]], design$sample_miss),
      sample_miss = design$sample_miss
    )
  }
  out
}
