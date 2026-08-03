# partial NA -> cohort mean, fully absent -> vendor ref

# a max this far past 1 is an order-of-magnitude error, not a rounding one, so
# percent methylation is worth naming outright rather than hedging about scale.
PERCENT_SCALE_AT <- 50

# value gates over one col_stats() sweep: overflow stops, everything else warns
check_col_values <- function(scan, cols) {
  at <- scan[["overflow_col"]]
  if (!is.null(at)) {
    cli::cli_abort(
      c(
        "DNAm column {.val {cols[at[[1L]]]}} does not sum to a finite value.",
        "i" = "Its entries look finite but are extremely large -- far outside
               the usual beta range of {.val {0}} to {.val {1}}. Please check
               that column before scoring.",
        "i" = "The scan stops at the first such column, so there may be others."
      ),
      call = NULL
    )
  }

  # an Inf is missing, not fatal -- but it is a data bug worth naming
  if (isTRUE(scan[["any_inf"]])) {
    cli::cli_warn(
      c(
        "DNAm contains infinite values.",
        "i" = "They are treated as missing: filled from the cohort mean where
               the probe is partly observed, and counted absent where it is
               not.",
        "i" = "An infinite beta is often an upstream divide-by-zero.
               {.fn clocks_coverage} shows what was imputed."
      ),
      call = NULL
    )
  }

  # the range is a running min/max seeded at the beta bounds, so out-of-range
  # is exactly min_val < 0 / max_val > 1. a matrix can carry both sides. only
  # the panel columns are scanned, which is enough: scale is a whole-matrix
  # property, so the panel is a valid sample of it.
  lo <- scan[["min_val"]]
  if (lo < 0) {
    cli::cli_warn(
      c(
        "DNAm contains values below {.val {0}}; the smallest is
         {.val {signif(lo, 4)}}, in column {.val {cols[scan[['min_col']]]}}.",
        "i" = "{.fn calc_clocks} expects beta values in {.val {0}} to
               {.val {1}}. An M-value matrix is a common cause -- it will
               score without error, but the ages won't be meaningful.",
        "i" = "If that sounds right, convert with
               {.code beta <- 2^m / (2^m + 1)}."
      ),
      call = NULL
    )
  }
  hi <- scan[["max_val"]]
  if (hi > 1) {
    cli::cli_warn(
      c(
        "DNAm contains values above {.val {1}}; the largest is
         {.val {signif(hi, 4)}}, in column {.val {cols[scan[['max_col']]]}}.",
        "i" = "{.fn calc_clocks} expects beta values in {.val {0}} to
               {.val {1}}. It will score without error, but the ages won't be
               meaningful.",
        if (hi > PERCENT_SCALE_AT) {
          c(
            "i" = "Percent methylation is the usual cause at this size --
                   convert with {.code DNAm / 100}."
          )
        } else {
          c("i" = "Please double-check the scale of {.arg DNAm}.")
        }
      ),
      call = NULL
    )
  }
  invisible(NULL)
}

# post-score value gate for nan/inf. na is legitimate.
check_score_values <- function(scores) {
  n_bad <- vapply(
    scores,
    function(v) sum(is.nan(v) | is.infinite(v)),
    integer(1L)
  )
  bad <- n_bad[n_bad > 0L]
  if (!length(bad)) {
    return(invisible(NULL))
  }

  lines <- sprintf(
    "%s: %d of %d sample(s)",
    names(bad),
    bad,
    lengths(scores[names(bad)])
  )
  # sample_scale clocks divide by per-sample sd (may be 0 or undefined).
  scaled <- names(bad)[vapply(
    names(bad),
    function(id) !is.null(clock_moment_key(id)),
    logical(1)
  )]
  full <- scaled[vapply(scaled, clock_needs_full_panel, logical(1))]
  ref <- setdiff(scaled, full)
  hint <- c(
    if (length(full)) {
      c(
        "i" = "{.val {full}} divide{cli::qty(full)}{?s/} by a per-sample sd
               taken over every column of {.arg DNAm}, so a sample observing one
               value, or the same value everywhere, has no spread to scale by."
      )
    },
    if (length(ref)) {
      c(
        "i" = "{.val {ref}} divide{cli::qty(ref)}{?s/} by a per-sample sd taken
               over {cli::qty(ref)}{?its/their} declared reference set, so a
               sample observing one value, or the same value everywhere, on that
               set has no spread to scale by."
      )
    }
  )

  cli::cli_warn(
    c(
      "{length(bad)} clock{?s} produced {cli::qty(sum(bad))}non-finite
       score{?s}:",
      capped_bullets(lines),
      hint,
      "i" = "{.code NaN} or {.code Inf} usually means a non-finite value
             reached the arithmetic. Please check {.arg DNAm} rather than
             the score itself."
    ),
    call = NULL
  )
  invisible(NULL)
}

# max moment domains per col_stats() sweep (uint8_t mask width).
MAX_MOMENT_SETS <- 8L

# moment_sets for col_stats(): NULL, or a list of column-index vectors.
# the domains are catalog-derived, so a failure here is a package bug -- but it
# is the guard standing between a bad index and an out-of-bounds kernel read,
# so it stays. bare stop(), not checkmate: nothing a user typed reaches it.
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

# domain cpgs -> column indices. NULL element is the whole matrix.
# declared refs keep only measured cols.
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

# per-output mean/sd. mean needs n >= 1, sd needs n >= 2.
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
    list(mean = mk, sd = sk)
  })
  names(out) <- names(sets)
  out
}

# one col_stats() sweep: columns, means, value gates, row_obs, moment domains.
scan_missing_cpgs <- function(
  DNAm,
  needed_cpgs,
  score_cpgs,
  moment_domains = NULL
) {
  present_needed <- intersect(needed_cpgs, colnames(DNAm))
  # unique by construction, or a repeated index double-counts the column stats
  needed_idx <- match(present_needed, colnames(DNAm))
  nr <- nrow(DNAm)

  # domains index DNAm directly and are validated before the kernel sees them
  sets <- check_moment_sets(
    resolve_moment_sets(moment_domains, colnames(DNAm)),
    ncol(DNAm)
  )

  # index into dnam, not a slice.
  scan <- col_stats(DNAm, needed_idx, sets)
  check_col_values(scan, present_needed)

  # dead samples checked on scoring panels only.
  present_score <- if (identical(score_cpgs, needed_cpgs)) {
    present_needed
  } else {
    intersect(score_cpgs, colnames(DNAm))
  }
  if (length(present_score)) {
    obs <- if (identical(present_score, present_needed)) {
      scan[["row_obs"]]
    } else {
      row_observed(DNAm, match(present_score, colnames(DNAm)))
    }
    dead <- rownames(DNAm)[obs == 0L]
    if (length(dead)) {
      cli::cli_abort(
        c(
          "{length(dead)} sample{?s} {?has/have} no observed CpGs on any
           scoring panel: {.val {utils::head(dead, 10L)}}.",
          "i" = "Please remove or repair {cli::qty(dead)}{?it/them} before
                 scoring."
        ),
        call = NULL
      )
    }
  }

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
    sample_moments = moments
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
