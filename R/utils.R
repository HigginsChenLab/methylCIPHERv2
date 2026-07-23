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

# per-sample count of cohort-mean fills
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

# n x 1 score matrix every branch returns
score_matrix <- function(values, sample_id, id) {
  matrix(
    as.numeric(values),
    nrow = length(sample_id),
    ncol = 1L,
    dimnames = list(sample_id, id)
  )
}
