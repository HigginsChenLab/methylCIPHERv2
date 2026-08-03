# karyotype call has no parity fixture. unit-test the map.

test_that("the declared quadrants map, including the corner never tested", {
  kc <- karyotype_spec()
  scores <- list(
    chrX = c(-1, 1, -1, 1, 0),
    chrY = c(1, 1, -1, -1, 0)
  )
  # 4th falls to default (no rule). 5th is the exact-zero case.
  expect_equal(
    apply_karyotype(scores, kc),
    c("Male", "47,XXY", "45,XO", "Female", "Female")
  )
})

test_that("a sample missing either score gets no call", {
  kc <- karyotype_spec()
  scores <- list(chrX = c(NA, -1, NA), chrY = c(1, NA, NA))
  expect_true(all(is.na(apply_karyotype(scores, kc))))
})

test_that("operand order is checked against the input ids", {
  kc <- karyotype_spec()
  # swapping the inputs alone would invert every call, silently
  swapped <- kc
  swapped[["inputs"]] <- rev(kc[["inputs"]])
  expect_error(karyotype_inputs(swapped))
})

test_that("predict_sex returns both PCs and a call per sample", {
  ids <- c("DNAmSex_Wang_ChrX", "DNAmSex_Wang_ChrY")
  sim <- sim_DNAm(ids, n = 5L)
  out <- predict_sex(sim$DNAm, sim$pheno)

  expect_equal(names(out), c("ID", ids, "predicted_sex"))
  expect_equal(nrow(out), 5L)

  kc <- karyotype_spec()
  labels <- c(
    as.character(kc[["default"]]),
    vapply(kc[["rules"]], function(r) as.character(r[["predicted_sex"]]), "")
  )
  expect_true(all(out$predicted_sex %in% labels))
})
