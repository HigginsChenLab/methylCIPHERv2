# Epigenetic Clock Scores

Scores CpG-based epigenetic clocks on a matrix of methylation beta
values.

## Usage

``` r
calc_clocks(
  DNAm,
  clocks,
  pheno = NULL,
  pheno_id = "ID",
  covariates = NULL,
  min_clocks_coverage = 0.75,
  min_samples_coverage = 0.75,
  normalize = NULL,
  ext_data = NULL,
  ask = TRUE
)
```

## Arguments

- DNAm:

  A numeric matrix. The methylation beta values, with samples in the
  rows and CpGs in the columns.

- clocks:

  A character vector. The clocks to score, named by clock id, group id,
  or tag. Each name is given one time. See
  [`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md).

- pheno:

  A data frame. The sample metadata, with one row for each sample.
  Default is `NULL`.

- pheno_id:

  A string. The name of the column in `pheno` that holds the sample ids.
  Default is `"ID"`.

- covariates:

  A named character vector. Points a covariate at the column that holds
  it, for metadata that names its columns something else. Default is
  `NULL`.

- min_clocks_coverage:

  A number between 0 and 1. The smallest fraction of a clock's CpGs that
  must be present for that clock to score. Default is `0.75`.

- min_samples_coverage:

  A number between 0 and 1. The smallest fraction of a clock's CpGs that
  must be present for a sample to score that clock. Default is `0.75`.

- normalize:

  A named logical vector. Turns background normalization on or off for
  the clocks that declare a method. Default is `NULL`.

- ext_data:

  A string. The path to the directory that holds the clock assets.
  Default is `NULL`, which uses the assets directory.

- ask:

  A boolean. Asks for confirmation before the assets directory changes.
  Default is `TRUE`. Pass `FALSE` to continue without asking, in a
  non-interactive session.

## Value

An `mc_result` object. It holds the scores, the narrowed `pheno`, and
the coverage counts for the run.

## Details

[`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md)
and
[`list_clock_tags()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clock_tags.md)
show every value `clocks` accepts.

`min_clocks_coverage` is read against both panels, and it decides
differently on each. A clock under it on the scoring panel scores `NA`
for every sample, because there is nothing left to score from. A clock
under it on the background panel is scored without normalization,
because the beta values are still there. Each case raises a warning that
names the clocks.

`min_samples_coverage` is read against the scoring panel alone. A sample
under it scores `NA` for that clock, and for that clock only.

A clock with none of its scoring CpGs present scores `NA` at any value
of either argument. A clock just above either value is scored, and
raises a warning. Pass the returned value to
[`clocks_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/clocks_coverage.md)
or
[`samples_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/samples_coverage.md)
to see the counts. The `note` column of
[`samples_coverage()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/samples_coverage.md)
says why each `NA` score is missing.

`calc_clocks()` narrows `pheno` before it stores it. The returned value
keeps the id column and the covariates that the clocks need, and drops
the other columns.

## The assets directory

Four clock groups keep their weights in downloadable assets, outside the
package. `ext_data` says where to read them from, and accepts three
forms.

- `NULL` reads from the assets directory, and downloads any asset that
  is missing. Use
  [`set_mc_assets_dir()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/set_mc_assets_dir.md)
  to choose that directory.

- A path reads only that directory, and never downloads. A missing asset
  is an error.

- Assets already in memory from
  [`load_mc_assets()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/load_mc_assets.md)
  are used directly.

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

## Normalization

Some clocks declare a background normalization method. `normalize`
accepts four forms.

- `NULL` leaves every clock at its own default. A clock that declares
  `quantile` is normalized, and a clock that declares `bmiq` is not.

- `TRUE` or `FALSE` sets every clock that declares a method.

- A character vector of clock ids turns normalization on for those
  clocks, and leaves every other clock at its default.

- A named logical vector sets the clocks it names, and leaves every
  other clock at its default.

The character form only turns normalization on. To turn a method off,
name the clock in a named logical vector.

Normalization needs a background panel that is much larger than the
scoring panel, so a matrix cut down to the scoring CpGs cannot supply
it. The `normalize` column of
[`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md)
with `all_columns = TRUE` gives the method each clock declares.

## Examples

``` r
clocks <- c("Horvath1", "Hannum")
sim <- sim_DNAm(clocks, n = 20)

res <- calc_clocks(sim[["DNAm"]], clocks)
res
#> <mc_result> 20 samples x 2 clocks
#> 
#> $scores [6 of 20 rows, 2 clocks]
#>             Horvath1    Hannum
#>   -------  ---------  --------
#>   sample1  121.57529  37.88488
#>   sample2  131.05186  50.32948
#>   sample3  102.20911  60.26443
#>   sample4   46.72342  69.17409
#>   sample5   73.39157  62.24323
#>   sample6  127.55273  69.88226
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

# pheno is narrowed to the id column and the covariates the clocks need
pheno <- data.frame(ID = rownames(sim[["DNAm"]]), Age = runif(20, 20, 80))
res <- calc_clocks(sim[["DNAm"]], clocks, pheno = pheno)
head(res[["pheno"]])
#>        ID
#> 1 sample1
#> 2 sample2
#> 3 sample3
#> 4 sample4
#> 5 sample5
#> 6 sample6
```
