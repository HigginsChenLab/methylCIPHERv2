# Which scorer a clock routes to, from (external, weights_format, computation_type, group_id).
# Pure catalog lookup -> a closed tag set consumed by the dispatch switch in calc_clocks().
# `component_matrices + linear` fans out to three scorers by group_id (GrimAge surrogates ->
# linear_score, FitAge members -> score_fitage_member), so group_id is a real dispatch axis.
# Anything unrecognized -> "unsupported", which the switch turns into an informative error.
# Worth a structural test: every catalog clock should map to a known tag (implemented or a
# deliberate "unsupported"), so a new (weights_format, computation_type) combo can't fall
# through silently.
score_type <- function(p) {
  if (clock_is_external(p)) {
    return("unsupported")
  }
  ct <- clock_type(p)
  wf <- clock_weights_format(p)
  if (wf == "cpg_coefficient" && ct %in% c("linear", "linear_transformed")) {
    return("linear")
  }
  switch(
    clock_group_id(p),
    GrimAge = switch(
      ct,
      linear = "linear",
      linear_transformed = "grimage",
      "unsupported"
    ),
    DNAmFitAge = switch(
      ct,
      linear = "fitage_member",
      linear_transformed = "fitage_composite",
      "unsupported"
    ),
    # PhysAge surrogates are cpg_coefficient/linear (already "linear" above); only the
    # component_matrices composites reach here.
    PhysAge = switch(ct, linear_transformed = "physage", "unsupported"),
    "unsupported"
  )
}

# Public scorer: resolve clocks, prepare once, score each unit, assemble a methylCIPHER record.
# Legacy per-clock calc* may wrap this; they are not the engine.
#
# @param DNAm    n x p numeric matrix, samples x CpGs. rownames = sample_id; rowname-less DNAm
#                gets positional ids sample1..N unless allow_positional_ids is FALSE.
# @param clocks  character tokens: "all", group_ids, and/or clock_ids.
# @param pheno   optional covariate table (Age, Female); aligned onto sample_id, not appended.
# @param pheno_id column in `pheno` holding the sample id. Defaults to "ID".
# @param allow_positional_ids permit scoring rowname-less DNAm by row order (default TRUE).
# @param min_coverage warn when a clock has fewer than this fraction of scoring CpGs (default 0.8).
# @return a "methylCIPHER" S3 record: list(scores, coverage, provenance).
calc_clocks <- function(
  DNAm,
  clocks,
  pheno = NULL,
  pheno_id = "ID",
  allow_positional_ids = TRUE,
  min_coverage = 0.8,
  ...
) {
  # user tokens -> requested clock_ids; then transitive deps, deps-first order.
  # Auto-added deps are returned as columns too (with their own coverage).
  clock_ids <- resolve_clocks(clocks)
  clock_sequence <- resolve_clocks_sequence(clock_ids)
  output_ids <- c(clock_ids, setdiff(clock_sequence, clock_ids))
  check_DNAm(DNAm)

  # Identity before check_DNAm (rownames must be non-NULL by then). Positional records
  # are flagged so cbind can refuse them.
  positional_ids <- is.null(rownames(DNAm))
  if (positional_ids) {
    if (!allow_positional_ids) {
      stop(
        "DNAm has no rownames. Set them, or pass ",
        "`allow_positional_ids = TRUE` to score with positional ids (sample1..sampleN).",
        call. = FALSE
      )
    }
    rownames(DNAm) <- paste0("sample", seq_len(nrow(DNAm)))
  }
  sample_id <- rownames(DNAm)
  resolve_DNAm_extra(clock_sequence)

  # covariate union over the full compute plan (requested + deps)
  extra_columns <- unique(unlist(lapply(
    clock_sequence,
    clock_covariates_required
  )))
  if (length(extra_columns) && is.null(pheno)) {
    stop(
      "The requested clock(s) need covariate(s) ",
      paste(extra_columns, collapse = ", "),
      ", but `pheno` is NULL. Supply a pheno table carrying these columns.",
      call. = FALSE
    )
  }
  check_pheno(
    pheno,
    ID = pheno_id,
    extra_columns = extra_columns,
    positional = positional_ids
  )
  pheno <- resolve_pheno(DNAm, pheno, pheno_id, positional_ids)

  # missingness: needed_union bounds the scan; order is scan -> resolve_cpgs -> cache
  needed_union <- needed_cpgs_union(clock_sequence)
  mna <- scan_missing_cpgs(DNAm, needed_union)
  cpg_list <- resolve_cpgs(mna$usable_cols, clock_sequence)
  warn_low_coverage(cpg_list, min_coverage)
  partial_cache <- build_partial_cache(
    DNAm,
    intersect(cpg_list$present_needed_union, mna$partial_na_cols)
  )

  # Dispatch on score_type(): a closed tag set from (external, weights_format,
  # computation_type, group_id). Deps precede composites in clock_sequence, so the
  # surrogates/members a pack reads are already in `results` by the time it runs.
  results <- vector("list", length(clock_sequence))
  names(results) <- clock_sequence
  for (p in clock_sequence) {
    cpgs <- cpg_list$per_clock[[p]]
    results[[p]] <- switch(
      score_type(p),
      linear = linear_score(cpgs, DNAm, partial_cache, pheno),
      grimage = score_grimage(
        p,
        cpgs,
        results,
        mna$usable_cols,
        DNAm,
        partial_cache,
        pheno
      ),
      fitage_member = score_fitage_member(p, cpgs, DNAm, partial_cache, pheno),
      fitage_composite = score_fitage_composite(
        p,
        cpgs,
        results,
        DNAm,
        partial_cache,
        pheno
      ),
      physage = score_physage(p, cpgs, DNAm, partial_cache),
      stop(
        "calc_clocks(): clock '",
        p,
        "' (weights_format '",
        clock_weights_format(p),
        "', computation_type '",
        clock_type(p),
        "') is not implemented yet -- only cpg_coefficient/{linear,linear_transformed}, ",
        "the GrimAge pack, and the DNAmFitAge pack are supported so far.",
        call. = FALSE
      )
    )
  }

  # Batch-dependent clocks (PhysAge cohort_zscore, Zhang sample_scale) depend on which samples
  # were scored together, so freeze a batch id over the scoring cohort. It survives subsetting so
  # cbind can later refuse binding a subset against a fresh scoring of the same ids (detail-plan
  # sec 6 / sec 7.1). NULL when no returned clock is batch-dependent.
  batch_set_id <- if (any(vapply(output_ids, clock_batch_dependent, logical(1)))) {
    digest::digest(sort(sample_id))
  } else {
    NULL
  }

  construct_methylCIPHER(
    results[output_ids],
    output_ids,
    clock_ids,
    sample_id,
    positional_ids,
    batch_set_id
  )
}

# Stack scorer outputs into the methylCIPHER record: scores, coverage, provenance.
# Pure reshape -- never re-touches DNAm.
construct_methylCIPHER <- function(
  results,
  output_ids,
  requested_ids,
  sample_id,
  positional_ids,
  batch_set_id = NULL
) {
  scores <- do.call(cbind, lapply(results, function(r) r$score))
  dimnames(scores) <- list(sample_id, output_ids)

  per_clock <- lapply(results, function(r) r$coverage)
  names(per_clock) <- output_ids
  sample_miss <- do.call(cbind, lapply(results, function(r) r$sample_miss))
  dimnames(sample_miss) <- list(sample_id, output_ids)

  # covariates actually used = names required by returned clocks (not coef maps alone)
  covariates_used <- unique(unlist(
    lapply(output_ids, clock_covariates_required),
    use.names = FALSE
  ))
  if (is.null(covariates_used)) {
    covariates_used <- character(0)
  }

  structure(
    list(
      scores = scores,
      coverage = list(per_clock = per_clock, sample_miss = sample_miss),
      provenance = list(
        sample_id = sample_id,
        positional_ids = positional_ids,
        clocks = output_ids,
        requested = requested_ids,
        dependencies = setdiff(output_ids, requested_ids),
        covariates_used = covariates_used,
        batch_set_id = batch_set_id
      )
    ),
    class = "methylCIPHER_result"
  )
}
