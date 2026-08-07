# why a score is NA. every reason is derived from the finished record, so
# nothing about a gap is stored and nothing can drift from the gate that made it.

# the cells this function must explain. `is.na()` is TRUE for NaN, which is a
# computed value check_score_values() already reports, not a missing score.
missing_scores <- function(m) is.na(m) & !is.nan(m)

# an all-NA character matrix on another matrix's axes. one row per sample,
# one column per clock, so shape_scores() melts it like any score matrix.
reason_matrix <- function(m) {
  matrix(
    NA_character_,
    nrow = nrow(m),
    ncol = ncol(m),
    dimnames = dimnames(m)
  )
}

# one batch's coverage in the shape row_gate() reads (id-keyed, rows subset).
# the row gate reads the scoring panel alone, so the norm panel is not needed.
batch_gate_input <- function(x, per_clock, rows) {
  ids <- covered_ids(per_clock)
  # one row subset for the panel, not one per clock
  m <- x[["coverage"]][["sample_miss"]][["score"]][rows, , drop = FALSE]
  list(
    per_clock = per_clock,
    sample_miss = list(score = stats::setNames(lapply(ids, function(id) m[, id]), ids))
  )
}

# reason -> clock id -> logical over this batch's samples. every clock the run
# computed, not just the ones it returned. the list order is the precedence.
gap_masks <- function(x, gated, gate, rows, ids) {
  sample_id <- x[["provenance"]][["sample_id"]][rows]
  failures <- x[["provenance"]][["scoring_failures"]]
  none <- rep(FALSE, length(rows))
  # one sweep per covariate column, not one per clock that reads it
  na_cov <- lapply(x[["pheno"]][rows, , drop = FALSE], is.na)

  test <- list(
    covariate = function(id) {
      need <- intersect(clock_covariates_required(id), names(na_cov))
      Reduce(`|`, na_cov[need], none)
    },
    # the column gate already graded every clock. this reads its verdict.
    clock_coverage = function(id) if (id %in% gated) !none else none,
    sample_coverage = function(id) gate[[id]][["na"]] %||% none,
    fit = function(id) {
      lost <- failures[[id]]
      if (is.null(lost)) none else sample_id %in% lost
    }
  )

  lapply(test, function(f) stats::setNames(lapply(ids, f), ids))
}

# walk every computed clock in dependency order, carrying where it is NA and
# why. a returned clock reads its own column for the first; masks is keyed by
# seq_ids and dependencies precede dependents, so every lookup is populated.
gap_walk <- function(x, na_mat, masks, seq_ids, rows) {
  routed <- sex_routed_members()
  sex <- sex_rows(x[["pheno"]][["Female"]][rows], length(rows))
  none <- rep(FALSE, length(rows))
  returned <- colnames(na_mat)
  na <- list()
  why <- list()

  for (id in seq_ids) {
    if (id %in% returned) {
      gone <- na_mat[, id]
    } else {
      own <- Reduce(`|`, lapply(masks, function(m) m[[id]]), none)
      gone <- Reduce(
        `|`,
        lapply(clock_depends_on(id), function(d) na[[d]]),
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
    for (nm in names(masks)) {
      r[is.na(r) & gone & masks[[nm]][[id]]] <- nm
    }
    for (d in clock_depends_on(id)) {
      take <- is.na(r) & gone & na[[d]]
      # a dependency that never reaches the frame hands over its own reason,
      # so every row the reader gets names a clock they can find in it.
      r[take] <- if (d %in% returned) "dependency" else why[[d]][take]
    }
    na[[id]] <- gone
    why[[id]] <- r
  }
  why
}

# one batch's reasons, as a character matrix over the returned clocks
batch_gaps <- function(x, b, rows, seq_ids) {
  per_clock <- x[["coverage"]][["per_clock"]][[b]]
  prov <- x[["provenance"]]
  clock_floor <- prov[["min_clocks_coverage"]][[b]]

  # the column gate first: at score time it decided which clocks the row gate
  # was even asked about, and skipping them here keeps the two the same shape.
  gated <- Filter(
    function(id) {
      rec <- per_clock[[id]]
      if (is.null(rec)) {
        return(FALSE)
      }
      verdict <- clock_gate_verdict(
        rec[["score_present"]],
        rec[["score_needed"]],
        clock_floor
      )
      verdict %in% GATE_NA
    },
    names(per_clock)
  )
  gate <- row_gate(
    batch_gate_input(x, per_clock, rows),
    prov[["min_samples_coverage"]][[b]],
    skip = gated
  )

  # one sweep of the NA pattern, read by the walk and by the check below
  na_mat <- missing_scores(x[["scores"]][rows, , drop = FALSE])
  masks <- gap_masks(x, gated, gate, rows, seq_ids)
  why <- gap_walk(x, na_mat, masks, seq_ids, rows)

  out <- reason_matrix(na_mat)
  for (id in colnames(out)) {
    out[, id] <- why[[id]]
  }
  blind <- na_mat & is.na(out)
  if (any(blind)) {
    stop(
      sprintf(
        paste0(
          "gap_reasons(): no reason for %d NA score(s) of %s ",
          "(batch %s). This is a package bug -- please report it."
        ),
        sum(blind),
        paste(colnames(blind)[apply(blind, 2L, any)], collapse = ", "),
        b
      ),
      call. = FALSE
    )
  }
  out
}

# one row per NA score, as (id, clock_id, reason). internal: samples_coverage()
# joins it onto its score rows, and must pass an already finalized `x`.
gap_reasons <- function(x) {
  batch <- x[["provenance"]][[MC_BATCH]]
  scores <- x[["scores"]]

  reasons <- reason_matrix(scores)
  # nothing to explain: the walk never runs over a record with every score
  if (any(missing_scores(scores))) {
    seq_ids <- resolve_clocks_sequence(x[["provenance"]][["requested"]])
    # positions, so a batch subsets its own rows and not the whole record
    idx <- split(seq_along(batch), batch)
    for (b in names(x[["coverage"]][["per_clock"]])) {
      rows <- idx[[b]]
      reasons[rows, ] <- batch_gaps(x, b, rows, seq_ids)
    }
  }

  out <- shape_scores(reasons, "id", "reason", batch, long = TRUE)
  out <- out[!is.na(out[["reason"]]), c("id", "clock_id", "reason")]
  rownames(out) <- NULL
  out
}
