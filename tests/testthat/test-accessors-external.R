# External clocks source coef/impute from the loaded pack.

# Minimal PCClocks pack for tests.
fake_pcclocks_pack <- function() {
  list(
    group_id = "PCClocks",
    cpgs = c("cg0001", "cg0002"),
    coefficient_matrix = matrix(
      c(1, 2, 3, 4),
      nrow = 2,
      dimnames = list(NULL, c("PCADM", "PCGrimAge"))
    ),
    impute = c(0.1, 0.2)
  )
}

test_that("clock_coefs() pulls an external clock's named column from the pack", {
  packs <- list(PCClocks = fake_pcclocks_pack())
  co <- clock_coefs("PCADM", packs)

  expect_identical(co, c(cg0001 = 1, cg0002 = 2))
})

test_that("clock_impute_ref() reads external vendor means from the pack $impute vector", {
  packs <- list(PCClocks = fake_pcclocks_pack())
  ref <- clock_impute_ref("PCADM", packs)
  expect_identical(ref, c(cg0001 = 0.1, cg0002 = 0.2))
})

test_that("external accessors error when the group's pack is not in the registry", {
  expect_error(clock_coefs("PCADM", NULL))
  expect_error(clock_coefs("PCADM", list()))
  expect_error(clock_impute_ref("PCADM", list()))
})

test_that("clock_coefs() errors when the external clock is not a pack column", {
  pack <- list(
    group_id = "PCClocks",
    cpgs = "cg0001",
    coefficient_matrix = matrix(1, 1, dimnames = list(NULL, "PCGrimAge")),
    impute = 0.5
  )
  expect_error(clock_coefs("PCADM", list(PCClocks = pack)))
})

test_that("bundled clocks ignore `packs` and still resolve from mc_bundles", {
  expect_identical(
    clock_coefs("Hannum"),
    clock_coefs("Hannum", list(PCClocks = 1))
  )
})
