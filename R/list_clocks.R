# browsable catalog menu for the clocks= argument

# default menu columns.
LIST_CLOCKS_DEFAULT_COLS <- c(
  "clock_id",
  "group_id",
  "covariates",
  "external",
  "tags"
)

#' Epigenetic Clock Catalog
#'
#' Lists the clocks in the catalog, with the group and tags of each one.
#'
#' @param group A character vector. Keeps only the clocks in these groups.
#'   Default is `NULL`, which keeps every group.
#' @param tag A character vector. Keeps only the clocks that carry one of
#'   these tags. Default is `NULL`, which applies no tag filter.
#' @param pattern A string. A regular expression matched against the clock id
#'   and the group id. Default is `NULL`, which applies no pattern filter.
#' @inheritParams mc-params
#'
#' @details
#' Valid values for `tag` are the names of [list_clock_tags()].
#'
#' `clock_id` names the token to pass to `clocks` in [calc_clocks()].
#' `covariates` names the [calc_clocks()] `pheno` columns a clock needs, and
#' `external` is `TRUE` for a clock whose weights are a download.
#'
#' `all_columns = TRUE` adds three more columns.
#'
#' - `group_size` counts the clocks a group token expands to.
#' - `batch_dependent` is `TRUE` for a clock whose score depends on the other
#'   samples scored with it.
#' - `normalize` names the background normalization scheme a clock declares,
#'   and is empty for a clock that declares none. `"quantile"` is on by
#'   default and `"bmiq"` is off. The `normalize` argument of [calc_clocks()]
#'   turns either one on or off.
#'
#' @returns A data.frame. One row for each clock that the `clocks` argument of
#'   [calc_clocks()] accepts.
#'
#' @seealso
#' - [list_clock_tags()] for the tags a `tag` value accepts.
#' - [clock_cpgs()] for the CpGs a set of clocks needs.
#' - [list_mc_assets()] for the assets an external clock needs.
#'
#' @examples
#' list_clocks(pattern = "^Horvath")
#' nrow(list_clocks(tag = "mortality"))
#' list_clocks(group = "Dunedin", all_columns = TRUE)
#'
#' @export
list_clocks <- function(
  group = NULL,
  tag = NULL,
  pattern = NULL,
  all_columns = FALSE
) {
  # one of each token is the ceiling, and it runs ahead of every other line so
  # an oversized vector reaches neither the pool nor the nearest-match search.
  checkmate::assert_character(
    group,
    null.ok = TRUE,
    any.missing = FALSE,
    unique = TRUE,
    max.len = length(unique(mc_index[["group_id"]]))
  )
  checkmate::assert_character(
    tag,
    null.ok = TRUE,
    any.missing = FALSE,
    unique = TRUE,
    max.len = length(MC_TAGS)
  )
  checkmate::assert_subset(tag, names(MC_TAGS), empty.ok = TRUE)
  checkmate::assert_string(pattern, null.ok = TRUE)
  checkmate::assert_flag(all_columns)

  # a sex-routed member is not a clock a user can request, so it is not listed
  idx <- mc_index[
    !mc_index[["clock_id"]] %in% names(sex_routed_members()[["alias"]]),
    ,
    drop = FALSE
  ]

  # what a group token expands to
  group_size <- table(idx[["group_id"]])

  out <- data.frame(
    clock_id = idx[["clock_id"]],
    group_id = idx[["group_id"]],
    group_size = as.integer(group_size[idx[["group_id"]]]),
    covariates = vapply(
      idx[["covariates_required"]],
      paste,
      character(1L),
      collapse = ", "
    ),
    external = idx[["external_group"]],
    batch_dependent = idx[["batch_dependent"]],
    # the scheme actually applied, so a declared but inexpressible one reads ""
    normalize = vapply(
      idx[["clock_id"]],
      function(id) {
        scheme <- clock_norm_scheme(id)
        if (scheme %in% NORM_SCHEMES) scheme else ""
      },
      character(1L),
      USE.NAMES = FALSE
    ),
    stringsAsFactors = FALSE,
    row.names = NULL
  )

  tag_ids <- lapply(names(MC_TAGS), resolve_clocks)
  names(tag_ids) <- names(MC_TAGS)
  out[["tags"]] <- vapply(
    out[["clock_id"]],
    function(id) {
      paste(
        names(MC_TAGS)[vapply(tag_ids, function(x) id %in% x, logical(1L))],
        collapse = ", "
      )
    },
    character(1L),
    USE.NAMES = FALSE
  )

  if (!is.null(group)) {
    unknown <- setdiff(group, out[["group_id"]])
    if (length(unknown)) {
      pool <- suggestion_pools()[["groups"]]
      cli::cli_abort(
        c(
          "{length(unknown)} name{?s} in {.arg group} {cli::qty(unknown)}{?is/are}
           not a group: {.val {capped_vals(unknown)}}.",
          capped_bullets(
            unknown,
            function(toks) {
              vapply(
                toks,
                function(tok) {
                  cli::format_inline(
                    "{.val {tok}}. Did you mean
                     {.or {.val {did_you_mean(tok, pool)}}}?"
                  )
                },
                character(1L)
              )
            },
            # one adist pass per token, so the search is capped, not the text
            n = MC_SUGGEST_CAP
          ),
          "i" = "Call {.fn list_clocks} with no arguments to see every group."
        ),
        call = NULL
      )
    }
    out <- out[out[["group_id"]] %in% group, , drop = FALSE]
  }

  if (!is.null(tag)) {
    # one call, not one per tag: resolve_clocks() already takes the vector and
    # unions it. an empty tag selects nothing, as it always has.
    keep <- if (length(tag)) resolve_clocks(tag) else character(0)
    out <- out[out[["clock_id"]] %in% keep, , drop = FALSE]
  }

  if (!is.null(pattern)) {
    hit <- grepl(pattern, out[["clock_id"]], ignore.case = TRUE) |
      grepl(pattern, out[["group_id"]], ignore.case = TRUE)
    out <- out[hit, , drop = FALSE]
  }

  out <- out[order(out[["group_id"]], out[["clock_id"]]), , drop = FALSE]
  row.names(out) <- NULL
  if (all_columns) {
    return(out)
  }
  out[, LIST_CLOCKS_DEFAULT_COLS, drop = FALSE]
}
