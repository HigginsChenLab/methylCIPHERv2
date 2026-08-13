# Predicted Sex Karyotype

Predicts sex and identifies sex chromosome aneuploidy.

## Usage

``` r
predict_sex(DNAm, pheno = NULL, covariates = NULL, ...)
```

## Arguments

- DNAm:

  A numeric matrix. The methylation beta values, with samples in the
  rows and CpGs in the columns.

- pheno:

  A data frame. The sample metadata, with one row for each sample.
  Default is `NULL`.

- covariates:

  A named character vector. Points a covariate at the column that holds
  it, for metadata that names its columns something else. Default is
  `NULL`.

- ...:

  Passed to
  [`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md).

## Value

A data frame. One row for each sample, with the `DNAmSex_Wang_ChrX` and
`DNAmSex_Wang_ChrY` scores, `predicted_sex`, `sex_aneuploidy`, and, when
`pheno` has a `Female` column, `recorded_sex` and `sex_mismatch`. Each
score also has a `_coverage` column and a `_note` column, named after
the score.

## Details

This is a re-implementation of the sex prediction algorithm of the
wateRmelon package.

`predicted_sex` is one of `"Male"`, `"Female"`, `"47,XXY"`, or
`"45,XO"`. A sample missing either score gets `NA`, not a default call.

`sex_aneuploidy` is `TRUE` where the call is a sex chromosome
aneuploidy, and `FALSE` where it is not. It is `NA` where there is no
call. The classifier tests for `"Male"`, `"47,XXY"` and `"45,XO"`, and
gives `"Female"` to a sample that matches none of the three. A `FALSE`
therefore means that no aneuploidy was found. It does not confirm a
euploid karyotype.

When `pheno` has a `Female` column, coded `0` or `1`, the result also
carries `recorded_sex` and `sex_mismatch`. `sex_mismatch` is `TRUE` only
where `predicted_sex` disagrees with a binary `recorded_sex`. A
`"47,XXY"` or `"45,XO"` call is never flagged, because a binary `Female`
column cannot record it.

`predict_sex()` reads `Female` itself, and the two clocks it scores read
no covariate. Pass a column of another name to `covariates`, as
`covariates = c(Female = "sex_f")`. `pheno` with no `Female` column
builds no comparison, and says so.

Each score carries the coverage of its own panel and the note for the
same sample. `DNAmSex_Wang_ChrX_coverage` and
`DNAmSex_Wang_ChrY_coverage` give the part of each panel that `DNAm`
holds for that sample. `DNAmSex_Wang_ChrX_note` and
`DNAmSex_Wang_ChrY_note` give the note that
[`samples_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/samples_coverage.md)
gives for the same sample and clock. The two panels are of very
different sizes, so they are counted apart.

These columns qualify a call. A sample that covers little of a panel can
still reach a call, and `sex_aneuploidy` reads `FALSE` for that sample
and for a sample on a full panel alike. A note is present where the
score is `NA`, and the coverage can still be `1`. A sample with no
spread across the reference domain is the case where that happens.

## Covariate columns

Some clocks read a covariate from the sample metadata. A clock names the
covariate it reads, and looks for a column of that name.

`covariates` points a covariate at a column that holds it under another
name. Write the covariate on the left and your own column on the right,
as in `covariates = c(Age = "age_yrs")`. Only a covariate this call
reads can be pointed at a column, and each one may be pointed once.

A covariate that is already a column of the metadata needs no entry. The
`covariates` column of
[`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md)
with `all_columns = TRUE` gives the covariates each clock reads.

A pointer moves the name and nothing else. `Female` pointed at a column
that holds `1` for male scores every clock that reads sex, and scores
all of them wrong, so check what the column means before you point at
it.

## References

Wang Y, Hannon E, Grant OA, Gorrie-Stone TJ, Kumari M, Mill J, Zhai X,
McDonald-Maier KD, Schalkwyk LC (2021). DNA methylation-based sex
classifier to predict sex and identify sex chromosome aneuploidy. *BMC
Genomics*, 22(1), 484.
[doi:10.1186/s12864-021-07675-2](https://doi.org/10.1186/s12864-021-07675-2)

## See also

- [`calc_accel()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_accel.md)
  for the age acceleration of each sample.

- [`score_associations()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/score_associations.md)
  for how each clock tracks age against a reference.

## Examples

``` r
sim <- sim_DNAm("DNAmSex_Wang", n = 6, Female = TRUE)
predict_sex(sim[["DNAm"]], sim[["pheno"]])
#> ! 3 samples have a predicted sex that does not match the Female column in
#>   `pheno`.
#> ℹ The sex_mismatch column marks those samples.
#> ℹ A mismatch can come from the recorded sex or from the array data. Check both
#>   sources before you correct either one.
#>        ID DNAmSex_Wang_ChrX DNAmSex_Wang_ChrY predicted_sex sex_aneuploidy
#> 1 sample1          38.96823         -3.450254        Female          FALSE
#> 2 sample2          35.81618         -6.262427        Female          FALSE
#> 3 sample3          38.24813         -5.217332        Female          FALSE
#> 4 sample4          36.73826         -3.853436        Female          FALSE
#> 5 sample5          37.98177         -5.485732        Female          FALSE
#> 6 sample6          38.59752         -5.922559        Female          FALSE
#>   recorded_sex sex_mismatch DNAmSex_Wang_ChrX_coverage DNAmSex_Wang_ChrX_note
#> 1         Male         TRUE                          1                   <NA>
#> 2         Male         TRUE                          1                   <NA>
#> 3       Female        FALSE                          1                   <NA>
#> 4         Male         TRUE                          1                   <NA>
#> 5       Female        FALSE                          1                   <NA>
#> 6       Female        FALSE                          1                   <NA>
#>   DNAmSex_Wang_ChrY_coverage DNAmSex_Wang_ChrY_note
#> 1                          1                   <NA>
#> 2                          1                   <NA>
#> 3                          1                   <NA>
#> 4                          1                   <NA>
#> 5                          1                   <NA>
#> 6                          1                   <NA>
```
