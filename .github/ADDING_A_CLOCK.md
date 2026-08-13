# Adding a clock

A clock is declared in the `methylCIPHER-meta` repository, not in this one. That repository holds the scoring contract: the coefficients, the panels, the citations, and the reference values that prove a score is right. `data-raw/sync.R` reads it and writes `R/sysdata.rda`, which is committed. `META_REMOTE` at the top of `data-raw/sync.R` names the repository, and that line is the only place the location is recorded.

Two consequences follow. Most clocks need no change to this repository at all. And `methylCIPHER-meta` is private, so a contributor needs read access before any of this is possible. Ask the maintainer for access.

## What decides the size of the change

The work is not proportional to the clock. It depends on whether the arithmetic already has a home.

| Case | What it takes |
| --- | --- |
| The clock is a weighted sum of CpG coefficients | Declarations and weights upstream. No R code. |
| The clock declares a normalization scheme the package already applies | Declarations and weights upstream. No R code. |
| The clock is a member of a group that already has a scoring branch | Declarations and weights upstream. No R code. |
| The arithmetic is new | The above, plus a branch in `R/`, plus a value test. |

The first three cases are the common ones, and they grow more common as the catalog grows, because a new clock is more and more likely to match a shape that already exists.

## Step 1: declare the clock upstream

Six things, all in `methylCIPHER-meta`.

**The clock meta.** `weights/<group_id>/<clock_id>.meta.json`. Required fields are `clock_id`, `group_id`, `weights_format`, `computation_type`, `n_cpgs`, `license` and `pmid`. Optional fields cover everything else: `intercept`, `covariates`, `output_transform`, `normalization`, `imputation`, `components`, `shared`, `probe_sets`, `recipe`, `code_ref` and `code_deps`.

**The coefficients.** For `weights_format = "cpg_coefficient"`, the path is derived, never searched: `weights/<group_id>/<clock_id>.csv.gz`. The header must read `cpg,coefficient`. A file at any other path is not found, and the build stops.

**Every declared path points under `weights/` or `papers/`.** Anything else stops the build. Paths under `papers/` are recognised and skipped, so the package never vendors them.

**A row in `manifest.json`**, carrying `clock_id` and `bundle_hash`. A clock with a meta file and no manifest row is not built. This is the switch that releases a clock.

**Citations.** One or more rows in `bibliography/clock_citations.csv`, with exactly one row at `role = "primary"` and a non-empty `bib_key`. Each `bib_key` must resolve to an entry in `bibliography/clocks.bib`, and that entry carries `title`, `author`, `year` and `pmid`. The `pmid` in the two files must agree.

**Fixtures.** One `fixtures[]` entry per registry cohort, each carrying the cohort name, the expected scores, and which oracle produced them. See "The fixture" below.

`control/clock_meta_v1.csv` carries the descriptor columns that `codebook()` reports. It is a left join, so a clock the table misses reads `NA` rather than failing the build. Add the row where the values are known.

## Step 2: run the sync

```r
source("data-raw/sync.R")
sync()
```

This rebuilds the catalog and writes `R/sysdata.rda`, which is committed alongside the change. The rebuild takes a few seconds. External weight packs are reused from a lockfile unless their `bundle_hash` moved.

Three checks in the build are worth knowing about, because each one stops the sync rather than shipping something wrong.

**The declared panel must match `n_cpgs`.** `assert_declared_n_cpgs()` derives the scoring panel from the tensors and compares it to the declared count. There is no exemption list. A mismatch means the meta and the weights file disagree about the clock.

**Recipe operations come from a closed vocabulary.** An `op` outside `KNOWN_OPS` stops the sync and names the offending value. A new operation must be classified as per-sample or cross-sample before it can run.

**A declared path that does not exist stops the build**, naming the field that declared it.

## Step 3: check whether R code is needed

Routing is total. `score_type()` returns a known branch for every catalog entry, or it stops. There is no fallback branch and no "unsupported" state, so a clock that no branch claims fails the test suite rather than scoring silently.

Two declarations reach an existing branch with no code at all:

- `weights_format = "cpg_coefficient"` with `computation_type` of `linear` or `linear_transformed`.
- A `normalization` scheme the package already applies, which reaches the normalize-then-score branch.

A clock in a group that already has a branch routes on that group. Anything else needs a branch added to `R/`, and that branch needs a value test written by hand, because parity alone does not prove which branch ran.

## Step 4: run the tests

```r
devtools::test()
```

Each tier answers a different question, and the always-on tiers do not prove a score is correct.

**The smoke tier** scores every bundled clock that `clocks =` accepts. A new bundled clock joins it automatically. It proves the clock runs in the default configuration. It does not look at the number.

**The value tier** holds hand-written tests for each scoring path. A new branch belongs here. An existing branch does not need a new entry.

**The parity tier** is the science gate and it is where correctness is proved. It is skipped unless `MC_PARITY` is set and a cohort is staged, so a green `devtools::test()` says nothing about the arithmetic. The maintainer runs it.

The parity tier also holds a census test: every catalog clock must declare a fixture for every registry cohort. Sex-routed aliases are exempt, because their members carry the fixtures. A clock with no fixture emits no parity test at all, so the census is what turns a silent gap into a failure.

## The fixture

This is the one irreducible cost, and it is the reason the pipeline is worth its friction.

A fixture records what a trusted implementation produced on a known cohort. Parity then scores the same cohort through `calc_clocks()` and compares. Both an absolute and a relative bound must pass, both taken as a maximum over every element, so one wrong sample fails the test. Correlation is never used, anywhere, because it cannot tell agreement from a uniform offset.

**A clock the lab authored has the best available oracle: the author's own reference implementation.** Run it once on the cohorts, record the scores, and the fixture proves the package reproduces the author's own numbers. That check catches transcription errors, sign flips and probe-order mistakes, which are the failures nobody finds by reading.

The tolerance is a statement about units, never about agreement. Relaxing it needs a reason that survives review.

## Bundled or external

Small groups ship inside `R/sysdata.rda`. Heavy groups ship as release assets, downloaded on request and cached. `EXTERNAL_GROUPS` and `EXTERNAL_CLOCKS` in `data-raw/sync.R` decide, and the setting is per clock, so a group can have members on both sides.

Default to bundled. Move a group external when its weights are large enough that every user would pay for them.

## What to open

Open one pull request upstream and one here, and say in each that the other exists. The upstream change carries the declarations, the weights and the fixtures. The change here is the regenerated `R/sysdata.rda`, plus a branch and a value test if the arithmetic is new.

Read [CONTRIBUTING.md](https://github.com/HigginsChenLab/methylCIPHERv2/blob/main/.github/CONTRIBUTING.md) for the pull request process itself.
