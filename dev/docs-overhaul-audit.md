# CLAUDE.md audit (stage 1)

Read-only. Audited `.claude/CLAUDE.md` at commit `343046b`: 1237 lines, 106943 chars. Nothing in
the file was changed. This table is the proposal; stage 3 acts on it only after the verdicts are
approved. Deleted with the plan in stage 9.

## How to read the table

- **lines**: first line of the block. A block runs to the next row.
- **size**: chars in the block today.
- **kind**: what the block is made of, largest part first.
  R rule, G guard ("do not simplify X back"), W one-clause reason, E evidence or measurement,
  H history or tombstone, S snapshot (a count a sync or a new test moves), B description of shipped
  behavior the code already states, F workflow, M text about the docs themselves.
- **chk**: could a reviewer test the rule against a diff. y, part, n.
- **ver**: every function, constant and file the block names was checked against the tree.
  ok, STALE (see Findings), snap (holds a number I could not cheaply verify), n/a.
- **verdict**: keep (as is or nearly), compress (rule stays, the rest moves or goes), rewrite
  (wrong or contradicted today), delete.
- **dest**: where the kept part lives. Draft areas, fixed in stage 2: core, front-door, engine,
  norm-kernels, record-bind, coverage, exits-print, catalog, assets, sync, testing.
- **keep**: my estimate of the chars that stay in a loaded file. The rest goes to the rationale
  entry named in the last column, or nowhere. An estimate, not a measurement.
- **slug**: the proposed `dev/RATIONALE.md` heading that receives the evidence and history. `-`
  means nothing worth moving.

## Summary

Computed from the rows below, by primary destination. "Today" is measured; "keep" is the sum of
my per-block estimates.

| Destination | Blocks | Today | Keep est. |
|---|---|---|---|
| core | 33 | 24.9k | 10.7k |
| front-door | 2 | 3.1k | 1.4k |
| engine | 5 | 4.1k | 3.0k |
| norm-kernels | 6 | 6.1k | 2.6k |
| record-bind | 11 | 10.4k | 6.1k |
| coverage | 14 | 11.7k | 6.3k |
| exits-print | 13 | 11.0k | 5.8k |
| catalog | 5 | 4.7k | 2.7k |
| assets | 6 | 5.3k | 3.2k |
| sync | 8 | 5.4k | 3.0k |
| testing | 31 | 18.9k | 11.1k |
| deleted outright | 1 | 0.1k | 0 |
| **total** | **135** | **105.7k** | **55.9k** |

The 135 blocks cover 105.7k of the file's 106.9k chars; the remainder is section headings.
Verdicts: 35 keep, 90 compress, 9 rewrite, 1 delete. Verification: 100 ok, 19 snap, 16 STALE.

- **Always loaded today: 107k chars, about 27k tokens.**
- **Always loaded after: about 10.7k chars**, plus the spine and the index of rules files, so
  call it 12.5k chars, about 3k tokens. At this file's line length that is 170 to 200 lines,
  which is near the documented target.
- **Loaded on touch:** the largest area is testing at 11.1k, then coverage at 6.3k and
  record-bind at 6.1k. Reading `R/summary.R` loads exits-print at 5.8k; following the index to
  coverage as well makes about 12k.
- **About 50k chars leave loaded files altogether.** My estimate is that some 35k is evidence
  and history that moves to the rationale file, and some 15k is deleted: snapshots, duplicates,
  and descriptions of what the code already says. That split is not computed.

Two things the numbers say about the partition, for stage 2. Front-door is the primary home of
only two blocks but a secondary reader of five (positions axis, pheno shape, `ext_data`, the
full-panel rule, the floors), so it either merges with engine or is accepted as a small file
that mostly points elsewhere. And testing is as large as the new core, so it may want splitting
into the always-on tiers and the parity tier, which have different readers.

The core forecast is the soft one. It assumes the cross-cutting rules compress as hard as I
estimate, and it is the number to re-measure after the first area lands.

## Findings

Things wrong today, independent of the restructure. Each needs a fix in stage 3 whatever the
verdict on its block.

**Contradictions inside the file**

1. Three places tell the reader to write a `dev/DECISIONS.md` entry (line 86, line 1137, lines
   1206-1207). Lines 1171-1175 forbid creating that file.
2. The header (lines 4-5) says volatile detail lives in `dev/` and to prefer it for specifics.
   Lines 1196-1207 say there is no such doc and that is deliberate.
3. The header (lines 7-8) says the file does not restate the evidence. It does, throughout.
4. The suite trim is quoted as 1284 to 799 (line 869) and as 1284 to 801 (line 1026).
5. Line 252 says the four `sample_scale` clocks "report `fit`". Line 258 says `fit` was split the
   same day; the live token is `fit_spread`.
6. The ASCII section requires `--`. The maintainer's standing preference is single hyphens only in
   anything they read. The plan and this file follow the preference. Rules files and the
   rationale file are read by the maintainer, so this needs a ruling before stage 3.

**Stale against the tree**

7. Lines 322-324 say `codebook()` is "decided but unbuilt" and must not be built. It is built and
   exported: `R/codebook.R`, three S3 methods, `test-codebook.R`. Lines 193-194 say the built
   surface is "exactly" six verbs and omit it. Line 735 already speaks of `mc_codebook` as
   shipped. Needs the maintainer's word on whether the `description` field is now verified.
8. Lines 982-987 name `needs_full_panel()` as a parity helper. It is `clock_needs_full_panel()`
   in `R/accessors.R`, and `R/` now reads it: `say_full_panel_clocks()` in `R/validate_inputs.R`
   tells the user, and `R/score_cohort.R` branches on it. CLAUDE.md never mentions that front-door
   behavior. It may also qualify the claim at lines 181-182 that the sweep reads the requested
   panels alone. Worth a look before the text is rewritten.
9. Line 1098, in the CLI section, names `note_scoring_failure()`. The function is `mc_note_scoring_failure()`.
10. Line 677 says "all 28 user-facing topics". `man/` holds 32 `.Rd` files.
11. Lines 372-373 list `samples_coverage()` as a `finalized()` call site. The call sits in
    `sample_coverage_rows()`, which lines 201-208 correctly describe. The five-site count holds.
12. `dev/to-do.md` does not exist on this machine (`dev/next-step.md` does). The file cites its
    ids Q4 (line 212), B5 (line 1163), A1 and Q4 (line 1193). Nobody can follow them today.

**Shape defects**

13. Lines 148-149 read "`$per_clock`, `$per_clock` and `$sample_miss` span one set". One of the
    first two is a typo, probably for the gates.
14. Lines 303-307 and 318-324 are continuation paragraphs stranded after nested bullets. Each
    reads as part of the wrong parent.
15. Lines 1182-1194 explain why `dev/to-do.md` was untracked by describing, in a public file,
    the two topics that were judged not ready to be public. Flagged for the maintainer; my
    proposal is one sentence that says the file is maintainer-local and its ids do not resolve.

**Counts that will drift.** Beyond the test snapshots, the rule text carries catalog counts that
the next sync moves: "7 sex-routed aliases", "14 members", "the two `DNAmPhysAge` clocks", "four
`sample_scale` clocks", "two `Zhang2019` arms", the clock list at lines 551-553, "150 / 47 / 3",
"nine tokens", "five values". Proposal: a rule names the declaration it reads, never the count.

**Rules stated more than once**

| Rule | Places |
|---|---|
| check is on demand | 33, 88, 1215 |
| parity deps undeclared, parity file not shipped | 35, 902 |
| `compile_dll` after a `.cpp` edit | 27, 690 |
| `$provenance` is internal | 158, 395, 1052 |
| read `dev/WRITING.md` first | 667, 1107 |
| both lints must be empty | 679, 1129 |
| assert that a message errors, not its wording | 1037, 1127 |
| `document()` owns `NAMESPACE` and `man/` | 29, 674, 681, 1215 |
| ASCII | 1072, 1219 |
| neither floor aborts | 108, 171 |
| `not_finite` excludes a plain `NA` | 244, 311 |
| score-routed members are never masked | 556, 643 |

**Verified and fine.** 198 backticked function names checked: every one is defined in the tree,
is a base or third-party function, or is named by the file itself as retired. All 21 package constants
resolve. Every function-to-file claim I tested holds (28 of 28). `DESCRIPTION` matches the
dependency text. `.Rbuildignore` matches. `META_REMOTE`, `PARITY_ABS_TOL`, `PARITY_REL_TOL`,
`MC_SUGGEST_CAP` and the nine `MC_NOTES` tokens match. No tracked `.Rprofile`.

## The table

### Header and getting started

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 1 | 500 | M | n | STALE | rewrite | core | 300 | findings 2, 3. New header says what the core is, what the rules files are, what a `(why: slug)` is |
| 10 | 355 | B | n | ok | keep | core | 350 | - |
| 17 | 736 | F | n | ok | keep | core | 700 | - |
| 33 | 877 | R H | y | ok | compress | core | 250 | deps-for-code-not-tests. Duplicate of 902; one home |
| 44 | 1249 | R H E | y | ok | compress | norm-kernels | 400 | normalization-vendored. One line in core: `LinkingTo` is Rcpp alone, no `Remotes:` |
| 58 | 977 | R G E H | part | ok | compress | norm-kernels | 300 | bmiq-no-rng. The `nfit = length(gold)` half also goes in sync |
| 70 | 1151 | R B E H | part | snap | compress | norm-kernels | 300 | bmiq-gold-as-fit |

### Invariants: workflow, engine, coverage record

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 84 | 103 | M | n | STALE | rewrite | core | 100 | finding 1 |
| 88 | 1023 | R F E H | n | snap | compress | core | 350 | check-on-demand. Keep the ban, "say check was not run", and the pandoc and LaTeX requirements |
| 99 | 1456 | R G W H | y | ok | compress | core | 500 | one-beta-reader. Keep who may take `DNAm` and what a second reader is |
| 115 | 320 | R | y | ok | keep | core | 320 | - |
| 119 | 382 | R | y | ok | keep | engine | 330 | routing-total |
| 123 | 575 | R | y | ok | keep | engine | 480 | cross-sample-pending. "today the two clocks" goes |
| 129 | 441 | R B | part | ok | compress | coverage | 300 | coverage-batch-axis |
| 134 | 728 | R B | part | ok | compress | coverage | 520 | - |
| 142 | 429 | R G | y | ok | keep | coverage | 380 | - |
| 147 | 755 | R H | part | STALE | rewrite | coverage | 450 | coverage-one-span. Finding 13 |

### Invariants: the result record

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 156 | 788 | R W | y | ok | compress | record-bind | 350 | provenance-internal. One line in core, since it binds every cli message. Duplicates at 395 and 1052 go |
| 165 | 961 | R W H | part | ok | compress | record-bind | 520 | floors-per-batch |
| 175 | 801 | R G B | part | ok | compress | record-bind | 380 | input-sweep-per-batch. Field list goes; "never total across batches" stays. Finding 8 |
| 184 | 830 | R G H | y | ok | compress | record-bind | 450 | normalize-two-facts |
| 193 | 745 | R H | y | STALE | rewrite | exits-print | 400 | no-third-coverage-frame. Finding 7. `score_gaps()` tombstone moves |
| 201 | 695 | R G H | y | ok | compress | coverage | 360 | frame-vs-warning |
| 209 | 760 | R W S | y | snap | compress | exits-print | 380 | predict-sex-columns. Panel sizes and the Q4 citation go |
| 217 | 776 | R G | y | ok | keep | exits-print | 560 | summary-counts-notes |
| 225 | 1064 | R G H | part | ok | compress | exits-print | 560 | summary-counts-notes (same entry) |
| 237 | 1280 | R H S | y | ok | compress | coverage | 560 | note-is-step-verdict. Keep: closed enum, the failure filter, the cell set |
| 250 | 715 | R G H | part | STALE | compress | coverage | 350 | not-finite-backstop. Finding 5 |
| 258 | 1134 | R W H S | y | ok | compress | coverage | 520 | note-tokens-closed |
| 270 | 1518 | R G E H | y | snap | compress | exits-print | 620 | note-legend. The width measurements move |
| 286 | 789 | R E | y | ok | compress | exits-print | 400 | digest-sort-order |
| 295 | 711 | R H E | y | ok | compress | exits-print | 320 | batch-label-display |
| 303 | 374 | H B | n | ok | compress | coverage | 150 | partial-is-a-note. Finding 14. Folds into the 237 block |
| 308 | 934 | G W | y | ok | compress | coverage | 560 | no-blind-na-label. The strongest guard in the file; trim lightly. Absorbs the duplicate at 244 |
| 318 | 552 | R H | part | STALE | rewrite | catalog | 250 | cite-clocks-generic. Findings 7, 14 |
| 325 | 1159 | R G W | y | ok | compress | record-bind | 680 | batch-column-conditional |
| 338 | 502 | R W | y | ok | keep | record-bind | 380 | mc-batch-id-name |
| 344 | 1047 | R G H | y | ok | compress | record-bind | 720 | batch-label-derived. `is_auto_label()` tombstone moves |
| 355 | 1154 | R G W | y | ok | keep | record-bind | 880 | rbind-never-reconciles. Most checkable rule in the file |
| 367 | 1873 | R G H | y | STALE | compress | record-bind | 800 | finalizer-definition. The "one-clause form was wrong" story moves. Finding 11 |
| 388 | 387 | R | y | ok | keep | record-bind | 380 | - |
| 392 | 825 | R W | part | ok | compress | exits-print | 480 | print-grammar |
| 401 | 1817 | R G E H | part | ok | compress | exits-print | 760 | fmt-grid. Keep the four "must keep doing" rules, move the `kable` comparisons and the retired helpers |
| 423 | 623 | R W | y | ok | compress | exits-print | 450 | - |
| 430 | 233 | R | y | ok | keep | exits-print | 230 | - |
| 433 | 558 | R H | y | ok | compress | exits-print | 260 | digest-order |
| 439 | 879 | R W H | y | ok | compress | record-bind | 600 | pheno-shape. Also read by front-door (`resolve_pheno()`) |

### Invariants: cross-cutting code rules

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 448 | 187 | R | part | ok | keep | core | 187 | - |
| 450 | 1286 | R G E | y | snap | compress | engine | 880 | positions-axis. Silent wrong answer; trim lightly. Timing moves. Front-door reads it too |
| 464 | 174 | R | y | ok | keep | core | 174 | - |
| 466 | 965 | R W | y | ok | compress | core | 480 | no-dollar |
| 476 | 1204 | R W E | y | ok | compress | core | 380 | no-partial-match. `match.arg()` measurements move |
| 489 | 1947 | R G E S | y | snap | compress | front-door | 650 | token-args-bounded. 68.7 s, 300k, 150 / 47 / 3 all move or go |
| 510 | 752 | R W | y | ok | compress | core | 420 | - |
| 518 | 1363 | R G W | y | ok | compress | core | 720 | checkmate-at-surface |
| 533 | 1015 | R B | y | ok | compress | catalog | 620 | accessors-never-search. One line in core |

### Invariants: coverage and the callable pool

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 544 | 1760 | R G S | part | snap | compress | coverage | 820 | coverage-only-what-was-counted. The clock list at 551-553 goes |
| 564 | 820 | R G H S | y | snap | compress | coverage | 400 | gates-span-one-set |
| 573 | 1185 | R W | part | ok | compress | front-door | 760 | two-floors-two-panels |
| 586 | 1202 | R G H | y | ok | compress | norm-kernels | 560 | bmiq-fails-the-sample. Keep the re-vendor warning |
| 599 | 969 | R G H | part | ok | compress | coverage | 460 | row-gate-after-notes |
| 609 | 676 | R G E | y | snap | compress | coverage | 450 | na-coverage-row-drop |
| 616 | 755 | R G | y | ok | keep | engine | 620 | - |
| 624 | 662 | R | y | snap | keep | catalog | 560 | routed-members-hidden |
| 631 | 1769 | R W H | part | ok | compress | catalog | 820 | routed-members-hidden (same entry). Stopgap note stays, one sentence. Sync half goes to sync |
| 650 | 722 | R G H | y | ok | compress | catalog | 460 | routed-members-hidden (same entry) |

### Invariants: provenance, numeric gates, docs, kernels

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 658 | 87 | R | y | ok | keep | core | 87 | - |
| 659 | 83 | R | y | ok | keep | core | 83 | - |
| 660 | 623 | R W | y | ok | compress | core | 400 | no-correlation-gate |
| 667 | 622 | R W | n | ok | compress | core | 350 | - Merges with 1107 |
| 674 | 648 | H S R | part | STALE | compress | core | 150 | generated-namespace. Finding 10. Mostly history; merges into 681 |
| 681 | 827 | R G H | y | ok | compress | core | 450 | generated-namespace (same entry) |
| 690 | 306 | R | n | ok | keep | norm-kernels | 220 | - Also the code comment at line 27 |
| 694 | 1179 | R G W | y | ok | compress | norm-kernels | 820 | kernel-bounds-and-sexp |

### sync.R workflow

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 708 | 418 | F | n | ok | compress | sync | 300 | - One line stays in core: sync is maintainer-side, the catalog is committed |
| 715 | 533 | R H | y | ok | compress | sync | 220 | meta-remote |
| 721 | 229 | R | y | ok | keep | sync | 229 | - |
| 724 | 1146 | R W | y | ok | compress | sync | 460 | control-exemption |
| 737 | 294 | B | n | ok | keep | sync | 260 | - |
| 741 | 1647 | R G B H | y | ok | compress | sync | 720 | sync-registries |
| 760 | 572 | R G | y | ok | keep | exits-print | 420 | sync-registries (same entry). Lives with `R/predict_sex.R` |
| 766 | 1063 | F B | n | ok | compress | sync | 720 | - |
| 778 | 697 | R | y | ok | compress | assets | 500 | external-unit-is-clock |
| 786 | 1061 | R G | y | ok | compress | engine | 700 | external-vs-pack-scored |
| 797 | 1312 | R H W | y | ok | compress | assets | 620 | assets-dir-is-cache |
| 811 | 1578 | R G H | y | ok | compress | assets | 920 | assets-consent |
| 828 | 569 | R W | y | ok | keep | assets | 460 | ext-data-argument |
| 835 | 300 | R | y | ok | keep | assets | 290 | - |
| 839 | 843 | R G E | y | snap | compress | assets | 420 | pack-is-gz-rds. Bit-flip counts move; "a warning is an abort" stays |
| 848 | 88 | R | y | ok | keep | sync | 88 | - |

### Testing

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 850 | 163 | M | n | ok | keep | testing | 160 | - |
| 855 | 848 | R W | part | ok | compress | testing | 560 | smoke-tier-purpose |
| 864 | 470 | R H | n | ok | compress | testing | 260 | - |
| 869 | 802 | R S | n | STALE | compress | testing | 340 | cran-runs-a-fraction. Finding 4. Every count goes |
| 878 | 720 | R W | n | ok | compress | testing | 460 | cran-runs-a-fraction (same entry) |
| 886 | 462 | R S | y | snap | compress | testing | 250 | - |
| 891 | 921 | G H | part | ok | compress | testing | 560 | goldens-parity-cannot-see |
| 901 | 65 | H | n | ok | delete | - | 0 | Folds into 855 as the word "ungated" |
| 902 | 1184 | R E | y | ok | compress | testing | 520 | source-tree-tests-do-not-ship. Takes the duplicate from 33 |
| 916 | 670 | R F | n | ok | compress | testing | 500 | - |
| 923 | 388 | R | n | ok | keep | core | 260 | - Moves to core: "run the tests" is said anywhere, so the ban must always be loaded |
| 927 | 801 | R G E | y | snap | compress | testing | 420 | parity-gate-on-generator |
| 936 | 573 | R H | part | ok | compress | testing | 360 | - |
| 942 | 558 | R W | y | ok | keep | testing | 460 | parity-two-axes |
| 948 | 645 | R B | y | ok | compress | testing | 460 | - |
| 955 | 1098 | G E | y | snap | compress | testing | 420 | horvath-block-skipped. Keep "do not fix this with a tolerance" |
| 967 | 1329 | R E H | y | snap | compress | testing | 520 | horvath-normalized-block |
| 982 | 529 | R | part | STALE | rewrite | testing | 300 | full-panel-fixtures. Finding 8. The `R/` half needs a home in front-door |
| 988 | 686 | R W | y | snap | compress | testing | 460 | fixture-census |
| 995 | 1333 | S R | n | snap | compress | testing | 250 | - About 85% snapshot. Keep: read a run by fail and skip counts, fail is 0 or bust |
| 1010 | 901 | R G S | y | snap | compress | testing | 560 | known-parity-gaps |
| 1021 | 203 | R | n | ok | keep | testing | 200 | - |
| 1026 | 643 | R S | n | STALE | compress | testing | 420 | suite-budget. Finding 4 |
| 1033 | 352 | R | y | ok | compress | testing | 260 | - |
| 1037 | 185 | R | y | ok | keep | testing | 185 | - |
| 1039 | 438 | R W | y | ok | compress | testing | 260 | - |
| 1044 | 294 | R | y | ok | keep | testing | 290 | - |
| 1047 | 262 | R | y | ok | keep | testing | 260 | - |
| 1050 | 168 | R | n | ok | keep | testing | 168 | - |
| 1052 | 442 | R | n | ok | compress | testing | 300 | - Duplicate of provenance-internal goes |
| 1057 | 465 | R S | part | snap | compress | testing | 300 | - |
| 1062 | 548 | R | y | ok | compress | testing | 400 | - |
| 1068 | 231 | R | y | ok | keep | testing | 230 | - |

### The rest

| lines | size | kind | chk | ver | verdict | dest | keep | slug or note |
|---|---|---|---|---|---|---|---|---|
| 1072 | 596 | R | y | ok | compress | core | 400 | - Finding 6 needs a ruling first |
| 1083 | 1698 | R B H | part | STALE | compress | core | 550 | cli-audience-line. Finding 9. The "So today" enumeration goes; by the file's own account it has drifted twice. The score-branch split goes to engine |
| 1107 | 1735 | M R | n | ok | compress | core | 450 | - A table of contents of `dev/WRITING.md`, which this file says it does not restate. Keep the pointer and the `say_*` against `mc_note_*` rule |
| 1132 | 367 | R | n | STALE | rewrite | core | 250 | Finding 1 |
| 1141 | 898 | R W E | y | ok | compress | core | 250 | claude-md-location |
| 1152 | 1903 | M H | n | STALE | rewrite | core | 300 | rationale-not-a-log. Stage 4 rewrites this to describe `dev/RATIONALE.md` |
| 1177 | 226 | M | n | ok | keep | core | 220 | - |
| 1182 | 1249 | M H | n | STALE | rewrite | core | 180 | Findings 12, 15 |
| 1196 | 1030 | R H | n | STALE | compress | core | 300 | no-design-doc. Finding 1 |
| 1209 | 146 | M | n | ok | keep | core | 146 | - |
| 1212 | 441 | F | n | ok | compress | core | 250 | - All four lines duplicate a rule above |
| 1221 | 1327 | R W H | y | ok | compress | core | 350 | no-tracked-rprofile. The CI story moves |

## Proposed slugs

78 entries, close to the 80 tags the file carries today. Several blocks share one entry.

```
assets-consent                  fixture-census                 no-third-coverage-frame
assets-dir-is-cache             floors-per-batch               no-tracked-rprofile
accessors-never-search          fmt-grid                       normalization-vendored
batch-column-conditional        frame-vs-warning               normalize-two-facts
batch-label-derived             full-panel-fixtures            not-finite-backstop
batch-label-display             gates-span-one-set             note-is-step-verdict
bmiq-fails-the-sample           generated-namespace            note-legend
bmiq-gold-as-fit                goldens-parity-cannot-see      note-tokens-closed
bmiq-no-rng                     horvath-block-skipped          one-beta-reader
check-on-demand                 horvath-normalized-block       pack-is-gz-rds
checkmate-at-surface            input-sweep-per-batch          parity-gate-on-generator
cite-clocks-generic             kernel-bounds-and-sexp         parity-two-axes
claude-md-location              known-parity-gaps              partial-is-a-note
cli-audience-line               mc-batch-id-name               pheno-shape
control-exemption               meta-remote                    positions-axis
coverage-batch-axis             na-coverage-row-drop           predict-sex-columns
coverage-one-span               no-blind-na-label              print-grammar
coverage-only-what-was-counted  no-correlation-gate            provenance-internal
cran-runs-a-fraction            no-design-doc                  rationale-not-a-log
cross-sample-pending            no-dollar                      rbind-never-reconciles
deps-for-code-not-tests         no-partial-match               routed-members-hidden
digest-order                    routing-total                  row-gate-after-notes
digest-sort-order               smoke-tier-purpose             source-tree-tests-do-not-ship
external-unit-is-clock          suite-budget                   summary-counts-notes
external-vs-pack-scored         sync-registries                token-args-bounded
ext-data-argument               two-floors-two-panels          finalizer-definition
```

The Armadillo history at line 52 folds into `normalization-vendored` and gets no entry of its own.

## Decisions needed before stage 2

1. **Finding 6.** Single hyphens or `--` in the rules files and the rationale file. My
   recommendation: single hyphens there, and narrow the ASCII section to say `--` is required in
   package sources only.
2. **Finding 7.** Is `codebook()` now a settled part of the surface, and is the `description`
   field verified upstream. The text follows from the answer.
3. **Finding 8.** Whether the full-panel front-door behavior needs a rule of its own, or a line
   under the sweep rule.
4. **Finding 15.** Whether the `dev/to-do.md` paragraph compresses to one sentence.
5. **The counts proposal.** A rule names the declaration it reads and never the count.
6. **Approve or amend the verdicts.** The ones I would look at first, because they cut the most
   from text that guards a silent wrong answer: 367 (finalizer), 450 (positions axis), 308 (blind
   `NA`), 586 (BMIQ per sample), 839 (pack reader).
