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
#' @param scale_scores A named logical vector. Turns cohort scaling on or off
#'   for the clocks that declare a scaled score. Default is `NULL`.
#'
#' @inheritSection mc-params The assets directory
#' @inheritSection mc-params Covariate columns
#' @inheritSection mc-params Normalization
#'
#' @section Scaled scores:
#' Some clocks are reported as a z-score across the samples that are scored
#' together, because the authors define the clock that way. `scale_scores`
#' accepts the same four forms as `normalize`.
#'
#' - `NULL` leaves every clock at its own default. A clock that declares a
#'   scaled score is scaled.
#' - `TRUE` or `FALSE` sets every clock that declares a scaled score.
#' - A character vector of clock ids turns scaling on for those clocks.
#' - A named logical vector sets the clocks it names, and leaves every other
#'   clock at its default.
#'
#' A scaled score depends on the other samples in the call. The same sample
#' can score differently in another cohort, and a call with one sample scores
#' `NA`. To compare or pool scores from different studies, pass
#' `scale_scores = FALSE`. After [rbind.mc_result()], call
#' [refinalize_clocks()] to scale again over every sample. The
#' `scale_scores` column of [list_clocks()] with `all_columns = TRUE` gives
#' the clocks that declare a scaled score.
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
#' [samples_coverage()] to see the counts. The `note` column of
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
  ask = TRUE,
  scale_scores = NULL
) {
  # the boundary: everything downstream assumes these are already validated
  # an empty name cannot be a column, and reaches $pheno and every exit frame
  checkmate::assert_string(pheno_id, min.chars = 1L)
  checkmate::assert_number(min_clocks_coverage, lower = 0, upper = 1)
  checkmate::assert_number(min_samples_coverage, lower = 0, upper = 1)

  spec <- mc_spec(clocks, pheno_id, normalize, ext_data, ask, scale_scores)
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
    # which output columns hold a score scaled across this batch
    scaled = intersect(spec[["scaled"]], spec[["output_ids"]]),
    min_clocks_coverage = min_clocks_coverage,
    min_samples_coverage = min_samples_coverage,
    # what the front door found in the matrix this batch was scored from
    input = facts[["input"]],
    scoring_failures = merge_notes(scored[["notes"]], final[["notes"]]),
    partial_calibration = scored[["partial"]],
    # kept, not discarded, so a bound record can re-finalize exactly
    pending = scored[["pending"]]
  )
}
