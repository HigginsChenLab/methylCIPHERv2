# shared scoring helpers

# name a character vector as cli "*" bullets
bullets <- function(x) {
  stats::setNames(x, rep("*", length(x)))
}

# present CpGs covered by the cohort-mean cache
cached_cols <- function(present, partial_cache) {
  if (is.null(partial_cache)) {
    character(0)
  } else {
    intersect(present, colnames(partial_cache))
  }
}

# observed betas for `present`: cohort-mean-filled columns first, then raw.
# `values` is n x 0 when nothing is present, which matmuls to a zero column.
observed_panel <- function(present, DNAm, partial_cache = NULL) {
  cached <- cached_cols(present, partial_cache)
  raw <- setdiff(present, cached)
  list(
    cached = cached,
    cols = c(cached, raw),
    values = cbind(
      partial_cache[, cached, drop = FALSE],
      DNAm[, raw, drop = FALSE]
    )
  )
}

# per-sample count of cohort-mean fills (always integer)
count_sample_miss <- function(DNAm, cached) {
  out <- if (length(cached)) {
    as.integer(slideimp::mat_miss(DNAm[, cached, drop = FALSE], col = FALSE))
  } else {
    integer(nrow(DNAm))
  }
  names(out) <- rownames(DNAm)
  out
}

# vendor-mean fill for fully absent CpGs
vendor_offset <- function(coef, absent, ref, id) {
  miss_ref <- setdiff(absent, names(ref))
  if (length(miss_ref)) {
    cli::cli_abort(
      c(
        "{.val {id}}: no vendor mean for {length(miss_ref)} absent CpG{?s}.",
        "x" = "{.val {utils::head(miss_ref, 5L)}}"
      ),
      call = NULL
    )
  }
  sum(coef[absent] * ref[absent])
}

# one clock's coverage record. `used`, `imputed_full` and `dropped` are counts;
# the rest derives from the cpg split. Partial-fill counts are per panel:
# `score_imputed_partial` sums the score-panel miss, `norm_imputed_partial` the
# norm-panel miss (0 when the clock does not normalize). `normalizes` is the one
# declared panel fact -- readers must not re-derive it from `norm_needed`.
coverage_record <- function(
  cpgs,
  score_miss,
  norm_miss = NULL,
  used,
  imputed_full = 0L,
  dropped = 0L,
  policy = clock_impute(cpgs$clock_id)[["policy"]]
) {
  list(
    clock_id = cpgs$clock_id,
    policy = policy,
    normalizes = isTRUE(cpgs$normalizes),
    score_needed = length(cpgs$score_needed),
    score_present = length(cpgs$score_present),
    score_used = used,
    score_imputed_partial = sum(score_miss),
    score_imputed_full = imputed_full,
    score_dropped = dropped,
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    norm_imputed_partial = if (is.null(norm_miss)) 0L else sum(norm_miss),
    missing_cpgs = cpgs$score_absent
  )
}

# n x 1 score matrix every branch returns
score_matrix <- function(values, sample_id, id) {
  matrix(
    as.numeric(values),
    nrow = length(sample_id),
    ncol = 1L,
    dimnames = list(sample_id, id)
  )
}
