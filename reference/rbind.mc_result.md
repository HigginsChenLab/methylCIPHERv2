# Combined Batches Of Scores

Stacks two or more outputs from
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
runs into one object of multiple batches.

## Usage

``` r
# S3 method for class 'mc_result'
rbind(..., deparse.level = 1)
```

## Arguments

- ...:

  Two or more `mc_result` objects.

- deparse.level:

  A single whole number. Not used by this method. Default is `1`.

## Value

An `mc_result` object. It holds the stacked scores, `pheno`, and
`coverage` of every input, under one `mc_batch_id` label for each.

## Details

Each input must use disjoint sample ids, the same scored clocks, the
same `pheno_id`, and the same normalized clocks.
[`rbind()`](https://rdrr.io/r/base/cbind.html) stops when any of those
differ between inputs.

The normalized clocks are the ones a run applied a scheme to, which are
not always the ones it was asked to. A batch whose background panel was
too thin is scored without the scheme, so two inputs given the same
`normalize` setting can still differ here.
[`rbind()`](https://rdrr.io/r/base/cbind.html) names the cause when it
stops.

The combined value gets one `mc_batch_id` label for each input. A clock
that depends on sample-wise information, such as a z-score, keeps the
value each input calculated on its own samples. Call
[`refinalize_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/refinalize_clocks.md)
to calculate it again from every sample in the combined value.

## See also

- [`refinalize_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/refinalize_clocks.md)
  for a cross-sample score recomputed after a bind.

- [`as.data.frame.mc_result()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/as.data.frame.mc_result.md)
  for the scores as a data frame.

- [`as.matrix.mc_result()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/as.matrix.mc_result.md)
  for the scores as a numeric matrix.

## Examples

``` r
clocks <- c("Horvath1", "Hannum")
sim1 <- sim_DNAm(clocks, n = 10)
sim2 <- sim_DNAm(clocks, n = 10, suffix = "b")

res1 <- calc_clocks(sim1[["DNAm"]], clocks)
res2 <- calc_clocks(sim2[["DNAm"]], clocks)

combined <- rbind(res1, res2)
combined
#> <mc_result> 20 samples x 2 clocks
#> 
#> $scores [6 of 20 rows, 2 clocks]
#>             Horvath1    Hannum
#>   -------  ---------  --------
#>   sample1   39.07357  99.41836
#>   sample2   25.60942  87.09818
#>   sample3  137.19828  80.02799
#>   sample4   63.05925  42.35102
#>   sample5   61.33898  67.61679
#>   sample6   91.21213  42.78517
#>   ... 14 more rows
#> 
#> $pheno [6 of 20 rows, 1 column]
#>   ID
#>   -------
#>   sample1
#>   sample2
#>   sample3
#>   sample4
#>   sample5
#>   sample6
#>   ... 14 more rows
#> 
#> mc_batch_id [2 batches]
#>   a683cd7ddcd49f1f, c877d86e3e1f0aa8
```
