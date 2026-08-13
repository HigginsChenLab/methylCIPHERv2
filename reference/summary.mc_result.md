# Summary Method For An mc_result Object

Summarizes the scores and coverage of an `mc_result` object.

## Usage

``` r
# S3 method for class 'mc_result'
summary(object, ...)
```

## Arguments

- object:

  An `mc_result` object.

- ...:

  Not used.

## Value

An `mc_summary` object. It holds the clocks requested and the
dependencies they needed, the clocks scored and failed, the `input` and
`arguments` tables, the `by_clock` and `by_sample` problem tables, and,
when `object` holds more than one batch, the batches.

## Details

The requested clocks are the ones the `clocks` argument of
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
asked for. A clock that another clock needs is a dependency, and it gets
a score column of its own. The two sets together give every score
column.

A clock is failed when every sample has a `score` note for it, because
it then produced no value at all. The clocks that produced a value are
scored. Both sets cover the dependencies as well as the requested
clocks. A run reports no failed clock when every clock produced one.

The `input` table describes the matrix each batch was scored from.
`n_cpgs` is the number of columns it held, and `n_scanned` is the number
of those columns the clocks needed. `n_all_missing` counts the scanned
columns with no value for any sample.

Four more columns appear only where a scanned value is outside `0` to
`1`. `min_val` and `max_val` give that value, and `min_col` and
`max_col` name the column it is in. A fifth column, `any_inf`, appears
where a value is infinite.

The `arguments` table gives the values each batch was scored under. Two
batches can differ, because each one keeps the values of the call that
scored it.

The two problem tables count the same notes two ways. `by_clock` gives
the number of samples for each clock, panel and note. `by_sample` counts
the samples that lost the same number of clocks, for each panel and
note, so it says how far a problem spread and not which sample it
reached.
[`samples_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/samples_coverage.md)
names the sample.

A note on a `score` row means the score is missing. A note on a `norm`
row is about the background panel, and the score may still be present.
Both tables carry the `explanation` of each note beside it, and
[`samples_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/samples_coverage.md)
gives the full set of notes.

Totals are never added across batches, because each batch was scored
from a different matrix.

## See also

- [`clocks_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/clocks_coverage.md)
  for the CpG counts behind each clock's score.

- [`samples_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/samples_coverage.md)
  for the counts and the `note` of each sample.

## Examples

``` r
clocks <- c("Horvath1", "Hannum")
sim <- sim_DNAm(clocks, n = 20)
res <- calc_clocks(sim[["DNAm"]], clocks)

summary(res)
#> <mc_summary> 20 samples x 2 clocks
#> 
#> clocks [2 requested]
#>   Horvath1, Hannum
#> 
#> problems [none]
#> 
#> input [1 batch]
#>   n_cpgs  n_scanned  n_all_missing
#>   ------  ---------  -------------
#>      418        418              0
#> 
#> arguments [1 batch]
#>   min_clocks_coverage  min_samples_coverage
#>   -------------------  --------------------
#>                  0.75                  0.75
```
