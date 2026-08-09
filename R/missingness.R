# partial NA -> cohort mean, fully absent -> vendor ref

# max this far past 1 is treated as percent methylation.
PERCENT_SCALE_AT <- 50

# the sweep reads the requested panels, so every value verdict is that narrow
SCAN_SCOPE <- "The check covers only the CpGs that the requested clocks use."

# value gates over one col_stats() sweep: overflow stops, everything else warns
check_col_values <- function(scan, cols) {
  at <- scan[["overflow_col"]]
  if (!is.null(at)) {
    cli::cli_abort(
      c(
        "{.arg DNAm} column {.val {cols[at[[1L]]]}} does not sum to a finite
         value.",
        "i" = "The entries are finite but very large. Beta values normally run
               from {.val {0}} to {.val {1}}.",
        "i" = "Use {.fn range} on that column before you score.",
        "i" = "The value check stops at the first such column, so the matrix
               may hold others."
      ),
      call = NULL
    )
  }

  # an Inf is missing, not fatal -- but it is a data bug worth naming
  if (isTRUE(scan[["any_inf"]])) {
    cli::cli_warn(
      c(
        "{.arg DNAm} contains infinite values.",
        "i" = "An infinite value is treated as missing, then filled or dropped
               like any other missing value.",
        "i" = "{.fn clocks_coverage} reports what was filled or dropped. An
               infinite beta is often a divide by zero earlier in the
               pipeline.",
        "i" = SCAN_SCOPE
      ),
      call = NULL
    )
  }

  # range is a running min/max seeded at beta bounds. only panel columns are scanned.
  lo <- scan[["min_val"]]
  if (lo < 0) {
    cli::cli_warn(
      c(
        "{.arg DNAm} contains values below {.val {0}}.",
        "x" = "The smallest is {.val {signif(lo, 4)}}, in column
               {.val {cols[scan[['min_col']]]}}.",
        "i" = "{.fn calc_clocks} expects beta values from {.val {0}} to
               {.val {1}}. An M-value matrix is a common cause.",
        "i" = SCAN_SCOPE
      ),
      call = NULL
    )
  }
  hi <- scan[["max_val"]]
  if (hi > 1) {
    cli::cli_warn(
      c(
        "{.arg DNAm} contains values above {.val {1}}.",
        "x" = "The largest is {.val {signif(hi, 4)}}, in column
               {.val {cols[scan[['max_col']]]}}.",
        "i" = "{.fn calc_clocks} expects beta values from {.val {0}} to
               {.val {1}}.",
        if (hi > PERCENT_SCALE_AT) {
          c("i" = "Percent methylation is a common cause at this size.")
        } else {
          c("i" = "Check the scale of {.arg DNAm}.")
        },
        "i" = SCAN_SCOPE
      ),
      call = NULL
    )
  }
  invisible(NULL)
}

# post-score value gate for nan/inf. na is legitimate.
check_score_values <- function(scores) {
  # one definition of "not finite", shared with the note of the same name
  n_bad <- vapply(scores, function(v) sum(not_finite(v)), integer(1L))
  bad <- n_bad[n_bad > 0L]
  if (!length(bad)) {
    return(invisible(NULL))
  }

  bad_lines <- function(ids) {
    vapply(
      ids,
      function(id) {
        cli::format_inline(
          "{.val {id}}: {bad[[id]]} of {length(scores[[id]])} sample{?s}"
        )
      },
      character(1L)
    )
  }
  cli::cli_warn(
    c(
      "{length(bad)} clock{?s} produced {cli::qty(sum(bad))}non-finite
       score{?s}:",
      capped_bullets(names(bad), bad_lines),
      "i" = "A {.code NaN} or {.code Inf} usually means a non-finite value
             reached the calculation. Check {.arg DNAm}.",
      "i" = "{.fn samples_coverage} gives the sample and the clock of each
             one, under the {.val not_finite} note."
    ),
    call = NULL
  )
  invisible(NULL)
}

# what the sweep found about the matrix, kept rather than only warned about.
# min_col / max_col are NA unless a value left the beta range.
input_scan <- function(scan, cols, n_cpgs, n_all_na) {
  list(
    n_cpgs = n_cpgs,
    n_scanned = length(cols),
    n_all_na = n_all_na,
    min_val = scan[["min_val"]],
    max_val = scan[["max_val"]],
    min_col = cols[scan[["min_col"]]],
    max_col = cols[scan[["max_col"]]],
    any_inf = isTRUE(scan[["any_inf"]])
  )
}

# max moment domains per col_stats() sweep (uint8_t mask width).
MAX_MOMENT_SETS <- 8L

# moment_sets for col_stats(): NULL, or a list of column-index vectors.
check_moment_sets <- function(sets, nc) {
  if (is.null(sets)) {
    return(NULL)
  }
  bug <- function(...) {
    stop(sprintf(...), call. = FALSE)
  }
  if (!is.list(sets) || !length(sets) || length(sets) > MAX_MOMENT_SETS) {
    bug(
      "moment_sets must be a list of 1 to %d index vectors, got %s of length %d.",
      MAX_MOMENT_SETS,
      class(sets)[[1L]],
      length(sets)
    )
  }
  labels <- names(sets) %||% rep("", length(sets))
  out <- lapply(seq_along(sets), function(k) {
    who <- if (nzchar(labels[[k]])) labels[[k]] else as.character(k)
    v <- sets[[k]]
    if (!is.numeric(v)) {
      bug("moment_sets[[%s]] must be numeric, got %s.", who, class(v)[[1L]])
    }
    if (anyNA(v)) {
      bug("moment_sets[[%s]] has missing values.", who)
    }
    if (any(v != trunc(v))) {
      bug("moment_sets[[%s]] has non-integer values.", who)
    }
    # 1-based column indices into DNAm -- the kernel does not range-check them
    if (length(v) && (min(v) < 1 || max(v) > nc)) {
      bug(
        "moment_sets[[%s]] indexes outside 1:%d (range %g to %g).",
        who,
        nc,
        min(v),
        max(v)
      )
    }
    as.integer(v)
  })
  names(out) <- names(sets)
  out
}

# domain CpGs -> column indices; NULL = whole matrix; keep measured only.
resolve_moment_sets <- function(domains, cpgs) {
  if (!length(domains)) {
    return(NULL)
  }
  lapply(domains, function(d) {
    if (is.null(d)) {
      return(seq_along(cpgs))
    }
    # one match() only. kernel ORs repeated indices, so no dedup needed.
    m <- match(d, cpgs)
    m[!is.na(m)]
  })
}

# per-output mean/sd. mean needs n >= 1, sd needs n >= 2 and a spread.
split_moments <- function(scan, sets) {
  if (is.null(sets)) {
    return(NULL)
  }
  n_mom <- scan[["row_moment_obs"]]
  row_mean <- scan[["row_mean"]]
  row_m2 <- scan[["row_m2"]]
  # explicit [, k]: the kernel returns a matrix per output, one column per set
  out <- lapply(seq_along(sets), function(k) {
    nk <- n_mom[, k, drop = TRUE]
    mk <- row_mean[, k, drop = TRUE]
    sk <- sqrt(row_m2[, k, drop = TRUE] / (nk - 1))
    mk[nk < 1L] <- NA_real_
    sk[nk < 2L] <- NA_real_
    # a zero sd is no more usable than a missing one: a z-score has nothing
    # to divide by either way. NA is what the branches already report as a
    # failure, so this routes both through one path. which() drops the NAs.
    sk[which(sk == 0)] <- NA_real_
    list(mean = mk, sd = sk)
  })
  names(out) <- names(sets)
  out
}

# one col_stats() sweep: columns, means, value gates, row_obs, moment domains.
scan_missing_cpgs <- function(DNAm, needed_cpgs, moment_domains = NULL) {
  cn <- colnames(DNAm)
  # one hash of the column names, and the positions it found are kept
  hit <- match(needed_cpgs, cn, 0L)
  ok <- hit > 0L
  present_needed <- needed_cpgs[ok]
  # unique by construction, or a repeated index double-counts the column stats
  needed_idx <- hit[ok]
  nr <- nrow(DNAm)

  # domains index DNAm directly and are validated before the kernel sees them
  sets <- check_moment_sets(resolve_moment_sets(moment_domains, cn), ncol(DNAm))

  # index into dnam, not a slice.
  scan <- col_stats(DNAm, needed_idx, sets)
  check_col_values(scan, present_needed)

  # past the overflow gate, stats is populated -- and it is the panel's alone
  st <- scan[["stats"]]
  n_obs <- st["n_obs", ]
  all_na <- present_needed[n_obs == 0]
  partial <- present_needed[n_obs > 0 & n_obs < nr]
  i <- match(partial, present_needed)

  # the kernel counts each domain itself, so the divisor is that domain's count
  moments <- split_moments(scan, sets)

  # only partial columns get a mean (all-NA columns are classified, not divided)
  list(
    usable_cols = setdiff(present_needed, all_na),
    partial_na_cols = partial,
    all_na_cols = all_na,
    col_mean = stats::setNames(st["sum", i] / st["n_obs", i], partial),
    sample_moments = moments,
    # the gate above reports these once; the record keeps them
    input = input_scan(scan, present_needed, ncol(DNAm), length(all_na))
  )
}

# cohort-mean fill on a fresh slice (fill_imp_col mutates in place)
build_partial_cache <- function(DNAm, cols, partial_fill) {
  if (!length(partial_fill)) {
    return(NULL)
  }
  sub <- DNAm[, cols, drop = FALSE]
  fill_imp_col(sub, partial_fill)
  sub
}
