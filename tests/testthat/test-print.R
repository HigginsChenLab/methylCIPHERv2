# shared printer grammar (R/print.R). class tag and return value are the contract.

test_that("every mc_* printer runs and returns its input invisibly", {
  sim <- sim_DNAm("Hannum", n = 3L)
  res <- calc_clocks(sim[["DNAm"]], "Hannum", pheno = sim[["pheno"]])
  cit <- cite_clocks("Hannum")
  # built here, not loaded -- load_mc_assets() would download
  assets <- structure(
    list(FakeGroup = list(clocks = c("a", "b"), cpgs = c("cg1", "cg2"))),
    class = c("mc_assets", "list")
  )

  for (x in list(sim, res, cit, assets)) {
    got <- suppressMessages(capture.output(out <- print(x)))
    expect_equal(out, x)
  }

  # cat printers write stdout. mc_citation uses the message stream.
  expect_output(print(sim), "<mc_sim>", fixed = TRUE)
  expect_output(print(res), "<mc_result>", fixed = TRUE)
  expect_output(
    print(assets),
    "$FakeGroup [2 clocks, 2 CpGs]",
    fixed = TRUE
  )
})

test_that("a block is indented under its header, and pads no line", {
  skip_on_cran()
  sim <- sim_DNAm("Hannum", n = 3L)
  txt <- utils::capture.output(print(sim))
  body <- txt[grepl("[^[:space:]]", txt) & !grepl("^[<$]", txt)]

  expect_true(all(startsWith(body, MC_INDENT)))
  # a padded column must not reach the end of a line
  expect_false(any(grepl("[[:space:]]$", txt)))
  # a whole axis states its size, and drops the "of" that means it was cut
  expect_true(any(grepl("3 rows", txt, fixed = TRUE)))

  # one rule under the header, and nothing else added
  grid <- fmt_grid(data.frame(a = c("x", "yy"), n = c(1L, 20L)))
  expect_equal(length(grid), 4L)
  expect_match(grid[[2L]], "^[- ]+$")

  # a grid too wide for the terminal continues below rather than being folded
  # mid-cell by the terminal itself
  wide <- as.data.frame(matrix(1:6, nrow = 1L))
  expect_gt(length(fmt_grid(wide, width = 10L)), 3L)
})

test_that("a run with no pheno argument still carries the id column", {
  DNAm <- random_betas(clock_scoring_cpgs("Hannum"), n = 3L)
  res <- calc_clocks(DNAm, "Hannum")

  expect_equal(names(res[["pheno"]]), "ID")
  expect_equal(res[["pheno"]][["ID"]], rownames(DNAm))
  expect_output(print(res), "pheno", fixed = TRUE)
})
