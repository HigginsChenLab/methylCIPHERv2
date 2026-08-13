# Print Method For An mc_summary Object

Prints the tables of an `mc_summary` object.

## Usage

``` r
# S3 method for class 'mc_summary'
print(x, n = 6, ...)
```

## Arguments

- x:

  An `mc_summary` object.

- n:

  A single whole number. The number of rows to print for each table.
  Default is `6`.

- ...:

  Not used.

## Value

An `mc_summary` object. Returns `x`, invisibly, after printing it.

## Details

The two problem tables print the `note` of each row. The notes table
under them gives the `explanation` of every note they print. The
`explanation` stays in `x` beside the `note`.

Every table shortens `mc_batch_id` to its first seven characters, except
the `mc_batch_id` table, which gives every label in full.

## Examples

``` r
clocks <- c("Horvath1", "Hannum")
sim <- sim_DNAm(clocks, n = 20)
res <- calc_clocks(sim[["DNAm"]], clocks)
print(summary(res), n = 3)
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
