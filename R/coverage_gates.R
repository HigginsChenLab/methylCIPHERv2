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

# the band just above a floor, where a clock still scores but only barely.
# both gates read it, so the two tiers cannot drift apart.
warn_band <- function(threshold) min(1, threshold * 1.1)

# verdicts that blank a column. "dead" is the floor-independent one.
GATE_NA <- c("na", "dead")

# the column gate's verdict on one clock's counts. shared with score_gaps(),
# so the gate and the reason a cell is given for it cannot drift.
clock_gate_verdict <- function(present, needed, threshold) {
  if (needed == 0L) {
    return("")
  }
  # no observed CpG is unscoreable at any floor, whatever the fill policy
  if (present == 0L) {
    return("dead")
  }
  ratio <- present / needed
  if (ratio < threshold) {
    "na"
  } else if (ratio < warn_band(threshold)) {
    # within 10% of the floor: warn, before the gate itself trips
    "warn"
  } else {
    ""
  }
}

# column gate: returns the ids that score NA, having warned about them
check_coverage <- function(cpg_list, threshold = 0.75) {
  # threshold is min_clocks_coverage, already validated at the front door
  routed <- sex_routed_members()
  # only the clocks that read CpGs. one assembled from other clocks' scores has
  # no coverage of its own, and inherits NA through them.
  per_clock <- cpg_list[["per_clock"]]
  per_clock <- per_clock[vapply(
    names(per_clock),
    clock_reads_cpgs,
    logical(1L)
  )]

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
  classify <- function(x) {
    clock_gate_verdict(
      length(x[["score_present"]]),
      length(x[["score_needed"]]),
      threshold
    )
  }

  graded <- vapply(per_clock, classify, character(1L))
  ids_for <- function(lvl) names(graded)[graded %in% lvl]

  fail <- ids_for(GATE_NA)
  if (length(fail)) {
    # a clock with no observed CpG is NA at every floor, so the advice splits
    observed <- graded[fail] == "na"
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

  fail
}

# normalization gate: the clocks whose background is too thin to normalize
# against. it declines the scheme, it never blanks a score -- the clock is
# still scored, from its raw betas. run before the panels are resolved.
norm_gate <- function(spec, usable, threshold = 0.75) {
  on <- names(spec[["normalize"]])[spec[["normalize"]]]
  if (!length(on)) {
    return(character(0))
  }
  # one ratio per distinct background, not one per clock
  panel <- lapply(on, function(id) clock_norm_cpgs(id, TRUE))
  present <- vapply(panel, function(p) sum(p %in% usable), integer(1L))
  needed <- lengths(panel)
  ratio <- ifelse(needed > 0L, present / needed, NA_real_)

  low <- !is.na(ratio) & (present == 0L | ratio < threshold)
  if (!any(low)) {
    return(character(0))
  }

  drop <- on[low]
  lines <- function(ids) {
    vapply(
      ids,
      function(id) {
        at <- match(id, on)
        cli::format_inline(
          "{.val {id}}: {present[[at]]}/{needed[[at]]} normalization CpGs
           ({round(100 * ratio[[at]], 1)}%)"
        )
      },
      character(1L)
    )
  }
  cli::cli_warn(
    c(
      "{length(drop)} clock{?s} {?has/have} too few normalization CpGs in
       {.arg DNAm} to normalize ({.arg min_clocks_coverage} =
       {format(threshold)}):",
      capped_bullets(drop, lines),
      "i" = "{cli::qty(length(drop))}{?That clock is/Those clocks are} scored
             without normalization.",
      "i" = "Supply the background CpGs, or lower {.arg min_clocks_coverage},
             to normalize {cli::qty(length(drop))}{?it/them}.",
      "i" = "Call {.fn clock_cpgs} with {.code normalize = TRUE} to list the
             background a clock needs."
    ),
    call = NULL
  )
  drop
}

# per-sample observed fraction of the scoring panel, the one the arithmetic
# reads. a thin normalization background is the norm gate's business, and it
# declines the scheme for the whole cohort rather than blanking a row.
row_coverage <- function(cov, score_miss) {
  if (is.null(cov)) {
    return(NULL)
  }
  # needed is a scalar count, so 0 is the only empty
  needed <- cov[["score_needed"]]
  if (is.null(score_miss) || needed == 0L) {
    return(NULL)
  }
  panel_ratio(cov[["score_present"]], score_miss, needed)
}

# one clock's per-sample verdicts, or NULL when nothing is below the band
row_gate_one <- function(cov_rec, score_miss, threshold) {
  rc <- row_coverage(cov_rec, score_miss)
  if (is.null(rc)) {
    return(NULL)
  }
  cov <- rc[["cov"]]
  # na already: a row this clock's sex did not score
  seen <- !is.na(cov)
  # no observed CpG is unscoreable at any floor, and `cov < threshold` cannot
  # say so at a floor of 0, so the zero rule stays its own clause.
  dead <- seen & cov == 0
  na <- dead | (seen & cov < threshold)
  near <- seen & !na & cov < warn_band(threshold)
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

  # the clocks with at least one sample in a tier, keyed by id
  tier <- function(field) Filter(function(s) any(s[[field]]), gate)

  # one line per clock, strings only for the ids that survive the cap. a near
  # sample is never dead (row_gate_one() takes na out first), so the near tier
  # reaches only the thin half of this.
  lines_for <- function(hit, field) {
    function(these) {
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
  }

  blank <- tier("na")
  if (length(blank)) {
    any_of <- function(f) any(vapply(blank, f, logical(1L)))
    cli::cli_warn(
      c(
        "Some samples have too few CpGs in {.arg DNAm} for
         {length(blank)} clock{?s} ({.arg min_samples_coverage} =
         {format(threshold)}):",
        capped_bullets(names(blank), lines_for(blank, "na")),
        "i" = "Those samples score {.code NA} for
               {cli::qty(length(blank))}{?that clock/those clocks}.",
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
  if (length(marginal)) {
    cli::cli_warn(
      c(
        "Some samples are just above {.arg min_samples_coverage} =
         {format(threshold)} for {length(marginal)} clock{?s}:",
        capped_bullets(names(marginal), lines_for(marginal, "near")),
        "i" = "Call {.fn samples_coverage} to see the coverage of every
               sample."
      ),
      call = NULL
    )
  }

  invisible(NULL)
}
