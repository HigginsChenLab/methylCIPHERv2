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

# warn band just above the coverage threshold (shared by column and row gates).
warn_band <- function(threshold) min(1, threshold * 1.1)

# one gate bullet (labels pre-formatted for cli).
panel_line <- function(id, present, needed, label, routed) {
  cli::format_inline(
    "{gate_label(id, routed)}: {present}/{needed}
     {label} CpGs ({round(100 * present / needed, 1)}%)"
  )
}

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
  routed <- sex_routed_members()
  # only clocks that read CpGs (composites inherit NA through deps).
  per_clock <- cpg_list[["per_clock"]]
  per_clock <- per_clock[vapply(
    names(per_clock),
    clock_reads_cpgs,
    logical(1L)
  )]

  score_lines <- function(ids) {
    vapply(
      ids,
      function(id) {
        x <- per_clock[[id]]
        panel_line(
          id,
          length(x[["score_present"]]),
          length(x[["score_needed"]]),
          "scoring",
          routed
        )
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
    # sex-routed clocks: one model label; only that sex loses the score.
    plain <- setdiff(fail, names(routed[["alias"]]))
    modelled <- setdiff(fail, plain)
    cli::cli_warn(
      c(
        "{length(fail)} clock{?s} {?has/have} too few CpGs in {.arg DNAm} to
         score ({.arg min_clocks_coverage} = {format(threshold)}):",
        capped_bullets(fail, score_lines),
        if (length(plain)) {
          c(
            "i" = "{cli::qty(plain)}{?That clock scores/Those clocks score}
                   {.code NA} for every sample."
          )
        },
        if (length(modelled)) {
          c(
            "i" = "A sex-specific clock scores {.code NA} only for samples of
                   that sex."
          )
        },
        if (any(observed)) {
          c("i" = "Lower {.arg min_clocks_coverage} to score more clocks.")
        },
        if (!all(observed)) {
          c("i" = "A clock with no CpGs in {.arg DNAm} is {.code NA} at every
                   {.arg min_clocks_coverage}.")
        },
        "i" = "{.fn clock_cpgs} gives the CpGs a clock needs."
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
        "i" = "{.fn clocks_coverage} gives the panel counts for each clock."
      ),
      call = NULL
    )
  }

  fail
}

# decline normalize when the background panel is too thin (before resolve).
norm_gate <- function(panels, usable, threshold = 0.75) {
  routed <- sex_routed_members()
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

  lines <- function(these) {
    vapply(
      these,
      function(id) {
        i <- at[[match(id, ids)]]
        panel_line(id, present[[i]], needed[[i]], "normalization", routed)
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
      # no claim about the score here: this gate runs before the column gate.
      "i" = "Supply the background CpGs, or lower {.arg min_clocks_coverage},
             to normalize {cli::qty(length(drop))}{?it/them}.",
      "i" = "{.fn clock_cpgs} with {.code normalize = TRUE} gives the
             background a clock needs."
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

  # one line per clock for ids that pass the cap.
  lines_for <- function(hit, field) {
    function(these) {
      vapply(
        these,
        function(id) {
          s <- hit[[id]]
          low <- s[[field]]
          # dead samples: count only, no 0% figure.
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
        if (any_of(function(s) any(s[["na"]] & !s[["dead"]]))) {
          c("i" = "Lower {.arg min_samples_coverage} to score more samples.")
        },
        if (any_of(function(s) any(s[["dead"]]))) {
          c("i" = "A sample with no scoring CpGs is {.code NA} at every
                   {.arg min_samples_coverage}.")
        },
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
         {format(threshold)} for {length(marginal)} clock{?s}:",
        capped_bullets(names(marginal), lines_for(marginal, "near")),
        "i" = "{.fn samples_coverage} gives the coverage of every sample."
      ),
      call = NULL
    )
  }

  invisible(NULL)
}
