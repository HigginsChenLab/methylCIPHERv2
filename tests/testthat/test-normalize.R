# normalize=: per-clock normalization decision, resolved before any DNAm read

GOLD <- clock_norm_target("Horvath1")

# bmiq needs multi-modal input -- jitter the gold standard, not U(0,1).
# `background` thins the gold panel to scoring panel plus that many background probes.
methylation_betas <- function(gold = GOLD, n = 4L, background = NULL) {
  panel <- names(gold)
  if (!is.null(background)) {
    score <- clock_scoring_cpgs("Horvath1")
    panel <- c(score, setdiff(panel, score)[seq_len(background)])
  }
  m <- matrix(
    rep(as.numeric(gold[panel]), each = n),
    nrow = n,
    dimnames = list(paste0("sample", seq_len(n)), panel)
  )
  pmin(pmax(m + stats::rnorm(length(m), sd = 0.05), 0.001), 0.999)
}

# the linear half of Horvath1, over whatever matrix it is handed
horvath1_score <- function(m) {
  coef <- clock_coefs("Horvath1")
  tf <- resolve_output_transform(clock_output_transform("Horvath1"))
  as.numeric(tf(clock_intercept("Horvath1") + m[, names(coef)] %*% coef))
}

# the record-half runs share one call: Horvath1 normalized over a thinned
# background, with both gates off because that background is deliberately short.
horvath1_normalized <- function(DNAm = methylation_betas(background = 1000L)) {
  calc_clocks(
    DNAm,
    "Horvath1",
    normalize = c(Horvath1 = TRUE),
    min_clocks_coverage = 0,
    min_samples_coverage = 0
  )
}

bmiq_calibrated <- function(m) {
  bmiq_calibration(
    m,
    goldstandard.beta = as.numeric(GOLD[colnames(m)]),
    verbose = FALSE,
    on.sample.error = "continue",
    failed.sample = "NA"
  )$calibrated
}

# front-door refusals: the user's own normalize= argument
test_that("normalize= refuses what the catalog cannot express", {
  # no scheme declared at all
  expect_error(resolve_normalize(c(Hannum = TRUE), "Hannum"))
  # noob is an IDAT-level correction, unreachable from a beta matrix
  expect_error(resolve_normalize(c(Horvath2 = TRUE), "Horvath2"))
  # a clock outside the run, an unnamed vector, a non-logical
  expect_error(resolve_normalize(c(Horvath1 = TRUE), "Hannum"))
  expect_error(resolve_normalize(c(TRUE, FALSE), c("Hannum", "Horvath1")))
  expect_error(resolve_normalize(c(Hannum = NA), "Hannum"))
})

test_that("normalize= resolves per clock, and every scheme can be declined", {
  expect_true(resolve_normalize(NULL, "DunedinPACE")[["DunedinPACE"]])
  # on by default is a default, not a part of the clock that cannot be moved
  expect_false(
    resolve_normalize(c(DunedinPACE = FALSE), "DunedinPACE")[["DunedinPACE"]]
  )
  # declining a scheme the clock never declared is merely redundant
  expect_false(resolve_normalize(c(Hannum = FALSE), "Hannum")[["Hannum"]])
  # an unnamed policy reaches every clock that declares an expressible scheme
  ids <- c("Horvath1", "DunedinPACE", "Hannum")
  expect_equal(unname(resolve_normalize(TRUE, ids)), c(TRUE, TRUE, FALSE))
  expect_equal(unname(resolve_normalize(FALSE, ids)), c(FALSE, FALSE, FALSE))
})

test_that("normalize= takes clock ids, which speak for those clocks alone", {
  ids <- c("Horvath1", "DunedinPACE", "Hannum")
  # the character form is the named form with every value TRUE
  expect_equal(
    resolve_normalize("Horvath1", ids),
    resolve_normalize(c(Horvath1 = TRUE), ids)
  )
  # naming one clock leaves every other clock at its own default
  got <- resolve_normalize("Horvath1", ids)
  expect_true(got[["Horvath1"]])
  expect_true(got[["DunedinPACE"]])
  # the two refusals the named form already makes, reached through the sugar
  expect_error(resolve_normalize("Horvath1", "Hannum"))
  expect_error(resolve_normalize("Hannum", "Hannum"))
  # an empty request is a mistake, not a request for the defaults
  expect_error(resolve_normalize(character(0), ids))
  expect_error(resolve_normalize(logical(0), ids))
})

test_that("Horvath1 defaults to declining normalization", {
  DNAm <- random_betas(clock_scoring_cpgs("Horvath1"), n = 5L)
  res <- calc_clocks(DNAm, "Horvath1")

  cov <- res$coverage$per_clock[[1]]$Horvath1
  expect_false(cov$normalizes)
  expect_equal(cov$norm_imputed_partial, 0L)
  expect_equal(res$provenance$normalized, character(0))
  # a clean run records no scoring failures: list(), not an absent field
  expect_equal(res$provenance$scoring_failures, list())
})

# declining is the absence of a panel, not a special case downstream
test_that("a declined clock asks for no normalization panel", {
  skip_on_cran()
  expect_equal(length(clock_norm_cpgs("Horvath1", FALSE)), 0L)
  # accepting asks for exactly the declared gold panel, whatever its size
  expect_equal(length(clock_norm_cpgs("Horvath1", TRUE)), length(GOLD))

  # the 21k gold panel never reaches the required CpG set
  DNAm <- random_betas(clock_scoring_cpgs("Knight"), n = 4L)
  res <- calc_clocks(DNAm, "Knight")
  expect_false(res$coverage$per_clock[[1]]$Knight$normalizes)
  expect_false("Knight" %in% colnames(res$coverage$sample_miss$norm))

  # and sim_DNAm builds over the same resolved decision
  sim <- sim_DNAm("Horvath1", n = 3L)
  expect_equal(ncol(sim$DNAm), length(clock_scoring_cpgs("Horvath1")))
})

# the norm half of sample_miss is keyed by clock, like the score half
test_that("a clock with no norm panel keeps its entry rather than losing it", {
  skip_on_cran()
  spec <- mc_spec(c("Hannum", "DunedinPACE"))
  DNAm <- random_betas(panels_union(spec$panels), n = 4L)
  miss <- score_cohort(DNAm, spec, mc_cohort(DNAm, spec))$coverage$sample_miss

  expect_equal(names(miss$norm), spec$sequence)
  expect_equal(names(miss$score), spec$sequence)
  # present but empty for the clock that does not normalize
  expect_null(miss$norm[["Hannum"]])
  expect_equal(length(miss$norm[["DunedinPACE"]]), nrow(DNAm))
})

# normalized arithmetic is in test-fixtures-parity.R. this file covers the record half.
test_that("a normalized run says on the record that it normalized", {
  skip_on_cran()
  res <- horvath1_normalized()

  # the record must be able to say which Horvath1 it holds
  expect_equal(res$provenance$normalized, "Horvath1")
  cov <- res$coverage$per_clock[[1]]$Horvath1
  expect_true(cov$normalizes)
  expect_true("Horvath1" %in% colnames(res$coverage$sample_miss$norm))

  # on by default is recorded even though nobody asked for it
  pace <- calc_clocks(
    random_betas(names(clock_norm_target("DunedinPACE")), n = 3L),
    "DunedinPACE",
    min_samples_coverage = 0
  )
  expect_equal(pace$provenance$normalized, "DunedinPACE")
})

# the record keeps both facts, so a difference can be attributed to one of them
test_that("a declined scheme is on the record beside the request", {
  skip_on_cran()
  # the scoring panel alone: nowhere near enough background to normalize with
  DNAm <- random_betas(clock_scoring_cpgs("Horvath1"), n = 4L)
  res <- suppressWarnings(
    calc_clocks(DNAm, "Horvath1", normalize = c(Horvath1 = TRUE))
  )

  # asked for, not done -- and the score is the raw one, so it is not NA
  asked <- res$provenance$normalize_requested
  # keyed by batch, so the name is the label and the value is the request
  expect_equal(names(asked), res$provenance$mc_batch_id[[1L]])
  expect_equal(unname(unlist(asked)), "Horvath1")
  expect_equal(res$provenance$normalized, character(0))
  expect_false(anyNA(res$scores[, "Horvath1"]))

  # a batch that never asked binds with it: both normalized nothing, so the
  # columns mean the same thing even though the two requests differ
  other <- random_betas(clock_scoring_cpgs("Horvath1"), n = 4L)
  rownames(other) <- paste0(rownames(other), "b")
  plain <- calc_clocks(other, "Horvath1")
  bound <- rbind(res, plain)

  expect_equal(bound$provenance$normalized, character(0))
  # kept per batch, never reconciled: one entry each, and they disagree
  both <- bound$provenance$normalize_requested
  expect_equal(length(both), 2L)
  expect_equal(sort(unname(lengths(both))), c(0L, 1L))
  expect_equal(sort(names(both)), sort(unique(bound$provenance$mc_batch_id)))
})

# unfit BMIQ sample: NA score + notes entry (coverage still full)
test_that("a sample BMIQ cannot fit is on the record, not a bare NA", {
  skip_on_cran()
  # the failure is a property of the unfittable sample, not of the width
  DNAm <- methylation_betas(background = 1000L)
  DNAm[2, ] <- 0.5

  res <- suppressWarnings(horvath1_normalized(DNAm))
  got <- res$scores[, "Horvath1"]

  expect_equal(res$provenance$scoring_failures$Horvath1, rownames(DNAm)[2])
  expect_true(is.na(got[[2]]))
  expect_false(anyNA(got[-2]))

  # coverage stays full -- notes is what distinguishes the NA
  cov <- res$coverage$per_clock[[1]]$Horvath1
  expect_equal(cov$score_used, cov$score_needed)
})

# a partly calibrated sample still scores, so its note belongs on the norm row
# and must not touch the score. The collector is written from a thrown H step,
# which no fixture can raise on demand, so it is set here instead: what this
# guards is the join, which silently matches nothing if the key is built the
# wrong way round.
test_that("a partial calibration marks the norm panel and leaves the score", {
  skip_on_cran()
  DNAm <- methylation_betas(background = 1000L)
  res <- suppressWarnings(horvath1_normalized(DNAm))
  marked <- rownames(DNAm)[c(1, 3)]
  res$provenance$partial_calibration <- list(Horvath1 = marked)

  sc <- samples_coverage(res)
  noted <- sc[!is.na(sc$note), ]
  expect_equal(unique(noted$panel), "norm")
  expect_equal(unique(noted$note), "partial")
  expect_setequal(noted$id, marked)
  expect_false(anyNA(res$scores[marked, "Horvath1"]))
})

# Horvath1 and Knight declare one background, so it is calibrated once and the
# fit is shared. parity scores a single clock per call and cannot see this.
test_that("two clocks on one background score as if scored alone", {
  skip_on_cran()
  both <- c("Horvath1", "Knight")
  score <- unique(unlist(lapply(both, clock_scoring_cpgs)))
  panel <- c(score, setdiff(names(GOLD), score)[seq_len(1000L)])
  DNAm <- methylation_betas()[, panel, drop = FALSE]

  pair <- calc_clocks(
    DNAm,
    both,
    normalize = c(Horvath1 = TRUE, Knight = TRUE),
    min_clocks_coverage = 0,
    min_samples_coverage = 0
  )
  alone <- vapply(
    both,
    function(id) {
      res <- calc_clocks(
        DNAm,
        id,
        normalize = stats::setNames(TRUE, id),
        min_clocks_coverage = 0,
        min_samples_coverage = 0
      )
      as.numeric(res$scores[, id])
    },
    numeric(nrow(DNAm))
  )

  expect_equal(unname(pair$scores[, both]), unname(alone))
})

# absent background CpGs are dropped from the fit, never filled from the target
test_that("BMIQ drops absent background CpGs rather than filling them", {
  skip_on_cran()
  full <- methylation_betas()
  # drop background-only probes: the scoring panel stays whole, so no gate fires
  norm_only <- setdiff(names(GOLD), clock_scoring_cpgs("Horvath1"))
  dropped <- norm_only[seq_len(2000L)]
  thin <- full[, setdiff(names(GOLD), dropped), drop = FALSE]

  res <- calc_clocks(thin, "Horvath1", normalize = c(Horvath1 = TRUE))
  cov <- res$coverage$per_clock[[1]]$Horvath1
  expect_equal(cov$norm_present, length(GOLD) - 2000L)
  # the record says dropped, not filled
  expect_equal(cov$norm_dropped, 2000L)
  expect_equal(cov$norm_imputed_full, 0L)
  expect_false(anyNA(res$scores[, "Horvath1"]))

  # and the fit really did ignore them: filling from the target moves the score
  filled <- full
  filled[, dropped] <- rep(as.numeric(GOLD[dropped]), each = nrow(full))
  expect_false(isTRUE(all.equal(
    as.numeric(res$scores[, "Horvath1"]),
    horvath1_score(bmiq_calibrated(filled[, names(GOLD)]))
  )))
})
