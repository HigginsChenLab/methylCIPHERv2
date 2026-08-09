# pre-score coverage gates over the resolved panels

# warn band just above the coverage threshold (shared by column and row gates).
warn_band <- function(threshold) min(1, threshold * 1.1)

# verdicts that blank a column. "dead" is the floor-independent one.
GATE_NA <- c("na", "dead")

# column-gate verdict for one clock (shared with gap_reasons()).
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
  # only clocks that read CpGs (composites inherit NA through deps).
  per_clock <- cpg_list[["per_clock"]]
  per_clock <- per_clock[vapply(
    names(per_clock),
    clock_reads_cpgs,
    logical(1L)
  )]

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
         score ({.arg min_clocks_coverage} = {format(threshold)}).",
        # lowering the floor is worth naming only where a clock would gain by
        # it, so the caveat rides on that bullet instead of taking its own.
        c("i" = if (!any(observed)) {
          "A clock with no CpGs in {.arg DNAm} stays {.code NA} at every
           {.arg min_clocks_coverage}."
        } else if (all(observed)) {
          "Lower {.arg min_clocks_coverage} to score more clocks."
        } else {
          "Lower {.arg min_clocks_coverage} to score more clocks. A clock
           with no CpGs in {.arg DNAm} stays {.code NA} at every value."
        }),
        "i" = "{.fn clocks_coverage} gives the panel counts for each clock."
      ),
      call = NULL
    )
  }

  marginal <- ids_for("warn")
  if (length(marginal)) {
    cli::cli_warn(
      c(
        "{length(marginal)} clock{?s} {?is/are} just above
         {.arg min_clocks_coverage} = {format(threshold)}.",
        "i" = "{.fn clocks_coverage} gives the panel counts for each clock."
      ),
      call = NULL
    )
  }

  fail
}

# decline normalize when the background panel is too thin (before resolve).
norm_gate <- function(panels, usable, threshold = 0.75) {
  ids <- panels[["clock_id"]]
  # grade each distinct background once; empty norm panel grades "".
  uniq <- panels[["norm"]][["uniq"]]
  at <- panels[["norm"]][["idx"]]
  needed <- lengths(uniq)
  present <- vapply(uniq, function(p) sum(p %in% usable), integer(1L))
  verdict <- vapply(
    seq_along(uniq),
    function(i) clock_gate_verdict(present[[i]], needed[[i]], threshold),
    character(1L)
  )

  drop <- ids[verdict[at] %in% GATE_NA]
  if (!length(drop)) {
    return(character(0))
  }

  cli::cli_warn(
    c(
      "{length(drop)} clock{?s} {?has/have} too few normalization CpGs in
       {.arg DNAm} to normalize ({.arg min_clocks_coverage} =
       {format(threshold)}).",
      # no claim about the score here: this gate runs before the column gate.
      "i" = "Supply the background CpGs, or lower {.arg min_clocks_coverage},
             to normalize {cli::qty(length(drop))}{?it/them}.",
      "i" = "{.fn clocks_coverage} gives the panel counts for each clock."
    ),
    call = NULL
  )
  drop
}

# per-sample scoring-panel verdicts, or NULL if nothing is near/below the band.
row_gate_one <- function(cov_rec, score_miss, threshold) {
  rc <- panel_ratio(
    cov_rec[["score_present"]],
    score_miss,
    cov_rec[["score_needed"]]
  )
  cov <- rc[["cov"]]
  # na already: a row this clock's sex did not score
  seen <- !is.na(cov)
  # zero observed CpGs is always unscoreable (even at threshold 0).
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
    # zero-CpG subset of na (count, not percent)
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

  blank <- tier("na")
  if (length(blank)) {
    any_of <- function(f) any(vapply(blank, f, logical(1L)))
    # a sample with no scoring CpGs is NA at every floor, so the advice splits
    thin <- any_of(function(s) any(s[["na"]] & !s[["dead"]]))
    cli::cli_warn(
      c(
        "Some samples have too few CpGs in {.arg DNAm} for
         {length(blank)} clock{?s} ({.arg min_samples_coverage} =
         {format(threshold)}).",
        c("i" = if (!thin) {
          "A sample with no scoring CpGs stays {.code NA} at every
           {.arg min_samples_coverage}."
        } else if (!any_of(function(s) any(s[["dead"]]))) {
          "Lower {.arg min_samples_coverage} to score more samples."
        } else {
          "Lower {.arg min_samples_coverage} to score more samples. A sample
           with no scoring CpGs stays {.code NA} at every value."
        }),
        "i" = "{.fn samples_coverage} gives the coverage of every sample."
      ),
      call = NULL
    )
  }

  marginal <- tier("near")
  if (length(marginal)) {
    cli::cli_warn(
      c(
        "Some samples are just above {.arg min_samples_coverage} =
         {format(threshold)} for {length(marginal)} clock{?s}.",
        "i" = "{.fn samples_coverage} gives the coverage of every sample."
      ),
      call = NULL
    )
  }

  invisible(NULL)
}
