# shared @param donor for @inheritParams mc-params. x is mc_result only.

#' Shared Parameters
#'
#' Parameter definitions reused across the package.
#'
#' @param DNAm A numeric matrix. The methylation beta values, with samples in
#'   the rows and CpGs in the columns.
#' @param x An `mc_result` object. The value returned by [calc_clocks()].
#' @param clocks A character vector. The clocks to score, named by clock id,
#'   group id, or tag. Each name is given one time. See [list_clocks()].
#' @param pheno A data.frame. The sample metadata, with one row for each
#'   sample. Default is `NULL`.
#' @param covariates A named character vector. Points a covariate at the column
#'   that holds it, for metadata that names its columns something else. Default
#'   is `NULL`.
#' @param normalize A named logical vector. Turns background normalization on
#'   or off for the clocks that declare a method. Default is `NULL`.
#' @param ext_data A string. The path to the directory that holds the clock
#'   assets. Default is `NULL`, which uses the assets directory.
#' @param ask A boolean. Asks for confirmation before the assets directory
#'   changes. Default is `TRUE`. Pass `FALSE` to continue without asking, in a
#'   non-interactive session.
#' @param all_columns A boolean. Returns every column, including the ones the
#'   frame leaves out by default. Default is `FALSE`.
#' @param groups A character vector. The asset groups to act on. One or more
#'   of `"PCBrainAge"`, `"PCClocks"`, `"SystemsAge"` and `"Zhang2019"`, or
#'   `"all"` for every group. Repeated values are ignored, and an empty vector
#'   selects nothing. Default is `"all"`.
#' @param long A boolean. Returns one row for each sample and clock when
#'   `TRUE`, and one row for each sample, with one column for each clock, when
#'   `FALSE`. Default is `TRUE`.
#'
#' @section The assets directory:
#' Four clock groups keep their weights in downloadable assets, outside the
#' package. `ext_data` says where to read them from, and accepts three forms.
#'
#' - `NULL` reads from the assets directory, and downloads any asset that is
#'   missing. Use [set_mc_assets_dir()] to choose that directory.
#' - A path reads only that directory, and never downloads. A missing asset
#'   is an error.
#' - Assets already in memory from [load_mc_assets()] are used directly.
#'
#' @section Normalization:
#' Some clocks declare a background normalization method. `normalize` accepts
#' four forms.
#'
#' - `NULL` leaves every clock at its own default. A clock that declares
#'   `quantile` is normalized, and a clock that declares `bmiq` is not.
#' - `TRUE` or `FALSE` sets every clock that declares a method.
#' - A character vector of clock ids turns normalization on for those clocks,
#'   and leaves every other clock at its default.
#' - A named logical vector sets the clocks it names, and leaves every other
#'   clock at its default.
#'
#' The character form only turns normalization on. To turn a method off, name
#' the clock in a named logical vector.
#'
#' Normalization needs a background panel that is much larger than the scoring
#' panel, so a matrix cut down to the scoring CpGs cannot supply it. The
#' `normalize` column of [list_clocks()] with `all_columns = TRUE` gives the
#' method each clock declares.
#'
#' @section Covariate columns:
#' Some clocks read a covariate from the sample metadata. A clock names the
#' covariate it reads, and looks for a column of that name.
#'
#' `covariates` points a covariate at a column that holds it under another
#' name. Write the covariate on the left and your own column on the right, as
#' in `covariates = c(Age = "age_yrs")`. Only a covariate this call reads can
#' be pointed at a column, and each one may be pointed once.
#'
#' A covariate that is already a column of the metadata needs no entry. The
#' `covariates` column of [list_clocks()] with `all_columns = TRUE` gives the
#' covariates each clock reads.
#'
#' A pointer moves the name and nothing else. `Female` pointed at a column that
#' holds `1` for male scores every clock that reads sex, and scores all of them
#' wrong, so check what the column means before you point at it.
#'
#' @section Clocks that use all the samples:
#' Some clocks depend on information from all the samples, such as a z-score.
#' When `x` holds more than one batch, these clocks take their value from
#' every sample in `x`, and not from one batch alone. This is the same
#' calculation as [refinalize_clocks()].
#'
#' @name mc-params
#' @keywords internal
NULL
