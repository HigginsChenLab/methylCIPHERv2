# The Clock Catalog

## What the columns mean

The table scrolls sideways to reach the columns that do not fit. Select
the arrow at the start of a row to read a longer description of that
clock.

**Clock** is the identifier for a single scored clock. **Group** is the
family it belongs to. **CpGs** counts the CpGs that the clock scores.

**Covariates** lists the columns that `pheno` must carry for that clock.
An empty cell means the clock reads methylation values alone.

**Normalize** names the background normalization scheme a clock
declares, and an empty cell means it declares none. A `quantile` cell is
on by default and a `bmiq` cell is off. The `normalize` argument of
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
turns either one on or off. Normalization also needs a background panel
that is much larger than the scoring panel, so
[`calc_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/calc_clocks.md)
warns and declines a scheme whose background is too thin to use.

The remaining columns describe the clock as it was published.
**Tissue**, **Array**, **Cohort**, **Samples**, **Health**, **Age min**,
**Age max**, **Age unit**, **Sex** and **Ancestry** report the data that
the clock was trained on. **Algorithm** names the method that fit it. An
empty cell means the value is not on record.

[`codebook()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/codebook.md)
returns the same descriptions as a data frame, for a set of clocks or
for the clocks that a run scored.

``` r

codebook(c("Horvath1", "Hannum"))[["column"]]
#> [1] "meta_version" "clock_id"     "Horvath1"     "Hannum"
```

## Scoring from the catalog

Any value in the **Clock** column works as the `clocks` argument.

``` r

res <- calc_clocks(DNAm, clocks = "Horvath1", pheno = pheno)
```

A group name scores every member of that family.

``` r

res <- calc_clocks(DNAm, clocks = "GrimAge", pheno = pheno)
```

A tag scores every clock that carries it.
[`list_clock_tags()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clock_tags.md)
returns the tags with their members.

``` r

names(list_clock_tags())
#> [1] "gestational" "mitotic"     "mortality"
```

## Filtering the catalog in code

[`list_clocks()`](https://HigginsChenLab.github.io/methylCIPHERv2/reference/list_clocks.md)
returns this catalog as a data frame, so it is available in a script as
well as on this page. It takes a tag directly.

``` r

mitotic <- list_clocks(tag = "mitotic")
mitotic[["clock_id"]]
#> [1] "EpiTOC"        "EpiTOC2"       "HypoClock"     "MiAge"        
#> [5] "RepliTali"     "RepliTaliNorm"
```

The result is an ordinary data frame, so you can filter the other
columns with base R.

``` r

all_clocks <- list_clocks()
bundled <- all_clocks[!all_clocks[["external"]], ]
nrow(bundled)
#> [1] 94
```
