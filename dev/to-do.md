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

### A3. Test suite trim and audit, with the first `R CMD check`

Deferred to immediately pre-alpha (DECISIONS 2026-08-03), and it lands together with the first
check run. Direction: assert what `calc_clocks()` produces, not how it is wired; no
`expect_identical`; no internal dispatch-tag tables; errors asserted as *that* and not by wording;
in-test re-derivation only where parity does not already own the golden. The last one is the
largest reduction, since anything parity covers should be a smoke here.

`DESCRIPTION` is no longer part of this item. `Title:`, `Description:`, `URL:` and `BugReports:`
were settled 2026-08-04.

### A4. `codebook()`. BLOCKED UPSTREAM

`data.frame(clock_id, description)`, dispatching like `cite_clocks()`. `description` is a sentence
per clock saying what the score means: the one column `list_clocks()` does not carry and that
nothing in the package can derive. Reinstated 2026-08-04, reversing the 2026-07-31 decision that
kept it out.

The method is small. The work is upstream: `description` is not verified across the 137 clocks in
`methylCIPHER-meta`. **Do not build it against a partially populated field** -- a `codebook()`
returning `NA` for most of the catalog reads as a package defect.

### A5. README, at submission

Restore the CRAN install block, deliberately absent while the package is not on CRAN. The three
counts quoted in the coverage prose follow the seed and the `remove = 100` argument, so a change to
either has to be carried into the sentences.

---

## Open questions

### Q2. BMIQ partial calibration: is a warning the right surface?

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

### Q5. `covariates =` name map on the front doors. DESIGNED, NOT BUILT

A caller whose pheno has `age_yrs` / `sex_f` must rename to `Age` / `Female` before scoring. The
ask is to accept a pointer instead. Requested by a senior collaborator; the counter is that it buys
a one-line rename at a real maintenance cost, so the shape below is what makes it affordable.

**One named map per front door, never one argument per covariate.**
`covariates = c(Age = "age_yrs", Female = "sex_f")`, validated with `assert_subset()` on the names
against `clock_covariates_required()` over the resolved sequence. `age_id` / `female_id` is the
shape that becomes `tissue_id` and `bmi_id` one at a time. Keep the noun `covariates`: the package
already uses it in `covariates_used`, `covariates_required`, `clock_covariates_coefs` and the
`covariates` stack namespace, so `alt_cov` would read as a different concept.

**Canonicalize, do not restore.** Rename inside `resolve_pheno()` (`R/validate_inputs.R`), which
already materializes a fresh subset, so the rename touches a names attribute and never the user's
object. Every downstream read is then untouched: `names(cov_coefs)` in `linear_predictor()`, the
`covariates` stack namespace, `coverage.R`, `gap_reasons.R`, `predict_sex.R`, `score_routed.R`.
Restoring the caller's names on the way out is the dead branch, for three reasons: `accel_label()`
builds the output column name from `attr(terms(formula), "term.labels")`, so the default model
would return `Age_accel` for one user and `age_yrs_accel` for another; `warn_age_units()` fires off
`"Age" %in% extra_columns` and would go silent for exactly the callers who renamed; and rewriting
user formula language is substitution into a call once `I(Age^2)` is in play, not a name swap.

**Both `calc_clocks()` and `calc_accel()` need it.** `$pheno` carries `Age` only when a scored clock
required it, so on a Horvath1 + Hannum record `$pheno` is the id column alone and the flagship
`calc_accel(res, data = my_pheno)` reads `Age` out of `data`. That is the common call, not an edge
case. `score_associations()` needs nothing: it already takes `age =` as a bare vector.

**Do not carry the map in `$provenance`.** That was considered and is worse.
`provenance$covariates_used` is today a catalog fact, which is why `rbind` can take
`ref[["covariates_used"]]` flat and ungated (`R/bind.R`); a caller-chosen map is not derivable from
the clocks, so it would have to become batch-keyed like `normalize_requested` and the two floors.
Stateless is strictly smaller, and it closes the one new trap for free: canonicalize `data` *before*
`merge_accel_data()` and `age_yrs` becomes `Age`, which now overlaps `$pheno`, so the existing "may
add a column, may not change one" equality check fires instead of silently carrying the same values
under two names.

**Scope if built:** one helper, two call sites, two arguments, the front-door messages naming the
caller's word, tests, a DECISIONS entry. The standing risk to state in that entry: a pointer moves
the name but not the contract, so `Female` pointed at a `1 = male` column passes
`assert_integerish(lower = 0, upper = 1)` and scores every GrimAge and every sex-routed clock
silently wrong.

### Q6. `normalize =` should accept scheme names

`normalize = c(Horvath1 = FALSE, DunedinPACE = TRUE)` is the only per-clock form today, and it is
cumbersome for what is nearly always a per-scheme wish. Measured 2026-08-07: the whole catalog is
133 `none`, 2 `bmiq` (`Horvath1`, `Knight`), 1 `quantile` (`DunedinPACE`), 1 inexpressible `noob`.

**The heterogeneity is scheme-shaped, with no residue.** A hand-written default list
(`list(DunedinPACE = TRUE, Horvath1 = FALSE, Knight = FALSE)`) carries exactly the information in
`NORM_DEFAULT_ON <- "quantile"` at three times the length: every `TRUE` in it is the quantile clock
and every `FALSE` is a bmiq clock. It would also be the first hand-maintained clock list in the
package, it needs the scheme rule as a fallback for a newly synced clock anyway (two sources for one
decision), and it fails the argument's own validation: `resolve_normalize()` aborts on
`setdiff(names(normalize), clock_sequence)` (`R/resolve_inputs.R`), so a default naming three clocks
would abort on `calc_clocks(clocks = "Hannum")`.

**Proposal:** a fourth accepted form, a character vector of scheme names, `assert_subset()`ed
against `NORM_SCHEMES`.

```r
calc_clocks(DNAm, clocks = "all", normalize = "bmiq")                  # bmiq on, quantile off
calc_clocks(DNAm, clocks = "all", normalize = c("quantile", "bmiq"))   # both
```

This makes the roxygen line the call-site documentation that was wanted: **Default is
`"quantile"`.** One word, exactly true, and it cannot drift because it is the constant. Keep the
named-logical form for the case schemes cannot express, normalizing `Horvath1` but not `Knight`,
which are both bmiq. Real, but rare, and it stops being the shape a caller meets first.

Optional and weigh it separately: a derived `normalize_default` logical in
`list_clocks(all_columns = TRUE)`, one line off `NORM_DEFAULT_ON`. It would be a fourth hidden
column at 3 non-empty rows out of 123, against the wide-set argument in DECISIONS 2026-08-03.

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

- [data-raw/build_clock_reference.R:98](data-raw/build_clock_reference.R:98) comments `sex_coef` as
  "male vs female"; the estimated level is female. Comment only, the numbers are correct.
