# small helpers shared by the scoring branches

# present CpGs that the cohort-mean cache covers (empty when there is no cache)
cached_cols <- function(present, partial_cache) {
  if (is.null(partial_cache)) {
    character(0)
  } else {
    intersect(present, colnames(partial_cache))
  }
}

# per-sample count of cohort-mean-filled CpGs, named by sample
count_sample_miss <- function(DNAm, cached) {
  out <- if (length(cached)) {
    slideimp::mat_miss(DNAm[, cached, drop = FALSE], col = FALSE)
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
    stop(
      "vendor_offset(): '",
      id,
      "' absent CpG(s) lack a vendor mean (cannot fill): ",
      paste(utils::head(miss_ref, 5L), collapse = ", "),
      call. = FALSE
    )
  }
  sum(coef[absent] * ref[absent])
}

# one clock's scores as the n x 1 matrix every branch returns
score_matrix <- function(values, sample_id, id) {
  matrix(
    as.numeric(values),
    nrow = length(sample_id),
    ncol = 1L,
    dimnames = list(sample_id, id)
  )
}
