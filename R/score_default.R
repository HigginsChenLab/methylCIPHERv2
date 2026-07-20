# Scorers: one work unit -> list(score, coverage, sample_miss). calc_clocks() dispatches here on
# clock_type() (computation_type) and assembles the returned pieces into the methylCIPHER record.
# Only the linear engine lives here for now; the pack / transform / external scorers land later and
# will reuse linear_score() as their inner linear sub-step (detail-plan §2.2).

# Output-transform registry (detail-plan §2.3): maps the catalog `output_transform` NAME to the
# function applied to a clock's linear predictor. `linear` and `linear_transformed` are the SAME
# engine -- the ONLY difference is this transform, which is identity() for every plain-linear clock
# (so `linear` is just `linear_transformed` with identity, and linear_score applies it uniformly).
# anti.trafo is Horvath's age back-transformation (adult.age = 20, his published constant), shared
# verbatim by all 8 anti.trafo clocks; the catalog stores only the name, asserting they use the
# identical function. Source: dev/legacy/R-pre-rewrite.R (trafo / anti.trafo).
anti_trafo <- function(x, adult.age = 20) {
  ifelse(x < 0, (1 + adult.age) * exp(x) - 1, (1 + adult.age) * x + adult.age)
}

resolve_output_transform <- function(name) {
  switch(
    name,
    identity = function(x) x,
    anti.trafo = anti_trafo,
    stop(
      "Unknown output_transform '", name, "' -- add it to the registry in score.R.",
      call. = FALSE
    )
  )
}

# The shared linear engine (detail-plan §2.3). Scores ONE cpg_coefficient clock of computation_type
# `linear` OR `linear_transformed` -- they are the same engine, differing only in the output transform:
#
#   score_i = output_transform( intercept + sum_j coef_j * beta_ij  (+ covariate terms) )
#
# output_transform is identity() for plain `linear` clocks (a no-op) and anti.trafo (Horvath age
# back-transform) for the `linear_transformed` age clocks -- resolved from the catalog per clock.
#
# Inputs are the already-prepared per-call context, NOT raw user args (calc_clocks did the front end):
#   cpgs          one element of resolve_cpgs()$per_clock -- the clock's CpG skeleton: $clock_id,
#                 $score_needed/$score_present/$score_absent, $norm_needed/$norm_present. All set
#                 math is done; $score_present already excludes off-panel AND all-NA columns (§2.3a).
#   DNAm          raw n x p matrix, rownames = sample_id. Never mutated here.
#   partial_cache NULL, or the shared n x k cohort-filled cache (colnames = the present-but-partial-NA
#                 CpGs). A scoring CpG that is a column here reads its COHORT-filled value; every other
#                 present CpG reads raw DNAm. This is where partial-NA (cohort) fill is consumed --
#                 build_partial_cache() produced it once for the whole call (§2.3a).
#   pheno         NULL, or the aligned covariate table (sample_id order) -- only touched when the clock
#                 carries covariate coefficients.
#
# Missingness fork (§2.3, never crossed): PRESENT-but-NA -> cohort (the cache, above). COMPLETELY
# ABSENT -> vendor fill or drop, by the clock's `imputation$policy`. Only `omit`/`drop` (drop the term)
# is implemented; vendor fill is gated -- a vendor-policy clock with 0 absent CpGs scores identically
# (nothing to fill), so it proceeds; one WITH absent CpGs raises a clear not-yet-implemented error
# rather than silently dropping terms it was meant to fill.
#
# Returns list(
#   score        n x 1 double matrix, colnames = clock_id, rownames = sample_id
#   coverage     tier-1 aggregate row (detail-plan §4.1): counts + missing_cpgs char vector
#   sample_miss  length-n named integer vector, tier-2 (§4.2): per-sample partial-NA count over this
#                clock's present scoring CpGs, on the RAW subset before the cache fill.
# )
# Numeric core shared by linear_score() (whole standalone clocks/surrogates) and score_grimage()
# (the V2 `_internal` surrogates computed inline). Forms the linear predictor
#
#   linpred_i = intercept + sum_j coef_j * beta_ij  (+ covariate terms)
#
# honoring the missingness fork WITHOUT deciding it: `score_present` is the ALREADY-resolved present
# scoring CpG set (absent CpGs excluded by the caller's omit/vendor logic), and `partial_cache`
# supplies cohort-filled values for whichever present CpGs are partial-NA (the rest read raw DNAm).
# Returns the numeric pieces only -- the OUTPUT TRANSFORM and coverage assembly stay with the callers
# (linear_score applies the clock's identity/anti.trafo; score_grimage stacks the surrogate columns
# and applies grimage_rescale). `id` is used only in the covariate error message.
#
# Returns list(
#   linpred      n x 1 double matrix (no dimnames)
#   used_cols    the present CpGs actually multiplied in, in c(cached, raw) order
#   cached       the subset of used_cols read from the cohort cache (the partial-NA columns)
# )
linear_predictor <- function(
  coef,
  intercept,
  cov_coefs,
  score_present,
  DNAm,
  partial_cache = NULL,
  pheno = NULL,
  id = "<component>"
) {
  n <- nrow(DNAm)

  # present scoring CpGs: cohort-cache columns vs raw columns. Canonical order c(cache, raw); coef is
  # reordered to match so the %*% lines up by name.
  cached <- if (is.null(partial_cache)) {
    character(0)
  } else {
    intersect(score_present, colnames(partial_cache))
  }
  raw <- setdiff(score_present, cached)
  used_cols <- c(cached, raw)

  if (length(used_cols)) {
    sub <- cbind(
      partial_cache[, cached, drop = FALSE],
      DNAm[, raw, drop = FALSE]
    )
    cpg_contrib <- sub %*% coef[used_cols]
  } else {
    cpg_contrib <- matrix(0, nrow = n, ncol = 1L) # nothing present -> only intercept/covariates
  }

  # covariate terms (e.g. GrimAge surrogates carry an Age coefficient)
  cov_contrib <- 0
  if (length(cov_coefs)) {
    need <- names(cov_coefs)
    if (is.null(pheno) || !all(need %in% names(pheno))) {
      stop(
        "linear_predictor(): '",
        id,
        "' needs covariate(s) ",
        paste(need, collapse = ", "),
        " but they are absent from `pheno`.",
        call. = FALSE
      )
    }
    cov_mat <- as.matrix(pheno[, need, drop = FALSE])
    cov_contrib <- cov_mat %*% cov_coefs[need]
  }

  linpred <- cpg_contrib + cov_contrib + intercept
  list(linpred = linpred, used_cols = used_cols, cached = cached)
}

linear_score <- function(cpgs, DNAm, partial_cache = NULL, pheno = NULL) {
  id <- cpgs$clock_id
  policy <- clock_impute(id)$policy
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  # --- absent CpGs: drop (omit) or vendor-fill (gated, not yet implemented) ---
  absent <- cpgs$score_absent
  if (length(absent) && !policy %in% c("omit", "drop")) {
    stop(
      "linear_score(): clock '",
      id,
      "' has imputation policy '",
      policy,
      "', which vendor-fills ",
      length(absent),
      " absent CpG(s), but vendor imputation is not implemented yet. ",
      "Pass a DNAm matrix that carries these CpGs (they score fine when present).",
      call. = FALSE
    )
  }
  dropped <- absent # omit/drop path: absent terms contribute zero
  vendor_filled <- character(0)

  lp <- linear_predictor(
    coef = clock_coefs(id), # named numeric over score_needed
    intercept = clock_intercept(id),
    cov_coefs = clock_covariate_coefs(id), # {name: coef}; numeric(0) when none
    score_present = cpgs$score_present,
    DNAm = DNAm,
    partial_cache = partial_cache,
    pheno = pheno,
    id = id
  )

  # the clock's output transform (identity for plain-linear; anti.trafo for the Horvath-family age
  # clocks). This single line is the whole `linear` vs `linear_transformed` split.
  transform <- resolve_output_transform(clock_output_transform(id))
  score <- matrix(
    as.numeric(transform(lp$linpred)),
    nrow = n,
    ncol = 1L,
    dimnames = list(sample_id, id)
  )

  # --- tier-2: per-sample partial-NA count over present scoring CpGs (raw, pre-fill; §4.2) ---
  # Only the cached (partial-NA) columns can carry an NA; clean present columns add 0 to every sample.
  sample_miss <- if (length(lp$cached)) {
    slideimp::mat_miss(DNAm[, lp$cached, drop = FALSE], col = FALSE)
  } else {
    integer(n)
  }
  names(sample_miss) <- sample_id

  # --- tier-1: per-clock aggregate coverage (§4.1) ---
  coverage <- list(
    clock_id = id,
    policy = policy,
    score_needed = length(cpgs$score_needed),
    score_present = length(cpgs$score_present),
    score_used = length(lp$used_cols) + length(vendor_filled),
    score_imputed_partial = sum(sample_miss), # cells filled from cohort cache (= sum over samples)
    score_imputed_full = length(vendor_filled), # absent probes vendor-filled (0 until implemented)
    score_dropped = length(dropped),
    norm_needed = length(cpgs$norm_needed),
    norm_present = length(cpgs$norm_present),
    missing_cpgs = absent
  )

  list(score = score, coverage = coverage, sample_miss = sample_miss)
}
