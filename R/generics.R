# Result-record methods for class "mc_result" (stubs).

# cbind mc_result records after sample/batch gates. Not implemented yet.
# cbind.mc_result <- function(..., deparse.level = 1) {
#   stop("cbind.mc_result: not yet implemented")
# }

#' @export
rbind.mc_result <- function(...) {
  # TODO: some zscore clocks need to be recalculated.
}
