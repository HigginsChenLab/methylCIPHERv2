# qc_report(): the html report and the descriptive helpers behind it.

qc_fixture <- function(n = 12L, clocks = c("Horvath1", "Hannum")) {
  DNAm <- random_betas(clock_cpgs(clocks), n = n)
  pheno <- mc_pheno(
    rownames(DNAm),
    Age = mc_ages(n),
    Female = rep(c(0L, 1L), length.out = n)
  )
  pheno[["site"]] <- rep(c("a", "b", "c"), length.out = n)
  list(
    DNAm = DNAm,
    pheno = pheno,
    result = calc_clocks(DNAm, clocks, pheno = pheno),
    clocks = clocks
  )
}

read_page <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")

test_that("qc_report() refuses a call with nothing to report on", {
  expect_error(qc_report(open = FALSE))
})

test_that("every input alone, and all three together, write one page", {
  fx <- qc_fixture()
  out <- withr::local_tempdir()
  calls <- list(
    dnam = list(DNAm = fx$DNAm, clocks = fx$clocks),
    pheno = list(pheno = fx$pheno),
    x = list(x = fx$result),
    all = list(DNAm = fx$DNAm, pheno = fx$pheno, x = fx$result, clocks = fx$clocks)
  )
  for (nm in names(calls)) {
    path <- file.path(out, paste0(nm, ".html"))
    got <- do.call(qc_report, c(calls[[nm]], list(file = path, open = FALSE)))
    expect_true(file.exists(path))
    expect_equal(got, normalizePath(path))
    page <- read_page(path)
    for (id in c("overview", "dnam", "pheno", "clocks", "bib", "notes")) {
      expect_match(page, sprintf("id=\"%s\"", id), fixed = TRUE)
    }
  }
})

test_that("the overview plots clock age against age and flags an outlier", {
  fx <- qc_fixture()
  path <- withr::local_tempfile(fileext = ".html")
  qc_report(fx$DNAm, fx$pheno, fx$result, clocks = fx$clocks, file = path, open = FALSE)
  expect_match(read_page(path), "Horvath1 against age", fixed = TRUE)

  age <- seq(20, 80, length.out = 30)
  score <- age + rep(c(-1, 1), 15)
  score[[7L]] <- score[[7L]] + 40
  expect_equal(which(qc_age_outliers(age, score)), 7L)
})

test_that("a missing input is reported as not computable, not dropped", {
  fx <- qc_fixture()
  path <- withr::local_tempfile(fileext = ".html")
  qc_report(pheno = fx$pheno, file = path, open = FALSE)
  page <- read_page(path)
  expect_match(page, "No DNAm matrix was supplied", fixed = TRUE)
  expect_match(page, "No mc_result object was supplied", fixed = TRUE)
})

test_that("warnings and messages go to the page, not the console", {
  fx <- qc_fixture()
  # predict_sex() warns on the thin sex panels and on the mismatches
  path <- withr::local_tempfile(fileext = ".html")
  expect_no_warning(expect_no_message(
    qc_report(fx$DNAm, fx$pheno, fx$result, clocks = fx$clocks,
              file = path, open = FALSE)
  ))
  expect_match(read_page(path), "id=\"notes\"", fixed = TRUE)
})

test_that("a matrix with no sex call reports no mismatch count", {
  skip_on_cran()
  # the fixture carries no chrX or chrY CpGs, so no sample is sexed
  fx <- qc_fixture()
  st <- new.env(parent = emptyenv())
  st[["notes"]] <- list()
  sec <- qc_section_dnam(st, fx$DNAm, fx$pheno, "ID", fx$clocks, NULL)
  mm <- Filter(function(cd) cd[["label"]] == "Sex mismatches", sec[["cards"]])[[1L]]
  expect_equal(mm[["status"]], "na")
})

test_that("sample ids reach the page escaped", {
  fx <- qc_fixture(n = 6L)
  DNAm <- fx$DNAm
  rownames(DNAm)[[1L]] <- "<b>bad</b>"
  DNAm[1L, 1:5] <- NA
  path <- withr::local_tempfile(fileext = ".html")
  qc_report(DNAm, clocks = fx$clocks, file = path, open = FALSE)
  page <- read_page(path)
  expect_false(grepl("<b>bad</b>", page, fixed = TRUE))
  expect_match(page, "&lt;b&gt;bad&lt;/b&gt;", fixed = TRUE)
})

test_that("the matrix pass counts the same in blocks as in one piece", {
  m <- random_betas(mc_fake_cpgs(37), n = 5)
  m[2, c(1, 9, 30)] <- NA
  m[, 4] <- NA
  m[3, 5] <- 1.5
  m[4, 6] <- -0.2
  m[5, 7] <- Inf
  one <- qc_dnam_stats(m)
  chunked <- qc_dnam_stats(m, block = 4L)
  expect_equal(chunked, one)

  expect_equal(one$n_missing, 3 + 5)
  expect_equal(one$n_cpg_all_na, 1L)
  expect_equal(one$n_cpg_any_na, 4L)
  expect_equal(one$sample_miss[[2L]], 4 / 37)
  expect_equal(one$n_above, 1)
  expect_equal(one$n_below, 1)
  expect_equal(one$n_nonfinite, 1)
  expect_equal(one$hi, 1.5)
  expect_equal(one$lo, -0.2)
})

test_that("each array is inferred from its own probe ids, with or without a suffix", {
  ref <- array_reference()
  for (a in c("450K", "EPICv1", "EPICv2", "MSA")) {
    loci <- ref$locus[ref[[paste0("on_", a)]]]
    expect_equal(qc_array(loci)$inferred, a)
  }
  v2 <- paste0(ref$locus[ref$on_EPICv2], "_BC11")
  got <- qc_array(v2)
  expect_equal(got$inferred, "EPICv2")
  expect_equal(got$n_suffixed, length(v2))
  expect_true(is.na(qc_array(mc_fake_cpgs(500))$inferred))
})

test_that("sex chromosome coverage counts against the inferred array", {
  ref <- array_reference()
  cols <- ref$locus[ref$on_450K]
  x_450k <- sum(ref$on_450K & ref$chr %in% "X")
  keep <- cols[!(cols %in% ref$locus[ref$chr %in% "Y"])]
  sx <- qc_sex_chrom(keep, integer(length(keep)), 3L, "450K")
  expect_equal(sx$expected[[1L]], x_450k)
  expect_equal(sx$coverage[[1L]], 1)
  expect_equal(sx$present[[2L]], 0L)
})

test_that("phenotype summaries match base R", {
  ph <- data.frame(
    ID = paste0("s", 1:10),
    Age = c(21, 35, 40, NA, 55, 61, 62, 70, 71, 80),
    grp = c(rep("a", 6), rep("b", 3), NA),
    stringsAsFactors = FALSE
  )
  st <- qc_pheno_stats(ph, "ID")
  age <- st[st$variable == "Age", ]
  a <- ph$Age[!is.na(ph$Age)]
  expect_equal(age$n_missing, 1L)
  expect_equal(age$mean, mean(a))
  expect_equal(age$median, stats::median(a))
  expect_equal(age$p10, unname(stats::quantile(a, 0.1)))
  expect_equal(age$p90, unname(stats::quantile(a, 0.9)))
  grp <- st[st$variable == "grp", ]
  expect_equal(grp$type, "categorical")
  expect_equal(grp$n_distinct, 2L)
  expect_match(grp$counts, "a: 6", fixed = TRUE)
})

test_that("a clock panel is counted against the columns, not scored", {
  cpgs <- clock_cpgs("Horvath1")
  keep <- thin_panel(cpgs, 0.5)
  cp <- qc_clock_panels(keep, integer(length(keep)), 4L, "Horvath1", NULL)
  row <- cp$table
  expect_equal(row$n_needed, length(cpgs))
  expect_equal(row$n_present, length(keep))
  expect_equal(row$status, "below threshold")
  expect_equal(row$samples_ok, 0L)
})

test_that("per-sample panel coverage reads the missing cells", {
  cpgs <- clock_cpgs("Hannum")
  m <- random_betas(cpgs, n = 4)
  m[1, seq_len(ceiling(0.3 * length(cpgs)))] <- NA
  s <- qc_dnam_stats(m)
  cp <- qc_clock_panels(colnames(m), s$cpg_na, 4L, "Hannum", NULL)
  cp <- qc_fill_samples_ok(cp, m)
  expect_equal(cp$table$status, "complete")
  expect_equal(cp$table$samples_ok, 3L)
})

test_that("a large scatter keeps hover titles only on the points that ask", {
  p <- svg_panel(c(0, 1), c(0, 1))
  n <- QC_TITLE_MAX + 50L
  x <- seq(0, 1, length.out = n)
  keep <- seq_len(n) %in% c(3L, 7L)
  out <- svg_points(p, x, x, titles = paste0("s", seq_len(n)), title_keep = keep)
  expect_equal(lengths(regmatches(out, gregexpr("<circle", out, fixed = TRUE))), n)
  expect_equal(lengths(regmatches(out, gregexpr("<title>", out, fixed = TRUE))), 2L)

  small <- svg_points(p, x[1:5], x[1:5], titles = paste0("s", 1:5))
  expect_equal(lengths(regmatches(small, gregexpr("<title>", small, fixed = TRUE))), 5L)
})
