# Decisions log (package rewrite)

Append-only, date-stamped. Records **why** we chose a design -- the "we tried X / other
maintainers will ask this" history that should not bloat an operational doc.

**Scope:** R package rewrite, packaging, API, and local maintainer workflow. Upstream
metadata contract decisions live in `data-raw/methylCIPHER-meta/control/DECISIONS.md`.

Newest first. Add an entry when a decision reverses a prior approach or is likely to be
second-guessed; do not restate rules already stated in `CLAUDE.md` or `dev/id-streaming-plan.md`.

**Archive:** entries before 2026-07-30 live in `dev/DECISIONS.old.md` (unchanged full log).
Older dated citations in `CLAUDE.md` resolve there. Do not restate that history here.

---

## 2026-08-01 -- the multi-batch test is `is_multi_batch()`, and a frame may decline to build

Always-on suite 1051 pass / 0 fail / 260 skip. Parity not run; `R CMD check` not run.

**The one multi-batch test moved out of `drop_single_batch()` into `is_multi_batch()`**, which
`drop_single_batch()` now calls. Nothing about the exit schema changed -- this is a rename plus one
new reader.

**Every exit frame now reads it to skip building the batch column instead of building and then
dropping it.** `shape_scores()`'s long frame is n x k rows and the batch column is one of its four,
so at a single batch -- every record that has not been through `rbind`, i.e. the common case -- a
quarter of the frame was allocated to be deleted three lines later. Measured at 1.2e6 rows: 37.1 MB
/ 11.98 ms -> 28.4 MB / 9.98 ms, and the two forms are `identical()`. Scales linearly, so ~38 MB at
5e6 rows.

**The invariant this looks like it touches is about the output schema, and the output is
unchanged.** What the 2026-07-31 entry protects is the four exit frames agreeing on whether the
join key exists; a frame that never builds a doomed column and one that drops it are the same
frame. The real risk in a conditional build is the *predicate* getting a second home and drifting
-- which is why the test is named and stated once rather than inlined at the build site. That was
the whole cost of the change, and it is ~10 lines.

**`drop_single_batch()` still runs at all four exits, including the one that no longer needs it.**
Assigning `NULL` to an absent column is a no-op, so the call is free, and keeping it means the
output is correct even if a build condition is later changed or removed. Do not "clean up" the
now-redundant call: it is the gate, and the conditional build is an optimization underneath it.

**All four exits decline to build, not just the one with the measurable win.** The saving is
overwhelmingly in `shape_scores()`'s long branch; the coverage frames were converted for
uniformity, and their numbers are small to nil. `samples_coverage()` at 36000 rows: 22.3 MB ->
19.9 MB (-11%), time within noise -- its frame is six columns of mixed type and `rbind` dominates,
so the batch column is a smaller share than in the four-column score frame. `clocks_coverage()` is
(clocks x batches) rows, so a full catalog at one batch saves under a kilobyte. Neither was worth
doing on its own; both were worth doing so that one rule holds at every exit and no reader has to
work out why one frame builds a column it will lose.

**The two coverage frames thread a flag; they cannot add the column afterwards.**
`samples_coverage()` builds parts per batch, `rbind`s them and then NA-filters, so after the filter
there is no per-row batch left to reconstruct. The flag therefore goes down through
`clock_sample_rows()` and `panel_rows()`, and `empty_sample_rows()` takes it too because it seeds
the `rbind` and a mismatched seed is a hard error. `b` still masks the rows in the loop -- only the
label is withheld -- so the masking never depends on the flag. `empty_sample_rows()` takes a
**logical, not a label**: at zero rows there is no value to carry, and reusing the loop's `b` there
would read the last batch, or fail outright on a record with none.

**`clocks_coverage()` keys on the provenance vector, not on `names(per_clock)`.** The count it
iterates and the count that decides the column are different questions, and CLAUDE.md already pins
the answer to the second one. Passing `if (keep) b else NULL` keeps the loop reading `per_clock`'s
names while the decision reads `provenance[[mc_batch_id]]`.

**Inverting to an `add_batch_column()` that only ever adds was considered and rejected** -- it is
the cleaner one-function form, but `samples_coverage()` cannot use it for the reason above, so it
would need a second path for that site and stop being one function.

---

## 2026-07-31 -- `accel_id` names the spec, and one spec per call

Always-on suite 1051 pass / 0 fail / 260 skip. Parity not run; `R CMD check` not run.

**`calc_accel()` long output carries `accel_id` beside `clock_id`**, derived from the call's
`(formula, type)` pair -- `Age_accel`, `Age_Female_accel`, `Female_diff`, and bare `diff` when
there is no rhs. `long = FALSE` is that same frame pivoted: one column per pair, named
`<clock_id>_<accel_id>`. Wide accel column names therefore changed; they were bare clock ids.

**One `(formula, type)` per call. There is no grid argument.** Every per-fit diagnostic is scoped
to one design matrix -- `say_fill_batch()`, the "too few complete samples" warning that names the
dead clocks, `merge_accel_data()`'s conflict error -- so a grid either fires each of them N times
or merges them into something naming neither call. A grid also forces a cross-product-vs-paired
semantics decision, which is an interpreter. Composition covers it instead, and `accel_id` is what
makes the composition safe: `rbind` over long frames from several calls is unambiguous because
`(id, clock_id, accel_id)` stays unique, and wide frames `cbind` because the label is in the names.

**Term labels go in verbatim -- not lowercased, not slugged.** `~ Age + Female` gives
`Age_Female_accel`, because `Age` is the column the caller has in their pheno and the label should
round-trip to it. Lowercasing only makes sense if `calc_clocks()` case-folds pheno names on the way
in, which it does not and which is a much larger change. A non-syntactic term (`I(Age^2)`) lands in
a wide column name as-is; that is the same choice `shape_scores()` already makes for clock ids via
`as.data.frame(optional = TRUE)`.

**The first draft slugged (`tolower` + non-alphanumerics to `_`) and added an `accel_id =`
override to escape the collisions slugging created** -- `Age.x` and `Age_x` both becoming `age_x`.
Verbatim labels do not have that problem, so the override went with it: derived, never assigned,
same as the batch label. The one residual case is a `_` inside a pheno column name colliding with
the `_` join (`~ Age_Female` against `~ Age + Female`), which is a coincidence in the caller's own
data and does not buy an argument. Note the `is_auto_label()` reasoning (2026-07-30) is about
*gating* on a label; nothing gates on `accel_id`, so an override would have been cheap -- it was
dropped for having no remaining job, not because it was unsafe.

**`accel_id` is not `resid_type`.** `type` already names the `type =` argument, and bare
`type = "diff"` with no formula residualizes nothing, so "resid type" is false for exactly the case
it most needs to label. `accel_id` parallels `clock_id`, and both are join keys.

`MC_ACCEL` lives in `R/calc_accel.R`, not `R/constants.R` -- one file uses it, which is that
file's stated rule. It is deliberately **not** reserved against `data =` the way `MC_BATCH` is: it
never enters the pheno or the formula namespace, so a caller's `accel_id` column cannot collide
with it.

---

## 2026-07-31 -- the batch label is multi-batch only at the exits

Always-on suite 1044 pass / 0 fail / 260 skip. Parity not run; `R CMD check` not run.

**`mc_batch_id` now appears in an exit frame only when the record spans more than one batch.**
`as.data.frame()`, `calc_accel()`, `clocks_coverage()` and `samples_coverage()` all drop it
through one helper, `drop_single_batch()` (`R/mc_result.R`). Nothing internal changed: `$provenance`
still always carries the per-sample vector, `calc_accel()` still always offers `mc_batch_id` to
the formula and still always errors when `data =` supplies it.

**This is not a new policy -- `print.mc_result` has done it since it was written.** The printer
emits its `$provenance [N batch(es)]` block only when `N > 1`, under the comment "a single-pass
record has nothing new to say here". The exit frames were the outlier, not the change. Anyone
re-opening this should start from that: the record already declined to show a single-batch label
in the one place a user always looks.

**The first argument against was wrong on the facts and is recorded so it is not re-run.** It ran:
a user who scores two batches separately, exports each with `as.data.frame()`, and stacks the
frames in dplyr a week later gets two single-batch records, so dropping the label removes it from
exactly the workflow it exists for. That does not hold. The label is a bare 16-hex `xxhash64` of
the id column -- `2f6267c9ce1fa180` -- and a user hand-stacking two frames labels them with
something they chose, not with our hash. At one batch the column is a single repeated opaque value:
its information content is zero, not merely low. The join argument fails the same way; with one
batch `clock_id` is already unique, so `merge(clocks_coverage(x), samples_coverage(x))` still
resolves.

**What decided it was comprehension, not noise.** The noise problem was already solved once by
putting the column last (2026-07-31, "one name for the batch label"). The live problem is that
`mc_batch_id` looks alarming, most users never call `rbind`, and **prose docs are deferred**, so
there is currently nowhere for a user to look up what the column is. Shipping an unexplained hash
to the majority case to serve the minority one is the wrong default.

**The surviving cost is accepted knowingly: this is a data-dependent schema.** `df[["mc_batch_id"]]`
returns `NULL` rather than erroring, `dplyr::select(mc_batch_id)` errors, and either way the code
works on the author's record and fails on the user's. That is the price, and the mitigation is that
**every multi-batch-only decision reads one definition** -- `batch_labels()` (`R/mc_result.R`),
`unique(x[["provenance"]][[MC_BATCH]])`. The printer and all four exits go through it. If they
diverged, the two coverage frames could disagree about whether the join key exists, which is
strictly worse than always carrying it.

`per_clock`'s names were the other candidate and are what the printer used before this entry. They
are not the source: they answer "which batches have coverage records", while the column is filled
from the per-sample vector. The two agree except under a 64-bit label collision -- and there,
provenance gives the more honest answer, because two batches sharing a label cannot be told apart
by a column carrying that label anyway.

**Correction while here: the label is 16 hex (64-bit), not 12 hex (48-bit).** `batch_hash()` returns
`digest(algo = "xxhash64")` untruncated. The 2026-07-30 entry below and `CLAUDE.md` both said 12,
and the collision figure was computed from 48 bits (1.8e-11 at 100 batches); the real figure is
~2.7e-16. `CLAUDE.md` is corrected in place. Nothing downstream depended on the width -- the
conclusion was "no gate on labels" and it only gets stronger.

Not chosen: an `as.data.frame(x, batch = FALSE)` argument. Four functions gain an argument for a
cosmetic default, and the caller still reasons about a conditional schema -- just one they picked.

---

## 2026-07-31 -- R/constants.R holds the shared constants only

Housekeeping pass over the SCREAMING_CASE constants. Always-on suite 1036 pass / 0 fail / 260 skip.
Parity not run; `R CMD check` not run.

**A package namespace is already one flat, sealed environment**, so nothing here was ever defined
twice -- `loadNamespace()` locks the bindings and every `R/*.R` sees every other file's top-level
objects. The whole question was where a human looks, which is why the answer is a plain file of
`NAME <- value` and not a list or a locked env: those buy nothing the namespace lock already gives,
and under the `[[`-only rule they would read as `MC[["NORM_SCHEMES"]]` at every site.

**Only cross-file values moved.** `R/constants.R` holds `MC_BATCH` and the four `NORM_*` policy
sets, which are read from four files between them and whose *names* are the entire point --
a bare `"quantile"` in `coverage.R` says nothing, `NORM_SCHEMES_FILL` says why it is there.
Everything used in exactly one file stayed next to its caller (`MC_ASSET_SUFFIX`,
`PACK_SCORE_TYPES`, `WRITE_SIM_EXTS`, `MC_TAGS`, `MIAGE_*`): `ADULT_AGE <- 20` three lines above
its only reader documents better than the same line in a constants file, and moving it makes you
jump files to read one branch.

**`NORM_ROLES` and `STACK_NAMESPACES` stay in `R/accessors.R` on purpose**, and both now carry a
one-line comment saying so. `data-raw/sync.R` does `source("R/accessors.R", local = mc_runtime)`
and reads them straight back out; hoisting them turns `mc_runtime[["NORM_ROLES"]]` into `NULL`,
which is a sync failure with no error at the point of the mistake. This will look like an unfinished
hoist to the next reader -- it is not.

**Constants that were only naming a well-known number were deleted, not moved.** `ADULT_AGE`,
`LOG_AGE_OFFSET`, `WARN_COVERAGE_MARGIN` and `MC_DEFAULT_RELEASE_REPO` each had exactly one use
site within a few lines of their definition, and the name restated what the literal already said.
The Horvath anti-transform is `21 * exp(x) - 1` / `21 * x + 20` to everyone who reads that
function. `MIAGE_LOWER`/`MIAGE_UPPER` collapsed into one `MIAGE_BOUNDS` because the starts grid
derives from the bounds -- that coupling is real and worth a name, two separate scalars were not.

**Four `mc_batch_id` literals survive, and that is not an oversight.** `MC_BATCH` replaced the
lookup keys (`out[[MC_BATCH]]`, `prov(args, MC_BATCH)`) because a typo there silently yields a
wrong column. It cannot replace a `name =` position inside `list()` / `data.frame()` without
`setNames` or `do.call`, which is more machinery than the literal costs. The rule is: keys use the
constant, declarations spell it out.

---

## 2026-07-31 -- one name for the batch label, and finalizers re-finalize

Third pass over the finalizers, driven by walking the rbind -> `calc_accel` workflow. Always-on
suite 1036 pass / 0 fail / 260 skip. Parity not run; `R CMD check` not run.

**The batch label is `mc_batch_id` everywhere, renamed from `batch`.** Two reasons, and the second
is the one that forced it. First, it was about to become a formula variable in `calc_accel`, and
a user's `batch` is their **slides or plates** -- biology, and a covariate they may legitimately
want in the rhs -- while ours only says which samples shared a cohort-mean fill. Shadowing theirs
with ours would be the worst kind of silent wrong answer. Second, and independent of formulas:
`batch` is a common column name, so `clocks_coverage()` / `samples_coverage()` output collided with
a user's own metadata on a join. The `mc_` prefix fixes both, and the rename went everywhere the
user can touch it -- both coverage frames, both finalizer frames, and `$provenance` -- because
"prefixed here, bare there" is exactly the inconsistency being removed. `data =` supplying
`mc_batch_id` is a flat **error**: the name is reserved, which is simpler than a precedence rule
and, given the prefix, cannot happen by accident.

**The label is always minted, so it is never auto-injected into a design.** `construct_mc_result()`
sets one on every run, so a single-batch record's label is a *constant* column -- absorbed by the
intercept, numerically nothing, conceptually noise. And on a multi-batch record injecting a
k-level factor adds k-1 columns and moves **every** residual for **every** clock. Chunking is an
operational decision (memory, streaming); it must not silently change the model. So the label is
offered to the formula and never added to it.

**The prompt to use it is gated on the fill actually happening.** Not "more than one batch" but
"more than one batch **and** some CpG was cohort-mean filled". Verified detectable:
`score_imputed_partial` is 0 on a clean run and >0 once the beta matrix has NAs, per batch. Only
the *partial* fill counts -- `imputed_full` takes the clock's vendored reference, which is the same
constant in every batch. Without that gate the note fires on records where the batches are
numerically irrelevant, which is how a real warning gets trained away.

**Every finalizer re-finalizes; `rbind` still does not.** `calc_accel` was residualizing
per-batch reductions of a bound cross-sample clock (measured: `DNAmPhysAge` accel changes after
`refinalize_clocks()`, `Hannum` does not) and saying nothing. The rbind reason for staying hands-off
does not transfer: `do.call(rbind, ...)` recurses, so re-finalizing there would redo the work at
every intermediate step, but a finalizer is a **leaf** -- it hands back a frame the record cannot be
recovered from, so it must hand back the right numbers. `as.data.frame()` does it too, so the two
finalizers cannot disagree about the same clock on the same record. Wanting the per-batch
reductions is still expressible: finalize each record *before* binding.

**The guard is `say_pending()`'s, not `length(pending)`.** First cut used the latter and printed
"Re-finalized ..." on every single-batch record holding a cross-sample clock -- `calc_clocks()`
retains `pending` even for a single pass, and a single-batch reduction already spans its whole
cohort, so that call was a numerical no-op emitting a message. Matching `say_pending()`'s condition
(pending **and** more than one batch) is also the right symmetry: finalizers re-finalize exactly
where `rbind` would have warned.

---

## 2026-07-31 -- `calc_accel` internals: one QR per row set, and the join gates what a join can break

Second pass over `R/calc_accel.R`. Always-on suite 1020 pass / 0 fail / 260 skip. Parity not run;
`R CMD check` not run.

**`lm()` is gone, and with it the scratch response column.** The first cut fitted per clock with
`lm(.mc_y ~ <rhs>)`, which needed a fixed magic name for the response because the response is a
different clock each iteration, and needed the rhs spliced back into a two-sided formula via
`call("~", quote(.mc_y), formula[[2L]])`. All of that existed only to satisfy `lm`'s interface. But
the rhs is **already one-sided**, so it *is* the design formula: `model.matrix()` consumes it
directly and `qr.resid()` needs no response name at all. Verified identical to `residuals(lm())`,
max abs diff 0, over `~ Age + Female`, `~ Age + I(Age^2)`, a factor covariate, `~ 1`, and a
rank-deficient design. It also makes the degenerate test exact -- `nrow(X) - qr$rank < 1` -- where
before it was a `length(vars) + 1` heuristic (wrong for factors and interactions) backed by a
post-fit `df.residual` check.

**The grouped fit stopped being an optimization.** `dev/calc_accel.md` had deferred "group clocks
by missingness pattern, one QR per pattern" as a performance escape hatch. Under `qr.resid` -- which
takes a **matrix** response -- it is simply the shorter code, and in the common case (no `NA`
scores) there is exactly one group, so the entire residualization is one decomposition over the
whole n x k matrix instead of k separate `lm` calls each rebuilding the same design. Group on the
rows a column *fits over* (`!is.na(resp) & keep`), not on its raw NA pattern: two clocks whose NAs
differ only where `keep` is already `FALSE` share a design and must not get two QRs.

**The cost is accepted, not overlooked:** `qr.resid` returns residuals and nothing else -- no
coefficients, R^2, or p-values. The frame is for plotting, and anyone modelling on it re-adds
`Age`/`Female` to their own rhs. If a future caller wants a slope back, that is `lm` coming back
with it.

**The join gates what a join can break, and nothing else.** Proposed a strict coverage gate --
every record sample must appear in `data`, mirroring `resolve_pheno()`. Wrong framing, and dropped.
`merge_accel_data()` is a **left join**; unmatched left rows are what a left join *is*. The only
thing that makes it ill-defined is a duplicated key on the right, and since `$pheno`'s ids are
already unique by the scoring-time `check_pheno`, "validate 1:1" reduces to the one check that was
already there. So: **multiplicity is a gate, coverage is a report.** The unmatched-id case warns
instead, which also draws a distinction worth having -- an explicit `NA` row in `data` is the
caller saying they know, a *missing* row is the caller possibly not knowing. Same downstream `NA`,
different thing to say.

That report is not cosmetic. Zero id overlap (a `sample1` vs `Sample1` typo) previously produced
two true but misleading warnings -- "Age: 8 samples missing", then "too few complete samples" --
and sent the user looking for phenotype data that was fine.

**Also corrected:** the duplicate-id gate's stated reason. `match()` returns the first match and
cannot multiply rows, so "fan-out" was wrong; the gate exists because the pick would be silent and
arbitrary.

**Type families replaced the numeric/character free-for-all.** `values_agree()` compared
storage-agnostically across *everything*, so `45` and `"45"` agreed. Now `type_family()` returns
`number` (numeric/logical), `string` (character/factor), or the class name -- and a cross-family
pair is a **distinct error naming both classes**, not a disagreement count, because nothing
disagrees in value. Returning the class name for everything else means `Date`, `POSIXct` and list
columns each become their own family and mismatch for free, so no separate atomic guard is needed.
`TRUE` vs `1` still agrees, deliberately: that is `Female`'s storage, not its value.

---

## 2026-07-31 -- building the finalizers: `calc_accel`, no `collapse`, and what the record's pheno cannot answer

Built the surface designed in the entry below (`R/calc_accel.R`,
`tests/testthat/test-clocks-accel.R`). Five things came out differently once it was code, so the
entry below states the design and this one states the build. Always-on suite: 1008 pass, 0 fail,
260 skip. Parity not run; `R CMD check` not run.

**The verb is `calc_accel()`, not `clock_accel()`.** The finalizer family is already
`clocks_coverage()` / `samples_coverage()` -- plural noun, then the quantity. A singular `clock_`
would have been the only one, and the frame is one row per (sample, clock) anyway.

**No `collapse` dependency.** The plan added it for `pivot()` and `join(validate = "1:1")`, and
both evaporated: keeping the whole pipeline matrix-native (`$scores` in, an NA-filled matrix of the
same shape out, `shape_scores()` choosing long or wide once at the end) makes the long/wide exit
five lines of `rep()` and makes the residual rejoin **positional by construction** rather than a
runtime join whose 1:1-ness has to be validated. A dependency that buys nothing base R does not do
in three lines is bloat regardless of how much we like the package; `collapse` stays available for
a future path (`HDW()`) where it would earn its place. This also means `clock_id` is a character
column, not the factor `pivot()` returns.

**`check_pheno()` gained nothing; its NA hint got shorter instead.** The plan wanted a caller-noun
argument so the message could say "score NA" for `calc_clocks()` and "dropped from the fit" for
`calc_accel()`. Built that, then removed it: the two consequences are the same consequence
("Those samples will score NA"), and a format-string parameter to distinguish them is machinery in
place of one general sentence. The **missing-column** message is a different matter and does live
in `calc_accel()`, because `check_pheno()`'s hint ("add it to `pheno`") would send the caller
back to re-score when the fix is `data =`.

**The `$pheno` narrowing stands, and the reason is stronger than the one in CLAUDE.md.** Proposed
widening `resolve_pheno()`'s `keep` to retain every supplied column, on the grounds that discarding
a user's `Age` is a silent discard and that `~ Age + <cell counts>` is the realistic accel formula.
Declined, correctly. `$pheno` does not exist to remember what was fed in -- it exists to remember
**what went into the numbers**. `Age` and `Female` are on the record because the clocks consumed
them, which is exactly what gives `merge_accel_data()`'s conflict check something real to defend:
it can refuse a `data` that would residualize on a different `Age` than the one that produced the
score. Widen it and `$pheno` becomes a general covariate bag, the conflict check starts guarding
columns no score ever saw, and the footgun it exists to prevent comes back. A covariate the scoring
did not use is the caller's to carry, and `data =` is where it goes. (The costs of widening, for
the record, were also real: a new `rbind` gate on pheno columns, and `print.mc_result` cutting the
pheno block instead of printing every column. Neither was the deciding argument.)

**So `calc_accel(res)` failing on a covariate-free record is the design, not a papercut.** The
error names `data =` and that is the whole fix.

**`type = "diff"` with an rhs that spans `Age` is exactly `type = "accel"` on that rhs.** Subtracting
a column of the design from the response changes the coefficients and leaves the residuals
identical, so `diff` + `~ Age` and `accel` + `~ Age` agree to floating point. The
constrained-vs-estimated distinction the design turns on is real but only bites when the rhs does
**not** span Age -- `~ Female`, say, where `diff` fixes the age slope at 1 and `accel` never sees
Age at all. A test asserted the two always differ and failed, correctly. The test now pins both
halves: equal on `~ Age`, different on `~ Female`. Do not "fix" the equality case by special-casing
`diff` -- it is linear algebra, and a `diff` that disagreed with `accel` there would be wrong.

**Also:** `expect_warning(x <- expr)`, never `x <- expect_warning(expr)`. testthat returns the
*condition* when one is caught, so the second form binds a condition object; `acc$SomeClock` is
then `NULL` and `all(is.na(NULL))` is `TRUE`, which is how a degenerate-clock test passed
vacuously here before it was caught.

---

## 2026-07-31 -- the finalizer family: no `augment`, `clock_accel` instead, `data` adds but never changes

**Design decision, nothing built.** Recorded now because the shape was argued out in full and the
reasoning should not be re-derived. Ideas were collected from PR #3 (`dev/pr3-triage.md` sec 4.4,
D1-D3); **no code is being taken from it** -- this is a clean re-implementation, and the surface owes
the PR about two things (the `na.exclude` hazard, and clash detection on a user covariate frame).
This entry settles `dev/pr3-triage.md` sec 5.4: D1 and D2 are in, D3 (`codebook`) stays out --
it touches no result, reads a `bib_key` that does not exist, and is a third view of `list_clocks()`
/ `clock_cpgs()`.

**`mc_result` is the canonical class, so every data.frame-returning function is a *finalizer*** --
a one-way exit. Past it you have no `rbind`, no `refinalize_clocks()`, no coverage, no provenance,
and re-binding what you got is the caller's problem. This is not a new contract: `clocks_coverage()`,
`samples_coverage()` and `as.data.frame(cite_clocks(x))` are already finalizers by this definition.
Naming it is what makes `as.data.frame.mc_result` an ordinary member of an existing family instead
of a novel API decision -- and it means **no finalizer needs a guard**. No `force =`, no round-trip,
no re-attaching a class on the way back.

**No finalizer's output contains another finalizer's output.** Each returns join keys plus its own
payload; the caller joins. This is the rule that kills `augment()`, and the argument is not merely
that `augment(x)` duplicates `as.data.frame(x)` -- it is that the nesting *grows*: add `_resid`, a
second `adjust` set, a `_diff`, and the frame doubles each time while the id and score columns repeat
verbatim. Applied to the derivative verb it also settles what comes back: `clock_accel()` returns id
+ clock + acceleration and **not the covariates it fit on**. `Age` and `Female` are inputs, not
payload, and the caller already holds the frame they came from.

**`augment` was also the wrong name twice over.** `generics::augment` is a real S3 generic
re-exported by broom and every tidymodels package, so a bare `augment <- function(x, ...)` is masked
the moment a user attaches broom afterwards, and the call then dispatches to broom's generic, finds
no `mc_result` method, and errors -- the same collision that made `cite_clocks()` a package-owned
name (2026-07-23, 2026-07-24, 2026-07-25). Beyond the collision, broom's `augment` is singular
because there is one model and one `.fitted`; here the derived quantity is plural and parameterized.
Splitting the join from the derivative lets the derivative be named for what it does.

**`type` sets the response; `formula` sets the right-hand side.** That factorization is the whole
signature: `type = "accel"` with no formula is `resid(score ~ Age)`, the classic; with a formula it
is the residual on that RHS; `type = "diff"` is `score - Age` with no fit at all; `type = "diff"`
plus a formula is `resid((score - Age) ~ ...)`. The last is **not** redundant with the second and
must not be "simplified" away -- constraining the age coefficient to exactly 1 is a different
estimator from estimating it, and the constrained one is a real (and contested, re: regression to
the mean) choice in this literature. `diff` is expressible as a formula in principle
(`resid(lm(score ~ 0 + offset(Age)))` is exactly `score - Age`) and is not offered that way: nobody
reads `~ offset(Age)` as a subtraction, dropping the `0 +` silently yields something else, and a
projection routine will not honour `offset()`. The structural reason is stronger than the ergonomic
one -- **accel is cohort-relative and diff is per-sample**, so diff alone is stable under subsetting
and under `rbind`, and that is the one distinction a reader must see at the call site.

**`type = "diff"` with no formula is identity, not `~ 1`.** `resid(d ~ 1)` is `d - mean(d)`, which
would silently re-introduce cohort dependence into the one arm that does not have it.

**`data` may add a column; it may never change one.** `$pheno` is `unique(c(pheno_id, covariates))`
where the covariates are the ones the run *actually required*, so every non-id column of it is by
construction a value that was fed into scoring. A `data` column that disagrees therefore disagrees
with a scoring input, and residualizing on an `Age` the score was not computed from is incoherent.
Three consequences, no clauses: absent from `$pheno` -> added; present and equal -> silent, `$pheno`
wins; present and different **including NA-vs-value** -> error, pointing at `calc_clocks()`.

The first cut allowed `data` to fill where `$pheno` was `NA`, on the argument that such a sample
either scored `NA` anyway or its clocks never read the covariate. **Rejected: under that rule the
same value has two different roles in one call, and which role depends on which clock you look at**
-- for an Age-needing clock the fill overrides an input that produced `NA`, for an Age-free clock it
supplements a score that never touched it. No rule stated in one sentence can mean both. Scoring is
cheap enough that "re-run `calc_clocks()` with the corrected pheno" is the honest answer, and it is
the same line `rbind` already takes: bind and label, never reconcile, and no `force =`. Nobody is
prevented from anything -- a caller can rebuild the frame in two lines -- we decline to launder it
through the machinery.

Two details this rests on. **The comparator is tolerance-based and storage-agnostic, never
`identical()`**: a pheno re-read from CSV gives integer `50L` where the in-memory one had double
`50`, and `identical()` would hard-error the modal workflow (score with `pheno`, add `Female`, pass
the same frame as `data`) over a difference that is not one. This is the same reasoning as
"never `expect_identical()`, always `expect_equal()`". And **the conflict check is *not* scoped to
the formula's variables** even though everything else is -- a disagreeing `Female` means some scores
were computed from a different `Female` whether or not this call reads it, and scoping would make one
`data` frame acceptable in one call and refused in another, which is exactly the clause-dependent
behaviour the NA-fill rejection removed.

**Two NA drops, different scopes, and neither is `na.omit()`.** The covariate set is exactly
`all.vars(formula)` (plus `Age` for `type = "diff"`) -- `na.omit()` on the frame would drop rows
whose `Female` is `NA` on a `~ Age` call, where `Female` is irrelevant. The pheno drop is **global**
(one eligible sample set, applied before the pivot, so no clock is ever fit against a covariate row
another clock did not see); the score drop is **per-cell**. Order is: drop pheno NA, pivot long, drop
score NA, inner join. That is the same cell set as one `complete.cases()` over the long frame, and it
is written as two steps because the two counts are separately meaningful and separately reported.

**Fit sets are per-clock and are deliberately not unified.** A clock with `NA` scores is fit on
fewer rows, which is honest -- its residual is genuinely relative to the vector that exists. The
alternative (drop any sample `NA` in *any* clock, so residuals are cross-clock comparable) is
rejected because one degenerate clock -- a pack clock `NA` for half the cohort -- would then silently
shrink every other clock's fit set. One bad column must not move Horvath's residuals.

**Consequence to document, not to fix: `accel` is `NA` on a superset of where `score` is.** Worked
example, n = 100, 5 samples with `Age = NA`, GrimAge (needs Age) also 3 coverage-NA, Horvath 2
coverage-NA. Both drop the same 5 globally; GrimAge fits 92, Horvath 93. Horvath's acceleration is
`NA` for 7 samples but its *score* is `NA` for only 2 -- the other 5 have a good score and no
residual because their covariate was missing. A reader seeing a score with no acceleration will
otherwise assume scoring failed.

**Drop-upfront makes `na.action` moot, so use `na.fail` as a free assertion.** The classic
misalignment trap is that `resid()` returns one value per complete case and assigning it into a
full-length column shifts everything; `na.exclude` patches that by padding back out. Having already
dropped the incomplete rows, the residual is length- and order-matched by construction, so nothing
depends on `na.action` semantics -- and setting it to `na.fail` turns any NA that slips through into
a loud error instead of a silent shortening. The rejoin is a left join on `(id, clock_id)` with
multiplicity validated `1:1`; a fan-out is the one remaining way this pipeline could misalign.

**Degenerate clocks yield `NA` and one aggregated warning.** All-NA (zero rows after the drop, `lm`
errors) and `n <= p` (`lm` returns aliased `NA` coefficients rather than erroring, and the residuals
are meaningless) are both caught by a row-count check before the fit. One warning naming the affected
clocks -- 121 separate warnings would be unusable.

**`check_pheno()` is reused rather than re-implemented**, with `extra_columns = all.vars(formula)`.
It already errors on a missing required column, type-checks `Age` (finite numeric) and `Female`
(integerish 0/1) for free, and warns with a per-column count of NAs over the id-joined rows -- which
is the global pheno drop, reported without new code. Two of its strings are clock-specific ("columns
the requested clocks need", "Clocks that need them will score NA") and need a parameterized noun,
safe to change since the test rule forbids asserting wording.

**`long = TRUE` is the uniform default across the family**, including `as.data.frame.mc_result`;
`as.matrix()` is the wide exit for scores. Per-function "natural" defaults were considered and
dropped -- a shared argument whose default flips per function is worse than no shared argument.
Long is also the computation form: one response name makes `reformulate(vars, response = "score")`
uniform across every clock, the per-cell NA drop is a single row filter, and the id survives so the
rejoin is exact.

**Fit N is derivable, so it is not stored.** It is the count of non-`NA` `accel` per clock. Storing
it would breach the no-nesting rule and it cannot be a column in the wide shape anyway.

**`collapse` is accepted as a dependency** -- `pivot()` for the long/wide exit, `join()` for the id
joins, and `HDW()`/`fHDwithin()` as the eventual fast path for linear residualization. Its NA/`fill`
semantics must be verified against a hand-rolled `lm` on a small case before it is used for the fit;
until then `split` + per-clock `lm` is the baseline. That loop rebuilds the model matrix once per
clock, which at this package's scale is about a second and not worth optimizing -- and the escape is
not a rewrite, since `lm` accepts a **matrix response**, so grouping clocks by distinct missingness
pattern gives one QR per pattern (one fit total in the common case) through the same
`residuals()` call.

Still open: nothing blocking. `type = "diff"` needs `Age` spelled exactly that way (the catalog's
only spelling; 25 clocks require it, 16 require `Female`) and gets its error from `check_pheno`
rather than a bespoke check.

## 2026-07-31 -- the paper's fields ride `mc_citations`; the runtime never parses BibTeX

`sync.R` now parses the vendored `clocks.bib` and widens the citation join with the paper's own
fields (`title`, `author`, `year`, `journal`, `volume`, `number`, `pages`, `doi`, `url`), so
`as.data.frame(cite_clocks(x))` is 13 columns instead of 4.

**No information was ever lost -- only its shape.** `bib_entries()` already read every entry
verbatim and `toBibtex()` already round-tripped it complete, fields and all. What did not exist was
a *tabular* view: `$links` is the clock -> paper join (`clock_id`, `pmid`, `role`, `bib_key`), which
answers "which paper" and not "what is that paper". Anyone wanting to sort by year or pull a DOI had
to regex the BibTeX text themselves.

**Parsed at sync, not at read.** The alternative was an `as.data.frame(x, expand = TRUE)` that ran
the extraction on demand. That puts a regex parser in the read path to recover data the build
already had in hand, which is the shape of thing "accessors read declarations; they never search"
exists to prevent. The `.bib` is vendored at sync time, so parsing it there keeps every runtime read
a lookup. Cost is 9 columns x 128 rows denormalized across 41 distinct papers -- immaterial in
`sysdata.rda`.

**The layout is read as declared, never searched.** `clocks.bib` comes from upstream's
deterministic emitter (`scripts/lib_bib.py`, `write_clocks_bib` / `format_entry`), gated by
upstream's own round-trip probe: one field per line, two-space indent, ` = {` assignment, values
collapsed and never wrapped. `read_bib_fields()` parses exactly that and `stop()`s on any deviation
-- unindented, over-indented, wrapped, unclosed, duplicated field, duplicate key, missing required
field. The first cut regex-mined each field out of the entry blob and was replaced: **a tolerant
per-field search cannot tell "field absent" from "layout moved"**, and `volume` / `number` are
legitimately absent on some entries, so drift would have shipped a table of NAs instead of failing.
This is the same rule as "accessors read declarations; they never search", applied at sync.

**Three ways it fails loudly.** A cited `bib_key` absent from the `.bib`; the two independent `pmid`
copies (`clock_citations.csv` and the entry) disagreeing; and any field in `BIB_FIELDS` appearing on
**no** entry at all. That last one is not redundant with the per-entry required-field check:
`BIB_REQUIRED` is only `title`/`author`/`year`/`pmid` because the entry *type* is deliberately not
asserted -- a `@misc` may legitimately carry no `journal` -- so a wholesale rename upstream
(`journal` -> `journaltitle`) passed every per-entry gate and produced an all-NA column. Measured:
it silently NA'd all 43 entries. Presence-somewhere is the strongest claim that holds without
pinning the type. Contrast PR #3's `bibliography()`, which synthesized a placeholder
`@article{key, pmid, url}` for a missing key and so hid exactly the gap worth hearing about.

The strict rewrite is **output-identical** to the regex version on the shipped bibliography
(`identical()` on all 128 rows), so it needed no `sysdata.rda` regeneration.

`pmid` is parsed but not attached -- the join already carries it, and a second copy would be a
column that can disagree with its neighbour. `volume` (6 rows) and `number` (10) are `NA` because
those papers declare neither upstream; every other field is complete across all 128 rows.

---

## 2026-07-30 -- The batch label is derived from the sample ids, and `batch =` is gone

Reverses this same day's "labels are assigned, never derived" and the `CLAUDE.md` line "never hash
anything to make one". `$pheno` is now always materialized, `calc_clocks(batch =)` is removed, and
`construct_mc_result()` derives the label as `batch_hash(pheno[[pheno_id]])`.

**What the assigned label cost.** The sticky-vs-auto rule needed `is_auto_label()`, which
re-derives the caller's *intent* from the label's spelling (`^[0-9]+$`). Nothing in a string can
carry that, so `batch = "2024"` twice silently renumbered to `2024, 2025` while `"T1"` twice threw
-- a wave/year label is the obvious thing to pass and the one that misbehaved. The collision error
also dead-ended: it said "give argument 2 a different name", and doing so hit
`apply_arg_name()`'s refusal to rename a non-auto label, with no way out but re-scoring. Both are
symptoms of storing a label without storing whether a human chose it.

**Deriving it removes the policy rather than fixing it.** A label that is a function of the
record's own ids is stable under re-association by construction: `rbind(rbind(r1, r2), r3)` and
`rbind(r1, r2, r3)` now return `identical()` records, where before the right-hand side renumbered.
So `rbind` mints nothing, renames nothing and renumbers nothing -- `DEFAULT_BATCH`,
`is_auto_label()`, `check_batch_label()`, `next_auto_label()`, `apply_arg_name()`,
`resolve_labels()` and `batch_maps()` all deleted, and the old "sticky name collides loudly" error
with them.

**`rbind` argument names are dropped, not refused.** Refusing them was tried first and reverted the
same session: `split()` names its result by factor level, so
`do.call(rbind, lapply(split(seq_len(n), g), score))` -- the canonical blocking idiom, the workflow
this feature exists for -- died on a wall of `"1", "2", ... "50"`. That is the `is_auto_label()`
mistake again in a new place: a name on `...` no more carries "I meant to label a batch" than a
digit-shaped string does. Names arrive from `split()`, `setNames()` and `Map()` for reasons that
have nothing to do with batching, and those cases outnumber a hand-typed `rbind(early = r1)` by far.
There is no way to tell the two apart -- `do.call` builds a call carrying the names either way --
so a warning would fire mostly on correct code. `unname(list(...))` and nothing else.

**Why the id column and not `$pheno` whole.** Hashing the pheno frame was the original proposal
and is wrong twice over. Before this change `resolve_pheno()` returned `NULL` whenever no pheno was
supplied -- 95 of 120 callable clocks require no covariate -- so *every* such batch hashed
identically and k batches would have collapsed onto one `per_clock` key, silently merging exactly
the per-batch fill regimes the batch axis exists to keep apart. Materializing `$pheno` fixes that,
but hashing the whole frame then folds covariate *values* into batch identity: correcting one
subject's age renames the batch, and `digest` is sensitive to column storage type, so the same CSV
read with integer vs double `Age` hashes differently. The id column has neither problem and answers
the question the label is actually asking -- *which samples were scored together*. In the 95/120
no-covariate case the two are byte-identical anyway.

**Rejected reasons, revisited.** 2026-07-30 rejected id-set hashing on cost, not soundness (it
says outright "hashing the id set is the only sound one"): a `digest` dependency, hex in the two
frames people read, and the `batch_set_id` non-goal. The first is paid (`digest` Suggests ->
Imports; it was already a Suggests). The second is handled by moving `batch` to the **end** of
`clocks_coverage()` and `samples_coverage()` -- it is still the key those frames join on, it just
no longer sits in front of `clock_id` where it reads as noise. The third stands as written and is
the part being reversed: the ban existed to stop anything *joining* on a content-derived id, and
`samples_coverage()` already joins on `batch` regardless of how the label is produced, so deriving
it changes what the label costs to compute and not what it is used for.

**The hashed value is canonicalized, and that is not optional.** `digest(ids)` hashes the id
*sequence and its R representation*, not the id set: reversing three ids, naming them, or handing
in a factor each produce a different label, so re-scoring a block after sorting its rows would
silently relabel it. `batch_hash()` therefore hashes
`paste0(sort(unname(as.character(ids)), method = "radix"), collapse = "\r")`. Every piece is
load-bearing -- `sort` makes it a function of the set, `method = "radix"` keeps that
locale-independent (plain `sort()` collates per-locale, so two machines would disagree),
`unname`/`as.character` drop attributes, and `serialize = FALSE` hashes the bytes so no R
serialization version reaches the label. A batch label appears in published
`clocks_coverage()` output, so it has to survive a change of machine.

Width is 12 hex of `xxhash64` (48 bits). Gate 1 makes the id sets disjoint, so a shared label needs
a real collision: **1.8e-11 at 100 batches, 1.8e-9 at 1000** (birthday bound; an earlier revision
of this entry said 1e-13, which was wrong by ~100x). 200k distinct inputs collided zero times when
measured. Since there is no longer a gate on labels, a collision would be silent -- the trade is
accepted at these numbers, and the fix if it ever mattered is to widen the truncation, not to
re-add the gate. `xxhash64` is non-cryptographic, which is fine here because sample ids are not
adversarial.

**Two unreachable guards were cut rather than kept "just in case."** A `gate_distinct_batches()`
and a partial-`pending` "package bug" stop were both written and both deleted the same session,
39 lines between them. Neither can fire: the first needs the 48-bit collision above, the second
needs two records with equal `$provenance$clocks` and different `spec$cross_sample`, which cannot
happen because `covariates`/`cross_sample` are functions of the clock sequence that gate 2 pins
(measured: `GrimAgeV1` vs `c("GrimAgeV1", "DNAmADM")` give identical output columns *and*
identical pending keys). The rule they now follow is the one that also deleted `gate_same_pheno()`'s
column check and rejected a `covariates_used` gate: **a guard on something an earlier gate makes
impossible is deleted, not kept.** Keeping some and cutting others left no statable principle, and
"which unreachable guards do we keep" is exactly the per-guard re-litigation the "one line decides
every gate" framing exists to stop. If a cross-sample clock ever becomes a routing target, gate 2
stops pinning `cross_sample` and the second guard becomes reachable -- add it back then, with a
test that fires it.

**`$pheno` is always present now.** With none supplied it is the id column alone, which reads
*closer* to the standing invariant ("the aligned pheno narrowed to the id column plus the
covariates the run required") than `NULL` did -- `NULL` carries no id column at all. This also
kills two things: `print.mc_result`'s `is.null(pheno)` branch, and `gate_same_pheno()`'s carried-
column check. That check is now unreachable -- `names(pheno)` is `unique(c(pheno_id, covariates))`
and `covariates` is a pure function of the clock sequence, which gate 2 pins -- so it is deleted
for the same reason the "same id, different covariates" gate was deleted this morning, leaving
`gate_same_pheno_id()`.

**`sim_DNAm(batch =)` is renamed `suffix =`, not removed.** It never labelled anything: it
suffixes the sample ids (`sample1_T1`) so two simulated blocks are disjoint by construction and
clear gate 1. That job is still needed and is now the *only* thing the caller controls about
batching, so it stops sharing a word with the derived label. `$batch` on the returned `mc_sim`
becomes `$suffix`.

---

## 2026-07-30 -- Phase 4 gates: refuse what the caller chose, record what batching forced

Settles the `rbind` design, which then shipped in the same session (`R/bind.R`, `test-bind.R`).
Narrows sec 8's four gates to four different ones and reverses two things sec 8 said.

**The line that decides every gate.** Sec 8 already said "record, never refuse, on differing fill
regimes", but did not say what that generalizes to, so each new question re-litigated it. It is:

> **Record what batching forces. Refuse what the caller chose differently.**

A per-batch fill regime is *forced* -- cohort means are per-run by construction, so a batched user
cannot avoid it and refusing would refuse the whole feature. Every other difference between two
records is a free argument with one obviously right answer across batches, so a difference is a
mistake and the bind says so. An earlier framing, "refuse on ambiguous identity, record on differing
method", was rejected: it puts `normalize=` on the record side, and `normalize=` is exactly the
caller choice that should be refused.

**The gates, and why there are four of them and not sec 8's four.**

1. **Disjoint ids**, checked as `anyDuplicated()` over the concatenated `$provenance$sample_id` --
   **not** over the pheno id column. `$pheno` is `NULL` whenever the run required no covariates,
   which is most runs, so a pheno-side check silently checks nothing exactly where the exposure is
   worst.
2. **Identical score columns**, reordered to the first record or thrown. This **subsumes sec 8's
   gate 3** (comparable coverage denominators): `output_ids` is the compute sequence minus routed
   members and the sequence is a deterministic function of the requested ids, so identical columns
   implies identical sequence implies identical panels. One gate, not two.
3. **Identical `pheno_id`.** Sec 8's gate 4 also required "no id appearing twice with different
   covariates", which is dead as written -- gate 1 forbids an id appearing twice at all.
4. **Identical `$provenance$normalized`.** New. Two records with the same clocks but different
   `normalize=` pass gates 1-3 with identical columns and identical *scoring* panels, while
   `Horvath1` measured 0.114 vs 7.715 absolute against the oracle depending on the setting
   (2026-07-29). The experimenter comparing normalized against raw is **already refused by gate 1**
   -- same samples scored twice, so the ids collide -- and wants the two columns side by side
   anyway, not stacked under a batch label. So the only caller who reaches this gate is one whose
   loop varied the argument across chunks, which is a bug.

**Refusing on overlapping ids is not over-strict.** A warning does not help: the double-count lands
in the *mean and sd*, so a z-score or an age-acceleration residual over the bound record is wrong
for every sample, not just the duplicated ones. After the bind, "one sample scored twice" and "two
samples sharing a name" are indistinguishable, so there is nothing to record instead. The fix is one
line user-side (`rownames(DNAm) <- paste0(rownames(DNAm), "_T1")`) and is the same relabelling the
caller's own downstream analysis needs. No `force =`, and no comparing record *contents* to detect
that two arguments are literally the same record -- the id sets are the whole test.

**Batch labels: no hash, and no stored counter.**

Hashing was considered in three forms and all three are rejected. Hashing `$pheno` cannot work:
`resolve_pheno()` narrows it to the id column plus required covariates, so it is `NULL` or exactly
`data.frame(ID = ids)` for any request with no covariates, and every such batch hashes the same;
where it *does* differ it folds covariate values into batch identity, so correcting one subject's
age silently renames a batch. Hashing the **fill regime** (`partial_fill` + `usable_cols`) is
float-brittle -- 2026-07-24's chunk-invariance measurement already found last-bit drift from
`dgemm` blocking alone -- and collides on the case that matters, two clean matrices over the same
CpG set. Hashing the **id set** is the only sound one (gate 1 makes collision impossible), but it
promotes `digest` from Suggests to Imports for a naming problem, prints hex into the two frames
people read, and is a `batch_set_id` -- the one thing the plan's non-goals name.

A stored counter field is rejected for a different reason: `$provenance$batch` is already a
per-sample vector, so the labels present **are** the counter and the next one is
`max(as.integer(labels)) + 1`. A separate field's only possible behaviour is to drift out of sync
with the vector it summarizes.

So the label is assigned, not derived:

- a user-supplied name (`calc_clocks(batch = "T1")`, or the `rbind()` argument name, which
  `do.call(rbind, named_list)` supplies for free) is **sticky** -- never renumbered, and two records
  claiming the same name throw, because that collision was deliberate;
- otherwise the next free integer, **renumbered on collision**.

`sim_DNAm(batch =)` is the same word doing a different job and is worth not confusing: it
**suffixes the sample ids** (`sample1_T1`) so two simulated batches are disjoint by construction,
and it defaults to `NULL` rather than to an integer, because a default would rename every sample in
every existing call. Threading it also collapsed a latent bug -- `ID` and the matrix rownames were
two independent `paste0("sample", seq_len(n))` expressions that happened to agree.

**Renumbering is safe only because the label is not a key.** `rbind(rbind(r1, r2), rbind(r3, r4))`
brings two sides both carrying batches `{1, 2}`; the right-hand side is renumbered to `{3, 4}`. That
shifts a name and never a row's group, so the partition is preserved -- which is exactly what the
"a batch label is not a `batch_set_id`" non-goal buys. The left-to-right folds
(`Reduce(rbind, ...)`, `do.call(rbind, ...)`, flat `rbind(r1, r2, r3)`) never renumber at all, and
a user who cares about stable labels names them.

**Two things in sec 8 were wrong and are rewritten, not annotated.**

- "Chunk reassembly labels every row one batch" predates the park. It was true when chunk
  reassembly meant the Phase 6 front end, which shares one fill regime across blocks. Post-park
  `rbind` **is** the chunking path, so k records are k batches -- which is precisely why the
  per-block offset has to be recorded.
- Sec 8's gates 3 and 4 are subsumed and half-dead respectively, per above.

**Coverage nests by batch.** `$coverage$per_clock` becomes batch -> clock -> record on **every**
record, single-pass included, and `clocks_coverage()` becomes one row per (clock, batch) with
`batch` leading. Merging was rejected: `score_imputed_partial` counts the panel CpGs in *that run's*
partial cache, and two independently-scored batches almost never share an NA pattern, so a merged
figure would be wrong on nearly every bind rather than in a corner case. The counts stay CpG counts
on the CpG axis; what changed is that the CpG axis is now indexed by batch. This is also what
satisfies sec 8's "per-batch imputation summary" without a hash -- two batches with different fill
regimes are visibly different in `clocks_coverage()` whether or not their labels say so.
`samples_coverage()` carries a `batch` column too. It is redundant against `id` (gate 1 makes the
id determine the batch) and exists anyway, because without it the long frame cannot be joined to
`clocks_coverage()` on the key that frame is now on.

**Not defended against: pack version drift.** Two records scored against different pack payloads
have identical columns and different coefficients, and it is undetectable -- `payload_hash` is
maintainer-side and deliberately never reaches a record (2026-07-24). Reversing that to make one
gate possible is not worth it; a package that moves breaks reproducibility by many other routes.

**Retaining `pending`.** It lands on `$provenance$pending`, keeping the record's four top-level
elements as `CLAUDE.md` states them. It is built **with** `rbind`, not before: retention only pays
off at bind time, so landing it early would add a field to the public record with no consumer.

## 2026-07-30 -- Phase 6 is parked; `rbind` covers the realistic case

Reverses the entry below it, which made the store mandatory and Phase 6 next. **Nothing in sec 5 is
deleted** -- it stays as the record of what was measured -- but the streaming front end is no longer
scheduled, and Phase 4 takes its place as the next thing built.

**The projection number, measured off the committed catalog.** 87 bundled callable clocks: panels
sum to 32,228 and union to **20,430** scoring CpGs, or 38,540 including the 21,368-probe BMIQ norm
panel. Against an 866k array:

| n | full array | projected union | x3 copies |
|---|---|---|---|
| 1,000 | 6.45 GB | 0.15 GB | 0.46 GB |
| 10,000 | 64.5 GB | 1.52 GB | 4.57 GB |
| 50,000 | 322 GB | 7.61 GB | 22.8 GB |

So a request for **every bundled clock is resident past any cohort that exists** on the 4-8 GB box
sec 5 targets. The entry below drew the same conclusion and then built for the exception anyway.
(The PC-scale panel sizes it quotes -- 357,852 for PCBrainAge and so on -- were not re-verified
here; the catalog does not carry `n_cpgs` and the packs were not staged.)

**The premise that fell is gzip.** The store was mandatory because a `.csv.gz` cannot be seeked, so
two passes meant two whole-stream deflates. But anyone with a cohort genuinely too big to hold does
not have a `.csv.gz` -- they have HDF5, Zarr or TileDB, because that is what an append-capable store
is. On a random-access source two passes are free and the store has no remaining justification, and
with it go the ingest contract, the lifecycle/consent surface for an 80 GB user-data object with no
default location, and sec 5.8's blocking benchmark.

**What is actually left, and why it is niche.** One case: a cohort too big to hold *even projected*,
**carrying NA**. The NA is load-bearing -- cohort-mean fill is the only thing sample-blocking can get
wrong, so on a complete matrix a user-side loop is already exact. That conjunction (too big to hold
projected AND missing values AND, in practice, a PC-scale panel) is rare enough not to lead a
roadmap.

**What covers the rest: Phase 4.** A user with a random-access store can already project
(`clock_cpgs()` ships), block, and score; the only missing piece is assembly. Two notes carried into
sec 8:

- Per-batch cohort means are a real difference but second-order as noise (block mean unbiased,
  SE `sd/sqrt(n_block)`). The mechanism worth naming is a probe all-NA within one block but partial
  cohort-wide: that block takes the vendored ref while others take the cohort mean, which is a
  systematic per-block offset, not noise. `rbind` cannot undo it -- the batch label is what makes it
  honest.
- **Cross-sample re-finalization can be exact, which sharpens the "do not re-finalize" rule rather
  than reversing it.** `physage_raws()` is per-sample, so if a record *retains* `pending` instead of
  discarding it after `finalize_cross_sample()`, a bind-time re-finalize reproduces the single-pass
  number rather than approximating it. Still opt-in and still never silent, since it rewrites a
  column the user has already seen, and it keys on `spec$cross_sample` rather than on PhysAge.

Also settled while measuring, and recorded because it outlives this reversal:

- **Bioconductor keeps phenotype out of the HDF5 by design.** `saveHDF5SummarizedExperiment()`
  writes `assays.h5` (assay datasets only, not even dimnames) plus `se.rds` holding colData,
  rowData and dimnames. Dimnames are a `writeHDF5Array()` convention -- `.<name>_dimnames/1` and
  `/2` plus a `DIMENSION_LIST` attribute -- and rhdf5 cannot read that attribute (`VLEN not yet
  implemented`), so the naming convention is the contract and the attribute is decoration. Any
  future HDF5 support adopts that layout rather than inventing one, and pheno stays an R argument.
- **The float32 non-goal is wrong as written.** "No float32 anywhere on the input path" justified by
  `PARITY_REL_TOL = 1e-10` conflates input storage precision with arithmetic precision; that
  tolerance bounds our agreement with an oracle given identical inputs. Refusing float32 input
  declines to score data whose precision was already fixed before we saw it. The rule that does the
  intended work: promote to float64 on read, never compute or store intermediates in float32.

## 2026-07-30 -- the duckdb store is mandatory, not scratch; the resident set is the panel, not the file

Sharpens 2026-07-29 rather than reversing it: duckdb stays the access engine, but the **ingest step
is promoted from a request-scoped `tempdir()` convenience to a required stage**, and the reason is
stated differently.

**The target this is built for.** A small box -- 2-4 cores, 4-8 GB RAM, i.e. a cheap AWS partition
or a laptop -- against a tall `.csv.gz` far larger than RAM, with no ETL the user has to run
themselves. On that box the run is **deflate-bound and serial**: gzip inflate is whole-stream and
single-threaded, so it is the floor no amount of cores moves. That is the whole reason chunking
exists here; if the data fits in memory the question is moot.

**Projection is the first lever, and it was missing from the plan.** Only `needed_cpgs x n_samples`
has to be resident, never the file. Against a 1e6-probe array at n=1e4 (80 GB as doubles) the 101
bundled panels union to 39,025 probes = 3.1 GB. So a 1e6 x 1e4 file scores on an 8 GB box with
*nothing* streaming, and what forces chunking is **requesting a PC-scale panel, not cohort size** --
PCBrainAge's 357,852 probes is 28.6 GB. The sizing table is in the plan (sec 5).

**Why the store is mandatory: gzip is whole-stream, a columnar store is per-page.** A `.csv.gz`
cannot be seeked, so every pass over it re-inflates and re-parses the entire file regardless of how
little that pass needs. Since cohort-mean fill makes two passes non-negotiable (plan sec 2), the
choice is between paying the deflate twice per request or ingesting once. The store is what converts
one whole-stream deflate into per-page reads.

**A per-request projected spill was considered and rejected.** Writing only the resolved panel,
partitioned by sample block, during pass 1 is smaller (3.1-28.6 GB against ~80 GB) and free as a
byproduct of that pass. It loses because the panel depends on the clock request, so it re-deflates
the source **once per request** -- and the realistic session is a sequence of requests over one file
(bundled clocks, then a PC clock added, then a re-run after a pheno fix). One deflate ever beats one
deflate per request, and 80 GB of scratch disk is the cheap side of that trade.

**duckdb, not parquet.** Maintainer's call on two grounds: duckdb handles the wide schema (1e4+
sample columns) better than parquet's per-column-per-row-group footer metadata, and a `PRIMARY KEY`
on the CpG id gives a real index plus an ingest-time duplicate-probe check. **This is a decision, not
a benchmark** -- parquet was not measured at that width, and neither was duckdb (see below).

**Five corrections found while deriving this**, all now in the plan:

1. **The block-width formula was off by ~3x.** Sec 5.3 divided the budget by one copy of the block.
   Peak is three: the block, `build_partial_cache()`'s slice, and `pack_design()`'s `n x |panel|`
   copy. The cache is not a sliver -- at any realistic NA rate nearly every column carries at least
   one NA, so it is a full second copy.
2. **Projecting first would silently redefine `sample_scale`.** `scan_missing_cpgs()`'s row moments
   span *every* column of the matrix, and the two Zhang2019 arms z-score each sample over the whole
   array; substituting the panel union was measured at 1.8e1 absolute / 82% relative. So pass 1's
   probe filter is on **iff `spec$needs_moments` is FALSE**.
3. **duckdb's `avg()` does not treat `+/-Inf` as missing; `col_stats()` does.** A SQL route to the
   per-sample moments therefore disagrees with the kernel on a file carrying an `Inf`, and needs the
   value gate ordered ahead of it. The kernel gives them in the traversal pass 1 already performs.
4. **`pheno` is not the id source** -- it is `NULL` for any request with no covariates. Sample ids
   are the header, which is a real simplification: under the tall orientation id uniqueness and the
   pheno subset are settled by a header-only read, not by the cross-block accumulation sec 5.4
   assumed.
5. **The expression-depth wall is about SQL arithmetic, not about width.** Returning 1e4 columns is
   fine (measured to 20,000); writing `S1+...+S10000` is not. Pass 1 asks for rows and sums them in
   `col_stats()`, so the limit never applies. Sec 5.3 said this; it reads as a workaround and is
   actually a refusal to use SQL for arithmetic at all.

**Recorded, not scheduled: probe-axis accumulation.** A pack-scored clock is a batched weighted sum,
and a weighted sum is additive over the contracted axis -- so accumulating `n x k` partial scores
over probe chunks needs ~10 MB resident at n=1e4 instead of a 28.6 GB projected panel, and would
remove sample-major blocking for exactly the clocks that need it most. The blocker is the branch
contract, not the arithmetic: "a branch returns only its score" would become "a branch returns a
partial score plus a merge rule", and every branch in the closed set would need an additivity
classification. It sits beside sample-blocking rather than replacing it, so it stays an open.

**Nothing here is measured at 1e4 samples.** Every figure above is arithmetic off the 2026-07-29
baseline (500 samples / 20k columns). Ingest carries ~10 ms per column of fixed overhead and 20,000
columns took 96.5s at only 5M cells, so a 1e4-column ingest sits in an overhead-dominated regime
nothing has been measured in. If it is bad, the fix is partitioning the store by sample block, which
changes the schema -- so that benchmark comes before the build (plan sec 5.8).
