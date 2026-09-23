# Quality Control Report

Writes an HTML report on a beta matrix, its sample metadata, and the
clocks scored from it.

## Usage

``` r
qc_report(
  DNAm = NULL,
  pheno = NULL,
  x = NULL,
  clocks = "all",
  file = NULL,
  pheno_id = "ID",
  covariates = NULL,
  ext_data = NULL,
  title = "methylCIPHERv2 QC report",
  open = interactive()
)
```

## Arguments

- DNAm:

  A numeric matrix. The methylation beta values, with samples in the
  rows and CpGs in the columns. Default is `NULL`, which leaves the
  methylation sections out.

- pheno:

  A data frame. The sample metadata, with one row for each sample.
  Default is `NULL`, which reads the `pheno` stored in `x` when `x` is
  given.

- x:

  An `mc_result` object. The value returned by
  [`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md).
  Default is `NULL`, which leaves the clock result sections out.

- clocks:

  A character vector. The clocks whose CpGs are counted against the
  columns of `DNAm`, named by clock id, group id, or tag. Default is
  `"all"`.

- file:

  A string. The path of the HTML file to write. Default is `NULL`, which
  writes to a temporary file.

- pheno_id:

  A string. The name of the column in `pheno` that holds the sample ids.
  Default is `"ID"`.

- covariates:

  A named character vector. Points a covariate at the column that holds
  it, for metadata that names its columns something else. Default is
  `NULL`.

- ext_data:

  A string. The path to the directory that holds the clock assets.
  Default is `NULL`, which uses the assets directory.

- title:

  A string. The title at the top of the report. Default is
  `"methylCIPHERv2 QC report"`.

- open:

  A boolean. Opens the report in a browser after it is written. Default
  is [`interactive()`](https://rdrr.io/r/base/interactive.html).

## Value

A string. The path of the written file, invisibly.

## Details

Every argument is optional, but at least one of `DNAm`, `pheno` and `x`
is needed. A section whose input is not given says that it is not
computable. The overview at the top gives the key counts from every
section.

The overview also plots the `Horvath1` and `Zhang2019EN` scores against
age. A sample is flagged when its score is far from the trend with age,
or when its predicted sex differs from the `Female` column. The scores
come from `x` where it holds them, and from `DNAm` otherwise. Each kind
of flag has a box above the plots. Clear a box to hide those samples.

The `DNAm` sections describe the beta values, the missing values for
each sample and each CpG, the array that the probe ids match, and the
coverage of the X and Y chromosomes. They also count the CpGs of each
clock in `clocks` against the columns of `DNAm`. These counts describe
the matrix and decide nothing.
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
reads the matrix again when it scores, and
[`clocks_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/clocks_coverage.md)
gives what it counted. A clock whose weights are in an asset is counted
only when that asset is already in the assets directory, or in
`ext_data`. The report never downloads an asset. When `DNAm` is given,
[`predict_sex()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/predict_sex.md)
also runs on it.

The `pheno` sections give summary statistics and missing values for each
column, and the age distribution. Age is read from an `Age` column and
sex from a `Female` column, coded `0` or `1`, as in
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md).
The age distribution is also split by sex and by every column with two
to eight distinct values.

The `x` sections list each scoring problem from
[`summary.mc_result()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/summary.mc_result.md)
with the clocks it applies to. They also give the age correlation of
each clock against the blood reference from
[`score_associations()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/score_associations.md).
A bibliography of the scored clocks from
[`cite_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/cite_clocks.md)
closes the report.

Warnings and messages raised while the report is built are listed at the
end of the report, not printed.

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

## Examples

``` r
clocks <- c("Horvath1", "Hannum")
sim <- sim_DNAm(clocks, n = 20, Age = TRUE, Female = TRUE)
res <- calc_clocks(sim[["DNAm"]], clocks, pheno = sim[["pheno"]])
path <- qc_report(sim[["DNAm"]], sim[["pheno"]], res, clocks = clocks,
                  open = FALSE)
file.exists(path)
#> [1] TRUE
```
