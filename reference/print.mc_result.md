# Print Method For An mc_result Object

Prints the scores and the `pheno` table for an `mc_result` object.

## Usage

``` r
# S3 method for class 'mc_result'
print(x, n = 6, p = 6, ...)
```

## Arguments

- x:

  An `mc_result` object. The value returned by
  [`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md).

- n:

  A single whole number. The number of sample rows to print. Default is
  `6`.

- p:

  A single whole number. The number of clock columns to print for the
  scores table. Default is `6`.

- ...:

  Not used.

## Value

An `mc_result` object. Returns `x`, invisibly, after printing it.

## Details

The output lists the batch labels only when `x` holds more than one
batch.

## Examples

``` r
clocks <- c("Horvath1", "Hannum")
sim <- sim_DNAm(clocks, n = 20)
res <- calc_clocks(sim[["DNAm"]], clocks)
print(res, n = 3, p = 2)
#> <mc_result> 20 samples x 2 clocks
#> 
#> $scores [3 of 20 rows, 2 clocks]
#>            Horvath1    Hannum
#>   -------  --------  --------
#>   sample1  31.60265  63.22831
#>   sample2  98.22894  77.10027
#>   sample3  39.33378  57.78378
#>   ... 17 more rows
#> 
#> $pheno [3 of 20 rows, 1 column]
#>   ID
#>   -------
#>   sample1
#>   sample2
#>   sample3
#>   ... 17 more rows
```
