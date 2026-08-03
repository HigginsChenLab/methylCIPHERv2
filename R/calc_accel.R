MC_ACCEL <- "accel_id"

finalized <- function(x) {
  pending <- x[["provenance"]][["pending"]]
  if (length(pending) && length(x[["coverage"]][["per_clock"]]) > 1L) {
    x <- refinalize_clocks(x)
  }
  x
}

shape_scores <- function(m, id_col, value_col, batch, long, label = NULL) {
  if (!long) {
    ids <- stats::setNames(
      data.frame(rownames(m), stringsAsFactors = FALSE),
      id_col
    )
    out <- cbind(ids, as.data.frame(m, optional = TRUE))
    if (!is.null(label)) {
      names(out) <- c(id_col, paste0(colnames(m), "_", label))
    }
    out[[MC_BATCH]] <- batch
    rownames(out) <- NULL
    return(drop_single_batch(out, batch))
  }
  out <- data.frame(
    id = rep(rownames(m), times = ncol(m)),
    clock_id = rep(colnames(m), each = nrow(m)),
    value = as.vector(m),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  names(out) <- c(id_col, "clock_id", value_col)
  if (is_multi_batch(batch)) {
    out[[MC_BATCH]] <- rep(batch, times = ncol(m))
  }
  if (!is.null(label)) {
    out[[MC_ACCEL]] <- label
    keep <- setdiff(names(out), MC_ACCEL)
    out <- out[append(keep, MC_ACCEL, after = match("clock_id", keep))]
  }
  drop_single_batch(out, batch)
}

#' @export
as.data.frame.mc_result <- function(
  x,
  row.names = NULL,
  optional = FALSE,
  ...,
  long = TRUE
) {
  check_mc_result(x)
  checkmate::assert_flag(long)
  x <- finalized(x)
  shape_scores(
    x[["scores"]],
    x[["provenance"]][["pheno_id"]],
    "score",
    x[["provenance"]][[MC_BATCH]],
    long
  )
}

type_family <- function(v) {
  if (is.numeric(v) || is.logical(v)) {
    "number"
  } else if (is.character(v) || is.factor(v)) {
    "string"
  } else {
    class(v)[[1L]]
  }
}

values_agree <- function(a, b) {
  if (is.numeric(a) || is.logical(a)) {
    a <- as.numeric(a)
    b <- as.numeric(b)
    same <- abs(a - b) <= 1e-8 * pmax(1, abs(a), abs(b))
  } else {
    same <- as.character(a) == as.character(b)
  }
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & same)
}

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

merge_accel_data <- function(pheno, data, pheno_id) {
  if (is.null(data)) {
    return(pheno)
  }
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
    # accel with no formula is the classic age regression.
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

accel_label <- function(formula, type) {
  rhs <- if (is.null(formula)) {
    NULL
  } else {
    attr(stats::terms(formula), "term.labels")
  }
  paste(c(rhs, type), collapse = "_")
}

pattern_residuals <- function(y, ph, formula) {
  mfr <- stats::model.frame(formula, data = ph, na.action = stats::na.fail)
  qrx <- qr(stats::model.matrix(formula, mfr))
  if (nrow(y) - qrx[["rank"]] < 1L) {
    return(NULL)
  }
  qr.resid(qrx, y)
}

residualize <- function(resp, ph, vars, formula) {
  keep <- rep(TRUE, nrow(ph))
  for (v in vars) {
    keep <- keep & !is.na(ph[[v]])
  }

  out <- resp
  out[] <- NA_real_
  okm <- !is.na(resp) & keep
  patt <- apply(okm, 2L, function(v) paste0(which(!v), collapse = ","))
  dead <- character(0)
  for (cols in split(seq_len(ncol(resp)), patt)) {
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

say_fill_batch <- function(x, rhs_vars) {
  per_clock <- x[["coverage"]][["per_clock"]]
  if (length(per_clock) < 2L || MC_BATCH %in% rhs_vars) {
    return(invisible(NULL))
  }
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

#' @export
calc_accel <- function(
  x,
  formula = NULL,
  type = c("accel", "diff"),
  data = NULL,
  long = TRUE
) {
  check_mc_result(x)
  checkmate::assert_data_frame(data, min.rows = 1, null.ok = TRUE)
  checkmate::assert_flag(long)
  type <- match.arg(type)
  formula <- accel_formula(formula, type)
  x <- finalized(x)

  pheno_id <- x[["provenance"]][["pheno_id"]]
  sample_id <- x[["provenance"]][["sample_id"]]
  rhs_vars <- if (is.null(formula)) character(0) else all.vars(formula)
  vars <- unique(c(if (type == "diff") "Age", rhs_vars))
  say_fill_batch(x, rhs_vars)

  pheno <- merge_accel_data(x[["pheno"]], data, pheno_id)
  pheno[[MC_BATCH]] <- x[["provenance"]][[MC_BATCH]][
    match(pheno[[pheno_id]], sample_id)
  ]
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

  shape_scores(
    out,
    pheno_id,
    "accel",
    x[["provenance"]][[MC_BATCH]],
    long,
    accel_label(formula, type)
  )
}
