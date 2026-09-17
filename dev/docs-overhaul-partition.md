# Partition (stage 2)

Proposal for approval. Nothing under `.claude/` has been written yet. Deleted with the plan in
stage 9. Row numbers refer to the first-line column of `dev/docs-overhaul-audit.md`.

## Three principles

1. **A rule lives in exactly one rules file.** No restating, which is what the audit found twelve
   cases of.
2. **That file's globs name every source file where an edit could break the rule**, so the rule
   loads itself. Overlap between areas is how a cross-file rule works, not a defect.
3. **Overlap is preferred to moving a rule.** The docs are oriented to code review, where a
   reviewer on a seam file should hold both sides' rules. A rule moves only where a wildcard
   glob does a better job than a list: the producer half of a rule that binds every scoring
   branch sits in engine, whose `R/score_*.R` covers a branch nobody has written yet.

The audit assigned blocks by concept. This pass assigns them by where the violating edit would be
typed, which moved ten blocks (listed below) and answered both open questions from stage 1:
front-door is a real area once it is assigned by file, and testing splits in two.

## Glob syntax, checked against the docs

`paths:` is a YAML list. `*`, `**` and brace expansion are documented. Negation is not, so a glob
cannot exclude a file. Whether every matching rules file loads when several match is not
documented either; the stage 3 canary can answer it on a file that matches two areas.

## Areas

Sizes are the audit's keep estimates re-summed by area. Estimates, not measurements.

| Area | `paths:` | Holds (audit rows) | Est. |
|---|---|---|---|
| front-door | `R/calc_clocks.R`, `R/resolve_inputs.R`, `R/validate_inputs.R`, `R/missingness.R`, `R/coverage_gates.R`, `R/score_cohort.R` | 489 token arguments, 573 two floors, 564 gates span one set, 175 (sweep half, plus the full-panel line), 439 pheno shape, the `split_moments()` half of 250 | 3.1k |
| engine | `R/score_*.R`, `R/resolve_inputs.R` | 119 routing total, 123 branch returns its score, 616 never score an uncounted CpG, 786 external is not pack-scored, 450 positions axis, 544 (the `clock_reads_cpgs()` half), 258 (the producer half: a branch passes a token, never a phrase), 1083 (the score-branch message split) | 3.9k |
| norm-kernels | `R/normalize_*.R`, `R/score_normalized.R`, `R/score_Dunedin.R`, `src/**`, `R/RcppExports.R` | 44, 58, 70 normalization and BMIQ, 586 BMIQ fails the sample, 690 rebuild, 694 kernel bounds and `SEXP` | 2.6k |
| record | `R/mc_result.R`, `R/bind.R`, `R/calc_accel.R`, `R/score_associations.R`, `R/coverage_report.R` | 156, 165, 175 (never total across batches), 184, 193, 325, 338, 344, 355, 367, 388 | 5.8k |
| coverage | `R/coverage.R`, `R/coverage_report.R`, `R/gap_reasons.R`, `R/constants.R`, `R/score_cohort.R`, `R/predict_sex.R`, `R/summary.R` | 129, 134, 142, 147, 201, 237, 250, 258, 303, 308, 544 (the no-record half), 599, 609 | 5.4k |
| print-summary | `R/print.R`, `R/summary.R` | 217, 225, 270, 286, 295, 392, 401, 423, 430, 433 | 4.6k |
| predict-sex | `R/predict_sex.R` | 209, 760 | 0.9k |
| catalog | `R/accessors.R`, `R/list_clocks.R`, `R/clock_cpgs.R`, `R/tags.R`, `R/codebook.R`, `R/cite_clocks.R`, `R/score_routed.R` | 318, 533, 624, 631, 650 | 2.5k |
| assets | `R/mc_data.R`, `R/score_pack.R` | 778, 797, 811, 828, 835, 839 | 3.2k |
| sync | `data-raw/**` | 708 to 766, 848, the sync half of 58 and of 631 | 3.4k |
| testing | `tests/**` | 850 to 902, 1021 to 1057, 1068 | 6.0k |
| parity | `tests/testthat/test-fixtures-parity.R`, `R/dev-utils.R` | 916 to 1010 except 923, plus 1062 | 5.1k |

**Low-level files, matched by no rules file:** `R/utils.R`, `R/mc-params.R`,
`R/methylCIPHERv2-package.R`, `R/sim_DNAm.R`. They hold no high-level logic, so the core rules are
all that bind them, and they come last in any review. `R/sim_DNAm.R` sits here on the
maintainer's ruling: it generates a matrix and decides nothing. The list is written into the
core, and the stage 5 check reads it: a file must match a glob or be on the list.

Checked mechanically: all 53 files (48 under `R/`, 5 under `src/`) match an area or are on the list.

## Overlaps, each one deliberate

| File | Areas | Why |
|---|---|---|
| `R/score_cohort.R` | front-door, engine, coverage | The hub, and the heaviest load in the tree at about 12k. `mc_cohort()` runs the gates in the order rule 573 depends on, `score_cohort()` is the engine, and it calls `compute_coverage()` and owns the `mc_note_*` collectors. |
| `R/predict_sex.R` | predict-sex, coverage | Rule 201 is broken by an edit typed here: calling the export where the frame is wanted. |
| `R/summary.R` | print-summary, coverage | The digest counts the note tokens coverage defines. |
| `R/resolve_inputs.R` | front-door, engine | `resolve_clocks()` is the token front door; `resolve_cpgs()` is where the positions axis starts. |
| `R/coverage_report.R` | record, coverage | Holds both coverage frames and a `finalized()` call site. About 11k. |
| `R/score_normalized.R`, `R/score_Dunedin.R` | engine, norm-kernels | A scoring branch that normalizes. |
| `R/score_pack.R` | engine, assets | Scores from a pack. |
| `R/score_routed.R` | engine, catalog | `drop_routed_members()` is one of the five things that derive from `routed_members()`. |
| `R/score_associations.R` | engine, record | **A false match.** It is an exit, caught by `R/score_*.R` on its name alone. Engine opens with a line saying so. Listing the branch files by hand would fix it, and would rot the first time a branch is added. |

Every other file loads one area. The parity file loads testing and parity, about 11k, which is
right: it needs the altitude rules too.

## Blocks that moved since the audit

| Row | Was | Now | Reason |
|---|---|---|---|
| 439 pheno shape | record | front-door | `resolve_pheno()` is the one exit that enforces it |
| 564 gates span one set | coverage | front-door | The edit that breaks it is in `R/coverage_gates.R` |
| 175 sweep | record | split | Building it is front-door; "never total across batches" is record |
| 544 only what was counted | coverage | split | `clock_reads_cpgs()` sits in `R/score_cohort.R`; the no-record rows are coverage |
| 258 note tokens | coverage | split | The producer side binds every branch that records a failure |
| 250 `not_finite` | coverage | split | The divisor guard is in `R/missingness.R` |
| 193 verb is a method | exits-print | record | It is about the record's surface |
| 318 `cite_clocks` generic | exits-print | catalog | Lives with `R/cite_clocks.R` and `R/codebook.R` |
| 209, 760 | exits-print, sync | predict-sex | One small file beats loading record to read `R/predict_sex.R` |
| 1062 parity in one file | testing | parity | - |

A split row is two different rules that shared a paragraph, not one rule stated twice. Each half
cites the same rationale slug.

## What stays in the core

- What the package is, and getting started.
- Workflow bans: check is on demand, parity is never run unprompted, `devtools::test()` is how a
  change is verified, no network at build or check, commit and PR bodies carry the rationale.
- Architecture in one line each: one beta reader, one engine with a closed branch set, accessors
  are the schema and never search, imputation in one place, scores only, the result is an S3
  record over `list`, no commit SHA as provenance, double precision.
- Code rules: never `$`, never a partial match, never `<<-`, `checkmate` at the surface and bare
  `stop()` inside, the cli audience line, `say_*` against `mc_note_*`, short comments.
- One-liners that must reach a file no area owns: `$provenance` is never named to a user, every
  `print.mc_*` reuses the builders in `R/print.R`, correlation is never a numeric gate.
- Docs and deps: read `dev/WRITING.md` first, `NAMESPACE` and `man/` are generated, both lints
  empty, `DESCRIPTION` declares for code and not for tests, `LinkingTo` is Rcpp alone.
- About these docs: what a rules file is, what `(why: slug)` means, the index, the core-only
  list, no design doc, no tracked `.Rprofile`, where this file lives and why, ASCII.
- **The numbers rule, new.** A rule names the declaration it reads and never a count. Any number
  the code, the catalog or a test run can produce on demand stays out of every loaded file and
  out of the rationale file. A dated measurement that decided something (a timing, a residual, a
  bit-flip count) is evidence and lives in the rationale file only.

## Draft spine

Read off `calc_clocks()` and `mc_cohort()` today. Re-checked when it is written into the core.

```
calc_clocks()                         R/calc_clocks.R
  mc_spec()                           R/score_cohort.R      clocks, normalize, ext_data -> spec
  canonicalize_covariates()           R/validate_inputs.R
  mc_cohort()                         R/score_cohort.R      -> facts
    check_DNAm(), check_pheno(), resolve_pheno()            R/validate_inputs.R
    scan_missing_cpgs()               R/missingness.R       the one sweep; usable_cols, input
    norm_gate()                       R/coverage_gates.R    before resolve_cpgs(), always
    resolve_cpgs()                    R/resolve_inputs.R    panels become positions
    check_coverage()                  R/coverage_gates.R    the column gate
  score_cohort()                      R/score_cohort.R      -> scores, pending, coverage, notes
    mc_block(), compute_coverage(), row_gate(), score_type() -> linear_score() or a branch
  finalize_cross_sample()             R/score_cohort.R
  check_row_coverage(), check_score_values()
  construct_mc_result()               R/mc_result.R         -> mc_result
```

## Seams

The spine says what runs in what order. A seam is a contract that crosses files, and it is where
a bug that returns a number lives. Seven, each a chain read off the code today. They go in the
core under the spine, one line each, so every agent and every reviewer holds them without being
told. This is the "main veins" map the overhaul started from; the globs could not express it.

```
positions      resolve_cpgs() -> mc_block() -> block_cols(), component_present() -> linear_score(), branches
counted        compute_coverage(), clock_reads_cpgs() <-> what a branch scores (component_present())
normalization  resolve_normalize() -> norm_gate() -> resolve_cpgs() -> score_normalized(), bmiq_fit()
               -> provenance normalized, normalize_requested -> gate_same_normalized()
pending        score_cohort() -> finalize_cross_sample() -> construct_mc_result() -> rbind, reduce_pending(),
               refinalize_clocks() -> finalized() -> the five exits
notes          mc_note_scoring_failure(), mc_note_partial_calibration() -> merge_notes() -> bind_by_key()
               -> gap_reasons() -> attach_notes() -> summary(), predict_sex()
batch          batch_hash(), construct_mc_result() -> the rbind gates -> is_multi_batch(), n_batches() -> the four frames
packs          mc_spec(), pack_groups_needed() -> load_mc_assets(), mc_read_pack() -> clock_coefs(id, packs)
               -> score_pack_group()
```

## Review passes

The rules file is the loading unit. It is not the review unit, and it does not need to be.

A reviewer is an agent with tools: the target says what is being judged, not what may be read.
As it follows a call into another file, that file's rules load with it. So small rules files do
not starve a review of context, and merging them would only make every ordinary edit load more.
What a review gains from grouping is **order** and **seams**, and both come from the data flow:

- Upstream before downstream, so each pass can trust what the last one established.
- One or two areas per pass, sized near two thousand lines of code, so the judging stays sharp.
- Each pass also traces the seams that end in it, because a seam is only checked by a reviewer
  looking at both of its sides.

| Pass | Areas | Code lines | Seams traced |
|---|---|---|---|
| 1 | norm-kernels | 2.7k | - (self-contained: memory safety, the vendored BMIQ) |
| 2 | catalog | 1.2k | - (so later passes can trust the accessors) |
| 3 | front-door | 2.0k | normalization, first half |
| 4 | engine | 2.3k | positions, counted, packs |
| 5 | record, coverage | 2.2k | pending, notes, batch, normalization second half |
| 6 | print-summary, predict-sex | 0.9k | notes, tail end |
| 7 | assets, low-level files | 1.2k | packs, the download side |
| 8 | sync | 3.1k | tier 1; run it next to pass 2, since the accessors read what sync builds |
| 9 | testing, parity | - | optional; test quality, not package correctness |

`R/score_cohort.R` is judged twice on purpose, in pass 3 for `mc_spec()` and `mc_cohort()` and in
pass 4 for `mc_block()` and `score_cohort()`. Pass 5 carries the two largest rule areas, so it is the one to split, into
record then coverage, if its findings come back shallow.

### Tiers (approved 2026-09-17)

The passes are not equally urgent, and their fixes land as separate PRs, one per pass.

| Tier | Passes | Test | Standing |
|---|---|---|---|
| 1 | 1 norm-kernels, 2 catalog, 8 sync, 3 front-door, 4 engine, 5 record and coverage | A bug here returns a wrong number with no error | The gate. Fix PRs from these also need a parity run. |
| 2 | 6 print-summary and predict-sex, 7 assets | A bug here is visible: a wrong table, a failed download | After tier 1, in any order |
| 3 | low-level files, `R/sim_DNAm.R`, README and vignettes, 9 tests | Nothing downstream trusts it | Whenever |

Sync is tier 1 on the maintainer's ruling: it builds the catalog, the registries and the packs,
so it sets the structure every other core area reads. A defect there is a wrong number in every
clock it touches, shipped as data. It is maintainer-side and not under test, which is a reason to
review it, not a reason to defer it.

**The gate is per area, not global.** A feature waits for the pass over the areas it touches, and
for nothing else. Two reasons: a review of code that is about to change is wasted, and a fix PR
and a feature PR in the same file conflict. So the `pheno` change, which touches front-door and
record, goes *before* passes 3 and 5 rather than after them, and passes 1, 2 and 4 can run while
it is being written.

Two things the stage 3 canary decides. Whether a target can be several paths: if not, a pass is
one run per file, in the order above. And whether scoped rules load inside the reviewer: if not,
each pass names its rules files by hand, which the core index already tells it to do.

## Order for stage 3

Smallest and most self-contained first, the big bullet's three areas last, the core at the end.

1. predict-sex. The canary runs here: its rules will exist nowhere else, and the file matches
   one area, so the result is unambiguous.
2. norm-kernels, 3. catalog, 4. assets, 5. sync, 6. front-door, 7. engine. A second canary on
   `R/score_cohort.R` after step 7 answers whether two matching areas both load.
8. parity, 9. testing, 10. print-summary, 11. coverage, 12. record, 13. the core.

## Decisions recorded from stage 1

- Finding 6: single hyphens in the rules files and the rationale file. The ASCII section narrows
  to say `--` is required in package sources only.
- Finding 7: `codebook()` is settled. Rows 193 and 318 are rewritten to include it, and the
  "unbuilt" sentence goes.
- Finding 8: the full-panel behavior is a line under the sweep rule, in front-door.
- Finding 15: `dev/to-do.md` becomes a one-sentence pointer to a maintainer-local file.
- Counts: the numbers rule above, wider than the audit proposed.
- The verdicts are approved.
