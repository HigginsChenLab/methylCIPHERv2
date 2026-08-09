# what happened to a score cell (derived from the finished result, not stored).

# cells that need a note: missing, or not a finite number.
needs_note <- function(m) is.na(m) | is.infinite(m)

# not a finite number, as opposed to merely missing. a positive test, so a
# plain NA with no explanation still reaches the blind check in batch_gaps().
not_finite <- function(m) is.nan(m) | is.infinite(m)

# character matrix shaped like scores (sample x clock), all NA.
reason_matrix <- function(m) {
  matrix(
    NA_character_,
    nrow = nrow(m),
    ncol = ncol(m),
    dimnames = dimnames(m)
  )
}

# one batch's coverage in row_gate() shape (scoring panel only).
batch_gate_input <- function(x, per_clock, rows) {
  ids <- covered_ids(per_clock)
  # one row subset for the panel, not one per clock
  m <- x[["coverage"]][["sample_miss"]][["score"]][rows, , drop = FALSE]
  list(
    per_clock = per_clock,
    sample_miss = list(
      score = stats::setNames(lapply(ids, function(id) m[, id]), ids)
    )
  )
}

# reason -> clock id -> logical over batch samples (list order = precedence).
gap_masks <- function(x, gated, gate, rows, ids) {
  sample_id <- x[["provenance"]][["sample_id"]][rows]
  failures <- x[["provenance"]][["scoring_failures"]]
  none <- rep(FALSE, length(rows))
  # one sweep per covariate column, not one per clock that reads it
  na_cov <- lapply(x[["pheno"]][rows, , drop = FALSE], is.na)

  # the collector is keyed clock -> cause -> ids, so one closure per cause.
  fit_mask <- function(cause) {
    function(id) {
      lost <- failures[[id]][[cause]]
      if (is.null(lost)) none else sample_id %in% lost
    }
  }

  test <- list(
    covariate = function(id) {
      need <- intersect(clock_covariates_required(id), names(na_cov))
      Reduce(`|`, na_cov[need], none)
    },
    # the column gate already graded every clock. this reads its verdict.
    clock_coverage = function(id) if (id %in% gated) !none else none,
    sample_coverage = function(id) gate[[id]][["na"]] %||% none,
    # spelled out rather than built from MC_NOTE_CAUSES: the list order is the
    # precedence, so it must be readable here and not in a constant. pipeline
    # order, so a clock that ever hits two reports the cause, not the effect.
    fit_bmiq = fit_mask("fit_bmiq"),
    fit_spread = fit_mask("fit_spread"),
    fit_reduce = fit_mask("fit_reduce")
  )

  lapply(test, function(f) stats::setNames(lapply(ids, f), ids))
}

# walk computed clocks in dependency order; fill one note per cell.
gap_walk <- function(x, na_mat, nf, masks, seq_ids, rows) {
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
      # mask routed members outside their sex so the alias owns the dependency rule.
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
      # map dep reasons onto returned clocks the reader can find.
      r[take] <- if (d %in% returned) "dependency" else why[[d]][take]
    }
    # last, so a dependency that is itself non-finite gives the better story:
    # the dependency is not_finite, and the clock built from it is dependency.
    if (id %in% returned) {
      r[is.na(r) & nf[, id]] <- "not_finite"
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

  # skip column-gated clocks so row_gate matches score time.
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

  # one sweep of the score pattern, read by the walk and by the check below
  sc <- x[["scores"]][rows, , drop = FALSE]
  na_mat <- needs_note(sc)
  masks <- gap_masks(x, gated, gate, rows, seq_ids)
  why <- gap_walk(x, na_mat, not_finite(sc), masks, seq_ids, rows)

  out <- reason_matrix(na_mat)
  for (id in colnames(out)) {
    out[, id] <- why[[id]]
  }
  blind <- na_mat & is.na(out)
  if (any(blind)) {
    stop(
      sprintf(
        paste0(
          "gap_reasons(): no note for %d score cell(s) of %s ",
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

# one row per NA score (id, clock_id, note); caller must finalize x first.
gap_reasons <- function(x) {
  batch <- x[["provenance"]][[MC_BATCH]]
  scores <- x[["scores"]]

  reasons <- reason_matrix(scores)
  # nothing to explain
  if (any(needs_note(scores))) {
    seq_ids <- resolve_clocks_sequence(x[["provenance"]][["requested"]])
    # positions, so a batch subsets its own rows and not the whole record
    idx <- split(seq_along(batch), batch)
    for (b in names(x[["coverage"]][["per_clock"]])) {
      rows <- idx[[b]]
      reasons[rows, ] <- batch_gaps(x, b, rows, seq_ids)
    }
  }

  out <- shape_scores(reasons, "id", "note", batch, long = TRUE)
  out <- out[!is.na(out[["note"]]), c("id", "clock_id", "note")]
  rownames(out) <- NULL
  out
}
