# To-do

Queued work. **This is a staging area, not a record.** An item that becomes a design commitment
gets a dated `dev/DECISIONS.md` entry when it lands, and an item that becomes a rule moves to
`CLAUDE.md`. Delete an item when it ships; do not leave a done list behind.

There is no open code defect. Everything below is licensing, release plumbing, prose, or deferred.

---

## Before public alpha

### A1. Package license, forced by the clock weights

The terms come from upstream: each clock's weights and paper carry their own license, recorded in
the catalog's `license` field, which is populated for all 137. The package currently declares
`BSD_3_clause + file LICENSE` with Yale University as copyright holder.

**The likely outcome is GPL-2.** Copyleft terms on any bundled clock propagate to the distributed
work, and 10 clocks declare GPL-2, GPL-2+, GPL-3 or GPL-3 / CC-BY-4.0. BSD-3 cannot carry them.

Distribution as declared upstream:

| Declared terms | Clocks | Effect |
| --- | --- | --- |
| open-redistributable | 31 | no constraint |
| MIT | 3 | no constraint |
| CC BY, CC BY 2.0, CC BY 4.0 | 5 | attribution required |
| GPL-2, GPL-2+, GPL-3, GPL-3 / CC-BY-4.0 | 10 | copyleft, forces the package license |
| journal-supp | 33 | varies by journal, unresolved |
| public-github-unspecified | 26 | no rights granted by default |
| unspecified | 15 | unknown |
| non-commercial | 12 | not redistributable under any OSI license |
| CC BY-NC-ND 4.0 | 1 | not redistributable, also no derivatives |
| research-use-only | 1 | not redistributable under any OSI license |

**Two problems, and relicensing solves only the first.** GPL-2 resolves the 10 copyleft clocks. It
does nothing for the 14 under non-commercial, CC BY-NC-ND 4.0 or research-use-only terms, which no
OSI license absorbs and which CRAN's free-redistribution requirement does not permit. Those have to
be dropped, moved behind the external asset split, or cleared with the rights holder. The 41 under
`unspecified` or `public-github-unspecified` are unknown rather than permissive: code published
without a license grants no redistribution right.

**Upstream work first.** The field records what upstream has recorded, and it is not verified per
clock. Nothing can be settled package-side until it is. `LICENSE`, `LICENSE.md` and the
`^LICENSE\.md$` line in `.Rbuildignore` are already in the shape CRAN expects, whichever license
lands.

### A2. `CLAUDE.md` is published on the pkgdown site

`pkgdown:::package_mds()` globs the package root plus `.github/` and drops only README, LICENSE,
NEWS and the two GitHub templates. The drop list is hard-coded and `.Rbuildignore` does not apply.
On pkgdown 2.2.1 it returns `CLAUDE.md`, so the site carries `CLAUDE.html` and indexes it in
`search.json` and `sitemap.xml`.

The site was published 2026-08-04 for internal collaboration, accepting this. **Resolve before the
site is public.** `CLAUDE.md` names the private `methylCIPHER-meta` remote, the maintainer upload
path, and the known parity gaps.

Options: r-lib/pkgdown#2959 (open since 2025-11-24, adds file exclusions), a CI step that deletes
the rendered file before deploy, or accepting it. A CI guard was written and reverted 2026-08-04 as
maintenance debt that breaks when either pkgdown or the file set moves. `CLAUDE.local.md` is
gitignored and never reaches the runner, so the tracked `CLAUDE.md` is the whole exposure.

### A3. The first `R CMD check`

Deferred to immediately pre-alpha (DECISIONS 2026-08-03). Check has never been run here: it is
maintainer-on-demand by invariant, so the first run is its own piece of work and will surface
things nothing else can, starting with the unstated-dependency scan and the examples.

**The trim already happened and is not part of this item.** 1284 expectations were cut to 801 on
2026-08-04, and the direction that guided it -- assert what `calc_clocks()` produces, no
`expect_identical`, no dispatch-tag tables, errors asserted as *that*, in-test re-derivation only
where parity does not own the golden -- is now the "Test altitude" section of `CLAUDE.md`. Read it
there. The suite has grown to 915 since, so a second trim may be worth it, but that is a judgement
to make against the budget rule, not a queued task.

`DESCRIPTION` is no longer part of this item either. `Title:`, `Description:`, `URL:` and
`BugReports:` were settled 2026-08-04.

### A4. `codebook()`. BLOCKED UPSTREAM

`data.frame(clock_id, description)`, dispatching like `cite_clocks()`. `description` is a sentence
per clock saying what the score means: the one column `list_clocks()` does not carry and that
nothing in the package can derive. Reinstated 2026-08-04, reversing the 2026-07-31 decision that
kept it out.

The method is small. The work is upstream: `description` is not verified across the 137 clocks in
`methylCIPHER-meta`. **Do not build it against a partially populated field** -- a `codebook()`
returning `NA` for most of the catalog reads as a package defect.

### A5. README, at submission

Restore the CRAN install block, deliberately absent while the package is not on CRAN.

The chunks are evaluated at knit time under `set.seed(1)`, and the missingness example depends on
`remove = 10` plus a 20-cell `sample.int()` draw, so a change to the seed or to either number moves
the printed output. The prose itself quotes no counts, so nothing has to be edited by hand to match.

---

## Open questions

### Q5. QC digest. DESIGNED, NOT BUILT -- pick up here

**Decided: post-flight, not pre-flight.** A pre-flight `report(DNAm)` arm was asked for and is
refused. It is a second beta reader (see the one-entry-point invariant), and the measurement kills
its rationale: on 50 x 323,499, everything up to normalization is 0.37s of a 3.03s call, and the
scoring loop itself is 0.12s. BMIQ is 87% and sits *after* where a pre-flight stops, so it warns
about nothing expensive and is pure overhead. It also cannot report `fit` failures, NaN scores,
declined normalization, or which clocks came back `NA` -- none of that exists until scoring runs.
Post-flight is a strict superset, and it describes the matrix that was actually scored.

**The blocker: the front-door findings are not retained.** `check_col_values()` (`R/missingness.R`)
reads `min_val` / `max_val` / `min_col` / `max_col` / `any_inf` off the `col_stats()` sweep, warns,
and returns `invisible(NULL)`. `scan_missing_cpgs()` drops them; `mc_cohort()` also drops
`all_na_cols`; `construct_mc_result()` has no field for any of it. So the digest cannot print the
input diagnostics until the record keeps them. What must start being recorded:

- input shape (`ncol(DNAm)` -- `nrow` is already `sample_id`)
- the value verdicts (min / max with the offending column, `any_inf`)
- the all-NA column count
- BMIQ partial calibration per sample -- this is what folds Q2 in below

Already available, no change needed: clocks requested vs dependencies, `normalized` vs
`normalize_requested` (already per batch), both floors, `scoring_failures`, NaN/Inf scores
(recomputable -- `$scores` keeps `NaN` distinct from `NA`), and both collapses from
`samples_coverage()`.

**Grain: long `(unit, reason)`, both halves.** Not collapsed. Collapsing is lossy exactly where the
digest earns its keep -- a clock failing 3 for `covariate` and 2 for `sample_coverage` becomes one
unreadable row, `all_failed` turns ambiguous, and the decode stops matching the closed set. The
reason vocabulary is 5 values (`covariate`, `clock_coverage`, `sample_coverage`, `fit`,
`dependency`, `R/gap_reasons.R`), so human-readable text is a 5-entry named vector, not a parser.
Long costs nothing in the common case: in an adversarial 12-sample fixture, 16 clocks failed and
**0 were mixed** -- `clock_coverage` is a per-batch column verdict, so it cannot co-occur with a
per-sample reason on the same cell.

**`score_associations()` stays out.** It needs an age vector, and a `summary`-shaped call taking a
mandatory argument is a contradiction. Building strictly on `samples_coverage()` also means the
digest never touches `$scores` or `$coverage`, so it adds no `finalized()` call site and inherits
multi-batch handling free.

**Constraints on the print.** Reuse `R/print.R`'s builders. `$` in that grammar means "a component
you may reach for", so the input / problems / collapse sections take `fmt_named_section()`, the
un-`$` form the multi-batch `mc_batch_id` block uses. Nothing may name `$provenance`. Note the
range scan covers **panel columns only**, not the whole matrix -- the existing warning's "`DNAm`
contains values above 1" is already loose on this and should be tightened in the same pass.

**Open, decide first:** does `summary()` return the digest or only print it? Print-only keeps "there
is no third frame" intact but makes the collapses unreachable in code; returning two frames is
useful and is, fairly read, two more frames. The standard idiom -- return invisibly, print by
default -- gets both and is the current lean, but it should be chosen knowingly.

### Q2. BMIQ partial calibration: is a warning the right surface?

**Folded into Q5 above.** Keep the analysis here until Q5 lands.


`say_partial_calibration()` (`R/score_cohort.R`) warns when BMIQ skipped its H step for a sample
(`h.applied == FALSE`). That sample **still scored** -- the value is not `NA`. A warning about a
successful score reads as a failure, which is why the wording was softened in the 2026-08-07 cli
pass ("still has a score, from a partial calibration") but the channel was left as `cli_warn`.

The open question is the surface, not the wording. A partial calibration is a per-sample fact about
how a cell was produced, which is exactly the shape `samples_coverage()` already carries per (sample,
clock). Folding it in there -- a column, or a value in `reason` -- would let a caller find the
affected cells on demand instead of being warned about a non-problem at score time. That likely
lets the warning drop entirely, the same way an `NA` score is explained by the `reason` column
rather than by a bare warning.

Do not act before deciding what a partial calibration means to a user who did not ask about BMIQ
internals. If it changes nothing they can act on, it may not belong in any user-facing surface at
all.

### Q1. Chunked front end. PARKED

Every piece exists: batch-wise fill regimes, derived batch labels, `rbind`, retained `pending`,
`refinalize_clocks()`. Parked because the usage does not yet justify the front-end surface.

Both axes now refuse a per-chunk re-derivation rather than scoring it (DECISIONS 2026-08-05):
a `usable_cols` that is not the one the panels were resolved against stops in `mc_block()`, and a
chunk row the cohort facts do not carry stops in `block_rows()`. Read those two before designing
the chunk loop -- they are the constraints it has to satisfy.

The alternative works today: score each cohort separately, save each `mc_result`, and `rbind` once
at the end. One wrinkle, worth deciding rather than leaving to chance: two cohorts with the same
sample ids hash to the same `mc_batch_id`. A cohort tag carried on `pheno` and folded into the hash
would separate them. This interacts with `rbind` gate 1, where overlapping ids throw, so the tag has
to be decided together with what "the same sample" means across cohorts.

### Q4. Sex prediction when the deposit has no chrY. PARKED

`predict_sex()` needs both Wang members, so a GEO series that strips chrY returns all `NA`. The
question is whether a chrX-only fallback is worth building.

Measured 2026-08-07 on `cohort_EPICv1` (71 samples, all 19090 manifest chrX probes present, from
`slideimp.extra::ilmn_manifest("EPICv1")`):

| statistic | probes | Cohen d | gap / within-sd |
| --- | --- | --- | --- |
| PC1 of scaled whole chrX | 19090 | 11.06 | 6.17 |
| PC1 of the Wang chrX rotation panel | 4046 | 22.25 | 17.38 |
| PC1 of chrX outside that panel | 15044 | 8.03 | 3.38 |
| intermediate fraction, whole chrX | 19090 | 13.92 | 9.80 |
| intermediate fraction, Wang panel | 4046 | 29.80 | 24.15 |

"Intermediate fraction" is the per-sample share of chrX betas in (0.25, 0.75), the X-inactivation
signature. `hclust` or `kmeans` on the whole-chrX PC1 recovers recorded sex perfectly (43 female,
28 male), and stays perfect down to 50 random chrX probes, so the signal is not in doubt.

Four findings that shape the design:

1. **Whole chrX is the noisier feature.** Wang's 4046 chrX probes carry roughly three times the
   separation of the whole chromosome by the gap ratio, and the 15044 probes outside the panel are
   what dilutes it. Any fallback should score the declared panel, not the chromosome.
2. **A per-sample statistic beats clustering.** Clustering fails on a single-sex cohort (females
   only still cut 5 / 38) and cannot label its own clusters. Cluster separation does not detect
   that failure: gap over within-sd was 6.17 mixed against 4.00 female-only and 6.87 male-only.
   PC1 variance explained does (0.576 against 0.186 and 0.180) but that is one number from one
   cohort.
3. **It cannot restore the karyotype calls.** On chrX alone `47,XXY` reads as `XX` and `45,XO`
   reads as `XY`, so the declared rule table loses half its vocabulary. Any fallback emits binary
   calls only, and that has to be visible to the caller rather than silently substituted.
4. **`cohort_450K` strips chrX too**: 0 of 11232 manifest chrX probes in a 473034 probe deposit,
   which is why `DNAmSex_Wang_*@cohort_450K` sits in `KNOWN_PARITY_GAPS`. So the addressable
   population is "chrX kept, chrY dropped", and nobody has measured how large that is. **Measure it
   against a real GEO sweep before building anything.**

Direction if it is built: a posterior over the two classes, not a threshold. Two candidate shapes,
and the choice is not obvious. A cohort-wise two-component mixture needs no training data and no
cut, but inherits failure 2 above and cannot score `n = 1`. A model trained across many series
transfers to a single sample, but its labels are the recorded sex, which is the thing
`sex_mismatch` exists to doubt, so it would have to be fitted on samples where chrX and chrY
already agree. The hybrid (trained likelihood, cohort-derived prior) is the interesting one.

Two package constraints on any trained variant. Wang's own per-sample standardization against the
autosomal reference domain is what makes its score comparable across arrays, so a new statistic
needs an equivalent or it will not transfer. And a fitted model is weights: it belongs upstream in
`methylCIPHER-meta` as a declared clock with tensors and a meta, never as a constant in `R/`.

---

## Housekeeping

- [data-raw/build_clock_reference.R:91](data-raw/build_clock_reference.R:91) comments `sex_coef` as
  "male vs female"; the estimated level is female. Comment only, the numbers are correct.
