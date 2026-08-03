# formatters over a finished record's $coverage (no re-touch of beta)

# every caller is an exported verb taking a user-supplied record, so this is a
# front-door refusal and reads as cli, not as a developer stop().
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

# one batch's rows (aliases have NA panels).
# batch is NULL when the exit drops the label.
batch_coverage <- function(per_clock, batch, returned) {
  ids <- names(per_clock)

  int_field <- function(nm) {
    unname(vapply(
      per_clock,
      function(r) if (is.null(r)) NA_integer_ else as.integer(r[[nm]]),
      integer(1L)
    ))
  }

  out <- data.frame(
    clock_id = ids,
    # from the catalog, not the record -- a NULL record still has a group
    group_id = unname(vapply(ids, clock_group_id, character(1L))),
    role = ifelse(ids %in% returned, "returned", "routing_target"),
    policy = unname(vapply(
      per_clock,
      function(r) if (is.null(r)) NA_character_ else r[["policy"]],
      character(1L)
    )),
    normalizes = unname(vapply(
      per_clock,
      function(r) if (is.null(r)) NA else r[["normalizes"]],
      logical(1L)
    )),
    score_needed = int_field("score_needed"),
    score_present = int_field("score_present"),
    score_used = int_field("score_used"),
    score_imputed_partial = int_field("score_imputed_partial"),
    score_imputed_full = int_field("score_imputed_full"),
    score_dropped = int_field("score_dropped"),
    norm_needed = int_field("norm_needed"),
    norm_present = int_field("norm_present"),
    norm_imputed_partial = int_field("norm_imputed_partial"),
    norm_imputed_full = int_field("norm_imputed_full"),
    norm_dropped = int_field("norm_dropped"),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  # absent-probe list stays a list-column
  out[["missing_cpgs"]] <- unname(lapply(
    per_clock,
    function(r) if (is.null(r)) character(0) else r[["missing_cpgs"]]
  ))
  # batch last: a hash next to clock_id reads as noise, but it is the join key
  if (!is.null(batch)) {
    out[[MC_BATCH]] <- batch
  }
  out
}

# one row per (clock, batch).
#' @export
clocks_coverage <- function(x) {
  check_mc_result(x)
  batches <- x[["coverage"]][["per_clock"]]
  returned <- x[["provenance"]][["clocks"]]
  batch <- x[["provenance"]][[MC_BATCH]]
  # keyed on provenance's per-sample vector, never on per_clock's names.
  keep <- is_multi_batch(batch)
  out <- do.call(
    rbind,
    lapply(names(batches), function(b) {
      batch_coverage(batches[[b]], if (keep) b else NULL, returned)
    })
  )
  rownames(out) <- NULL
  drop_single_batch(out, batch)
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
  # last join key, like clocks_coverage().
  # omitted at single batch so the column is never built.
  if (!is.null(batch)) {
    out[[MC_BATCH]] <- batch
  }
  out
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

# the exit's one gate: the most restrictive floor any bound batch was scored
# under. rbind keeps them per batch, so a filter on the frame needs one number.
finalize_samples_gate <- function(x) {
  max(x[["provenance"]][["min_samples_coverage"]])
}

# re-warn on the assembled frame, so a bound record says it once under one floor
say_low_samples <- function(out, threshold) {
  low <- out[["coverage"]] < threshold
  if (!any(low)) {
    return(invisible(NULL))
  }
  n_samp <- length(unique(out[["id"]][low]))
  cli::cli_warn(
    c(
      "{sum(low)} of {nrow(out)} row{?s} {cli::qty(sum(low))}{?is/are} under
       {.arg min_samples_coverage} = {format(threshold)}, across
       {n_samp} sample{?s}.",
      "i" = "The {.field coverage} column carries the fraction each row was
             scored on -- filter on it to see them."
    ),
    call = NULL
  )
  invisible(NULL)
}

# one row per (sample, returned clock, panel)
#' @export
samples_coverage <- function(x) {
  check_mc_result(x)
  batch <- x[["provenance"]][[MC_BATCH]]
  # one row per (sample, clock, panel). batch masks rows. label withheld when single-batch.
  keep <- is_multi_batch(batch)

  parts <- list()
  for (b in names(x[["coverage"]][["per_clock"]])) {
    per_clock <- x[["coverage"]][["per_clock"]][[b]]
    rows <- batch == b
    # no record means no cpgs of its own.
    ids <- covered_ids(per_clock)
    parts <- c(
      parts,
      lapply(ids, function(id) {
        clock_sample_rows(x, id, per_clock[[id]], if (keep) b else NULL, rows)
      })
    )
  }

  # seed with the empty frame so a run of pure composites keeps the shape
  out <- do.call(rbind, c(list(empty_sample_rows(keep)), parts))

  # drop na coverage rows (routed member on a sex it did not score)
  out <- out[!is.na(out[["coverage"]]), , drop = FALSE]
  rownames(out) <- NULL
  say_low_samples(out, finalize_samples_gate(x))
  drop_single_batch(out, batch)
}
