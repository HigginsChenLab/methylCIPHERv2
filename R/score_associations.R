# Advisory age-association check: a cohort's observed score-age correlation
# against the shipped per-clock reference (DECISIONS 2026-08-02).

MIN_ASSOC_N <- 5L

# below this reference |r| the expected sign carries no information
SIGN_FLAG_MIN_R <- 0.3

ASSOC_COLS <- c(
  "clock_id",
  "n",
  "obs_age_r",
  "exp_age_r",
  "exp_lo",
  "exp_hi",
  "outside",
  "wrong_sign"
)

mc_clock_reference <- function() {
  path <- system.file(
    "extdata",
    "clock_reference.csv",
    package = "methylCIPHERv2"
  )
  if (!nzchar(path) || !file.exists(path)) {
    return(NULL)
  }
  utils::read.csv(path, stringsAsFactors = FALSE)
}

assoc_age <- function(x, age) {
  n <- nrow(x[["scores"]])
  if (is.null(age)) {
    pheno <- x[["pheno"]]
    if (!("Age" %in% names(pheno))) {
      stop(
        "No age to correlate against. Pass age = <numeric vector>, or score ",
        "with a pheno carrying an Age column.",
        call. = FALSE
      )
    }
    age <- pheno[["Age"]]
  }
  age <- suppressWarnings(as.numeric(age))
  if (length(age) != n) {
    stop(
      sprintf(
        "age has %d value(s); the record has %d sample(s).",
        length(age),
        n
      ),
      call. = FALSE
    )
  }
  age
}

assoc_row <- function(id, v, age, r) {
  ok <- is.finite(v) & is.finite(age)
  if (sum(ok) < MIN_ASSOC_N) {
    return(NULL)
  }
  if (stats::sd(v[ok]) == 0 || stats::sd(age[ok]) == 0) {
    return(NULL)
  }
  obs <- stats::cor(v[ok], age[ok])
  lo <- r[["age_r_lo"]]
  hi <- r[["age_r_hi"]]
  exp_r <- r[["age_r"]]
  data.frame(
    clock_id = id,
    n = sum(ok),
    obs_age_r = round(obs, 3),
    exp_age_r = exp_r,
    exp_lo = lo,
    exp_hi = hi,
    outside = isTRUE(is.finite(lo) && is.finite(hi) && (obs < lo || obs > hi)),
    wrong_sign = isTRUE(
      is.finite(exp_r) &&
        abs(exp_r) > SIGN_FLAG_MIN_R &&
        sign(obs) != sign(exp_r)
    ),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

assoc_empty <- function() {
  out <- data.frame(
    clock_id = character(0),
    n = integer(0),
    obs_age_r = numeric(0),
    exp_age_r = numeric(0),
    exp_lo = numeric(0),
    exp_hi = numeric(0),
    outside = logical(0),
    wrong_sign = logical(0),
    stringsAsFactors = FALSE
  )
  out[ASSOC_COLS]
}

#' Stub
#'
#' Rcpp needs some roxygen2 stub
#'
#' @param x x
#' @param age x
#' @param ref x
#'
#' @returns x
#' @export
score_associations <- function(x, age = NULL, ref = mc_clock_reference()) {
  check_mc_result(x)
  if (is.null(ref)) {
    stop(
      "No clock reference table installed with methylCIPHERv2.",
      call. = FALSE
    )
  }
  x <- finalized(x)
  scores <- x[["scores"]]
  age <- assoc_age(x, age)

  ids <- intersect(colnames(scores), ref[["clock"]])
  rows <- lapply(ids, function(id) {
    assoc_row(id, scores[, id], age, ref[match(id, ref[["clock"]]), ])
  })
  out <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(out)) {
    return(assoc_empty())
  }
  # widest gap between observed and expected first
  out <- out[order(out[["obs_age_r"]] - out[["exp_age_r"]]), , drop = FALSE]
  rownames(out) <- NULL
  out
}
