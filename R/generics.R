# Result-record methods for class "methylCIPHER".
# STUBS ONLY — bodies land later. This file reserves the verb surface and the identity contract.

# rownames(DNAm) is the canonical sample_id. Rowname-less DNAm gets positional ids (sample1..N);
# those records are flagged positional_ids and cbind refuses them. pheno is a covariate side-table
# aligned onto sample_id, never the identity. The record stays scores-only.
#
# cbind gates: (0) refuse positional_ids, (1) equal sample_id set (reorder if needed),
# (2) shared covariates agree per sample, (3) batch_set_id equal when batch-dependent.

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
#   # TODO: positional guard, sample_id gate, batch_set_id gate, then cbind scores.
#   stop("cbind.methylCIPHER: not yet implemented")
# }

rbind.methylCIPHER <- function(...) {
  # TODO some zscore clocks needs to be recalculated.
}
