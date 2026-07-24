# Pure formatters over a finished record's $coverage. They read the hoisted
# structure and never re-touch beta or recompute a ratio: per-sample coverage is
# always row_coverage() (R/resolve_inputs.R), the single source the
# min_row_coverage warning also uses, so a table and its warning cannot disagree.

check_mc_result <- function(x, arg = "x") {
  if (!inherits(x, "mc_result")) {
    cli::cli_abort(
      "{.arg {arg}} must be an {.cls mc_result} from {.fn calc_clocks}.",
      call = NULL
    )
  }
  invisible(x)
}

# a returned clock's per-sample miss vector from the (finished) matrix, or NULL
# when it has no such panel column
score_miss_vec <- function(x, id) {
  m <- x[["coverage"]][["sample_miss"]][["score"]]
  if (id %in% colnames(m)) m[, id] else NULL
}
norm_miss_vec <- function(x, id) {
  m <- x[["coverage"]][["sample_miss"]][["norm"]]
  if (!is.null(m) && id %in% colnames(m)) m[, id] else NULL
}

# per-clock aggregate: one row per clock COMPUTED (returned columns, dependency
# columns, and routing_target members kept for coverage). A sex-routed alias has
# a NULL record, so its panel fields are NA and only its member rows carry the
# per-sex denominators. `role` splits returned score columns from routing targets.
#' @export
clocks_coverage <- function(x) {
  check_mc_result(x)
  per_clock <- x[["coverage"]][["per_clock"]]
  returned <- x[["provenance"]][["clocks"]]
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
    stringsAsFactors = FALSE,
    row.names = NULL
  )
  # absent-probe list stays a list-column so the full account survives
  out[["missing_cpgs"]] <- unname(lapply(
    per_clock,
    function(r) if (is.null(r)) character(0) else r[["missing_cpgs"]]
  ))
  out
}

# one panel's per-sample rows for a non-alias returned clock. `coverage` is the
# ratio; for the row-gate panel it IS row_coverage() so the table and warning
# agree, for the other panel it is the same (present - miss) / needed formula.
panel_rows <- function(id, panel, present, needed, miss, coverage, sample_id) {
  data.frame(
    id = sample_id,
    clock_id = id,
    panel = panel,
    n_observed = as.integer(present - miss),
    n_needed = as.integer(needed),
    coverage = coverage,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

# a returned non-alias clock: always a score row, plus a norm row when it
# normalizes. The row-gate panel's coverage comes from row_coverage().
clock_sample_rows <- function(x, id, sample_id) {
  rec <- x[["coverage"]][["per_clock"]][[id]]
  sm <- score_miss_vec(x, id)
  nm <- norm_miss_vec(x, id)
  gate <- row_coverage(rec, sm, nm)

  rows <- list()
  # score panel (gate iff the clock does not normalize)
  score_cov <- if (isTRUE(rec[["normalizes"]])) {
    (rec[["score_present"]] - sm) / rec[["score_needed"]]
  } else {
    gate[["cov"]]
  }
  rows[["score"]] <- panel_rows(
    id,
    "score",
    rec[["score_present"]],
    rec[["score_needed"]],
    sm,
    score_cov,
    sample_id
  )
  # norm panel (the gate) only when the clock normalizes
  if (isTRUE(rec[["normalizes"]])) {
    rows[["norm"]] <- panel_rows(
      id,
      "norm",
      rec[["norm_present"]],
      rec[["norm_needed"]],
      nm,
      gate[["cov"]],
      sample_id
    )
  }
  do.call(rbind, rows)
}

# a sex-routed alias: NULL record, so each sample's denominators come from the
# member that scored it (routed by pheno$Female, the same split the score used).
# The alias's stitched miss column is each row's own member's raw count, so
# row_coverage() over the masked member record reproduces that member's ratio.
alias_sample_rows <- function(x, alias, sample_id) {
  route <- clock_routing(alias)
  pheno_id <- x[["provenance"]][["pheno_id"]]
  female <- rep(NA_integer_, length(sample_id))
  pheno <- x[["pheno"]]
  if (!is.null(pheno) && "Female" %in% names(pheno)) {
    idx <- match(sample_id, pheno[[pheno_id]])
    female <- as.integer(pheno[["Female"]])[idx]
  }
  miss <- score_miss_vec(x, alias)

  n_observed <- rep(NA_integer_, length(sample_id))
  n_needed <- rep(NA_integer_, length(sample_id))
  coverage <- rep(NA_real_, length(sample_id))

  for (sx in c("female", "male")) {
    member <- as.character(route[[sx]])
    rec <- x[["coverage"]][["per_clock"]][[member]]
    if (is.null(rec)) {
      next
    }
    applies <- if (identical(sx, "female")) female == 1 else female == 0
    applies[is.na(applies)] <- FALSE
    if (!any(applies)) {
      next
    }
    member_miss <- rep(NA_integer_, length(sample_id))
    member_miss[applies] <- miss[applies]
    rc <- row_coverage(rec, member_miss, NULL)
    coverage[applies] <- rc[["cov"]][applies]
    n_needed[applies] <- rc[["needed"]]
    n_observed[applies] <- as.integer(rec[["score_present"]] - member_miss[applies])
  }

  data.frame(
    id = sample_id,
    clock_id = alias,
    panel = "score",
    n_observed = n_observed,
    n_needed = n_needed,
    coverage = coverage,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

# per-(sample, clock, panel) coverage: one row per returned score column and
# panel. A normalizing clock (DunedinPACE) contributes a score row and a norm
# row with different denominators; everything else just a score row. `coverage`
# is n_observed / n_needed, literally row_coverage() on the row-gate panel.
#' @export
samples_coverage <- function(x) {
  check_mc_result(x)
  sample_id <- x[["provenance"]][["sample_id"]]
  returned <- x[["provenance"]][["clocks"]]
  per_clock <- x[["coverage"]][["per_clock"]]

  parts <- lapply(returned, function(id) {
    if (is.null(per_clock[[id]])) {
      alias_sample_rows(x, id, sample_id)
    } else {
      clock_sample_rows(x, id, sample_id)
    }
  })
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}
