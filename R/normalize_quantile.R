# quantile norm to a target (vendored from hhp94/betanorm; internal).

# Port of preprocessCore::normalize.quantiles.use.target(); rank each row onto target.
quantile_norm <- function(obj, target) {
  checkmate::assert_matrix(
    obj,
    mode = "numeric",
    any.missing = FALSE,
    min.rows = 1L,
    min.cols = 1L
  )
  checkmate::assert_numeric(
    target,
    any.missing = FALSE,
    min.len = 1L,
    finite = TRUE,
    .var.name = "target"
  )
  qnorm_target_rows_cpp(obj, target)
}
