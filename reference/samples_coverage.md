# Sample Coverage Counts

Reports each sample's CpG coverage for every clock in `x`, and a note on
what happened at each step that was run for it.

## Usage

``` r
samples_coverage(x)
```

## Arguments

- x:

  An `mc_result` object. The value returned by
  [`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md).

## Value

A data frame. One row for each sample, clock, and panel, with
`n_observed`, `n_needed`, `coverage`, `note`, `explanation`, and, when
`x` holds more than one batch, `mc_batch_id`.

## Details

Every clock in the scores of `x` gets a row for each sample, and so does
every clock that scores as part of another clock. A clock assembled only
from other clocks' scores counts no CpGs of its own, so its counts are
`NA`. A clock scored separately for each sex has no row for a sample
outside the sex it scored.

A clock that normalizes has a second row for each sample, under
`panel = "norm"`, for the panel used to normalize it.

`note` says what happened to the panel in that row, and is `NA` when
nothing did. `panel` says which step the note is about, so a sample that
normalized and then scored can carry a note for each. Where more than
one note applies to a row, the first of these is given. `explanation`
gives the same note in words. Match on `note`, because it is the value
that stays the same between versions of this package.

On a `score` row, a note means the score is missing:

- `covariate`, when a covariate the clock needs is missing from `pheno`.
  An unknown `Female` value is the usual cause.

- `clock_coverage`, when the clock is under `min_clocks_coverage`. Every
  sample is missing this score.

- `sample_coverage`, when the sample is under `min_samples_coverage`.

- `fit_bmiq`, when the `bmiq` method failed for the sample, so the clock
  had no normalized values to score from.

- `fit_spread`, when the values of the sample have no spread, so the
  clock could not calculate a z-score for it.

- `fit_reduce`, when a clock that uses all the samples could not be
  calculated for the sample.

- `dependency`, when a clock that this clock is calculated from is
  missing for that sample.

- `not_finite`, when the score was calculated but is not a finite
  number, such as `NaN` or `Inf`.

On a `norm` row, a note is about the background panel, and the score may
still be present:

- `partial`, when the sample was normalized but one step of the scheme
  could not be applied to it. The score is real, and is calculated from
  a background that was only partly calibrated.

A score that is not a finite number is present, and is still a `score`
row with a note.
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
warns about it as well, and that warning names the likely cause.
`min_clocks_coverage` and `min_samples_coverage` are read for the batch
that scored the sample, because those are the values that decided the
score.

`samples_coverage()` warns when a `score` row's `coverage` is under the
strictest `min_samples_coverage` value used to score `x`. A `norm` row
is never read against that value, because the background panel is
counted for the whole run and not for one sample. The `mc_batch_id`
column appears only when `x` holds more than one batch.

## See also

- [`clocks_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/clocks_coverage.md)
  for the same panels counted for each clock.

- [`summary.mc_result()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/summary.mc_result.md)
  for the `note` column counted by clock and by sample.

## Examples

``` r
clocks <- c("Horvath1", "Hannum")
sim <- sim_DNAm(clocks, n = 20)
res <- calc_clocks(sim[["DNAm"]], clocks)

head(samples_coverage(res))
#>        id clock_id panel n_observed n_needed coverage note explanation
#> 1 sample1 Horvath1 score        353      353        1 <NA>        <NA>
#> 2 sample2 Horvath1 score        353      353        1 <NA>        <NA>
#> 3 sample3 Horvath1 score        353      353        1 <NA>        <NA>
#> 4 sample4 Horvath1 score        353      353        1 <NA>        <NA>
#> 5 sample5 Horvath1 score        353      353        1 <NA>        <NA>
#> 6 sample6 Horvath1 score        353      353        1 <NA>        <NA>
```
