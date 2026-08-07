# clocks_coverage() / samples_coverage() formatters over a finished record.

# one draw each, shared by the tests below that only read the record
GRIP4 <- grip_fixture()
HANNUM4 <- random_betas(clock_cpgs("Hannum"), n = 4L)
HANNUM_RES <- calc_clocks(HANNUM4, "Hannum")

test_that("clocks_coverage marks members routing_target and the alias returned", {
  res <- calc_clocks(GRIP4$DNAm, "DNAmGrip_wAge", pheno = GRIP4$pheno)
  cc <- clocks_coverage(res)

  expect_s3_class(cc, "data.frame")

  # the alias reads no CpGs of its own, so its panel row is all NA
  alias <- cc[cc$clock_id == "DNAmGrip_wAge", ]
  expect_equal(alias$role, "returned")
  expect_true(is.na(alias$score_needed))

  # the two members are routing targets carrying the per-sex denominators
  members <- cc[
    cc$clock_id %in% c("DNAmGrip_wAge_Female", "DNAmGrip_wAge_Male"),
  ]
  expect_equal(sort(unique(members$role)), "routing_target")
  expect_setequal(members$score_needed, c(length(GRIP4$fem), length(GRIP4$mal)))
})

test_that("clocks_coverage reports score_used = present + imputed_full per row", {
  fx <- gait_holed_fixture()

  cc <- clocks_coverage(calc_clocks(
    fx$DNAm,
    "DNAmGait_noAge",
    pheno = fx$pheno
  ))
  row <- cc[cc$clock_id == fx$id, ]
  expect_equal(row$score_imputed_full, 5L)
  expect_equal(row$score_used, row$score_present + row$score_imputed_full)
  expect_equal(row$missing_cpgs[[1]], fx$drop)
})

test_that("a clock that reads no CpGs gets rows, and no counts on them", {
  female <- c(1, 1, 1, 0, 0, 0)
  fx <- grip_fixture(female)
  DNAm <- fx$DNAm

  res <- calc_clocks(DNAm, "DNAmGrip_wAge", pheno = fx$pheno)
  sc <- samples_coverage(res)

  # the alias is a returned column that reads no CpGs, so it gets a row per
  # sample with nothing counted on it. that row is what carries a reason.
  alias <- sc[sc$clock_id == "DNAmGrip_wAge", ]
  expect_equal(nrow(alias), 6L)
  expect_true(all(is.na(alias$n_needed)))
  expect_true(all(is.na(alias$coverage)))

  # the members that read betas keep one row per sample, under the model
  # that scored it, and those rows carry the counts.
  mem <- sc[sc$clock_id != "DNAmGrip_wAge", ]
  expect_setequal(
    unique(mem$clock_id),
    c("DNAmGrip_wAge_Female", "DNAmGrip_wAge_Male")
  )
  expect_equal(nrow(mem), 6L)
  expect_false(anyNA(mem$coverage))
  expect_equal(
    mem$clock_id[match(rownames(DNAm), mem$id)],
    ifelse(female == 1, "DNAmGrip_wAge_Female", "DNAmGrip_wAge_Male")
  )
  expect_equal(
    mem$n_needed[match(rownames(DNAm), mem$id)],
    ifelse(female == 1, length(fx$fem), length(fx$mal))
  )
})

test_that("a sample no model scored keeps the row that explains it", {
  # the last sample's sex is unknown, so neither member claims it
  fx <- grip_fixture(c(1, 1, 0, NA))
  DNAm <- fx$DNAm

  # the unknown sex is worth a warning, and it is not what this test asserts
  expect_warning(res <- calc_clocks(DNAm, "DNAmGrip_wAge", pheno = fx$pheno))
  sc <- samples_coverage(res)

  unscored <- rownames(DNAm)[4]
  expect_true(is.na(res$scores[unscored, "DNAmGrip_wAge"]))
  # no member counted it, so it has no counted row and one alias row
  expect_setequal(sc$clock_id[sc$id == unscored], "DNAmGrip_wAge")
  expect_equal(sc$reason[sc$id == unscored], "covariate")
})

test_that("samples_coverage coverage is the observed fraction of the panel", {
  panel <- clock_scoring_cpgs("Hannum")
  DNAm <- random_betas(panel, n = 6L)
  DNAm[1, panel[[1]]] <- NA_real_ # one sample leans on a cohort mean

  sc <- samples_coverage(calc_clocks(DNAm, "Hannum", min_samples_coverage = 0))
  hannum <- sc[sc$clock_id == "Hannum", ]

  expect_equal(nrow(hannum), 6L)
  # sample 1 is one CpG short of the panel, the rest are full
  expect_equal(hannum$n_observed[1], length(panel) - 1L)
  expect_equal(hannum$coverage[1], (length(panel) - 1L) / length(panel))
  expect_true(all(hannum$coverage[-1] == 1))
})

test_that("samples_coverage gives a normalizing clock a score and a norm row", {
  norm_panel <- names(clock_norm_target("DunedinPACE"))
  score_panel <- clock_scoring_cpgs("DunedinPACE")
  DNAm <- random_betas(norm_panel, n = 4L)

  res <- calc_clocks(DNAm, "DunedinPACE", min_samples_coverage = 0)
  sc <- samples_coverage(res)
  dp <- sc[sc$clock_id == "DunedinPACE", ]

  # per panel role, and the norm background is the larger, separate panel
  expect_setequal(unique(dp$panel), c("score", "norm"))
  needed <- tapply(dp$n_needed, dp$panel, unique)
  expect_equal(as.integer(needed[["score"]]), length(score_panel))
  expect_gt(needed[["norm"]], needed[["score"]])
})

test_that("min_samples_coverage reads the score rows and not the norm rows", {
  skip_on_cran()
  gold <- names(clock_norm_target("DunedinPACE"))
  bg_only <- setdiff(gold, clock_scoring_cpgs("DunedinPACE"))
  DNAm <- random_betas(gold, n = 4L)
  # sample 1 loses 40% of the background alone. every scoring CpG is present,
  # cohort-wide and for that sample, so nothing was gated and nothing is NA.
  DNAm[1, bg_only[seq_len(round(0.4 * length(bg_only)))]] <- NA_real_

  res <- calc_clocks(DNAm, "DunedinPACE")
  expect_false(anyNA(res$scores[, "DunedinPACE"]))
  expect_silent(sc <- samples_coverage(res))

  # the norm row really is under the floor. it is simply not read against it.
  thin <- sc[sc$panel == "norm" & sc$id == rownames(DNAm)[[1L]], ]
  expect_lt(thin$coverage, 0.75)
})

# the coverage floors the run was scored under

# one sample leaning on a cohort mean for all but 10 CpGs of the panel
thin_sample_betas <- function(n = 6L) {
  panel <- clock_scoring_cpgs("Hannum")
  DNAm <- random_betas(panel, n = n)
  DNAm[1, panel[-seq_len(10L)]] <- NA_real_
  DNAm
}

test_that("samples_coverage re-warns, and a bound record uses the strictest floor", {
  # the thin sample is row 1, so it sits in the `hot` block
  DNAm <- thin_sample_betas(6L)

  quiet <- calc_clocks(DNAm[4:6, ], "Hannum", min_samples_coverage = 0)
  expect_silent(samples_coverage(quiet))
  expect_warning(
    hot <- calc_clocks(DNAm[1:3, ], "Hannum", min_samples_coverage = 0.9)
  )
  expect_warning(samples_coverage(hot))

  # differing floors bind without complaint -- record what batching forced
  out <- rbind(quiet, hot)
  expect_equal(unname(out$provenance$min_samples_coverage), c(0, 0.9))
  expect_equal(
    names(out$provenance$min_samples_coverage),
    names(out$coverage$per_clock)
  )

  # 0.9 is the strictest, and the thin sample is under it
  expect_warning(samples_coverage(out))
})

test_that("a record whose two batch counts disagree stops at every exit", {
  skip_on_cran()
  res <- HANNUM_RES

  # provenance says one batch, coverage says two. neither count is preferred.
  bad <- res
  bad$coverage$per_clock <- c(
    bad$coverage$per_clock,
    stats::setNames(bad$coverage$per_clock, "a-second-batch")
  )

  expect_error(clocks_coverage(bad))
  expect_error(samples_coverage(bad))
  expect_error(as.data.frame(bad))
  expect_error(as.matrix(bad))
})

test_that("a clocks_coverage column appears only when the record has that fact", {
  skip_on_cran()
  plain <- clocks_coverage(HANNUM_RES)
  expect_false(any(c("normalizes", "norm_needed", "role") %in% names(plain)))

  # role: only when the record holds a routing target
  cc <- clocks_coverage(
    calc_clocks(GRIP4$DNAm, "DNAmGrip_wAge", pheno = GRIP4$pheno)
  )
  expect_true("role" %in% names(cc))

  # missing_cpgs: only when a CpG is absent
  panel <- clock_scoring_cpgs("Hannum")
  expect_false("missing_cpgs" %in% names(plain))
  thin <- HANNUM4[, setdiff(colnames(HANNUM4), panel[1:3]), drop = FALSE]
  expect_setequal(
    clocks_coverage(calc_clocks(thin, "Hannum"))[["missing_cpgs"]][[1]],
    panel[1:3]
  )

  # the norm block: only when a clock normalizes
  DNAm <- random_betas(names(clock_norm_target("DunedinPACE")), n = 4L)
  norm <- clocks_coverage(calc_clocks(DNAm, "DunedinPACE"))
  expect_true(all(c("normalizes", "norm_needed") %in% names(norm)))
  expect_true(norm[norm$clock_id == "DunedinPACE", "normalizes"])
})

test_that("all_columns is one fixed set, and never mints the batch column", {
  skip_on_cran()
  wide <- clocks_coverage(HANNUM_RES, all_columns = TRUE)
  narrow <- clocks_coverage(HANNUM_RES)

  expect_true(all(names(narrow) %in% names(wide)))
  expect_gt(ncol(wide), ncol(narrow))
  # the batch label keeps its own rule: one batch, no column, either way
  expect_false("mc_batch_id" %in% names(wide))

  # the wide frame does not change shape with the record it describes
  other <- clocks_coverage(
    calc_clocks(GRIP4$DNAm, "DNAmGrip_wAge", pheno = GRIP4$pheno),
    all_columns = TRUE
  )
  expect_equal(names(other), names(wide))

  expect_error(clocks_coverage(HANNUM_RES, all_columns = NA))
})
