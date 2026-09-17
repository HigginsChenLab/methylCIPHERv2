# cAge: an age model and a log(age) model, each with squared terms, and a
# router that keeps one per sample by the age model's score
score_cAge <- function(id, cpgs, block, results) {
  sample_id <- block[["sample_id"]]
  if (!cage_reads_cpgs(id)) {
    # inputs are scored first (sequence order): the router, then its branches
    step <- recipe_step_op(id, "route_by_score")
    inputs <- as.character(unlist(step[["inputs"]]))
    picked <- route_by_score(
      router = as.numeric(results[[inputs[[1L]]]]),
      branches = do.call(cbind, results[inputs[-1L]]),
      breaks = as.numeric(unlist(step[["breaks"]])),
      ties = as.character(unlist(step[["ties"]]))
    )
    return(score_matrix(picked, sample_id, id))
  }

  lin <- recipe_step_op(id, "linear")
  score <- step_linpred(id, lin, cpgs, block)
  # the log(age) model declares its way back to years
  if (!identical(as.character(lin[["out"]]), "score")) {
    back <- recipe_step_out_op(id, "score", "transform")
    if (!identical(as.character(back[["in"]]), as.character(lin[["out"]]))) {
      catalog_bug("%s: the score transform does not read the linear step.", id)
    }
    score <- step_transform(back, score)
  }
  score_matrix(score, sample_id, id)
}

# a model reads betas. the router is assembled from its inputs' scores.
cage_reads_cpgs <- function(id) {
  !length(clock_depends_on(id))
}
