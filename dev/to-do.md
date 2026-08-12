# To-do

Queued work. **This is a staging area, not a record.** An item that becomes a design commitment
gets a dated `dev/DECISIONS.md` entry when it lands, and an item that becomes a rule moves to
`CLAUDE.md`. Delete an item when it ships; do not leave a done list behind.

**An item number is a stable identifier, so the sequence has gaps and that is not an error.** A
gap means that item shipped and was deleted. Do not renumber to close one: `dev/DECISIONS.md`
cites these numbers from outside this file, and a renumber silently repoints every citation. A2,
A3 and B1 are the gaps today, and B1 cost a session real confusion before this line existed.

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

### A7. Repoint every hard-coded owner reference, when the repo transfers

The org is `HigginsChenLab`, and **it is not a transfer.** The lab created
`HigginsChenLab/methylCIPHERv2` and `HigginsChenLab/methylCIPHER-meta` on 2026-08-06, both empty
(size 0, no branches), and asked for the contents to be pushed over. That is a different operation
from a GitHub transfer and the difference is load-bearing, so the rest of this item reads
accordingly. Copyright is already Yale's (`LICENSE`, and `DESCRIPTION` lists Yale as `cph`), so
neither operation moves ownership.

**Five of the six sites were repointed on 2026-08-12** and the sixth is deliberately unchanged.
What is left of this item is below the site list.

What a push does not carry, and a transfer would have:

- **Releases and their assets.** `git push` copies commits only. The old repo holds 4 releases /
  8 assets / ~91 MB (SystemsAge, PCClocks, PCBrainAge, Zhang2019), and the org repo will hold
  none, so every external clock stops scoring the moment `mc.release_repo` points at the org.
  **No always-on test catches this** -- parity skips those clocks when no pack is cached, so a
  warm-cache machine reports green. Fix is `sync(upload = TRUE)` with `MC_UPLOAD_PAT` set;
  `package_release_repo()` derives the target from `git remote origin`, so no code edit is needed,
  but the PAT needs release-write on the org, which is a new grant. **Do this before deleting or
  archiving the old repo** -- until it runs, the old repo is the only place the weights exist.
- **The redirect.** A transfer forwards old URLs; a push does not, and both repos stay live. Decide
  what `hhp94/methylCIPHERv2` becomes. Deleting it yields 404s rather than redirects, since GitHub
  only redirects on transfer or rename.
- **Issues and PRs.** Near-zero cost here (0 stars, 0 watchers, 1 fork), with one exception:
  **PR #3 is open and from an outside fork**, `dsborrus:feature/generics-and-qc`. Close it with a
  note rather than abandoning it silently.
- **`gh-pages`, and Pages itself.** The branch needs pushing or regenerating, Pages needs enabling
  on the org repo, and org Actions permissions are worth checking before relying on the deploy.

`ploidy-bmiq` is **not** in that list: it is fully merged (`origin/main..origin/ploidy-bmiq` is
empty) and should not travel. Turn on automatic head-branch deletion on the org repo.

The six sites, and they are not equivalent:

- `.github/CODE_OF_CONDUCT.md` carried the stub contact `hhp94@example.com`, which the sweep caught
  as intended. It now names the PI, `a.higginschen@yale.edu`, and **that is an interim, not the
  finished answer.** The earlier deadline is met, so the site no longer publishes a dead address to
  the people the document exists to protect. What is still owed is an address that is not a person:
  whoever is named becomes the enforcement body, and a NetID-backed address moves when its holder
  does. The target is a shared lab mailbox under the same org the repo transfers to, so that swap
  belongs with the rest of this item rather than ahead of it. Yale's central equity offices were
  considered and are wrong here -- a Contributor Covenant report can come from a contributor with
  no Yale affiliation about another one, which is outside their jurisdiction and their intake.
- `.github/CONTRIBUTING.md`, `create_from_github()`. **Done.**
- `_pkgdown.yml` `url:` and the matching `DESCRIPTION` `URL:` / `BugReports:`. **Done**, and
  `man/methylCIPHERv2-package.Rd` regenerated from them.
- `mc.release_repo` in `R/mc_data.R`. **Done.** Read the release bullet above before assuming this
  one is finished: the default now names a repo with no releases on it.
- `README.Rmd`, both the article link and `pak::pkg_install()`; `README.md` re-rendered. **Done.**
  The install line still names a GitHub repo rather than CRAN, per A5.
- `META_REMOTE` in `data-raw/sync.R`. **Deliberately unchanged.** Maintainer-side only, and it
  points at `methylCIPHER-meta`, a separate private repo. The org now has an empty
  `HigginsChenLab/methylCIPHER-meta`, which makes the move look decided; it is not, and it is
  upstream's call rather than a consequence of this one.

**A5 and this item touch the same README block**, so do them in one pass or the second one
re-renders over the first.

What is still open on this item:

1. The push itself, and the four carry-over tasks above.
2. The CoC contact, currently the PI as an interim; see that bullet.
3. **`Authors@R`, which this item used to say the move does not change.** That is still true of the
   move and was the wrong thing to record, because it reads as "nothing to do here". Pre-rewrite
   history carries 156 commits from nine identities -- Kasamoto 47, Thrush 35, Pham 29, Sehgal 20,
   Higgins-Chen 14, Borrus 10, Schaaf 1 -- against 124 post-rewrite commits from Pham alone.
   `Authors@R` names Pham, Thrush and Yale, so five contributors including the PI appear nowhere in
   the package metadata, and the commit log is the only record. That is worth settling before the
   package carries the lab's name, and it is the reason not to truncate history (audited
   2026-08-12: no secrets ever committed, and pre-rewrite is only 27 MB of 118 MB in blobs, most of
   the bulk being post-rewrite `R/sysdata.rda` churn).

One thing that genuinely does not change: CRAN needs one human `cre` and cannot take an
organization, so `cre` stays a person and a later change of maintainer has to come from whoever
holds it at the time.

---

## Backlog

### B3. Re-audit the cli surface against the current rule set, on Opus 4.8

The last full cli audit predates R9, so every message has been graded against a rule set that has
since grown. Re-read `dev/WRITING.md` first, as the invariant requires, and grade the whole
user-facing surface: cli message text, roxygen prose, `README.Rmd`, `vignettes/*.Rmd`.

**Run this one on Opus 4.8, not Opus 5**, on the maintainer's judgement that 4.8 writes better
prose. That is a standing preference for prose passes, not a one-off.

Two things that follow from that and are easy to get wrong. **It cannot be delegated to a
subagent**: the model argument takes a family alias, so a spawned agent inherits the session's
Opus, and pinning 4.8 means starting the session on 4.8. And it belongs on **its own branch off
`main`**, after the current work has landed, because it grades text that work just wrote and a
whole-surface copy-edit mixed into a code change is unreviewable.

Two things this pass should not repeat. The audit section of `dev/WRITING.md` already lists the
known-good exceptions an independent reader will otherwise re-report as defects, so read it before
flagging anything. And a rule the shipped files violate is worse than no rule, so where a message
and the file disagree, fix the file in the same pass rather than filing it.

Newest messages, least audited: `say_no_recorded()` and `say_mismatch()` in `R/predict_sex.R`, the
`sex_aneuploidy` roxygen, and the `summary()` / `print.mc_summary()` block from 2026-08-09.

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
