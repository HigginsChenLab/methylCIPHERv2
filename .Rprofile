# Interactive convenience only. Do not make these unconditional again.
# R sources this file for every Rscript started in the repo root, which includes
# the one CI runs to set up the library before a single dependency is installed.
# A bare library() there is a hard error that fails the job, not a warning.
if (interactive()) {
  for (pkg in c("devtools", "testthat")) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    }
  }
}

options(tibble.width = Inf)
