# finalizers: mc_result -> data.frame. one-way exits, so the record's other
# verbs (rbind, refinalize_clocks, coverage) are gone once you call one.

# re-finalize multi-batch pending before leaving the record, and say so
finalized <- function(x) {
  pending <- x[["provenance"]][["pending"]]
  if (length(pending) && length(x[["coverage"]][["per_clock"]]) > 1L) {
    x <- refinalize_clocks(x)
  }
  x
}

# n x k score matrix -> the shared long/wide frame. the batch label is last and
# multi-batch only, and the frame is keyed by the id column, never by row names
shape_scores <- function(m, id_col, value_col, batch, long) {
  checkmate::assert_flag(long)
  if (!long) {
    ids <- stats::setNames(
      data.frame(rownames(m), stringsAsFactors = FALSE),
      id_col
    )
    # optional = TRUE keeps make.names() off, so a column is exactly its clock id
    out <- cbind(ids, as.data.frame(m, optional = TRUE))
    out[[MC_BATCH]] <- batch
    rownames(out) <- NULL
    return(drop_single_batch(out, batch))
  }
  # clock-major, so the long frame reads in score-column order
  out <- data.frame(
    id = rep(rownames(m), times = ncol(m)),
    clock_id = rep(colnames(m), each = nrow(m)),
    value = as.vector(m),
    batch = rep(batch, times = ncol(m)),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  names(out) <- c(id_col, "clock_id", value_col, MC_BATCH)
  drop_single_batch(out, batch)
}

# scores as a frame. row.names/optional are the generic's, and unused -- the
# id column is the only key this frame has
#' @export
as.data.frame.mc_result <- function(
  x,
  row.names = NULL,
  optional = FALSE,
  ...,
  long = TRUE
) {
  check_mc_result(x)
  x <- finalized(x)
  shape_scores(
    x[["scores"]],
    x[["provenance"]][["pheno_id"]],
    "score",
    x[["provenance"]][[MC_BATCH]],
    long
  )
}

# first n, with a tail count. the plain-text sibling of capped_bullets()
capped <- function(x, n = 10L) {
  paste0(
    paste(utils::head(x, n), collapse = ", "),
    if (length(x) > n) sprintf(" ... and %d more", length(x) - n)
  )
}

# comparison family. integer/double/logical are one, character/factor another,
# and anything else is its own -- so a Date or a list column mismatches for free
type_family <- function(v) {
  if (is.numeric(v) || is.logical(v)) {
    "number"
  } else if (is.character(v) || is.factor(v)) {
    "string"
  } else {
    class(v)[[1L]]
  }
}

# tolerance-based and storage-agnostic within a family. never identical():
# integer-vs-double and factor-vs-character are storage, not disagreement
values_agree <- function(a, b) {
  if (is.numeric(a) || is.logical(a)) {
    a <- as.numeric(a)
    b <- as.numeric(b)
    # absolute and relative together, like every other bound in this package
    same <- abs(a - b) <= 1e-8 * pmax(1, abs(a), abs(b))
  } else {
    same <- as.character(a) == as.character(b)
  }
  # both NA agree. NA against a value is a disagreement, not a gap to be filled
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & same)
}

# how a shared column disagrees, or NULL when it does not
column_conflict <- function(a, b, nm) {
  if (type_family(a) != type_family(b)) {
    return(sprintf(
      "  %s: %s on the record, %s in `data`",
      nm,
      class(a)[[1L]],
      class(b)[[1L]]
    ))
  }
  n_off <- sum(!values_agree(a, b))
  if (n_off == 0L) {
    return(NULL)
  }
  sprintf("  %s: %d sample(s) disagree", nm, n_off)
}

# data adds a column. it never changes one -- re-score if a covariate moved
merge_accel_data <- function(pheno, data, pheno_id) {
  if (is.null(data)) {
    return(pheno)
  }
  checkmate::assert_data_frame(data, min.rows = 1)
  if (MC_BATCH %in% names(data)) {
    stop(
      sprintf(
        "`%s` is reserved for the run's batch label; rename your column.",
        MC_BATCH
      ),
      call. = FALSE
    )
  }
  if (!pheno_id %in% names(data)) {
    stop(
      sprintf("`data` needs the id column `%s`.", pheno_id),
      call. = FALSE
    )
  }
  # the join is a left join, so the only thing that can make it ill-defined is
  # a duplicated key on the right -- match() would silently take the first
  ids <- as.character(data[[pheno_id]])
  dup <- unique(ids[duplicated(ids)])
  if (length(dup)) {
    stop(
      sprintf(
        "`data` has %d duplicate id(s) in `%s`: %s.",
        length(dup),
        pheno_id,
        capped(dup)
      ),
      call. = FALSE
    )
  }

  idx <- match(as.character(pheno[[pheno_id]]), ids)
  # data says nothing about a sample it does not carry
  seen <- !is.na(idx)
  shared <- setdiff(intersect(names(pheno), names(data)), pheno_id)
  bad <- unlist(lapply(shared, function(cl) {
    column_conflict(pheno[[cl]][seen], data[[cl]][idx[seen]], cl)
  }))
  if (length(bad)) {
    stop(
      paste(
        c(
          "`data` changes columns the scores were computed against:",
          bad,
          paste0(
            "Re-run calc_clocks() with the pheno you want. `data` may add a ",
            "column, never change one."
          )
        ),
        collapse = "\n"
      ),
      call. = FALSE
    )
  }

  # an unmatched sample is a legal left join, but a silent all-NA covariate is
  # how a mistyped id column looks downstream, so say it here
  if (any(!seen)) {
    warning(
      sprintf(
        "`data` has no row for %d sample(s): %s. Added columns are NA there.",
        sum(!seen),
        capped(as.character(pheno[[pheno_id]])[!seen])
      ),
      call. = FALSE
    )
  }

  for (cl in setdiff(names(data), names(pheno))) {
    pheno[[cl]] <- data[[cl]][idx]
  }
  pheno
}

# the model's rhs, carried as language so terms like I(Age^2) survive
accel_formula <- function(formula, type) {
  if (is.null(formula)) {
    # accel with no formula is the classic age regression. diff has no fit
    if (type == "diff") {
      return(NULL)
    }
    formula <- stats::as.formula("~ Age")
  }
  if (!inherits(formula, "formula") || length(formula) != 2L) {
    stop(
      "`formula` must be one-sided, e.g. `~ Age + Female`.",
      call. = FALSE
    )
  }
  formula
}

# residuals of every column sharing one design, or NULL when n <= p leaves
# nothing to residualize. the rhs is one-sided, so it is the design directly
pattern_residuals <- function(y, ph, formula) {
  # na.fail is an assertion: the drops below already happened
  mfr <- stats::model.frame(formula, data = ph, na.action = stats::na.fail)
  qrx <- qr(stats::model.matrix(formula, mfr))
  if (nrow(y) - qrx[["rank"]] < 1L) {
    return(NULL)
  }
  qr.resid(qrx, y)
}

# residualize every column on one rhs, onto the full grid. one QR per distinct
# missingness pattern -- which is one QR for the whole matrix when no score is NA
residualize <- function(resp, ph, vars, formula) {
  # scoped to the formula's variables: an NA in Female must not drop a row
  # from a ~ Age call
  keep <- rep(TRUE, nrow(ph))
  for (v in vars) {
    keep <- keep & !is.na(ph[[v]])
  }

  out <- resp
  out[] <- NA_real_
  # group on the rows a column actually fits over, not on its raw NA pattern:
  # two clocks whose NAs differ only where keep is already FALSE share a design
  okm <- !is.na(resp) & keep
  patt <- apply(okm, 2L, function(v) paste0(which(!v), collapse = ","))
  dead <- character(0)
  for (cols in split(seq_len(ncol(resp)), patt)) {
    # every column in the group shares a row set, so the first speaks for all
    ok <- okm[, cols[[1L]]]
    got <- pattern_residuals(
      resp[ok, cols, drop = FALSE],
      ph[ok, , drop = FALSE],
      formula
    )
    if (is.null(got)) {
      dead <- c(dead, colnames(resp)[cols])
      next
    }
    out[ok, cols] <- got
  }
  if (length(dead)) {
    warning(
      sprintf(
        "%d clock(s) had too few complete samples to fit: %s. They are all NA.",
        length(dead),
        capped(dead)
      ),
      call. = FALSE
    )
  }
  out
}

# multi-batch fill can offset residuals. say so unless mc_batch_id is on the rhs
say_fill_batch <- function(x, rhs_vars) {
  per_clock <- x[["coverage"]][["per_clock"]]
  if (length(per_clock) < 2L || MC_BATCH %in% rhs_vars) {
    return(invisible(NULL))
  }
  # only the partial (cohort-mean) fill is batch-dependent. imputed_full takes
  # the clock's vendored reference, which is the same constant everywhere
  filled <- vapply(
    per_clock,
    function(recs) {
      any(vapply(
        recs,
        function(r) {
          !is.null(r) && as.integer(r[["score_imputed_partial"]]) > 0L
        },
        logical(1L)
      ))
    },
    logical(1L)
  )
  if (!any(filled)) {
    return(invisible(NULL))
  }
  cli::cli_inform(c(
    "!" = "This record has {length(per_clock)} batches and some CpGs were
           cohort-mean filled, which is done within a batch.",
    "i" = "Add {.field {MC_BATCH}} to your {.arg formula} to regress that
           offset out."
  ))
  invisible(NULL)
}

# age acceleration, as a frame. type sets the response, formula sets the rhs
#' @export
clocks_accel <- function(
  x,
  formula = NULL,
  type = c("accel", "diff"),
  data = NULL,
  long = TRUE
) {
  check_mc_result(x)
  type <- match.arg(type)
  formula <- accel_formula(formula, type)
  x <- finalized(x)

  pheno_id <- x[["provenance"]][["pheno_id"]]
  sample_id <- x[["provenance"]][["sample_id"]]
  # the rhs governs the NA drop. diff reads Age on top of it, in the response
  rhs_vars <- if (is.null(formula)) character(0) else all.vars(formula)
  vars <- unique(c(if (type == "diff") "Age", rhs_vars))
  say_fill_batch(x, rhs_vars)

  pheno <- merge_accel_data(x[["pheno"]], data, pheno_id)
  # the record's own label, offered to the formula and reserved against data
  pheno[[MC_BATCH]] <- x[["provenance"]][[MC_BATCH]][
    match(pheno[[pheno_id]], sample_id)
  ]
  # $pheno carries only what the scoring itself used, so anything else belongs
  # in data = -- check_pheno's hint would send them back to re-score for nothing
  need <- setdiff(vars, names(pheno))
  if (length(need)) {
    stop(
      sprintf(
        "The record's pheno has no column(s) %s. Pass them via `data`.",
        paste(need, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  check_pheno(pheno, ID = pheno_id, extra_columns = vars, sample_id = sample_id)
  # by id, never by row order
  ph <- pheno[match(sample_id, pheno[[pheno_id]]), , drop = FALSE]

  resp <- x[["scores"]]
  if (type == "diff") {
    resp <- resp - ph[["Age"]]
  }
  # diff with no formula is the difference itself -- no fit, no drop
  out <- if (is.null(formula)) {
    resp
  } else {
    residualize(resp, ph, rhs_vars, formula)
  }

  shape_scores(out, pheno_id, "accel", x[["provenance"]][[MC_BATCH]], long)
}
