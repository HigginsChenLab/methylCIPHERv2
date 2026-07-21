# Result-record methods for class "methylCIPHER" (stubs).
# Identity: rownames(DNAm) are sample_id; positional records refuse cbind.
# cbind gates: no positional_ids, equal sample set, agreeing covariates, equal batch_set_id.

# cbind methylCIPHER records after sample/batch gates. Not implemented yet.
# cbind.methylCIPHER <- function(..., deparse.level = 1) {
#   stop("cbind.methylCIPHER: not yet implemented")
# }

#' @export
rbind.methylCIPHER <- function(...) {
  # TODO: some zscore clocks need to be recalculated.
}
