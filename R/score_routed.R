# Sex-routed aliases: one callable clock over a pair of sex-resolved members.

# Each sample takes the score of the member matching its sex. Emits no coverage
# -- the two members' panels are near-disjoint and each applies to a different
# half of the cohort, so any aggregate over their union would describe no
# sample. Coverage stays on the members, which do have one panel per sample.
score_sex_routed <- function(id, results, DNAm, pheno) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)
  route <- clock_routing(id)

  member_score <- function(key) {
    member <- route[[key]]
    r <- results[[member]]
    if (is.null(r)) {
      stop(
        "score_sex_routed(): ",
        id,
        " needs member '",
        member,
        "' but it was not computed upstream.",
        call. = FALSE
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
    score = matrix(
      score_vec,
      nrow = n,
      ncol = 1L,
      dimnames = list(sample_id, id)
    ),
    coverage = NULL,
    sample_miss = NULL
  )
}

# Blank the rows a routed member does not apply to. Runs after every score is
# computed, so an alias and any downstream composite still read full columns;
# what changes is only the member column the caller sees, which must not show a
# plausible number for the wrong sex.
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
    # The partial-impute scalar is the sample-axis sum of what is left.
    results[[id]]$coverage$score_imputed_partial <- sum(
      results[[id]]$sample_miss,
      na.rm = TRUE
    )
  }
  results
}
