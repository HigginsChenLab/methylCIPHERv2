# ensaya: row mean of its input clocks' scores (scored first, sequence order)
score_Ensaya <- function(id, cpgs, block, results) {
  inputs <- stack_operands(stack_step(id))
  na_rm <- isTRUE(recipe_step_op(id, "row_mean")[["na_rm"]])
  stacked <- do.call(cbind, results[inputs])
  score_matrix(rowMeans(stacked, na.rm = na_rm), block[["sample_id"]], id)
}
