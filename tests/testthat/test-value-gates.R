# value gates: overflow stops, Inf and out-of-[0,1] warn.

gate_betas <- function(n = 8L) {
  spec <- mc_spec("Hannum")
  panel <- panels_union(spec$panels)
  list(DNAm = random_betas(panel, n = n), panel = panel)
}

# collect every warning (the two range flags are independent)
warnings_of <- function(expr) {
  seen <- character(0)
  withCallingHandlers(
    expr,
    warning = function(cond) {
      seen <<- c(seen, conditionMessage(cond))
      invokeRestart("muffleWarning")
    }
  )
  seen
}

test_that("an infinite value scores as missing, and warns that it did", {
  b <- gate_betas()

  # no NA anywhere (anyNA does not see Inf)
  inf_only <- b$DNAm
  inf_only[1, b$panel[1]] <- Inf
  expect_equal(length(warnings_of(res <- calc_clocks(inf_only, "Hannum"))), 1L)
  expect_true(all(is.finite(res$scores[, "Hannum"])))
  # imputed exactly like an NA in the same cell would have been
  expect_equal(
    res$coverage$per_clock[[1]][["Hannum"]]$score_imputed_partial,
    1L
  )

  neg <- b$DNAm
  neg[3, b$panel[5]] <- -Inf
  expect_equal(length(warnings_of(calc_clocks(neg, "Hannum"))), 1L)
})

test_that("an Inf and an NA in the same cell score identically", {
  b <- gate_betas()
  as_inf <- as_na <- b$DNAm
  as_inf[3, b$panel[5]] <- Inf
  as_na[3, b$panel[5]] <- NA

  inf_res <- suppressWarnings(calc_clocks(as_inf, "Hannum"))
  na_res <- calc_clocks(as_na, "Hannum")

  expect_equal(inf_res$scores, na_res$scores)
  expect_equal(inf_res$coverage$sample_miss, na_res$coverage$sample_miss)
})

test_that("an off-panel Inf is missing to the moments, like any other Inf", {
  # zhang2019EN z-scores over the whole matrix.
  DNAm <- cbind(
    sim_DNAm("Zhang2019EN", n = 4L)$DNAm,
    random_betas("cg_offpanel_1", n = 4L)
  )
  as_inf <- as_na <- DNAm
  as_inf[2, "cg_offpanel_1"] <- Inf
  as_na[2, "cg_offpanel_1"] <- NA

  inf_res <- calc_clocks(as_inf, "Zhang2019EN")
  na_res <- calc_clocks(as_na, "Zhang2019EN")

  # skipped, not poison: the moments come off the same kernel as the panel stats
  expect_equal(inf_res$scores, na_res$scores)
  expect_true(all(is.finite(inf_res$scores[, "Zhang2019EN"])))
  # and dropping one of 515 columns moves only that sample
  clean <- calc_clocks(DNAm, "Zhang2019EN")
  expect_equal(inf_res$scores[-2, ], clean$scores[-2, ])
})

test_that("the moments span columns the column stats and gates never see", {
  panel <- panels_union(mc_spec("Zhang2019EN")$panels)
  DNAm <- random_betas(panel, n = 4L)
  off <- paste0("cg_offpanel_", seq_len(50L))
  wide <- cbind(DNAm, random_betas(off, n = 4L))
  wide[, off] <- 0.9

  # off-panel columns are in the moments, so every sample's score moves ...
  expect_true(all(
    abs(
      calc_clocks(wide, "Zhang2019EN")$scores -
        calc_clocks(DNAm, "Zhang2019EN")$scores
    ) >
      1e-6
  ))

  # ... but not in the column stats, so no value gate ever looks at them
  wide[1, off[[1]]] <- -0.5
  expect_no_warning(calc_clocks(wide, "Zhang2019EN"))
})

test_that("an unscored sample is NA, which is not a non-finite score", {
  expect_no_warning(check_score_values(list(Hannum = matrix(c(1, NA_real_)))))
  expect_warning(check_score_values(list(Hannum = matrix(c(1, NaN)))))
  expect_warning(check_score_values(list(Hannum = matrix(c(1, Inf)))))
})

test_that("a wholly infinite column classifies absent, like an all-NA one", {
  b <- gate_betas()
  DNAm <- b$DNAm
  DNAm[, b$panel[2]] <- Inf

  mna <- suppressWarnings(scan_missing_cpgs(DNAm, b$panel, b$panel))
  expect_true(b$panel[2] %in% mna$all_na_cols)
  expect_false(b$panel[2] %in% mna$usable_cols)
  expect_true(all(is.finite(mna$col_mean)))
})

test_that("the kernel counts Inf as missing, not as observed", {
  b <- gate_betas(n = 6L)
  DNAm <- b$DNAm
  DNAm[3, b$panel[5]] <- Inf

  scan <- col_stats(DNAm[, b$panel[1:8], drop = FALSE])
  expect_true(scan$any_inf)
  expect_null(scan$overflow_col)
  # the Inf row observed 7 of the 8 columns, and the mean skips it
  expect_equal(scan$row_obs, c(8L, 8L, 7L, 8L, 8L, 8L))
  expect_equal(unname(scan$stats["n_obs", 5]), 5)
  expect_equal(
    unname(scan$stats["sum", 5]),
    sum(DNAm[-3, b$panel[5]])
  )
  # an Inf is missing, so it says nothing about range
  expect_equal(scan$max_val, 1)
  expect_true(is.na(scan$max_col))
})

test_that("each range flag warns on its own, and both can fire", {
  b <- gate_betas()

  low <- b$DNAm
  low[4, b$panel[7]] <- -0.2
  expect_equal(length(warnings_of(calc_clocks(low, "Hannum"))), 1L)

  high <- b$DNAm
  high[4, b$panel[7]] <- 1.4
  expect_equal(length(warnings_of(calc_clocks(high, "Hannum"))), 1L)

  both <- b$DNAm
  both[4, b$panel[7]] <- -0.2
  both[5, b$panel[9]] <- 1.4
  expect_equal(length(warnings_of(calc_clocks(both, "Hannum"))), 2L)

  # an M-value matrix (betas through log2(p / (1 - p))) spans both sides
  m <- log2(b$DNAm / (1 - b$DNAm))
  expect_equal(length(warnings_of(res <- calc_clocks(m, "Hannum"))), 2L)
  # warnings, not a refusal -- the caller still gets their scores
  expect_equal(nrow(res$scores), nrow(m))
})

test_that("ordinary betas pass both gates in silence", {
  b <- gate_betas()
  expect_no_warning(calc_clocks(b$DNAm, "Hannum"))

  # nas are missing, not bad: they fill and say nothing about range
  with_na <- b$DNAm
  with_na[1:3, b$panel[1]] <- NA
  expect_no_warning(filled <- calc_clocks(with_na, "Hannum"))
  # one CpG, filled in three samples: the record counts CpGs
  expect_equal(
    filled$coverage$per_clock[[1]][["Hannum"]]$score_imputed_partial,
    1L
  )
})

test_that("per-sample fill counts land on the samples that were filled", {
  b <- gate_betas(n = 6L)
  DNAm <- b$DNAm
  # 2 CpGs filled for sample 1, 1 for sample 4, none for anyone else
  DNAm[1, b$panel[1:2]] <- NA
  DNAm[4, b$panel[1]] <- NA

  res <- calc_clocks(DNAm, "Hannum")
  miss <- res$coverage$sample_miss$score[, "Hannum"]

  expect_equal(unname(miss), c(2L, 0L, 0L, 1L, 0L, 0L))
  expect_equal(names(miss), rownames(DNAm))
  # the record counts the other axis: 2 distinct CpGs, not the 3 filled cells
  expect_equal(
    res$coverage$per_clock[[1]][["Hannum"]]$score_imputed_partial,
    2L
  )
})

test_that("an all-missing column classifies rather than erroring", {
  b <- gate_betas()
  DNAm <- b$DNAm
  DNAm[, b$panel[2]] <- NA

  # all-NA column is ordinary -- classified, not averaged
  expect_no_warning(res <- calc_clocks(DNAm, "Hannum"))
  expect_true(all(is.finite(res$scores[, "Hannum"])))

  mna <- scan_missing_cpgs(DNAm, b$panel, b$panel)
  expect_true(b$panel[2] %in% mna$all_na_cols)
  expect_false(b$panel[2] %in% mna$usable_cols)
  expect_false(b$panel[2] %in% names(mna$col_mean))
  expect_true(all(is.finite(mna$col_mean)))
})

test_that("a column that overflows its own sum stops, and names no sample", {
  b <- gate_betas()
  DNAm <- b$DNAm
  # overflow: column reported, row is NA (no invented position)
  DNAm[, b$panel[4]] <- 1e308

  scan <- col_stats(DNAm[, b$panel[1:8], drop = FALSE])
  expect_equal(scan$overflow_col, 4L)
  expect_null(scan$stats)

  # naming the column is the feature
  err <- tryCatch(calc_clocks(DNAm, "Hannum"), error = function(e) e)
  expect_s3_class(err, "error")
  expect_true(grepl(b$panel[4], conditionMessage(err), fixed = TRUE))
})

test_that("a sample with nothing on the scoring panel stops, off-panel or not", {
  b <- gate_betas()
  extra <- paste0("cg_offpanel_", seq_len(20L))
  DNAm <- cbind(b$DNAm, random_betas(extra, n = nrow(b$DNAm)))

  # all panel CpGs partial-NA cohort-wide would fill this sample from others
  DNAm[1, b$panel] <- NA
  expect_error(calc_clocks(DNAm, "Hannum"))

  # off-panel observations do not make a sample scoreable
  expect_true(all(is.finite(DNAm[1, extra])))
})

test_that("a dead row is judged on the scoring panel, not the norm one", {
  spec <- mc_spec("DunedinPACE")
  score <- panels_union(spec$panels, "score")
  norm_only <- setdiff(panels_union(spec$panels), score)
  expect_true(length(norm_only) > 0L)

  DNAm <- random_betas(panels_union(spec$panels), n = 4L)

  # a full normalization background does not make a sample scoreable
  dead <- DNAm
  dead[1, score] <- NA
  expect_true(all(is.finite(dead[1, norm_only])))
  expect_error(mc_cohort(dead, spec))

  # the converse is not fatal -- a thin background only warns
  thin <- DNAm
  thin[1, norm_only] <- NA
  expect_no_error(mc_cohort(thin, spec))
})

test_that("col_stats counts observed entries per row as well as per column", {
  b <- gate_betas(n = 6L)
  DNAm <- b$DNAm
  DNAm[2, b$panel[1:4]] <- NA
  DNAm[3, ] <- NA

  scan <- col_stats(DNAm[, b$panel[1:4], drop = FALSE])
  expect_equal(scan$row_obs, c(4L, 0L, 0L, 4L, 4L, 4L))
})

test_that("col_stats sums and counts observed entries in one sweep", {
  b <- gate_betas(n = 10L)
  DNAm <- b$DNAm
  DNAm[1:4, b$panel[1]] <- NA
  DNAm[, b$panel[2]] <- NA

  scan <- col_stats(DNAm[, b$panel[1:3], drop = FALSE])
  expect_null(scan$overflow_col)
  # seeded at the beta bounds, so in-range betas leave them where they are
  expect_equal(scan$min_val, 0)
  expect_equal(scan$max_val, 1)

  st <- scan$stats
  expect_equal(rownames(st), c("sum", "n_obs"))
  val <- function(row, col) unname(st[row, col])

  # partial NA: observed count drops, the mean comes off the same sweep
  expect_equal(val("n_obs", 1), 6)
  expect_equal(
    val("sum", 1) / val("n_obs", 1),
    mean(DNAm[5:10, b$panel[1]])
  )

  # all NA: nothing observed, so no mean is defined for it
  expect_equal(val("n_obs", 2), 0)
  expect_equal(val("sum", 2), 0)

  # untouched column
  expect_equal(val("n_obs", 3), 10)
  expect_equal(val("sum", 3), sum(DNAm[, b$panel[3]]))
})

# cols: scan a subset of DNAm's columns without materializing a slice

test_that("scanning by cols agrees with scanning a pre-subset matrix", {
  b <- gate_betas(n = 8L)
  DNAm <- b$DNAm
  DNAm[1:3, b$panel[1]] <- NA
  DNAm[, b$panel[2]] <- NA

  # deliberately not in column order
  sel <- b$panel[c(5, 1, 9, 2)]
  direct <- col_stats(DNAm, match(sel, colnames(DNAm)))
  sliced <- col_stats(DNAm[, sel, drop = FALSE])

  expect_equal(direct$stats, sliced$stats)
  expect_equal(direct$row_obs, sliced$row_obs)
  expect_equal(direct$min_val, sliced$min_val)
  expect_equal(direct$max_val, sliced$max_val)
  expect_null(direct$overflow_col)

  # results are ordered by cols, not by position in DNAm
  expect_equal(unname(direct$stats["n_obs", 2]), 5)
  expect_equal(unname(direct$stats["sum", 2]), sum(DNAm[4:8, b$panel[1]]))
  expect_equal(unname(direct$stats["n_obs", 4]), 0)
})

test_that("cols narrows the sweep -- unlisted columns are not scanned", {
  b <- gate_betas(n = 6L)
  DNAm <- b$DNAm
  DNAm[2, b$panel[1:4]] <- NA
  # out-of-range value the narrow scan must not see
  DNAm[, b$panel[20]] <- -0.5

  narrow <- col_stats(DNAm, match(b$panel[1:4], colnames(DNAm)))
  expect_equal(narrow$row_obs, c(4L, 0L, 4L, 4L, 4L, 4L))
  expect_equal(narrow$min_val, 0)

  # widen over the same matrix and the range moves
  wide <- col_stats(DNAm, match(b$panel[c(1:4, 20)], colnames(DNAm)))
  expect_equal(wide$min_val, -0.5)
  # position within cols, like overflow_col -- panel[20] is the 5th entry
  expect_equal(wide$min_col, 5L)
  expect_equal(wide$row_obs, c(5L, 1L, 5L, 5L, 5L, 5L))
})

test_that("overflow_col names a position within cols, not a column of DNAm", {
  b <- gate_betas()
  DNAm <- b$DNAm
  DNAm[, b$panel[5]] <- 1e308

  # panel[5] is the 2nd entry of cols
  scan <- col_stats(DNAm, match(b$panel[c(1, 5, 9)], colnames(DNAm)))
  expect_equal(scan$overflow_col, 2L)
  expect_null(scan$stats)
  expect_null(scan$row_obs)
})

test_that("cols defaults to every column of DNAm", {
  b <- gate_betas(n = 5L)
  sub <- b$DNAm[, b$panel[1:6], drop = FALSE]
  expect_equal(col_stats(sub), col_stats(sub, seq_len(ncol(sub))))
})

test_that("cols must be in-range column indices", {
  b <- gate_betas(n = 4L)
  DNAm <- b$DNAm
  expect_error(col_stats(DNAm, 0L))
  expect_error(col_stats(DNAm, -1L))
  expect_error(col_stats(DNAm, ncol(DNAm) + 1L))
  expect_error(col_stats(DNAm, NA_integer_))
})

test_that("an empty cols scans nothing and observes nothing", {
  b <- gate_betas(n = 4L)
  scan <- col_stats(b$DNAm, integer(0))
  expect_equal(dim(scan$stats), c(2L, 0L))
  expect_equal(scan$row_obs, integer(4))
  expect_null(scan$overflow_col)
})

# moment_sets is validated in R before the kernel.

test_that("check_moment_sets passes NULL and normalizes what it keeps", {
  expect_null(check_moment_sets(NULL, 40L))
  expect_equal(check_moment_sets(list(a = c(1, 2, 3)), 40L)[["a"]], 1:3)
  expect_equal(names(check_moment_sets(list(a = 1L, b = 2L), 40L)), c("a", "b"))
  # a ref meeting no measured column is a data fact, not a usage error
  expect_equal(check_moment_sets(list(a = integer(0)), 40L)[["a"]], integer(0))
})

test_that("check_moment_sets rejects what would be fatal in the kernel", {
  expect_error(check_moment_sets(list(a = NULL), 40L))
  expect_error(check_moment_sets(list(a = "x"), 40L))
  expect_error(check_moment_sets(list(), 40L))
  expect_error(
    check_moment_sets(
      lapply(seq_len(MAX_MOMENT_SETS + 1L), function(i) 1L),
      40L
    )
  )
  expect_error(check_moment_sets(list(a = 0L), 40L))
  expect_error(check_moment_sets(list(a = 41L), 40L))
  expect_error(check_moment_sets(list(a = NA_integer_), 40L))
})

test_that("validated sets are what the kernel accepts", {
  b <- gate_betas(n = 5L)
  sets <- check_moment_sets(list(a = c(1, 2, 3)), ncol(b$DNAm))
  expect_no_error(col_stats(b$DNAm, NULL, sets))
})

test_that("R and the kernel agree on the mask width", {
  b <- gate_betas(n = 3L)
  one <- lapply(seq_len(MAX_MOMENT_SETS), function(i) i)
  expect_no_error(col_stats(b$DNAm, NULL, one))
  # one past the width is a stop, not a silently truncated mask
  expect_error(col_stats(b$DNAm, NULL, c(one, list(1L))))
})

# mask width is a ceiling on domains. catalog must fit inside it.
test_that("every catalog clock's domains fit one sweep", {
  ids <- names(mc_catalog)
  # census keys only (resolving every ref tensor is unnecessary).
  keys <- vapply(ids, function(id) clock_moment_key(id) %||% NA_character_, "")
  expect_lte(length(unique(stats::na.omit(keys))), MAX_MOMENT_SETS)
})

# moment domains: each set carries its own counter.

# per-row golden over a column subset, finite entries only
domain_golden <- function(DNAm, cols, f) {
  sub <- DNAm[, cols, drop = FALSE]
  unname(apply(sub, 1, function(v) f(v[is.finite(v)])))
}

# obs/mean/sd triple one set's kernel outputs must match.
expect_domain_moments <- function(got, DNAm, cols, nm) {
  expect_equal(
    got$row_moment_obs[, nm],
    as.integer(rowSums(is.finite(DNAm[, cols, drop = FALSE]))),
    info = nm
  )
  expect_equal(got$row_mean[, nm], domain_golden(DNAm, cols, mean), info = nm)
  expect_equal(
    sqrt(got$row_m2[, nm] / (got$row_moment_obs[, nm] - 1)),
    domain_golden(DNAm, cols, stats::sd),
    info = nm
  )
}

test_that("row_obs stays the subset's count when moments widen the sweep", {
  b <- gate_betas(n = 6L)
  DNAm <- b$DNAm
  sel <- b$panel[1:4]
  off <- setdiff(colnames(DNAm), sel)
  DNAm[2, sel] <- NA
  DNAm[3:4, off[1]] <- NA
  sidx <- match(sel, colnames(DNAm))

  mom <- col_stats(DNAm, sidx, list(all = seq_len(ncol(DNAm))))
  flat <- col_stats(DNAm, sidx)

  # moments no longer change what row_obs counts
  expect_equal(mom$row_obs, flat$row_obs)
  expect_equal(mom$row_obs, c(4L, 0L, 4L, 4L, 4L, 4L))
  # the moment counter spans the domain, here the whole matrix
  expect_equal(
    mom$row_moment_obs[, "all"],
    as.integer(rowSums(is.finite(DNAm)))
  )
  # the column half is still the subset's alone
  expect_equal(mom$stats, flat$stats)
})

test_that("the moment outputs are nr x K, named by their sets", {
  b <- gate_betas(n = 5L)
  sel <- match(b$panel[1:3], colnames(b$DNAm))
  sets <- list(a = 1:4, b = 5:9)

  # absent without sets, like row_mean and row_m2
  expect_null(col_stats(b$DNAm, sel)$row_moment_obs)

  got <- col_stats(b$DNAm, sel, sets)
  for (nm in c("row_moment_obs", "row_mean", "row_m2")) {
    expect_equal(dim(got[[nm]]), c(5L, 2L), info = nm)
    expect_equal(colnames(got[[nm]]), c("a", "b"), info = nm)
  }

  # and the overflow bail nulls them out with the rest
  DNAm <- b$DNAm
  DNAm[, b$panel[2]] <- 1e308
  scan <- col_stats(DNAm, sel, sets)
  expect_equal(scan$overflow_col, 2L)
  expect_null(scan$row_moment_obs)
})

test_that("a set confines the moments to its own columns", {
  b <- gate_betas(n = 6L)
  DNAm <- b$DNAm
  ref <- b$panel[1:10]
  sel <- b$panel[5:14]
  DNAm[1, ref[1]] <- NA
  DNAm[2, setdiff(colnames(DNAm), ref)[1]] <- NA
  sidx <- match(sel, colnames(DNAm))

  got <- col_stats(DNAm, sidx, list(ref = match(ref, colnames(DNAm))))

  expect_domain_moments(got, DNAm, ref, "ref")
  # the stats half does not move with the moment domain
  flat <- col_stats(DNAm, sidx)
  expect_equal(got$stats, flat$stats)
  expect_equal(got$row_obs, flat$row_obs)
})

test_that("a moment column is counted once however the passes split it", {
  b <- gate_betas(n = 5L)
  DNAm <- b$DNAm
  ridx <- match(b$panel[1:8], colnames(DNAm))

  # every overlap regime between the stats subset and the moment domain
  subsets <- list(
    disjoint = match(b$panel[20:25], colnames(DNAm)),
    overlapping = match(b$panel[5:12], colnames(DNAm)),
    identical = ridx,
    # nothing to sum: a moments-only sweep
    empty = integer(0),
    whole = NULL
  )
  got <- lapply(subsets, function(cs) col_stats(DNAm, cs, list(r = ridx)))

  ref_obs <- as.integer(rowSums(is.finite(DNAm[, ridx, drop = FALSE])))
  for (nm in names(got)) {
    expect_equal(got[[nm]]$row_moment_obs[, "r"], ref_obs, info = nm)
    expect_equal(got[[nm]]$row_mean, got[["disjoint"]]$row_mean, info = nm)
    expect_equal(got[[nm]]$row_m2, got[["disjoint"]]$row_m2, info = nm)
  }
})

test_that("overlapping domains are each counted in full in one sweep", {
  b <- gate_betas(n = 6L)
  DNAm <- b$DNAm
  DNAm[1, b$panel[1]] <- NA
  DNAm[2, b$panel[12]] <- NA

  # a partial overlap, a nesting and the whole matrix, all in one call
  cols <- list(
    a = b$panel[1:10],
    b = b$panel[6:15],
    nested = b$panel[7:9],
    all = colnames(DNAm)
  )
  got <- col_stats(
    DNAm,
    match(b$panel[1:3], colnames(DNAm)),
    lapply(cols, function(cc) match(cc, colnames(DNAm)))
  )

  for (nm in names(cols)) {
    expect_domain_moments(got, DNAm, cols[[nm]], nm)
  }
})

test_that("scan_missing_cpgs banks one moment entry per declared domain", {
  b <- gate_betas(n = 7L)
  DNAm <- b$DNAm
  sel <- b$panel[1:5]
  ref <- b$panel[20:30]
  DNAm[1, sel[1]] <- NA
  DNAm[2, setdiff(colnames(DNAm), sel)[1]] <- Inf

  mna <- suppressWarnings(scan_missing_cpgs(
    DNAm,
    sel,
    sel,
    moment_domains = list(full = NULL, ref = ref)
  ))
  expect_equal(names(mna$sample_moments), c("full", "ref"))
  # a NULL domain is every column. a declared one is only its own
  expect_equal(
    mna$sample_moments$full$mean,
    domain_golden(DNAm, colnames(DNAm), mean)
  )
  expect_equal(
    mna$sample_moments$full$sd,
    domain_golden(DNAm, colnames(DNAm), stats::sd)
  )
  expect_equal(mna$sample_moments$ref$mean, domain_golden(DNAm, ref, mean))
  expect_equal(mna$sample_moments$ref$sd, domain_golden(DNAm, ref, stats::sd))
})

test_that("no declared domain banks no moments at all", {
  b <- gate_betas(n = 4L)
  sel <- b$panel[1:5]
  expect_null(scan_missing_cpgs(b$DNAm, sel, sel)$sample_moments)
  expect_null(
    scan_missing_cpgs(b$DNAm, sel, sel, moment_domains = list())$sample_moments
  )
})

test_that("a domain resolves against what was measured, not what it declares", {
  b <- gate_betas(n = 4L)
  ref <- c(b$panel[1:3], "cg_not_measured_at_all")
  mna <- scan_missing_cpgs(
    b$DNAm,
    b$panel[1:5],
    b$panel[1:5],
    moment_domains = list(ref = ref)
  )
  # the unmeasured CpG drops out rather than erroring or widening the panel
  expect_equal(
    mna$sample_moments$ref$mean,
    domain_golden(b$DNAm, ref[1:3], mean)
  )
})

test_that("a domain too thin to describe a sample reports NA, not zero spread", {
  b <- gate_betas(n = 5L)
  DNAm <- b$DNAm
  thin <- b$panel[1:3]
  # sample 2 observes nothing in the domain, sample 3 observes exactly one
  DNAm[2, thin] <- NA
  DNAm[3, thin[2:3]] <- NA
  score <- b$panel[10:20]

  mna <- scan_missing_cpgs(
    DNAm,
    score,
    score,
    moment_domains = list(thin = thin, one = thin[1])
  )
  got <- mna$sample_moments$thin
  # n = 0 gives neither. n = 1 gives a mean but no spread
  expect_true(is.na(got$mean[2]))
  expect_true(is.na(got$sd[2]))
  expect_equal(got$mean[3], DNAm[3, thin[1]])
  expect_true(is.na(got$sd[3]))
  # the rest of the column is untouched by the guard
  expect_false(anyNA(got$sd[c(1, 4, 5)]))

  # a one-column domain can never carry a spread, and never reads as 0
  expect_true(all(is.na(mna$sample_moments$one$sd)))
  expect_equal(mna$sample_moments$one$mean[1], DNAm[1, thin[1]])
})

test_that("an empty domain is a data fact, reported as NA", {
  b <- gate_betas(n = 4L)
  sel <- b$panel[1:5]
  mna <- scan_missing_cpgs(
    b$DNAm,
    sel,
    sel,
    moment_domains = list(none = character(0))
  )
  expect_true(all(is.na(mna$sample_moments$none$mean)))
  expect_true(all(is.na(mna$sample_moments$none$sd)))
})

# pheno Age units gate: per row, warn only, both sides independent.

age_pheno <- function(age) {
  data.frame(ID = paste0("s", seq_along(age)), Age = age)
}

test_that("one wrong row fires even in an otherwise clean cohort", {
  # the whole reason this is per row: a cohort statistic cannot see this
  ph <- age_pheno(c(45, 52, 600, 38, 61, 47, 55, 39))
  expect_warning(flagged <- warn_age_units(ph, "ID", ph$ID))
  expect_equal(flagged, "s3")
})

test_that("both bounds fire independently on one pheno", {
  ph <- age_pheno(c(45, 600, -38, 38))
  seen <- warnings_of(flagged <- warn_age_units(ph, "ID", ph$ID))
  expect_equal(length(seen), 2L)
  expect_equal(flagged, c("s2", "s3"))
})

test_that("real ages, pre-birth fractions and NA are left alone", {
  # -0.5/-1 are a legitimate pre-birth convention and 122 is a real maximum
  ph <- age_pheno(c(-0.5, -1, 122, 0, 45, NA, 118))
  expect_no_warning(flagged <- warn_age_units(ph, "ID", ph$ID))
  expect_equal(flagged, character(0))
})

test_that("only rows surviving the id-join are judged", {
  # the out-of-range row is not in the DNAm sample set, so it is not this run's
  ph <- age_pheno(c(45, 52, 600))
  expect_no_warning(warn_age_units(ph, "ID", c("s1", "s2")))
})

test_that("calc_accel reaches the gate through its own pheno merge", {
  b <- gate_betas(n = 4L)
  res <- suppressMessages(calc_clocks(b$DNAm, "Hannum"))
  ids <- rownames(b$DNAm)
  bad <- data.frame(ID = ids, Age = c(45, 52, 600, 38))
  expect_warning(calc_accel(res, type = "diff", data = bad))
})
