# constants shared across files. single-use values stay next to their caller.

# reserved batch label: both coverage frames, provenance, the formula namespace
MC_BATCH <- "mc_batch_id"

# schemes expressible as a declared panel + a vendored target
NORM_SCHEMES <- c("quantile", "bmiq")

# schemes score_normalized() implements (quantile routes via Dunedin)
NORM_SCHEMES_ROUTED <- "bmiq"

# schemes that are on unless declined. every scheme here can be declined.
NORM_DEFAULT_ON <- "quantile"

# schemes that fill an absent background cpg with the target value
NORM_SCHEMES_FILL <- "quantile"

# note tokens a score branch may record against a sample. the other five are
# derived in gap_reasons() and pass through no collector.
MC_NOTE_CAUSES <- c("fit_bmiq", "fit_spread", "fit_reduce", "partial")

# the whole note enum, token -> the phrase samples_coverage() prints beside it,
# in the order R/coverage_report.R documents. table cells: no markup, no period.
MC_NOTES <- c(
  covariate = "a covariate the clock needs is missing",
  clock_coverage = "too few CpGs for the clock",
  sample_coverage = "too few CpGs for the sample",
  fit_bmiq = "the bmiq method failed for the sample",
  fit_spread = "the values of the sample have no spread",
  fit_reduce = "a clock that uses all the samples could not be calculated",
  dependency = "a clock this clock is calculated from is missing",
  not_finite = "the score is not a finite number",
  partial = "the background panel was only partly calibrated"
)
