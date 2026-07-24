# result-record methods for class "mc_result"

# rbind is refused -- re-run calc_clocks() on the combined DNAm instead
#' @export
rbind.mc_result <- function(...) {
  cli::cli_abort(
    c(
      "{.cls mc_result} records cannot be {.fn rbind}-ed.",
      "i" = "Re-run {.fn calc_clocks} on the combined DNAm -- batch-dependent
             clocks must see all samples at once."
    ),
    call = NULL
  )
}
