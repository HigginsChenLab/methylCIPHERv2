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
  # min_val and max_val are seeded at the beta bounds, so they read 0 and 1 on
  # a clean run and say something only beside the column that broke a bound.
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

# group `df` by `cols` and count the rows of each group. first appearance keeps
# the frame's own order, which is clock major.
group_count <- function(df, cols, count_name) {
  out <- df[, cols, drop = FALSE]
  key <- do.call(paste, c(unname(out), sep = "\r"))
  first <- !duplicated(key)
  out <- out[first, , drop = FALSE]
  out[[count_name]] <- tabulate(match(key, key[first]), sum(first))
  rownames(out) <- NULL
  out
}

# batch in the order the run holds it, so a capped table shows one batch
# before the next. NULL where the frame withheld the column.
batch_key <- function(df, labels) {
  if (MC_BATCH %in% names(df)) {
    factor(df[[MC_BATCH]], levels = labels)
  }
}

# panel then note, each on its declared order rather than alphabetically.
# panel is redundant while partial is the only norm note, and is kept anyway.
note_keys <- function(df) {
  list(
    factor(df[["panel"]], levels = c("score", "norm")),
    factor(df[["note"]], levels = names(MC_NOTES))
  )
}

sort_rows <- function(df, keys) {
  out <- df[do.call(order, Filter(Negate(is.null), keys)), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# one row per clock, panel, note and batch. the source frame holds one row per
# (id, clock_id, panel), so the group size is the sample count.
clock_notes <- function(noted, keys, labels) {
  cols <- c("clock_id", "panel", "note")
  out <- group_count(noted, c(cols, "explanation", keys), "n_samples")
  # explanation trails the counts: it is the one column of variable width, and
  # a sentence between two short ones reads as a run-on. batch stays last.
  out <- out[c(cols, "n_samples", "explanation", keys)]
  # clock in the order the frame first names it, which is score-column order
  # for the clocks that counted CpGs and puts the rest after them.
  sort_rows(
    out,
    c(
      list(
        batch_key(out, labels),
        match(out[["clock_id"]], unique(out[["clock_id"]]))
      ),
      note_keys(out)
    )
  )
}

# the same notes counted by sample: how many samples lost how many clocks, for
# each panel and note. samples_coverage() is what names the sample.
sample_notes <- function(noted, keys, labels) {
  cols <- c("panel", "note")
  grp <- c(cols, "explanation")
  per_sample <- group_count(noted, c("id", grp, keys), "n_clocks")
  out <- group_count(per_sample, c(grp, "n_clocks", keys), "n_samples")
  out <- out[c(cols, "n_clocks", "n_samples", "explanation", keys)]
  # no clock to key on, so the note orders it. widest spread first.
  sort_rows(
    out,
    c(list(batch_key(out, labels)), note_keys(out), list(-out[["n_clocks"]]))
  )
}

# the clocks that produced no value at all: a score-panel note for every
# sample. derived from the frame, so no score cell is read.
failed_clocks <- function(noted, clocks, n_samples) {
  hit <- table(noted[["clock_id"]][noted[["panel"]] == "score"])
  intersect(clocks, names(hit)[hit >= n_samples])
}

# a problem table as it prints. the phrase on every row wraps the table, so the
# token prints and note_legend() states each phrase once.
shown_notes <- function(df) {
  df[setdiff(names(df), "explanation")]
}

# hex of a batch label kept where the label joins a table to its batch. every
# table shortens it except the mc_batch_id table, which prints it whole.
MC_BATCH_SHOWN <- 7L

shown_batch <- function(df) {
  if (MC_BATCH %in% names(df)) {
    df[[MC_BATCH]] <- paste0(substr(df[[MC_BATCH]], 1L, MC_BATCH_SHOWN), "...")
  }
  df
}

# the phrase behind every token the two tables show, in the order they show it.
# built from the rows that print, never a row the cap held back.
note_legend <- function(...) {
  note <- unique(unlist(lapply(list(...), function(df) df[["note"]])))
  note <- note[order(factor(note, levels = names(MC_NOTES)))]
  data.frame(
    note = note,
    explanation = explain_notes(note),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
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
#' The requested clocks are the ones the `clocks` argument of [calc_clocks()]
#' asked for. A clock that another clock needs is a dependency, and it gets a
#' score column of its own. The two sets together give every score column.
#'
#' A clock is failed when every sample has a `score` note for it, because it
#' then produced no value at all. The clocks that produced a value are
#' scored. Both sets cover the dependencies as well as the requested clocks.
#' A run reports no failed clock when every clock produced one.
#'
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
#' The two problem tables count the same notes two ways. `by_clock` gives
#' the number of samples for each clock, panel and note. `by_sample` counts
#' the samples that lost the same number of clocks, for each panel and note,
#' so it says how far a problem spread and not which sample it reached.
#' [samples_coverage()] names the sample.
#'
#' A note on a `score` row means the score is missing. A note on a `norm`
#' row is about the background panel, and the score may still be present.
#' Both tables carry the `explanation` of each note beside it, and
#' [samples_coverage()] gives the full set of notes.
#'
#' Both tables are ordered by batch and then by `note`. `by_clock` keeps the
#' order of the score columns, and `by_sample` gives the widest spread first.
#'
#' Totals are never added across batches, because each batch was scored from
#' a different matrix.
#'
#' @returns An `mc_summary` object. It holds the clocks requested and the
#'   dependencies they needed, the clocks scored and failed, the `input` and
#'   `arguments` tables, the `by_clock` and `by_sample` problem tables, and,
#'   when `object` holds more than one batch, the batches.
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

  n <- nrow(object[["scores"]])
  failed <- failed_clocks(noted, prov[["clocks"]], n)

  structure(
    list(
      n_samples = n,
      n_clocks = ncol(object[["scores"]]),
      requested = prov[["requested"]],
      # what the request pulled in. the two sets sum to the score columns,
      # which is what makes the printed counts reconcile.
      dependencies = prov[["dependencies"]],
      scored = setdiff(prov[["clocks"]], failed),
      failed = failed,
      input = input_rows(prov[["input"]][labels], batch),
      arguments = argument_rows(prov, labels, batch),
      by_clock = clock_notes(noted, keys, labels),
      by_sample = sample_notes(noted, keys, labels),
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
#' @details
#' The two problem tables print the `note` of each row. The notes table under
#' them gives the `explanation` of every note they print. The `explanation`
#' stays in `x` beside the `note`.
#'
#' Every table shortens `mc_batch_id` to its first seven characters, except
#' the `mc_batch_id` table, which gives every label in full.
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

  # both are set sizes, not the cut axis the tail counts, and they sum to the
  # header's clock count. a scored count is arithmetic, so it is left out.
  requested <- x[["requested"]]
  dependencies <- x[["dependencies"]]
  print_vector(
    "clocks",
    requested,
    min(n, length(requested)),
    "clock",
    sprintf("%d requested", length(requested)),
    if (length(dependencies)) {
      sprintf("%d dependencies", length(dependencies))
    }
  )

  # named, never counted: which clock produced nothing is what the reader
  # acts on, and a count leaves them to derive it from the problem tables.
  failed <- x[["failed"]]
  if (length(failed)) {
    print_vector(
      "failed",
      failed,
      min(n, length(failed)),
      "clock",
      plural_count(length(failed), "clock")
    )
  }

  # one row per batch, so both count batches and not rows
  print_table("input", shown_batch(x[["input"]]), n, "batch", "es")
  print_table("arguments", shown_batch(x[["arguments"]]), n, "batch", "es")

  by_clock <- x[["by_clock"]]
  if (!nrow(by_clock)) {
    cat("\n", fmt_named_section("problems", "none"), "\n", sep = "")
  } else {
    by_sample <- x[["by_sample"]]
    print_table("problems by clock", shown_batch(shown_notes(by_clock)), n)
    print_table("problems by sample", shown_batch(shown_notes(by_sample)), n)
    # keyed on the rows that printed, so it explains those and nothing else
    legend <- note_legend(utils::head(by_clock, n), utils::head(by_sample, n))
    print_table("notes", legend, nrow(legend), "note")
  }

  # the labels, not the component that stores them
  batches <- x[["batches"]]
  if (!is.null(batches)) {
    print_table(MC_BATCH, batches, n, "batch", "es")
  }

  invisible(x)
}
