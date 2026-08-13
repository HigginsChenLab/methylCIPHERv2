# Print Method For An mc_sim Object

Prints a compact summary of an `mc_sim` object, with a preview of `DNAm`
and `pheno`.

## Usage

``` r
# S3 method for class 'mc_sim'
print(x, n = 6, p = 6, ...)
```

## Arguments

- x:

  An `mc_sim` object. The value returned by
  [`sim_DNAm()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/sim_DNAm.md).

- n:

  A single whole number. The number of sample rows to preview from
  `DNAm` and `pheno`. Default is `6`.

- p:

  A single whole number. The number of CpG columns to preview from
  `DNAm`. Default is `6`.

- ...:

  Not used.

## Value

An `mc_sim` object. Returns `x`, invisibly, after printing it.

## Examples

``` r
sim <- sim_DNAm(c("Horvath1", "Hannum"), n = 10)
print(sim)
#> <mc_sim> 10 samples x 418 CpGs
#> 
#> $DNAm [6 of 10 rows, 6 of 418 CpGs]
#>            cg00075967  cg00374717  cg00864867  cg00945507  cg01027739
#>   -------  ----------  ----------  ----------  ----------  ----------
#>   sample1   0.3322881   0.8290881   0.6176930  0.05029849  0.85969510
#>   sample2   0.7588981   0.5929770   0.9564317  0.49038623  0.14477357
#>   sample3   0.3396747   0.6452627   0.9171483  0.54794441  0.94817055
#>   sample4   0.3497814   0.5980214   0.1479221  0.49638887  0.01526108
#>   sample5   0.8729758   0.5491154   0.5948933  0.47902772  0.69061569
#>   sample6   0.1348665   0.3177117   0.7448172  0.20417086  0.92553510
#>            cg01353448
#>   -------  ----------
#>   sample1   0.6930633
#>   sample2   0.2974899
#>   sample3   0.7122271
#>   sample4   0.2825268
#>   sample5   0.1498658
#>   sample6   0.2357280
#>   ... 4 more rows, 412 more CpGs
#> 
#> $pheno [6 of 10 rows, 1 column]
#>   ID
#>   -------
#>   sample1
#>   sample2
#>   sample3
#>   sample4
#>   sample5
#>   sample6
#>   ... 4 more rows
```
