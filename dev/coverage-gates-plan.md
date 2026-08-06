# Plan: harmonize the two coverage gates on NA

Work plan for the branch `coverage-gate-na`. **This is a staging doc, not a record.** It exists so
the work can be checkpointed across sessions. When the work ships, the decisions move to a dated
`dev/DECISIONS.md` entry, the rules move to `CLAUDE.md`, and **this file is deleted**. It is not a
design doc for shipped behavior; the repo deliberately has none (see CLAUDE.md, "Source-of-truth
docs").

Started 2026-08-06.

---

## 1. The change in one line

**Neither coverage floor aborts. A floor decides what does not get a number.**

| condition | today | after |
| --- | --- | --- |
| clock below `min_clocks_coverage` | `cli_abort`, whole call dies | warn, that clock's column is `NA` for the batch |
| clock within 1.1x of the floor | warn, scores | unchanged |
| thin normalization panel | warn, scores | unchanged |
| sample below `min_samples_coverage` | warn, scores | warn, that cell is `NA` |
| sample within 1.1x of the floor | (no band) | warn, scores |
| zero observed CpGs, either axis | abort | `NA`, at any floor, under any policy |
| sample with no observed CpG on any panel | abort | `NA` row |
| PhysAge surrogate flat across the cohort | abort | `NA` plus a recorded reason |

`calc_clocks()` gains no arguments and the record gains no fields.

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

The clause **drops the `clock_impute()` policy lookup** that today's `undefined` test carries. Cost
accepted: a `vendor_mean` clock with a fully absent panel no longer scores at threshold 0. It
returned an identical constant for every sample, which is not a score anyone should act on.
`test-coverage-gate.R:46` pins that behavior today and inverts.

**The gate reads observed presence, never `score_used`.** For a `vendor_mean` clock
`score_used / score_needed` is always 1, so gating on it would mean the floor has no effect on
vendor-filled clocks at all. The two features do different jobs: the floor decides whether a clock
is scored, and the vendored fill patches absent probes for clocks that already cleared the floor.
Below the floor a `vendor_mean` clock is NA and unfilled, like any other.

The same rule is what makes the dead-sample abort removable (step 3): a sample with zero observed
CpGs has every value filled from the cohort mean, so its score equals the mean sample's score.

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
| R4 | branch could not fit the sample (BMIQ calibration failure, Wang moments with n < 2, flat PhysAge surrogate) | cell | recorded at score time in `$provenance$scoring_failures` |
| R5 | a dependency was NA | cell | derived from `clock_depends_on()` + the dependency's NA cells |
| - | unexplained | cell | must always be empty; if it fires it is a package defect |

**Derive, do not store.** Both gates are pure functions of facts the record already holds per
batch, and R4 already has a channel. Storing an n x k reason matrix would duplicate them and could
drift from the gate that made the decision. Deriving R2 and R3 through the *same* helpers the gates
use (`panel_ratio()`, `row_coverage()`) makes drift impossible by construction, keeps the record
small, and stays exact under `rbind`.

Two rules that fall out:

1. **The derivation reads each batch's own floor, never the reconciled `max`.** `samples_coverage()`
   takes the most restrictive floor across batches so its warning has one meaning, but a cell's
   NA-ness was decided under the floor its own batch ran with. Using the max post-bind would label
   cells "below the floor" that hold a real score.
2. **The accessor is a finalizer** and falls into that derived set by CLAUDE.md's mechanical test
   without an edit, because it reads the NA pattern of `$scores` and an unfinalized cross-sample
   column is entirely NA until `finalize_cross_sample()` runs. So it calls `finalized()`.

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
  and already warns for a column with too few complete samples. **`calc_accel()` needs no change.**
- `assoc_row()` (`R/score_associations.R:60`) filters on `is.finite(v)` and returns NULL below
  `MIN_ASSOC_N`, so an NA-heavy or all-NA clock drops out of the report.
  **`score_associations()` needs no change.**
- `apply_karyotype()` (`R/predict_sex.R:64`) handles NA (`hit[is.na(hit)] <- FALSE`) but routes the
  sample to `kc[["default"]]`. **Open risk, see step 6.**
- `output_ids` derives from the request, not from coverage, so score columns are identical across
  batches even when one batch NA'd a clock. `rbind` and `refinalize_clocks()` need no change.

## 5. Open items, with the default if nobody decides

- `min_samples_coverage` default stays `0.75` even though it now blanks cells rather than warning.
  Consistency with the clock floor beats leniency, and there are no users yet. It is a sharp
  default: a sample whose panel is 26% cohort-mean-filled goes from a degraded number to `NA`.
- The accessor is `score_gaps()`. It fits the `<verb>_<noun>` shape of `clocks_coverage()` and
  `samples_coverage()` better than `na_reasons()`.
- Each gate emits one `cli_warn` covering both its tiers as separate bullet groups, so the worst
  case drops from five warnings in a call to three.

---

## 6. Steps

Steps 1 to 3 are one coherent behavior change and can land as one commit. 4 to 7 can trail.
Roughly eight files in `R/`, one new export, two or three test files.

Standing constraints: never run `R CMD check` or `devtools::check()`; never run the parity tier
unless the maintainer asks; read `dev/WRITING.md` before writing any user-facing text.

### Step 1. Column gate stops aborting

- [ ] `classify()` in `R/coverage_gates.R` returns `na` / `warn` / `""`, drops the
      `clock_impute()` policy lookup, gains the D1 zero clause.
- [ ] `check_coverage()` warns instead of aborting and **returns** the NA'd ids.
- [ ] `mc_cohort()` (`R/score_cohort.R:181`) carries them in `facts`.
- [ ] `score_cohort()` seeds those ids with an n x 1 NA matrix, filters both the pack-group loop
      and the dispatch loop, and never lets them reach `pending`.
- [ ] Tests: the gated clock is NA while its neighbours score; a composite inherits NA from a gated
      dependency; an alias inherits per sex.

Done when: `calc_clocks()` returns a record for a request holding one under-covered clock.

### Step 2. Sample gate NAs its cells

- [ ] Build the per-clock sample mask from `row_coverage()`, once, after `compute_coverage()` and
      before the dispatch loop. That placement is what enforces D2 structurally.
- [ ] Apply it in the loop immediately after each branch returns, to the pack-group outputs too,
      and to the cross-sample raws before they enter `pending`.
- [ ] `check_row_coverage()` becomes the near-miss warning only, and excludes gated clocks: "scored
      some samples below" is false for a clock that was not scored.
- [ ] Tests: cell-level NA; PhysAge survivors still score with a masked sample present;
      `refinalize_clocks()` still exact after a bind.

Done when: a low-coverage sample yields `NA` for that clock and a real score for its neighbours.

### Step 3. The last two coverage aborts

- [ ] `scan_missing_cpgs()` (`R/missingness.R:267`): drop the dead-sample abort. D1's zero rule
      catches the row on the sample axis at any floor.
- [ ] `zscore_raws()` (`R/score_PhysAge.R:74`): NA those samples and record an R4 note instead of
      stopping.

### Step 4. Messages

- [ ] Read `dev/WRITING.md` first.
- [ ] One `cli_warn` per gate, two bullet groups each, carrying the NA fact and the "lower the
      floor" hint.
- [ ] Keep `gate_label()` so routed member ids never leak into user-facing text.
- [ ] Tests assert *that* it warns, never the wording.

### Step 5. `score_gaps()`

- [ ] Derive R1, R2, R3, R5; read R4 from `scoring_failures`; apply the precedence in D3; assert
      the unexplained bucket is empty.
- [ ] Per-batch floors, not the reconciled max. Calls `finalized()`.
- [ ] Long frame: `id`, `clock_id`, `reason`, plus `mc_batch_id` only when multi-batch, through the
      shared `drop_single_batch()` / `is_multi_batch()` path.
- [ ] Roxygen to `dev/WRITING.md`, close the `@seealso` groups across the neighbouring topics,
      `devtools::document()`, then `lint_roxygen()` and `lint_seealso()` both empty.
- [ ] Say in the summary which `export()` entry this implies.

### Step 6. Verify downstream

- [ ] Check the catalog's declared karyotype `default`. If it is a real karyotype rather than an
      unknown marker, an unscoreable sample is silently called, and that needs fixing here.
- [ ] One test each pinning that `calc_accel()` and `score_associations()` survive an all-NA
      column. Both are safe today (section 4), but it is now a reachable state, not a theoretical
      one.

### Step 7. Docs and invariants

- [ ] `calc_clocks()`: the `@details` coverage paragraph and both `@param` texts.
- [ ] `clocks_coverage()` / `samples_coverage()` details where they describe the gates.
- [ ] `CLAUDE.md`: the "recorded but read by nothing / it aborts, so a record's existence proves it
      passed" line; the parity note on the `ratio == 0` stop (the rule survives, the verdict
      changes); the `KNOWN_PARITY_GAPS` reasoning; the finalizer set gains `score_gaps()` by
      derivation, so check the wording still reads correctly.
- [ ] `dev/DECISIONS.md` entry: the gate reversal, the one-pass rule with its accepted cost, the
      floor-independent zero rule, the closed reason set, derive-not-store.
- [ ] Delete this file and its `dev/to-do.md` pointer.

### Step 8. Test sweep

- [ ] `devtools::test()`, reported honestly, saying plainly that check was not run.
- [ ] `test-coverage-gate.R` inverts rather than grows. Most of its `expect_error` blocks become
      warn plus an `is.na` assertion. The suite has a budget (CLAUDE.md, "Test altitude").
- [ ] Parity only if the maintainer asks. Expected to be unaffected: it runs both gates at 0, and
      the only zero-panel targets are already `KNOWN_PARITY_GAPS` skips.
