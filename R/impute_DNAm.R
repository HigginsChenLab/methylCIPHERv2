# Missingness front end + imputation primitives (detail-plan §2.3 / §2.3a). Numeric machinery lives
# here; the PURE per-clock CpG resolution is resolve_cpgs() in resolve_inputs.R. The load-bearing
# invariant throughout: partial NA (present-but-NA) is a COHORT source, completely-absent is a VENDOR
# source, and the two are never crossed (§2.3).

# One numeric pre-pass over DNAm, run ONCE in calc_clocks(), gated by a single anyNA(). Produces the
# usable-column universe for resolve_cpgs() and the partial-NA column set the cache is built from, and
# HARD-ERRORS on fully-empty samples. When DNAm has no NA at all the body is skipped: usable = the
# needed present columns, no partial columns, nothing to throw. This is the common case (pre-handled
# betas), so the anyNA gate keeps it a single cheap boolean.
#
# `needed_cpgs` (needed_cpgs_union(): scoring + norm CpGs any planned clock needs) BOUNDS the column
# work. The per-column classification only ever feeds imputation (partial -> cache) and coverage
# (all-NA -> absent), and both are per-clock over needed sets, so a probe no clock scores is never
# consulted -- scanning it on a 450k/850k panel is wasted. We narrow to `present_needed` (needed AND on
# the panel) and classify only those columns; the rest of the panel is left untouched. The one thing
# that stays full-width is the empty-SAMPLE row scan below (a sample is dead only if ALL its CpGs --
# not just the needed ones -- are NA).
#
# Column classification via mat_miss(col = TRUE) over the narrowed sub-matrix (per-column NA counts):
#   0            fully observed  -> usable, no cache entry
#   1 .. nrow-1  partial NA       -> usable, cache candidate (cohort-filled in build_partial_cache)
#   nrow         ALL-NA present   -> reclassified ABSENT (0 observed -> no cohort mean; == a probe off
#                                    the panel). Dropped from usable_cols by a name setdiff, so it
#                                    routes to the vendor/drop path and counts in n_cpg_score_miss (§4.1).
#
# Empty-row throw (mat_miss(col = FALSE); row_miss == ncol): an all-NA sample cannot be scored, and --
# the reason it is an ERROR not a warning -- cohort-mean imputation would otherwise fill its every
# cached cell with the column mean and emit a plausible-looking FABRICATED score instead of an honest
# NA. (An all-NA row is isnan-skipped in every column mean, so it never biases other samples; the
# damage is confined to its own fake score, but that suffices to refuse it.) No permissive dial --
# unlike rowname-less DNAm (§5.1 allow_positional_ids), empty rows are always fatal.
scan_missing_cpgs <- function(DNAm, needed_cpgs) {
  cols <- colnames(DNAm)
  # the only columns whose NA-state can matter: needed by some clock AND actually on the panel.
  present_needed <- intersect(needed_cpgs, cols)
  out <- list(
    has_na = FALSE,
    usable_cols = present_needed, # clean case: every needed present column is scorable
    partial_na_cols = character(0),
    all_na_cols = character(0)
  )
  if (!anyNA(DNAm)) {
    return(out) # dominant common case: no NA anywhere -> no partial fill, no empty rows
  }

  nr <- nrow(DNAm)

  # empty samples first: refuse before any imputation can fabricate a score for them. This IS full
  # width -- "no observed CpGs" means across the whole panel, not merely the needed subset.
  row_miss <- slideimp::mat_miss(DNAm, col = FALSE)
  dead <- rownames(DNAm)[row_miss == ncol(DNAm)]
  if (length(dead)) {
    stop(
      "DNAm has ",
      length(dead),
      " sample(s) with no observed CpGs (all NA): ",
      paste(utils::head(dead, 10L), collapse = ", "),
      if (length(dead) > 10L) ", ..." else "",
      ". Remove or fix these samples before scoring.",
      call. = FALSE
    )
  }

  # three-way column split from one pass -- but ONLY over the needed present columns. Subsetting to
  # `present_needed` bounds the scan (and the allocated sub-matrix) to clock width instead of the full
  # panel; the discarded columns were classified and thrown away before. `present_needed` may be empty
  # (nothing needed is on the panel) -> col_miss is length 0, both splits empty, usable stays as is.
  # worst case is 120k cpg for SystemsAge
  sub <- DNAm[, present_needed, drop = FALSE]
  col_miss <- slideimp::mat_miss(sub, col = TRUE)
  all_na <- present_needed[col_miss == nr]
  partial <- present_needed[col_miss > 0 & col_miss < nr]

  out$has_na <- TRUE
  out$all_na_cols <- all_na
  out$partial_na_cols <- partial
  out$usable_cols <- setdiff(present_needed, all_na) # all-NA needed -> vendor/drop path
  out
}

# Build the shared partial-NA cohort cache: ONE n x k matrix of the present scoring CpGs that carry a
# partial NA, with those NAs filled by column mean (mean over each probe's observed samples). Computed
# once per call so a CpG shared across many clocks (rife in the component families) is cohort-imputed a
# single time -- and every scorer that needs it reads the IDENTICAL filled column, a consistency
# guarantee, not only a speed win (DECISIONS 2026-07-18).
#
# `cache_cpgs` must already be intersect(resolve_cpgs()$present_needed_union, scan$partial_na_cols):
# present (a cohort mean exists), needed by some clock (don't cache dead columns), and actually partial
# (something to fill). Empty -> NULL (no NA touched any needed CpG; scorers read raw DNAm).
#
# Subset-first is load-bearing: slideimp::mean_imp_col() returns a matrix the SAME width as its input
# (untouched columns are memcpy'd), so calling it on the full panel would allocate a second n x p copy
# -- the §3 spike. Narrowing to cache_cpgs first bounds the cache to the handful of partial-NA needed
# probes (empty in the clean case). Every column here is partial by construction, so mean_imp_col's
# "0 observed -> unchanged" and "no NA -> unchanged" branches never fire in our path. Non-destructive:
# raw DNAm is never mutated.
build_partial_cache <- function(DNAm, cache_cpgs, cores = 1L) {
  if (!length(cache_cpgs)) {
    return(NULL)
  }
  sub <- DNAm[, cache_cpgs, drop = FALSE] # bounded realize (the copy a scorer subset pays anyway)
  slideimp::mean_imp_col(sub, cores = cores)
}

# The single fill-APPLICATION primitive (detail-plan §2.3 "imputation lives in one place"). Given a
# per-clock scoring subset and values the caller already resolved, write them in. It does not DECIDE
# sources -- keeping partial=cohort / absent=vendor from ever crossing is the caller's job; this only
# applies values. TODO(next layer): finalize signature once linear_score() is written -- expected to
# take the raw per-clock subset, the shared partial_cache (cohort columns to swap in), and the vendor
# fill (absent CpGs + their ref values, sex-keyed via Female). Returns the completed scoring matrix.
impute_DNAm <- function(DNAm, impute_cpgs, impute_values) {}
