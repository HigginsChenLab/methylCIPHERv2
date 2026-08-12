# karyotype call from the two DNAmSex_Wang sex PCs. rules come from the catalog.

# the one group that answers this question
SEX_GROUP <- "DNAmSex_Wang"

# companion columns to the declared karyotype output_column
SEX_ANEUPLOIDY <- "sex_aneuploidy"
RECORDED_SEX <- "recorded_sex"
SEX_MISMATCH <- "sex_mismatch"

# which emitted label a binary Female column records as. euploidy is declared,
# this correspondence is not, so it stays here.
BINARY_CALLS <- c(female = "Female", male = "Male")

# declared karyotype_call block for SEX_GROUP.
karyotype_spec <- function() {
  kc <- group_entry(SEX_GROUP)[["routing"]][["karyotype_call"]]
  if (is.null(kc)) {
    catalog_bug("Group %s declares no karyotype_call.", SEX_GROUP)
  }
  kc
}

# operand keys a rule set names, in first-appearance order
karyotype_keys <- function(kc) {
  keys <- unique(unlist(lapply(kc[["rules"]], names), use.names = FALSE))
  setdiff(keys, as.character(kc[["output_column"]]))
}

# operand key -> clock id. checked against declared order.
karyotype_inputs <- function(kc) {
  ids <- as.character(unlist(kc[["inputs"]]))
  keys <- karyotype_keys(kc)
  if (length(keys) != length(ids)) {
    catalog_bug(
      "%s: karyotype_call declares %d input(s) for %d rule operand(s).",
      SEX_GROUP,
      length(ids),
      length(keys)
    )
  }
  bad <- !endsWith(tolower(ids), tolower(keys))
  if (any(bad)) {
    catalog_bug(
      "%s: karyotype operand '%s' does not name input %s.",
      SEX_GROUP,
      keys[bad][[1L]],
      ids[bad][[1L]]
    )
  }
  stats::setNames(ids, keys)
}

# declared condition ("<0", ">0") -> predicate. threshold is read, not assumed.
karyotype_predicate <- function(cond) {
  cond <- as.character(cond)
  op <- sub("^([<>]=?).*$", "\\1", cond)
  rhs <- suppressWarnings(as.numeric(sub("^[<>]=?", "", cond)))
  if (!(op %in% c("<", "<=", ">", ">=")) || is.na(rhs)) {
    catalog_bug("%s: cannot read karyotype condition '%s'.", SEX_GROUP, cond)
  }
  function(x) match.fun(op)(x, rhs)
}

# operand scores plus declared rules -> one call per sample.
apply_karyotype <- function(scores, kc) {
  out_col <- as.character(kc[["output_column"]])
  n <- length(scores[[1L]])
  call <- rep(as.character(kc[["default"]]), n)

  for (rule in kc[["rules"]]) {
    hit <- rep(TRUE, n)
    for (key in setdiff(names(rule), out_col)) {
      if (is.null(scores[[key]])) {
        catalog_bug(
          "%s: karyotype rule names unknown operand '%s'.",
          SEX_GROUP,
          key
        )
      }
      hit <- hit & karyotype_predicate(rule[[key]])(scores[[key]])
    }
    # an NA score matches nothing.
    hit[is.na(hit)] <- FALSE
    call[hit] <- as.character(rule[[out_col]])
  }

  # unscorable samples get no call (not a default label).
  call[Reduce(`|`, lapply(scores, is.na))] <- NA_character_
  call
}

# declared euploidy, one entry per emitted label. sync gates the coverage.
karyotype_euploid <- function(kc) {
  e <- kc[["euploid"]]
  if (is.null(e)) {
    catalog_bug("%s: karyotype_call declares no euploid map.", SEX_GROUP)
  }
  e
}

# TRUE where the call is a karyotype the catalog declares non-euploid.
# an unscored sample has no call, so it gets no verdict.
aneuploidy_of <- function(pred, kc) {
  e <- karyotype_euploid(kc)
  unknown <- setdiff(pred[!is.na(pred)], names(e))
  if (length(unknown)) {
    catalog_bug(
      "%s: karyotype_call declares no euploid entry for '%s'.",
      SEX_GROUP,
      unknown[[1L]]
    )
  }
  unname(!e[pred])
}

# every call the rule table can emit, its default included
karyotype_calls <- function(kc) {
  out_col <- as.character(kc[["output_column"]])
  unique(c(
    as.character(kc[["default"]]),
    vapply(kc[["rules"]], function(r) as.character(r[[out_col]]), character(1L))
  ))
}

# map pheno Female (1/0) onto the rule table labels. refuse non-0/1 values.
recorded_from_female <- function(female) {
  checkmate::assert_integerish(
    female,
    lower = 0,
    upper = 1,
    any.missing = TRUE,
    null.ok = FALSE,
    .var.name = "pheno$Female"
  )
  # na carries through: an unrecorded sex is not a disagreement
  ifelse(
    as.integer(female) == 1L,
    BINARY_CALLS[["female"]],
    BINARY_CALLS[["male"]]
  )
}

# left join recorded sex onto calls by id, never by row order.
# pheno is already canonicalized, so Female is the caller's pointed column too.
attach_recorded <- function(out, pheno, pheno_id, pred, kc) {
  if (is.null(pheno)) {
    return(out)
  }
  if (!"Female" %in% names(pheno)) {
    say_no_recorded()
    return(out)
  }
  missing_labels <- setdiff(BINARY_CALLS, karyotype_calls(kc))
  if (length(missing_labels)) {
    catalog_bug(
      "%s: karyotype_call emits no '%s' call to compare a recorded sex against.",
      SEX_GROUP,
      missing_labels[[1L]]
    )
  }

  idx <- id_index(
    out[[pheno_id]],
    as.character(pheno[[pheno_id]]),
    "attach_recorded"
  )
  recorded <- recorded_from_female(pheno[["Female"]][idx])
  out[[RECORDED_SEX]] <- recorded
  # only a euploid call is comparable against a binary column
  comparable <- !is.na(pred) & !aneuploidy_of(pred, kc)
  out[[SEX_MISMATCH]] <- !is.na(recorded) & comparable & pred != recorded
  out
}

# coverage of each scored panel, widened onto the call. one row per
# (sample, clock) survives the score filter, so each clock gives two columns.
attach_coverage <- function(out, res, ids, pheno_id) {
  cov <- sample_coverage_rows(res)
  cov <- cov[cov[["panel"]] == "score", , drop = FALSE]

  for (id in ids) {
    rows <- cov[cov[["clock_id"]] == id, , drop = FALSE]
    # a sample with no counted row has no coverage of its own, hence NA
    idx <- id_index(out[[pheno_id]], rows[["id"]], "attach_coverage", "na")
    out[[paste0(id, "_coverage")]] <- rows[["coverage"]][idx]
    out[[paste0(id, "_note")]] <- rows[["note"]][idx]
  }
  out
}

# a supplied pheno with no sex column. pheno = NULL is silent.
say_no_recorded <- function() {
  cli::cli_inform(c(
    "{.arg pheno} has no {.field Female} column, so the result carries no
     {.field {RECORDED_SEX}} column and no {.field {SEX_MISMATCH}} column.",
    "i" = "Pass the column that holds the recorded sex to {.arg covariates},
           as {.code covariates = c(Female = \"my_column\")}."
  ))
  invisible(NULL)
}

say_mismatch <- function(out) {
  n <- sum(out[[SEX_MISMATCH]])
  if (!n) {
    return(invisible(NULL))
  }
  cli::cli_inform(c(
    "!" = "{n} sample{?s} {cli::qty(n)}{?has/have} a predicted sex that does
           not match the {.field Female} column in {.arg pheno}.",
    "i" = "The {.field {SEX_MISMATCH}} column marks
           {cli::qty(n)}{?that sample/those samples}.",
    "i" = "A mismatch can come from the recorded sex or from the array data.
           Check both sources before you correct either one."
  ))
  invisible(NULL)
}

#' Predicted Sex Karyotype
#'
#' Predicts sex and identifies sex chromosome aneuploidy.
#'
#' @inheritParams mc-params
#' @param ... Passed to [calc_clocks()].
#'
#' @inheritSection mc-params Covariate columns
#'
#' @references
#' Wang Y, Hannon E, Grant OA, Gorrie-Stone TJ, Kumari M, Mill J, Zhai X,
#' McDonald-Maier KD, Schalkwyk LC (2021). DNA methylation-based sex
#' classifier to predict sex and identify sex chromosome aneuploidy.
#' *BMC Genomics*, 22(1), 484. \doi{10.1186/s12864-021-07675-2}
#'
#' @details
#' This is a re-implementation of the sex prediction algorithm of the
#' wateRmelon package.
#'
#' `predicted_sex` is one of `"Male"`, `"Female"`, `"47,XXY"`, or `"45,XO"`.
#' A sample missing either score gets `NA`, not a default call.
#'
#' `sex_aneuploidy` is `TRUE` where the call is a sex chromosome aneuploidy,
#' and `FALSE` where it is not. It is `NA` where there is no call. The
#' classifier tests for `"Male"`, `"47,XXY"` and `"45,XO"`, and gives
#' `"Female"` to a sample that matches none of the three. A `FALSE` therefore
#' means that no aneuploidy was found. It does not confirm a euploid
#' karyotype.
#'
#' When `pheno` has a `Female` column, coded `0` or `1`, the result also
#' carries `recorded_sex` and `sex_mismatch`. `sex_mismatch` is `TRUE` only
#' where `predicted_sex` disagrees with a binary `recorded_sex`. A
#' `"47,XXY"` or `"45,XO"` call is never flagged, because a binary `Female`
#' column cannot record it.
#'
#' `predict_sex()` reads `Female` itself, and the two clocks it scores read no
#' covariate. Pass a column of another name to `covariates`, as
#' `covariates = c(Female = "sex_f")`. `pheno` with no `Female` column builds
#' no comparison, and says so.
#'
#' Each score carries the coverage of its own panel and the note for the same
#' sample. `DNAmSex_Wang_ChrX_coverage` and `DNAmSex_Wang_ChrY_coverage` give
#' the part of each panel that `DNAm` holds for that sample.
#' `DNAmSex_Wang_ChrX_note` and `DNAmSex_Wang_ChrY_note` give the note that
#' [samples_coverage()] gives for the same sample and clock. The two panels
#' are of very different sizes, so they are counted apart.
#'
#' These columns qualify a call. A sample that covers little of a panel can
#' still reach a call, and `sex_aneuploidy` reads `FALSE` for that sample and
#' for a sample on a full panel alike. A note is present where the score is
#' `NA`, and the coverage can still be `1`. A sample with no spread across the
#' reference domain is the case where that happens.
#'
#' @returns A data frame. One row for each sample, with the
#'   `DNAmSex_Wang_ChrX` and `DNAmSex_Wang_ChrY` scores, `predicted_sex`,
#'   `sex_aneuploidy`, and, when `pheno` has a `Female` column,
#'   `recorded_sex` and `sex_mismatch`. Each score also has a `_coverage`
#'   column and a `_note` column, named after the score.
#'
#' @seealso
#' - [calc_accel()] for the age acceleration of each sample.
#' - [score_associations()] for how each clock tracks age against a reference.
#'
#' @examples
#' sim <- sim_DNAm("DNAmSex_Wang", n = 6, Female = TRUE)
#' predict_sex(sim[["DNAm"]], sim[["pheno"]])
#'
#' @export
predict_sex <- function(DNAm, pheno = NULL, covariates = NULL, ...) {
  kc <- karyotype_spec()
  map <- karyotype_inputs(kc)

  # this call reads Female itself. the scored clocks declare their own.
  reads <- union(
    unlist(lapply(unname(map), clock_covariates_required), use.names = FALSE),
    "Female"
  )
  # above both readers: calc_clocks()'s pheno checks and the join below
  pheno <- canonicalize_covariates(pheno, covariates, reads)

  # both members are scored together -- neither is interpretable alone
  res <- calc_clocks(DNAm, unname(map), pheno = pheno, covariates = NULL, ...)
  out <- as.data.frame(res, long = FALSE)

  scores <- lapply(map, function(id) out[[id]])
  pred <- apply_karyotype(scores, kc)
  out[[as.character(kc[["output_column"]])]] <- pred
  out[[SEX_ANEUPLOIDY]] <- aneuploidy_of(pred, kc)

  pheno_id <- res[["provenance"]][["pheno_id"]]
  # Female is not a required covariate. comparison reads the caller's pheno.
  out <- attach_recorded(out, pheno, pheno_id, pred, kc)
  if (SEX_MISMATCH %in% names(out)) {
    say_mismatch(out)
  }
  # last: diagnostics sit after the answer they qualify
  attach_coverage(out, res, unname(map), pheno_id)
}
