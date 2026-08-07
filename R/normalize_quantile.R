# quantile normalization to a target distribution, vendored from hhp94/betanorm.
# internal: calc_clocks() stays the only public reader of a beta matrix.

# no-missing-data port of preprocessCore::normalize.quantiles.use.target().
# each sample row is ranked onto `target` -- Bolstad equal-length indexing when
# length(target) == ncol(obj), linear quantile interpolation otherwise.
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
