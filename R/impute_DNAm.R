# Missingness front end. Partial NA fills from cohort; fully absent from vendor.

# One NA scan over needed columns; errors on fully-empty samples.
scan_missing_cpgs <- function(DNAm, needed_cpgs) {
  cols <- colnames(DNAm)
  present_needed <- intersect(needed_cpgs, cols)
  out <- list(
    has_na = FALSE,
    usable_cols = present_needed,
    partial_na_cols = character(0),
    all_na_cols = character(0)
  )
  if (!anyNA(DNAm)) {
    return(out)
  }

  nr <- nrow(DNAm)

  row_miss <- slideimp::mat_miss(DNAm, col = FALSE)
  dead <- rownames(DNAm)[row_miss == ncol(DNAm)]
  if (length(dead)) {
    stop(
      "DNAm has ",
      length(dead),
      " sample(s) with no observed CpGs (all NA): ",
      paste(utils::head(dead, 10L), collapse = ", "),
      if (length(dead) > 10L) ", ..." else "",
      ". Remove or fix these samples before scoring.",
      call. = FALSE
    )
  }

  sub <- DNAm[, present_needed, drop = FALSE]
  col_miss <- slideimp::mat_miss(sub, col = TRUE)
  all_na <- present_needed[col_miss == nr]
  partial <- present_needed[col_miss > 0 & col_miss < nr]

  out$has_na <- TRUE
  out$all_na_cols <- all_na
  out$partial_na_cols <- partial
  out$usable_cols <- setdiff(present_needed, all_na)
  out
}

# Shared partial-NA cohort cache (column means over present scoring CpGs).
build_partial_cache <- function(DNAm, cache_cpgs, cores = 1L) {
  if (!length(cache_cpgs)) {
    return(NULL)
  }
  sub <- DNAm[, cache_cpgs, drop = FALSE]
  slideimp::mean_imp_col(sub, cores = cores)
}

# Apply resolved fill values to a scoring subset (caller chooses sources).
impute_DNAm <- function(DNAm, impute_cpgs, impute_values) {}
