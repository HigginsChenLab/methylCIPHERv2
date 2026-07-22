# Dev-only helpers. Build-ignored; available after devtools::load_all().

# Run the cohort parity tier (sets METHYLCIPHER_PARITY=1 for this test run).
test_parity <- function(filter = "fixtures-parity", ...) {
  withr::with_envvar(
    c(METHYLCIPHER_PARITY = "1"),
    devtools::test(filter = filter, ...)
  )
}
