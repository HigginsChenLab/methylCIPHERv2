# shared printer grammar (R/print.R). class tag and return value are the contract.

test_that("every mc_* printer runs and returns its input invisibly", {
  sim <- sim_DNAm("Hannum", n = 3L)
  res <- calc_clocks(sim[["DNAm"]], "Hannum", pheno = sim[["pheno"]])
  cit <- cite_clocks("Hannum")

  for (x in list(sim, res, cit)) {
    got <- suppressMessages(capture.output(out <- print(x)))
    expect_equal(out, x)
  }

  # cat printers write stdout. mc_citation uses the message stream.
  expect_output(print(sim), "<mc_sim>", fixed = TRUE)
  expect_output(print(res), "<mc_result>", fixed = TRUE)
})

test_that("a run with no pheno argument still carries the id column", {
  DNAm <- random_betas(clock_scoring_cpgs("Hannum"), n = 3L)
  res <- calc_clocks(DNAm, "Hannum")

  expect_equal(names(res[["pheno"]]), "ID")
  expect_equal(res[["pheno"]][["ID"]], rownames(DNAm))
  expect_output(print(res), "pheno", fixed = TRUE)
})
