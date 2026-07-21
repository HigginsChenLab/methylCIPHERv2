# Missingness front end + imputation primitives.
# Partial NA (present-but-NA) fills from the cohort; completely-absent fills from vendor -- never cross.

# One numeric pre-pass over DNAm (once per call), gated by anyNA(). Classifies needed present
# columns as clean / partial / all-NA; hard-errors on fully-empty samples.
scan_missing_cpgs <- function(DNAm, needed_cpgs) {
  cols <- colnames(DNAm)
  # only columns whose NA-state can matter: needed by some clock AND on the panel
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

  # empty samples: refuse before imputation can fabricate a score
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

  # three-way column split over needed present columns only
  sub <- DNAm[, present_needed, drop = FALSE]
  col_miss <- slideimp::mat_miss(sub, col = TRUE)
  all_na <- present_needed[col_miss == nr]
  partial <- present_needed[col_miss > 0 & col_miss < nr]

  out$has_na <- TRUE
  out$all_na_cols <- all_na
  out$partial_na_cols <- partial
  out$usable_cols <- setdiff(present_needed, all_na) # all-NA needed -> vendor/drop path
  out
}

# Shared partial-NA cohort cache: one n x k matrix of present scoring CpGs with column-mean fill.
# Subset columns first so mean_imp_col does not allocate a second full panel.
build_partial_cache <- function(DNAm, cache_cpgs, cores = 1L) {
  if (!length(cache_cpgs)) {
    return(NULL)
  }
  sub <- DNAm[, cache_cpgs, drop = FALSE]
  slideimp::mean_imp_col(sub, cores = cores)
}

# Apply resolved fill values to a scoring subset. Does not choose sources -- caller keeps
# partial=cohort / absent=vendor separate. TODO: finalize signature once linear_score settles.
impute_DNAm <- function(DNAm, impute_cpgs, impute_values) {}
