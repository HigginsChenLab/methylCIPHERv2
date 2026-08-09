# formatters over a finished record's $coverage (no re-touch of beta)

# norm-count columns, listed by name (not matched on a "^norm_" prefix).
CC_NORM_COLS <- c(
  "normalizes",
  "norm_needed",
  "norm_present",
  "norm_imputed_partial",
  "norm_imputed_full",
  "norm_dropped"
)

# columns keyed on a record fact. dropped at exit when the record lacks them.
trim_clock_cols <- function(out, all_columns) {
  if (all_columns) {
    return(out)
  }
  drop <- character(0)
  # every row returned means the reader has no routing target to tell apart
  if (!any(out[["role"]] == "routing_target")) {
    drop <- c(drop, "role")
  }
  # aliases carry NA here, so na.rm: a real TRUE is what keeps the block
  if (!any(out[["normalizes"]], na.rm = TRUE)) {
    drop <- c(drop, CC_NORM_COLS)
  }
  # a list column costs more than its width, and an empty one says nothing
  if (!any(lengths(out[["missing_cpgs"]]) > 0L)) {
    drop <- c(drop, "missing_cpgs")
  }
  out[, setdiff(names(out), drop), drop = FALSE]
}

# front-door refusal for a user-supplied record (cli, not stop()).
check_mc_result <- function(x, arg = "x") {
  if (!inherits(x, "mc_result")) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be an {.cls mc_result}, not {.cls {class(x)[[1L]]}}.",
        "i" = "{.cls mc_result} is what {.fn calc_clocks} returns."
      ),
      call = NULL
    )
  }
  invisible(x)
}

# per-sample miss from the finished panel matrix.
miss_vec <- function(x, id, panel = c("score", "norm")) {
  panel <- match.arg(panel)
  m <- x[["coverage"]][["sample_miss"]][[panel]]
  if (is.null(m) || !(id %in% colnames(m))) {
    stop(
      sprintf(
        paste0(
          "No %s-panel miss column for %s. ",
          "This is a package bug -- please report it."
        ),
        panel,
        id
      ),
      call. = FALSE
    )
  }
  m[, id]
}

# one field of a named list of records down a column, typed by `empty`. a NULL
# record read no CpGs, so it has nothing to report on any field.
rec_field <- function(per_clock, nm, empty) {
  mode <- typeof(empty)
  unname(vapply(
    per_clock,
    function(r) if (is.null(r)) empty else as.vector(r[[nm]], mode),
    empty
  ))
}

# one batch's rows (aliases have NA panels). batch is NULL when the exit drops the label.
batch_coverage <- function(per_clock, batch, returned) {
  ids <- names(per_clock)
  count <- function(nm) rec_field(per_clock, nm, NA_integer_)

  out <- data.frame(
    clock_id = ids,
    # from the catalog, not the record -- a NULL record still has a group
    group_id = unname(vapply(ids, clock_group_id, character(1L))),
    role = ifelse(ids %in% returned, "returned", "routing_target"),
    policy = rec_field(per_clock, "policy", NA_character_),
    normalizes = rec_field(per_clock, "normalizes", NA),
    score_needed = count("score_needed"),
    score_present = count("score_present"),
    score_used = count("score_used"),
    score_imputed_partial = count("score_imputed_partial"),
    score_imputed_full = count("score_imputed_full"),
    score_dropped = count("score_dropped"),
    norm_needed = count("norm_needed"),
    norm_present = count("norm_present"),
    norm_imputed_partial = count("norm_imputed_partial"),
    norm_imputed_full = count("norm_imputed_full"),
    norm_dropped = count("norm_dropped"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  # absent-probe list stays a list-column
  out[["missing_cpgs"]] <- unname(lapply(
    per_clock,
    function(r) if (is.null(r)) character(0) else r[["missing_cpgs"]]
  ))
  add_batch(out, batch)
}

# one row per (clock, batch).
#' Clock Coverage Counts
#'
#' Reports the CpG counts behind each clock's score in `x`, one row for
#' each clock and batch.
#'
#' @inheritParams mc-params
#'
#' @details
#' Every row gives the clock's `group_id`, its `policy`, and the six
#' `score_*` counts for the CpGs in its own scoring panel.
#'
#' A clock assembled only from other clocks' scores reads no CpGs of its
#' own, and gets a row of `NA` counts. Read the coverage of the clocks it
#' depends on instead.
#'
#' Four more kinds of column appear only where they say something about `x`.
#'
#' - `role` appears when `x` holds a clock that scores as part of another
#'   clock.
#' - `normalizes`, and the five `norm_*` counts for the normalizing panel,
#'   appear when a clock in `x` normalizes. There is no `norm_used`.
#' - `missing_cpgs` lists the CpGs absent from a clock's panel, and appears
#'   when a CpG is absent.
#' - `mc_batch_id` appears when `x` holds more than one batch. A batch is
#'   the set of samples from one [calc_clocks()] call, and [rbind()]
#'   combines batches.
#'
#' Pass `all_columns = TRUE` to keep `role`, `normalizes`, the `norm_*`
#' counts, and `missing_cpgs` in every frame. Use it when your own code reads
#' one of those columns by name. `mc_batch_id` is the one exception, and
#' still appears only when `x` holds more than one batch.
#'
#' @returns A data.frame. One row for each clock and batch, with the CpG
#'   counts of its scoring panel, and the columns above that apply to `x`.
#'
#' @seealso
#' - [samples_coverage()] for the same panels counted for each sample.
#' - [summary.mc_result()] for a digest of the run and of what it could not
#'   score.
#'
#' @examples
#' clocks <- c("Horvath1", "Hannum")
#' sim <- sim_DNAm(clocks, n = 20)
#' res <- calc_clocks(sim[["DNAm"]], clocks)
#'
#' clocks_coverage(res)
#' clocks_coverage(res, all_columns = TRUE)
#'
#' @export
clocks_coverage <- function(x, all_columns = FALSE) {
  check_mc_result(x)
  checkmate::assert_flag(all_columns)
  batches <- x[["coverage"]][["per_clock"]]
  returned <- x[["provenance"]][["clocks"]]
  batch <- x[["provenance"]][[MC_BATCH]]
  # keyed on provenance's per-sample vector. n_batches() stops if the two disagree.
  keep <- n_batches(x) > 1L
  out <- do.call(
    rbind,
    lapply(names(batches), function(b) {
      batch_coverage(batches[[b]], if (keep) b else NULL, returned)
    })
  )
  rownames(out) <- NULL
  trim_clock_cols(drop_single_batch(out, batch), all_columns)
}

# one panel's per-sample rows for a non-alias returned clock
panel_rows <- function(id, panel, batch, ratio, sample_id) {
  out <- data.frame(
    id = sample_id,
    clock_id = id,
    panel = panel,
    n_observed = as.integer(ratio[["n_observed"]]),
    n_needed = as.integer(ratio[["needed"]]),
    coverage = ratio[["cov"]],
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  # omitted at single batch, like clocks_coverage().
  add_batch(out, batch)
}

# score-panel rows, plus a norm row when the clock normalizes
clock_sample_rows <- function(x, id, rec, batch, rows) {
  sample_id <- x[["provenance"]][["sample_id"]][rows]

  out <- list()
  out[["score"]] <- panel_rows(
    id,
    "score",
    batch,
    panel_ratio(
      rec[["score_present"]],
      miss_vec(x, id, "score")[rows],
      rec[["score_needed"]]
    ),
    sample_id
  )
  # norm panel only when the clock normalizes
  if (rec[["normalizes"]]) {
    out[["norm"]] <- panel_rows(
      id,
      "norm",
      batch,
      panel_ratio(
        rec[["norm_present"]],
        miss_vec(x, id, "norm")[rows],
        rec[["norm_needed"]]
      ),
      sample_id
    )
  }
  do.call(rbind, out)
}

# composite clocks: one score row per sample, all counts NA.
composite_sample_rows <- function(id, batch, sample_id) {
  panel_rows(
    id,
    "score",
    batch,
    list(n_observed = NA_integer_, needed = NA_integer_, cov = NA_real_),
    sample_id
  )
}

# empty samples_coverage() frame. seeds rbind and matches the batch-column test.
empty_sample_rows <- function(keep_batch) {
  out <- data.frame(
    id = character(0),
    clock_id = character(0),
    panel = character(0),
    n_observed = integer(0),
    n_needed = integer(0),
    coverage = numeric(0),
    stringsAsFactors = FALSE
  )
  if (keep_batch) {
    out[[MC_BATCH]] <- character(0)
  }
  out
}

# most restrictive floor across bound batches.
finalize_samples_gate <- function(x) {
  max(x[["provenance"]][["min_samples_coverage"]])
}

# re-warn on the assembled frame, so a bound record says it once under one floor
say_low_samples <- function(out, threshold) {
  # grade score rows only (not norm or composite).
  out <- out[
    out[["panel"]] == "score" & !is.na(out[["coverage"]]),
    ,
    drop = FALSE
  ]
  low <- out[["coverage"]] < threshold
  if (!any(low)) {
    return(invisible(NULL))
  }
  n_samp <- length(unique(out[["id"]][low]))
  cli::cli_warn(
    c(
      "{n_samp} sample{?s} {cli::qty(n_samp)}{?is/are} under
       {.arg min_samples_coverage} = {format(threshold)} on the {.val score}
       panel ({sum(low)} of {nrow(out)} row{?s}).",
      "i" = "Filter the returned frame to see {cli::qty(sum(low))}{?the
             row/the rows}. For example, {.code cov[cov$panel == \"score\" &
             cov$coverage < {format(threshold)}, ]}.",
      "i" = "{.fn clocks_coverage} gives the panel counts for each clock."
    ),
    call = NULL
  )
  invisible(NULL)
}

# one row per (sample, clock with a coverage record, panel)
#' Sample Coverage Counts
#'
#' Reports each sample's CpG coverage for every clock in `x`, and a note on
#' what happened at each step that was run for it.
#'
#' @inheritParams mc-params
#'
#' @details
#' Every clock in the scores of `x` gets a row for each sample, and so does
#' every clock that scores as part of another clock. A clock assembled only
#' from other clocks' scores counts no CpGs of its own, so its counts are
#' `NA`. A clock scored separately for each sex has no row for a sample
#' outside the sex it scored.
#'
#' A clock that normalizes has a second row for each sample, under
#' `panel = "norm"`, for the panel used to normalize it.
#'
#' `note` says what happened to the panel in that row, and is `NA` when
#' nothing did. `panel` says which step the note is about, so a sample that
#' normalized and then scored can carry a note for each. Where more than one
#' note applies to a row, the first of these is given.
#'
#' On a `score` row, a note means the score is missing:
#'
#' - `covariate`, when a covariate the clock needs is missing from `pheno`.
#'   An unknown `Female` value is the usual cause.
#' - `clock_coverage`, when the clock is under `min_clocks_coverage`. Every
#'   sample is missing this score.
#' - `sample_coverage`, when the sample is under `min_samples_coverage`.
#' - `fit`, when the clock reached the sample but could not be calculated
#'   for it.
#' - `dependency`, when a clock that this clock is calculated from is
#'   missing for that sample.
#' - `not_finite`, when the score was calculated but is not a finite
#'   number, such as `NaN` or `Inf`.
#'
#' On a `norm` row, a note is about the background panel, and the score may
#' still be present:
#'
#' - `partial`, when the sample was normalized but one step of the scheme
#'   could not be applied to it. The score is real, and is calculated from a
#'   background that was only partly calibrated.
#'
#' A score that is not a finite number is present, and is still a `score`
#' row with a note. [calc_clocks()] warns about it as well, and that warning
#' names the likely cause.
#' `min_clocks_coverage` and `min_samples_coverage` are read for the batch
#' that scored the sample, because those are the values that decided the
#' score.
#'
#' `samples_coverage()` warns when a `score` row's `coverage` is under the
#' strictest `min_samples_coverage` value used to score `x`. A `norm` row is
#' never read against that value, because the background panel is counted for
#' the whole run and not for one sample. The `mc_batch_id` column appears
#' only when `x` holds more than one batch.
#'
#' @returns A data.frame. One row for each sample, clock, and panel, with
#'   `n_observed`, `n_needed`, `coverage`, `note`, and, when `x` holds more
#'   than one batch, `mc_batch_id`.
#'
#' @seealso
#' - [clocks_coverage()] for the same panels counted for each clock.
#' - [summary.mc_result()] for the `note` column counted by clock and by
#'   sample.
#'
#' @examples
#' clocks <- c("Horvath1", "Hannum")
#' sim <- sim_DNAm(clocks, n = 20)
#' res <- calc_clocks(sim[["DNAm"]], clocks)
#'
#' head(samples_coverage(res))
#'
#' @export
samples_coverage <- function(x) {
  check_mc_result(x)
  # finalizer: note reads NA scores (cross-sample cols need reduction first).
  x <- finalized(x)
  batch <- x[["provenance"]][[MC_BATCH]]
  # one row per (sample, clock, panel). batch masks rows. label withheld when single-batch.
  keep <- n_batches(x) > 1L
  returned <- colnames(x[["scores"]])

  counted <- list()
  composite <- list()
  for (b in names(x[["coverage"]][["per_clock"]])) {
    per_clock <- x[["coverage"]][["per_clock"]][[b]]
    rows <- batch == b
    label <- if (keep) b else NULL
    # no record means no cpgs of its own.
    ids <- covered_ids(per_clock)
    counted <- c(
      counted,
      lapply(ids, function(id) {
        clock_sample_rows(x, id, per_clock[[id]], label, rows)
      })
    )
    composite <- c(
      composite,
      lapply(setdiff(returned, ids), function(id) {
        composite_sample_rows(id, label, x[["provenance"]][["sample_id"]][rows])
      })
    )
  }

  # drop NA coverage on the counted half (routed member, wrong sex).
  counted <- do.call(rbind, counted)
  counted <- counted[!is.na(counted[["coverage"]]), , drop = FALSE]

  # seed with the empty frame so the column types and order are fixed
  out <- do.call(
    rbind,
    c(list(empty_sample_rows(keep)), list(counted), composite)
  )
  rownames(out) <- NULL
  say_low_samples(out, finalize_samples_gate(x))
  attach_notes(drop_single_batch(out, batch), gap_reasons(x), partial_cells(x))
}

# join key for one (sample, clock, panel) cell. build it the same way everywhere.
cell_key <- function(id, clock_id, panel) {
  # paste() recycles the scalar panel up, but returns one element rather than
  # none for an empty id -- which would shift every note off its key
  if (!length(id)) {
    return(character(0))
  }
  paste(id, clock_id, panel, sep = "\r")
}

# the norm-panel cells whose calibration was only partly applied
partial_cells <- function(x) {
  partial <- x[["provenance"]][["partial_calibration"]]
  unlist(
    lapply(names(partial), function(id) cell_key(partial[[id]], id, "norm")),
    use.names = FALSE
  )
}

# attach each row's note: score rows from the gap walk, norm rows from the
# calibrations that were only partly applied.
attach_notes <- function(out, gaps, partial) {
  key <- c(cell_key(gaps[["id"]], gaps[["clock_id"]], "score"), partial)
  note <- c(gaps[["note"]], rep("partial", length(partial)))

  cols <- names(out)
  rows <- cell_key(out[["id"]], out[["clock_id"]], out[["panel"]])
  out[["note"]] <- note[match(rows, key)]
  # mc_batch_id stays last: it is the join key, and it is a hash
  out[c(setdiff(cols, MC_BATCH), "note", intersect(MC_BATCH, cols))]
}
