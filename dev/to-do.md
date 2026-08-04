# To-do

Queued work. **This is a staging area, not a record.** An item that becomes a design commitment
gets a dated `dev/DECISIONS.md` entry when it lands, and an item that becomes a rule moves to
`CLAUDE.md`. Delete an item when it ships; do not leave a done list behind.

There is no open code defect. Everything below is licensing, release plumbing, prose, or deferred.

---

## Before public alpha

### A1. Clock weight licensing

The catalog carries a `license` field for every clock, populated for all 137. The package declares
`BSD_3_clause + file LICENSE` with Yale University as copyright holder, and the bundled
coefficients have to be compatible with that.

Current distribution:

| Declared terms | Clocks | Redistributable as declared |
| --- | --- | --- |
| open-redistributable | 31 | yes |
| MIT | 3 | yes |
| CC BY, CC BY 2.0, CC BY 4.0 | 5 | yes, with attribution |
| GPL-2, GPL-2+, GPL-3, GPL-3 / CC-BY-4.0 | 10 | review, copyleft against BSD-3 |
| journal-supp | 33 | review, terms vary by journal |
| public-github-unspecified | 26 | no, code with no license grants no rights |
| unspecified | 15 | unknown |
| non-commercial | 12 | no |
| CC BY-NC-ND 4.0 | 1 | no |
| research-use-only | 1 | no |

39 of 137 are clear as declared. Decide per bucket: ship, ship with an attribution file, move behind
the external asset split, or drop. Where the field is `unspecified` or `public-github-unspecified`
the upstream terms have to be established before the bucket can be decided.

`LICENSE`, `LICENSE.md` and the `^LICENSE\.md$` line in `.Rbuildignore` are already in the shape
CRAN expects. This item is the coefficients, not the package license.

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

### A4. README, at submission

Restore the CRAN install block, deliberately absent while the package is not on CRAN. The three
counts quoted in the coverage prose follow the seed and the `remove = 100` argument, so a change to
either has to be carried into the sentences.

---

## Open questions

### Q1. `collapse` as a dependency

Not for speed. For correctness: the package performs several id-keyed left joins by hand, each one
a `match()` plus a duplicate-id guard plus a no-matching-row warning, in `merge_accel_data()` and
`calc_accel()` ([R/calc_accel.R](R/calc_accel.R)), `resolve_pheno()`
([R/validate_inputs.R](R/validate_inputs.R)) and `attach_recorded()`
([R/predict_sex.R](R/predict_sex.R)). Each re-derives the same three checks, and they are correct
today only because the checks upstream of them line up. One join verb with explicit join-type
semantics and a built-in account of unmatched and many-to-many rows would make that guarantee
uniform. The same argument covers the set operations over large character vectors in
`missingness.R` and `clock_cpgs.R`.

To settle before it lands, since this is a new hard dependency carrying compiled code:

- what it buys, measured at the sites above, against one small internal `left_join_by_id()` that
  centralizes the same three checks with no new dependency;
- whether its join diagnostics are the ones to raise, or whether it would be wrapped anyway to get
  the package's own;
- install weight and CRAN submission surface, given `Rcpp` is already present.

### Q2. Chunked front end. PARKED

Every piece exists: batch-wise fill regimes, derived batch labels, `rbind`, retained `pending`,
`refinalize_clocks()`. Parked because the usage does not yet justify the front-end surface.

The alternative works today: score each cohort separately, save each `mc_result`, and `rbind` once
at the end. One wrinkle, worth deciding rather than leaving to chance: two cohorts with the same
sample ids hash to the same `mc_batch_id`. A cohort tag carried on `pheno` and folded into the hash
would separate them. This interacts with `rbind` gate 1, where overlapping ids throw, so the tag has
to be decided together with what "the same sample" means across cohorts.

---

## Housekeeping

- `dev/pr3-triage.md` says `clocks_accel()` in its header and in sections 4.4 and 5.4. The function
  is `calc_accel()`.
- PR #3 response (`dev/PR3-respond.md`): the four agreed edits landed 2026-08-03. Posting the
  response and closing the PR are manual steps and are held. One open point: section 3.8 declines
  per-clock score summary statistics outright, which is a one-paragraph change if it should stay an
  open question instead.
- `build_clock_reference.R` calls `sex_coef` "male vs female"; the estimated level is female.
  Comment only, the numbers are correct.
