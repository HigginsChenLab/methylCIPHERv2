# why a score is NA. every reason is derived from the finished record, so
# nothing about a gap is stored and nothing can drift from the gate that made it.

# tested in this order. the first that fires is the cell's reason.
GAP_REASONS <- c(
  "covariate",
  "clock_coverage",
  "sample_coverage",
  "fit",
  "dependency"
)

# empty score_gaps() frame. seeds rbind and matches the batch-column test.
empty_gap_rows <- function(keep_batch) {
  out <- data.frame(
    id = character(0),
    clock_id = character(0),
    reason = character(0),
    stringsAsFactors = FALSE
  )
  if (keep_batch) {
    out[[MC_BATCH]] <- character(0)
  }
  out
}

# one batch's coverage in the shape row_gate() reads (id-keyed, rows subset)
batch_gate_input <- function(x, per_clock, rows) {
  ids <- covered_ids(per_clock)
  pull <- function(panel) {
    m <- x[["coverage"]][["sample_miss"]][[panel]]
    out <- lapply(ids, function(id) {
      if (id %in% colnames(m)) m[rows, id] else NULL
    })
    stats::setNames(out, ids)
  }
  list(
    per_clock = per_clock,
    sample_miss = list(score = pull("score"), norm = pull("norm"))
  )
}

# reason -> clock id -> logical over this batch's samples. every clock the run
# computed, not just the ones it returned.
gap_masks <- function(x, per_clock, gate, floor, rows, ids) {
  pheno <- x[["pheno"]]
  sample_id <- x[["provenance"]][["sample_id"]][rows]
  failures <- x[["provenance"]][["scoring_failures"]]
  none <- rep(FALSE, length(sample_id))

  test <- list(
    covariate = function(id) {
      need <- intersect(clock_covariates_required(id), names(pheno))
      Reduce(`|`, lapply(need, function(v) is.na(pheno[[v]][rows])), none)
    },
    clock_coverage = function(id) {
      rec <- per_clock[[id]]
      if (is.null(rec)) {
        return(none)
      }
      hit <- clock_gate_verdict(
        rec[["score_present"]],
        rec[["score_needed"]],
        floor
      ) ==
        "na"
      if (hit) !none else none
    },
    sample_coverage = function(id) gate[[id]][["na"]] %||% none,
    fit = function(id) sample_id %in% failures[[id]]
  )

  lapply(test, function(f) stats::setNames(lapply(ids, f), ids))
}

# walk every computed clock in dependency order, carrying two things per clock:
# where it is NA, and why. a returned clock reads its own column for the first.
gap_walk <- function(x, scores, masks, seq_ids, rows) {
  routed <- sex_routed_members()
  sex <- sex_rows(x[["pheno"]][["Female"]][rows], sum(rows))
  none <- rep(FALSE, sum(rows))
  returned <- colnames(scores)
  na <- list()
  why <- list()

  for (id in seq_ids) {
    if (id %in% returned) {
      gone <- is.na(scores[rows, id])
    } else {
      own <- Reduce(`|`, lapply(masks, function(m) m[[id]] %||% none), none)
      gone <- Reduce(
        `|`,
        lapply(clock_depends_on(id), function(d) na[[d]] %||% none),
        own
      )
      # a routed member is absent outside its own sex by construction, not by
      # a gap. masking here is what lets its alias take the dependency rule.
      key <- routed[["sex"]][[id]]
      if (!is.null(key)) {
        gone <- gone & sex[[key]]
      }
    }

    r <- rep(NA_character_, length(gone))
    for (nm in setdiff(GAP_REASONS, "dependency")) {
      r[is.na(r) & gone & (masks[[nm]][[id]] %||% none)] <- nm
    }
    for (d in clock_depends_on(id)) {
      take <- is.na(r) & gone & (na[[d]] %||% none)
      # a dependency that never reaches the frame hands over its own reason,
      # so every row the reader gets names a clock they can find in it.
      r[take] <- if (d %in% returned) "dependency" else why[[d]][take]
    }
    na[[id]] <- gone
    why[[id]] <- r
  }
  why
}

# one batch's rows, one per NA cell
batch_gaps <- function(x, b, rows, seq_ids, batch) {
  per_clock <- x[["coverage"]][["per_clock"]][[b]]
  prov <- x[["provenance"]]
  clock_floor <- prov[["min_clocks_coverage"]][[b]]

  # the column gate first: at score time it decided which clocks the row gate
  # was even asked about, and skipping them here keeps the two the same shape.
  gated <- names(per_clock)[vapply(
    names(per_clock),
    function(id) {
      rec <- per_clock[[id]]
      !is.null(rec) &&
        clock_gate_verdict(
          rec[["score_present"]],
          rec[["score_needed"]],
          clock_floor
        ) ==
          "na"
    },
    logical(1L)
  )]
  gate <- row_gate(
    batch_gate_input(x, per_clock, rows),
    prov[["min_samples_coverage"]][[b]],
    skip = gated
  )

  scores <- x[["scores"]]
  masks <- gap_masks(x, per_clock, gate, clock_floor, rows, seq_ids)
  why <- gap_walk(x, scores, masks, seq_ids, rows)
  sample_id <- x[["provenance"]][["sample_id"]][rows]

  parts <- lapply(colnames(scores), function(id) {
    na_col <- is.na(scores[rows, id])
    if (!any(na_col)) {
      return(NULL)
    }
    reason <- why[[id]]
    blind <- na_col & is.na(reason)
    if (any(blind)) {
      stop(
        sprintf(
          paste0(
            "score_gaps(): no reason for %d NA scores of %s ",
            "(batch %s). This is a package bug -- please report it."
          ),
          sum(blind),
          id,
          b
        ),
        call. = FALSE
      )
    }
    keep <- !is.na(reason)
    out <- data.frame(
      id = sample_id[keep],
      clock_id = id,
      reason = reason[keep],
      stringsAsFactors = FALSE,
      row.names = NULL
    )
    if (!is.null(batch)) {
      out[[MC_BATCH]] <- batch
    }
    out
  })
  do.call(rbind, parts)
}

# one row per NA score
#' Reasons A Score Is Missing
#'
#' Reports why each `NA` score in `x` is missing, one row for each missing
#' score.
#'
#' @inheritParams mc-params
#'
#' @details
#' Every reason is worked out from `x` itself, so the frame always agrees
#' with the coverage counts and the gates that `calc_clocks()` used. A run
#' with no missing score gives a frame with no rows.
#'
#' The `reason` column takes one of five values. Where more than one applies,
#' the first of these is given.
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
#'
#' A `dependency` row always names a clock that has its own rows in the
#' frame, so the cause can be followed to it. A clock scored separately for
#' each sex takes the reason of the model for that sample's sex, because
#' that model is not one of the scores of `x`.
#'
#' Each floor is read for the batch the sample was scored in, which is the
#' floor that decided the score. The `mc_batch_id` column appears only when
#' `x` holds more than one batch.
#'
#' @returns A data.frame. One row for each missing score, with the sample
#'   `id`, the `clock_id`, the `reason`, and, when `x` holds more than one
#'   batch, `mc_batch_id`.
#'
#' @examples
#' clocks <- c("Horvath1", "Hannum")
#' sim <- sim_DNAm(clocks, n = 20)
#' # keep half the CpGs, so a clock falls under the coverage floor
#' DNAm <- sim[["DNAm"]]
#' res <- calc_clocks(DNAm[, seq(1, ncol(DNAm), by = 2)], clocks)
#'
#' head(score_gaps(res))
#'
#' @export
score_gaps <- function(x) {
  check_mc_result(x)
  # a finalizer: a cross-sample column is all NA until its reduction runs
  x <- finalized(x)
  batch <- x[["provenance"]][[MC_BATCH]]
  keep <- n_batches(x) > 1L
  seq_ids <- resolve_clocks_sequence(x[["provenance"]][["requested"]])

  parts <- lapply(names(x[["coverage"]][["per_clock"]]), function(b) {
    batch_gaps(x, b, batch == b, seq_ids, if (keep) b else NULL)
  })
  out <- do.call(rbind, c(list(empty_gap_rows(keep)), parts))
  rownames(out) <- NULL
  drop_single_batch(out, batch)
}
