# Map catalog fields to a closed scorer tag for calc_clocks() dispatch.
# group_id matters for component_matrices (GrimAge/FitAge/PhysAge fan-out).
score_type <- function(p) {
  # External cpg_coefficient clocks (PCClocks, PCBrainAge) score on the shared linear
  # engine from the loaded pack. SystemsAge organ sub-clocks are also plain linear
  # (coef from pack$organs); its two component_matrices composites (Age_prediction,
  # SystemsAge) route to the family orchestrator.
  if (clock_is_external(p) && identical(clock_group_id(p), "SystemsAge")) {
    if (identical(clock_weights_format(p), "cpg_coefficient")) {
      return("linear")
    }
    return("systemsage")
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
    # PhysAge surrogates are already "linear" above; only composites reach here.
    PhysAge = switch(ct, linear_transformed = "physage", "unsupported"),
    "unsupported"
  )
}

# Public scorer: resolve clocks, prepare once, score each unit, assemble a record.
# @param DNAm n x p matrix (samples x CpGs); rownames = sample_id.
# @param clocks "all", group_ids, and/or clock_ids.
# @param pheno optional covariates (Age, Female), aligned onto sample_id.
# @param pheno_id sample-id column in pheno (default "ID").
# @param allow_positional_ids score rowname-less DNAm by row order (default TRUE).
# @param min_coverage warn below this fraction of scoring CpGs (default 0.8).
# @param assets external-pack source: NULL = default cache (consent download of missing
#   packs); a cache-dir path or loaded pack(s) = closed set, no download (see load_mc_assets).
# @param ask prompt before downloading missing external packs (default TRUE).
# @return "methylCIPHER" S3 record: list(scores, coverage, provenance).
calc_clocks <- function(
  DNAm,
  clocks,
  pheno = NULL,
  pheno_id = "ID",
  allow_positional_ids = TRUE,
  min_coverage = 0.8,
  assets = NULL,
  ask = TRUE,
  ...
) {
  # Requested clocks + transitive deps (deps first). Auto-deps are returned too.
  clock_ids <- resolve_clocks(clocks)
  clock_sequence <- resolve_clocks_sequence(clock_ids)
  output_ids <- c(clock_ids, setdiff(clock_sequence, clock_ids))
  check_DNAm(DNAm)

  # Stamp positional sample ids when rownames are missing.
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

  # Scan missingness, resolve present/absent CpGs, build partial-NA cache.
  needed_union <- needed_cpgs_union(clock_sequence)
  mna <- scan_missing_cpgs(DNAm, needed_union)
  cpg_list <- resolve_cpgs(mna$usable_cols, clock_sequence)
  warn_low_coverage(cpg_list, min_coverage)
  partial_cache <- build_partial_cache(
    DNAm,
    intersect(cpg_list$present_needed_union, mna$partial_na_cols)
  )

  # External packs needed by the plan, resolved once (sole download/consent site) and
  # threaded into the pure scoring loop. Only groups whose clocks route to a pack-consuming
  # scorer are fetched, so a still-unimplemented external clock (e.g. SystemsAge) never
  # triggers a download that would only be followed by an "unsupported" error.
  pack_groups <- unique(unlist(lapply(clock_sequence, function(p) {
    if (clock_is_external(p) && !identical(score_type(p), "unsupported")) {
      clock_group_id(p)
    } else {
      NULL
    }
  })))
  packs <- load_mc_assets(pack_groups, assets, ask)

  # Deps precede composites so pack scorers find upstream results.
  results <- vector("list", length(clock_sequence))
  names(results) <- clock_sequence

  # External-pack clocks share one CpG panel per group; score each group in a single
  # batched matmul (one subset reused across members) rather than one matmul per clock.
  # Packs are dependency-isolated, so they can be scored apart from the per-clock loop.
  is_pack <- vapply(
    clock_sequence,
    function(p) clock_is_external(p) && !identical(score_type(p), "unsupported"),
    logical(1)
  )
  if (any(is_pack)) {
    pack_ids <- clock_sequence[is_pack]
    pgroups <- vapply(pack_ids, clock_group_id, character(1))
    for (g in unique(pgroups)) {
      grp <- score_pack_group(
        g,
        pack_ids[pgroups == g],
        cpg_list,
        mna$usable_cols,
        DNAm,
        partial_cache,
        pheno,
        packs
      )
      results[names(grp)] <- grp
    }
  }

  # Bundled clocks keep the per-clock engine (deps precede dependents).
  for (p in clock_sequence[!is_pack]) {
    cpgs <- cpg_list$per_clock[[p]]
    results[[p]] <- switch(
      score_type(p),
      linear = linear_score(cpgs, DNAm, partial_cache, pheno, packs),
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
        "the GrimAge / DNAmFitAge / PhysAge / SystemsAge packs are supported so far.",
        call. = FALSE
      )
    )
  }

  # Freeze batch id for cohort/sample-dependent clocks so cbind can refuse mismatched batches.
  batch_set_id <- if (
    any(vapply(output_ids, clock_batch_dependent, logical(1)))
  ) {
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

# Stack scorer outputs into the methylCIPHER record (pure reshape).
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
