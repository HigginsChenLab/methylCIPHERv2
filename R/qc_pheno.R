# phenotype statistics for qc_report()

# a numeric column with at most this many distinct values also gets counts
QC_FEW_VALUES <- 5L

# levels listed for a categorical variable before the rest are summed
QC_MAX_LEVELS <- 10L

# a categorical column splits the age plot only between these level counts
QC_SPLIT_LEVELS <- c(2L, 8L)

# a value this many standard deviations from the mean is counted as an outlier
QC_OUTLIER_Z <- 4

qc_var_type <- function(v) {
  if (is.logical(v) || is.factor(v) || is.character(v)) {
    return("categorical")
  }
  if (is.numeric(v)) {
    return("numeric")
  }
  "other"
}

level_counts <- function(v, max_levels = QC_MAX_LEVELS) {
  tb <- sort(table(as.character(v[!is.na(v)]), useNA = "no"), decreasing = TRUE)
  if (!length(tb)) {
    return("")
  }
  keep <- utils::head(tb, max_levels)
  pct <- as.numeric(keep) / sum(tb)
  out <- paste0(
    html_escape(names(keep)), ": ", fmt_int(as.integer(keep)),
    " (", fmt_pct(pct), ")"
  )
  if (length(tb) > max_levels) {
    rest <- length(tb) - max_levels
    out <- c(out, sprintf(
      "%d more level%s: %s",
      rest, if (rest == 1L) "" else "s", fmt_int(sum(tb[-seq_len(max_levels)]))
    ))
  }
  paste(out, collapse = "<br>")
}

# one row per variable. numeric columns carry the nine summaries, categorical
# columns carry their level counts.
qc_pheno_stats <- function(pheno, pheno_id) {
  vars <- setdiff(names(pheno), pheno_id)
  rows <- lapply(vars, function(nm) {
    v <- pheno[[nm]]
    type <- qc_var_type(v)
    n_miss <- sum(is.na(v))
    q <- rep(NA_real_, 11L)
    counts <- ""
    n_out <- NA_integer_
    n_distinct <- length(unique(v[!is.na(v)]))
    if (type == "numeric") {
      x <- as.numeric(v)
      x <- x[is.finite(x)]
      if (length(x)) {
        q <- c(
          mean(x),
          if (length(x) > 1L) stats::sd(x) else NA_real_,
          min(x),
          stats::quantile(x, c(0.1, 0.25, 0.5, 0.75, 0.9), names = FALSE, type = 7),
          max(x),
          NA_real_,
          NA_real_
        )
        s <- q[[2L]]
        n_out <- if (is.finite(s) && s > 0) sum(abs(x - q[[1L]]) / s > QC_OUTLIER_Z) else 0L
      }
      if (n_distinct <= QC_FEW_VALUES) {
        counts <- level_counts(v)
      }
    } else {
      counts <- level_counts(v)
    }
    data.frame(
      variable = nm,
      type = type,
      n = length(v),
      n_missing = n_miss,
      pct_missing = if (length(v)) n_miss / length(v) else NA_real_,
      n_distinct = n_distinct,
      mean = q[[1L]],
      sd = q[[2L]],
      min = q[[3L]],
      p10 = q[[4L]],
      p25 = q[[5L]],
      median = q[[6L]],
      p75 = q[[7L]],
      p90 = q[[8L]],
      max = q[[9L]],
      n_outliers = n_out,
      counts = counts,
      stringsAsFactors = FALSE
    )
  })
  if (!length(rows)) {
    return(NULL)
  }
  do.call(rbind, rows)
}

# columns that can split the age plot: few levels, not the id, not Age itself
qc_split_vars <- function(pheno, pheno_id) {
  vars <- setdiff(names(pheno), c(pheno_id, "Age", "Female"))
  vars[vapply(
    vars,
    function(nm) {
      v <- pheno[[nm]]
      k <- length(unique(v[!is.na(v)]))
      k >= QC_SPLIT_LEVELS[[1L]] && k <= QC_SPLIT_LEVELS[[2L]] &&
        (qc_var_type(v) == "categorical" || k <= QC_FEW_VALUES)
    },
    logical(1L)
  )]
}

# Female coded 0 / 1, as calc_clocks() reads it, to a labelled factor
female_label <- function(v) {
  v <- suppressWarnings(as.numeric(v))
  factor(
    ifelse(is.na(v), NA_character_, ifelse(v == 1, "Female", ifelse(v == 0, "Male", NA_character_))),
    levels = c("Female", "Male")
  )
}
