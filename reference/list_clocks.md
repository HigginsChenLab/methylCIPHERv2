# Epigenetic Clock Catalog

Lists the clocks in the catalog, with the group and tags of each one.

## Usage

``` r
list_clocks(group = NULL, tag = NULL, pattern = NULL, all_columns = FALSE)
```

## Arguments

- group:

  A character vector. Keeps only the clocks in these groups. Default is
  `NULL`, which keeps every group.

- tag:

  A character vector. Keeps only the clocks that carry one of these
  tags. Default is `NULL`, which applies no tag filter.

- pattern:

  A string. A regular expression matched against the clock id and the
  group id. Default is `NULL`, which applies no pattern filter.

- all_columns:

  A boolean. Returns every column, including the ones the frame leaves
  out by default. Default is `FALSE`.

## Value

A data frame. One row for each clock that the `clocks` argument of
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
accepts.

## Details

Valid values for `tag` are the names of
[`list_clock_tags()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clock_tags.md).

`clock_id` names the token to pass to `clocks` in
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md).
`covariates` names the
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
`pheno` columns a clock needs, and `external` is `TRUE` for a clock
whose weights are a download.

`all_columns = TRUE` adds three columns about how a clock computes.

- `group_size` counts the clocks a group token expands to.

- `batch_dependent` is `TRUE` for a clock whose score depends on the
  other samples scored with it.

- `normalize` names the background normalization scheme a clock
  declares, and is empty for a clock that declares none. `"quantile"` is
  on by default and `"bmiq"` is off. The `normalize` argument of
  [`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
  turns either one on or off.

`all_columns = TRUE` also adds `n_cpgs`, which counts the CpGs a clock
scores, and twelve columns that describe the clock as published. These
are `description`, `cohort_trained`, `tissues_derived`,
`array_type_trained`, `n_samples_trained`, `health_status_trained`,
`age_min_trained`, `age_max_trained`, `age_unit_trained`,
`training_algorithm`, `sex_distribution_trained` and `ancestry_trained`.
A column is `NA` where the value is not on record.

## See also

- [`list_clock_tags()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clock_tags.md)
  for the tags a `tag` value accepts.

- [`clock_cpgs()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/clock_cpgs.md)
  for the CpGs a set of clocks needs.

- [`list_mc_assets()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_mc_assets.md)
  for the assets an external clock needs.

## Examples

``` r
list_clocks(pattern = "^Horvath")
#>   clock_id group_id covariates external tags
#> 1 Horvath1 Horvath1               FALSE     
#> 2 Horvath2 Horvath2               FALSE     
nrow(list_clocks(tag = "mortality"))
#> [1] 13
list_clocks(group = "Dunedin", all_columns = TRUE)
#>        clock_id group_id group_size covariates external batch_dependent
#> 1   DunedinPACE  Dunedin          2               FALSE           FALSE
#> 2 DunedinPoAm38  Dunedin          2               FALSE           FALSE
#>   normalize tags n_cpgs
#> 1  quantile         173
#> 2                    46
#>                                                                                                                                                                                                                                                                                                  description
#> 1 DunedinPACE is a third-generation blood DNAm biomarker that estimates the current pace of biological aging (biological years per calendar year) by distilling two decades of longitudinal multi-organ decline, and is built on a reliability-filtered probe set for excellent test-retest reproducibility.
#> 2                                                                                                     A third-generation blood clock that measures the pace of biological aging rather than an age, trained against a 12-year, 18-biomarker Pace-of-Aging phenotype in the single-birth-year Dunedin cohort.
#>   cohort_trained tissues_derived array_type_trained n_samples_trained
#> 1  Dunedin Study           blood       450K; EPICv1               817
#> 2  Dunedin Study           blood       450K; EPICv1               810
#>   health_status_trained age_min_trained age_max_trained age_unit_trained
#> 1      population-based              26              45            years
#> 2      population-based              26              38            years
#>   training_algorithm sex_distribution_trained ancestry_trained
#> 1        elastic net               48% female         European
#> 2        elastic net               48% female         European
```
