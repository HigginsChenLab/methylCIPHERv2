# check_DNAm(): orientation, EPICv2/MSA suffixes, shape and name refusals,
# plus the front-door arguments that name a column or a count.

test_that("a malformed DNAm is refused", {
  x <- random_betas(mc_fake_cpgs(40), n = 6)
  expect_error(check_DNAm(as.data.frame(x)))
  expect_error(check_DNAm(seq_len(10)))

  # sample ids are mandatory
  no_ids <- x
  rownames(no_ids) <- NULL
  expect_error(check_DNAm(no_ids))
})

# a name nothing can join on or look up, refused where it enters
test_that("unusable sample and CpG names are refused", {
  m <- random_betas(mc_fake_cpgs(40), n = 4)
  expect_silent(check_DNAm(m))

  # sample ids are half of the pheno join key, and the pheno half refuses NA
  na_id <- m
  rownames(na_id)[[2]] <- NA
  expect_error(check_DNAm(na_id))
  empty_id <- m
  rownames(empty_id)[[2]] <- ""
  expect_error(check_DNAm(empty_id))

  # a CpG under either name can never match a declared panel
  na_cpg <- m
  colnames(na_cpg)[[2]] <- NA
  expect_error(check_DNAm(na_cpg))
  empty_cpg <- m
  colnames(empty_cpg)[[2]] <- ""
  expect_error(check_DNAm(empty_cpg))
})

test_that("an argument is held to the type its documentation states", {
  tiny <- random_betas(mc_fake_cpgs(5), n = 2)
  # "" reached $pheno, and as.data.frame() emitted a column with no name
  expect_error(calc_clocks(tiny, "Hannum", pheno_id = ""))
  # documented as a single whole number, and gated by nothing
  expect_error(sim_DNAm("Hannum", n = 2.7))
  expect_error(sim_DNAm("Hannum", n = c(3, 4)))
  expect_error(sim_DNAm("Hannum", n = 0))
})

test_that("orientation is reported, and a tall cohort is not mistaken for it", {
  expect_silent(check_DNAm(random_betas(mc_fake_cpgs(40), n = 6)))

  # regex kept: transposed and unrecognizable-names are two distinct warnings.
  expect_warning(
    check_DNAm(t(random_betas(mc_fake_cpgs(40), n = 6))),
    "transposed"
  )

  # one clock over a large cohort is legitimately taller than it is wide
  expect_silent(check_DNAm(random_betas(mc_fake_cpgs(3), n = 20)))
  unnamed <- random_betas(mc_fake_cpgs(3), n = 20)
  colnames(unnamed) <- paste0("v", seq_len(ncol(unnamed)))
  expect_warning(check_DNAm(unnamed))
})

test_that("replicate suffixes are reported, sparse ones included", {
  skip_on_cran()
  # the scan is a bounded sample, so a sparse case is the one worth pinning
  ids <- mc_fake_cpgs(400)
  ids[c(5, 200, 399)] <- paste0(ids[c(5, 200, 399)], "_TC11")
  expect_warning(check_DNAm(random_betas(ids, n = 3)))

  # retroelement panels carry ch... ids with underscores that are not replicate addresses.
  quiet <- c(
    mc_fake_cpgs(20),
    "ch.13.39564907R_II_R_O_37491",
    "ch.2.30415474F_II_F_O_37488"
  )
  expect_silent(check_DNAm(random_betas(quiet, n = 6)))
})
