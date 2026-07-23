# sex-routed alias: pick the member score matching each sample's sex
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
    as.numeric(r[["score"]])
  }

  female <- as.numeric(pheno[["Female"]])
  score_vec <- rep(NA_real_, n)
  rows <- list(female = which(female == 1), male = which(female == 0))
  for (key in names(rows)) {
    if (length(rows[[key]])) {
      score_vec[rows[[key]]] <- member_score(key)[rows[[key]]]
    }
  }

  list(
    score = score_matrix(score_vec, sample_id, id),
    coverage = NULL,
    sample_miss = NULL
  )
}

# blank wrong-sex rows on routed member columns
mask_routed_members <- function(results, clock_sequence, pheno) {
  routed <- sex_routed_members()
  ids <- intersect(clock_sequence, names(routed$sex))
  if (!length(ids) || is.null(pheno)) {
    return(results)
  }
  female <- as.numeric(pheno[["Female"]])

  for (id in ids) {
    applies <- if (identical(routed$sex[[id]], "female")) {
      female == 1
    } else {
      female == 0
    }
    applies[is.na(applies)] <- FALSE
    if (all(applies)) {
      next
    }
    results[[id]]$score[!applies, ] <- NA_real_
    results[[id]]$sample_miss[!applies] <- NA_integer_
    results[[id]]$coverage$score_imputed_partial <- sum(
      results[[id]]$sample_miss,
      na.rm = TRUE
    )
  }
  results
}
