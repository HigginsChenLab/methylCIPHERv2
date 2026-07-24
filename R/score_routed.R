# sex-routed alias: pick the member score matching each sample's sex. The
# alias's per-sample miss is stitched the same way in compute_coverage; here we
# only build the score column.
score_sex_routed <- function(id, results, DNAm, pheno) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)
  route <- clock_routing(id)

  member_score <- function(key) {
    member <- route[[key]]
    r <- results[[member]]
    if (is.null(r)) {
      cli::cli_abort(
        "{.val {id}} needs member {.val {member}}, which was not scored
         upstream.",
        call = NULL
      )
    }
    r
  }

  female <- as.numeric(pheno[["Female"]])
  score_vec <- rep(NA_real_, n)
  rows <- list(female = which(female == 1), male = which(female == 0))
  for (key in names(rows)) {
    i <- rows[[key]]
    if (!length(i)) {
      next
    }
    score_vec[i] <- as.numeric(member_score(key))[i]
  }

  score_matrix(score_vec, sample_id, id)
}

# routed members are internal: scored and kept for coverage, never a column
drop_routed_members <- function(ids) {
  setdiff(ids, names(sex_routed_members()$sex))
}
