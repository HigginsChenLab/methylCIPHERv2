# CpGs Required To Score Clocks

Lists the CpGs needed to score a set of clocks, including background
CpGs for normalization.

## Usage

``` r
clock_cpgs(clocks, normalize = NULL, ext_data = NULL, ask = TRUE)
```

## Arguments

- clocks:

  A character vector. The clocks to score, named by clock id, group id,
  or tag. Each name is given one time. See
  [`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md).

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

A character vector. The CpGs needed to score `clocks`, with duplicates
removed.

## Details

A clock built from other clocks also needs their CpGs. A clock adds its
background panel when its normalization method is on.

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

## See also

- [`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md)
  for the clocks a `clocks` value accepts.

- [`list_clock_tags()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clock_tags.md)
  for the tags a `clocks` value accepts.

- [`list_mc_assets()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_mc_assets.md)
  for the assets an external clock needs.

## Examples

``` r
cpgs <- clock_cpgs(c("Horvath1", "Hannum"))
length(cpgs)
#> [1] 418

# normalizing Horvath1 adds its background panel to the union
norm_cpgs <- clock_cpgs(c("Horvath1", "Hannum"), normalize = "Horvath1")
length(norm_cpgs)
#> [1] 21432
```
