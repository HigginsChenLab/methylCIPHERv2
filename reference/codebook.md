# Clock Codebook

Describes a set of clocks, or the clocks scored in an `mc_result`
object.

## Usage

``` r
codebook(x, ...)

# S3 method for class 'character'
codebook(x, ...)

# S3 method for class 'mc_result'
codebook(x, ...)

# Default S3 method
codebook(x, ...)
```

## Arguments

- x:

  A character vector. The clock ids, group ids or tags to describe, or
  an `mc_result` object from
  [`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md).

- ...:

  Not used.

## Value

A data frame. One row for each described clock, with the `column` it
appears as and a one sentence `description` of it.

## Details

A character vector describes the clocks it names. A group id describes
every clock in the group, and a tag describes every clock the tag
expands to. See
[`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md)
and
[`list_clock_tags()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clock_tags.md).
An `mc_result` object describes the clocks in its scores.

The first row reports the version of the clock descriptions. The second
row describes the `clock_id` column of
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html). Each row
after that is one value of that column.

A clock with no description on record reads `NA`.

## Examples

``` r
codebook(c("Horvath1", "Hannum"))
#>         column
#> 1 meta_version
#> 2     clock_id
#> 3     Horvath1
#> 4       Hannum
#>                                                                                                                                                                                                        description
#> 1                                                                                                                                                                                                               v1
#> 2                                                                                                                                                                               The clock that produced the score.
#> 3                                 The landmark first multi-tissue DNA-methylation age clock, a 353-CpG predictor trained across 39 datasets spanning 51 tissues and cell types on the 27K/450K array intersection.
#> 4 Hannum is a foundational first-generation, blood-based epigenetic clock that predicts chronological age from just 71 CpGs, and was among the earliest single-tissue DNAm age predictors built on the 450K array.

sim <- sim_DNAm("Hannum", n = 5)
res <- calc_clocks(sim[["DNAm"]], "Hannum")
codebook(res)
#>         column
#> 1 meta_version
#> 2     clock_id
#> 3       Hannum
#>                                                                                                                                                                                                        description
#> 1                                                                                                                                                                                                               v1
#> 2                                                                                                                                                                               The clock that produced the score.
#> 3 Hannum is a foundational first-generation, blood-based epigenetic clock that predicts chronological age from just 71 CpGs, and was among the earliest single-tissue DNAm age predictors built on the 450K array.
```
