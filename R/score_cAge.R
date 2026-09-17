# cAge: an age model and a log(age) model, each with squared terms. the age
# model's score picks which of the two is kept.
score_cAge <- function(id, cpgs, block, results) {
  pick <- recipe_step_op(id, "threshold_select")
  operands <- as.character(unlist(pick[["internal"]]))
  # the second operand is the log(age) model, back-transformed to years
  back <- recipe_step_out_op(id, operands[[2L]], "transform")
  age_step <- recipe_step_out_op(id, operands[[1L]], "linear")
  log_step <- recipe_step_out_op(id, back[["in"]], "linear")

  age <- step_linpred(id, age_step, cpgs, block)
  years <- step_transform(back, step_linpred(id, log_step, cpgs, block))
  score_matrix(
    threshold_select(age, years, as.numeric(pick[["threshold"]])),
    block[["sample_id"]],
    id
  )
}

# a where it clears the threshold, else b. strict, so a tie takes b.
threshold_select <- function(a, b, threshold) {
  ifelse(a > threshold, a, b)
}
