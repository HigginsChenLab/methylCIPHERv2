# unroutable catalog entry
unroutable <- function(p, gid, wf, ct) {
  cli::cli_abort(
    c(
      "No scoring path for clock {.val {p}}.",
      "*" = "group {.val {gid}}, weights_format {.val {wf}},
             computation_type {.val {ct}}",
      "i" = "This is a package bug -- please report it."
    ),
    call = NULL
  )
}

# scorer tag for calc_clocks() dispatch
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

  # group-specific tags first
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

# pack groups use score_pack_group()
PACK_SCORE_TYPES <- c("pack_linear", "pack_systemsage")

is_pack_scored <- function(p) {
  score_type(p) %in% PACK_SCORE_TYPES
}

# external pack groups needed for a compute sequence
pack_groups_needed <- function(clock_sequence) {
  unique(unlist(lapply(clock_sequence, function(p) {
    if (is_pack_scored(p)) clock_group_id(p) else NULL
  })))
}

# public scorer
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
  # routed members are internal machinery: scored, but never a score column
  output_ids <- drop_routed_members(c(
    clock_ids,
    setdiff(clock_sequence, clock_ids)
  ))
  checkmate::assert_number(min_row_coverage, lower = 0, upper = 1)

  # stamp positional ids first -- check_DNAm() requires rownames. A non-matrix
  # skips the stamp so check_DNAm() reports it rather than the assignment.
  positional_ids <- is.matrix(DNAm) && is.null(rownames(DNAm))
  if (positional_ids) {
    if (!allow_positional_ids) {
      cli::cli_abort(
        c(
          "DNAm has no rownames.",
          "i" = "Set them, or pass {.code allow_positional_ids = TRUE}
                 to use sample1..sampleN."
        ),
        call = NULL
      )
    }
    rownames(DNAm) <- paste0("sample", seq_len(nrow(DNAm)))
  }
  check_DNAm(DNAm)
  sample_id <- rownames(DNAm)
  resolve_DNAm_extra(clock_sequence)

  # the one covariate union: gates the pheno check, narrows the carried
  # pheno, and is stamped as provenance
  extra_columns <- unique(unlist(lapply(
    clock_sequence,
    clock_covariates_required
  )))
  if (is.null(extra_columns)) {
    extra_columns <- character(0)
  }
  if (length(extra_columns) && is.null(pheno)) {
    cli::cli_abort(
      c(
        "These clocks need {cli::qty(extra_columns)} pheno column{?s}
         {.field {extra_columns}}, but {.arg pheno} is missing.",
        "i" = "Pass a pheno table with {cli::qty(extra_columns)}
               {?that/those} column{?s}."
      ),
      call = NULL
    )
  }
  check_pheno(
    pheno,
    ID = pheno_id,
    extra_columns = extra_columns,
    positional = positional_ids,
    sample_id = sample_id
  )
  pheno <- resolve_pheno(DNAm, pheno, pheno_id, positional_ids, extra_columns)

  packs <- load_mc_assets(pack_groups_needed(clock_sequence), assets, ask)

  panels <- clock_panels(clock_sequence, packs)
  mna <- scan_missing_cpgs(DNAm, panels_union(panels))
  cpg_list <- resolve_cpgs(mna$usable_cols, panels)
  check_coverage(cpg_list, min_col_coverage)
  partial_cache <- build_partial_cache(
    DNAm,
    intersect(cpg_list$present_needed_union, mna$partial_na_cols)
  )

  # coverage/QC needs no score: compute it once, keyed by clock id
  coverage <- compute_coverage(
    clock_sequence,
    cpg_list,
    DNAm,
    partial_cache,
    pheno
  )
  # gate every clock actually computed -- a routed member's panel is the one
  # that carries the alias's samples, and it has no column of its own
  check_row_coverage(coverage, min_row_coverage)

  # scoring loop returns score matrices only; coverage was hoisted above
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
        results,
        mna$usable_cols,
        DNAm,
        partial_cache,
        pheno
      ),
      DNAmFitAge = score_DNAmFitAge(p, results, DNAm),
      PhysAge = score_PhysAge(p, cpgs, DNAm, partial_cache),
      Dunedin = score_Dunedin(p, cpgs, DNAm, partial_cache),
      EpiTOC2 = score_EpiTOC2(p, cpgs, DNAm, partial_cache),
      MiAge = score_MiAge(p, cpgs, DNAm, partial_cache),
      Zhang2019 = score_Zhang2019(p, cpgs, DNAm, partial_cache),
      sex_routed = score_sex_routed(p, results, DNAm, pheno),
      cli::cli_abort(
        "No dispatch branch for score_type {.val {score_type(p)}}
         (clock {.val {p}}).",
        call = NULL
      )
    )
  }

  batch_set_id <- if (
    any(vapply(clock_sequence, clock_batch_dependent, logical(1)))
  ) {
    digest::digest(sort(sample_id))
  } else {
    NULL
  }

  construct_mc_result(
    results,
    coverage,
    output_ids,
    clock_ids,
    sample_id,
    positional_ids,
    pheno = pheno,
    pheno_id = pheno_id,
    covariates_used = extra_columns,
    batch_set_id = batch_set_id
  )
}

# n x length(ids) per-sample miss matrix; a NULL entry (no such panel) is NA
miss_matrix <- function(miss_list, ids, sample_id) {
  m <- matrix(
    NA_integer_,
    nrow = length(sample_id),
    ncol = length(ids),
    dimnames = list(sample_id, ids)
  )
  for (id in ids) {
    v <- miss_list[[id]]
    if (!is.null(v)) {
      m[, id] <- v
    }
  }
  m
}

# stack scorer outputs into mc_result. `results` are the per-clock score
# matrices; `coverage` is the hoisted structure keyed by clock id. `output_ids`
# are the ones that get a score column -- coverage is kept for every clock
# computed, so a routed member still reports the panel its alias's samples used.
construct_mc_result <- function(
  results,
  coverage,
  output_ids,
  requested_ids,
  sample_id,
  positional_ids,
  pheno = NULL,
  pheno_id = "ID",
  covariates_used = character(0),
  batch_set_id = NULL
) {
  scores <- do.call(cbind, results[output_ids])
  dimnames(scores) <- list(sample_id, output_ids)

  # NULL coverage (aliases) stays a key. sample_miss is per panel: a score
  # matrix over every column, and a norm matrix over just the columns whose
  # clock normalizes (a NULL norm entry means no norm panel).
  per_clock <- coverage$per_clock
  norm_ids <- output_ids[vapply(
    output_ids,
    function(id) !is.null(coverage$sample_miss$norm[[id]]),
    logical(1L)
  )]
  sample_miss <- list(
    score = miss_matrix(coverage$sample_miss$score, output_ids, sample_id),
    norm = miss_matrix(coverage$sample_miss$norm, norm_ids, sample_id)
  )

  structure(
    list(
      scores = scores,
      pheno = pheno,
      coverage = list(per_clock = per_clock, sample_miss = sample_miss),
      provenance = list(
        sample_id = sample_id,
        positional_ids = positional_ids,
        pheno_id = pheno_id,
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
