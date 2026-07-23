# a catalog entry no branch claims -- hard stop: a sync that adds an unroutable
# routing pair is a gap to fix here, not something to score around silently
unroutable <- function(p, gid, wf, ct) {
  stop(
    "score_type(): no scoring branch for clock '",
    p,
    "' -- group '",
    gid,
    "', weights_format '",
    wf,
    "', computation_type '",
    ct,
    "'. Add a branch, or drop the clock upstream.",
    call. = FALSE
  )
}

# scorer tag for calc_clocks() dispatch -- total over the catalog: every clock
# routes to a known tag or this errors
score_type <- function(p) {
  ct <- clock_type(p)
  wf <- clock_weights_format(p)
  gid <- clock_group_id(p)

  if (identical(ct, "sex_routed")) {
    return("sex_routed")
  }

  if (clock_is_external(p)) {
    if (identical(gid, "SystemsAge")) {
      return("pack_systemsage")
    }
    if (wf == "cpg_coefficient" && ct %in% c("linear", "linear_transformed")) {
      return("pack_linear")
    }
    unroutable(p, gid, wf, ct)
  }

  # group-specific tags first -- generic cpg_coefficient/linear falls through below
  gtag <- switch(
    gid,
    Dunedin = "Dunedin",
    Zhang2019 = "Zhang2019",
    GrimAge = switch(
      ct,
      linear = "linear",
      linear_transformed = "GrimAge",
      NULL
    ),
    DNAmFitAge = switch(
      ct,
      linear = "linear",
      linear_transformed = "DNAmFitAge",
      NULL
    ),
    PhysAge = switch(ct, linear_transformed = "PhysAge", NULL),
    EpiTOC2 = switch(ct, reference_code_required = "EpiTOC2", NULL),
    MiAge = switch(ct, reference_code_required = "MiAge", NULL),
    CellDRIFT = switch(ct, reference_code_required = "linear", NULL),
    NULL
  )
  if (!is.null(gtag)) {
    return(gtag)
  }

  if (wf == "cpg_coefficient" && ct %in% c("linear", "linear_transformed")) {
    return("linear")
  }
  unroutable(p, gid, wf, ct)
}

# tags scored by score_pack_group() rather than the per-clock switch
PACK_SCORE_TYPES <- c("pack_linear", "pack_systemsage")

is_pack_scored <- function(p) {
  score_type(p) %in% PACK_SCORE_TYPES
}

# external pack groups a compute sequence needs loaded
pack_groups_needed <- function(clock_sequence) {
  unique(unlist(lapply(clock_sequence, function(p) {
    if (is_pack_scored(p)) clock_group_id(p) else NULL
  })))
}

# public scorer: resolve, prepare once, score each unit, assemble record
calc_clocks <- function(
  DNAm,
  clocks,
  pheno = NULL,
  pheno_id = "ID",
  allow_positional_ids = TRUE,
  min_col_coverage = 0.75,
  min_row_coverage = 0.75,
  assets = NULL,
  ask = TRUE
) {
  clock_ids <- resolve_clocks(clocks)
  clock_sequence <- resolve_clocks_sequence(clock_ids)
  output_ids <- c(clock_ids, setdiff(clock_sequence, clock_ids))
  check_DNAm(DNAm)
  # floor for check_row_coverage(), checked before scoring
  checkmate::assert_number(min_row_coverage, lower = 0, upper = 1)

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
    positional = positional_ids,
    sample_id = sample_id
  )
  pheno <- resolve_pheno(DNAm, pheno, pheno_id, positional_ids)

  packs <- load_mc_assets(pack_groups_needed(clock_sequence), assets, ask)

  panels <- clock_panels(clock_sequence, packs)
  mna <- scan_missing_cpgs(DNAm, panels_union(panels))
  cpg_list <- resolve_cpgs(mna$usable_cols, panels)
  check_coverage(cpg_list, min_col_coverage)
  partial_cache <- build_partial_cache(
    DNAm,
    intersect(cpg_list$present_needed_union, mna$partial_na_cols)
  )

  results <- vector("list", length(clock_sequence))
  names(results) <- clock_sequence

  is_pack <- vapply(clock_sequence, is_pack_scored, logical(1))
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

  for (p in clock_sequence[!is_pack]) {
    cpgs <- cpg_list$per_clock[[p]]
    results[[p]] <- switch(
      score_type(p),
      linear = linear_score(cpgs, DNAm, partial_cache, pheno, packs),
      GrimAge = score_GrimAge(
        p,
        cpgs,
        results,
        mna$usable_cols,
        DNAm,
        partial_cache,
        pheno
      ),
      DNAmFitAge = score_DNAmFitAge(
        p,
        cpgs,
        results,
        DNAm,
        partial_cache
      ),
      PhysAge = score_PhysAge(p, cpgs, DNAm, partial_cache),
      Dunedin = score_Dunedin(p, cpgs, DNAm, partial_cache),
      EpiTOC2 = score_EpiTOC2(p, cpgs, DNAm, partial_cache),
      MiAge = score_MiAge(p, cpgs, DNAm, partial_cache),
      Zhang2019 = score_Zhang2019(p, cpgs, DNAm, partial_cache),
      sex_routed = score_sex_routed(p, results, DNAm, pheno),
      # score_type() already rejects unroutable catalog entries, so reaching here
      # means a tag was added there without a branch below
      stop(
        "calc_clocks(): score_type tag '",
        score_type(p),
        "' (clock '",
        p,
        "') has no dispatch branch.",
        call. = FALSE
      )
    )
  }

  results <- mask_routed_members(results, clock_sequence, pheno)
  check_row_coverage(results[output_ids], min_row_coverage)

  batch_set_id <- if (
    any(vapply(output_ids, clock_batch_dependent, logical(1)))
  ) {
    digest::digest(sort(sample_id))
  } else {
    NULL
  }

  construct_mc_result(
    results[output_ids],
    output_ids,
    clock_ids,
    sample_id,
    positional_ids,
    batch_set_id
  )
}

# stack scorer outputs into the mc_result record
construct_mc_result <- function(
  results,
  output_ids,
  requested_ids,
  sample_id,
  positional_ids,
  batch_set_id = NULL
) {
  scores <- do.call(cbind, lapply(results, function(r) r$score))
  dimnames(scores) <- list(sample_id, output_ids)

  # NULL coverage (e.g. sex-routed) becomes all-NA in the sample QC matrix
  per_clock <- lapply(results, function(r) r$coverage)
  names(per_clock) <- output_ids
  sample_miss <- do.call(
    cbind,
    lapply(results, function(r) {
      if (is.null(r$sample_miss)) {
        rep(NA_integer_, length(sample_id))
      } else {
        r$sample_miss
      }
    })
  )
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
    class = "mc_result"
  )
}
