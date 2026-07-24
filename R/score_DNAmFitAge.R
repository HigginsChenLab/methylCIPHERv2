# DNAmFitAge_{Sex}: Klemera-Doubal mix of upstream member scores
score_DNAmFitAge <- function(id, results, DNAm) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  kdm <- fitage_kdm_params(id)

  comp_score <- function(component) {
    r <- results[[component]]
    if (is.null(r)) {
      cli::cli_abort(
        "{.val {id}} needs {.val {component}}, which was not scored upstream.",
        call = NULL
      )
    }
    as.numeric(r)
  }

  score_vec <- numeric(n)
  for (i in seq_len(nrow(kdm))) {
    cv <- comp_score(kdm[["component"]][i])
    score_vec <- score_vec +
      kdm[["weight"]][i] * (cv - kdm[["center"]][i]) / kdm[["scale"]][i]
  }

  score_matrix(score_vec, sample_id, id)
}
