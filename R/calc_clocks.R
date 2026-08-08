# public front door

#' Epigenetic Clock Scores
#'
#' Scores CpG-based epigenetic clocks on a matrix of methylation beta values.
#'
#' @inheritParams mc-params
#' @param pheno_id A string. The name of the column in `pheno` that holds the
#'   sample ids. Default is `"ID"`.
#' @param min_clocks_coverage A number between 0 and 1. The smallest fraction
#'   of a clock's CpGs that must be present for that clock to score. Default is
#'   `0.75`.
#' @param min_samples_coverage A number between 0 and 1. The smallest fraction
#'   of a clock's CpGs that must be present for a sample to score that clock.
#'   Default is `0.75`.
#'
#' @inheritSection mc-params The assets directory
#' @inheritSection mc-params Covariate columns
#' @inheritSection mc-params Normalization
#'
#' @details
#' [list_clocks()] and [list_clock_tags()] show every value `clocks` accepts.
#'
#' `min_clocks_coverage` is read against both panels, and it decides
#' differently on each. A clock under it on the scoring panel scores `NA`
#' for every sample, because there is nothing left to score from. A clock
#' under it on the background panel is scored without normalization, because
#' the beta values are still there. Each case raises a warning that names the
#' clocks.
#'
#' `min_samples_coverage` is read against the scoring panel alone. A sample
#' under it scores `NA` for that clock, and for that clock only.
#'
#' A clock with none of its scoring CpGs present scores `NA` at any value of
#' either argument. A clock just above either value is scored, and raises a
#' warning. Pass the returned value to [clocks_coverage()] or
#' [samples_coverage()] to see the counts. The `reason` column of
#' [samples_coverage()] says why each `NA` score is missing.
#'
#' `calc_clocks()` narrows `pheno` before it stores it. The returned value
#' keeps the id column and the covariates that the clocks need, and drops the
#' other columns.
#'
#' @returns An `mc_result` object. It holds the scores, the narrowed `pheno`,
#'   and the coverage counts for the run.
#'
#' @examples
#' clocks <- c("Horvath1", "Hannum")
#' sim <- sim_DNAm(clocks, n = 20)
#'
#' res <- calc_clocks(sim[["DNAm"]], clocks)
#' res
#'
#' # pheno is narrowed to the id column and the covariates the clocks need
#' pheno <- data.frame(ID = rownames(sim[["DNAm"]]), Age = runif(20, 20, 80))
#' res <- calc_clocks(sim[["DNAm"]], clocks, pheno = pheno)
#' head(res[["pheno"]])
#'
#' @export
calc_clocks <- function(
  DNAm,
  clocks,
  pheno = NULL,
  pheno_id = "ID",
  covariates = NULL,
  min_clocks_coverage = 0.75,
  min_samples_coverage = 0.75,
  normalize = NULL,
  ext_data = NULL,
  ask = TRUE
) {
  # the boundary: everything downstream assumes these are already validated
  checkmate::assert_string(pheno_id)
  checkmate::assert_number(min_clocks_coverage, lower = 0, upper = 1)
  checkmate::assert_number(min_samples_coverage, lower = 0, upper = 1)

  spec <- mc_spec(clocks, pheno_id, normalize, ext_data, ask)
  # canonicalize before any pheno check, so every check reads one set of names
  pheno <- canonicalize_covariates(pheno, covariates, spec[["covariates"]])
  facts <- mc_cohort(DNAm, spec, pheno, min_clocks_coverage)
  scored <- score_cohort(DNAm, spec, facts, min_samples_coverage)
  # shared with refinalize_clocks() -- a no-op when pending is empty
  final <- finalize_cross_sample(scored[["scores"]], scored[["pending"]])
  scores <- final[["scores"]]

  # the row gate already blanked its cells. this reports them.
  check_row_coverage(scored[["gate"]], min_samples_coverage)
  # value gate on output columns. nan/inf land here.
  check_score_values(scores[spec[["output_ids"]]])

  construct_mc_result(
    scores,
    scored[["coverage"]],
    spec[["output_ids"]],
    spec[["clock_ids"]],
    facts[["sample_id"]],
    pheno = facts[["pheno"]],
    pheno_id = spec[["pheno_id"]],
    covariates_used = spec[["covariates"]],
    # normalized = applied; normalize_requested = asked for.
    normalized = names(facts[["normalize"]])[facts[["normalize"]]],
    normalize_requested = names(spec[["normalize"]])[spec[["normalize"]]],
    min_clocks_coverage = min_clocks_coverage,
    min_samples_coverage = min_samples_coverage,
    scoring_failures = merge_notes(scored[["notes"]], final[["notes"]]),
    # kept, not discarded, so a bound record can re-finalize exactly
    pending = scored[["pending"]]
  )
}
