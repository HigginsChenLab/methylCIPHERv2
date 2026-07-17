# Pure namespace resolution: user tokens -> catalog clock_ids. No math, no ordering, no
# cross-clock dependencies -- FitAge-needs-GrimAge lives INSIDE the pack orchestrator, not here.
# Accepts, in any mix: the alias "all" (every clock), a group_id (expanded to its members), or a
# bare clock_id (kept as-is). Returns unique clock_ids in first-seen order after expansion.
# e.g. resolve_clocks("Bohlin") -> c("Bohlin251", "Bohlin96").
# (roxygen comes later, once the API stabilizes; man/resolve_clocks.Rd is stale until then.)
resolve_clocks <- function(clocks) {
  members <- split(mc_index$clock_id, mc_index$group_id)

  lookup <- c(
    members,
    stats::setNames(as.list(mc_index$clock_id), mc_index$clock_id),
    list(all = mc_index$clock_id)
  )

  bad <- setdiff(clocks, names(lookup))
  if (length(bad)) {
    stop("Unknown clock token(s): ", paste(bad, collapse = ", "), call. = FALSE)
  }

  out <- unlist(lookup[clocks], use.names = FALSE)
  out[!duplicated(out)]
}

# Universal DNAm invariants only -- runs ONCE, no clock knowledge. Clock-specific DNAm
# preconditions (full-panel adequacy) live in check_DNAm_extra() below, not here. Identity-less
# DNAm is handled UPSTREAM inline in calc_clocks() (rownames absent -> positional sample1..N under
# allow_positional_ids, else hard error); by the time this runs rownames are non-NULL (real, or
# positional), so the unique-id invariant below is unconditional.
check_DNAm <- function(DNAm) {
  checkmate::assert_matrix(
    DNAm,
    mode = "double",
    min.rows = 1,
    min.cols = 1
  )
  # CpG names must be the column names.
  checkmate::assert_character(colnames(DNAm), unique = TRUE, null.ok = FALSE)
  # rownames are the canonical sample_id: non-NULL and unique. Identity-less DNAm is resolved
  # upstream inline in calc_clocks() (real ids, or opt-in positional sample1..N), so here the
  # invariant is unconditional. Positional ids satisfy uniqueness but are flagged
  # provenance$positional_ids so cbind() refuses them -- the footgun stays closed at the bind step.
  checkmate::assert_character(rownames(DNAm), unique = TRUE, null.ok = FALSE)
  if (nrow(DNAm) > ncol(DNAm)) {
    warning("DNAm should be formatted as samples * CpG. Currently DNAm has more rows (samples) than columns (CpGs), which is highly unlikely. Pass the full DNAm matrix without pre-subsetting to `calc_clock()`.")
  }
  if (!any(grepl("^cg", colnames(DNAm)))) {
    warning("It looks like you may need to format DNAm using t(DNAm) to get samples as rows!")
  }
  # Missingness is not handled here. It is handled in the imputation step.
  invisible(TRUE)
}

# Precondition of the `sample_scale` pre-transform -- NOT a universal or front-end check. Zhang2019
# is the only clock whose recipe carries `sample_scale` (per-sample row moments across the WHOLE
# CpG panel), so its scores drift when DNAm is pre-subsetted. Rather than a generic catalog-driven
# warning, this is HARD-CODED to Zhang2019 for now (the sole `sample_scale` clock) and emits an
# informational message(), not a warning -- the moments were originally computed over all CpGs, but
# a large-enough subset is usually sufficient. `DNAm` is unused for now (kept in the signature so
# the call site is stable). Intended direction: retire clock_needs_full_panel() and this whole
# check, folding the notice into the sample_scale transform once that module exists (detail-plan
# §2.4). The `"sample_scale" %in% batch_ops` catalog marker + clock_needs_full_panel() accessor
# stay for now. NB: this is the ONLY norm-adjacent thing the package executes -- array
# normalization (BMIQ/noob/quantile) is upstream and never run here.
check_DNAm_extra <- function(DNAm, clock_ids) {
  if ("Zhang2019" %in% clock_ids) {
    message(
      "Zhang2019's original code computes per-sample moments over all CpGs. ",
      "A large-enough subset of CpGs is usually sufficient."
    )
  }
  invisible(TRUE)
}

# Structure/dtype validation only; identity alignment is resolve_pheno()'s job. `positional` mirrors
# the DNAm mode: in id mode the ID column is the join key (must exist, be unique, non-missing); in
# positional mode there is no id join (row-order), so those ID asserts are skipped -- pheno need not
# even carry the id column. Covariate dtype checks (Age/Female) run in BOTH modes.
check_pheno <- function(pheno, ID = NULL, extra_columns = NULL, positional = FALSE) {
  if (is.null(pheno)) {
    return(invisible(TRUE))
  }
  checkmate::assert_data_frame(pheno, min.rows = 1)
  if (!positional) {
    # pheno_id always has a default, so ID is always a string; when pheno is supplied
    # the id column must exist and be a unique, non-missing key. No unique(pheno) dedup
    # -- duplicate ids are the caller's error.
    checkmate::assert_string(ID, null.ok = FALSE)
    checkmate::assert_choice(ID, names(pheno))
    checkmate::assert_character(
      pheno[[ID]],
      any.missing = FALSE,
      unique = TRUE,
      null.ok = FALSE
    )
  }
  if ("Female" %in% extra_columns) {
    checkmate::assert_integerish(
      pheno[["Female"]],
      lower = 0,
      upper = 1,
      null.ok = FALSE,
      any.missing = TRUE
    )
  }
  if ("Age" %in% extra_columns) {
    checkmate::assert_numeric(
      pheno[["Age"]],
      finite = TRUE,
      null.ok = FALSE,
      any.missing = TRUE
    )
  }
  invisible(TRUE)
}

# Aligns pheno onto the resolved sample_id and returns it in sample_id (= rownames(DNAm)) order,
# or NULL when pheno is NULL. DNAm's rownames are already resolved (real or positional) by the time
# this runs. Two modes, chosen by `positional_ids`:
#   - id join (positional_ids = FALSE): pheno[[pheno_id]] is the key. Every rownames(DNAm) must be
#     present in it (a SUPERSET pheno is fine -- extra cohort rows are dropped); else throw naming
#     the missing ids. Subset to the requested ids and reorder to rownames(DNAm) order.
#   - row-order join (positional_ids = TRUE): no real id exists, so row i of pheno IS sample i.
#     Requires nrow(pheno) == nrow(DNAm) EXACTLY -- a taller pheno is ambiguous (which rows?), a
#     shorter one is short. pheno is taken in given order; the id column is OVERWRITTEN with the
#     positional sample_id (any real ids the caller left there are discarded -- unused for alignment).
# Post-condition (both modes): returned pheno has nrow(DNAm) rows in sample_id order, with
# pheno[[pheno_id]] == rownames(pheno) == sample_id. check_pheno() validated dtypes first; this is
# identity alignment only. The record stays scores-only -- this aligned pheno feeds
# covariate-needing scorers, it is not appended.
resolve_pheno <- function(DNAm, pheno, pheno_id, positional_ids) {
  if (is.null(pheno)) {
    return(NULL)
  }
  sample_id <- rownames(DNAm)

  if (positional_ids) {
    if (nrow(pheno) != nrow(DNAm)) {
      stop(
        "DNAm has no rownames, so pheno is aligned by row order and must have exactly ",
        nrow(DNAm), " row(s) to match DNAm (got ", nrow(pheno), "). ",
        "Give DNAm rownames to align pheno by id instead.",
        call. = FALSE
      )
    }
    # No id to join on -- align by row order, then OVERWRITE the id column with the positional
    # sample_id so the returned pheno is self-consistent (pheno[[pheno_id]] == rownames == sample_id),
    # the same post-condition id mode reaches for free. Any real ids the caller left in that column
    # are discarded -- they were never used for alignment. (pheno_id must be a column name; falls back
    # to "sample_id" if calc_clocks passed none -- give it a default per detail-plan §5.1.)
    pheno[[pheno_id]] <- sample_id
    return(pheno)
  }
  missing <- setdiff(sample_id, pheno[[pheno_id]])
  if (length(missing)) {
    stop(
      "pheno is missing ", length(missing), " sample id(s) present in rownames(DNAm): ",
      paste(utils::head(missing, 10L), collapse = ", "),
      if (length(missing) > 10L) ", ..." else "",
      call. = FALSE
    )
  }
  pheno <- pheno[match(sample_id, pheno[[pheno_id]]), , drop = FALSE]
  pheno
}
