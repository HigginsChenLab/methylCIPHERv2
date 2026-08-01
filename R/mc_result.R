# mc_result record: constructor + methods for class "mc_result"

# batch label is a hash of the pheno id column. same ids always get the same label
batch_hash <- function(ids) {
  # hash the id set, not the sequence or r representation
  key <- paste0(
    sort(unname(as.character(ids)), method = "radix"),
    collapse = "\r"
  )
  digest::digest(key, algo = "xxhash64", serialize = FALSE)
}

# the record's distinct batch labels. every multi-batch-only decision reads this
# one definition -- print.mc_result and all four exit frames -- so they cannot
# disagree about how many batches a record has
batch_labels <- function(x) {
  unique(x[["provenance"]][[MC_BATCH]])
}

# does the batch label carry anything? the one multi-batch test. a frame may
# read it to decline building the column (shape_scores) or to drop it after the
# fact (drop_single_batch) -- either way there is one statement of the rule
is_multi_batch <- function(batch) {
  length(unique(batch)) > 1L
}

# at one batch the label is a single repeated hash, so it says nothing and every
# exit frame drops it. batch is provenance's per-sample vector at every call
# site: the two coverage frames must never disagree about whether the key is there
drop_single_batch <- function(df, batch) {
  if (is_multi_batch(batch)) {
    return(df)
  }
  # a no-op where the column was never built -- still the gate every exit runs
  df[[MC_BATCH]] <- NULL
  df
}

# n x length(ids) per-sample miss matrix (NULL entry -> NA)
miss_matrix <- function(miss_list, ids, sample_id) {
  m <- matrix(
    NA_integer_,
    nrow = length(sample_id),
    ncol = length(ids),
    dimnames = list(sample_id, ids)
  )
  for (id in ids) {
    v <- miss_list[[id]]
    if (!is.null(v)) {
      m[, id] <- v
    }
  }
  m
}

# stack scorer outputs into an mc_result record
construct_mc_result <- function(
  results,
  coverage,
  output_ids,
  requested_ids,
  sample_id,
  pheno,
  pheno_id,
  covariates_used,
  normalized,
  scoring_failures = list(),
  pending = list()
) {
  scores <- do.call(cbind, results[output_ids])
  dimnames(scores) <- list(sample_id, output_ids)

  # derived, never passed in: the id column is the batch's whole identity
  batch <- batch_hash(pheno[[pheno_id]])

  # coverage spans clocks that read cpgs. pure composites are in none of them
  per_clock <- coverage[["per_clock"]]
  record_ids <- covered_ids(per_clock)
  # normalizers from the record's normalizes flag
  norm_ids <- record_ids[vapply(
    record_ids,
    function(id) isTRUE(per_clock[[id]][["normalizes"]]),
    logical(1L)
  )]
  sample_miss <- list(
    score = miss_matrix(
      coverage[["sample_miss"]][["score"]],
      record_ids,
      sample_id
    ),
    norm = miss_matrix(coverage[["sample_miss"]][["norm"]], norm_ids, sample_id)
  )

  structure(
    list(
      scores = scores,
      pheno = pheno,
      coverage = list(
        # batch -> clock -> record. one fill regime per batch
        per_clock = stats::setNames(list(per_clock), batch),
        sample_miss = sample_miss
      ),
      provenance = list(
        sample_id = sample_id,
        # per-sample, aligned to sample_id (never a key -- see rbind)
        mc_batch_id = rep(batch, length(sample_id)),
        pheno_id = pheno_id,
        clocks = output_ids,
        requested = requested_ids,
        dependencies = setdiff(output_ids, requested_ids),
        covariates_used = covariates_used,
        # which clocks were actually normalized
        normalized = normalized,
        # clock id -> sample ids the scorer could not fit
        scoring_failures = scoring_failures,
        # retained per-sample intermediates, so a bind can re-finalize exactly
        pending = pending
      )
    ),
    class = "mc_result"
  )
}

# scores then pheno, in the shared printer grammar (R/print.R)
#' @export
print.mc_result <- function(x, n = 6, p = 6, ...) {
  scores <- x[["scores"]]
  pheno <- x[["pheno"]]

  cat(
    fmt_header("mc_result", nrow(scores), "sample", ncol(scores), "clock"),
    "\n",
    sep = ""
  )
  print_block(
    "scores",
    scores,
    min(n, nrow(scores)),
    min(p, ncol(scores)),
    "clock"
  )
  # always present -- the id column at minimum (see resolve_pheno)
  print_block(
    "pheno",
    pheno,
    min(n, nrow(pheno)),
    ncol(pheno),
    "column",
    cut_cols = FALSE
  )

  # multi-batch only, on the same test the exit frames use. a single-pass record
  # has nothing new to say here
  labels <- batch_labels(x)
  if (length(labels) > 1L) {
    cat(
      "\n",
      fmt_section("provenance", plural_count(length(labels), "batch", "es")),
      "\n",
      paste(labels, collapse = ", "),
      "\n",
      sep = ""
    )
  }

  invisible(x)
}

# naked scores (coverage and provenance stay on the record)
#' @export
as.matrix.mc_result <- function(x, ...) {
  x[["scores"]]
}
