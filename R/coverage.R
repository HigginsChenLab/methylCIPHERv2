# Coverage/QC computed once, upstream of scoring. No field of a coverage record
# depends on a score, so the whole structure is built from the cpg split, the
# cohort-mean cache and the imputation policy -- keyed by clock id, then merged
# into the result. Branches return only their score.
#
# Per-sample miss is counted per distinct panel once (FitAge/GrimAge reuse
# panels) and per panel role: every clock has a score panel; a normalizing clock
# (only DunedinPACE) also has a norm panel. The two never collapse into one
# implicit number.

# per-sample partial-fill count over one panel's present CpGs
panel_sample_miss <- function(present, DNAm, partial_cache) {
  count_sample_miss(DNAm, cached_cols(present, partial_cache))
}

# one clock's record from its per-panel miss. Counts follow the policy: a
# vendor_mean clock fills every absent CpG into the predictor (used = present +
# imputed_full); anything else drops them (used = present, dropped = absent).
coverage_for <- function(cpgs, score_miss, norm_miss) {
  policy <- clock_impute(cpgs$clock_id)[["policy"]]
  n_absent <- length(cpgs$score_absent)
  fill <- identical(policy, "vendor_mean")
  coverage_record(
    cpgs,
    score_miss,
    norm_miss,
    used = length(cpgs$score_present) + if (fill) n_absent else 0L,
    imputed_full = if (fill) n_absent else 0L,
    dropped = if (fill) 0L else n_absent,
    policy = policy
  )
}

# alias per-sample miss: each row was scored by exactly one member (its sex's),
# so the row's count is that member's raw count. Panel counts do not route --
# the members' panels differ -- so the alias keeps a NULL coverage record. Aliases
# never normalize, so only the score panel is stitched.
stitch_routed_sample_miss <- function(alias, score_miss, female, sample_id) {
  miss <- rep(NA_integer_, length(sample_id))
  names(miss) <- sample_id
  if (is.null(female)) {
    return(miss)
  }
  route <- clock_routing(alias)
  rows <- list(female = which(female == 1), male = which(female == 0))
  for (key in names(rows)) {
    i <- rows[[key]]
    if (!length(i)) {
      next
    }
    sm <- score_miss[[as.character(route[[key]])]]
    if (!is.null(sm)) {
      miss[i] <- as.integer(sm)[i]
    }
  }
  miss
}

# full coverage structure for the compute sequence: per_clock records, and
# per-sample miss as list(score = <per clock>, norm = <per clock, NULL where the
# clock does not normalize>). Aliases keep a NULL record and a stitched score
# miss; routed members are masked to the samples they actually scored.
compute_coverage <- function(
  clock_sequence,
  cpg_list,
  DNAm,
  partial_cache,
  pheno
) {
  sample_id <- rownames(DNAm)
  routed <- sex_routed_members()
  is_alias <- vapply(
    clock_sequence,
    function(p) identical(clock_type(p), "sex_routed"),
    logical(1L)
  )
  seqi <- seq_along(clock_sequence)
  pidx <- cpg_list$panel_index

  # count each distinct panel's per-sample miss once, then fan out via the index
  score_part_miss <- lapply(
    pidx$score$parts,
    function(p) panel_sample_miss(p$present, DNAm, partial_cache)
  )
  norm_part_miss <- lapply(pidx$norm$parts, function(p) {
    if (!length(p$needed)) {
      NULL
    } else {
      panel_sample_miss(p$present, DNAm, partial_cache)
    }
  })

  per_clock <- stats::setNames(
    vector("list", length(clock_sequence)),
    clock_sequence
  )
  score_miss <- per_clock
  norm_miss <- per_clock

  # 1. record + per-panel miss for every non-alias clock
  for (i in seqi[!is_alias]) {
    id <- clock_sequence[[i]]
    sm <- score_part_miss[[pidx$score$idx[[i]]]]
    nm <- norm_part_miss[[pidx$norm$idx[[i]]]]
    score_miss[[id]] <- sm
    norm_miss[[id]] <- nm
    per_clock[[id]] <- coverage_for(cpg_list$per_clock[[id]], sm, nm)
  }

  female <- if (is.null(pheno)) NULL else as.numeric(pheno[["Female"]])

  # 2. aliases: stitch score-panel miss from raw member counts (before masking)
  for (i in seqi[is_alias]) {
    id <- clock_sequence[[i]]
    score_miss[[id]] <- stitch_routed_sample_miss(
      id,
      score_miss,
      female,
      sample_id
    )
  }

  # 3. mask routed members on the score panel (members never normalize): blank
  #    the rows a member did not score, so its kept record is only its samples
  if (!is.null(female)) {
    for (id in intersect(clock_sequence, names(routed$sex))) {
      applies <- if (identical(routed$sex[[id]], "female")) {
        female == 1
      } else {
        female == 0
      }
      applies[is.na(applies)] <- FALSE
      if (all(applies)) {
        next
      }
      sm <- score_miss[[id]]
      sm[!applies] <- NA_integer_
      score_miss[[id]] <- sm
      per_clock[[id]][["score_imputed_partial"]] <- sum(sm, na.rm = TRUE)
    }
  }

  list(
    per_clock = per_clock,
    sample_miss = list(score = score_miss, norm = norm_miss)
  )
}
