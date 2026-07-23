# dev-only helpers -- build-ignored, available after devtools::load_all()

# run the cohort parity tier (sets MC_PARITY=1 for this test run)
test_parity <- function(filter = "fixtures-parity", ...) {
  withr::with_envvar(
    c(MC_PARITY = "1"),
    devtools::test(filter = filter, ...)
  )
}

scratch <- function() {
  if (!dir.exists("dev")) {
    dir.create("dev")
  }
  file.edit("dev/scratch.R")
}
