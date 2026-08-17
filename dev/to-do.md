# To-do

Queued work. **This is a staging area, not a record.** An item that becomes a design commitment is
argued in the commit message and the PR body that land it, and an item that becomes a rule moves to
`.claude/CLAUDE.md`. Delete an item when it ships; do not leave a done list behind.

**An item number is a stable identifier, so the sequence has gaps and that is not an error.** A
gap means that item shipped and was deleted. Do not renumber to close one: commit messages cite
these numbers from outside this file, and a renumber silently repoints every citation. A2,
A3, B1 and B3 are the gaps today, and B1 cost a session real confusion before this line existed.

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

**Yale as `cph` is part of this item, not a separate one.** `DESCRIPTION` names Yale University as
copyright holder and `LICENSE` says the same, so the institution's name is already attached to
whatever the package ships. That is exactly why the two cannot be settled apart: putting the lab's
and the university's name on a distribution that violates a clock's terms is the failure mode, and
the `cph` line is what makes it their exposure rather than a maintainer's. So the copyright holder,
the package license and `Authors@R` in A7 resolve together, and none of the three is a formality to
be tidied ahead of the other two. All of it is still open.

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

### A7. Attribution, and the Code of Conduct contact

**The move itself is finished and this item is what it left behind.** All six owner-reference sites
are settled, the packs are republished and verified against the org from a cold cache, Pages is
live, and the outside PR on the old repo was closed with a note. None of that needs revisiting.
Two things are open, and both are about whose name is on the package rather than about plumbing.

**1. The CoC contact is an interim.** `.github/CODE_OF_CONDUCT.md` names the PI personally,
`a.higginschen@yale.edu`, which cleared the real problem: the file previously published a stub
address to the people it exists to protect. What is still owed is an address that is not a person.
Whoever is named becomes the enforcement body, and a NetID-backed address moves when its holder
does, so the target is a shared lab mailbox under the org. Yale's central equity offices were
considered and are wrong here, because a Contributor Covenant report can come from a contributor
with no Yale affiliation about another one, which is outside their jurisdiction and their intake.

**2. `Authors@R` does not match who wrote the package.** Pre-rewrite history carries 156 commits
from nine identities (Kasamoto 47, Thrush 35, Pham 29, Sehgal 20, Higgins-Chen 14, Borrus 10,
Schaaf 1) against 124 post-rewrite commits from Pham alone. `Authors@R` names Pham, Thrush and
Yale, so five contributors including the PI appear nowhere in the package metadata and the commit
log is the only record. This is the reason not to truncate history, which was audited 2026-08-12:
no secrets were ever committed, and pre-rewrite accounts for 27 MB of 118 MB in blobs, most of the
bulk being post-rewrite `R/sysdata.rda` churn.

**These resolve with A1, not before it.** Yale is already `cph`, so the institution's name is
attached to whatever ships, and the contributor list is the other half of the same question. See
the `cph` paragraph in A1: the copyright holder, the package license and this list are one
decision taken three times, and taking any one of them early just means redoing it.

One thing that genuinely does not change: CRAN needs one human `cre` and cannot take an
organization, so `cre` stays a person and a later change of maintainer has to come from whoever
holds it at the time.

**Loose ends, small and independent of the above.** The old repo still needs archiving rather than
deleting, since deletion yields 404s and GitHub only redirects on transfer or rename, and the
merged `ploidy-bmiq` branch can go. Automatic head-branch deletion needs admin on the org repo,
which is tracked in `dev/next-step.md` section 3.

---

## Backlog

### B4. `report_mc_result()`, a static HTML QC report

`summary()` shipped 2026-08-09 as the QC digest and is the first piece of this. The second is a
static HTML render of the same material: the digest laid out properly, plus the full coverage
output that `summary()` deliberately caps, in tabs.

**The two coverage frames are the two tabs, and there is no third.** `clocks_coverage()` is one row
per (clock, batch), `samples_coverage()` is one row per sample per panel with the `note` column.
A report tab is a view of one of those frames, never a new aggregation invented for the page.

Four constraints the invariants already fix, each easy to break in a renderer:

- **`summary()` never reads a score value**, which is what keeps it off `finalized()`'s call-site
  list. A report that displays `$scores` **is** a finalizer and has to call `finalized()` and say
  so. Decide that deliberately rather than discovering it.
- **`$provenance` is internal.** No printed section may name it, and an HTML page is printed
  output. Every fact in it has an exit that presents it better.
- **The two problem tables are two views, not a transpose.** `by_clock` is keyed
  (clock_id, panel, note); `by_sample` counts samples. Collapsing them into one sortable widget
  loses the distinction that makes each readable.
- **Never total a per-batch row across batches**, and the batch column only exists at multi-batch,
  so the renderer must not assume it is there.

**The dependency question comes first, and it is not free.** `reactable` and `htmltools` are in
`Config/Needs/website` today, which is website-only and costs a user nothing. Calling them from
`report_mc_result()` moves them into `Suggests`, which is a real user-facing dependency and lands
squarely in A6. `rmarkdown` and `knitr` are already in `Suggests`. Settle the dependency shape
before writing the renderer, because it decides whether this is a self-contained HTML writer or a
widget host.

### B5. Two pkgdown articles: a FAQ, and the clock licenses

**Home is `vignettes/articles/faq.Rmd`.** `^vignettes/articles$` is in `.Rbuildignore`, so an
article renders on the website and never enters the tarball: no bytes, no `R CMD check` surface, no
CRAN cost. `clocks.Rmd` is the precedent, and pkgdown picks a new article up with no
`_pkgdown.yml` change. It is not a root markdown file, so it avoids the root-glob problem that put
`CLAUDE.md` under `.claude/`.

**The sorting rule, because half of the candidate questions are really doc bugs.** If the answer
belongs next to the thing, fix the reference page instead. "Where is the list of normalization
schemes" is a gap in the `normalize` param and the Normalization section of `mc-params`, and
answering it in a FAQ is how that gap survives. If the answer is "why this way and not the obvious
other way", it is an entry.

**Three properties keep this from becoming the decision log CLAUDE.md bans.** It is topical and
edited in place rather than append-only newest-first, so two authors editing different questions do
not collide at byte zero. Entries are deletable, and get deleted when the answer graduates into the
reference docs, so the file shrinks. And each entry ends with a pointer to the commit or PR holding
the measurements rather than reproducing them, which makes it an index and not a lossy replacement.

**Seed only from questions actually asked.** Speculative entries are how it turns into a dump. The
set with real evidence behind it today:

- Why do the scores not match the Horvath online calculator? (the oracle fills absent probes
  server-side with an unpublished per-probe constant and BMIQs its panel for `DNAmAge` only, so the
  residual tracks absent-probe count; pairs with zero absent probes agree to about 1e-8 relative)
- Why did my clock score `NA`? (both floors, and the `note` column of `samples_coverage()`)
- Why do the large weight sets download instead of shipping with the package?
- Why CRAN and not Bioconductor? (10 MB built and 5 MB per file is the same constraint on both, so
  the difference is the mechanism: ExperimentHub would replace the whole asset surface)
- Why can I not request `DNAmFitAge_Female` by name?

**A second article, listing every clock's license.** Same `vignettes/articles/` home and the same
website-only cost.

It is **not** a view of the catalog surface, and that is the point rather than an oversight.
`codebook()` and `list_clocks(all_columns = TRUE)` carry many descriptor columns because they
answer "what is this clock", and a reader who wants to know whether they may use a clock in a
commercial setting needs three columns rather than twenty. Making them read the wide table to find
one field is how the question goes unanswered.

Three columns: the clock, the declared terms, and **what the terms mean for use**. The third is
the one that earns the page, because `GPL-2` and `CC BY-NC-ND 4.0` are strings a biologist has no
reason to be able to decode, whereas "using this obliges your own work to be GPL" and "cannot be
redistributed at all" are decisions they can act on.

**Generate it from the catalog, never hand-maintain it.** The `license` field is populated for all
137 clocks, so the page is a chunk reading the catalog at knit time. A hand-written table desyncs
on the next sync and nothing would catch it.

**It must state that the field is unverified, prominently and at the top.** A1 records that the
catalog reports what upstream recorded and that no per-clock verification has happened yet.
Publishing an authoritative-looking license table off an unverified field is worse than publishing
none, because people will rely on it. The honest framing is "as declared upstream, corrections
welcome", which also makes the page the natural place to point at B6's feedback route: a reader who
knows a clock's real terms is the cheapest verification available, and A1 currently has no other
source of it.

### B6. A request front door for new clocks

Where someone with no access to anything asks for a clock to be included.

**Split `ADDING_A_CLOCK.md` in two, and that is the real finding here.** The document already shows
the seam: it says meta is private and a contributor needs read access before any of it is possible,
and everything after that sentence is written for someone who got access. A clock author asking to
be included never will. So `.github/ADDING_A_CLOCK.md` stays what it is, the internal contract
(meta fields, the derived path rule, the manifest row, sync, fixtures, routing), and a new public
article carries the request path, assumes no access, and never mentions `manifest.json`. The two
link to each other, and the article also links across to B5's license article, which is the same
question from the submitter's side.

**v1 is the field list as prose. No form, no JS, no issue template, no workflow.** The mechanism was
discussed to the end and deliberately not built: an article-hosted HTML form doing client-side
validation, building a prefilled issue URL (GitHub prefills issue-form fields by query parameter
matching each field's `id`), with R validation in a `issues: [opened]` workflow using `setup-r` the
way `test.yaml` already does. All of that is real and none of it is v1. Writing the fields down is
what has to be right first, because every later mechanism just re-encodes them.

**Uploads are not solved and should stop being attempted.** GitHub issue forms have no file field at
all. Ask for a URL instead: most clock authors already publish their own work, and 26 clocks in the
catalog are logged `public-github-unspecified`, meaning the weights are on GitHub right now. A link
also beats an attachment on merit, since it keeps pointing at whatever the authors correct later
where a pasted file is a snapshot with no provenance. Oversized or awkward cases contact the
maintainer, which is one sentence of prose and will almost never fire: a single clock's coefficients
are tens of KB, and the heavy things here are whole packs (SystemsAge 23 MB, PCClocks 8.9 MB).

**Two things are not the maintainer's call alone.** A clock is declared in `methylCIPHER-meta`,
which is private and separately owned, so the queue and the repository that fulfills it currently
have different owners. And whoever triages has to answer requests, which is a standing commitment
rather than a one-time build.

#### The fields, v1

Ids use upstream's own words (`n_cpgs`, `pmid`, `license`) so the article, the meta file and any
later validation all say the same thing.

**Disclaimer, at the top.** Say that it becomes a public issue, not that secrets are bad. "This
becomes a public GitHub issue" is what makes someone check; "do not put your secrets" reads as
boilerplate. Name the failure modes: unpublished data, credentials, file contents.

**Who is asking.** `first_name`, `last_name`, `github_user`, `contact_email`, `relationship`.

- At least one of `github_user` and `contact_email`, both allowed. No issue form can express that
  rule, so it would live in the JS and again in the workflow.
- But **a GitHub issue already records who opened it**, so the contact fields only do work when
  someone files for a colleague or wants replies elsewhere. Frame them that way, or accept that
  both are optional and the rule is vacuous. Undecided.
- Email in `name at example dot com` form, to cost the naive scrapers something. It also costs any
  future validation the `@` check, leaving only non-empty. Put the expected shape in the
  placeholder or people invent five variants.
- `relationship` (author / works with the authors / user) is the highest-value field and was not in
  the first draft. It says whether the license and reference-value answers are authoritative or
  secondhand, and secondhand answers to both need re-asking.

**The paper.** `clock_name`, `doi`, `pmid`, `paper_url`.

- **Published only, and say so explicitly.** Do not lean on `pmid` to enforce it: bioRxiv mints
  DOIs and Europe PMC gives preprints a `PPR` id, but NIH-funded preprints deposited through the
  NIH Preprint Pilot land in PMC with real PMIDs. A PMID does not prove peer review.
- `pmid` stays required because upstream requires it and the two citation files cross-check it.

**How the score is computed.** `model_url`, `clocks`, `model_notes`.

- **Not "weights".** Upstream's own vocabulary already separates `weights_format`,
  `computation_type` and `recipe`, and only one of those is a coefficient list. The user-facing
  section is how the score is computed, and `model_notes` is the free-text home for normalization,
  covariates, transforms, anything that is not a plain weighted sum.
- **One paper per issue, not one clock**, which maps to `group_id` and scales to a twelve-member
  family without twelve issues. `clocks` is a textarea with a declared line format, `name, n_cpgs`
  one per line, so it stays machine-readable later. `assert_declared_n_cpgs()` stops the sync when
  the declared count and the file disagree, so the CpG count is the one number a check can get a
  real answer from.

**License.** `license`, `license_url`. Its own section, physically separated from `model_url`.

- A1 is the live blocker, and a non-commercial, no-derivatives or research-use-only clock cannot be
  fulfilled by bundling at all, so asking at intake saves the whole round trip.
- The trap the separation exists for: answering "here it is on GitHub" feels like it answered "you
  may ship it". Those same 26 `public-github-unspecified` clocks are exactly the case, public and
  granting no redistribution right at all.
- Options in plain terms, not the catalog's internal labels: MIT/BSD/Apache; GPL or other copyleft;
  CC BY; CC BY-NC; CC BY-ND; research or academic use only; public with no license stated; other;
  I do not know.
- **No copyright-holder field in v1.** The coefficients often belong to a publisher rather than the
  authors, which is a different question from the license. Real, and judged too much for v1.

**Reference values.** `has_reference_scores`, plus notes.

- **Without oracle values there is no science gate**, so a request with none is either a rejection
  or a research task, and the article should say which.
- Options: yes; no; I do not know what this means. The third is deliberate, because someone picking
  it has told you they are not the person to ask, which beats a guessed yes.

### B7. `write_mc_results()`, one call that writes a whole run to a directory

Scores, both coverage frames, and the B4 HTML report, written under a caller-supplied path.
Depends on B4, so it lands after it.

**It is a finalizer, and that is the first thing to get right.** The test has two clauses and this
meets both: it returns something that is not an `mc_result`, and it reads the cells of `$scores`
rather than their shape. So it calls `finalized()` and joins that call-site list, which is
`as.data.frame()`, `as.matrix()`, `calc_accel()`, `score_associations()` and `samples_coverage()`
today. It must **not** be reached by way of `rbind()` or become recursive, for the reason `rbind`
is kept off the list.

**Not a method, and the reason is the `cite_clocks()` precedent.** Base R has `write()` and
`write.csv()` as plain functions, so taking either name masks them, and neither is generic. Make it
a plain exported function like `calc_accel()`, and do not mint a `write` generic to satisfy the
verb-is-a-method rule, which only binds where a suitable generic already exists.

**The conditional batch column is the schema trap.** `as.data.frame()`, `calc_accel()` and both
coverage frames build the `mc_batch_id` column only when the record spans more than one batch, and
the invariant is that the four appear and vanish together. Writing files means those schemas become
artifacts on someone's disk, so a single-batch run and a bound run produce differently shaped CSVs
under the same filenames. Either accept that and document it, or decide the written form always
carries the column. Do not resolve it by making one exit disagree with the other three.

**Writing to a user's filespace is the CRAN-sensitive part.** The path is an argument with no
default that writes anywhere surprising, and an existing directory needs the same consent register
the assets surface already uses, where only `ask = FALSE` consents and anything that is not a
single non-NA logical is an error rather than permission. Decide the overwrite behaviour explicitly
rather than inheriting whatever `write.csv()` does.

### B8. Score across multiply imputed beta matrices

A caller with `m` imputed versions of the **beta matrix** wants every clock scored on each one and
the results pooled, so that uncertainty from the imputation reaches the score instead of being
discarded by picking one completion.

**Two structural collisions, both with `rbind`, and they are the reason this is not just a loop.**
Gate 1 refuses overlapping sample ids, and `m` imputations are by definition the same samples, so
the records cannot be bound. And `batch_hash()` hashes the pheno id column alone, so all `m` runs
derive the **identical** `mc_batch_id` and the batch axis cannot tell them apart. Q1 flags the same
root problem for two cohorts sharing sample ids and proposes a tag folded into the hash. One
mechanism would serve both, so decide them together rather than inventing a second one here.

**Rubin's rules do not apply at the score level, and this is the part most likely to be got
wrong.** A score is deterministic given the betas, so it carries no standard error and there is no
within-imputation variance to combine. Pooling `$scores` is therefore a mean, and the
between-imputation spread is genuinely new information that the record has nowhere to put today.
Real pooling belongs at the analysis exits, `calc_accel()` and `score_associations()`, which fit
models and do have standard errors. `mice::pool()` already implements Rubin's rules over a list of
fits, so the question there is whether those exits can return something poolable rather than
whether to reimplement the arithmetic. A `mice` dependency would be `Suggests` and lands in A6.

**It interacts with the package's own fill, and the interaction depends on how complete the
imputations are.** Imputation lives in one place today: cohort mean for a partial NA on a present
probe, the vendored ref or a drop for a fully absent one. Matrices that arrive complete mean that
path never fires, which is the clean case. Matrices still carrying NAs mean both mechanisms fire,
and `score_imputed_partial` then differs across the `m` runs, so the coverage record stops being
constant and has to be reported per imputation rather than once.

**Decide the pooling question before the container question.** Whether this is a list of
`mc_result`s plus a pooling function, or a new class, follows from what actually has to be carried,
and that is not known until the paragraph above is settled. Do not mint a container first.

### B9. One README pass, once the new surface exists

`README.Rmd` has fallen behind what the package does. Four gaps, one of them already shipped and
three of them pending other items.

- **`summary()` is missing**, and it shipped 2026-08-09. The "Check the coverage" section walks
  `clocks_coverage()` and `samples_coverage()` and stops there, so the QC digest that ties them
  together is invisible to anyone who only reads the README. This one is stale **now** and does not
  wait for anything.
- **No Code of Conduct or Contributing pointer**, though both files exist under `.github/`. Standard
  for a public repo, and the CoC link matters more than usual here because A7 is unfinished: the
  document is only useful to someone who can find it.
- **Only the `clocks` article is linked.** B5 adds a FAQ and a license article, and both want a line
  here when they land.
- **B4 and B7 add `report_mc_result()` and `write_mc_results()`**, which need a section rather than
  a mention, since the whole point of them is producing an artifact a reader can look at.

**Do this in one pass with A5**, which restores the CRAN install block at submission. Both edit the
same file, and the second render overwrites the first. The old A7 carried that warning and it moved
here when A7 was cut back.

Mechanics that bite: `README.Rmd` is the source and `README.md` is generated, so the pass ends with
`devtools::build_readme()`, which needs pandoc on both `RSTUDIO_PANDOC` and `PATH`. Chunks evaluate
at knit time under `set.seed(1)`, and the missingness example depends on `remove = 10` plus a
20-cell `sample.int()` draw, so touching either moves printed output that the prose does not quote.

**This is one pass, not a standing chore.** Three of the four gaps are waiting on B4, B5 and B7, so
doing it now means doing it again twice. The exception is `summary()`, which could ride along with
any smaller change that is already touching the file.

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

### Q5. A karyotype label on a partial chrY panel. NEXT

Q4 is chrY absent, which fails honestly: the clock is refused and every call is `NA`. This is chrY
**present but truncated**, which fails confidently. Hit on real data 2026-08-17, on a 694 sample
sesame matrix of 896261 probes:

| panel | present | share |
| --- | --- | --- |
| `DNAmSex_Wang_ChrX` | 3632 of 4047 | 0.8975 |
| `DNAmSex_Wang_ChrY` | 164 of 284 | 0.5775 |

At the default floors the column gate refused chrY and all 694 calls were `NA`, which is correct.
With both floors lowered to 0.5 so it would score, the result was:

- 304 of 304 recorded females called `47,XXY`
- 343 of 343 recorded males called `Male`
- nobody called `Female`, and the 47 samples with no recorded sex split 22 / 25 the same way

So **discrimination is perfect and calibration is gone**. 47% of a cohort called Klinefelter, against
a real prevalence near 1 in 500 to 1 in 1000 male births. `score_DNAmSex_Wang()` is a projection,
`obs %*% rotation[present]`, so absent probes drop their loadings and the score moves against a
threshold that was set on a complete panel. The rule table then reads a shifted female score as
X-high with Y-present.

The uncomfortable part is not this cohort, which the defaults already refused. It is that
`min_clocks_coverage` is **a coverage gate, not a calibration gate**, and nobody has measured where
those two part company. A cohort at 0.80 chrY clears the default floor and gets labels with no
warning at all. The first task here is therefore a measurement, not a design: take a cohort with a
complete Wang chrY panel, down-sample it, and find the coverage at which calls start to move. That
curve decides everything below.

Three candidate remedies, cheapest first.

1. **Gate the vocabulary on panel completeness.** Below the bar the two scores still separate sex, so
   emit the binary call and say the karyotype labels are unavailable. Precedent is exact:
   `norm_gate()` declines a scheme whose background panel cannot support it rather than normalizing
   badly, and this is the same shape one level up. Per sample, no model, no new dependency, and it
   needs the measurement above to site the bar.
2. **A cohort mixture as an ad hoc check**, fitting 2, 3 and 4 components and comparing by BIC, so a
   rule table emitting three labels where the data supports two says so. Two objections carry over
   from Q4 finding 2 and neither is answered by moving from call to check: it cannot work on a
   single sex cohort, and it cannot score `n = 1`. It does dodge the cluster labelling problem,
   since it compares counts rather than naming groups. Note `fit_mixture()` already exists in
   `R/normalize_bmiq.R`, so this need not mean a new dependency.
3. **A prevalence warning.** Aneuploid calls above some share of a cohort are not a finding. Catches
   exactly what happened here, costs almost nothing, and says nothing about a single sample.

One package constraint binds 2 and 3. A cohort derived verdict is cross-sample, so if it ever
changes a **score** it has to route through `cross_sample_at`, `pending` and `refinalize_clocks()`,
with the batch semantics that implies. A warning carries no such obligation. That asymmetry argues
for shipping the check as a warning before considering it as part of the call.
