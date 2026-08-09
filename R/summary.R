# a digest of one finished run. built from samples_coverage(), so it inherits
# that exit's finalization and never reads a score value itself.

# one row per batch: the shape of the matrix scored, and its value verdicts.
input_rows <- function(input, batch) {
  out <- data.frame(
    n_cpgs = rec_field(input, "n_cpgs", NA_integer_),
    n_scanned = rec_field(input, "n_scanned", NA_integer_),
    n_all_missing = rec_field(input, "n_all_na", NA_integer_),
    min_val = rec_field(input, "min_val", NA_real_),
    min_col = rec_field(input, "min_col", NA_character_),
    max_val = rec_field(input, "max_val", NA_real_),
    max_col = rec_field(input, "max_col", NA_character_),
    any_inf = rec_field(input, "any_inf", NA),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  # min_val and max_val are seeded at the beta bounds, so they read 0 and 1
  # on a clean run whatever the data holds. they are a verdict, not a range,
  # and say something only beside the column that broke the bound.
  drop <- c(
    if (all(is.na(out[["min_col"]]))) c("min_val", "min_col"),
    if (all(is.na(out[["max_col"]]))) c("max_val", "max_col"),
    if (!any(out[["any_inf"]])) "any_inf"
  )
  add_batch(out[, setdiff(names(out), drop), drop = FALSE], batch)
}

# one batch's normalize= request, as a single cell.
normalize_cell <- function(v) {
  if (!length(v)) NA_character_ else paste(v, collapse = ", ")
}

# one row per batch: the values the batch was scored under.
argument_rows <- function(prov, labels, batch) {
  out <- data.frame(
    min_clocks_coverage = unname(prov[["min_clocks_coverage"]][labels]),
    min_samples_coverage = unname(prov[["min_samples_coverage"]][labels]),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  requested <- vapply(
    labels,
    function(b) normalize_cell(prov[["normalize_requested"]][[b]]),
    character(1L),
    USE.NAMES = FALSE
  )
  done <- normalize_cell(prov[["normalized"]])
  # normalization says nothing where none was asked for and none happened
  if (any(!is.na(requested)) || !is.na(done)) {
    out[["normalize"]] <- requested
    # what happened, beside what was asked for, only where the two differ
    if (!identical(requested, rep(done, length(requested)))) {
      out[["normalized"]] <- done
    }
  }
  add_batch(out, batch)
}

# long (unit, note) counts: one row per unit, panel, note and batch. the frame
# holds one row per (id, clock_id, panel), so the group size is the count.
note_counts <- function(noted, unit, counted, count_name, keys) {
  out <- noted[, c(unit, "panel", "note", keys), drop = FALSE]
  # first appearance keeps the frame's own order, which is clock major
  key <- do.call(paste, c(unname(out), sep = "\r"))
  first <- !duplicated(key)
  out <- out[first, , drop = FALSE]
  out[[count_name]] <- tabulate(match(key, key[first]), sum(first))
  rownames(out) <- NULL
  # batch last, like every other frame: it is the join key, and it is a hash
  out[c(unit, "panel", "note", count_name, keys)]
}

# one row per batch, with the samples it scored.
batch_rows <- function(batch, labels) {
  out <- data.frame(
    n_samples = tabulate(match(batch, labels), length(labels)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  # the label identifies the row here, so it leads rather than joins
  out[[MC_BATCH]] <- labels
  out[c(MC_BATCH, "n_samples")]
}

#' Summary Of A Scoring Run
#'
#' Reports what `object` was scored from, what it was asked for, and what
#' happened to every score that is missing.
#'
#' @param object An `mc_result` object.
#' @param ... Not used.
#'
#' @details
#' The `input` table describes the matrix each batch was scored from.
#' `n_cpgs` is the number of columns it held, and `n_scanned` is the number
#' of those columns the clocks needed. `n_all_missing` counts the scanned
#' columns with no value for any sample.
#'
#' Four more columns appear only where a scanned value is outside `0` to
#' `1`. `min_val` and `max_val` give that value, and `min_col` and `max_col`
#' name the column it is in. A fifth column, `any_inf`, appears where a
#' value is infinite.
#'
#' The `arguments` table gives the values each batch was scored under. Two
#' batches can differ, because each one keeps the values of the call that
#' scored it.
#'
#' The two problem tables count the same notes two ways, and neither is
#' collapsed. `by_clock` gives the samples for each clock, panel and note,
#' and `by_sample` gives the clocks for each sample, panel and note. A note
#' on a `score` row means the score is missing. A note on a `norm` row is
#' about the background panel, and the score may still be present. See
#' [samples_coverage()] for what each note means.
#'
#' Totals are never added across batches, because each batch was scored from
#' a different matrix.
#'
#' @returns An `mc_summary` object. It holds the clocks requested and scored,
#'   the `input` and `arguments` tables, the `by_clock` and `by_sample`
#'   problem tables, and, when `object` holds more than one batch, the
#'   batches.
#'
#' @seealso
#' - [clocks_coverage()] for the CpG counts behind each clock's score.
#' - [samples_coverage()] for the counts and the `note` of each sample.
#'
#' @examples
#' clocks <- c("Horvath1", "Hannum")
#' sim <- sim_DNAm(clocks, n = 20)
#' res <- calc_clocks(sim[["DNAm"]], clocks)
#'
#' summary(res)
#'
#' @export
summary.mc_result <- function(object, ...) {
  check_mc_result(object, "object")
  # samples_coverage() finalizes, so this must not. it also decides the
  # batch column, and that decision is read here rather than made again.
  cov <- samples_coverage(object)
  keep_batch <- MC_BATCH %in% names(cov)
  prov <- object[["provenance"]]
  labels <- batch_labels(object)

  noted <- cov[!is.na(cov[["note"]]), , drop = FALSE]
  keys <- if (keep_batch) MC_BATCH else character(0)
  # one label vector for every table, or NULL where the frame withheld it
  batch <- if (keep_batch) labels else NULL

  structure(
    list(
      n_samples = nrow(object[["scores"]]),
      n_clocks = ncol(object[["scores"]]),
      requested = prov[["requested"]],
      scored = prov[["clocks"]],
      input = input_rows(prov[["input"]][labels], batch),
      arguments = argument_rows(prov, labels, batch),
      by_clock = note_counts(noted, "clock_id", "id", "n_samples", keys),
      by_sample = note_counts(noted, "id", "clock_id", "n_clocks", keys),
      # withheld with the column, so one flag decides the whole object
      batches = if (keep_batch) batch_rows(prov[[MC_BATCH]], labels) else NULL
    ),
    class = "mc_summary"
  )
}

#' Print Method For An mc_summary Object
#'
#' Prints the tables of an `mc_summary` object.
#'
#' @param x An `mc_summary` object.
#' @param n A single whole number. The number of rows to print for each
#'   table. Default is `6`.
#' @param ... Not used.
#'
#' @returns An `mc_summary` object. Returns `x`, invisibly, after printing it.
#'
#' @examples
#' clocks <- c("Horvath1", "Hannum")
#' sim <- sim_DNAm(clocks, n = 20)
#' res <- calc_clocks(sim[["DNAm"]], clocks)
#' print(summary(res), n = 3)
#'
#' @export
print.mc_summary <- function(x, n = 6, ...) {
  cat(
    fmt_header(
      "mc_summary",
      x[["n_samples"]],
      "sample",
      x[["n_clocks"]],
      "clock"
    ),
    "\n",
    sep = ""
  )

  # "requested" and "scored" are set sizes, not the cut axis the tail counts
  requested <- x[["requested"]]
  print_vector(
    "clocks",
    requested,
    min(n, length(requested)),
    "clock",
    sprintf("%d requested", length(requested)),
    sprintf("%d scored", length(x[["scored"]]))
  )

  # one row per batch, so both count batches and not rows
  print_table("input", x[["input"]], n, "batch", "es")
  print_table("arguments", x[["arguments"]], n, "batch", "es")

  by_clock <- x[["by_clock"]]
  if (!nrow(by_clock)) {
    cat("\n", fmt_named_section("problems", "none"), "\n", sep = "")
  } else {
    print_table("problems by clock", by_clock, n)
    print_table("problems by sample", x[["by_sample"]], n)
  }

  # the labels, not the component that stores them
  batches <- x[["batches"]]
  if (!is.null(batches)) {
    print_table(MC_BATCH, batches, n, "batch", "es")
  }

  invisible(x)
}
