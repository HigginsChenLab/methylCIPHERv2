# Contributing to methylCIPHERv2

This document describes how to propose a change to methylCIPHERv2.

## Fixing typos

You can fix a typo, a spelling mistake, or a grammatical error in the
documentation from the GitHub web interface, as long as you edit the
source file. For a function topic that is the
[roxygen2](https://roxygen2.r-lib.org/articles/roxygen2.html) comment
above the function in an `.R` file, not the generated file under `man/`.
The first line of every generated file names the `.R` file it came from.

## Bigger changes

For a bigger change, open an issue first and confirm that the change is
wanted. For a bug, open an issue with a minimal
[reprex](https://www.tidyverse.org/help/#reprex).

The tidyverse team publishes a set of [code review
principles](https://code-review.tidyverse.org/). The chapters written
for authors are worth reading before a first pull request. This package
treats them as recommended reading rather than as its own process.

### Pull request process

- Fork the repository and clone your fork.
  `usethis::create_from_github("HigginsChenLab/methylCIPHERv2", fork = TRUE)`
  does both.

- Install the dependencies with
  `pak::local_install_deps(dependencies = TRUE)`. Every dependency is on
  CRAN.

- The package contains compiled code, so a C++ toolchain is required. On
  Windows that is Rtools. After you edit a file under `src/`, run
  `pkgbuild::compile_dll(".", force = TRUE)`. Otherwise
  [`devtools::load_all()`](https://devtools.r-lib.org/reference/load_all.html)
  reuses the old library and the changed kernel does not exist.

- Create a branch for the change.
  `usethis::pr_init("brief-description-of-change")` does this. Open the
  pull request against `main`. Do not push to `main`.

- Run
  [`devtools::test()`](https://devtools.r-lib.org/reference/test.html)
  before you push.

- Run
  [`devtools::document()`](https://devtools.r-lib.org/reference/document.html)
  when you add or change a roxygen tag, and commit the regenerated
  `NAMESPACE` and `man/` files with the source. Never edit those two by
  hand. `document()` rewrites them and drops a hand-made change without
  a warning.

- [`devtools::check()`](https://devtools.r-lib.org/reference/check.html)
  is optional. It needs pandoc for the vignette and a LaTeX toolchain
  for the manual. State in the pull request whether you ran it.

### Code style

- Format R code with [Air](https://posit-dev.github.io/air/). Run
  `air format .` at the package root. The `air.toml` file at the root
  fixes the settings, so every contributor gets the same result.

- Text that a user can see follows the rules in `dev/WRITING.md`. Read
  that file before you edit a roxygen block, the README, a vignette, or
  a message. `lint_roxygen()` and `lint_seealso()` in `R/dev-utils.R`
  must both return nothing.

- Write plain ASCII in every file. Use the ASCII forms `--`, `->` and
  `>=` rather than the typographic characters.

### Tests

The suite has three tiers.
[`devtools::test()`](https://devtools.r-lib.org/reference/test.html)
runs the two that need no extra data. The third tier compares scores
against fixtures held in a private repository, and it skips unless those
fixtures are staged, so a contributor never needs them.

A test asserts what
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
returns, not how it is wired. A test that fails after a change with no
effect on the output is too specific.

## Design decisions

The package keeps a decision log that records why it works the way it
does. That log is maintainer-side and is not part of the repository, so
there is no file for you to edit. If a change reverses an earlier
approach, describe it in the pull request instead: what the earlier
approach was, and what makes the new one better. The maintainer records
it from there.

## Code of Conduct

The methylCIPHERv2 project is released with a [Contributor Code of
Conduct](https://HigginsChenLab.github.io/methylCIPHERv2/CODE_OF_CONDUCT.md).
By contributing to this project you agree to abide by its terms.
