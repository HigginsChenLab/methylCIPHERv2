# scoring seam: mc_spec (data-independent) + mc_cohort (cohort facts) + score_cohort

# stop for an unroutable catalog entry (names all four routing facts)
unroutable <- function(p) {
  catalog_bug(
    paste0(
      "No scoring path for clock %s ",
      "(group %s, weights_format %s, computation_type %s, normalization %s)."
    ),
    p,
    clock_group_id(p),
    clock_weights_format(p),
    clock_type(p),
    clock_norm_scheme(p)
  )
}

# scorer tag for calc_clocks() dispatch
score_type <- function(p) {
  # package-minted aliases route on kind first
  if (identical(clock_kind(p), "sex_routed_alias")) {
    return("sex_routed")
  }

  ct <- clock_type(p)
  wf <- clock_weights_format(p)
  gid <- clock_group_id(p)
  # the plain weighted-sum pair, read by both the external and bundled arms
  plain_linear <- wf == "cpg_coefficient" &&
    ct %in% c("linear", "linear_transformed")

  if (clock_is_external(p)) {
    # groups whose arithmetic is not a plain weighted sum keep their own branch
    etag <- switch(
      gid,
      SystemsAge = "pack_systemsage",
      Zhang2019 = "Zhang2019",
      NULL
    )
    if (!is.null(etag)) {
      return(etag)
    }
    if (plain_linear) {
      return("pack_linear")
    }
    unroutable(p)
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
    DNAmSex_Wang = switch(ct, wrapper = "DNAmSex_Wang", NULL),
    EpiTOC2 = switch(ct, reference_code_required = "EpiTOC2", NULL),
    MiAge = switch(ct, reference_code_required = "MiAge", NULL),
    CellDRIFT = switch(ct, reference_code_required = "linear", NULL),
    NULL
  )
  if (!is.null(gtag)) {
    return(gtag)
  }

  # declared scheme (except Dunedin) -> normalize-then-linear (else stop)
  scheme <- clock_norm_scheme(p)
  if (scheme %in% NORM_SCHEMES_ROUTED) {
    return("normalized")
  }
  if (scheme %in% NORM_SCHEMES) {
    unroutable(p)
  }

  if (plain_linear) {
    return("linear")
  }
  unroutable(p)
}

# true when the branch reads betas.
clock_reads_cpgs <- function(p) {
  switch(
    score_type(p),
    sex_routed = FALSE,
    DNAmFitAge = FALSE,
    # the family owns the derivation -- see R/score_GrimAge.R
    GrimAge = grimage_reads_cpgs(p),
    TRUE
  )
}

# pack groups use score_pack_group()
PACK_SCORE_TYPES <- c("pack_linear", "pack_systemsage")

is_pack_scored <- function(p) {
  score_type(p) %in% PACK_SCORE_TYPES
}

# external pack groups for a sequence. keyed on where weights live.
pack_groups_needed <- function(clock_sequence) {
  ext <- clock_sequence[vapply(clock_sequence, clock_is_external, logical(1L))]
  unique(vapply(ext, clock_group_id, character(1L), USE.NAMES = FALSE))
}

# moment domains over a sequence: key -> cpgs (NULL = every DNAm column).
resolve_moment_domains <- function(clock_sequence) {
  out <- list()
  for (id in clock_sequence) {
    # key first: two clocks on one ref must not resolve its CpGs twice
    key <- clock_moment_key(id)
    if (is.null(key) || key %in% names(out)) {
      next
    }
    # single-bracket: `out[[k]] <- NULL` would delete the element, not store one
    out[key] <- list(clock_sample_scale_ref(id))
  }
  out
}

# data-independent: resolved once, whatever the front end
mc_spec <- function(
  clocks,
  pheno_id = "ID",
  normalize = NULL,
  ext_data = NULL,
  ask = TRUE
) {
  clock_ids <- resolve_clocks(clocks)
  clock_sequence <- resolve_clocks_sequence(clock_ids)
  normalize <- resolve_normalize(normalize, clock_sequence)
  # routed members are scored but never a score column
  output_ids <- drop_routed_members(c(
    clock_ids,
    setdiff(clock_sequence, clock_ids)
  ))
  # tell the caller which clocks read every column, not just their panel
  say_full_panel_clocks(clock_sequence)

  # covariate union for pheno check, carried pheno, and provenance
  covariates <- unique(unlist(lapply(
    clock_sequence,
    clock_covariates_required
  ))) %||%
    character(0)

  packs <- load_mc_assets(pack_groups_needed(clock_sequence), ext_data, ask)
  panels <- clock_panels(clock_sequence, packs, normalize)

  list(
    clock_ids = clock_ids,
    sequence = clock_sequence,
    output_ids = output_ids,
    # the requested pair. mc_cohort()'s norm gate can decline a scheme the data
    # cannot support, so read facts[["normalize"]] for what a run did.
    normalize = normalize,
    covariates = covariates,
    pheno_id = pheno_id,
    packs = packs,
    panels = panels,
    # panel unions are functions of `panels` alone -- resolved here, not per block
    needed_union = panels_union(panels),
    # clocks whose reduction is still inside the branch (catalog-declared)
    cross_sample = split_cross_sample(clock_sequence)[["cross_sample"]],
    # per-sample moment domains mc_cohort banks, keyed (catalog-declared)
    moment_domains = resolve_moment_domains(clock_sequence)
  )
}

# cohort-set facts + pre-score gates (chunked front end accumulates these)
mc_cohort <- function(DNAm, spec, pheno = NULL, min_clocks_coverage = 0.75) {
  if (length(spec[["covariates"]]) && is.null(pheno)) {
    cli::cli_abort(
      c(
        "{.arg pheno} is missing. The requested clocks need
         {cli::qty(spec[['covariates']])} column{?s} in {.arg pheno}:
         {.field {spec[['covariates']]}}.",
        "i" = "Pass a data frame to {.arg pheno} with
               {cli::qty(spec[['covariates']])}{?that/those} column{?s}.",
        if ("Female" %in% spec[["covariates"]]) {
          c(
            "i" = "{.fn predict_sex} estimates the {.field Female} column
                   from {.arg DNAm}."
          )
        }
      ),
      call = NULL
    )
  }

  # sample ids are the DNAm rownames
  check_DNAm(DNAm)
  sample_id <- rownames(DNAm)

  check_pheno(
    pheno,
    ID = spec[["pheno_id"]],
    extra_columns = spec[["covariates"]],
    sample_id = sample_id
  )
  pheno <- resolve_pheno(DNAm, pheno, spec[["pheno_id"]], spec[["covariates"]])

  mna <- scan_missing_cpgs(
    DNAm,
    spec[["needed_union"]],
    moment_domains = spec[["moment_domains"]]
  )
  # the norm gate runs first, because declining a scheme empties that clock's
  # background panel and every downstream fact reads the resolved panel.
  normalize <- spec[["normalize"]]
  panels <- spec[["panels"]]
  declined <- norm_gate(panels, mna[["usable_cols"]], min_clocks_coverage)
  if (length(declined)) {
    normalize[declined] <- FALSE
    # only the norm half can move: declining empties a background panel and
    # leaves every scoring panel exactly as mc_spec() resolved it
    panels[["norm"]] <- dedup_panels(lapply(
      spec[["sequence"]],
      function(cid) clock_norm_cpgs(cid, normalize[[cid]])
    ))
    # a declined background is read by nothing, so it leaves the position axis
    # and the cohort-mean cache
    keep <- panels_union(panels)
    mna[["usable_cols"]] <- intersect(mna[["usable_cols"]], keep)
    mna[["col_mean"]] <- mna[["col_mean"]][names(mna[["col_mean"]]) %in% keep]
  }
  cpg_list <- resolve_cpgs(mna[["usable_cols"]], panels)

  list(
    sample_id = sample_id,
    pheno = pheno,
    usable_cols = mna[["usable_cols"]],
    cpg_list = cpg_list,
    # what the run normalized, after the gate declined what it could not
    normalize = normalize,
    # below min_clocks_coverage: scored NA, never dispatched
    na_clocks = check_coverage(cpg_list, min_clocks_coverage),
    # partial_fill names are the column classification.
    partial_fill = mna[["col_mean"]],
    # null unless a sample_scale clock declared a domain for the sweep to count
    sample_moments = mna[["sample_moments"]]
  )
}

# cohort-wide per-sample facts are narrowed to the rows in hand by this index
block_rows <- function(DNAm, facts) {
  id_index(rownames(DNAm), facts[["sample_id"]], "block_rows")
}

# pheno follows facts$sample_id. never NULL.
block_pheno <- function(facts, rows) {
  facts[["pheno"]][rows, , drop = FALSE]
}

# moments follow facts$sample_id, one entry per domain key.
block_moments <- function(facts, rows) {
  mom <- facts[["sample_moments"]]
  if (is.null(mom)) {
    return(NULL)
  }
  lapply(mom, function(d) list(mean = d[["mean"]][rows], sd = d[["sd"]][rows]))
}

# per-sample moments for a declared domain. missing key is a routing bug.
block_domain_moments <- function(block, id) {
  key <- clock_moment_key(id)
  mom <- if (!is.null(key)) block[["sample_moments"]][[key]]
  if (is.null(mom)) {
    stop(
      sprintf(
        paste0(
          "block_domain_moments: no moments banked for %s. ",
          "This is a package bug -- please report it."
        ),
        id
      ),
      call. = FALSE
    )
  }
  mom
}

# scoring-time failures per clock (coverage cannot see these)
new_notes <- function() {
  new.env(parent = emptyenv())
}

# record that `sample_id` could not be scored for clock `id`
note_scoring_failure <- function(block, id, sample_id) {
  notes <- block[["notes"]]
  if (!length(sample_id)) {
    return(invisible(NULL))
  }
  notes[[id]] <- union(notes[[id]], sample_id)
  invisible(NULL)
}

# every branch that scores NA for named samples says it this way. `reason` is
# the already-rendered lead line, so each branch supplies only what differs.
# points at samples_coverage(), never at the note it just wrote: the collector
# is internal and the `reason` column is the same fact where a user can read it.
say_scored_na <- function(id, failed, reason) {
  cli::cli_warn(
    c(
      reason,
      capped_bullets(failed, val_lines),
      "i" = "{.val {id}} scores {.code NA} for
             {cli::qty(failed)}{?this sample/these samples}.",
      "i" = "{.fn samples_coverage} marks {cli::qty(failed)}{?it/them} with
             {.field reason} {.val fit}."
    ),
    call = NULL
  )
}

# a sample_scale clock needs 2 observed values on its domain or the per-sample
# sd is NA. the domain is declared, so read it rather than naming the clocks.
say_moment_failure <- function(id, failed) {
  where <- if (clock_needs_full_panel(id)) {
    cli::format_inline("every column of {.arg DNAm}")
  } else {
    "the z-score reference"
  }
  say_scored_na(
    id,
    failed,
    cli::format_inline(
      "{length(failed)} sample{?s} {cli::qty(failed)}{?has/have} fewer than
       2 observed CpGs in {where}:"
    )
  )
}

# union two clock-keyed note lists, name-sorted. also the collector -> list
# conversion, as merge_notes(list(), as.list(env)).
merge_notes <- function(a, b) {
  if (!length(b)) {
    return(a)
  }
  for (id in names(b)) {
    a[[id]] <- union(a[[id]], b[[id]])
  }
  a[sort(names(a))]
}

# per-block view: DNAm + its usable column index, partial cache, pheno, notes
mc_block <- function(DNAm, spec, facts) {
  usable <- facts[["usable_cols"]]
  # cpg_list's positions index this vector, in this order
  if (!identical(usable, facts[["cpg_list"]][["usable_cols"]])) {
    stop(
      paste0(
        "mc_block: usable_cols is not the vector the CpG panels were resolved ",
        "against. This is a package bug -- please report it."
      ),
      call. = FALSE
    )
  }

  # usable position -> column position. unnamed: callers hold positions, not names
  usable_idx <- match(usable, colnames(DNAm))
  if (anyNA(usable_idx)) {
    stop(
      sprintf(
        paste0(
          "mc_block: %d usable CpG(s) are not columns of this block. ",
          "This is a package bug -- please report it."
        ),
        sum(is.na(usable_idx))
      ),
      call. = FALSE
    )
  }

  # the cohort-mean columns, on the usable axis every panel is resolved against
  fill <- facts[["partial_fill"]]
  fill_idx <- match(names(fill), usable)
  if (anyNA(fill_idx)) {
    stop(
      sprintf(
        paste0(
          "mc_block: %d cohort-mean CpG(s) are outside the usable set. ",
          "This is a package bug -- please report it."
        ),
        sum(is.na(fill_idx))
      ),
      call. = FALSE
    )
  }
  # a panel's cached CpGs are read off this by position, never by name
  cached_mask <- NULL
  if (length(fill_idx)) {
    cached_mask <- logical(length(usable))
    cached_mask[fill_idx] <- TRUE
  }

  # one cohort-row index, shared by every per-sample fact narrowed below
  rows <- block_rows(DNAm, facts)
  block <- list(
    DNAm = DNAm,
    pheno = block_pheno(facts, rows),
    # banked upstream: the block never needs the matrix at its full width
    sample_moments = block_moments(facts, rows),
    packs = spec[["packs"]],
    usable_idx = usable_idx,
    cached_mask = cached_mask,
    sample_id = rownames(DNAm),
    # write-only collector for scoring-time failures
    notes = new_notes()
  )
  block[["partial_cache"]] <- build_partial_cache(
    DNAm,
    block_cols(fill_idx, block),
    fill
  )
  block
}

# blank the rows the sample gate refused. one matmul scored them all, so the
# mask goes on every writer into results and pending.
mask_gated_rows <- function(out, gate, id) {
  low <- gate[[id]][["na"]]
  if (is.null(low) || !any(low)) {
    return(out)
  }
  out[low, ] <- NA_real_
  out
}

# score one block: scores, coverage, row-gate verdicts, pending, notes
score_cohort <- function(DNAm, spec, facts, min_samples_coverage = 0.75) {
  clock_sequence <- spec[["sequence"]]
  cpg_list <- facts[["cpg_list"]]
  block <- mc_block(DNAm, spec, facts)

  # coverage before scoring, keyed by clock id
  coverage <- compute_coverage(clock_sequence, cpg_list, block)

  results <- vector("list", length(clock_sequence))
  names(results) <- clock_sequence
  # per-sample intermediates for cohort-reducing clocks
  pending <- list()

  # gated columns are seeded, not scored. a null entry would shrink a dependent
  # to numeric(0) instead of carrying the NA into it.
  na_clocks <- intersect(clock_sequence, facts[["na_clocks"]])
  for (p in na_clocks) {
    results[[p]] <- score_matrix(NA_real_, block[["sample_id"]], p)
  }
  scoreable <- setdiff(clock_sequence, na_clocks)

  # one pass, skipping the clocks the column gate already blanked
  gate <- row_gate(coverage, min_samples_coverage, skip = na_clocks)

  # resolved once here, shared by the pack filter and the dispatch below
  types <- vapply(scoreable, score_type, character(1))
  is_pack <- types %in% PACK_SCORE_TYPES

  pack_ids <- scoreable[is_pack]
  pgroups <- vapply(pack_ids, clock_group_id, character(1), USE.NAMES = FALSE)
  # empty when nothing is pack-scored. one declared panel per group.
  for (gids in split(pack_ids, pgroups)) {
    grp <- score_pack_group(gids, cpg_list[["per_clock"]][[gids[[1]]]], block)
    for (id in names(grp)) {
      results[[id]] <- mask_gated_rows(grp[[id]], gate, id)
    }
  }

  # branch dispatch: every scorer takes (id, cpgs, block, results)
  for (p in scoreable[!is_pack]) {
    cpgs <- cpg_list[["per_clock"]][[p]]
    ty <- types[[p]]
    out <- switch(
      ty,
      linear = linear_score(cpgs, block),
      GrimAge = score_GrimAge(p, cpgs, block, results),
      DNAmFitAge = score_DNAmFitAge(p, cpgs, block, results),
      PhysAge = physage_raws(p, cpgs, block, results),
      Dunedin = score_Dunedin(p, cpgs, block, results),
      normalized = score_normalized(p, cpgs, block, results),
      EpiTOC2 = score_EpiTOC2(p, cpgs, block, results),
      MiAge = score_MiAge(p, cpgs, block, results),
      Zhang2019 = score_Zhang2019(p, cpgs, block, results),
      DNAmSex_Wang = score_DNAmSex_Wang(p, cpgs, block, results),
      sex_routed = score_sex_routed(p, cpgs, block, results),
      stop(
        sprintf("No dispatch branch for score_type %s (clock %s).", ty, p),
        call. = FALSE
      )
    )
    # masked here, so dependents read the NA and the raws carry it into pending
    out <- mask_gated_rows(out, gate, p)
    # cohort-reducing clocks yield intermediates into pending
    if (p %in% spec[["cross_sample"]]) {
      pending[[p]] <- out
    } else {
      results[[p]] <- out
    }
  }

  list(
    scores = results,
    coverage = coverage,
    # per-sample verdicts, for the front door to warn from
    gate = gate,
    pending = pending,
    # per-clock sample ids the branch could not score
    notes = merge_notes(list(), as.list(block[["notes"]]))
  )
}

# cohort reduction after assembly (no-op when pending is empty)
finalize_cross_sample <- function(scores, pending) {
  notes <- list()
  for (p in names(pending)) {
    ty <- score_type(p)
    raws <- pending[[p]]
    col <- switch(
      ty,
      PhysAge = finalize_PhysAge(p, raws),
      stop(
        sprintf("No finalize branch for score_type %s (clock %s).", ty, p),
        call. = FALSE
      )
    )
    scores[[p]] <- col
    # a sample with intermediates but no score lost it in the reduction. one
    # with none was already blanked upstream, and needs no second reason.
    lost <- rownames(raws)[rowSums(!is.na(raws)) > 0L & is.na(col[, 1L])]
    if (length(lost)) {
      notes[[p]] <- lost
    }
  }
  list(scores = scores, notes = notes)
}
