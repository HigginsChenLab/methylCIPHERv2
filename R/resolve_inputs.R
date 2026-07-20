# Universal DNAm invariants only -- runs ONCE, no clock knowledge. Clock-specific DNAm
# preconditions (full-panel adequacy) live in resolve_DNAm_extra() below, not here. Identity-less
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
  checkmate::assert_character(colnames(DNAm), unique = TRUE, null.ok = FALSE)
  checkmate::assert_character(rownames(DNAm), unique = TRUE, null.ok = FALSE)
  # orientation heuristics (we expect samples x CpGs). A real methylation panel carries 27k-937k
  # CpGs, but no study has anywhere near 2e5 SAMPLES -- so >= 2e5 columns can only be the CpG axis,
  # meaning the orientation is certainly correct and both checks below are moot. Gating on width
  # here also means the colname scan never runs on the widest (450k/850k/EPICv2) matrices, which is
  # exactly the case that dragged on older machines. Below that width, two independent tell-tales
  # of a transposed / mislabeled matrix:
  if (ncol(DNAm) < 2e5) {
    if (nrow(DNAm) > ncol(DNAm)) {
      warning(
        "DNAm should be formatted as samples * CpG. Currently DNAm has more rows (samples) than columns (CpGs), which is highly unlikely. Pass the full DNAm matrix without pre-subsetting to `calc_clock()`."
      )
    }
    # startsWith(), not grepl("^cg", ...): identical meaning (prefix "cg") but a plain C-level
    # string compare with no regex engine to spin up.
    if (!any(startsWith(colnames(DNAm), "cg"))) {
      warning(
        "It looks like you may need to format DNAm using t(DNAm) to get samples as rows!"
      )
    }
  }
  invisible(TRUE)
}

# Precondition NOTICE of the `sample_scale` pre-transform -- NOT a universal or front-end check, and
# NOT a stats collector. Zhang2019 is the only clock whose recipe carries `sample_scale` (per-sample
# row moments across the WHOLE CpG panel), so its scores drift when DNAm is pre-subsetted. Rather than
# a generic catalog-driven warning, this is HARD-CODED to Zhang2019 for now (the sole `sample_scale`
# clock) and emits an informational message(), not a warning -- the moments were originally computed
# over all CpGs, but a large-enough subset is usually sufficient. The moments themselves are NOT
# computed here: scorers receive raw full-width DNAm (detail-plan §3), so the sample_scale transform
# computes its own r_mu/r_sd downstream, and Zhang2019 is the only consumer so there is nothing to
# share by hoisting. Called for its side effect only. Intended end-state: retire this + the planned
# clock_needs_full_panel() accessor, folding the notice into the sample_scale transform once that
# module exists (detail-plan §2.4). The `"sample_scale" %in% batch_ops` catalog marker stays. NB: this
# is the ONLY norm-adjacent thing the package executes -- array normalization (BMIQ/noob/quantile) is
# upstream and never run here.
resolve_DNAm_extra <- function(clock_ids) {
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
check_pheno <- function(
  pheno,
  ID = NULL,
  extra_columns = NULL,
  positional = FALSE
) {
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
        nrow(DNAm),
        " row(s) to match DNAm (got ",
        nrow(pheno),
        "). ",
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
      "pheno is missing ",
      length(missing),
      " sample id(s) present in rownames(DNAm): ",
      paste(utils::head(missing, 10L), collapse = ", "),
      if (length(missing) > 10L) ", ..." else "",
      call. = FALSE
    )
  }
  pheno <- pheno[match(sample_id, pheno[[pheno_id]]), , drop = FALSE]
  pheno
}

# Pure namespace resolution: user tokens -> catalog clock_ids. No math, no ordering, and no
# cross-clock dependency expansion -- that is resolve_clocks_sequence()'s job (below), kept separate
# so this stays a pure token->id map.
#
# A token resolves by a fixed precedence, MAXIMAL clock-id set first:
#   1. "all"           -> every clock_id.
#   2. a group_id      -> all member clock_ids (the whole group).
#   3. a bare clock_id -> itself.
# Group beats clock on a name clash BY DESIGN: some group_ids are also clock_ids (e.g. "DNAmFitAge"
# names both the 7-member group and one composite member), and asking for the group must return as
# MANY member ids as possible. This one rule covers every shape uniformly -- a group_id that is no
# clock_id (GrimAge, SystemsAge, PCClocks), a group_id that is also a member id (DNAmFitAge), and a
# singleton group (group_id == its sole clock_id, e.g. MiAge); the last two coincide when the group
# has one member. Returns unique clock_ids in first-seen order after expansion.
# e.g. resolve_clocks("Bohlin") -> c("Bohlin251", "Bohlin96").
# (roxygen comes later, once the API stabilizes; man/resolve_clocks.Rd is stale until then.)
resolve_clocks <- function(clocks) {
  checkmate::assert_character(
    clocks,
    min.len = 1L,
    any.missing = FALSE,
    min.chars = 1L,
    .var.name = "clocks"
  )

  members <- split(mc_index$clock_id, mc_index$group_id) # group_id -> member clock_ids
  clock_ids <- mc_index$clock_id

  resolve_one <- function(tok) {
    if (tok == "all") {
      return(clock_ids)
    }
    # group first -> maximal expansion when a token is both a group_id and a clock_id
    if (!is.null(members[[tok]])) {
      return(members[[tok]])
    }
    if (tok %in% clock_ids) {
      return(tok)
    }
    NULL # unknown -> flagged below
  }

  resolved <- lapply(clocks, resolve_one)
  bad <- clocks[vapply(resolved, is.null, logical(1L))]

  if (length(bad)) {
    stop(
      "Unknown clock requested(s): ",
      paste(unique(bad), collapse = ", "),
      call. = FALSE
    )
  }

  out <- unlist(resolved, use.names = FALSE)
  out[!duplicated(out)]
}

# Expand a resolved clock_id set into a dependency-satisfying COMPUTE order.
#
# resolve_clocks() answers namespace only ("which clocks did the user ask for"). This answers "what
# must we compute, and in what order": it walks depends_on_clocks (via clock_depends_on()) to pull
# in every TRANSITIVE dependency and returns the closure topologically sorted, so a clock always
# comes AFTER everything it depends on. Like calc_clocks()'s covariate union, deps are pulled in ON
# DEMAND: only 3 clocks declare any (GrimAgeV1/V2, DNAmFitAge), so a request that never touches them
# adds nothing (e.g. SystemsAge and its organ/system members declare none and pass through
# unchanged). Independent clocks keep first-seen order (stable).
#
# Auto-added ids (in the plan but not in `clocks`) are compute-only INTERMEDIATES: the caller
# returns score columns for the REQUESTED set (setdiff against this plan) and feeds the rest in as
# inputs. This is exactly why calc_clocks()'s covariate union must run over the PLAN, not the raw
# request -- DNAmFitAge alone declares only Female, but its GrimAgeV1 / DNAmVO2max deps also need Age.
# `clocks` must already be catalog ids (resolve_clocks() output); each dep is validated on visit.
resolve_clocks_sequence <- function(clocks) {
  # Clocks can have recursive levels of dependencies: FitAge -> GrimAgeV1, but
  # GrimAgeV1 has its own deps (its 8 CpG surrogates). So we walk the dependency
  # chain, recursing into each dep, until we hit clocks with no deps (the base
  # case) -- giving the full transitive set in deps-first (topological) order.
  st <- new.env(parent = emptyenv())
  st$out <- character(length(mc_index$clock_id))
  st$n <- 0L
  st$seen <- new.env(parent = emptyenv())

  visit <- function(id, stack) {
    if (!is.null(st$seen[[id]])) {
      return(invisible()) # already planned (emitted under an earlier root or dep path)
    }
    if (id %in% stack) {
      stop(
        "Dependency cycle among clocks: ",
        paste(c(stack[match(id, stack):length(stack)], id), collapse = " -> "),
        call. = FALSE
      )
    }
    # clock_depends_on() -> clock_entry() errors on an id absent from the catalog, so a
    # dangling depends_on_clocks reference surfaces here rather than silently dropping a term.
    for (dep in clock_depends_on(id)) {
      visit(dep, c(stack, id))
    }
    # deps are all emitted now, so id lands after every clock it needs
    st$n <- st$n + 1L
    st$out[[st$n]] <- id
    st$seen[[id]] <- TRUE
    invisible()
  }

  for (id in clocks) {
    visit(id, character(0))
  }
  st$out[seq_len(st$n)] # trim to the ids actually planned
}

# Catalog-only union of every CpG any planned clock needs -- scoring role + normalization/background
# role -- across the compute sequence. PURE set math over the catalog: no DNAm, no numerics, no
# usable_cols (unlike resolve_cpgs, which needs the post-scan usable universe). That independence is
# the point: it can be computed BEFORE scan_missing_cpgs to BOUND the numeric missingness scan (and
# usable-column resolution) to clock width instead of the full 450k/850k panel -- classifying or
# intersecting the columns no clock touches is pure waste on a wide array. Deduped once here so a CpG
# shared across component clocks is listed a single time.
needed_cpgs_union <- function(clock_sequence) {
  unique(unlist(
    lapply(clock_sequence, function(id) {
      c(clock_scoring_cpgs(id), clock_norm_cpgs(id))
    }),
    use.names = FALSE
  ))
}

# Per-clock CpG resolution -- PURE set math over the compute plan. No numerics, no pheno, no DNAm
# values (it takes the USABLE column universe as a character vector, not the matrix). Given
# `usable_cols` (colnames(DNAm) minus the all-NA columns scan_missing_cpgs() reclassified as absent,
# detail-plan §2.3a) and the resolved `clock_sequence`, it answers per clock: which scoring / norm
# CpGs are needed, which are present, which are absent -- the tier-1 aggregate coverage skeleton
# (§4.1) whose n_cpg_* counts summary() reads straight off, plus `present_needed_union`, the candidate
# set the shared partial-NA cache is built from (§2.3a).
#
# Scope boundary (why this is not doing more): absence is sample-INVARIANT (a probe off the panel is
# absent for every sample), so it belongs in this aggregate pass. The two things that DON'T live here:
#   - partial-NA (present-but-NA) fill: sample-varying + numeric -> the shared cache (build_partial_cache).
#   - the tier-2 per-sample missingness vector (§4.2): each scorer emits it from its own raw subset.
# `pheno` is deliberately absent from the signature: it is only ever needed by sex-keyed VENDOR fill,
# which is per-clock and downstream -- pulling it in here was the scope-creep tell (DECISIONS 2026-07-18).
resolve_cpgs <- function(usable_cols, clock_sequence) {
  usable <- unique(usable_cols)

  one <- function(id) {
    score_needed <- clock_scoring_cpgs(id)
    norm_needed <- clock_norm_cpgs(id)
    list(
      clock_id = id,
      # scoring role (enters the weighted sum)
      score_needed = score_needed,
      score_present = intersect(score_needed, usable),
      score_absent = setdiff(score_needed, usable), # -> n_cpg_score_miss + vendor/drop input
      # normalization/background role (coverage annotation only; never imputed, §2.4a)
      norm_needed = norm_needed,
      norm_present = intersect(norm_needed, usable),
      norm_absent = setdiff(norm_needed, usable), # -> n_cpg_norm_miss
      norm_scheme = clock_norm_scheme(id)
    )
  }

  per_clock <- lapply(clock_sequence, one)
  names(per_clock) <- clock_sequence

  # Cache candidate set: only PRESENT scoring CpGs can carry a partial NA worth cohort-filling (absent
  # ones are the vendor/drop path; norm CpGs are never imputed). Unioned once across the plan so a CpG
  # shared by many clocks is cached a single time -- the dedup that motivated hoisting the cache.
  present_needed_union <- unique(unlist(
    lapply(per_clock, function(x) x$score_present),
    use.names = FALSE
  ))

  list(per_clock = per_clock, present_needed_union = present_needed_union)
}

# Coverage floor: warn once, listing every clock scoring on a smaller fraction of its scoring CpGs
# than `threshold`. Sample-INVARIANT by construction -- it reads the resolve_cpgs() skeleton, so it
# fires on panel/array mismatch (wrong array, a group's weights off-manifest, a simulated panel built
# from too narrow a clock set), NOT on per-sample NA, which is the cache/tier-2 story instead.
#
# It warns rather than errors on purpose: a partial panel still yields a defensible score for many
# clocks (vendor_mean fills; omit degrades smoothly), and the caller may be knowingly scoring a 27k
# array. What is NOT defensible is silence -- the motivating case is a composite whose INPUT collapsed:
# DNAmFitAge scored off a GrimAgeV1 built from 0 present CpGs comes back a plausible-looking number,
# and because coverage lives on the dep's row, nothing on the composite's own row shows it. Running
# this over the whole compute plan (deps included) is what makes that visible.
#
# Clocks with no scoring CpGs (score-reading composites, external groups) have no ratio and are skipped.
warn_low_coverage <- function(cpg_list, threshold = 0.8) {
  checkmate::assert_number(threshold, lower = 0, upper = 1)
  if (threshold <= 0) {
    return(invisible(character(0)))
  }

  ratios <- vapply(
    cpg_list$per_clock,
    function(x) {
      n <- length(x$score_needed)
      if (!n) NA_real_ else length(x$score_present) / n
    },
    numeric(1L)
  )
  low <- which(!is.na(ratios) & ratios < threshold)
  if (!length(low)) {
    return(invisible(character(0)))
  }

  ids <- names(ratios)[low]
  lines <- vapply(
    low,
    function(i) {
      x <- cpg_list$per_clock[[i]]
      sprintf(
        "  %s: %d/%d (%.1f%%)",
        x$clock_id,
        length(x$score_present),
        length(x$score_needed),
        100 * ratios[[i]]
      )
    },
    character(1L)
  )
  warning(
    sprintf(
      "%d clock(s) score on under %.0f%% of their scoring CpGs:\n%s",
      length(low),
      100 * threshold,
      paste(lines, collapse = "\n")
    ),
    call. = FALSE
  )
  invisible(ids)
}
