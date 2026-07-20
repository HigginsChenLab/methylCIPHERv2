# The one public scorer (detail-plan §1). Resolves clock tokens, prepares inputs ONCE (identity,
# pheno, missingness front end), scores each work unit through a scorer keyed on computation_type,
# and assembles a methylCIPHER record. Legacy per-clock calc* are at most thin wrappers over this;
# they are NOT the engine.
#
# @param DNAm    n x p numeric matrix, samples x CpGs. rownames = sample_id (canonical identity);
#                rowname-less DNAm is stamped positional ids sample1..N unless allow_positional_ids
#                is FALSE (§5.1). colnames = CpG ids.
# @param clocks  character tokens: "all", group_ids, and/or clock_ids (resolve_clocks() precedence).
# @param pheno   optional covariate side-table (Age, Female). Aligned onto sample_id, never appended
#                to the scores (§1.3).
# @param pheno_id column in `pheno` holding the sample id (id-join mode). Defaults to "ID".
# @param allow_positional_ids permit scoring a rowname-less DNAm by row order (default TRUE). Such
#                records are flagged $provenance$positional_ids and refused by cbind (§7.1 gate 0).
# @param min_coverage warn when a clock scores on a smaller fraction of its scoring CpGs than this
#                (default 0.8). Set 0 to silence.
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
  # -- resolve clocks --------------------------------------------------------------------------
  # user tokens -> REQUESTED clock_ids.
  clock_ids <- resolve_clocks(clocks)
  # compute plan: requested + transitive depends_on_clocks, ordered deps-first. Auto-added deps are
  # RETURNED too (not compute-only): they were genuinely computed, and each carries its own coverage
  # row -- silently dropping GrimAgeV1 out of a DNAmFitAge request hides the fact that a composite
  # rested on an input scored from few CpGs. Callers who want only what they asked for subset
  # downstream; $provenance$requested / $dependencies record which is which.
  clock_sequence <- resolve_clocks_sequence(clock_ids)
  # requested columns lead, in request order; auto-added deps follow in compute order.
  output_ids <- c(clock_ids, setdiff(clock_sequence, clock_ids))
  check_DNAm(DNAm) # universal invariants (rownames now non-NULL: real or positional)

  # -- sample identity + DNAm invariants -------------------------------------------------------
  # Identity is settled BEFORE check_DNAm: that check asserts rownames are non-NULL (unconditional),
  # so positional stamping has to run first (see check_DNAm's own header). rownames(DNAm) is the
  # canonical, preferred id; identity-less DNAm is not a hard error by default -- stamp positional
  # ids so row-order workflows can score. The flag flows to provenance and makes cbind refuse the
  # record (footgun closed at the bind step). Capture positional-ness BEFORE stamping.
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
  resolve_DNAm_extra(clock_sequence) # Zhang2019 full-panel notice (side effect only)

  # -- pheno: validate dtypes, then align onto sample_id ---------------------------------------
  # union of covariate names across the compute sequence (requested + auto-added deps).
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

  # -- missingness front end (detail-plan §2.3a) -----------------------------------------------
  # bounded-to-needed-first: needed_union is catalog-only (no DNAm), so it can lead and shrink the
  # numeric scan + set math below to clock width. Order is forced: cache needs resolve_cpgs's present
  # union; resolve_cpgs needs scan's usable_cols.
  needed_union <- needed_cpgs_union(clock_sequence)
  mna <- scan_missing_cpgs(DNAm, needed_union) # numeric scan; empty-sample hard error
  cpg_list <- resolve_cpgs(mna$usable_cols, clock_sequence) # per-clock present/absent skeleton
  # Coverage floor. Runs over the PLAN, so a thin dep (a GrimAge surrogate off-panel) is flagged even
  # though the user only asked for the composite that consumes it. Kept out of resolve_cpgs() to
  # leave that function pure set math (§2.3a).
  warn_low_coverage(cpg_list, min_coverage)
  partial_cache <- build_partial_cache(
    # one shared cohort cache over present ∧ needed ∧ partial-NA
    DNAm,
    intersect(cpg_list$present_needed_union, mna$partial_na_cols)
  )

  # -- score each work unit --------------------------------------------------------------------
  # dispatch on the catalog PAIR (weights_format, computation_type), plus the family group_id for the
  # pack orchestrators. Cases handled so far:
  #   * cpg_coefficient / {linear, linear_transformed} -> the shared linear engine (one engine;
  #     computation_type only selects linear_score()'s output transform, identity vs anti.trafo).
  #   * GrimAge group (component_matrices):
  #       - linear             = a single-cpg surrogate (DNAmADM, DNAmlogA1C, ...) -> linear_score()
  #         via the generalized clock_coefs() (V1 files for the standalone surrogates).
  #       - linear_transformed = the composite GrimAgeV1/V2 -> score_grimage(), which stacks the
  #         surrogate columns (V1 standalone deps, or V2 `_internal` computed inline) + Age/Female.
  #   * DNAmFitAge group (component_matrices):
  #       - linear             = a fitness biomarker member (DNAmGait/Grip/FEV1/VO2max) -> the
  #         sex-split score_fitage_member(): female/male coef selected on Female, completely-absent
  #         CpGs vendor-filled from sex-specific medians (the first vendor_mean policy).
  #       - linear_transformed = the composite DNAmFitAge -> score_fitage_composite(), a KDM mix of
  #         DNAmGait_noAge/DNAmGrip_noAge/DNAmVO2max + GrimAgeV1 read from `results`.
  # Deps are ordered before their composite in clock_sequence, so a surrogate/member is in `results`
  # by the time the composite reads it (GrimAgeV1 precedes DNAmFitAge, which crosses group bounds).
  # Everything else (external, custom, other component_matrices families, wrapper,
  # reference_code_required) still routes to the not-implemented error.
  results <- vector("list", length(clock_sequence))
  names(results) <- clock_sequence
  for (p in clock_sequence) {
    wf <- clock_weights_format(p)
    ct <- clock_type(p)
    if (
      !clock_is_external(p) &&
        wf == "cpg_coefficient" &&
        ct %in% c("linear", "linear_transformed")
    ) {
      results[[p]] <- linear_score(
        cpg_list$per_clock[[p]],
        DNAm,
        partial_cache,
        pheno
      )
    } else if (!clock_is_external(p) && clock_group_id(p) == "GrimAge") {
      if (ct == "linear") {
        results[[p]] <- linear_score(
          cpg_list$per_clock[[p]],
          DNAm,
          partial_cache,
          pheno
        )
      } else if (ct == "linear_transformed") {
        results[[p]] <- score_grimage(
          p,
          cpg_list$per_clock[[p]],
          results,
          mna$usable_cols,
          DNAm,
          partial_cache,
          pheno
        )
      } else {
        stop(
          "calc_clocks(): GrimAge member '",
          p,
          "' has unexpected computation_type '",
          ct,
          "'.",
          call. = FALSE
        )
      }
    } else if (!clock_is_external(p) && clock_group_id(p) == "DNAmFitAge") {
      if (ct == "linear") {
        results[[p]] <- score_fitage_member(
          p,
          cpg_list$per_clock[[p]],
          DNAm,
          partial_cache,
          pheno
        )
      } else if (ct == "linear_transformed") {
        results[[p]] <- score_fitage_composite(
          p,
          cpg_list$per_clock[[p]],
          results,
          DNAm,
          partial_cache,
          pheno
        )
      } else {
        stop(
          "calc_clocks(): DNAmFitAge member '",
          p,
          "' has unexpected computation_type '",
          ct,
          "'.",
          call. = FALSE
        )
      }
    } else {
      stop(
        "calc_clocks(): clock '",
        p,
        "' (weights_format '",
        wf,
        "', computation_type '",
        ct,
        "') is not implemented yet -- only cpg_coefficient/{linear,linear_transformed} and the ",
        "GrimAge pack are supported so far.",
        call. = FALSE
      )
    }
  }

  # -- assemble record (requested columns + the deps computed for them) ------------------------
  construct_methylCIPHER(
    results[output_ids],
    output_ids,
    clock_ids,
    sample_id,
    positional_ids
  )
}

# Stack per-clock scorer outputs into the methylCIPHER S3 record (detail-plan §1.3 / §4 / §7). Given
# the scorer results for every RETURNED clock (already subset to output order), builds:
#   $scores     n x k double matrix (samples x output_ids: requested first, then auto-added deps)
#   $coverage   list(per_clock = <tier-1 rows>, sample_miss = <n x k tier-2 matrix>)
#   $provenance list(sample_id, positional_ids, clocks, requested, dependencies, covariates_used,
#               batch_set_id)
# Pure reshape -- never re-touches DNAm.
construct_methylCIPHER <- function(
  results,
  output_ids,
  requested_ids,
  sample_id,
  positional_ids
) {
  scores <- do.call(cbind, lapply(results, function(r) r$score))
  dimnames(scores) <- list(sample_id, output_ids)

  per_clock <- lapply(results, function(r) r$coverage)
  names(per_clock) <- output_ids
  sample_miss <- do.call(cbind, lapply(results, function(r) r$sample_miss))
  dimnames(sample_miss) <- list(sample_id, output_ids)

  # covariates ACTUALLY used = the covariate NAMES the returned clocks require. Uses
  # clock_covariates_required(), NOT names(clock_covariate_coefs()): a composite like GrimAgeV1/V2
  # consumes Age + Female in its Cox stack yet carries no top-level $covariates coef map, so the
  # coef-name route would under-report them. covariates_required is the sync-flattened truth for both
  # plain-linear (Age coef) and composite clocks.
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
        # which columns the caller asked for vs. which were pulled in as dependencies and returned
        # alongside. Both are scored columns; this is the only place the distinction survives.
        requested = requested_ids,
        dependencies = setdiff(output_ids, requested_ids),
        covariates_used = covariates_used,
        batch_set_id = NULL # §6: no batch-dependent clock in the linear path yet
      )
    ),
    class = "methylCIPHER_result"
  )
}
