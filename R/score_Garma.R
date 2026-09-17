# garma: four squared-term models, and a router that keeps one per sample
score_Garma <- function(id, cpgs, block, results) {
  sample_id <- block[["sample_id"]]
  if (garma_reads_cpgs(id)) {
    step <- recipe_step_out_op(id, "score", "linear")
    return(score_matrix(step_linpred(id, step, cpgs, block), sample_id, id))
  }

  # inputs are scored first (sequence order): the router, then its branches
  step <- recipe_step_op(id, "route_by_score")
  inputs <- as.character(unlist(step[["inputs"]]))
  picked <- route_by_score(
    router = as.numeric(results[[inputs[[1L]]]]),
    branches = do.call(cbind, results[inputs[-1L]]),
    breaks = as.numeric(unlist(step[["breaks"]])),
    ties = as.character(unlist(step[["ties"]]))
  )
  score_matrix(picked, sample_id, id)
}

# a model reads betas. the router is assembled from its inputs' scores.
garma_reads_cpgs <- function(id) {
  !length(clock_depends_on(id))
}

# one branch per sample, by the breaks the router score lies above. a score at
# breaks[i] goes up only where ties[i] is "high".
route_by_score <- function(router, branches, breaks, ties) {
  k <- rep(1L, length(router))
  for (i in seq_along(breaks)) {
    at_break <- router == breaks[[i]] & identical(ties[[i]], "high")
    k <- k + (router > breaks[[i]] | at_break)
  }
  # a non-finite router lies in no bin: NA, never the first branch
  k[!is.finite(router)] <- NA_integer_
  branches[cbind(seq_along(k), k)]
}
