# Plan: harmonize the two coverage gates on NA

Work plan for the branch `coverage-gate-na`. **This is a staging doc, not a record.** It exists so
the work can be checkpointed across sessions. When the work ships, the decisions move to a dated
`dev/DECISIONS.md` entry, the rules move to `CLAUDE.md`, and **this file is deleted**. It is not a
design doc for shipped behavior; the repo deliberately has none (see CLAUDE.md, "Source-of-truth
docs").

Started 2026-08-06. **Steps 1 to 3 have landed** (commit `19376b9`), so the behavior below is the
behavior on this branch. Steps 4 to 8 are open.

---

## 1. The change in one line

**Neither coverage floor aborts. A floor decides what does not get a number.**

| condition | before the branch | now |
| --- | --- | --- |
| clock below `min_clocks_coverage` | `cli_abort`, whole call dies | warn, that clock's column is `NA` for the batch |
| clock within 1.1x of the floor | warn, scores | unchanged |
| thin normalization panel | warn, scores | unchanged |
| sample below `min_samples_coverage` | warn, scores | warn, that cell is `NA` |
| sample within 1.1x of the floor | (no band) | warn, scores |
| zero observed CpGs, either axis | abort | `NA`, at any floor, under any policy |
| sample with no observed CpG on its scoring panel | abort | `NA` cell, per clock |
| PhysAge surrogate flat across the cohort | abort | `NA` plus a recorded reason |

`calc_clocks()` gains no arguments and the record gains no fields.

### Where the code is, after steps 1 to 3

A fresh session should not have to rediscover these.

- `R/coverage_gates.R` -- `check_coverage()` (column gate, warns and **returns** the NA'd ids),
  `row_gate()` / `row_gate_one()` (per-sample verdicts, `na` and `near` masks per clock),
  `check_row_coverage()` (warns from those verdicts, two tiers), `gate_label()`, `row_coverage()`.
- `R/score_cohort.R` -- `mc_cohort()` stores `facts[["na_clocks"]]`; `score_cohort()` takes
  `min_samples_coverage`, seeds the gated columns, builds `gate` and returns it, and applies
  `mask_gated_rows()`; `finalize_cross_sample()` returns `list(scores, notes)`; `merge_notes()`.
- `R/calc_clocks.R` -- threads `min_samples_coverage` into `score_cohort()`, reads
  `scored[["gate"]]`, merges the two note sources into `scoring_failures`.

## 2. Why

`min_clocks_coverage` and `min_samples_coverage` are the same kind of statement about the same kind
of evidence, and they behaved differently for no stated reason: one killed the call, the other
warned. The package already ships the target behavior on a third axis, so this is bringing two axes
into line with an existing one rather than inventing a policy: `warn_missing_covariates()`
(`R/validate_inputs.R:278`) warns and tells the user "A sample with a missing covariate scores NA".

Aborting is also the wrong verdict on its merits. One under-covered clock in a request for forty
kills the other thirty-nine, and the caller cannot see the coverage report that would tell them
what to drop, because no record was returned.

## 3. Decisions, with the reasoning

### D1. Zero observed CpGs is always NA

One floor-independent rule, stated once, applied on both axes:

> Zero observed CpGs is always NA, at any floor, under any imputation policy.

The verdict is not special (everything is NA now); the **test** needs one extra clause, because a
comparison against a floor cannot express this when the floor is 0. `ratio < threshold` is
`0 < 0` at `min_clocks_coverage = 0`, which is FALSE, so a fully absent panel would not be caught
and the branch would run: `mean` reduction divides by zero and returns `NaN`, `sum` reduction
returns the bare intercept. That second one is a plausible-looking number computed from none of the
user's data. Parity runs both gates at 0, and CLAUDE.md already forbids exactly this outcome for
`DNAmSex_Wang_*@cohort_450K` ("a 0 there is the Female quadrant of the sign map, not a small
number").

The clause **drops the `clock_impute()` policy lookup** that the old `undefined` test carried. Cost
accepted: a `vendor_mean` clock with a fully absent panel no longer scores at threshold 0. It
returned an identical constant for every sample, which is not a score anyone should act on. The
test that pinned the old behavior now pins this one, over both policies at once.

**The gate reads observed presence, never `score_used`.** For a `vendor_mean` clock
`score_used / score_needed` is always 1, so gating on it would mean the floor has no effect on
vendor-filled clocks at all. The two features do different jobs: the floor decides whether a clock
is scored, and the vendored fill patches absent probes for clocks that already cleared the floor.
Below the floor a `vendor_mean` clock is NA and unfilled, like any other.

The same rule is what makes the dead-sample abort removable (step 3). A sample with zero observed
CpGs has every value filled from the cohort mean, so its score is the mean sample's score, which is
the same worthless number the column-axis clause exists to refuse.

**On the sample axis the rule is measured on the scoring panel, and that is not the panel the ratio
uses.** `row_coverage()` reads the normalization panel where a clock declares one, so a
`DunedinPACE` sample dead on all 173 scoring CpGs still reads about 99% covered against the roughly
20k gold-standard background. Ratio and zero rule therefore read different panels, by design. This
was found while building step 2 and is the one place the two axes are not symmetric.

### D2. One pass, column stat then sample stat, no feedback

The direction is `col stat -> col gate -> sample stat -> sample gate`, and it never runs backwards.
This is already the architecture, so the decision codifies rather than rebuilds:

- `scan_missing_cpgs()` computes cohort presence and the cohort means for partial fill (col stat).
- `check_coverage()` gates clocks on `present / needed` (col gate).
- `compute_coverage()` counts per-sample misses inside the surviving panels (sample stat).
- The new sample gate reads that.

**Accepted cost, and it belongs in the DECISIONS entry and the user docs:** a sample that gets
NA'd still contributes to the cohort mean that fills every other sample's partial CpGs, and a
column ratio is never recomputed after samples are gated. No recursion means no re-derivation.

The 1.1x warn band applies at both gates, computed on the same one-pass stats.

### D3. The NA reason set is closed, and derived rather than stored

Verified in the code, and it collapses the original six-cause list:

`scan_missing_cpgs()` puts all-NA columns in `all_na_cols` and removes them from `usable_cols`, so
they are absent, not present. Partial columns are cohort-mean filled and `observed_panel()`
overwrites them from `partial_cache`. **After the fill, the beta panel that reaches a matmul holds
no NA at all**, so `obs$values %*% coef` cannot create one. The only NA-bearing operands are the
covariate matrix and a dependency's score. No output transform creates NA either: `anti_trafo`,
`log_offset_anti_trafo` and `poly_eval` all propagate and never generate. Degenerate arithmetic
here yields `NaN` or `Inf`, a different value that `check_score_values()` already owns.

So "the matmul creates NA" and "the transform creates NA" are not root causes, they are
propagation. The closed set, in precedence order:

| | reason | grain | source |
| --- | --- | --- | --- |
| R1 | covariate missing in `pheno` (includes unknown `Female`, which is what NAs a sex-routed alias) | cell | derived from `$pheno` |
| R2 | clock below `min_clocks_coverage` | column, per batch | derived from `$coverage$per_clock` + that batch's floor |
| R3 | sample below `min_samples_coverage` | cell | derived from `$coverage$sample_miss` + that batch's floor |
| R4 | branch could not fit the sample (BMIQ calibration failure, Wang moments with n < 2, flat PhysAge surrogate) | cell | read from `$provenance$scoring_failures` |
| R5 | a dependency was NA | cell | derived from `clock_depends_on()` + the dependency's NA cells |
| - | unexplained | cell | must always be empty; if it fires it is a package defect |

**Derive, do not store.** Both gates are pure functions of facts the record already holds per
batch, and R4 already has a channel. Storing an n x k reason matrix would duplicate them and could
drift from the gate that made the decision. Deriving R2 and R3 through the *same* helpers the gates
use makes drift impossible by construction, keeps the record small, and stays exact under `rbind`.

Three rules that fall out:

1. **The derivation reads each batch's own floor, never the reconciled `max`.** `samples_coverage()`
   takes the most restrictive floor across batches so its warning has one meaning, but a cell's
   NA-ness was decided under the floor its own batch ran with. Using the max post-bind would label
   cells "below the floor" that hold a real score.
2. **R3 is derived by calling `row_gate()`, not by re-comparing a ratio to the floor.** After step 2
   the row gate is a ratio on the gate panel **plus** a zero rule on the scoring panel (see D1), so
   a hand-rolled `panel_ratio() < floor` misses the dead-on-scoring-panel case and leaves that cell
   in the unexplained bucket. `row_gate()` takes the coverage structure and a threshold and returns
   the `na` mask per clock, which is exactly what R3 needs.
3. **The accessor is a finalizer** and falls into that derived set by CLAUDE.md's mechanical test
   without an edit, because it reads the NA pattern of `$scores` and an unfinalized cross-sample
   column is entirely NA until `finalize_cross_sample()` runs. So it calls `finalized()`
   (`R/calc_accel.R:3`).

**R4 now has two producers, not one.** `note_scoring_failure()` writes into the block collector at
score time, and `finalize_cross_sample()` returns its own notes at reduce time, which
`merge_notes()` folds in. Read `$provenance$scoring_failures` and do not re-derive either.

Consequence: `clocks_coverage()` does **not** need a `scored` column, and the "no `below_min`
column" invariant stays as written.

### D4. Skip and seed on the column axis, mask after return on the sample axis

Not "run the branch on an empty panel and let NA fall out". That does not yield NA, it yields a
wrong number: `mean` reduction gives `NaN` (which then trips `check_score_values()` and produces a
second, misleading warning), `sum` reduction gives the bare intercept, and `zscore_raws()` aborts.

- **Column gate: skip the branch, seed `results[[id]]` with an n x 1 NA matrix.** The seed is
  mandatory, not cosmetic. A `NULL` entry makes `as.numeric(results[[nm]])` return `numeric(0)`,
  which silently shrinks a dependent's `score_vec` instead of erroring.
- **Sample gate: mask after the branch returns.** Rows cannot be skipped; the branch scores the
  cohort in one matmul. One line in the dispatch loop, applied uniformly, never inside a branch.

Masking inside the loop puts it before dependents read `results`, so NA propagates into GrimAgeV1,
DNAmFitAge and the sex-routed aliases for free, and per sex for the aliases. Verified NA-tolerant:
`score_DNAmFitAge` (`R/score_DNAmFitAge.R:12`), `score_GrimAge` (`R/score_GrimAge.R:39`),
`score_sex_routed` (`R/score_routed.R:25`) are the only three readers of `results`.

**Cross-sample clocks: mask the raws, before they enter `pending`, not the finalized score.** That
keeps `refinalize_clocks()` exact after a bind, and `scale()` in `zscore_raws()` computes both
center and sd with `na.rm = TRUE` (verified), so a masked sample drops out of the cohort moments and
every surviving sample keeps a real score.

## 4. Facts already verified, so a later session does not re-derive them

- `scale.default()` uses `na.rm = TRUE` for center and sd. Masked rows do not poison the PhysAge
  cohort z-score.
- `qr.resid()` **errors** on an NA in `y` (`NA/NaN/Inf in foreign function call`), confirmed at the
  console. It is not reached: `residualize()` (`R/calc_accel.R:254`) builds
  `okm <- !is.na(resp) & keep`, splits columns by missingness pattern, subsets rows before the fit,
  and already warns for a column with too few complete samples. **`calc_accel()` needs no change**,
  and after steps 1 to 3 this was confirmed against a real all-NA column: it warns "1 clock had too
  few complete samples to fit". It **keeps** that clock's rows with `NA` in `accel`, and does not
  drop them, which an earlier draft of this line said (corrected in step 6).
- `assoc_row()` (`R/score_associations.R:60`) filters on `is.finite(v)` and returns NULL below
  `MIN_ASSOC_N`, so an NA-heavy or all-NA clock drops out of the report.
  **`score_associations()` needs no change**, also confirmed against a real all-NA column.
- Both coverage frames build over a gated clock, and `samples_coverage()` still carries its rows.
  That is correct and not a defect: the clock read CpGs, so it is in the span the invariant defines,
  and its coverage really is low.
- `apply_karyotype()` (`R/predict_sex.R:64`) handles NA (`hit[is.na(hit)] <- FALSE`) but routes the
  sample to `kc[["default"]]`. **Closed in step 6: not a risk.** The earlier reading stopped at that
  line. The line after the rule loop blanks any sample missing an operand score, so the declared
  default is only ever reached by a sample with two real scores that match no rule.
- `output_ids` derives from the request, not from coverage, so score columns are identical across
  batches even when one batch NA'd a clock. `rbind` and `refinalize_clocks()` need no change.

## 5. Open items, with the default if nobody decides

- `min_samples_coverage` default stays `0.75` even though it now blanks cells rather than warning.
  Consistency with the clock floor beats leniency, and there are no users yet. It is a sharp
  default: a sample whose panel is 26% cohort-mean-filled goes from a degraded number to `NA`.
- The accessor is `score_gaps()`. It fits the `<verb>_<noun>` shape of `clocks_coverage()` and
  `samples_coverage()` better than `na_reasons()`.
- ~~Warning consolidation~~ **decided in step 4: the tiers stay apart.** Five warnings in the worst
  case, and they do not merge. A warning is a catchable condition, so merging two independent
  findings into one takes away a caller's ability to handle them apart. The tiers also have
  different next steps -- the NA tier says how to get a number, the near tier says nothing is wrong
  yet -- and R4 asks each message for one actionable next step. Folding them would also put two
  quantities in one template, which is exactly the `cli::qty()` footgun `dev/WRITING.md` section 3
  warns about. The tiers are disjoint by construction on both axes, so no run repeats a clock
  between them.

---

## 6. Steps

Steps 1 to 4 have landed. What remains: `score_gaps()`, the downstream check, the prose edits,
`CLAUDE.md`, and then one final pass over everything.

**The roxygen audit is deferred to step 9, deliberately.** Steps 5 to 8 write roxygen tags where a
new or changed topic needs them, because `document()` generates `NAMESPACE` from tags and an export
does not exist without one. They do **not** audit that text against `dev/WRITING.md`. Auditing prose
that a later step may rewrite is work done twice, and the manual only reads correctly when the whole
changed surface is read together. Step 9 does that read once, over everything.

Standing constraints: never run `R CMD check` or `devtools::check()`; never run the parity tier
unless the maintainer asks; read `dev/WRITING.md` before writing any user-facing text.

### Step 1. Column gate stops aborting. DONE 2026-08-06, commit `19376b9`

- [x] `classify()` in `R/coverage_gates.R` returns `na` / `warn` / `""`, drops the
      `clock_impute()` policy lookup, gains the D1 zero clause.
- [x] `check_coverage()` warns instead of aborting and **returns** the NA'd ids.
- [x] `mc_cohort()` carries them in `facts[["na_clocks"]]`.
- [x] `score_cohort()` seeds those ids with an n x 1 NA matrix, filters both the pack-group loop
      and the dispatch loop, and never lets them reach `pending`.
- [x] Tests: the gated clock is NA while its neighbours score; a composite inherits NA from a gated
      dependency; an alias inherits per sex.

Not in the plan, found while building it: **a partial `pending` after a bind is now reachable**,
because one batch may gate a cross-sample clock while another scores it. `refinalize_clocks()` read
a missing row through `id_index()`'s default `unmatched = "stop"`, which is a package-defect
message. It now passes `unmatched = "na"`, so those rows stay NA.

### Step 2. Sample gate NAs its cells. DONE 2026-08-06, commit `19376b9`

- [x] `row_gate()` classifies every sample once, after `compute_coverage()` and before the dispatch
      loop. That placement is what enforces D2 structurally.
- [x] `mask_gated_rows()` applies it in the loop immediately after each branch returns, to the
      pack-group outputs too, and to the cross-sample raws before they enter `pending`.
- [x] `check_row_coverage()` reads the verdicts `row_gate()` already built, warns in two tiers, and
      excludes column-gated clocks: "scored some samples below" is false for a clock not scored.
- [x] Tests: cell-level NA; PhysAge survivors still score with a masked sample present;
      `refinalize_clocks()` still exact after a bind.

**The zero rule needed a second panel, which the plan did not anticipate.** `row_coverage()`
measures its ratio on the **normalization** panel where a clock has one, so a `DunedinPACE` sample
dead on all 173 scoring CpGs still reads about 99% covered against the roughly 20k gold-standard
background. `row_gate_one()` therefore measures the ratio on the gate panel and the **zero rule on
the scoring panel**, which is the one the arithmetic reads. Without the split, removing
`scan_missing_cpgs()`'s dead-sample abort in step 3 would have silently lost that catch.

### Step 3. The last two coverage aborts. DONE 2026-08-06, commit `19376b9`

- [x] `scan_missing_cpgs()`: drop the dead-sample abort. The row gate catches the row per clock, on
      the panel that clock reads. This retires the function's `score_cpgs` argument and
      `spec[["score_union"]]`, both of which existed only for that check.
- [x] `zscore_raws()`: blank a surrogate that is constant across the cohort rather than stopping.
      One rule now covers a single sample and a surrogate that observed none of its CpGs, so the
      `n < 2` branch is gone too.
- [x] The R4 note. `finalize_cross_sample()` returns `list(scores, notes)` and derives the note
      **without knowing what PhysAge is**: a sample with intermediates but no score lost it in the
      reduction, and a sample with none was blanked upstream and needs no second reason.
      `merge_notes()` folds it into `scoring_failures` at both call sites.

**State after steps 1 to 3:** `devtools::test()` is 825 pass / 0 fail / 0 error / 0 warning / 2
skip, up from 799 expectations before the branch. Step 8 owns whether that growth stays. `R CMD
check` was not run, and neither was the parity tier.

Verified at the console, beyond the suite: `calc_accel()` warns and drops an all-NA column,
`score_associations()` drops it, both coverage frames build, a wholly dead sample scores `NA`
instead of aborting, and `rbind(rbind(r1, r2))` is still `identical()` to `rbind(r1, r2)` when one
batch gated the clock and the other did not.

### Step 4. Messages. DONE 2026-08-06

- [x] Consolidation decided against, reasoning in section 5. The tiers stay apart.
- [x] Audited all five (both column tiers, the thin-normalization warning, both row tiers) against
      R1 to R8. `gate_label()` kept, so no routed member id reaches user-facing text.
- [x] Closing bullets made parallel: `See {.fn f} for X` became `Call {.fn f} to see X` in the
      column near tier and the thin-normalization warning, matching the row tiers.
- [x] Row leads re-subjected. "N clocks have too few CpGs for some samples" put the clock in the
      subject of a statement about samples. Both row leads now open on the samples and carry the
      clock count where the bullets are keyed.
- [x] No test asserted any of the changed wording. Suite unchanged at 825.

**Two of the messages gave advice that does not work, and both are fixed.** This is the finding of
the step, not a style pass.

1. **"Lower the floor to score it" is false for a zero panel.** D1 makes a clock with no observed
   CpG NA at *every* floor, so the column gate told a user to do something that cannot help. The
   bullet is now conditional on at least one failing clock having an observed CpG, and a second
   conditional bullet states the zero rule when a zero-panel clock is in the list. The row gate had
   the identical defect for a sample dead on its scoring panel, fixed the same way.
2. **The row gate reported a coverage figure that contradicted its own verdict.** "worst 99% of
   19827 CpGs" for a `DunedinPACE` sample blanked for having none of its 173 scoring CpGs, because
   the ratio is measured on the gate panel (D1, last paragraph). `row_gate_one()` now returns
   `dead` as a subset of `na`, and the bullet counts dead samples apart from the worst ratio:
   `DunedinPACE: 1 of 6 samples, 1 with no scoring CpGs`, with the ratio clause omitted entirely
   when every blanked sample is dead.

All eight reachable message shapes were rendered and read, not just inspected in source.

### Step 5. `score_gaps()`. DONE 2026-08-06

- [x] `R/score_gaps.R`. R1, R2, R3, R5 derived; R4 read from `scoring_failures`; D3's precedence;
      the unexplained bucket is a `stop()` inside the function, so a call that returns proves it.
- [x] Per-batch floors, read from `provenance` by batch label. Calls `finalized()`.
- [x] Long frame `id`, `clock_id`, `reason`, plus `mc_batch_id` through `drop_single_batch()`.
- [x] Roxygen written, `devtools::document()` run. **Implies exactly one new line in `NAMESPACE`:
      `export(score_gaps)`**, plus `man/score_gaps.Rd`. Nothing else moved.
- [x] `tests/testthat/test-score-gaps.R`, 15 expectations. Suite 825 -> 840.

**The `reason` vocabulary is a returned data value, so it is API**: `covariate`,
`clock_coverage`, `sample_coverage`, `fit`, `dependency`. The two gate reasons are named for the
frames the reader calls next (`clocks_coverage()`, `samples_coverage()`) rather than for the
arguments, because lowering the floor is not always the fix.

**The column gate's span changed, and this is the finding of the step.** `check_coverage()` graded
every clock in `cpg_list`, which includes three clocks that have a declared panel but **no coverage
record**: `GrimAgeV1` (1030 CpGs) and the two `DNAmFitAge_{Sex}` members. So a run could NA a clock
on a panel that `CLAUDE.md` states is not its own coverage ("a clock that reads no betas has no
coverage of its own"), and `score_gaps()` could not then explain the cell from the record: R2 needs
a record to read, R5 does not fire when the descendants all scored, and the cell lands in the
unexplained bucket that D3 says must always be empty. `check_coverage()` now grades only
`clock_reads_cpgs()`, so **the column gate, the row gate and the coverage record span one set of
clocks**, which is the harmonization this branch is about. The loss is a clock whose union panel is
thin while every descendant clears the floor, which cannot happen for a union of panels that each
cleared it.

**One rule was added that the plan did not anticipate: the frame must be self-contained.** Every
`dependency` row names a clock the reader can find rows for in the same frame. The 14 sex-routed
members are the only clocks that break that, since they are never a score column and cannot be
requested by name, so an alias **inherits its member's reason** instead of being told `dependency`.
Without it a routed alias reported `dependency` pointing at a clock the user cannot inspect, which
is a dead end. Derived from `sex_routed_members()` and `sex_rows()`, the two existing sources, and
it is the only special case in the walk.

**Tooling bug found, and it would have broken step 9.** `devtools::document()` poisons
`lint_roxygen()` for the rest of the session: 0 rows after `load_all()`, **16 rows after
`document()`**, same files, same working directory, every one a false positive on a `DOC_TYPES`
fragment containing backticks. `dev/WRITING.md` section 7 prescribed exactly that order. It now
prescribes two sessions and records the measurement. The bug in `lint_roxygen()` itself is unfixed
and is not this branch's work.

### Step 6. Verify downstream. DONE 2026-08-06

- [x] The declared karyotype `default` **is** a real call, `"Female"`. No fix needed anyway:
      `apply_karyotype()` blanks any sample missing an operand score after the rule loop runs, so a
      gap never reaches the default. Confirmed at the console on both new paths, a column-gated arm
      (every sample `NA`) and a single dead row (that sample `NA`, the rest called).
- [x] `test-predict-sex.R`: a sample without both scores is `NA`, not the default, and a call that
      never happened is never a `sex_mismatch`.
- [x] `test-coverage-gate.R`: a gated clock does not break the clocks scored beside it.

**The two analysis verbs answer an all-NA column differently, and both are right.** `calc_accel()`
keeps its rows (one per sample and clock) with `NA` in `accel`; `score_associations()` drops the
clock entirely, because a row of its report would have nothing in it. Section 4 recorded both as
"needs no change", which was true, but recorded `calc_accel()` as dropping the column, which it does
not. The test now pins the shapes rather than the column sets.

### Step 7. Docs and invariants. DONE 2026-08-06

**Fixed what was factually wrong, did not polish.** Every roxygen item here described an abort that
no longer happens, so it was a stale claim about behaviour. Wording is step 9's.

- [x] `calc_clocks()`: the `@details` coverage paragraph rewritten around "neither one stops the
      call", and `min_samples_coverage`'s `@param` no longer says "without a warning".
- [x] Swept the whole roxygen surface for the two floor names and for `stops` / `aborts` /
      `refuses`. **The coverage frames needed nothing** -- neither describes a gate as fatal, and
      `samples_coverage()`'s "warns when a row is under the strictest value" is still exactly true.
- [x] `CLAUDE.md`, six places: the "read by nothing / it aborts" line, the pre-flight paragraph's
      "no refusal" clause, the record-verb surface, "all four exits" (now five, stated twice), the
      finalizer set, the `clock_reads_cpgs()` invariant (now bounding three things), and the
      `KNOWN_PARITY_GAPS` note.
- [x] `dev/DECISIONS.md` entry, dated 2026-08-06.

**One edit was considered and rejected as a falsehood.** `say_low_samples()` re-warns on the
assembled `samples_coverage()` frame, and the obvious step-7 edit is to add "those samples scored
`NA`". It would be wrong: that warning uses the reconciled `max` floor across batches, so a row
under it may well have scored under its own batch's floor. `score_gaps()` is the exact answer and
that message must not pretend to be. Leave it alone.

`CLAUDE.md` and `DECISIONS.md` are `dev`-facing, so R1 to R8 do not bind them and step 9 does not
re-read them. They are done.

**Left for step 9, deliberately:** neither coverage frame points at `score_gaps()`. Discoverability
of the new export is a `@seealso` question about a closed group, which is step 9's to decide, and an
inline `[score_gaps()]` in `@details` would pre-empt it.

### Step 8. Test sweep

The inversion already happened in steps 1 to 3: every `expect_error` that pinned a gate abort is
now a warn plus an `is.na` assertion, across `test-coverage-gate.R`, `test-value-gates.R`,
`test-score-physage.R` and `test-chunk-invariance.R`. What is left is the budget question.

- [ ] The suite went 799 -> 825 expectations. Decide whether the +26 stays (CLAUDE.md, "Test
      altitude"). The likeliest trims are the per-policy loop in the zero-CpG block and the second
      half of the two-band block.
- [ ] `devtools::test()`, reported honestly, saying plainly that check was not run.
- [ ] Parity only if the maintainer asks. Expected to be unaffected: it runs both gates at 0, and
      the only zero-panel targets are already `KNOWN_PARITY_GAPS` skips. **One thing to re-read
      before believing that:** D1 now blanks a zero-panel clock even at floor 0, so a parity target
      that previously scored an empty panel would change. The two `DNAmSex_Wang_*@cohort_450K`
      targets are exactly that shape and are already skips, which is why the expectation holds.

### Step 9. Final audit and simplify pass

**Last, and over the whole branch at once.** Nothing above audits prose or reworks code for shape,
so this step is where both happen. It reads the branch as a finished thing rather than as a series
of edits, which is the only way to catch a seam between two steps that are each fine alone.

Simplify:

- [ ] Read the branch diff end to end. Steps 1 to 8 optimise for landing correct behaviour, so the
      shape is whatever fell out. Look for a helper that earns no name, a conditional that a caller
      already decided, a note channel with one producer, and any pair of functions that now say the
      same thing.
- [ ] Specific candidates, to confirm or reject rather than assume: whether `row_gate_one()` still
      needs to return five fields; whether `merge_notes()` and `collect_notes()` should be one; and
      whether `check_row_coverage()`'s `tier()` closure is worth its indirection at two call sites.
- [ ] Whatever survives must still pass the suite unchanged. A simplification that moves a number
      is not a simplification.

Prose, over every topic this branch touched plus `score_gaps()`:

- [ ] Re-read `dev/WRITING.md`, then audit against R1 to R8. This is the pass steps 5 and 7 defer.
- [ ] `@seealso`: decide once, with the whole changed surface in view, whether `score_gaps()` joins
      the coverage group. **The groups are closed, so this is the maintainer's call, not an agent's**
      -- state the recommendation and the symmetry it would imply, and do not edit a tag without it.
- [ ] `devtools::document()`, then `lint_roxygen()` and `lint_seealso()` both empty.
- [ ] `dump_roxygen()` and read the rendered manual as a document. `dev/WRITING.md` section 2 is
      explicit that wordiness is invisible in the source and obvious in the render.
- [ ] Delete this file and its `dev/to-do.md` pointer, and drop the `.gitignore` exception.
