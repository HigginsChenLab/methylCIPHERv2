# To-do

Queued work. **This is a staging area, not a record.** An item that becomes a design commitment
gets a dated `dev/DECISIONS.md` entry when it lands, and an item that becomes a rule moves to
`CLAUDE.md`. Delete an item when it ships; do not leave a done list behind.

There is no open code defect. Everything below is licensing, release plumbing, prose, queued
feature work, or deferred.

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
there. The suite has grown to 996 since (2026-08-10), so a second trim may be worth it, but that is
a judgement to make against the budget rule, not a queued task.

`DESCRIPTION` is no longer part of this item either. `Title:`, `Description:`, `URL:` and
`BugReports:` were settled 2026-08-04.

### A4. Retire the `control/` exemption when `cohorts` lands

`codebook()` and the `list_clocks(all_columns = TRUE)` descriptor columns shipped 2026-08-09
against `control/clock_meta_v1.csv`, which CLAUDE.md now names as the one readable file under
`control/`. That exemption has an expiry and this is the reminder to collect it
(DECISIONS 2026-08-09).

Upstream calls the file a throwaway table with no per-field provenance, to be deleted once the
`cohorts` branch lands. `origin/cohorts` already carries `values_csv_fields_*_trained.csv` for the
same fields, with `check_locators.py` and a structural gate behind them, so the sourced
replacement is real work in progress rather than a hope.

When it merges:

- repoint `read_clock_meta()` (`data-raw/sync.R`) at the derived consumer artifact,
- delete the `control/` exemption from CLAUDE.md and restore the plain never-read line,
- re-check `CODEBOOK_CSV_FIELDS` against whatever the studies plane actually publishes, and
  `codebook_version()`, which derives `v1` from the source filename.

**Two things not to lose in the move.** `n_cpgs` is ours, read before `trim_build_only_fields()`
strips it, and must not revert to a paper-reported count -- the csv's own disagreed with the
shipped panel for 7 of 94 comparable clocks. And `mc_codebook` is a **left join**: rows it misses
read `NA`, which today is every sex-routed alias. Resolving an alias through `donor_clock_id` the
way `cite_clocks()` does would report `DNAmFitAge` as trained `"all female"`, because the donor is
always the `_Female` member. `test-list-clocks.R` and `test-codebook.R` both pin that.

The remaining question is whether the descriptor columns stay on `list_clocks(all_columns = TRUE)`
once they carry provenance, or move to `codebook()` alone. They are on both today because the
senior-facing MVP wanted them in the surface a reader runs first.

### A5. README, at submission

Restore the CRAN install block, deliberately absent while the package is not on CRAN.

The chunks are evaluated at knit time under `set.seed(1)`, and the missingness example depends on
`remove = 10` plus a 20-cell `sample.int()` draw, so a change to the seed or to either number moves
the printed output. The prose itself quotes no counts, so nothing has to be edited by hand to match.

### A6. Audit the declared dependencies, and write down why each one stays

Every `Imports` entry is a package a user must install to score a clock, so the set needs one
deliberate pass before it is frozen by a public release. Non-base today: `checkmate`, `cli`,
`digest`, `fs`, `Rcpp`. The output is a justification per entry -- what it is read for, what
dropping it would cost -- not necessarily a removal.

**`digest` was audited 2026-08-08 and stays.** One shipped call site, `batch_hash()`
(`R/mc_result.R`); the two in `data-raw/sync.R` are maintainer-side and never ship. It is a leaf
package -- no dependencies, own C, already installed nearly everywhere as a transitive dep of
knitr/shiny -- so dropping it saves one line and no transitive weight.

The replacement would be vendoring xxh64 into `src/`. **C++17 offers nothing usable, and this is
the part worth remembering**: `std::hash` is the only hash in the standard library and it is
explicitly implementation-defined, differs between libstdc++ and libc++, and is seeded per process
in some implementations. A batch label must be identical on Windows and Linux for the same id set,
so `std::hash` is disqualified outright rather than merely inferior. Deferring costs nothing either
way: labels are **derived, never assigned**, so no stored label anywhere would need migrating if the
hash were ever swapped.

---

## Backlog

### B1. Should `predict_sex()` surface probe coverage alongside the call

The aneuploidy column shipped 2026-08-10 (DECISIONS 2026-08-10, and the rule is in `CLAUDE.md`).
This is the half that did not.

Upstream recommends surfacing probe coverage beside the call, because `"Female"` is the residual
and a `FALSE` in `sex_aneuploidy` from a sample missing its sex-chromosome probes should not read
the same as one from a full panel. `predict_sex()` cannot do that today: it discards the
`mc_result` and returns a bare data.frame, so `clocks_coverage()` and `samples_coverage()` are
unreachable from what it hands back.

The extreme case is already handled and is not the argument for this. A sample with zero observed
CpGs scores `NA` at every floor, so it never reaches a `"Female"` call at all, which was measured
on 2026-08-10. The live case is **partial** coverage, where a weak signal still falls through to
the default.

This is a change to the return contract, not a column, which is why it was not folded into the
aneuploidy work. Deciding it means deciding whether `predict_sex()` keeps returning a plain
data.frame at all.

### B2. Harmonize how `data.frame` is written across user-facing text

One pass over roxygen, `README.Rmd` and `vignettes/*.Rmd`. Two axes, and they are separate
decisions.

**Spelling.** `data.frame` is the house form and is nearly uniform already: 25 roxygen mentions and
every `README.Rmd` mention use it, and `DOC_TYPES` in `R/dev-utils.R` pins the `@param` fragment as
`A data.frame.`, which `lint_roxygen()` enforces. There is exactly one outlier, the cli message at
`R/score_cohort.R:188`, which says "Pass a data frame to `pheno`". Nothing else in `R/` or the prose
files spells it with a space.

**Markup, which is the larger half.** R6 says every R language object in prose carries markup, and
`data.frame` is a class name, so most of these mentions are arguably unmarked today: `@returns A
data.frame.` and the `README.Rmd` prose both write it bare. Decide once whether `data.frame` is an
R language object that takes backticks and `{.cls}`, or a domain word that stays plain like "CpG"
and "M-value". Then apply it everywhere, including the `DOC_TYPES` fragment, so the linter and the
prose agree.

Do not split the two axes across two passes. Fixing the one spelling outlier without settling the
markup leaves the same inconsistency in a different place.

### B3. Re-audit the cli surface against the current rule set, on Opus 4.8

The last full cli audit predates R9, so every message has been graded against a rule set that has
since grown. Re-read `dev/WRITING.md` first, as the invariant requires, and grade the whole
user-facing surface: cli message text, roxygen prose, `README.Rmd`, `vignettes/*.Rmd`.

**Run this one on Opus 4.8, not Opus 5**, on the maintainer's judgement that 4.8 writes better
prose. That is a standing preference for prose passes, not a one-off.

Two things this pass should not repeat. The audit section of `dev/WRITING.md` already lists the
known-good exceptions an independent reader will otherwise re-report as defects, so read it before
flagging anything. And a rule the shipped files violate is worse than no rule, so where a message
and the file disagree, fix the file in the same pass rather than filing it.

Newest messages, least audited: `say_no_recorded()` and `say_mismatch()` in `R/predict_sex.R`, the
`sex_aneuploidy` roxygen, and the `summary()` / `print.mc_summary()` block from 2026-08-09.

### B4. Simplify pass over the vendored BMIQ

Three candidates, and one of them is already done, so measure before cutting.

**The RNG path is gone.** There is nothing left to drop in `R/`: no `set.seed`, no `sample.int`, no
`nfit`, no `.Random.seed` save and restore. The only RNG-adjacent thing left in the whole change is
the `nfit = length(gold)` argument sync passes to betanorm, and that one is load-bearing, not
residue. See the 2026-08-10 DECISIONS entry.

**The debug machinery is genuinely dead.** 21 references in `R/normalize_bmiq.R`: the `debug`
argument, `em_diagnostics()`, `sample.diagnostics`, and the per-sample `diagnostic` lists.
`bmiq_fit()` never passes `debug`, no test sets it, and the prefit now arrives with its
`diagnostics` already fixed at sync. This is the largest and safest cut.

**The scan overlap needs care rather than deletion.** `scan_finite_unit_interval_cpp(datM)` re-reads
columns that `col_stats()` already swept once at the front door (`R/missingness.R:218`). But the two
are not interchangeable: the front-door value gates **warn** where BMIQ needs a hard precondition,
and the kernel itself now stops on a boundary value. Work out which layer owns the invariant before
removing either, and do not leave it owned by nobody.

---

## Open questions

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
