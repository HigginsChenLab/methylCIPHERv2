# To-do

Queued work. **This is a staging area, not a record.** An item that becomes a design commitment
gets a dated `dev/DECISIONS.md` entry when it lands, and an item that becomes a rule moves to
`CLAUDE.md`. Delete an item when it ships; do not leave a done list behind.

There is no open code defect. Everything below is licensing, release plumbing, prose, or deferred.

---

## In progress

### P1. Make `summary()` readable at a glance

The digest is correct and is not yet pleasant to read. It went in on 2026-08-09 and was tightened
the same day (failed clocks named, `by_sample` collapsed to a spread, the duplicate row-gate
warning removed, the requested and dependency counts made to reconcile with the header), which
fixed what it *says*. What is left is how it *looks*.

The whole point of the object is that a reader skims it and stops. Today it is five sections of
`print.data.frame` output under bracketed headers, so a clean run and a run that lost a third of
its clocks read at the same visual weight. The model is `summary(lm)`: sections a reader can find
by shape, and the eye pulled to the line that matters.

Nothing here is a defect and nothing is urgent.

**Decided 2026-08-09, not yet written: hierarchy comes from indentation, not styling.** Two spaces
under each section header, so every table shares a left edge the eye can track -- which is also
the cell separator that reads as missing today. Indent survives `capture.output()`, a pasted
issue, a log file and a non-colour terminal; ANSI bold degrades to nothing, or to literal escape
codes in a capture. It also keeps `R/print.R` in plain `cat`, with no cli boundary to move.

Four mechanics, none of them free:

- **Spaces, not tabs.** `\t` renders at the terminal's tab stop -- 8 by default, configurable, and
  different between RStudio, a terminal and a captured file -- and it collides with the leading
  space `print(df, row.names = FALSE)` already emits.
- **Indenting needs a capture.** `print(df)` writes straight to stdout, so it is
  `capture.output()` then `cat(paste0("  ", lines), sep = "\n")` inside `print_table()`. The
  capture wraps at the current `width`, so the added two can push a wide line past the edge.
- **Left-aligning text is not a flag.** `print(df, right = FALSE)` left-aligns the numbers too.
  Pre-pad the character columns with `format(justify = "left")` and keep the default for numerics.
- **Count only a cut axis.** With the indent carrying the hierarchy, `[1 of 1 row(s)]` on a whole
  table is noise. Showing a count only where the axis really is cut removes most of the plural
  hedges in the same pass.

Target shape. The `explanation` column landed 2026-08-09, and with it the print-time drop of
`note` this mock already showed (DECISIONS 2026-08-09), so the columns below are what prints
today. What is missing is the indent and the alignment:

```txt
<mc_summary> 20 samples x 2 clocks

clocks [2 requested]
  Horvath1, Hannum

failed [1 clock]
  Hannum

problems by clock
  clock_id  panel  explanation                 n_samples
  Hannum    score  too few CpGs for the clock         20
```

Still open:

- **Section order buries the lede.** `input` and `arguments` sit between the clock list and the
  problems, so a broken run makes the reader scroll past two tables of boilerplate. `by_sample`
  is also the more readable of the two problem tables and prints second. Collapsing `input` and
  `arguments` to one line each when nothing is remarkable does most of this without a reorder.
- **The remaining plural hedges**, wherever an axis genuinely is cut. All of them come out of
  `plural_count()`, so one function fixes every print method at once.
- `mc_batch_id` is a 16-hex hash and is the widest column in three tables.
- Rounding is **not** an issue here: the digest prints only counts and the two floors. The 7-digit
  `coverage` column is `samples_coverage()`, a different frame and a separate question.

**Constraints.** `print.mc_summary()` shares the grammar in `R/print.R` with every other
`print.mc_*` method, so a change here is a change to `fmt_header` / `fmt_section` /
`print_table` / `print_vector` / `print_more` and lands on `mc_result`, `mc_sim`, `mc_citation`
and `mc_assets` too. That is the right depth, not a reason to special-case the digest. The
builders return strings so a cli printer and a `cat` printer emit the same text, and that must
stay true. `dev/WRITING.md` binds every character of it.

**Indent both helpers or neither.** `print_table()` is summary-only, but `print_block()` is read
by `print.mc_result` and `print.sim_DNAm`. Indenting one and not the other gives `print(res)` and
`print(summary(res))` different shapes, which is the drift the one-grammar invariant exists to
stop. The `explanation` column already widened `by_clock` by the length of a phrase, and
`shown_notes()` bought the room back by dropping `note` at the print site. `problems by clock`
now measures about 76 characters against a default width of 80, so an indent of two spends half
the remaining margin -- measure a multi-batch digest before assuming it fits.

### P2. The cli length problems a bullet count cannot see

The bullet pass landed 2026-08-09 (DECISIONS entry, and the verdicts are now `dev/WRITING.md`
section 3). It took 42 messages with two or more `"i"` bullets down to 25 and the seven with
three down to two. What it did **not** reach is everything that makes a message long without
adding a named bullet, and that class turned out to hold the worst offender in the package.

**The measurement is the thing to fix first.** `dev/cli_scan.R` counts named elements of the
first argument, so it is blind to a bullet built inside an `if` and to a list block. That is how
`check_coverage()` sat outside the audited set at fifteen rendered lines. Any second pass needs
an instrument that renders, or at least one that walks into `if` branches and `capped_bullets()`
calls.

Known remaining, none urgent:

- **`mc_manifest_bullets()` embeds a table.** Up to ten asset rows plus a total, inside
  `mc_consent()` and `mc_consent_delete()`. Both run to about fourteen lines on two or three
  bullets, and in `mc_consent()` the table sits between the assets directory and the fix that
  refers to it, so the two cannot simply be reordered.
- **Two more conditional-bullet sites.** `check_DNAm()`'s data.frame branch is the same shape as
  `check_coverage()` at smaller scale. `resolve_pheno()` puts up to ten sample ids inline in an
  `"x"` bullet rather than in a list.
- **Two long `{.code}` spans (R7).** `gate_disjoint_ids()` and `check_DNAm()`'s rownames fix.
  Both are permitted content, so this is formatting rather than policy.

`dev/cli-audit.md` holds the per-message detail. Its main table is stale for the rows that were
applied, but the appendix and the nine-message "leave these alone" list are still live, and the
role taxonomy is what section 3 was written from.

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
there. The suite has grown to 960 since, so a second trim may be worth it, but that is a judgement
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
