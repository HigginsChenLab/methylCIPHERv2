# descriptions for the values of the clock_id column (mc_codebook join)

#' Clock Codebook
#'
#' Describes a set of clocks, or the clocks scored in an `mc_result` object.
#'
#' @param x A character vector. The clock ids, group ids or tags to describe,
#'   or an `mc_result` object from [calc_clocks()].
#' @param ... Not used.
#'
#' @details
#' A character vector describes the clocks it names. A group id describes every
#' clock in the group, and a tag describes every clock the tag expands to. See
#' [list_clocks()] and [list_clock_tags()]. An `mc_result` object describes the
#' clocks in its scores.
#'
#' The first row reports the version of the clock descriptions. The second row
#' describes the `clock_id` column of [as.data.frame()]. Each row after that is
#' one value of that column.
#'
#' A clock with no description on record reads `NA`.
#'
#' @returns A data frame. One row for each described clock, with the `column`
#'   it appears as and a one sentence `description` of it.
#'
#' @examples
#' codebook(c("Horvath1", "Hannum"))
#'
#' sim <- sim_DNAm("Hannum", n = 5)
#' res <- calc_clocks(sim[["DNAm"]], "Hannum")
#' codebook(res)
#'
#' @export
codebook <- function(x, ...) {
  UseMethod("codebook")
}

#' @rdname codebook
#' @export
codebook.character <- function(x, ...) {
  new_codebook(resolve_clocks(x))
}

#' @rdname codebook
#' @export
codebook.mc_result <- function(x, ...) {
  new_codebook(colnames(x[["scores"]]))
}

#' @rdname codebook
#' @export
codebook.default <- function(x, ...) {
  cli::cli_abort(
    c(
      "{.obj_type_friendly {x}} has no {.fn codebook} method.",
      "i" = "Pass a character vector of clock ids or group ids.",
      "i" = "Or pass an {.cls mc_result} from {.fn calc_clocks}."
    ),
    call = NULL
  )
}

# the version row and the clock_id row lead, then one row per clock
new_codebook <- function(ids) {
  hit <- match(ids, mc_codebook[["clock_id"]])
  data.frame(
    column = c("meta_version", "clock_id", ids),
    description = c(
      attr(mc_codebook, "version"),
      "The clock that produced the score.",
      mc_codebook[["description"]][hit]
    ),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}
