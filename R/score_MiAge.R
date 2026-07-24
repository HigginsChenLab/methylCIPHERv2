# MiAge: multi-start L-BFGS-B mitotic age over n in [10, 10000]

MIAGE_LOWER <- 10
MIAGE_UPPER <- 10000

# four interior starts plus author default 500
MIAGE_STARTS <- c(
  MIAGE_LOWER + seq_len(4L) * (MIAGE_UPPER - MIAGE_LOWER) / 5,
  500
)

# best multi-start fit for one sample
miage_fit <- function(betaj, b, c, d) {
  objective <- function(n) sum((c + b^(n - 1) * d - betaj)^2)
  gradient <- function(n) {
    2 * sum((c + b^(n - 1) * d - betaj) * b^(n - 1) * log(b) * d)
  }

  fits <- lapply(MIAGE_STARTS, function(start) {
    stats::optim(
      par = start,
      fn = objective,
      gr = gradient,
      method = "L-BFGS-B",
      lower = MIAGE_LOWER,
      upper = MIAGE_UPPER,
      control = list(factr = 1)
    )
  })
  fits[[which.min(vapply(fits, function(f) f$value, numeric(1)))]]$par
}

score_MiAge <- function(id, cpgs, DNAm, partial_cache = NULL) {
  sample_id <- rownames(DNAm)
  n <- nrow(DNAm)

  params <- miage_params(id)
  present <- cpgs$score_present
  cached <- cached_cols(present, partial_cache)
  betas <- DNAm[, present, drop = FALSE]
  if (length(cached)) {
    betas[, cached] <- partial_cache[, cached]
  }

  b <- params$b[present]
  cc <- params$c[present]
  d <- params$d[present]
  score_matrix(
    vapply(seq_len(n), function(i) miage_fit(betas[i, ], b, cc, d), numeric(1)),
    sample_id,
    id
  )
}
