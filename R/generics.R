# Result-record methods for class "methylCIPHER" (detail-plan §1.3 method table).
# STUBS ONLY — bodies land later. This file reserves the verb surface and records
# the sample-identity / alignment contract the methods must honor.

# ===========================================================================
# Sample identity & alignment contract
# ===========================================================================
# rownames(DNAm) is the canonical sample_id: unique, and preferred. Identity-less DNAm is NOT a
# hard error by default -- calc_clocks() stamps positional ids (sample1..N) inline so less-defensive
# workflows can score by row order. But positional
# ids are NOT comparable across separate matrices, so such records are flagged
# $provenance$positional_ids = TRUE and cbind() REFUSES them (gate 0 below). That keeps the cbind
# footgun closed at the bind step instead of at the front door. allow_positional_ids = FALSE on
# calc_clocks() restores the strict hard-error contract. Real rownames are what enable binding.
#
# sample_id is derived ONCE, stamped on $provenance$sample_id, and used as
# rownames($scores). pheno is NEVER the identity -- it is a covariate side-table
# aligned onto sample_id. pheno_id (the id column name) ALWAYS has a default; only
# `pheno` itself may be NULL.
#
#   pheno = NULL  -> sample_id = rownames(DNAm)
#   pheno given   -> require pheno[[pheno_id]] present, UNIQUE, non-missing, AND
#                    rownames(DNAm) ⊆ pheno[[pheno_id]]; else error, naming the
#                    missing ids. No unique(pheno) dedup -- duplicate ids are the
#                    caller's error.
#
# When pheno is given it is subset + reordered to rownames(DNAm) order INTERNALLY
# (prepare_inputs). The record stays scores-only (detail-plan §1.3).
# `as.data.frame()` surfaces sample_id under the `pheno_id` name beside the scores.
#
# ---------------------------------------------------------------------------
# cbind(a, b, ...) gating -- a positional guard then THREE independent checks:
#   (0) positional-id guard -- if ANY record has $provenance$positional_ids = TRUE, throw. Its
#         sample1..N ids are row-order artifacts, not real identity, so set/order comparison
#         against another matrix is meaningless. Score positional records fine; just don't bind
#         them. Give real rownames to opt back into binding.
#   (1) sample_id SET
#         - sets differ                -> throw (different samples)
#         - equal set, same order      -> bind directly
#         - equal set, different order -> reorder later records to the first
#                                         record's sample_id order, re-verify
#                                         identical(sample_id), then bind
#   (2) covariate consistency -- PER COVARIATE, only for covariates SHARED by >1 record
#         - trigger: a covariate appears in `covariates_used` of more than one record.
#           Then its per-sample values (keyed by sample_id) must agree across those
#           records -- same Age/Female bound to the same sample. Reorder in (1) makes
#           this order-invariant.
#         - moot when: only one side carries covariates, OR both carry covariates but
#           they are DISJOINT (different covariates -> nothing shared to compare). A
#           covariate used by exactly one record is never checked.
#         - hashes each shared covariate keyed by sample_id; never the whole pheno
#           table (§12 non-goal).
#   (3) batch_set_id (§6) -- required equal for any batch-dependent column; a hash of
#       the sample SET, invariant to (1)'s reorder; mismatch -> throw.
# ===========================================================================

#' Column-bind methylCIPHER score records
#'
#' Binds score columns of two or more `methylCIPHER` records after gating on the
#' sample-identity + batch contract above. Merges `$scores` (cbind), `$coverage`
#' (row-append), and `$provenance` (union of clocks; shared sample_id).
#'
#' @param ... `methylCIPHER` records.
#' @param deparse.level passed through for `cbind` signature compatibility.
#' @return a `methylCIPHER` record.
#' @export
# cbind.methylCIPHER <- function(..., deparse.level = 1) {
#   # TODO (per contract above + detail-plan §1.3/§5/§7):
#   #   0. positional-id guard: throw if any record has $provenance$positional_ids = TRUE.
#   #   1. collect records from `...`; validate all are methylCIPHER.
#   #   2. sample_id gate: throw on set mismatch; reorder+recheck on order-only diff.
#   #   3. batch_set_id gate (§6) for batch-dependent columns.
#   #   4. cbind $scores; row-append $coverage; union clock provenance.
#   #   5. reassemble -> methylCIPHER record.
#   stop("cbind.methylCIPHER: not yet implemented")
# }

rbind.methylCIPHER <- function(...) {
  # TODO some zscore clocks needs to be recalculated.
}
