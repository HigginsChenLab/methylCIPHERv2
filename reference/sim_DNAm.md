# Simulated Methylation Data

Builds a random beta matrix and a matching `pheno` data frame for a set
of clocks.

## Usage

``` r
sim_DNAm(
  clocks,
  n = 10,
  Age = FALSE,
  Female = FALSE,
  remove = 0,
  normalize = NULL,
  ext_data = NULL,
  ask = TRUE,
  suffix = NULL
)
```

## Arguments

- clocks:

  A character vector. The clocks to score, named by clock id, group id,
  or tag. Each name is given one time. See
  [`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md).

- n:

  A single whole number. The number of samples to simulate. Default is
  `10`.

- Age:

  A boolean. Adds an `Age` column to `pheno`, drawn from a normal
  distribution. Default is `FALSE`.

- Female:

  A boolean. Adds a `Female` column to `pheno`, with about half the
  samples set to `1`. Default is `FALSE`.

- remove:

  A single whole number. The number of CpGs to drop at random from the
  simulated panel. Default is `0`.

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

- suffix:

  A string. Appended to every sample id, so two simulated matrices stay
  distinct. Default is `NULL`, which leaves the ids as given.

## Value

An `mc_sim` object. It holds the simulated `DNAm` matrix, the matching
`pheno` data frame, the `clocks` argument as given, and the `suffix`,
which is `NULL` when no suffix was set.

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
sim <- sim_DNAm(c("Horvath1", "Hannum"), n = 10, Age = TRUE, Female = TRUE)
dim(sim[["DNAm"]])
#> [1]  10 418
head(sim[["pheno"]])
#>        ID      Age Female
#> 1 sample1 51.44352      0
#> 2 sample2 37.41641      1
#> 3 sample3 49.47463      0
#> 4 sample4 46.19316      0
#> 5 sample5 45.13304      0
#> 6 sample6 41.04052      1
```
