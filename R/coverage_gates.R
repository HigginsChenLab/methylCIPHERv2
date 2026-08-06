# pre-score coverage gates over the resolved panels

# requestable token for a compute-sequence id (alias, not routed member).
gate_label <- function(id, routed = sex_routed_members()) {
  if (!id %in% names(routed[["alias"]])) {
    return(cli::format_inline("{.val {id}}"))
  }
  cli::format_inline(
    "{.val {routed[['alias']][[id]]}} ({routed[['sex']][[id]]} model)"
  )
}

# column gate: returns the ids that score NA, having warned about them
check_coverage <- function(cpg_list, threshold = 0.75) {
  # threshold is min_clocks_coverage, already validated at the front door
  # warn within 10% of the floor, before the gate itself trips
  warn_below <- min(1, threshold * 1.1)
  routed <- sex_routed_members()
  per_clock <- cpg_list[["per_clock"]]

  # interpolated labels. braces cannot become a cli template.
  panel_line <- function(id, present, needed, label) {
    cli::format_inline(
      "{gate_label(id, routed)}: {length(present)}/{length(needed)}
       {label} CpGs ({round(100 * length(present) / length(needed), 1)}%)"
    )
  }
  score_lines <- function(ids) {
    vapply(
      ids,
      function(id) {
        x <- per_clock[[id]]
        panel_line(id, x[["score_present"]], x[["score_needed"]], "scoring")
      },
      character(1L)
    )
  }
  norm_lines <- function(ids) {
    vapply(
      ids,
      function(id) {
        x <- per_clock[[id]]
        panel_line(id, x[["norm_present"]], x[["norm_needed"]], "normalization")
      },
      character(1L)
    )
  }

  classify <- function(x) {
    if (!length(x[["score_needed"]])) {
      return("")
    }
    present <- length(x[["score_present"]])
    ratio <- present / length(x[["score_needed"]])
    # no observed CpG is unscoreable at any floor, whatever the fill policy
    if (present == 0L || ratio < threshold) {
      "na"
    } else if (ratio < warn_below) {
      "warn"
    } else {
      ""
    }
  }

  graded <- vapply(per_clock, classify, character(1L))
  ids_for <- function(lvl) names(graded)[graded == lvl]

  fail <- ids_for("na")
  if (length(fail)) {
    # a clock with no observed CpG is NA at every floor, so the advice splits
    observed <- vapply(
      fail,
      function(id) length(per_clock[[id]][["score_present"]]) > 0L,
      logical(1L)
    )
    cli::cli_warn(
      c(
        "{length(fail)} clock{?s} {?has/have} too few CpGs in {.arg DNAm} to
         score ({.arg min_clocks_coverage} = {format(threshold)}):",
        capped_bullets(fail, score_lines),
        "i" = "{cli::qty(fail)}{?This clock scores/These clocks score}
               {.code NA} for every sample.",
        if (any(observed)) {
          c("i" = "Lower {.arg min_clocks_coverage} to score more clocks.")
        },
        if (!all(observed)) {
          c("i" = "A clock with no CpGs in {.arg DNAm} scores {.code NA} at
                   every value of {.arg min_clocks_coverage}.")
        },
        "i" = "Call {.fn clock_cpgs} with a clock id to list every CpG that
               clock needs."
      ),
      call = NULL
    )
  }

  marginal <- ids_for("warn")
  if (length(marginal)) {
    cli::cli_warn(
      c(
        "{length(marginal)} clock{?s} {?is/are} just above
         {.arg min_clocks_coverage} = {format(threshold)}:",
        capped_bullets(marginal, score_lines),
        "i" = "Call {.fn clock_cpgs} with a clock id to list every CpG that
               clock needs.",
        "i" = "Call {.fn clocks_coverage} to see the panel counts per clock."
      ),
      call = NULL
    )
  }

  # thin QN backgrounds warn only
  thin <- names(per_clock)[vapply(
    per_clock,
    function(x) {
      length(x[["norm_needed"]]) > 0L &&
        length(x[["norm_present"]]) / length(x[["norm_needed"]]) < threshold
    },
    logical(1L)
  )]
  if (length(thin)) {
    # qn fills absent background CpGs from the target, BMIQ does not
    thin_schemes <- unique(vapply(thin, clock_norm_scheme, character(1)))
    fate <- if (all(thin_schemes == "bmiq")) {
      "The absent CpGs are dropped from the BMIQ fit."
    } else if (any(thin_schemes == "bmiq")) {
      c(
        "The absent CpGs are dropped from the BMIQ fit.",
        "For quantile normalization, the absent CpGs are filled from the
         reference mean."
      )
    } else {
      "The absent CpGs are filled from the reference mean."
    }
    cli::cli_warn(
      c(
        "{length(thin)} clock{?s} {?has/have} too few normalization CpGs
         (below {.arg min_clocks_coverage} = {format(threshold)}):",
        capped_bullets(thin, norm_lines),
        stats::setNames(fate, rep("i", length(fate))),
        "i" = "Call {.fn clocks_coverage} to see the panel counts per clock."
      ),
      call = NULL
    )
  }

  fail
}

# per-sample observed fraction of the row-gate panel (norm if normalizes, else score)
row_coverage <- function(cov, score_miss, norm_miss) {
  if (is.null(cov)) {
    return(NULL)
  }
  qn <- cov[["normalizes"]]
  # needed is a scalar count, so 0 is the only empty
  needed <- if (qn) cov[["norm_needed"]] else cov[["score_needed"]]
  present <- if (qn) cov[["norm_present"]] else cov[["score_present"]]
  miss <- if (qn) norm_miss else score_miss
  if (is.null(miss) || needed == 0L) {
    return(NULL)
  }
  panel_ratio(present, miss, needed)
}

# one clock's per-sample verdicts, or NULL when nothing is below the band
row_gate_one <- function(cov_rec, score_miss, norm_miss, threshold) {
  rc <- row_coverage(cov_rec, score_miss, norm_miss)
  if (is.null(rc)) {
    return(NULL)
  }
  cov <- rc[["cov"]]
  # na already: a row this clock's sex did not score
  seen <- !is.na(cov)
  # the ratio is measured on the gate panel, which is the normalization panel
  # where the clock has one. no observed CpG is unscoreable at any floor, and
  # that is measured on the scoring panel, the one the arithmetic reads.
  dead <- cov_rec[["score_needed"]] > 0L &
    cov_rec[["score_present"]] - score_miss == 0L
  dead <- seen & dead
  na <- dead | (seen & cov < threshold)
  near <- seen & !na & cov < min(1, threshold * 1.1)
  if (!any(na) && !any(near)) {
    return(NULL)
  }
  list(
    cov = cov,
    scored = sum(seen),
    na = na,
    # a subset of na, kept apart because cov does not explain it
    dead = dead,
    near = near,
    needed = rc[["needed"]]
  )
}

# row gate over every clock that counted CpGs, keyed by clock id
row_gate <- function(coverage, threshold = 0.75, skip = character(0)) {
  # threshold is validated at the calc_clocks() front door, before scoring
  ids <- setdiff(covered_ids(coverage[["per_clock"]]), skip)
  out <- stats::setNames(
    lapply(ids, function(id) {
      row_gate_one(
        coverage[["per_clock"]][[id]],
        coverage[["sample_miss"]][["score"]][[id]],
        coverage[["sample_miss"]][["norm"]][[id]],
        threshold
      )
    }),
    ids
  )
  out[!vapply(out, is.null, logical(1L))]
}

# per-sample coverage gate, warning over the verdicts row_gate() already built
check_row_coverage <- function(gate, threshold = 0.75) {
  routed <- sex_routed_members()

  # counts per clock first, strings only for the ids that survive the cap
  tier <- function(field) {
    hit <- Filter(function(s) any(s[[field]]), gate)
    lines <- function(these) {
      vapply(
        these,
        function(id) {
          s <- hit[[id]]
          low <- s[[field]]
          # a dead sample failed on the scoring panel, so its gate-panel
          # figure does not explain the verdict. count it apart.
          gone <- low & s[["dead"]]
          thin <- low & !gone
          paste(
            c(
              cli::format_inline(
                "{gate_label(id, routed)}: {sum(low)} of {s[['scored']]}
                 sample{?s}"
              ),
              if (any(gone)) {
                cli::format_inline("{sum(gone)} with no scoring CpGs")
              },
              if (any(thin)) {
                cli::format_inline(
                  "worst {round(100 * min(s[['cov']][thin]), 1)}% of
                   {s[['needed']]} CpGs"
                )
              }
            ),
            collapse = ", "
          )
        },
        character(1L)
      )
    }
    list(ids = names(hit), lines = lines)
  }

  blank <- tier("na")
  if (length(blank[["ids"]])) {
    hit <- gate[blank[["ids"]]]
    any_of <- function(f) any(vapply(hit, f, logical(1L)))
    cli::cli_warn(
      c(
        "Some samples have too few CpGs in {.arg DNAm} for
         {length(blank$ids)} clock{?s} ({.arg min_samples_coverage} =
         {format(threshold)}):",
        capped_bullets(blank[["ids"]], blank[["lines"]]),
        "i" = "Those samples score {.code NA} for
               {cli::qty(blank$ids)}{?that clock/those clocks}.",
        if (any_of(function(s) any(s[["na"]] & !s[["dead"]]))) {
          c("i" = "Lower {.arg min_samples_coverage} to score more samples.")
        },
        if (any_of(function(s) any(s[["dead"]]))) {
          c("i" = "A sample with no scoring CpGs scores {.code NA} at every
                   value of {.arg min_samples_coverage}.")
        },
        "i" = "Call {.fn samples_coverage} to see the coverage of every
               sample."
      ),
      call = NULL
    )
  }

  marginal <- tier("near")
  if (length(marginal[["ids"]])) {
    cli::cli_warn(
      c(
        "Some samples are just above {.arg min_samples_coverage} =
         {format(threshold)} for {length(marginal$ids)} clock{?s}:",
        capped_bullets(marginal[["ids"]], marginal[["lines"]]),
        "i" = "Call {.fn samples_coverage} to see the coverage of every
               sample."
      ),
      call = NULL
    )
  }

  invisible(NULL)
}
