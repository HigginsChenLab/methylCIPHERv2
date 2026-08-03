# karyotype call from the two DNAmSex_Wang sex PCs. rules come from the catalog.

# the one group that answers this question
SEX_GROUP <- "DNAmSex_Wang"

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

#' Stub
#'
#' Rcpp needs some roxygen2 stub
#'
#' @param DNAm x
#' @param pheno x
#' @param ... x
#'
#' @returns x
#' @export
predict_sex <- function(DNAm, pheno = NULL, ...) {
  kc <- karyotype_spec()
  map <- karyotype_inputs(kc)

  # both members are scored together -- neither is interpretable alone
  res <- calc_clocks(DNAm, unname(map), pheno = pheno, ...)
  out <- as.data.frame(res, long = FALSE)

  scores <- lapply(map, function(id) out[[id]])
  out[[as.character(kc[["output_column"]])]] <- apply_karyotype(scores, kc)
  out
}
