# Decisions log (package rewrite)

Append-only, date-stamped. Records **why** we chose a design -- the "we tried X / other
maintainers will ask this" history that should not bloat an operational doc.

**Scope:** R package rewrite, packaging, API, and local maintainer workflow. Upstream
metadata contract decisions live in `data-raw/methylCIPHER-meta/control/DECISIONS.md`.

Newest first. Add an entry when a decision reverses a prior approach or is likely to be
second-guessed; do not restate rules already stated in `CLAUDE.md`.

**Archive:** entries before 2026-07-30 live in `dev/DECISIONS.old.md` (unchanged full log).
Older dated citations in `CLAUDE.md` resolve there. Do not restate that history here.

---

## 2026-08-09 -- `predict_sex()` declares its own `covariates`, because it is the reader

`covariates =` reached two front doors and not the third. `predict_sex()` forwarded it through
`...` to `calc_clocks()`, where `canonicalize_covariates()` graded it against
`spec[["covariates"]]` -- the covariates the *scored clocks* declare. Both `DNAmSex_Wang` members
declare `character(0)`, so `covariates = c(Female = "sex_f")` hit the `!length(reads)` branch and
aborted with **"this call reads no covariate"**, which is the opposite of the truth: `predict_sex()`
reads `Female`, just not through the scoring loop. The 2026-08-03 entry below had already written
down why -- `Female` is validated in `recorded_from_female()` "because nothing else does" -- so the
function was the declared reader of a covariate it never declared at its own front door.

**A formal, not a wider helper.** The alternative was to let `covariates` keep flowing through `...`
and give `canonicalize_covariates()` a way to be told about an extra read. That splits one rule
across two frames and leaves `predict_sex()`'s signature still silent about the one covariate it
consumes, so `?predict_sex` could not document it and `args()` could not show it. The formal makes
the third door declare its reads the way the other two do.

**`reads` is derived, not the constant it happens to be.**
`union(clock_covariates_required(<both members>), "Female")` is exactly `"Female"` today, because
neither member declares one. It is written as a union anyway: if upstream ever gives a member a
covariate, the derived form lets a caller point at it, and the hard-coded form would refuse a map
`calc_clocks()` would have honored. Accessors are the executable schema, and this is one accessor
read, not a spec build.

**Canonicalize once at the top, then forward `covariates = NULL`.** The rename has to run above
*every* read, because there are two: `calc_clocks()`'s pheno gates and the id-join in
`attach_recorded()`. Doing it in one place is also what fixed the second half of the defect --
`attach_recorded()` tested `!"Female" %in% names(pheno)` against the caller's raw frame, so the
mismatch comparison was silently dropped for exactly the callers who had supplied a map. Passing
`covariates = NULL` down is not defensive: it says the map is already spent, so nobody grades it
twice against a `reads` set that does not contain `Female`.

**The silence got a message, and only in the one case that is worth it.** A `pheno` with no
`Female` column now emits a `cli_inform` naming the two columns that were not built and the
`covariates` form that would build them. `pheno = NULL` stays silent, because a caller who supplied
no metadata asked for no comparison. The case in between -- metadata supplied, no sex in it -- is
the one where the argument bought the caller nothing, and the comparison is all `pheno` buys
beyond the id column.

**Unchanged, and not to be re-opened.** `predict_sex()` is still composition over `calc_clocks()`
and reads no beta matrix of its own, so the one-beta-entry-point invariant is untouched. The frozen
`calc_clocks()` API is untouched too -- the 2026-08-02 freeze was about a `sex =` argument on
`calc_clocks()`, not about this function's own signature. `Female` still does not reach `$pheno` on
a `predict_sex()` run, because the members require no covariate and `resolve_pheno()` narrows to
what the run required, so the comparison still reads the caller's frame and never the returned
value.

Always-on suite **933 pass / 0 fail / 2 skip / 0 warn**. `lint_roxygen()` and `lint_seealso()` both
empty. `NAMESPACE` unchanged -- `predict_sex` was already exported and the change is one formal.
Parity not run; `R CMD check` not run.

---

## 2026-08-08 -- The front-door value sweep is recorded, keyed by batch (QC phase 2)

**The findings existed and were thrown away.** `col_stats()` already computes the whole value
verdict in one pass -- running min and max with the column each came from, an `any_inf` flag -- and
`check_col_values()` read all of it, warned, and returned `invisible(NULL)`. `scan_missing_cpgs()`
dropped it on the floor, and `mc_cohort()` did the same to `all_na_cols` once it had subtracted them
from `usable_cols`. So a user who cleared a scrollback, or who scored in a script that captured no
warnings, had no way back to what the front door saw. Recording it costs one list per call and no
extra pass over the matrix.

**Keyed by batch, and this is the part that would have been built wrong.** The obvious shape is a
flat `n_cpgs` on the record, and it is wrong the moment two records bind: each came from a different
matrix, so a single number is either one batch's shape presented as the whole, or a sum of column
counts that overlap and means nothing. `input` therefore follows `min_clocks_coverage` and
`normalize_requested` -- one entry per batch label, concatenated by `rbind`, never reconciled and
never totalled. The test pins `names(provenance$input) == names(coverage$per_clock)`, because the
failure this design prevents is a verdict attached to the wrong matrix.

**`n_cpgs` and `n_scanned` are two numbers because the sweep is narrower than the matrix.** It reads
the requested panels alone, so on a 450K matrix scored for one clock it looks at a few hundred
columns. That was already true of the warnings and they did not say so: "`DNAm` contains values above
1" reads as a verdict on the matrix. All three value warnings now carry the scope as a shared
constant, so a clean warning cannot be misread as a clean matrix.

**Not recorded: the all-NA column names.** Only the count. Names are unbounded in the input, and the
one consumer that wants them -- the digest -- wants a number. `clocks_coverage(all_columns = TRUE)`
already names missing CpGs per clock, which is the question a name answers.

---

## 2026-08-08 -- `samples_coverage()$reason` becomes `$note`, a verdict on the row's own step

**The frame already had a step axis and only half-used it.** `panel` is `score` or `norm`, one row
each per (sample, clock), but `attach_reasons()` was commented "attach reason to score rows only",
so the norm row carried five counts and said nothing about whether normalization worked. That
produced a real misattribution: when BMIQ fails a sample, `failed.sample = "NA"` NAs its betas, the
score goes `NA`, and the gap walk reports `fit` **on the score row** -- the failure happens at the
norm step and is reported at the calculation step, with the norm row for that exact cell sitting
silent.

So `note` is now a verdict on whatever the row's `panel` names. Score rows keep the five values;
norm rows gain `partial`, for a sample normalized from a calibration that could not be fully
applied. The rename follows the meaning: once the column stops meaning "why this score is `NA`",
`reason` on a row where nothing went wrong asks the reader to accept `NA` as "no reason".

**This breaks a documented contract**, `!is.na(reason)` <=> the score is `NA`, and the failure
filter becomes `panel == "score" & !is.na(note)`. Absorbed pre-alpha; all three consumers were ours.
It is a column, not an export, so `NAMESPACE` did not move. **`note` stays a closed enum**,
enumerated in the roxygen -- the name must not become an invitation to free text.

**This retires a warning about a non-problem.** `say_partial_calibration()` warned that BMIQ skipped
its H step for a sample that **still scored**, which reads as a failure however it is worded, and
could not be filtered back to the affected cells. `h.applied` is already per sample within one
clock's `bmiq_fit()` call, which is exactly the norm row's key, so the fact needed no reshaping --
only a collector. `note_partial_calibration()` mirrors `note_scoring_failure()` into
`provenance$partial_calibration`, binds by the same rule, and `samples_coverage()` joins it on
(sample, clock). Same move as an `NA` score being explained by the column rather than by a warning.

**Two things were proposed during the design and rejected on measurement. Both were mine, and both
were wrong in the same direction -- assuming a hole where the code already had a guard.**

- **A terminal `fit` fallback in `gap_walk()`**, to make the column total by construction. Refused:
  `batch_gaps()` already computes `blind <- na_mat & is.na(out)` and `stop()`s naming it a package
  bug. That is strictly stronger, and the fallback would have **weakened** it -- converting a
  detected defect into a plausible-looking label.
- **A claimed live defect**, that a flat PhysAge surrogate NAs the whole column unexplained, reasoned
  from `finalize_PhysAge` not being among the three `note_scoring_failure()` call sites. Measured
  and false: flattening one of `DNAmPhysAge`'s 8 surrogates NAs all 12 scores and every one reports
  `fit`, because `finalize_cross_sample()` records reduction losses generically one frame above the
  branch. What the post-calculation layer still lacks a guard for is a partial **output transform**
  inside a score branch -- today none exists, since `anti_trafo` and `log_offset_anti_trafo` are
  total functions of one number (`exp(x) <= 1` on the negative branch; `exp(x) - 2` overflows only
  past `x ~ 709`). A future `log()` on a linear predictor would be the first, and the `blind` guard
  catches it as a bug rather than mislabelling it.

**`na.rm = TRUE` in `finalize_PhysAge()` was also proposed and rejected**, on the worry that one
coverage-failed sample would NA the whole cohort. It does not: `scale()` already ignores `NA` per
column, so a single `NA` cell NAs only its own row, and **only a flat surrogate (cohort sd 0) takes
out every sample**. What `na.rm = TRUE` would change is that flat case, where it turns a loud correct
`NA` into a silent wrong number -- PhysAge sums z-scores into a polynomial calibrated on all 8 terms,
so summing 7 is a plausible score on the wrong scale, and per-sample drops would make samples
non-comparable to each other. A degenerate cohort should say so.

## 2026-08-08 -- BMIQ's gold standard is distributional, so a bare `goldstandard.beta` needs no alignment check

`bmiq_calibration()` takes `goldstandard.beta` as an unnamed numeric vector paired positionally
with the matrix columns, and nothing inside it can check that pairing. Audited on the fear that a
mis-ordered gold would silently apply the wrong per-probe mean. **It cannot: there is no per-probe
gold mean.** `beta1.v` is read at four places -- one beta-mixture EM over the whole vector and two
`estimate_mode()` calls over subsets selected by the gold's *own* class assignment -- and what
crosses into `process_sample()` is five distributional summaries (`gold.a`, `gold.b`,
`gold.thresholds`, `mod1U`, `mod1M`). Measured: reversing the gold's order moves Horvath1 by
6.9e-11, and scrambling it while keeping the multiset moves it by 9.7e-13.

**The mask is what matters, not the order**, and that is a much smaller surface. Measured on the
same panel: a *different* 18868 of the 21368 probes moves the score 0.023 years, and a biased half
moves it 2.36. Both are prevented one frame up, by two things already required elsewhere --
`resolve_cpgs()` derives `present` / `present_idx` / `absent` from one `ok` mask, and `bmiq_fit()`
subsets the gold **by name** off `obs[["cols"]]`, the same object that names the matrix columns.
Full column permutation of the input gives `identical()` scores.

So do not add an alignment assertion inside `bmiq_calibration()`, and do not read the positional
signature as a latent bug. The gold is a named vector out of the catalog
(`probe_sets[].role == "bmiq_gold_standard"`, upstream `weights/<group>/goldstandard2.csv.gz`);
the names are what make the by-name subset possible and are the thing to preserve. Not verified
for the quantile scheme, which routes through `score_Dunedin` and shares only the mask guarantee.

---

## 2026-08-08 -- BMIQ fits the whole panel and draws no RNG; `nfit` is gone

`fit_mixture()` drew `min(nfit, length(beta))` indices through `draw_fit_indices()`, which called
`set.seed(1)` behind a `.Random.seed` save/restore. That is deterministic within a session but
**inherits the session's `RNGkind`**, so a user who set `L'Ecuyer-CMRG` -- routine for parallel
work -- scored Horvath1 differently. Measured on the shipped path: 3.39e-08 years between the two
generators.

**Two premises that motivated the change were both wrong, and are recorded so they are not
re-derived.** `bmiq_fit()` already passed `nfit = ncol(betas)`, overriding the 20000 default, so
the draw was always a **full permutation and never a subsample** -- traced live, 4 calls, all with
`n == size == 17368`. No probe was ever excluded; the RNG only reordered `y_fit` and perturbed
floating-point summation order in the EM. Consequently there is **no cost** to removing it (0.71s
vs 0.72s on 8 x 21368), not the +4% predicted from timing a direct `bmiq_calibration()` call that
bypassed `bmiq_fit()`.

`draw_fit_indices()` is deleted and `fit_mixture()` fits the whole vector. **`nfit` is removed
rather than ignored** -- an argument accepted and silently disregarded is a lie in the signature,
and `bmiq_calibration()` is internal, so no user-facing surface moves. The re-vendoring argument
for keeping it does not apply: `R/normalize_bmiq.R` has been this package's own code since
2026-08-07 and there is no re-vendor workflow to protect.

Scores now bit-identical across `RNGkind` and across seeds. Old vs new differ by 1.6e-07 years,
pure reassociation. **`HORVATH_NORM_TOL` needed no re-snapshot**: `Horvath1@cohort_450K` measured
1.137877e-01 / 1.926282e-03 against a recorded 1.137877e-01 / 1.926282e-03, unchanged to all
seven figures, because a 1.6e-07 perturbation sits six orders below a 0.11-year residual. Parity
ran at `FAIL 0 | SKIP 33 | PASS 710`, the documented cached-packs baseline.

---

## 2026-08-08 -- `normalize =` may name a sex-routed member, and that stays

`normalize =` validates `names(normalize)` against the resolved sequence, which carries the
sex-routed members, so `normalize = c(DNAmFitAge_Female = TRUE)` clears a gate `clocks =` would
refuse. **Built as one shared refusal and reverted the same day. Do not build it again.**

The hole is entirely latent. All 14 members declare `scheme = none`, so the scheme check already
refuses every one of them, and the fix changed no outcome -- only which message the user reads.
It made that message worse: it pointed at the alias, and the alias declares `scheme = none` too,
so the advice led to a second error. The prior message was terminal and true.

Reordering the two checks would have removed that regression, and the revert was still the right
call. What is left after the reorder is a refusal that fires only in a catalog state that does not
exist, against permanent maintenance cost. **A sync that gives a routed member `quantile` or `bmiq`
is what makes it live, and that sync surfaces it** -- so there is no queued item, deliberately.

---

## 2026-08-08 -- `covariates =` is a named map only, canonicalized above every check, and positional sugar is refused on a measurement

Builds `dev/to-do.md` Q5. The shape is the one that item designed --
`covariates = c(Age = "age_yrs")`, one named map per front door, canonicalize rather than restore --
with two corrections to it and one question it did not ask.

**The rename goes above `check_pheno()`, not inside `resolve_pheno()`.** The item said to rename
inside `resolve_pheno()` because it already materializes a fresh subset, so a rename there touches a
names attribute and never the caller's object. That reasoning is right and the placement is wrong:
`mc_cohort()` calls `check_pheno()` at `R/score_cohort.R:205` and `resolve_pheno()` at 211, so a
rename at 211 arrives six lines after every gate that reads the covariate by name. It would have
silently disabled the missing-covariate abort, the `Female` 0/1 assert, `warn_age_units()` and
`warn_missing_covariates()` **for exactly the callers who used the map** -- the failure looks like
the feature working. Canonicalizing at the top of the front door instead keeps the fresh-frame
property (the helper assigns into its own local `pheno`) and costs nothing downstream. Both doors
have a clean top: `calc_clocks()` between `mc_spec()` and `mc_cohort()`, where `spec[["covariates"]]`
first exists, and `calc_accel()` before `merge_accel_data()`, which the item had already identified
for its own reason. `tests/testthat/test-covariates.R` pins all three gates against the map, because
this is a bug that passes every score test.

**The map is validated against what the call reads, not against the catalog's two names.** The item
said `assert_subset()` against `clock_covariates_required()` over the resolved sequence, which is
right for `calc_clocks()` and does not generalize -- `calc_accel()`'s covariates are `Age` plus the
formula's own terms, which are not catalog facts. Stating the rule as *a covariate this call reads*
covers both doors with one helper, and picks up `~ Age + smoking` for free: a caller may point
`smoking` at `smoke_status` under the same rule, with no special case.

**Positional sugar is refused, and the reason is measured rather than stylistic.** The ask was for
something shorter than `c(Age = "age_yrs", Female = "sex_f")` -- positional (`c("age_yrs", "sex_f")`)
or numeric column indices. The blocker is that the two covariate domains **overlap in one
direction**: `Female` values `0/1` pass `check_pheno()`'s `assert_numeric(finite = TRUE)` for `Age`
silently, while `Age` values correctly fail `assert_integerish(lower = 0, upper = 1)` for `Female`.
So the dangerous mis-binding is the quiet one. Position is resolved against the run's required set,
which is derived from `clocks =` -- 17 catalog clocks read `Age` alone and 8 read `Female` alone --
so adding one clock to `clocks =` re-binds the positions and turns `Age` into a 0/1 column, which
still scores, still returns finite numbers, and is entirely wrong. That is the standing risk the
item already flagged, except positional *manufactures* it instead of permitting it. It is also the
same class as the partial-match ban: resolving a token to something the caller did not name.
Numeric indices fail on a second axis, breaking on any column reorder.

**No sugar was added, because the named form already is the sugar.** `c(Age = "age_yrs")` is
verbatim `dplyr::rename()` syntax, new name left and old name right, so there is nothing to learn;
and the length complaint is mostly about a call that is not the common one -- only 8 clocks read
both covariates, against 25 that read `Age` at all, so the modal call is the one-entry map. If the
ergonomics do bite later, the additive move is Q6's shape (a coercion at the front of the same
helper), which nothing here forecloses.

Two refusals the item did not specify and the helper needs: pointing at a column `pheno` does not
have (the message names the caller's own word, not the canonical one), and pointing a covariate at a
column whose canonical name is **already** a separate column, which would leave two columns with one
name. `.var.name = "names(covariates)"` on the subset assert, because the deparse says `nm`.

The standing risk stated in the item is unchanged and is now in the manual: a pointer moves the name
and not the contract, so `Female` aimed at a `1 = male` column scores every sex-reading clock
silently wrong.

---

## 2026-08-08 -- `normalize =` takes clock ids, not scheme names, and everything except a bare scalar is a partial override

**Reverses the shape proposed in `dev/to-do.md` Q6**, which was a character vector of *scheme*
names (`normalize = "bmiq"`), `assert_subset()`ed against `NORM_SCHEMES`. The built form is a
character vector of **clock ids**, and it is exact sugar for `c(<id> = TRUE)`. So `"bmiq"` and
`"quantile"` are now rejected the same way `"wrong_string"` is: they are not clocks being scored.

**One rule covers all four forms, and it was already the shipped semantics.** The bare scalar
`TRUE` / `FALSE` overrides every clock that declares a method. **Anything that names something
speaks for that thing alone**, and leaves every other clock at its default. That is not a new rule:
the named-logical branch has always been `out[nm] <- normalize` on top of the defaults
(`R/resolve_inputs.R`), so `c(Horvath1 = TRUE)` already left `DunedinPACE` alone. Stating it is what
makes the character form unambiguous, and the ambiguity is real -- `clocks = c("Horvath1",
"DunedinPACE")` with `normalize = "Horvath1"` reads equally well as "also turn on Horvath1" and as
"normalize only Horvath1". The first is the answer, because the sugar must mean what it desugars to.

**Why scheme names were declined**, having been the entry's whole proposal:

- **Two namespaces in one argument.** The package has been bitten by this: `KNOWN_PARITY_GAP_GROUPS`
  is a separate map from `KNOWN_PARITY_GAPS` because group ids and clock ids share a namespace and
  one flat map could not say which a key meant. `normalize` would have had schemes and clock ids in
  the same character vector.
- **A scheme name acts at a distance.** Under the proposed absolute reading, `normalize = "bmiq"`
  turns quantile *off*, so a request that includes `DunedinPACE` silently loses its normalization
  and returns a materially different score. Since normalization stopped being constitutive
  (DECISIONS 2026-08-06) that is a legal thing to ask for, which is exactly why it must be asked for
  by name.
- **The payoff is thin at catalog size.** "Turn on bmiq everywhere" is `c("Horvath1", "Knight")`.
  Two names. **The condition that reopens this:** a sync that lands many more bmiq clocks makes
  hand-listing unreasonable and earns schemes their place.

**What was given up, and where it went instead.** Q6's stated motivation was the roxygen line
"Default is `"quantile"`" -- one word, off `NORM_DEFAULT_ON`, incapable of drifting. Clock ids
cannot deliver that, because in clock-id terms the default is a list that moves with every sync.
**The scheme vocabulary belongs in the prose, not in the argument**: the donor's new
`Normalization` section says a clock declaring `quantile` is normalized and a clock declaring `bmiq`
is not, which is the same fact, derived from the same constant, and still cannot drift. Four
accepted forms also crossed the union-type threshold in `dev/WRITING.md`, so the forms live in a
donor `@section` pulled in by all three topics that take the argument (`calc_clocks`, `clock_cpgs`,
`sim_DNAm`), on the `ext_data` precedent.

**The implementation is a coercion, deliberately.** `is.character()` becomes
`setNames(rep(TRUE, n), normalize)` *before* the existing named branch, so every gate and every
message is inherited rather than rewritten. That is also why the valid set was **not** narrowed with
`assert_subset()`: the current code already splits the two mistakes and says more about each one
than a flat valid-set dump would. `"wrong_string"` is "not being scored"; `"Hannum"` is "cannot turn
on `normalize` for Hannum. This package can apply only the quantile, bmiq normalization methods."

**An empty request is now an error, on both types.** `character(0)` and `logical(0)` previously fell
through `!is.null(normalize) && length(normalize)` and returned the defaults without a word, so a
caller who computed an empty vector was told the run was normal. This is the position `CLAUDE.md`
already takes when it prefers `assert_subset()` over `match.arg(several.ok = TRUE)` for taking
`empty.ok` as an explicit flag. The wider sweep is `dev/to-do.md` A6.

**One inconsistency was found and deliberately not fixed here.** `normalize`'s valid set is
`clock_sequence`, which includes the 14 sex-routed members: measured on `clocks = "DNAmFitAge"`, 14
of the 30 clocks in the sequence are members that `resolve_clocks()` refuses by name. So there is a
set of clocks nameable in `normalize` but not in `clocks`. It is latent, not live -- all 14 declare
`scheme = none` and are refused by the `unusable` branch anyway -- and narrowing the set with
`drop_routed_members()` would make the *message* wrong, since a routed member genuinely is being
scored. The fix worth building borrows `resolve_clocks()`'s own refusal, which names the alias, and
that is a message rather than a one-line set change. Queued as `dev/to-do.md` Q7.

**This is not the Q3 partition question, which stays closed.** That item was deleted the day before
(DECISIONS 2026-08-07, `list_clocks()`), and its proposed rule was rejected on its merits: a routed
member is untypeable and necessarily visible in coverage, so "requestable" and "shown" are different
axes and no single partition spans them. What is queued here is smaller and does not reopen it --
`resolve_normalize()` validates against a set nobody chose, while `resolve_clocks()` chose one. A
survey of every site where a user names a clock found those two and no others.

## 2026-08-07 -- `list_clocks()` lists what `clocks =` accepts, and nothing else

`list_clocks()` returned all 137 catalog entries, including the 14 sex-routed members, which
`resolve_clocks()` refuses by name. It now returns the 123 a user can request, and the `callable`
and `request_as` columns go with them. This **reverses 2026-07-23** ("the 14 sex-routed members
appear with `callable = FALSE` and `request_as` naming their alias", `DECISIONS.old.md`) and
supersedes the column-set clause of 2026-08-03 below.

**The evidence was our own catalog article.** `vignettes/articles/clocks.Rmd` carried
`catalog[catalog[["clock_id"]] == catalog[["request_as"]], ]` with a two-line comment explaining
it. The one consumer we control was filtering the leak back out by hand, inferring
"not requestable" from a column identity. Three lines deleted.

**`all_columns` was the wrong lever and was rejected on its own terms.** Hiding the members in the
narrow frame and keeping them under `all_columns = TRUE` fails twice: the article needs
`all_columns` for its `normalize` column, so it would keep the filter; and `test-list-clocks.R`
asserts `nrow(narrow) == nrow(wide)`, which is the right model. The argument is named for columns
and must not add rows.

**Both dropped columns were provably constant afterwards, which is why they are not a second
decision.** `callable` is all `TRUE`. `request_as` equals `clock_id` in every row -- it existed
only to name a routed member's alias. 2026-08-03 dropped `callable` from the default set precisely
because it was `request_as == clock_id`; the two collapse together once the rows they split are
gone. Keeping either would have shipped a column carrying no information.

**What is knowingly lost: no public surface maps a `role = "routing_target"` id in
`clocks_coverage()` back to its alias.** Three things cover it. The coverage row still carries
`group_id`. The member ids are `<alias>_Female` / `_Male`. And passing one to `calc_clocks()`
returns the exact pointer. A `list_clocks(internal = TRUE)` argument was considered and rejected as
surface bought for a lookup that three cheaper routes already answer.

**This closes the `list_clocks()` half of `dev/to-do.md` Q3, and the item is deleted rather than
narrowed, because the other two halves were never open.** The pool half was already done --
`resolve_clocks()` excludes the members from `"all"`, from every group token and from every tag,
and refuses one by name with a pointer to its alias. The coverage half **must not** be done: an
alias has no `per_clock` record by the `clock_reads_cpgs()` invariant, so the member rows are the
only place a routed family's CpG counts exist, in both coverage frames. Q3's proposed rule -- one
partition, "requestable, shown, and returned" against "internal machinery counted only for
coverage", never overlapping in what a user "can type or see" -- **cannot be implemented as
written**, because type and see are different axes and a routed member has to sit on opposite sides
of them. It is untypeable and necessarily visible in coverage. The two functions that carry the
real taxonomy, `sex_routed_members()` and `clock_reads_cpgs()`, are deliberately not the same
partition.

Q3 also named `DNAmSex_Wang_ChrX` as a routed member. It is not one, and neither is
`DNAmSex_Wang_ChrY`: both are ordinary callable clocks that `predict_sex()` composes. All 14
members are the `DNAmFitAge` family.

Measured after the change: `list_clocks()` 137 rows to 123, `nrow(bundled)` in the article 108 to
94 (the chunk computes it, no prose quotes it), and the `head(list_clocks(), n = 3)` block in
`README.md` loses one column. No tag names a member, and no member sorts into the first three rows,
so the tag filter and the three `@examples` blocks are unchanged. 884 pass / 0 fail; parity not run.

---

## 2026-08-07 -- cli messages stop prescribing data fixes, and point at a diagnostic one way

A recommendation pass over the cli warnings and aborts, after a verbosity audit
(`dev/cli-audit.md`, `dev/cli-verbose.md`) and maintainer review. Two rules landed in
`dev/WRITING.md`, plus a set of trims.

**A cli message does not hand out a recipe for a numeric transformation of the data.** The age-unit
warnings dropped `Age / 12`, `Age / 52`, `Age / 365.25`; the beta-range warnings dropped
`beta <- 2^m / (2^m + 1)` and `DNAm / 100`; the EPICv2 warning dropped the `sub()` that strips
probe suffixes. The reason is liability, not length: a user who copies a conversion and misapplies
it gets a plausible but wrong age that traces back to our message, and the units, scale, or probe
layout of the input is theirs to own. The messages now name the likely cause ("an M-value matrix is
a common cause") and the property the data should have, never the correction. **A trivial structural
fix that fails loudly is the exception and stays** -- `t(DNAm)`, `rownames(DNAm) <- ...`,
`as.matrix()` -- because none of those can silently corrupt a score.

**One declarative phrasing points at a diagnostic function.** `Call {.fn samples_coverage} to
see ...` and its variants became `{.fn samples_coverage} gives ...`, with the function as the
subject. An imperative read as an order for something the reader may not need to do; the coverage
frames are there to read on demand. `clock_cpgs()` follows the same form. `norm_gate()` was left
imperative for now (its item was approved with no change) and is queued in `dev/to-do.md`.

**The missing-covariate warning stopped telling the user to drop samples.** Dropping a sample for a
missing covariate drops it for every clock, including the ones that never needed that covariate, so
the advice was actively wrong. It now says a sample scores `NA` only for the clocks that need the
covariate, and when the missing covariate is `Female` it points at `predict_sex()` to estimate sex
from `DNAm`.

Two items are deferred, not done: the assets closed-set aborts still read "never triggers a
download" (too strong), and a full sweep of every message not in `cli-verbose.md` against the recipe
rule. Both are in `dev/to-do.md`. Sex-routed members leaking into the callable pool became its own
open question (`dev/to-do.md` Q3), because the routed-member refusal is a patch over a wider
requestable-versus-internal inconsistency.

## 2026-08-07 -- BMIQ says it is running, and calibrates a shared background once

Two changes to the one BMIQ call site, from one measurement. `calc_clocks()` at 1000 samples with
`normalize = c(Horvath1 = TRUE)` takes **76.9 s**, against 0.01 s for the same call with
`normalize = FALSE`. The whole run is BMIQ, at a flat **77 ms per sample** past a one-time 0.17 s
gold-standard fit, and it printed nothing at all for those 77 seconds.

**The `-O0` caveat does not apply on this path, which is itself the finding.** The same job through
`load_all()` took 91 s, only 18% slower, because BMIQ is R-bound: the EM loop and the `pbeta` /
`qbeta` maps are R, and the C++ kernels are only the block gather and scatter. So the standing rule
against benchmarking through `load_all()` costs nothing here. The optimized figure came from
`R CMD INSTALL` into a temporary library, never from `check()`.

**Not a progress bar, and the vendored file is why.** `bmiq_calibration()` already carries a
`verbose` argument, dead since the one call site hard-codes `verbose = FALSE`, whose per-sample
`message()` would print 1000 lines. Converting it to `cli_progress_bar()` was rejected: the sample
loop lives inside `R/normalize_bmiq.R`, which is vendored from `hhp94/betanorm`, so a bar there
diverges the vendor for a caller-side concern. The alternative of calling `bmiq_calibration()` once
per sample block re-runs the gold fit each time. `cli::cli_progress_step()` works with **zero
updates inside the body** -- it prints on entry and rewrites with the elapsed time on exit -- so it
sits entirely in `bmiq_panel()` and the vendored file is untouched. `verbose` stays as upstream
wrote it.

**`BMIQ_SAY_AT` is 25 samples, and the threshold exists because the step does not self-suppress.**
`cli_progress_bar()` prints nothing under `cli.progress_show_after` (2 s, verified: a 0.9 s loop is
silent, a 5 s loop emits four throttled lines). `cli_progress_step()` has no such gate and announces
a 200 ms step, so a 10-sample run would newly print. 25 samples is about 2 s at the measured rate,
which is cli's own threshold reached by arithmetic rather than by a timer. **Quantile is left
silent** and needs no threshold of its own: `DunedinPACE` at 1000 samples is 2.27 s, because that
scheme is the C++ kernel.

**The background is calibrated once per panel, and the reporting stays per clock.** The catalog
declares exactly two bmiq clocks, `Horvath1` and `Knight`, whose declared backgrounds and gold
standards are `identical()` at 21368 probes, so `dedup_panels()` already collapses them to one
entry and scoring both calibrated it twice. `resolve_cpgs()` now carries a `norm_panel_key` per
clock and `bmiq_fit()` memoizes into `block[["norm_cache"]]`. Measured 40 samples: 9.64 s separately
against 6.44 s together, scores **bit-identical** (max abs diff 0) with matching NA patterns.

Three things about the shape, each of which could have gone the other way:

- **The key is `NULL` unless two clocks share the panel.** A calibrated panel is n x 21368 doubles,
  171 MB at 1000 samples. Today it dies when `bmiq_panel()` returns; cached, it would live until the
  block finishes every other clock. Keying only a shared panel means a lone normalizing clock
  retains exactly what it retains now, and peak memory with two clocks is unchanged, because the two
  never held separate copies at once anyway.
- **The panel is not the whole key, and the key is not hand-listed.** Two clocks can declare
  identical background panels and different gold standards, which `dedup_panels()` cannot see, and
  a later scheme could declare a per-clock `nL` or `doH` the same way. The obvious fix is to name
  the varying parts in the key, nested or pasted. It was rejected: a hand-listed key is an
  enumeration that has to be widened every time the call gains an argument, and forgetting returns
  a **hit** on an entry calibrated with different parameters. Instead `bmiq_fit()` builds the
  kernel's arguments once as `args`, `do.call`s them into `bmiq_calibration()`, and hands the same
  list to `norm_cached()`, which stores it beside the result and compares it whole with
  `identical()`. An argument cannot join the call without joining the key. The bucket name carries
  the scheme (`"bmiq/1"`) so a second scheme reading the same cache cannot collide, even though
  quantile does not read it today.

  **The betas are deliberately not in `args`.** Within one block the panel index fixes
  `norm_present` and `norm_present_idx`, so it fixes what `observed_panel()` returns, and the
  bucket name already carries that index. Storing the matrix instead would pin a second 171 MB at
  1000 samples to re-prove something the key already establishes.
- **`say_scored_na()` still fires once per clock, and `dev/to-do.md` was wrong to call that a
  blocker.** The queued entry held the hoist back on the theory that a shared calibration trading
  duplicate work for a duplicate warning was a bad bargain. The warning is not duplicated: it names
  a different clock and a different `NA` column each time, and both columns really are `NA`. Two
  clocks failing on one sample is two facts a reader needs, not one fact said twice. So the hoist
  is a pure performance change with no observable difference, which is what the new
  `test-normalize.R` block asserts. That block is kept against "parity owns the arithmetic" for the
  same reason as the other four: parity scores one clock per call, so it can never exercise a
  cross-clock cache at all.

---

## 2026-08-07 -- BMIQ drops RcppArmadillo; `LinkingTo:` is `Rcpp` alone

`src/bmiq_norm.cpp` was vendored earlier the same day as Armadillo code, and `LinkingTo:
RcppArmadillo` was recorded in `CLAUDE.md` as the accepted cost of bringing BMIQ in-house. Upstream
then shipped an Armadillo-free backend in `hhp94/betanorm`, and that is the version the package now
carries. The dependency is gone, so the cost was not paid at all.

**The strip is mechanical, and the arithmetic is untouched.** `arma::vec` becomes
`std::vector<double>`, `arma::mat` becomes `Rcpp::NumericMatrix` with explicit column-major
`i + n * k` indexing, `arma::uword` becomes `R_xlen_t`, and the two Armadillo reductions
(`arma::max(arma::abs(...))` over the parameter state) become an explicit loop. Nothing in the EM,
the Newton step, or the Armijo backtracking moved. The return shapes are preserved deliberately:
`a`, `b` and `mu` stay K x 1 matrices and `eta` stays a bare vector, so
`canonicalize_em_components()` and `em_diagnostics()` keep reading `em[["a"]][, 1L]` unchanged.

**One R-side change, and it is the signature.** `scan_finite_unit_interval_cpp()` took an
`arma::mat`, so the gold-standard call site wrapped its vector in `matrix(..., ncol = 1L)`. The
parameter is now `Rcpp::NumericVector`, which accepts a vector and a numeric matrix alike, so the
wrap is deleted. `datM` still passes as a matrix through the same parameter.

**Verified bit-identical, not merely within tolerance.** The always-on tier cannot catch a numeric
regression here: `test-normalize.R` keeps only the record half (`provenance[["normalized"]]`,
`cov[["normalizes"]]`, the `sample_miss[["norm"]]` column), and the BMIQ numeric golden lives in the
parity tier as `parity (horvath normalized)`, which is maintainer-gated. So both backends were built
and run against one fixed trimodal 6 x 3000 panel: **max abs diff 0, max rel diff 0,
`identical()` TRUE over all 18000 calibrated cells**, with matching `success` and `h.applied`
vectors. A checksum agreeing to 17 digits is not the gate; the element-wise `max` is, per the
correlation-is-never-a-gate rule. The Armadillo build was reconstructed from `betanorm` at HEAD,
confirmed equal to what was vendored by diffing HEAD-to-worktree against vendored-to-worktree.

**`src/Makevars` is deliberately left alone.** It carries `$(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)`
beside the OpenMP flags, and after the strip nothing in `src/` calls BLAS -- but nothing did before
BMIQ either. The flags arrived with the original Rcpp kernels commit, not with Armadillo, so
removing them is a separate question about boilerplate and not a consequence of this change.

## 2026-08-07 -- the vendored BMIQ code raises no warnings; its caller owns both

`bmiq_calibration()` shipped two `warning()` calls written for betanorm's public API, and both
pointed at the object betanorm returned. Through `calc_clocks()` neither destination exists: a
scoring caller never sees `result$failures` or `result$h.applied`. Both are deleted from
`R/normalize_bmiq.R`. The vendored function now computes `failures` and `h.applied` and says
nothing -- **only `bmiq_panel()` knows the clock id and the user's own sample ids**, which is what a
message about them has to name.

**The failure warning is simply dropped**, not moved: `bmiq_panel()` already raised its own,
naming the clock, the sample ids and `$provenance$scoring_failures`. One event was producing two
warnings, the vaguer one first.

**The H-skip warning moves to `bmiq_panel()` and deliberately takes no note.** A skipped H step is
not a failure: the sample is scored, with the intermediate probes left uncalibrated, so the number
returned is quietly unlike a fully calibrated one. Routing it through `note_scoring_failure()` was
the obvious-looking move and is wrong twice over -- `gap_reasons()` reads
`$provenance$scoring_failures` as *the reason a score is NA*, so a scored sample landing there would
be an unexplainable entry, and `test-normalize.R` asserts that list is empty on a clean run. So it
warns and records nothing.

**A provenance field for "scored but degraded" was considered and rejected on reach.** The branch
needs a sample with no methylated probe at or above the fitted M-component mean, or a degenerate
conformal map. Measured on the Horvath1 gold panel: 6 clean samples over the full 21k panel and
over the thinned 1000-probe panel skip H zero times, and a sweep of 40 samples under monotone
M-compression, U-tail inflation and profile shifts also skips zero times. Samples distorted far
enough to starve the upper-M tail fail calibration outright first and take the failure path
instead. A new `mc_result` component, an `rbind` rule and a finalizer question is a lot of standing
surface for a path that plausible data does not reach; a warning is proportionate. Revisit if a
real cohort ever raises it.

The message shipped as a plain `warning()` matching the failure warning beside it. That was
reversed the same day: see "score-branch warnings are cli" below.

## 2026-08-07 -- `$provenance` is internal across the board, and print says `mc_batch_id`

Extends the entry below from "not a destination" to "not named at all" in anything a user reads.
Three sites moved, and the audit that found them now comes back empty except for one known false
positive (`cov[cov$panel == "score", ]`, a column on a frame the reader holds).

- The `say_scored_na()` hint already pointed at `samples_coverage()`.
- `calc_clocks()`'s `@returns` said the object holds "the coverage counts, and the provenance of
  the run". It now stops at the coverage counts. `man/calc_clocks.Rd` regenerated.
- `print.mc_result()` headed its multi-batch block `$provenance [2 batch(es)]`. It now reads
  `mc_batch_id [2 batch(es)]`.

**The print change is the one with a rule behind it.** The grammar is `$component [what is shown]`,
so the old header was correct by that grammar and wrong by this one. The resolution is not an
exception, it is that **`$` in the grammar means "a component you may reach for"**, and the block
was never showing the component -- it shows the labels, under the name they carry in both coverage
frames, both finalizer frames and the `calc_accel()` formula namespace. `fmt_named_section()` is
the un-prefixed builder and `fmt_section()` now delegates to it, so the two stay one grammar.
`$coverage` has never printed either, so "one line per list element" was already not literal.

**Tests are explicitly not in scope, and the `CLAUDE.md` line saying so was kept.** 53 assertions
across 10 files read `$provenance`, and `provenance$normalized` in particular has no exit that
presents it. Rewriting them would either lose that coverage or invent an exit to justify a wording
rule, which is backwards. The rule is about **who is reading**: a message, a doc page and a printed
line are read by a user, and a test is not. The test-altitude line now says that rather than
appearing to contradict the invariant, with a preference for the exit where one exists.

## 2026-08-07 -- a component name describes, it never directs: point at the exit function

`say_scored_na()` shipped an hour earlier pointing at `{.field $provenance$scoring_failures}`. It
now points at `{.fn samples_coverage}` and its `reason` column, which carries `"fit"` for exactly
these samples. `dev/WRITING.md` R8 gained the rule, because R8 is what made the first version look
legal: it whitelists component names as acceptable vocabulary, and says nothing about the
difference between naming a component and **sending the reader to one**.

**The two uses are not the same, and only one is a problem.** Describing the returned object is
fine. Telling a reader where to look is a promise about the supported surface, and the supported
surface is the exit functions. A component path needs the reader to know the object's internals,
and `refinalize_clocks()` / `rbind` restructure `$provenance` under them. `$provenance` looks like
the exception because `print()` renders a section with that name, so the word is not hidden -- it
is still never a destination, because everything worth reading in it has an exit that presents the
same fact. Here the exit is strictly better: `samples_coverage()` already joins the collector to
the sample ids and labels it, which is what `gap_reasons()`'s `fit` branch is built from.

**The audit found one other thing and it is not this.** A parse-token scan of every string inside a
cli call, every roxygen line, and both prose files turned up two more hits, both fine.
`coverage_report.R` shows `cov[cov$panel == "score", ]`, which is a column on a frame the reader
already holds. `calc_clocks()`'s `@returns` says the object "holds the scores, the narrowed
`pheno`, the coverage counts, and the provenance of the run" -- a description of the four sections
`print()` displays, not a destination, and left alone. **`CLAUDE.md` disagrees on the wider point
and was not changed**: its test-altitude section calls provenance flags "output" and blesses
asserting `res$provenance$dependencies` in a test. That is about what a *test* may read, not about
where a *message* may send a user, and the two can stand together. Revisit if that stops being
true.

## 2026-08-07 -- score-branch warnings are cli, and a score branch is split by the message

All four `warning()` calls in scoring branches are now `cli_warn()`, and no `warning()` remains in
`R/score_*.R`. The enumeration in `dev/WRITING.md` section 1 (and its copy in `CLAUDE.md`) no
longer lists "score branches" as wholly `stop()`.

**The enumeration had drifted from the rule printed four lines above it, for the second time.**
The rule is "audience, not transport": user input is cli, a package defect is plain. The
enumeration said score branches are `stop()`. Both applied to these four, which are about the
user's own samples, so a reader could pick whichever supported what they were about to do. This is
the identical failure DECISIONS 2026-08-03 replaced the previous keep-set for. The fix is not a
longer list -- **a score branch is on both sides, and the message decides**: its `stop()`s are
defects (missing dispatch, an unbanked moment set) and stay plain, its warnings are about the
user's data and are cli.

**Three concrete things the plain form was costing, none of them cosmetic.** No `{.arg}` / `{.val}`
/ `{.field}` markup, against R6. Hand-written `"sample(s)"` and hand-written id joins, where cli
has `cli::qty()` and `capped_bullets()` -- one of these four had shipped an uncapped id list hours
earlier for exactly that reason. And **invisibility to the only automated check on user-facing
text**: `banned_msg_sites()` collects strings inside `MSG_CALLS`, which is seven cli functions, so
R3's ban on `--` and `;` was unenforced on precisely these strings. All four are now scanned.

**One emitter, because the tail was the same fact three times.** `say_scored_na(id, failed, reason)`
in `R/score_cohort.R` owns "these samples score `NA`" plus "`$provenance$scoring_failures` lists
them", and each branch passes only its own lead line. It sits beside `note_scoring_failure()`,
which records the same event -- `say_*` prints, `note_*` records, and a branch calls both. The
BMIQ H-skip warning is deliberately **not** routed through it: the sample is scored, so it must not
claim `NA` and must not point at a list it is correctly absent from.

**`say_moment_failure()` reads the domain off the declaration, never a clock list.** Wang and
Zhang2019 reach the same state from very different sets, and the message has to say which, so it
branches on `clock_needs_full_panel()`: "every column of `DNAm`" for a `moment_key` of `"full"`,
"the z-score reference" otherwise. That phrase is reused verbatim from the Wang warning it
replaces, and an earlier draft naming the clock inside the lead was dropped for repeating the id
the hint already carries.

Rendered and checked at 1 and at N for every branch, because a `{?}` marker not immediately
preceded by its quantity binds silently to the wrong value. Suite unchanged at 883 pass / 0 fail /
0 error / 0 warn / 2 skip. Parity was not run.

## 2026-08-07 -- the same undefined-moment failure now warns in both branches, and both id lists cap

Two follow-ups to the entry above, found while reviewing it.

**`capped()` now applies to both lists in `bmiq_panel()`.** The H-skip warning used `capped()` and
the failure warning beside it used a bare `paste(collapse = ", ")`, so a cohort with 300 failed
samples printed 300 ids while 300 H-skips printed 10. `dev/WRITING.md` R5 settles it: cap the list,
and add no "and N more" tail, because the true total already leads the sentence. Measured: 14
failures now report 14 in the lead and list 10.

**`score_Zhang2019()` warns, where it used to record the note silently.** It and
`score_DNAmSex_Wang()` reach the same state -- fewer than 2 observed values on the `sample_scale`
domain leaves the per-sample sd `NA`, so the score is `NA` and `gap_reasons()` reads `"fit"` -- but
only Wang said so. `check_score_values()` could not cover the gap either: it counts `NaN` and `Inf`
and deliberately skips `NA`, so the sample really was silent. The asymmetry was an oversight, not a
design.

**The two branches reach that state on very different sets, and the message has to say which.**
Wang's domain is a declared 442,533-CpG `zscore_ref`. Zhang2019's `moment_key` is `"full"` with no
declared cpgs, which `resolve_moment_sets()` turns into `seq_along(cpgs)` -- **every column of the
supplied `DNAm`, not the clock's own panel**. So the Zhang message says "in DNAm" and the source
comment now says so too; the old comment read "n < 2 on the domain", which invites the reader to
think of the Zhang panel. This is the same fact `calc_clocks()` already states in cli when it scores
a full-panel clock, so the two agree.

`test-gap-reasons.R` already constructed this exact case and now asserts the warning with
`expect_warning()` rather than letting it go unhandled. Suite: 882 pass / 0 fail / 0 error /
0 warn / 2 skip. Parity was not run.

## 2026-08-07 -- betanorm is vendored, internal, and `Remotes:` is gone

`bmiq_calibration()` and `quantile_norm()` now live in `R/normalize_bmiq.R` and
`R/normalize_quantile.R`, with `src/bmiq_norm.cpp` and `src/quantile_norm.cpp` beside them.
`betanorm` leaves `Suggests`, `Remotes: hhp94/betanorm` is deleted, and `require_betanorm()` is
deleted with it.

**Both functions moved, not just BMIQ, and that is the whole point.** Moving BMIQ alone would have
bought nothing on the dependency side: `score_Dunedin.R` reads `quantile_norm()` for the PACE
background, so `betanorm` would have stayed in `Suggests` and `Remotes:` would have stayed with it.
**CRAN does not resolve `Remotes:`**, so a GitHub-only dependency backing a scoring path is a
release blocker whatever tier it sits in, and the `Suggests` placement only made the blocker quiet.
`quantile_norm` cost 23 lines of R over a plain-Rcpp kernel to take, against a dependency it was
the sole remaining reason to keep.

**Internal, not exported.** `bmiq_calibration()` takes a beta matrix, so exporting it here would put
a third public beta reader beside `calc_clocks()` and `predict_sex()` and reopen exactly the
"second beta reader" question the pre-flight invariant closes. `NAMESPACE` and `man/` are unchanged
by the move -- that is the check that it stayed internal. The roxygen blocks became plain `#`
comments and the two `bmiq_calibration_result` S3 methods (`print`, `as.matrix`) were dropped: the
one caller takes `[["success"]]` and `[["calibrated"]]` directly, and an unexported S3 method on an
unreachable class is dead weight. `betanorm` keeps its own public API; this is a copy, not a
deletion upstream.

**The `$` conversion was done by the parser, not by a text match.** `R/` bans `$` and
`test-source-hygiene.R` enforces it on parse tokens, so 103 sites had to move to `[[`. A regex over
1365 lines would have been a guess. Instead `getParseData()` located each `'$'` token and its
following `SYMBOL`, and the rewrite was applied right-to-left by column. The check that it was exact
is that mapping `[["x"]]` back to `$x` reproduces the betanorm source with **zero** diff outside the
four intended edits. Do not re-do this kind of conversion by hand or by `sed`; a `$` inside a string
or comment is indistinguishable to a text tool and a wrong one here silently scores wrong betas.

**Cost and non-cost.** `LinkingTo` gains `RcppArmadillo` (the EM kernel is Armadillo). `src/Makevars`
needed **no** change: it already carried `$(SHLIB_OPENMP_CXXFLAGS)` and `$(LAPACK_LIBS)
$(BLAS_LIBS) $(FLIBS)`, byte-identical to betanorm's, so the two packages were already built for the
same kernel. The four bare `stats::`/`utils::` calls betanorm left unqualified were qualified to
match this package's convention; the rest were already qualified.

**No tests came across.** betanorm's five files (590 lines) mostly exercise an `nL` / geometry /
ordering argument surface that one internal caller never varies. What gates this code here is what
already gated it: the `test-normalize.R` BMIQ and record blocks, the parity `horvath normalized`
block, the DunedinPACE reference golden, and the smoke tier -- which now runs the
quantile-normalizing clocks **unconditionally**, since there is no longer an optional package to
skip on. Baseline and post-move suites are identical at **882 pass / 0 fail / 0 error / 0 warn /
2 skip**, per-file across all 29 files, measured against a worktree at `HEAD`. Parity was not run.

---

## 2026-08-06 -- qs2 dropped for gzipped rds, and the checksum it took with it is replaced by promoting a warning

External packs are now `<group>-<payload_hash>.rds`, written by `saveRDS(compress = "gzip")` and
read by the one internal `mc_read_pack()`. `qs2` leaves `Imports`. The package is pre-alpha with no
users, so nothing migrates: the local staging and cache directories were emptied by hand rather than
given a transitional suffix regex.

**Measured before deciding, over all four staged packs.** Totals: qs2 at `compress_level = 1` is
45.14 MB and 0.64 s to read; gzip rds is 45.55 MB and 0.72 s. That is +0.9% size and +80 ms across
the whole corpus, which is a wash on both axes. Uncompressed rds is 63.36 MB (rejected below on
correctness, not size). `xz` is 42.88 MB but 1.96 s to read and 25 s to write, so it buys 5% for 3x
the read: not taken.

**What it buys is the dependency graph, not speed.** `qs2` carries `RcppParallel` and `stringfish`,
both compiled, plus `SystemRequirements: GNU make, C++17`. Dropping it removes three compiled
packages from a CRAN install. `Rcpp` stays, because this package has its own `src/`.

**`payload_hash` does not move, and that is why this is cheap.** `payload_hash_of()` digests the R
object, never the file bytes, so the content address and the release tag are identical across the
serializer change. Only the extension moves. A rebuilt pack lands as a second asset under its
existing tag.

**The one real loss is `validate_checksum`, and it is not replaced by an equivalent.** The
2026-07-21 entry made qs2's checksum the single integrity guard and deleted the parallel sha256
recompute; a runtime re-hash of the loaded object would bring that cost straight back, doubling
every load to restore a property that is now cheaper to get another way.

**That other way is one rule: a warning from `readRDS()` is an abort.** This is the part that had
to be measured rather than assumed, and the measurement is the reason the rule exists. Over 60
random single-bit flips in a gzipped pack:

- 28 raised an error (`ReadItem: unknown type ...`, `embedded nul in string`),
- **32 raised only the warning `invalid or incomplete compressed data` and returned a wrong
  object**,
- 0 read correctly.

A warning stops nothing, so the plain reader hands 32 of 60 damaged files straight into scoring as
wrong weights. `mc_read_pack()` promotes both conditions to one cli abort naming the file and the
next step. With the promotion, all 60 abort, which is what qs2 gave.

**Uncompressed rds is therefore banned on the write side too.** A flip in an uncompressed stream
returns a wrong object with *no* condition at all, so the promotion has nothing to catch. gzip is
load-bearing for detection, not only for size.

**Truncation was already covered and stays covered**: it reads as `error reading from connection`,
and `mc_fetch()`'s `.part` staging plus atomic rename means a partial download never lands under
the real name. The pre-rename read is what validates it, exactly as before.

**The test is one block, and it scans rather than pins a byte.** `test-mc_data.R` finds the first
bit whose flip `readRDS()` accepts with only a warning, asserts such a bit exists, and asserts
`load_mc_assets()` refuses the file. Pinning an offset would rot on any change to the fixture
payload, and worse, could silently drift onto a byte in the gzip header slack, where a flip is a
clean correct read and the test would pass while proving nothing.

---

## 2026-08-06 -- Six guards on the coverage-gate branch could not fire, and each one restated a guarantee the caller already carries

**Method first, because the finding is only as good as it.** Every branch the coverage-gate work
added or changed was instrumented with a hit counter and the whole suite run through it
(880 pass / 0 fail, identical to clean). What the suite reached is kept. What it did not reach was
then argued reachable-or-not **by construction**, because a cold branch is not a dead one. Six came
out dead, and all six are the same mistake: a guard placed one frame below the thing that makes it
impossible.

**`row_coverage()`'s three, and the function with them.** Its only caller chain is
`row_gate()` -> `row_gate_one()`, and `row_gate()` iterates `covered_ids(per_clock)` -- which is
*defined* as the non-`NULL` names of `per_clock`. So `is.null(cov)` tested the one thing
`covered_ids()` exists to guarantee. `is.null(score_miss)` was the same story on the other axis:
`construct_mc_result()` builds the `sample_miss` matrix from `covered_ids()` and
`batch_gate_input()` builds its list from `covered_ids()`, so the two are keyed alike by
construction -- and on the `gap_reasons()` path the guard could not have fired even had they
disagreed, because `m[, id]` errors on a missing matrix column before returning anything.
`needed == 0L` needed a measurement rather than an argument, and got one: the smallest declared
scoring panel over the 127 CpG-reading clocks is 3. With all three gone the function was a one-line
wrapper around `panel_ratio()` with a single caller, so it was inlined into `row_gate_one()`, whose
own `is.null(rc)` fell with it. Note this is **not** the same as `clock_gate_verdict()`'s
`needed == 0L`, which fired 241 times and stays: that one grades **norm** panels, where an empty
panel is how a non-normalizing clock declines without a separate test.

**`gap_walk()`'s four `%||% none` fallbacks.** `masks` is `setNames(lapply(seq_ids, f), seq_ids)`
and the walk iterates `seq_ids`, so `masks[[nm]][[id]]` is always populated. `na[[d]]` was checked
across the whole catalog: every dependency precedes its dependent in `resolve_clocks_sequence()`
and none falls outside it. That one is **self-enforcing** and is the reason it can go without a
replacement test -- `score_cohort()` dispatches in the same order and its branches read
`results[[dep]]`, so a dependency arriving late breaks scoring long before any reason walk sees it.
The third fallback in that file, `gate[[id]][["na"]] %||% none` in `gap_masks()`, fired 44 times and
stays: `gate` holds only the clocks with a verdict, which is a genuinely partial set.

**The rule this leaves.** A guard earns its place by testing something its caller does not already
guarantee. Where a helper is reached only through a set-builder like `covered_ids()`, say so in a
comment and let the builder be the check -- a second test there cannot fail, and it reads as though
the key set were in doubt, which is worse than silence because the next reader will preserve it.
Everything else measured is live and was kept, including all four conditional bullets in
`check_coverage()` and all five in `check_row_coverage()`.

**One defect found in passing, in a defect guard.** `batch_gaps()`'s unexplained-gap `stop()` still
opened `"score_gaps(): "`, naming a function unexported hours earlier. That prefix is the greppable
handle a pasted bug report is located by, so a stale one is the whole failure mode. Now
`gap_reasons():`.

---

## 2026-08-06 -- `score_gaps()` is not a frame, it is a column of `samples_coverage()`. Unexported the day it shipped

**Reverses the same-day decision to export it.** The question the maintainer asked was whether the
gap reasons could just be joined onto `samples_coverage()`. Measured against a `DNAmFitAge` run
carrying all four reachable reasons, the answer is yes, and the fold **removes an asymmetry that was
already there** rather than creating one.

**The two coverage frames did not span the same set, and `samples_coverage()` was the odd one out.**
On that run `clocks_coverage()` spanned 30 clocks and `samples_coverage()` 20. The 10 missing are
the composites and the aliases, and `clocks_coverage()` had **always** carried them as an all-`NA`
count row -- the invariant "a clock reports only what it counted itself" is about not reporting a
*figure*, and an `NA` row is not a figure. `samples_coverage()` alone dropped them. Widening it to
the same span is the simplification; the `reason` column is what made the gap visible.

**A naive join loses the majority of the reasons, which is why this had to be a span change and not
a `merge()`.** Joined onto the old span, 14 of 19 gap rows have no row to sit on: every `dependency`
row, because a composite counts nothing, and every `covariate` row, because a sample no model scored
was dropped entirely. Those are exactly the reasons a caller cannot derive by hand. Widened, all 19
land. **So the `!is.na(coverage)` sweep had to move**: it now filters only the half built from
coverage records, where its one real job is a routed member masked outside its sex. Run over the
assembled frame it deletes every composite row, and the failure is silent -- the reasons just are
not there.

Three consequences, all accepted:

- **`samples_coverage()` is now a finalizer**: it reads the NA pattern of `$scores`, and a
  cross-sample column is entirely NA until its reduction runs. It was one of the two exits that
  deliberately did not call `finalized()`. `clocks_coverage()` still does not, and that asymmetry
  is now load-bearing rather than incidental: it never touches `$scores`.

  **Which exposed that the definition of "finalizer" was wrong, and had been all along.** The
  stated test was one clause -- "any exit that takes an `mc_result` and returns something that is
  not one" -- and `clocks_coverage()` satisfies it while never finalizing. So did `cite_clocks()`.
  The rule's whole claim for itself is that the set is **derived** and so cannot go stale, and it
  was not: two counterexamples predate this branch, and a separate sentence treating "both coverage
  frames" as their own category is what kept the mismatch out of sight. Asserting the conclusion
  ("`clocks_coverage()` is not one, and the asymmetry is the point") on top of a definition that
  says otherwise would have left the next reader to find this again.

  **The test is two clauses, and both do work.** An exit **returns something that is not an
  `mc_result`**, which excludes `rbind` and `refinalize_clocks`, and excludes `print` because it
  hands `x` back. And it **reads the cells of `$scores` rather than its shape**, which excludes
  `clocks_coverage` (never touches it) and `cite_clocks` (reads `colnames()`, and no reduction
  moves a column name). That derives exactly `finalized()`'s five call sites, with no exception
  list. Verified by grep against the tree rather than by reading the rule.
- **The frame is sparser.** 50 rows to 82 on that run, which is the worst shape in the catalog --
  a plain `c("Horvath1", "Hannum")` request adds nothing, because every clock in it counts its own
  CpGs. 23% of rows carry a reason and 61% carry a coverage figure.
- **`reason` is unconditional, unlike `role` or `missing_cpgs` in `clocks_coverage()`.** Those have
  `all_columns = TRUE` as an escape hatch and `samples_coverage()` has no such argument, so a
  conditional column would be unreachable for code that wants it. An all-`NA` column on a clean run
  reads as "nothing is missing", which is exactly true.

**A `norm` row never takes a reason.** It counts a background panel, not a score cell, so the join
is masked to `panel == "score"`. This is the same line the row gate already draws.

The machinery is unchanged and moved wholesale to `R/gap_reasons.R`: `gap_reasons()` is the internal
entry point, returns `(id, clock_id, reason)` with **no** batch column, and joins on the sample id
alone, which `rbind` gate 1 already made disjoint. That is what keeps the label out of an internal
shape, so it stays a decision made once at each of the four exits.

**Do not re-export it.** One row per `NA` score is a nicer object to read, and
`sc[!is.na(sc$reason), ]` is one line. A second public frame over the same axis is what was wrong
with it.

## 2026-08-06 -- Three coverage messages promised an outcome the same call could withdraw, and "floor" is our word, not the reader's

The final audit of `coverage-gate-na`. Every finding is a **factual error in text a user reads**,
and none is a wrong number, so the suite could not have caught any of them -- tests here assert
*that* a message errors, never its wording. Each was found by rendering the message and reading it
against what the run actually returned.

**One shape produced all three: a message stating an outcome that a different part of the same call
decides.** A gate knows its own verdict. It does not know the verdict of the gate that runs after
it, and it does not know how a label it printed maps onto the columns the caller gets back.

**The column gate claimed a whole column for a half-blanked alias.** `gate_label()` deliberately
renders a sex-routed member as the **alias the caller can request** -- that is the invariant, and it
is right -- but the bullet under it then said "This clock scores `NA` for every sample". The alias's
column is `NA` only for the samples of that model's sex: on `DNAmGrip_noAge` with three female and
three male samples and only the male model gated, three scores are finite and `score_gaps()` returns
three rows, not six. The row tier had always stated the same fact correctly ("Those samples score
`NA` for that clock"), so the two tiers of one gate contradicted each other. The fix splits `fail`
on membership of `sex_routed_members()` and gives the modelled half its own bullet. **Do not merge
the two bullets back into one sentence with a hedge**: the plain case is the common one and its
claim is exact, and weakening it to cover the routed case would make every message vaguer to fix a
case most runs never hit.

**`norm_gate()` promised a score that `check_coverage()` then took away.** It ran before the column
gate by design -- declining a scheme empties a background panel, and every downstream fact reads the
resolved panel -- so it could not see the column verdict, and it ended "Those clocks are scored from
the raw betas instead". Because a scoring panel is a **subset** of its background, any uniformly
thinned matrix trips both gates, which made the contradictory pair the ordinary case rather than an
edge: a half-sampled `DunedinPACE` background prints "scored from the raw betas instead" and then
"This clock scores `NA` for every sample" four lines later.

**The bullet was deleted, not reworded, and the ordering was not touched.** Moving `norm_gate()`
after the column gate was rejected outright -- the ordering is what keeps declining a scheme a flag
flip instead of a branch (DECISIONS 2026-08-06, the norm gate entry). Deferring the warning until
the column verdict exists was rejected as machinery bought for one sentence. Deleting it costs
nothing: the lead line already says the clocks have too few normalization CpGs **to normalize**, so
the outcome is stated where it cannot be withdrawn, and R4 bans exactly this kind of
"scoring continues" reassurance anyway. The two remaining bullets are both advice, and both still
work when the column gate also fires -- lowering `min_clocks_coverage` fixes both panels at once.

**`rbind` blamed coverage for a difference the caller made.** `gate_same_normalized()` computed
`forced` as "did any record decline anything", not "was a clock that actually differs declined", so
an unrelated decline anywhere in any batch flipped the message to the coverage wording and
suppressed the branch that would have helped. Bind a batch that asked for `Horvath1` (declined, no
bmiq background) against one that passed `normalize = c(DunedinPACE = FALSE)`, and the refusal --
whose whole cause is `DunedinPACE` -- advised lowering `min_clocks_coverage`, which cannot fix it.
This is the exact mis-attribution `normalize_requested` was added to prevent, one gate away from
where the field was added. `normalized_diff()` now returns the clocks `gate_same_set()` will refuse
on, and `forced` is measured against those. Both branches were re-checked as reachable after the
change; the coverage wording still fires when a batch really did decline the clock that differs.

### "floor" is dev vocabulary and had leaked into the manual

R8's test is mechanical -- a word that is not a function name, an argument name, a component name, a
column name, or already in a message the user sees is ours, not the reader's. **"floor" fails it**,
and it is the single most-used word for these two arguments in `CLAUDE.md`, this log and the branch
plan, which is exactly why it leaked: three user-facing places, all added by this branch. It is now
in R8's example list in `dev/WRITING.md` so the next agent does not re-import it. Say
`min_clocks_coverage`, or "either argument", or "either value".

Swept in the same read and fixed: `clock_cpgs()`'s `@details` still described normalization that "is
part of its definition" and "is optional", which the same branch had retired; `calc_clocks()`
claimed "the call does not stop", which is R4's other banned shape and is now defined by what
happens rather than by what does not; "the raw betas" became "the beta values", the form the `DNAm`
param already uses.

### The suite growth stays, minus two expectations

799 -> 878 was the number to justify. The verdict is that it is proportional and it stays: +330/-79
test lines, of which one new file (114 lines) is a **new exported verb with a five-value returned
vocabulary**, and most of the rest is `test-coverage-gate.R` rewritten for inverted behaviour rather
than added to. Two expectations were genuinely vacuous and are gone -- a full-panel
`expect_silent()` that every other silent call in the suite already proves, and a `mc_batch_id`
uniqueness check implied by the `sort(gaps$id)` assertion above it. **The third candidate on the
list was rejected on inspection**: the `expect_silent()` at floors of `0.5` is not a full-panel
test, it is the only proof that the warn band **moves with** its floor, and the block was renamed to
say so. Final: 876 pass / 0 fail / 0 error / 0 warning / 2 skip, `NOT_CRAN=true`.

## 2026-08-06 -- A `NaN` is not a missing score, `min_samples_coverage` grades one panel everywhere, and the zero-CpG rule needed a test per axis

Three defects found by reviewing the branch as a finished thing. All three are consequences of the
same shape: a rule was changed in one place and a second reader of that rule was left behind.

**`score_gaps()` treated a `NaN` as a gap it had to explain, and died when it could not.**
`is.na(NaN)` is `TRUE` in R, so `na_mat <- is.na(scores)` swept in a value `check_score_values()`
deliberately **warns about and returns** rather than refuses. No member of the closed reason set can
claim one, so the blind-cell guard fired and the exported accessor a user calls to find out why a
score is missing died with "This is a package bug -- please report it." Reproduced at the default
floors on `Zhang2019EN` and on both `DNAmSex_Wang_Chr*` arms by setting one sample row to all zeros:
`(cpg_contrib - m * csum)` and `s` are then both exactly `0`, so the sample z-score is `0/0`.

D3's premise was the root cause and was wrong on R's semantics: "degenerate arithmetic here yields
`NaN` or `Inf`, a different value that `check_score_values()` already owns" is true of `Inf` and
false of `NaN`. The fix keeps the reason set closed rather than widening it. `missing_scores()` is
`is.na(m) & !is.nan(m)`, read at both sites, so a non-finite score is treated the way `Inf` already
was -- reported once by the value gate, and not a row in the gap frame. **Do not add a sixth reason
for it.** The vocabulary is API and it would duplicate a warning the caller has already had.

**`score_Zhang2019()` had no note channel where its sibling had one.** `split_moments()` sets a
sample's mean and sd to `NA` below 2 observed values on the moment domain, and
`score_DNAmSex_Wang()` answers that with `note_scoring_failure()`. The Zhang branch, which shares
the same `sample_scale` machinery, did not, so at `min_samples_coverage = 0` -- the value parity
runs at -- a sample with one observed cell scored a silent `NA` that no gate and no note could
explain, and landed in the same blind bucket. It now takes the note. It does **not** also take
Wang's bare `warning()`: that message is about the caller's matrix, so by the audience rule it
belongs on the cli side, and copying a call that breaks the rule is worse than not copying it.

**`samples_coverage()` still graded the norm rows against `min_samples_coverage`.** On `main`
`row_coverage()` read the background panel where a clock declared one, so warning on a
`panel == "norm"` row was coherent. The entry below moved the row gate to the scoring panel alone
and `say_low_samples()` was left reading both. Reproduced: a `DunedinPACE` run with 40% of the
background-only CpGs absent for one sample scores every sample, leaves `score_gaps()` empty, and
still warns "1 of 12 rows is under `min_samples_coverage` = 0.75". The warning now reads the score
rows only, and its count, its denominator and its filter example all moved together -- a lead line
counting one panel beside an example that selects both is the same defect one layer down.

**The zero-CpG rule is two clauses and the suite pinned neither.** `clock_gate_verdict()`'s
`present == 0` and `row_gate_one()`'s `cov == 0` are independent, and the only block testing them
set **both** floors to 0, where either one alone satisfies `all(is.na(...))`. Mutation-confirmed in
an isolated copy: deleting either clause left the suite green. The block is now two, one per axis,
each holding the other floor away from 0 and asserting `score_gaps()$reason` rather than `is.na` --
the reason names which gate decided, which is the only assertion the other clause cannot satisfy.
Both mutations now fail. **Do not merge them back into one block**, and do not assert `is.na` alone:
that is exactly what made the old block vacuous.

## 2026-08-06 -- The record keeps the normalization request beside the result, because `rbind` could not otherwise say who caused a mismatch

Making the norm gate able to decline a scheme (entry below) put a machine decision into
`provenance$normalized`, which `rbind` gates on. Two batches given the *same* `normalize` argument,
differing only in how much background the array carried, then aborted the bind with
"Use one `normalize` setting for every batch" -- advice the caller had already followed, about an
argument they could not change to fix it.

**Refusing was still right; only the attribution was wrong.** A column normalized in one batch and
raw in another is two different columns, and binding them would put two meanings in one vector. So
the gate stays on `normalized`. What was missing was the second fact needed to explain it, so
`provenance$normalize_requested` now records what was asked for, and the gate reads the pair:
requests agree and results differ means coverage, so it names `clocks_coverage()` and
`min_clocks_coverage`; requests differ means the caller, so it keeps the old advice.

**The request is keyed by batch and the result is not, and that asymmetry is the point.**
`normalized` is gated equal across batches, so one flat vector is honest. A request is a per-batch
input that two batches may legitimately disagree on -- the same shape as the two coverage floors,
and stored the same way, `stats::setNames(list(...), batch)` merged by `rbind` without
reconciliation. **`normalize_requested` is deliberately not gated**: differing requests with
matching results is a legal bind, and the case that makes it legal is real -- a batch that asked
for bmiq and was declined holds the same raw column as a batch that never asked.

## 2026-08-06 -- `min_clocks_coverage` reads both panels, and a thin background declines the scheme rather than blanking the clock. Normalization is no longer constitutive.

`min_clocks_coverage` now grades the scoring panel **and** the normalization background, and what
it decides differs by panel because the two shortfalls are different failures. Too little of the
scoring panel and there is nothing to compute from, so the clock scores `NA`. Too little of the
background and only the *scheme* is impossible; the raw betas are all still there, so the clock is
scored without normalization. Neither stops the call, and both warn.

That second half **reverses `NORM_CONSTITUTIVE`**. `resolve_normalize()` used to refuse
`normalize = c(DunedinPACE = FALSE)` outright, on the ground that quantile normalization "is part
of the clock definition, not preprocessing". Auto-declining a thin background would have done
silently exactly what that refusal forbade, so the refusal had to go rather than acquire an
exception. The constant is now `NORM_DEFAULT_ON`: quantile is **on by default**, bmiq is **off by
default**, and either can be declined -- by the caller, or by the gate on the caller's behalf.
The cost is real and accepted: a column labelled `DunedinPACE` can now hold an unnormalized score.
That is why the gate warns naming the clock, and why `provenance$normalized` records what the run
actually normalized rather than what was asked for.

**What forced it was a shape the old rule could not see.** `row_coverage()` measured a normalizing
clock's per-sample ratio on its *background* panel. Feed `calc_clocks()` a matrix cut down to the
scoring CpGs -- which is what `sim_DNAm()` returns, and what any caller who subsets to
`clock_cpgs()` to save memory supplies -- and every sample reads about 1.7% against Horvath1's
21368-CpG background, so a clock with a **complete** scoring panel was blanked for every sample,
under a message about `min_samples_coverage`. The column axis, on the same run, called the same
evidence benign and said so ("the absent CpGs are dropped from the BMIQ fit"). One axis cannot
treat a thin BMIQ background as documented-and-fine while the other treats it as fatal.

**Measured before deciding, and it is not a real-data failure.** The whole normalizing surface is
three clocks: `DunedinPACE` (quantile, 20000), `Horvath1` and `Knight` (bmiq, sharing one
21368-CpG gold standard). Against the staged cohorts every background is 95% to 100% present
(EPICv1: 99.99 / 95.03 / 95.03; 450K: 99.92 / 100 / 100), so a real array never approaches the
floor -- you would need over 5342 background CpGs absent. This is a **panel-subset** failure, and
subsetting to the scoring panel is a normal way to use the package, not a misuse.

**The gate runs before `resolve_cpgs()`, and that is what keeps it from being a special case.**
Declining a scheme empties that clock's background panel, and every downstream fact already reads
the resolved panel: `normalizes` is `length(norm_needed) > 0`, the record's `norm_*` counts, the
`sample_miss$norm` columns, and both scoring branches, which already fall back to `linear_score()`
when `normalizes` is `FALSE`. So the gate flips one flag and rebuilds the **norm half** of
`panels`; **no branch changed**, and no scoring panel moves.

**The declined background then leaves the position axis, and that is not a tidiness point.** The
scan runs before the gate, so `usable_cols` and `col_mean` initially span a background nothing will
read. Measured on `DunedinPACE` + `Horvath1` + `Knight` at n = 500 with the gate firing: leaving it
in carries **30215 usable columns and a 117 MB `partial_cache`** where narrowing gives 668 columns
and 2.6 MB. An earlier draft of this entry called that "a few columns", which was wrong by three
orders of magnitude in exactly the case the gate exists for. So `mc_cohort()` intersects both down
to `panels_union()` after the gate, before `resolve_cpgs()`, which keeps `usable_cols` order and so
keeps the position axis and `mc_block()`'s identity check intact. Gating *ahead* of the scan would
also drop the 98 ms `col_stats` read, but it would have to grade against `colnames(DNAm)`, where an
all-NA background column counts as present -- a verdict change, not a refactor.

**A simplification fell out, superseding the asymmetry recorded below.** The entry below defends
`row_gate_one()` taking its ratio on the gate panel and its zero rule on the scoring panel. That
split existed only to patch the consequence of gating rows on the background. With the background
now a cohort-wide column decision, the row gate reads the scoring panel for both, and `dead`
collapses from a two-panel comparison to `cov == 0`. `score_gaps()` stops reading the norm panel
entirely.

## 2026-08-06 -- Neither coverage floor aborts. A floor decides what does not get a number.

`min_clocks_coverage` aborted the call and `min_samples_coverage` warned and scored. They are the
same kind of statement about the same kind of evidence, and the split had no stated reason. Both now
score `NA`: a clock under the clock floor is `NA` for every sample in that batch, a sample under the
sample floor is `NA` for that clock alone, and every case still warns.

Aborting was wrong on its merits, not merely inconsistent. One under-covered clock in a request for
forty killed the other thirty-nine, and the caller could not read the coverage report that would
have told them what to drop, because no record was returned. The package already shipped the target
behaviour on a third axis: `warn_missing_covariates()` warns and says a sample with a missing
covariate scores `NA`. This brings two axes into line with an existing one.

**Zero observed CpGs is `NA` at every floor, under every imputation policy.** The verdict is not
special, the *test* is: `ratio < threshold` is `0 < 0` at a floor of 0, which is `FALSE`, so a fully
absent panel would run. A `mean` reduction then returns `NaN`, and a `sum` reduction returns the
bare intercept, which is a plausible-looking number computed from none of the caller's data. Parity
runs both floors at 0, and the `DNAmSex_Wang_*@cohort_450K` gaps are exactly this shape. The clause
drops the `clock_impute()` policy lookup the old test carried, so a `vendor_mean` clock with a fully
absent panel no longer returns one constant for every sample.

**One pass, column stat then column gate then sample stat then sample gate, and it never runs
backwards.** Accepted cost, stated rather than hidden: a sample that gets `NA`'d still contributes
to the cohort mean that fills every other sample's partial CpGs, and a column ratio is never
recomputed after samples are gated. No recursion means no re-derivation.

**On the column axis, skip the branch and seed an n x 1 `NA` matrix. On the sample axis, mask after
the branch returns.** Not "run the branch on an empty panel and let `NA` fall out", which yields a
wrong number rather than `NA`. The seed is mandatory: a `NULL` entry makes `as.numeric(results[[nm]])`
return `numeric(0)` and silently shrinks a dependent's score vector. Rows cannot be skipped, because
one matmul scores the cohort, so the mask goes in the dispatch loop where dependents have not yet
read `results`, and cross-sample clocks are masked in their raws before those enter `pending`.

**Two branch-level aborts went the same way, and one of them had to.** `zscore_raws()`
(`R/score_PhysAge.R`) stopped the whole call on `n < 2` and on any surrogate constant across the
cohort; `scan_missing_cpgs()` stopped it on a sample with no observed CpG on any scoring panel. Both
are this entry's abort one layer down, and the PhysAge one was actively incompatible with the row
gate: a surrogate whose samples are all gated is a constant column, so the stop would have let one
under-covered sample kill a run the gate had just decided to score `NA`. Both now yield `NA`.
`scale()` na.rm's its moments, so a masked sample leaves every other sample's z-score alone, and a
constant column has no z-score to give at all -- which covers a single-sample cohort and a surrogate
that observed none of its CpGs with one rule instead of two messages. The `score_union` argument to
`scan_missing_cpgs()` and `mc_spec()` went with the second abort, since nothing else read it.

**The ratio and the zero rule read different panels, and that asymmetry is deliberate.**
`row_coverage()` measures on the normalization panel where a clock declares one, so a `DunedinPACE`
sample dead on all 173 scoring CpGs still reads about 99% covered against the roughly 20k
gold-standard background. `row_gate_one()` therefore takes the ratio on the gate panel and the zero
rule on the scoring panel, the one the arithmetic reads. Without the split, removing the dead-sample
abort in `scan_missing_cpgs()` would have silently lost that catch.

**The NA reason set is closed, and derived rather than stored** -- `score_gaps()`, one row per `NA`
score, reasons `covariate`, `clock_coverage`, `sample_coverage`, `fit`, `dependency`, in that
precedence. Storing an n x k reason matrix would duplicate facts the record already holds per batch
and could drift from the gate that made the decision; deriving through the *same* helpers the gates
use makes drift impossible by construction and stays exact under `rbind`. Each floor is read for the
sample's own batch, never the reconciled `max`, because a cell's NA-ness was decided under the floor
its batch ran with. The unexplained bucket is a `stop()` inside the function, so a call that returns
is the proof that it is empty.

Two things fell out of building it that the design did not anticipate.

- **`clock_reads_cpgs()` had to bound the column gate too.** It graded every entry in `cpg_list`,
  which includes `GrimAgeV1` and the two `DNAmFitAge_{Sex}` members: clocks that declare a panel and
  get no coverage record. So a run could `NA` a clock on a panel `CLAUDE.md` says is not its own
  coverage, and `score_gaps()` then had nothing to read. Nothing is lost, because the union of
  panels that each cleared the floor clears it too.
- **The returned frame has to be self-contained.** Every `dependency` row must name a clock the
  reader can find rows for. The 14 sex-routed members never are one and cannot even be requested by
  name, so an alias inherits its member's reason instead. It is the only special case in the walk,
  and it reuses `sex_routed_members()` and `sex_rows()` rather than re-deriving the routing.

Two messages were also giving advice that cannot work, both found by rendering rather than reading:
"lower the floor to score them" is false for a panel at 0%, and the row gate reported a gate-panel
percentage that contradicted a verdict made on the scoring panel. Both are now conditional on the
case that is actually true.

**The tiers stay as separate warnings.** A warning is a catchable condition, so merging two
independent findings takes away a caller's ability to handle them apart, and the two tiers have
different next steps. Folding them would also put two quantities in one cli template.

## 2026-08-05 -- `id_index()`: one id join, and the survey that shrank the site list

The last open half of the `collapse` audit below. It asked for "one helper carrying key uniqueness,
an explicit unmatched policy and a row-count check, applied at all ten". The survey found a
different set than the one the to-do listed, and a different shape of helper.

**Seven of the ten listed sites are id joins, not ten, and there is an eighth the list missed.**
`assoc_report()` is a scalar one-row lookup inside a per-clock `lapply`, and `new_mc_citation()` /
`bind_by_key()` are list-name lookups (`entries[[k]]`, `e[[id]]`). None of the three takes an index
without being contorted, and none of them can silently misalign a sample. Unlisted and genuine:
`refinalize_clocks()` (`R/bind.R`), where `col[rownames(x[["scores"]]), 1L]` yields a silent `NA`
score for an id the pending block does not carry.

**An index, not a join.** The to-do's name was `left_join_by_id()`, returning a reindexed table.
That fits four of the eight; the rest index a plain vector (`mc_batch_id[...]`,
`pheno[["Female"]][idx]`) or need the index for something else (`merge_accel_data()` reuses it for
its column-conflict check). So the primitive is `id_index(key, id, what, unmatched)`, returning an
integer, and `R/utils.R` is where it lives. There is no row-count check to write: `match()` returns
`length(key)` by construction, and the one policy that does not (`"drop"`) is the one that means it.

**The unmatched policy is the point, not the uniqueness check.** Taking only `anyDuplicated()` was
considered and rejected: three sites -- `calc_accel()`'s batch column, `block_rows()` and
`refinalize_clocks()` -- turn an unmatched id into a **silent NA**, which is the failure the audit
actually names, and a duplicate check does nothing about it. So `unmatched` is explicit at every
call site: `"stop"` at six, `"drop"` at `joined_rows()` (which runs inside `check_pheno()`, before
`resolve_pheno()` raises the user-facing refusal), `"na"` at the two that raise their own cli
message about the user's own input (`resolve_pheno()`, `merge_accel_data()`).

**Each `"stop"` was justified before it was written, and none of them is `check_pheno()`.**
`check_pheno()` asserts the id column is unique but never refuses a `sample_id` with no pheno row,
so the reasoning for `calc_accel()`'s two sites is different and is now in a comment there:
`merge_accel_data()` only ever **adds columns** to `x[["pheno"]]`, which `resolve_pheno()` already
aligned one row per sample, so its id column still is `sample_id`. `block_rows()` takes a row subset
of the cohort its facts were built from. `attach_recorded()` was already a hand-written defect stop.
Verified by tracing a live run: all eight sites are reached, and no `"stop"` branch fires.

**`resolve_pheno()` got shorter, not just guarded.** It hashed the same key set twice --
`setdiff(sample_id, pheno[[pheno_id]])` to build the refusal, then `match()` to build the index. It
now reads the missing ids off the index, so the cli message is unchanged and there is one lookup.

The tests are four expectations on the helper's own branches, which nothing else reaches: a repeated
right key, an unmatched key under `"stop"`, and the two return shapes under `"drop"` and `"na"`.

**Parity passed** (maintainer run, 2026-08-05). `R CMD check` was not run. No roxygen or exports
changed.

---

## 2026-08-05 -- the positional axis is guarded with `identical()`, and `scan_missing_cpgs()` was measured before it was changed

Follow-on to the positions entry below, closing the session hand-off it left behind. One item was
taken as recommended, one was reversed by measurement, and one was declined.

**Why a guard and not a test.** The positions change bought 1.25s by trusting a bare integer. Its
worst failure mode is code that has not been written yet: anything that sorts, uniques or subsets
`usable_cols` between `resolve_cpgs()` and `mc_block()` leaves every position in range,
`block_cols()`'s bounds guard passes, and the run scores **the wrong CpGs and returns a number**.
The parked chunked front end is exactly that shape, since a per-chunk `usable` is a different
axis from the cohort-wide one the panels were resolved against. No test can cover future code; a
runtime check can, and the package already prefers a cheap greppable `stop()` for a defect class.

**`identical()`, not a hash.** The hand-off recommended hashing `usable_cols`, with the note that
`batch_hash()`'s canonical form is wrong here because order is exactly what must be preserved.
Reversed on measurement. `digest(algo = "xxhash64")` over the 414k vector is 1.5ms, so cost was
never the objection -- but `identical()` is **0.000ms per call at 200 reps** in every case measured
(same object, equal-content rebuild, differs only at the last element, one element shorter),
because R interns strings and compares `CHARSXP`s by pointer. So `resolve_cpgs()` returns the
vector it resolved against and `mc_block()` refuses anything not `identical()` to it. That is exact
rather than probabilistic, needs no `digest` round-trip, and stores a reference rather than a copy.
Verified it fires on a reordered axis and on a filtered one, and passes an equal-content rebuild.

**Three tests, nine expectations, 803 -> 812.** The alignment invariant stated directly
(`usable[present_idx] == present`, one assertion per panel role over the whole request rather than a
loop per clock, on a request carrying a real 20k norm panel). The guards: `block_cols()` on a `0`
and on an out-of-range position, plus `mc_block()` on a reordered axis. And the end of the chain,
which is what a wrong position actually corrupts -- `colnames(observed_panel(...)$values)` equals
the panel, so the positions handed to the matrix resolve to the CpGs the coefficients are named
for, plus `cached_cols()`'s pair on a cohort carrying partial NA. All confirmed non-vacuous by
mutation: shifting one position breaks the first, the guard message is the one that fires in the
second, and a one-element rotation of `usable_idx` breaks the third.

**The third proposed test is declined as covered.** "Two clocks whose panels overlap partially"
would catch a `dedup_panels()` or `panel_index` change fanning the wrong panel's positions to the
wrong clock -- which is what `test-score-wang.R`'s mixed-request golden already does: two clocks in
one call, each score compared against its single-clock value. `dedup_panels()` compares panels with
`identical()`, so a partial overlap and a disjoint pair take the same path and the overlap adds no
distinct failure mode.

**`scan_missing_cpgs()` did not cost what the hand-off said.** The claim was 0.59s of a 1.75s run,
"mostly the `intersect()` calls". Measured on the real 413k-column request: the whole function is
**78ms of a 1.85s run**, and `intersect()` is 40ms of that. The change is still worth taking, for a
reason that is not speed. `present_needed` and `needed_idx` were two separate lookups of the same
key set, which is failure mode 2 (one panel, two masks) waiting to be introduced. One
`match(needed_cpgs, cn, 0L)` now yields both, the score panel resolves the same way, and
`row_observed()` takes those positions instead of re-resolving names. 78ms -> 52ms, and the output
is `identical()` to the old formulation across four shapes, including the `score != needed` branch
that a norm panel triggers.

**`setdiff(present_needed, all_na)` stays**, though `present_needed[n_obs > 0]` would be equivalent
and save another 10ms. It is the one thing that makes `usable_cols` unique whatever upstream does,
and `resolve_cpgs()`'s comment cites it by name. Trading the sole enforcement of the axis's
uniqueness for 0.5% of a run is the wrong side of this change.

**Parity passed on the change** (maintainer run, 2026-08-05), alongside the `identical()`
equivalence check above. `R CMD check` was not run. No roxygen or exports changed.

---

## 2026-08-05 -- a resolved panel carries positions, not names, and `collapse` is declined

Two halves of one audit. The question was whether to take `collapse` as a hard dependency for its
join verb and its set operations. The measurement said the cost it was meant to fix was
not a set-operation cost at all.

**What the profile found.** 32 requested clocks (SystemsAge, Zhang2019, PCClocks, PCBrainAge plus
the 25 smallest bundled clocks), `sim_DNAm(n = 30)`, DNAm 30 x 414110, packs warm. `Rprof` is
useless here -- it sampled 0.35s of a 3.2s run -- so these are wrapper timers around the internals.
`block_cols()` was **1.15s of a 3.0s run** across 82 calls. The line was
`block[["usable_idx"]][cols]`, and its cost is flat in the number of keys: 14ms for 1000 names,
17ms for 20000. What is being paid 82 times is R hashing the **414k names of the table**, not the
lookup. `match(cols, usable)` costs the same, for the same reason.

**Why positions and not a faster match.** Three alternatives were measured against the same 82
panels (1.46M keys total):

| | cost |
| --- | --- |
| 82 x `idx[names]` (what shipped) | 1687 ms |
| environment table, build + 82 x `mget()` | 690 + 1777 ms |
| 82 x `match(panel, usable)` up front | 1720 ms |
| **one `match()` over the concatenated panels** | **130 ms** |
| then 82 x `idx[pos]` | 47 ms |

An environment is worse than the named vector, and resolving each panel separately just moves the
same 82 hashes earlier. The only thing that helps is hashing `usable` **once** for every panel at
the same time -- which `resolve_cpgs()`'s `split_panels()` already did, at
`match(unlist(panels), usable, 0L) > 0L`, and then threw the positions away to keep a logical.

**So the change is to keep what was already computed.** `split_panels()` retains the integer, every
clock's entry gains `score_present_idx` / `norm_present_idx` (positions in `usable_cols`), and
`block_cols()` / `observed_panel()` take positions. `usable_idx` loses its names. Measured after:
`block_cols()` 1.15s -> 0.01s, the whole call 3.00s -> 1.75s; on a 138k-column panel set,
1.11s -> 0.67s at n = 30 and 2.53s -> 1.87s at n = 300.

**The axis is `facts[["usable_cols"]]`, and it has one owner.** `resolve_cpgs()` used to take
`unique(usable_cols)` while `mc_block()` keyed on the raw vector. That was a no-op only because
`scan_missing_cpgs()` builds it with `setdiff()`, and once positions cross between them a silent
re-`unique()` would shift every index. The `unique()` is gone and the coupling is stated at
`resolve_cpgs()`.

**Parity passed on the change** (2026-08-05), which is what makes the swap safe to keep: a desync
between the two consumers of the axis would surface there as a wrong score, not as an error.

**Two guards changed shape rather than going away.** `block_cols()` used to catch a name outside
`usable`, where the symptom was an NA column. The positional failures are different and worse: a
`0` **silently drops** an element and shrinks the panel, so the guard now tests the positions
themselves (`is.na | < 1 | > length(usable_idx)`) before indexing. `mc_block()` gained the matching
check for the cohort-mean columns, which is where the one remaining name lookup lives, paid once.

**`cached_cols()` stopped searching too.** It was `intersect(present, colnames(partial_cache))`,
i.e. a second name hash per panel, invisible in the profile only because simulated betas have no
NAs. It now reads a logical mask over `usable`, built once in `mc_block()`. The mask is `NULL`
when nothing was partly missing, which keeps the old short-circuit -- without it, `compute_coverage`
went from 0.04s to 0.17s paying mask lookups on cohorts that have no cache at all.

**`component_present()` returns a pair now**, `list(cols, idx)`, and selects with
`score_present %in% names(coef)` instead of `intersect(names(coef), score_present)`. Same set, but
it hashes the **component** (hundreds of coefficients) rather than the panel, and it keeps the
panel's own order so the positions stay aligned. The order of `obs[["cols"]]` therefore follows the
panel rather than the coefficient vector. Nothing downstream depends on it: every consumer indexes
by name off `obs[["cols"]]`.

**Why `collapse` is declined.** Its `join()` defaults are exactly the silence the dependency was
meant to remove -- `validate = "m:m"` performs no check and `multiple = FALSE` takes the first
match in `y` -- so every site would carry `validate = "1:1"` plus a `require` list, and would be
wrapped anyway to raise the package's own cli text. Its `pivot()` has nothing to accelerate: no
exit here reshapes, `shape_scores()` builds the long frame with `rep()` and `as.vector()` straight
off the score matrix, and `samples_coverage()` is 0.10s at n = 300. And `fmatch` would at best
shave a constant off the line that positions delete outright. The install weight, the GPL-2 | GPL-3
terms and a second Rcpp-linking dependency buy nothing measured.

**`merge(sort = FALSE)` was the other candidate and is also declined.** It does fail loudly on a
duplicated right key, because the result gains rows and an `nrow()` check catches it. But at
10k x 10k it costs 6.5ms against 0.5ms for `right[match(...), ]`, its row order under
`sort = FALSE` is documented as unspecified, and `anyDuplicated()` on the key is free. The
guarantee is worth having; `merge` is not how to buy it. The remaining work is one internal
`left_join_by_id()`, which shipped as `id_index()` in the entry above.

---

## 2026-08-05 -- two settled word choices in user-facing text: "confirm", and how a clock is named

Both are vocabulary, so neither can be linted and both drift silently. They are written into
`dev/WRITING.md` section 2 rather than left as a preference.

**"confirmation" / "confirm", not "consent".** Four doc sites used "consent" for what a yes-or-no
prompt does. `consent` reads as a legal term and overstates it. The replacement was scoped to text
a user can see: the `ask` donor param and the `@details` on `download_mc_assets()`,
`load_mc_assets()` and `clear_mc_assets()`. **The internal `mc_consent()` and
`mc_consent_delete()` keep their names**, along with the code comments and the two test names, on
the same line CLAUDE.md already draws between an audience and an implementation. Renaming them
buys nothing a reader can see and touches a mocked binding in the suite. No cli message used the
word, so the string surface was already clean, and `README.Rmd` had independently written
"downloading requires confirmation".

**A clock id in prose follows the reader, and the reader meets it in two different places.** The
docs spelled the sex classifier both ways with no rule: `predict_sex()`'s example requested
`c("DNAmSex_Wang_ChrX", "DNAmSex_Wang_ChrY")` while its `@returns` described the output as "the
two `DNAmSex_Wang` scores". Both were backwards. Verified: `resolve_clocks("DNAmSex_Wang")` gives
both members, and `predict_sex()` returns columns named `DNAmSex_Wang_ChrX` and
`DNAmSex_Wang_ChrY`. So a **request** takes the shortest token that resolves, which is the group
id, and a **returned column** is named in full, because `DNAmSex_Wang` is not a column anyone will
find in their frame. The README example now shows both at once: a one-token request producing two
long column names.

`README.md` was regenerated with `devtools::build_readme()` rather than hand-edited. The diff came
back as exactly the two intended edits with no churn, which is the check that the seeded chunks and
the staged assets still render faithfully.

---

## 2026-08-05 -- repeated roxygen prose is hoisted to the donor, and donor text names effects

An audit of every `@details` block found ten defects. Two of them were the same defect: text
copied between topics, drifting or over-specific at one call site and correct at another. So the
fix is structural, not per-topic.

**What moved to `R/mc-params.R`.** The cross-sample paragraph, verbatim on `as.data.frame`,
`as.matrix`, `calc_accel` and `score_associations`, is now the `Clocks that use all the samples`
section, pulled in with `@inheritSection`. `long`, identical on two topics, is a donor param. That
is the second `@section` on the donor and confirms the mechanism generalises past
`The assets directory`: a `@section` renders after `\value`, which is the right place for a
caveat about the returned value, and one edit now reaches four pages.

**Donor text names the effect, not the operations.** `ask` read "Asks for consent before a
download or a delete". Five of the six recipients cannot delete anything. An enumeration in shared
text is the worst kind of duplication, because it is one list that has to stay true of N call
sites and nothing checks it. It now reads "before the assets directory changes", which is true
everywhere and stays true when a seventh topic takes `ask`. This also fixed the `load_mc_assets()`
`@details`, which read as though the function refuses outright in a non-interactive session when
it refuses only a download of a missing asset.

**Three things were deliberately left duplicated**, all for the same reason: hoisting would
replace visible duplication with an invisible wrong default. `...` is identical on 9 of 11 topics,
but its three sentences mean opposite things and a wrong "Not used." on a topic that really passes
`...` through is invisible in the rendered page. `n` and `p` differ between the two print methods,
and `n` collides with `sim_DNAm()`'s different default. `optional` and `row.names` sit on two
topics of which only one may inherit, because the donor's `x` is an `mc_result` -- so the saving is
zero. Moving `x` out of the donor to close that footgun was costed and rejected: about ten topics
inherit it.

**The audit's own headline finding was unrelated to hoisting and worth recording.**
`samples_coverage()`'s `@details` said "Only the clocks in the returned scores of `x` get a row. A
clock that scores as part of another clock gets none." Both sentences were the exact inverse of
`covered_ids(per_clock)`, and they contradicted the paragraph's own fourth sentence. Measured on
`c("DNAmFitAge", "Horvath1")`: 12 rows are not score columns and 8 score columns have no row. The
`#` comment above the function had drifted the same way and was corrected with it.

---

## 2026-08-05 -- `load_mc_assets()` returns a classed `mc_assets`, so it has a printer

`load_mc_assets()` returned a bare named list of packs, and printing one dumped every coefficient
matrix in it. The four packs are the heaviest objects the package hands back, so the default
printer is the worst one it could have.

**The fix is a class, not a wrapper.** `new_mc_assets()` is `setNames()` plus
`class = c("mc_assets", "list")`, applied at both exits (the empty one included, so the shape is
uniform). Nothing else changes: `ext_data` still reaches `mc_canonicalize_ext_data()` through the
`is.list()` arm, `packs[[gid]]` still resolves in `clock_pack()`, and the existing tests that read
the value by name pass untouched.

**What it prints is `n_clocks` and `n_cpgs`, per group, because the reader has already met those
two.** They are the columns of `list_mc_assets()`. Both come off the pack itself (`clocks`,
`cpgs`), which every one of the four encoders in `sync.R` sets, rather than off the declared
registry -- a pack handed in through `ext_data` need not be a group the registry knows.

**The one departure from the shared grammar (`R/print.R`) is deliberate:** no blank line between
the `$group [...]` lines. In `mc_result` and `mc_sim` a `$name` section is a distinct component
with a data block under it. Here the sections are elements of one homogeneous axis and there is no
block, so they read as a list. Header, `fmt_section()` and `plural_count()` are the shared ones.

`mc_assets` also joins `DOC_TYPES` in `R/dev-utils.R` and the type table in `dev/WRITING.md`, and
`print.mc_assets` joins the list of topics whose `x` **must not** inherit from the `mc-params`
donor.

---

## 2026-08-04 -- source-tree-only tests are build-ignored, not CRAN-skipped

The first `devtools::check()` after the trim came back `1 error | 1 warning | 0 notes` in 51s (it
did not hang -- see the tier entry below for why). Both findings had the same root cause and the
same fix, and both falsify something asserted earlier the same day.

**The error.** `test-source-hygiene.R` failed twice in the installed package. The prediction was
that its scans would "pass vacuously over an empty file list" and that `skip_on_cran()` made that
an honest skip. **Both halves were wrong.** `scan_sources()` is `unlist(Map(f, R_PARSED, ...))`,
and `unlist(list())` is `NULL`, not `character(0)` -- so `expect_equal(NULL, character(0))` is a
*failure*, not a vacuous pass. And the gate never fired, because **`devtools::check()` sets
`NOT_CRAN=true`**. A `skip_on_cran()` is inert in exactly the check most likely to be run locally.

**The warning.** `checking for unstated dependencies in 'tests'` flagged `duckdb`, from
`test-fixtures-parity.R`. This one **cannot be fixed by any runtime skip**: the check is a *static
scan of the shipped sources*, so a `duckdb::` behind `if (parity_on)` still counts. `duckdb` and
`DunedinPACE` are deliberately undeclared -- the parity tier is maintainer-gated and CI installs
them itself -- so the only way to satisfy the scan without declaring a dependency the package does
not have is for the file not to be in the tarball. (`DBI` is in `Suggests` and was never at issue.)

**The rule that falls out.** A test whose subject is the **source tree** rather than the package's
behaviour does not ship. `test-fixtures-parity.R` reads `data-raw/methylCIPHER-meta/` (already
build-ignored) and `test-source-hygiene.R` reads `R/*.R` (an installed package ships `R/*.rdb`);
neither can ever work from a tarball, under any `NOT_CRAN` value. Both are now in `.Rbuildignore`,
joining the existing `^R/dev-utils\.R$` -- which is where `test_parity()` lives, so the precedent
was already set and simply had not been followed through to the test files.

Verified by building the tarball and listing it: 28 test files ship, neither of these two among
them. `skip_on_cran()` was then **removed** from the hygiene tests -- with the file build-ignored
the gate is dead weight, and worse, it implies the file ships. They now run on every
`devtools::test()`, which is the dev loop they exist for.

**What this does not change:** `skip_on_cran()` stays the right tool for the ~86 internal tests that
*do* ship and *can* run installed. The distinction is whether the test can execute at all outside
the source tree, not whether it is internal.

---

## 2026-08-04 -- Horvath1 is admitted to parity under a measured BMIQ snapshot

The third tolerance regime that 2026-07-29 declined to decide. Deciding it retires the last
hand-authored clock golden in the always-on tier.

**The reading being tested.** The `horvath` block is skipped wholesale because the oracle filled
completely-absent probes server-side with an unpublished constant, so the residual tracks the
absent-probe count. `Horvath1` was flagged as the exception -- the one clock the oracle BMIQ'd --
whose gap should therefore be a *normalization* gap, fixable by turning normalization on rather
than by widening a tolerance. That was an argument, never a measurement. It is now measured, and
it holds:

| cohort | scoring panel | `normalize` off | `normalize` on |
|---|---|---|---|
| `cohort_450K` | 353/353, zero absent | max_abs **7.72** | max_abs **0.114**, max_rel 1.93e-03 |
| `cohort_EPICv1` | 334/353, 19 absent | max_abs 6.53 | max_abs **3.96**, max_rel 1.71e-01 |

So on the complete panel, normalizing closes 98.5% of the gap and what is left is a
BMIQ-implementation difference. On the 19-probe-short panel it closes almost nothing, because
there the *fill* gap dominates -- exactly the original diagnosis, now with the two effects
separated by data rather than asserted.

**Why the split is a guard, not a second tolerance.** Admitting `cohort_EPICv1` at 4.0 years would
be the vacuous bound 2026-07-25 warned about. The test instead **skips unless the cohort leaves
zero scoring probes absent**, which is the precise condition under which the oracle's undisclosed
input cannot contaminate the comparison. That predicate is computed from the loaded matrix, so no
cohort is named anywhere and a restaged or extended cohort re-decides itself.

**Why a snapshot rather than an agreement target.** 1.9e-03 relative is far too loose to be an
agreement claim and is not offered as one; `PARITY_REL_TOL` stays 1e-10 for everything that is a
real gate. What this pins is *that the residual does not move*, which is the only thing worth
asserting against an oracle whose own pipeline we cannot reproduce. Verified deterministic --
bit-identical `max_abs`, `max_rel` and score checksum across three runs -- so the ceiling sits just
above the measurement instead of being padded, and drift will actually trip it. A pair that clears
the absent-probe guard with no entry in `HORVATH_NORM_TOL` **fails**: a newly admissible pair needs
its residual measured, never defaulted to a neighbour's.

**Membership is derived.** `is_normalized_horvath()` is horvath-online **and**
`clock_norm_scheme() %in% NORM_SCHEMES`. Today that is `Horvath1` alone -- of the 15 horvath-online
clocks, 13 declare `none` and `Horvath2` declares `noob`, which is not expressible here. (CLAUDE.md
previously said "14 of the 15 declare `scheme = none`"; corrected in the same pass.)

**What it replaced.** The `test-normalize.R` BMIQ golden, which composed
`betanorm::bmiq_calibration()` with the linear score by hand. **This is a real trade and worth
naming**: the deleted test was exact and ran on any machine with `betanorm`; the new one is
maintainer-gated and bounded at 1e-03. What is bought is that the gate is now against the
**oracle** rather than against the same library we call, so it can catch a wiring error the
hand-composed golden shared. The *record* half of the old block did not move -- `provenance$
normalized`, `cov$normalizes`, the `sample_miss$norm` column are things parity never looks at, so
they stay in `test-normalize.R` under a name that says so.

Standing parity state goes 264 -> 266 blocks.

---

## 2026-08-04 -- the always-on suite is cut to ~800, and CRAN sees only the exported surface

The suite had reached ~1284 expectations across 27 always-on files and was no longer maintainable:
a routine change touched a dozen files, and the cost of that was not buying proportional safety
because **the parity tier already proves the arithmetic**. Trimmed to 801 local / 391 under
`NOT_CRAN=false`, 0 failures either way, with the parity file untouched.

**The two cuts, and why they are different.** Deletion was applied to tests that could not fail
for a reason anyone would act on: goldens parity already owns (every catalog clock declares a
fixture, so a broken scoring branch fails parity before it fails a unit test), assertions about
maintainer-side plumbing that "Test altitude" already banned, message-wording pins, and loops
restating one invariant over many clocks. Gating with `skip_on_cran()` was applied to what
survives but is **internal** -- the kernel contracts, the catalog accessors, the chunking path,
the asset transfer mechanics. Those still run in dev and CI; they just stop being CRAN's problem.

**What CRAN actually runs now, stated plainly so nobody misreads a green check:** the smoke tier
in the default configuration, the front-door refusals, and the record contract. **No numeric
gate.** That is not a regression -- parity was already `MC_PARITY`-gated and CRAN-skipped, so CRAN
never proved a score. The change is that this is now visible instead of implied by a suite that
looked comprehensive. A CRAN green says the package loads, refuses correctly, and returns a
well-formed `mc_result`; it says nothing about the numbers.

**But `skip_on_cran()` is narrower than it sounds, and the trim should not be read as "these tests
now only run locally".** `NOT_CRAN` is unset on r-hub and on a GitHub Actions `R-CMD-check`, so the
gated tier runs on both -- across platforms, which is where a Windows-encoding or a long-double
difference would actually surface. What the flag buys is CRAN's own machines not paying for a tier
that cannot tell them anything. `devtools::check()` is the opposite case: it sets `NOT_CRAN=true`
and runs the whole suite, so a local check and a tarball check are not the same run.

**Addendum, same day, from the first `devtools::check()` after the trim.** Two files needed
`.Rbuildignore`, not `skip_on_cran()` -- see the entry below.

**Four goldens were kept against the "parity owns it" rule**, because parity is structurally blind
to them and the blindness is not incidental:

- **Alias routing** (`test-score-fitage.R`, `DNAmGrip_wAge`). Fixtures are declared on the 14
  routed *members*, never on the 7 aliases -- so *which sex's model scored which sample* has no
  parity coverage at all.
- **DunedinPACE quantile normalization** (`test-score-dunedin.R`). Since the reference golden moved
  to the parity tier earlier today, this is the only always-on proof normalization is applied.
- **PhysAge mean-divisor fill offset** (`test-score-physage.R`). Fill landing inside vs outside the
  divisor is a silently wrong number on a degraded panel; parity scores clean panels.
- **Wang mixed-request domain isolation** (`test-score-wang.R`). Parity scores one clock per call,
  so `sample_scale` contamination between two clocks in one request cannot appear there.

The BMIQ golden in `test-normalize.R` was kept for the same class of reason, and then **superseded
within the day** -- see the next entry.

**`test-sim-smoke.R` is untouched and ungated.** It is the only tier running `calc_clocks()` in the
default configuration and the only caller of `sim_DNAm()`, which is exactly what a CRAN machine
should be exercising. **`test-source-hygiene.R` is gated, and not because it is internal**: an
installed package ships `R/*.rdb`, not `R/*.R`, so `list.files(..., "\\.R$")` returns nothing there
and both scans would pass vacuously over an empty file list. `skip_on_cran()` converts a fake pass
into an honest skip.

**The gate goes inside the block, never at file level.** testthat runs top-level code at collection,
so a file-level `skip_on_cran()` reads as one skipped file rather than N skipped tests and hides how
much is off. One call, first line of each gated `test_that`; there is no top-level `skip_on_cran()`
in any file. Under `NOT_CRAN=false` the suite reports **89 skipped blocks** spread across 24 files
(the parity tier being one of them), which is how to check the gating is per-block rather than
per-file: a file-level gate would have shown 24.

---

## 2026-08-04 -- the parity tier gates its generator, and the suite runs silent

Two separate complaints about the same thing: the default `devtools::test()` was unreadable.

**The parity wall.** `run_parity_target()` opened with `skip_if_no_cohort()`, so with the tier off
all 263 generated targets ran far enough to skip. testthat prints skips grouped by reason **with a
location per skip**, so one sentence came back as ~90 wrapped lines of
`test-fixtures-parity.R:339:9`, repeated. The reason is identical every time and the locations are
all the same line, so the block carried exactly one bit of information and buried the run summary
under it.

The fix is to gate the **generator** rather than the generated test: `staged_cohorts` (the flag AND
a live duckdb connection) drives `parity_targets()`, the PhysAge loop, the census test and the
Dunedin golden, and a tier that cannot run emits **one** `test_that` saying so, plus one per
unstaged cohort. Verified generation is otherwise untouched -- with both cohorts staged the file
still produces 264 blocks, the same 146/28/30/56 split across `core`/`fitage`/`horvath`/`packs`.

**Why not just quieten the reporter.** Because the skips were never informative individually. The
counterpressure is real and was weighed: the block count is how a parity run is read (CLAUDE.md's
"264 blocks / 32 skip", checked against each other before the pass number), and a generator gate
makes that count depend on what is staged. That is the right dependency -- a test that had no cohort
to read was never a test -- but it means the standing figure is now "with both cohorts staged", and
the guard against a *dropped fixture* has to be the census test, which is already there and already
ungated by cohort. `skip_if_parity_off()` and `skip_if_no_cohort()` are gone; nothing else used them.

**The message noise.** Unrelated in mechanism, same symptom. Three sources, all of them the package
working correctly:

- `mc_spec()`'s full-panel note (`say_full_panel_clocks()`) fires once per spec build, so any test
  touching `Zhang2019EN` printed three lines. It is emitted from `mc_spec()`, **not** only from
  `score_cohort()` -- a test that never calls `calc_clocks()` still triggers it.
- `say_pending()` on a multi-batch `rbind` in `test-bind.R`, at two sites that were not asserting on
  it (the one that asserts uses `expect_message()` and stays).
- `utils::download.file(quiet = FALSE)` in `mc_fetch()`. This one is environment-dependent and was
  the confusing one: with `method = "auto"` a `file://` URL takes the `internal` method and says
  nothing, but an interactive session with `options(download.file.method = "libcurl")` -- what
  RStudio/Positron set -- prints `trying URL` / `Content type` / a progress bar. Those go to
  **stderr as raw text, not as conditions**, so `suppressMessages()` cannot touch them; only
  `capture.output(type = "message")` can. `test-mc_data.R` has a local `quietly()` that does both.
  The package side is unchanged: a progress bar on a 300 MB pack download is worth having.

Same file's one warning came from `download.file()` warning on its way to the failed status that
`mc_fetch()` turns into the abort under test; the test now suppresses it, because it restates the
abort in worse words and is not a second assertion.

**Result: 0 fail, 0 warn, 2 skip on a default run, with no stray output.** Parity was not run.

---

## 2026-08-04 -- `codebook()` is reinstated, and it is blocked upstream

**Reverses the 2026-07-31 decision** that kept D3 out of the finalizer family. That entry rejected
`codebook` on three grounds: it touches no result, it reads a `bib_key` that does not exist, and it
is a third view of `list_clocks()` / `clock_cpgs()`. The first is true and is not disqualifying, the
second named the wrong field, and the third is what changed.

`codebook()` returns `data.frame(clock_id, description)` and dispatches like `cite_clocks()`. It is
not a third view of the catalog: `description` is a sentence per clock saying what the score means,
which is the one column `list_clocks()` does not carry and cannot be derived from anything the
package holds. That is the whole justification, and it stands or falls on the column existing.

**Blocked upstream, and that is where the work is.** `description` is not verified in
`methylCIPHER-meta` across the 137 clocks. The method itself is small. Sourcing and checking one
description per clock is not, and it is upstream work rather than package work. **Do not build
against a partially populated field** -- a `codebook()` that returns `NA` for most of the catalog is
worse than no method, because it looks like a defect in the package.

## 2026-08-04 -- `duckdb` and `DunedinPACE` leave Suggests: a dep is declared for code, not for tests

Both were in `Suggests`, and `DunedinPACE` also needed `danbelsky/DunedinPACE` in `Remotes:`. Both
are gone; `Remotes:` now carries `hhp94/betanorm` alone.

**The line is where the *package* reads the dependency, not whether a test does.** `betanorm`
appears in `R/`: `require_betanorm()` in `R/score_normalized.R` gates every normalizing branch, so a
user who passes `normalize =` needs it at runtime, and it stays declared with its `Remotes:` entry.
Neither `duckdb` nor `DunedinPACE` appears anywhere in `R/`. They are read only by
`tests/testthat/test-fixtures-parity.R` and `tests/testthat/test-score-dunedin.R`, and both tiers
are already gated for other reasons -- parity needs `MC_PARITY=1` plus a staged duckdb cohort no
user has, and the Dunedin golden needs a GitHub-only package. Declaring them made every installing
user resolve a dependency for a tier they cannot run, and in `DunedinPACE`'s case made a CRAN
submission carry a `Remotes:` entry for a package CRAN does not have.

**So the reference golden moved to the tier that matches it.** The degraded-coverage test against
`DunedinPACE::PACEProjector()` was the only third-party-dependent test in the always-on value-golden
tier, where an undeclared dep means it skips silently on every machine forever. It now lives in
`tests/testthat/test-fixtures-parity.R`, behind the tier flag and **with no
`skip_if_not_installed()` on the reference at all**. That is the point: parity only ever runs on a
maintainer machine, which has both `duckdb` and `DunedinPACE`, so a skip there cannot protect
anybody and can only hide a silent non-run. If the reference is missing the test errors, which is
the correct signal on the one machine that runs it. It needs no duckdb and no staged cohort -- it
builds its own holed panel -- so the file's guards split: `skip_if_parity_off()` is the flag alone,
and `skip_if_no_cohort()` calls it and then demands a connection.

The other four tests in `test-score-dunedin.R` are in-package goldens with no third-party dep and
stay in the always-on tier. Measured after the move: always-on 1271 pass / 0 fail, parity 264 blocks
/ 707 pass / 32 skip / 0 fail (was 263 / 699 / 32 / 0 -- one block and eight expectations, which is
exactly the moved test).

**What this costs, stated plainly.** The degraded-coverage path is now checked only when a
maintainer runs parity, and no CI job gets it from DESCRIPTION. Accepted: the alternative is a
CRAN-facing DESCRIPTION advertising deps for tiers CRAN never runs. **A CI job that means to run
that tier must install `duckdb` and `DunedinPACE` itself.**

## 2026-08-04 -- `payload_hash_of()` stops hashing the serialize header, re-addressing every pack once

`payload_hash_of()` hashed `serialize(payload, version = 2L, xdr = TRUE)` as a raw stream.
`serialize()` writes a 14 byte header whose bytes 7 to 10 carry the **writer's R version**, so the
content-address moved on an R upgrade with not one coefficient changed. That is the one thing the
identity key exists to prevent: `payload_hash` sets the pack filename and the release tag, and its
whole job is to make re-upload of unchanged weights a no-op. It is now
`digest::digest(payload, algo = "sha256", serializeVersion = 2L)`, whose `skip = "auto"` drops that
header.

**The fix is not free: it re-addressed all four packs once.** `pcbrainage`, `pcclocks`, `systemsage`
and `zhang2019` each have a new hash, so `R/sysdata.rda` declares four filenames and four release
tags that did not exist before. The assets were re-uploaded under the new tags before this landed,
so no download breaks. Every existing user's cached packs become **superseded** on upgrade, exactly
as any `payload_hash` move does -- `list_mc_assets()` reports them and `clear_mc_assets()` reclaims
them, which is designed behaviour and not a special case. A one-time cost, paid to stop paying it on
every R release.

## 2026-08-04 -- The prose files split from one rule set into two, and stop being hard-wrapped

`dev/WRITING.md` section 10 governed `vignettes/*.Rmd` and `README` with a single rule set. Writing
the README exposed three things wrong with it. The detail is in that file. What matters here is
why each changed.

**The build split is the load-bearing correction.** The old section said an evaluated chunk "must
run offline, with no asset", derived from `R CMD check` building vignettes with no network. That
premise is true of vignettes and **false of `README.Rmd`, which is `.Rbuildignore`d** and is
rendered by the maintainer alone. Nothing on CRAN executes it. Applied as written the rule would
have forbidden the README that now exists, which scores `SystemsAge` against a staged asset and
shows the coverage record doing real work. The cost is that rendering `README.md` needs the assets
staged, so a collaborator with an empty assets directory cannot rebuild it. Accepted: the
alternative is a README that cannot show the package's most interesting output. `README.md` itself
is **not** ignored and does ship, so what lands in it is still held to the rules.

**Prose is no longer hard-wrapped in those two files.** One paragraph is one source line and the
editor soft-wraps. A hard-wrapped paragraph reflows on any edit, so changing one word rewrites five
lines and the real change is lost in the diff. Code blocks stay at 80 columns, because that text is
read as code and nothing reflows it. Scoped to `README.Rmd` and `vignettes/*.Rmd`. **`dev/` docs,
including `WRITING.md` itself, stay hard-wrapped.**

**ASCII binds the author, not the run.** The rule was stated as though it covered the whole file,
which is unachievable: cli emits its own symbols and captured chunk output carries them. Suppressing
them with `options(cli.unicode = FALSE)` was tried in `README.Rmd` and then removed, because it made
the rendered output disagree with the reader's own console, which is the one thing pasted output
exists to demonstrate. So: never hand-write a non-ASCII character, and leave cli's alone. Pandoc is
the third case and needed a fix rather than a rule, since its `smart` extension manufactures curly
apostrophes out of ASCII input. `README.Rmd` disables it with `md_extensions: -smart`.

**`CLAUDE.md` gains an invariant making the read mandatory before any user-facing text is edited**,
widened from the roxygen-only wording it had. The roxygen bullet no longer restates it.

---

## 2026-08-04 -- The assets dir stays `"cache"`, and the CRAN claim that justified it was false

Two separate things, and the first is why this entry exists at all. The rule does not change. Its
justification was wrong, and it was wrong in the direction that forbids a legal option.

**The policy claim was false.** `CLAUDE.md` said the dir must "never" be `which = "data"`, and
`DECISIONS.old.md` (2026-07-24, section 5) called such a change "a policy violation". Re-fetched
from <https://cran.r-project.org/web/packages/policies.html> on 2026-08-04, verbatim and unchanged:

> For R version 4.0 or later (hence a version dependency is required or only conditional use is
> possible), packages may store user-specific data, configuration and cache files in their
> respective user directories obtained from `tools::R_user_dir()`, provided that by default sizes
> are kept as small as possible and the contents are actively managed (including removing outdated
> material).

All three of data, configuration and cache are permitted. Two consequences. The "actively managed"
clause attaches to all three equally, so it is **not** evidence for `"cache"` over `"data"` --
`clear_mc_assets()` is required either way and stays exactly as it is. And "sizes kept as small as
possible" is satisfied by the consent design, not by the directory: nothing downloads unprompted,
so the default size is 0 bytes everywhere. Neither condition discriminates. The archive is not
edited, so this entry is the correction.

**The sizes that framed the question were wrong by roughly 9x.** The corpus is 43.0 MB total
(SystemsAge 22.5, PCClocks 8.9, PCBrainAge 6.7, Zhang2019 5.0), not the "several hundred megabytes"
the question was posed against. That figure came from the hand-written example output in
`vignettes/assets.Rmd`, which shows about 402 MB and does not match what `list_mc_assets()` returns.
Recorded because it moved the argument: at 43 MB a re-download is cheap, which weakens the
durability case that was the only case for `"data"`.

**The decision: keep `"cache"`, on platform merits.** Both are legal, so this is a trade-off, and it
is genuine rather than a clear win.

- Windows is where the hard failure lives. `"data"` is `%APPDATA%`, the roaming half of the profile:
  under a roaming profile it is copied across the LAN at every logon and logoff, and under Folder
  Redirection it lives on a network share so every read during scoring is SMB traffic. Roaming
  quotas around 100 MB are common and 43 MB spends a large slice of one. `"cache"` is
  `%LOCALAPPDATA%`, which never roams and which Storage Sense and Disk Cleanup do not touch.
- macOS is where the soft failure lives. `~/Library/Caches` is Apple's discardable location, sits
  in Time Machine's default exclusions, and is what third-party cleaners target. But there is no
  scheduled purge, and the cost when it happens is one consented re-download of at most 43 MB.
- **Severity is asymmetric, and that decides it.** The `"cache"` cost is consented, one-shot and
  user-initiated. The `"data"` cost on institutional Windows is unconsented, recurring, and paid by
  users who may never score an external clock again.
- A re-download is already routine anyway. Filenames are content-addressed, so every sync that moves
  a `payload_hash` orphans the old pack and every user re-fetches that group. A purge is the same
  event the normal lifecycle already produces; `"data"` would only make it rarer, not novel.

**Durability is `MC_ASSETS_DIR` / `set_mc_assets_dir()`, and the vignette must sell them on that.**
It currently sells them on control. This is the third option from the to-do item, taken deliberately:
the genuinely offline case -- air-gapped node, no-egress cluster -- is already told to use
`ext_data = <path>`, so it is not on the default dir at all. The default's durability matters least
exactly where the offline risk is worst.

**Precedent, measured rather than recalled.** On a machine with both installed,
`BiocFileCache::getBFCOption("CACHE")` and `ExperimentHub::getExperimentHubOption("CACHE")` both
resolve under `R_user_dir(..., "cache")`, and ExperimentHub was holding 1.9 GB there -- 45x this
package's whole corpus. Those are the two general-purpose data caches of the Bioconductor stack,
which is the stack this package's users already run. R's own `R_LIBS_USER` is under `%LOCALAPPDATA%`
on Windows too.

**`torch` is the one CRAN precedent that does otherwise, and it does not transfer.** `inst_path()`
reads `TORCH_HOME`, else falls back to `system.file("", package = "torch")` -- it writes into its own
installed package directory and never calls `R_user_dir`. That is dictated by dynamic linking:
libtorch is shared libraries the loader must find next to the package's compiled code. Our payload
is a `qs2` file read at runtime, with no linking and no loader. Copying torch here would put 43 MB
somewhere `update.packages()` destroys, which is worse durability than the `~/Library/Caches` risk
that opened the question, and it breaks outright on a read-only system library.

**The migration question is dissolved rather than answered.** It only existed if the directory moved.
Nothing moves, no user's assets go invisible, and no detection-or-migrate code gets written.

**A platform-conditional default was considered and rejected.** It buys the macOS property at the
cost of a default path that differs by OS for reasons the user cannot see, plus a branch in code
that has none, to protect 43 MB that re-downloads on request.

**The runtime download path stays as it is**, and the properties it already has are the reason: an
unauthenticated CDN GET rather than a **GitHub API** call, whose anonymous limit of 60 requests/hour
**per IP** is shared across an institutional NAT or an HPC login node; a declared `release_tag` +
`file` pointer resolved by `mc_asset_url()` rather than a list-the-release-then-find-the-file
search, per the standing accessor rule; and `mc_fetch()`'s staged `.part` download,
`validate_checksum` and atomic rename. Any replacement has to keep all four.

---

## 2026-08-03 -- The first vignette, and why almost none of it runs

`vignettes/assets.Rmd` is the package's first vignette. It documents the assets directory, the
four-source resolution order, and the download / load / clear lifecycle.

**Every block that downloads, deletes, prompts, or prints a per-machine path is `eval = FALSE`,
with its output written out by hand.** `R CMD check` builds vignettes, and the standing invariant
is no network at install, build, check or CRAN test. A vignette about downloading is exactly the
document most likely to break that, so the policy is stated in `dev/WRITING.md` section 10 rather
than left to the next author to infer. Exactly one block evaluates, a `list_clocks()` call over
the shipped catalog, which is offline and deterministic.

This is the `@examplesIf interactive()` policy in the other syntax. The two must not drift: an
example and a vignette chunk that show the same call under different guards would be a contract
with itself.

**`vignettes/` and `README` join the R1 to R8 scope.** They were outside it only because neither
existed. Markdown invites a chattier register than a `@details` block, so R2 and R3 are the rules
that slip there, and section 10 says so explicitly.

`DESCRIPTION` gains `VignetteBuilder: knitr` and `knitr` / `rmarkdown` under Suggests. Both are
build-time only and neither reaches `Imports`.

---

## 2026-08-03 -- The finalizer set is derived, and the two batch counts are cross-checked

An independent audit found `score_associations()` calling `finalized()` while the `CLAUDE.md`
invariant named only three finalizers and its own manual said nothing. Three changes came out of
it, and the first is the one that matters.

**The finalizer set is now derived from a mechanical test, not enumerated.** A finalizer is any
exit that takes an `mc_result` and returns something that is not one. That is checkable against any
signature, so the set cannot drift. It drifted twice under the enumeration: `as.matrix()` was
outside it until earlier the same day, and `score_associations()` was re-finalizing silently. The
test also settles `rbind` without a special case -- it returns an `mc_result`, so it is not a
finalizer, which is the same conclusion the old recursion argument reached the long way round.

**The two batch counts are cross-checked rather than chosen between.** `provenance[[mc_batch_id]]`
and `names(per_clock)` are independent derivations of "how many batches", and four sites read the
`per_clock` one while the four exit frames read the provenance one. They agree today. `n_batches()`
(`R/mc_result.R`) now derives the count from provenance -- authoritative, because it is the vector
that fills the column -- and `stop()`s if `per_clock` disagrees. Every finalizer and both coverage
frames route through it. **A record whose counts disagree is malformed, so the right behaviour is
to stop, not to pick one.** Picking one is how a disagreement becomes wrong numbers instead of an
error.

**`finalized()` calls it before the `pending` test, deliberately.** The obvious form,
`if (length(pending) && n_batches(x) > 1L)`, short-circuits: a record with no `pending` -- the
common case -- never evaluates the guard, so `as.data.frame()` and `as.matrix()` accepted a
malformed record while both coverage frames rejected it. Measured, not reasoned about: the first
version of the test failed on exactly those two exits. The check is unconditional now.

**`set_mc_assets_dir()` keeps returning the previous override, `NULL` included. The bug was the
documentation.** The audit flagged `@returns A string.` against a function that returns
`getOption("mc.assets_dir")`, which is `NULL` in the default state. That was first "fixed" by
returning the resolved directory instead, and then reversed the same day, because the resolved
value is the wrong thing for a setter to hand back.

**A setter returns whatever restores the previous state exactly.** `setwd()`, `options()`, `par()`
and Python's `ContextVar.set()` all work this way, and the property they share is that "was unset"
survives the round trip as a distinguishable state. Resolving it away conflates *no override,
falling through to `MC_ASSETS_DIR`* with *pinned to that path*, so restoring the return value
silently shadows the environment variable. It also duplicates the getter: "which directory is in
effect" is exactly what `get_mc_assets_dir()` answers, and it is always a string.

So the split is the ordinary one. **The getter returns the effective value, always a path. The
setter returns the previous override, `NULL` when there was none.** A test now pins the case that
distinguishes them: with `MC_ASSETS_DIR` set and no option, set-then-restore must leave the
environment variable back in charge.

---

## 2026-08-03 -- The `@seealso` groups, and why one generic stopped being four topics

`dev/WRITING.md` section 6 banned `@seealso` outright until the groups could be decided once with
the whole surface in view. That pass is done, and the rule is now "the groups are closed" rather
than "never write one".

**The mechanism is a set, not a per-topic judgement.** A topic's `@seealso` is the **union of the
groups it belongs to, minus itself**. Symmetry is then true by construction, including where a
topic is in two groups, which is the case that would otherwise rot. Five groups, 17 tagged topics,
58 links. `list_mc_assets` is in both discovery and assets and carries the union at eight links --
the widest list in the manual, and intended: it genuinely answers both questions.

**`calc_clocks` points nowhere on purpose.** It is the entry point, every relevant topic already
reaches it through the inherited `x` param text ("The value returned by `[calc_clocks()]`"), and a
hub that links to everything is a table of contents in the wrong place. `sim_DNAm`, `predict_sex`
and the three `print` methods are likewise untagged by decision, not by oversight.

**Four `cite_clocks` topics became one, and that replaced a group rather than joining one.**
`cite_clocks`, `.character`, `.mc_result` and `.default` are all `(x, ...)`, so `@rdname` merges
them with no param collision, and `?cite_clocks` now shows all four usage lines. Co-location beats
cross-reference here: the methods of one generic are the same verb, and a reader wants them on one
page, not linked from four.

**It also closed the footgun `WRITING.md` section 5 calls the one live risk in the donor scheme.**
The donor's `x` is an `mc_result`, so `cite_clocks.character` had to be kept from inheriting it --
inheritance matches on name alone and yields confidently wrong text rather than an error. Merged,
`x` is written once, locally, covering both accepted forms. `lint_roxygen()` went from 6 rows to 0
as a side effect, because the merge retired `cite_clocks.default`'s untyped `Any object.` /
`Nothing.` pair and three duplicated `@returns`.

**The `mc_result` methods were deliberately not merged.** `rbind.mc_result` cannot join them: a
merged topic has one `@param ...` slot, and its `...` means "two or more mc_result objects" while
the others mean "not used" -- a direct collision with the three fixed `...` sentences in
`WRITING.md` section 4. `print.mc_sim` cannot merge into `sim_DNAm` either, because `n` is the
sample count in one and the rows to display in the other. Same name, one slot, two meanings.

**A closed set needs an instrument, so `lint_seealso()` joins `R/dev-utils.R`.** It catches the
two failures nothing else does: a link whose topic does not exist, which is an `R CMD check`
WARNING and therefore invisible until the check that is deferred to section 3 of the to-do finally
runs, and a one-way link, which no tool has ever caught because Rd has no notion of a reciprocal
link. Both were verified against injected faults, not just against a clean tree.

---

## 2026-08-03 -- A frame column keyed on a record fact, and `all_columns` as the escape hatch

`clocks_coverage()` returned 17 columns and `list_clocks()` returned 10. Both now return a narrow
default and take `all_columns = FALSE`. The two use **different mechanisms**, and that difference is
the decision.

**`clocks_coverage()` keys on a declared record fact.** Nine columns are always there --
`clock_id`, `group_id`, `policy`, and the six `score_*` counts. Four appear only where they say
something: `role` when the record holds a routing target, `normalizes` plus the five `norm_*`
counts when a clock normalizes, `missing_cpgs` when a CpG is absent, and `mc_batch_id` under its
own existing rule. Its own `@examples` block dropped from 17 columns to 9, and the nine it lost
were all-`FALSE`, all-zero, or empty.

**The norm block is not "usually" empty, it is structurally empty.** Three of 137 catalog clocks
normalize -- `DunedinPACE` on quantile, two on `bmiq`, which is opt-in and off by default. So six
columns and a flag were dead weight in nearly every run the package will ever serve.

**The precedent that decides the mechanism is `samples_coverage()`, which was already conditional
in the row direction.** A `panel = "norm"` row exists only when the clock normalizes. Keying the
`clocks_coverage()` columns on the same fact makes the two frames agree about when the norm axis
exists, instead of one frame being conditional and its neighbour always-on. `samples_coverage()`
itself is untouched and gets no `all_columns`: it has nothing to drop, and a no-op argument for
symmetry is worse than the asymmetry. Its `panel` column stays even when constant, because
dropping it would change the row key from (sample, clock, panel) to (sample, clock).

**`normalizes` travels with the block it describes rather than staying always-on.** `CLAUDE.md`
calls it the one declared panel fact and forbids re-deriving it from `norm_needed`. That still
holds: the column is present whenever the answer is non-trivial, and where it is absent the fact
is simply that nothing normalized. No reader is pushed toward the derivation the rule bans.

**`list_clocks()` cannot use the same mechanism, so it gets a fixed set.** Its content depends on
the user's filter, not on a declared fact, and a generic "drop the constant columns" rule would
delete `group_id` from `list_clocks(pattern = "^Horvath")`. The default is `clock_id`, `group_id`,
`request_as`, `covariates`, `external`, `tags`. `callable` goes because it is **exactly**
`request_as == clock_id` -- measured, both split the same 14 of 137 rows, and there is now a test
asserting the identity rather than a comment claiming it. `group_size` goes because the frame
already carries what it counts, `batch_dependent` and `normalize` because they are set on 2 and 3
of 137 rows.

**The flag does not touch `mc_batch_id`, deliberately.** Folding it in would give one uniform story,
but `as.data.frame()` and `calc_accel()` have no such flag, so `all_columns = TRUE` on a
single-batch record would make the coverage frames carry a join key the other two exits do not.
That reopens the four-exits-together rule of 2026-08-03 to solve a cosmetic problem. The batch
label keeps its own gate.

**The cost is accepted, not overlooked.** A conditional column means `cov[["norm_needed"]]` returns
`NULL` rather than erroring, which is the silent-`NULL` hazard this package bans `$` over. This is
the second and third such axis after `mc_batch_id`. `all_columns = TRUE` exists precisely so code
that names a column directly has a fixed schema to name it in, and both `@details` sections say so.

---

## 2026-08-03 -- An empty `groups` selects nothing, and `"all"` is the only way to say all

`mc_resolve_groups(NULL)` and `mc_resolve_groups(character(0))` used to return **every** external
group. They now return `character(0)`, and `load_mc_assets()` routes through the same function
instead of normalizing `groups` itself.

**The two readings were already in conflict, in one file.** `pack_groups_needed()` returns
`character(0)` on any run that requests no external clock, which is the ordinary case, so
`load_mc_assets(character(0))` had to mean "load nothing" and did. `mc_resolve_groups(character(0))`
meant "every group". The same value meant opposite things eight functions apart, and the obvious
future cleanup -- route `load_mc_assets()` through `mc_resolve_groups()` -- would have made every
`calc_clocks("Hannum")` call try to download all four asset groups. That cleanup is now done, and
it is safe because the semantics were unified first.

**The failure modes are asymmetric, which decides the direction.** These verbs download hundreds of
megabytes and delete files. `clear_mc_assets(x)` where `x` came out of a filter that matched nothing
deleted the entire assets directory under the old rule. Empty-means-nothing fails as a no-op that
the caller notices immediately and harmlessly; empty-means-everything fails expensively and
silently. Nothing is lost, because the default is already `"all"` -- a caller who wants every group
omits the argument or spells it.

`NULL` is folded into the same rule rather than kept as "unspecified". With a default of `"all"`,
`NULL` never arrives from omission, so it is always either an explicit choice or a computed value
that came out empty, and the computed case is the one worth protecting.

**The validation is `checkmate::assert_subset()`, not `match.arg(several.ok = TRUE)`.** This was
tried both ways. Measured, `match.arg(several.ok = TRUE)` on these choices:

- `character(0)` errors, which is the one property it has that we wanted;
- `NULL` returns `choices[1L]` silently, which here is `"all"` -- exactly the mass-download
  behavior this entry removes, reintroduced through a back door;
- `c("SystemsAge", "Nope")` returns `"SystemsAge"`. It only errors when **every** element fails,
  so a typo beside a valid group is dropped without a word;
- it does not deduplicate.

So it gives one of the four properties and silently breaks two. `assert_subset()` gives exact
matching, an error naming both the bad element and the valid set, and `empty.ok` as an explicit
flag, and it is what `list_clocks(tag =)` already uses for the same shape of argument.

Partial matching is dropped with it, deliberately. The group set grows with each sync, so an
abbreviation that resolves today can become ambiguous later and break calling code that worked.
That is the same reasoning behind the blanket `$` ban in `CLAUDE.md`: a convenience that resolves
silently to something the caller did not name.

## 2026-08-03 -- `as.matrix()` is a finalizer, and a finalizer is defined by the exit

`as.matrix.mc_result()` was `x[["scores"]]` and nothing else. It now calls `finalized()` like
`as.data.frame()` and `calc_accel()` do.

Found while documenting the method, not while testing it: writing the `@details` paragraph meant
claiming what the function does with `pending`, and the claim was not true of this one.

**The rule was drawn at the wrong place.** The old set was "the two exits that return a frame",
which is a fact about the return type and has nothing to do with why re-finalizing is necessary.
The reason is that the caller is leaving the `mc_result` structure: `pending` lives in
`$provenance`, a bare matrix has nowhere to carry it, and the value cannot be recovered from. That
is equally true of `as.matrix()`. So the definition is now **any exit that leaves the S3
structure**, and the frame-vs-matrix distinction is not part of it.

The bug this closes is small but real: on a multi-batch record holding a non-empty `pending`,
`as.matrix(res)` and `as.data.frame(res)` returned **different numbers** for the same clock, and
neither said anything. Both now reduce over every sample and both announce it under
`say_pending()`'s unchanged guard.

`rbind` is still excluded, for its own unchanged reason: it recurses under `do.call()`, and it
hands back an `mc_result` rather than leaving the structure at all.

## 2026-08-03 -- The public message surface: audience, not transport, and one English

Four agents audited all 70 user-visible message sites against a proposed rule set. 11 were clean.
The rules and the per-site evidence were in `dev/cli-audit.md` and `dev/cli-audit/` (local only).
`dev/cli-audit.md` was retired on 2026-08-03, once the rules it argued for became `CLAUDE.md`
invariants and `dev/WRITING.md`. Only the four per-site part files remain.
`CLAUDE.md` now carries R1 to R7; this entry records the reversals and the things that will be
second-guessed.

**The cli keep-set was an enumeration and is now a rule.** cli was "front-door only", named file by
file. That put `resolve_normalize()`'s four aborts on the `stop()` side, even though every one of
them is about a `calc_clocks()` argument the caller typed. Those four could not carry markup, so
they could not satisfy R6, so a whole class of user-facing messages was structurally exempt from
the rules. That is a two-tier system, not a rule. The line is now **user-choosable input against
package defect**, which leaves the old keep set almost unchanged in practice and fixes the one
place where the transport was deciding the register.

Worth recording because it looks like a loss: the plain `stop()` text was **better** than its cli
neighbours on R2, with no first person and no "please". The voice problem was never caused by cli.
The bullet grammar invites it.

**`--` and `;` are banned in public-facing text, and that is not a reversal of the ASCII section.**
The ban is scoped to what a user reads -- cli message text now, roxygen prose later. Comments,
dev-facing `stop()` text and `dev/` docs keep `--`, which the ASCII section still requires. The
reason is accessibility: the maintainer has dyslexia that makes `--` and em-dashes require a guess
at the intended meaning, where a single `-` does not. Evidence that the ban costs nothing: all 14
banned characters across the audit were sentence boundaries in disguise, and not one rewrite needed
the ` - ` allowance that was left open for them.

**"Scoring continues" is deleted, not reworded.** Several warnings spent a whole bullet saying the
run had not stopped, which is what a warning already means. The premise behind keeping it was also
wrong: we cannot promise a transposed `DNAm` will fail at the coverage gate, and scoring can fail
for reasons that have nothing to do with the diagnosis. So the messages describe the problem and
name an instrument instead. One casualty is honest: `coverage_gates.R`'s marginal warning carried a
real fact, that more of the panel gets filled by imputation, and restating it accurately needs a
per-clock policy lookup (`vendor_mean` fills, every other policy drops). It was dropped rather than
stated approximately.

**No "... and N more" tail.** The cap was already 10 in four hand-rolled spellings with two
different tails. Less is more: the true total is already in the lead line, so the tail was
restating a number the reader has. The one exception is the interactive delete-consent manifest,
which counts the remainder on its own line -- there the list is what is being consented to. This
narrows `CLAUDE.md`'s older promise that the delete prompt "lists every file", knowingly: the
counts above the list stay exact, and an unbounded render is the failure the cap exists to prevent.

**`sprintf` never feeds cli, and interpolating is not enough on its own.** cli parses message
elements and bullets as templates, so a built string carrying a `{` is read as syntax --
`mc_manifest_bullets()` genuinely aborted with `Could not evaluate cli {} expression` on a brace in
a file name. Building with `format_inline()` fixes the *inputs* but not the output, which still
goes back through cli as a template, so `bullets()` escapes braces at the one door every bullet
passes through. The tempting shortcut, `cli_vec(vec-trunc)`, was rejected: it truncates the display
while still handing cli the whole vector, so it looks like the fix and does not meet the
requirement.

**`capped_bullets()` caps before it formats.** The old order formatted every element then capped,
which is why capping and markup were mutually exclusive: a finished `sprintf` line cannot carry
markup, and marking up an unbounded vector is what the cap forbids. Reversing the order dissolves
the conflict and is also strictly less work.

**`gate_label()` marks up the token, not the whole label.** It renders `"DNAmFitAge" (female
model)`, so the quotes sit on the part the caller can type back. The audit proposed embedding
`sprintf("{.val %s}", id)`, which is exactly the `sprintf`-into-cli mixing banned above; it uses
`format_inline()` instead. Two assertions in `test-coverage-gate.R` tested the exact string shape,
which the altitude rule discourages, and now assert what the label must and must not name.

**Two class names got `{.cls}` and nothing else changed at those sites.** Worth noting because it
is the one rule that reaches sites the other six leave alone: R6 caught `class(x)[[1L]]` rendering
bare in prose at two sites that were otherwise clean.

## 2026-08-03 -- The Age units gate is per row, not distributional, and it lives in `check_pheno()`

`check_pheno()` bounded `Age` only by `assert_numeric(finite = TRUE)`, which accepts an age in
months, weeks or days without comment. It now also warns per row, on both sides:
`AGE_MAX_YEARS <- 122` (the verified human maximum) and `AGE_MIN_YEARS <- -2`.

**Per row, not a cohort statistic.** The queued item floated keying on the distribution -- a median
far past any plausible age -- as the way to separate "wrong units" from "one unusual subject". That
is the weaker test and was rejected. A cohort statistic can only fire once **most** of the cohort is
wrong, so it is blind to the row-wise failure: a degenerate upstream `ifelse`, or a merge of two
files that coded age differently. That case leaves every other row looking fine, which is exactly
when a human will not catch it by eye. The per-row test also catches everything the distributional
test would have -- if the median is past 122 then rows are too -- so it strictly dominates. It is a
`warn`, so the usual objection to a sensitive test (it stops good runs) does not apply.

**Both bounds are at the edge of possibility, not the edge of typical**, because a units error is an
order-of-magnitude error: a 50-year-old is 600 in months and 18000 in days. So `122` never doubts a
real centenarian, and `-2` leaves the legitimate pre-birth convention (`-0.5`, `-1`) alone while
still catching gestational age in weeks (`-40` to `0`). The two sides warn **independently**,
mirroring `check_col_values()`'s `min_val` / `max_val` -- one pheno can carry both.

**It lives in `check_pheno()`, and the alternative would have covered half the surface.** The
obvious placement is after `resolve_pheno()`, which is where the canonical id vector and the
narrowed covariates first exist together. But `calc_accel()` **never calls `resolve_pheno()`** -- it
merges `data =` over the record's `$pheno` in `merge_accel_data()` and does its own id-join. It
does call `check_pheno()`, with `extra_columns = vars` (which includes `"Age"` whenever
`type = "diff"` or the formula names it) and `sample_id` in hand. So `check_pheno()` is already the
one place both entry points meet, and `warn_missing_covariates()` already establishes the pattern
there: narrow to the join-surviving rows, then warn per column. Both warners now share
`joined_rows()` rather than each re-deriving the join -- one fewer hand-rolled left join, not one
more (cf. the `collapse` question).

**Gating on `extra_columns` means the check fires exactly when the age is consumed.** If no
requested clock requires `Age`, `resolve_pheno()` drops it from `$pheno` and nothing warns -- the
package does not audit columns it does not read. If that same record later reaches
`calc_accel(type = "diff")`, the age must arrive via `data =`, `vars` contains `"Age"`, and the
gate fires there instead. There is no path where an age is used unchecked.

**The flagged ids are returned, not stored.** `warn_age_units()` hands back the offending ids on the
`sample_id` axis, so it is testable and could be threaded into `$provenance` later. It deliberately
is not: the flag is a pure function of `$pheno$Age`, which the record already carries, so storing it
duplicates derivable state -- the same reasoning that refused a `below_min` column on the coverage
frames. What would change the answer is a case where the age is **not** recoverable from the record,
and the one candidate (`calc_accel(data =)`) has nowhere to store it anyway: `calc_accel()` returns
a frame, not a record.

Suite: 0 failed / 0 error / 0 warning / 264 skipped / 1242 passed (+8, five new tests).
`R CMD check` not run. Parity not run.

---

## 2026-08-03 -- Assertions live at the boundary, and `.var.name` is filled only where the deparse lies

One pass over `R/`: 32 `checkmate` calls across 12 files -> 30 across 9. `coverage_gates.R`,
`missingness.R` and `score_cohort.R` now use `checkmate` not at all, which is the point -- all
three were asserting values that had already crossed the front door.

**What forced the pass was a measured message, not a principle.**
`calc_clocks(min_clocks_coverage = "a")` reported

```
Assertion on 'threshold' failed: Must be of type 'number', not 'character'.
```

because that floor was asserted **nowhere** at the front door -- `calc_clocks()` asserted only
`min_samples_coverage`, and the floor's sole validation was `assert_number(threshold, ...)` three
frames down in `check_coverage()`, reached through `mc_cohort()`. So the assertion named a variable
the caller never typed, while the cli messages in that same function correctly said
`{.arg min_clocks_coverage}`.

**The tempting fix is the wrong one.** Setting `.var.name = "min_clocks_coverage"` inside
`check_coverage()` makes the message right for today's one caller and a lie for any other, and it
buries a missing boundary check under a cosmetic patch. The floor is now asserted in
`calc_clocks()` beside its sibling, and `check_coverage()` asserts nothing -- at which point the
deparse is correct for free. **That is the general shape: a wrong variable name in a `checkmate`
message is usually evidence the check is in the wrong frame.** Look there first.

**So `.var.name` is filled only where relocation cannot help.** `checkmate` derives the name by
deparsing the expression, so at a boundary the default is already the caller's own word and a
hand-written string is pure staleness risk -- it survives the next rename; the deparse does not
need to. The rule: fill it **iff the deparsed expression does not name something the caller can
locate in their own call.** This is deliberately *not* "iff it is not a bare symbol" --
`assert_character(colnames(DNAm))` deparses to `colnames(DNAm)`, which any caller can find, and
filling it would be noise. The one site in this pass that qualified was `check_pheno()`'s
`assert_character(pheno[[ID]], ...)`, where `ID` is an internal parameter name; it now carries
`.var.name = paste0("pheno$", ID)`, which names the *actual column* and so beats both the internal
name and a generic `"pheno_id"`. Precedents already in the tree: `predict_sex.R`'s
`"pheno$Female"` and `missingness.R`'s `sprintf("moment_sets[[%s]]", who)`.

**`check_moment_sets()` went the other way -- checkmate to bare `stop()`.** Its input is
catalog-derived (`resolve_moment_domains()`), so a failure is a package bug and a `checkmate`
message aimed at a user is the wrong register. It is *not* deleted, because it is the guard between
a bad index and an out-of-bounds kernel read; the bounds, NA, integer and arity checks are all
still there, just as `stop()` with greppable text. Its existing tests assert *that* it errors and
nothing about wording, so they carried over untouched -- which is the altitude rule paying for
itself.

**`check_pheno()`'s missing-id-column refusal became cli.** `assert_choice(ID, names(pheno))`
printed `Assertion on 'ID' failed: Must be element of set {'zz'}, but is 'ID'` -- where `'ID'` is
simultaneously the fake variable name and the value. Pheno structure at the `calc_clocks` front
door is already on the cli keep-list, so this was never a `.var.name` question.

**`check_mc_result()` is a front-door refusal.** This was the open question section 4.1 flagged: it
is not an S3 method, so the keep-list did not name it. All six call sites (`rbind.mc_result`,
`refinalize_clocks`, `as.data.frame.mc_result`, `calc_accel`, `clocks_coverage`,
`samples_coverage`, `score_associations`) are exported verbs receiving a user-supplied first
argument, which is the keep-list's own pattern. It is now `cli_abort` and reports the class it got.

**The suite did not move: 0 failed / 0 error / 0 warning / 264 skipped / 1234 passed, identical to
the pre-pass baseline.** That is the check on the pass, not a coincidence -- tests assert *that* an
error fires rather than its wording, so relocating and rewording checks is invisible to them. A
failure here would have meant a test was too tight, not that the pass was wrong.

`R CMD check` not run (maintainer-only). Parity not run.

---

## 2026-08-03 -- `predict_sex()` compares against the recorded sex; the join is by id

`predict_sex()` already took `DNAm` and `pheno` on one call over one matrix and passed `pheno`
through purely for the id column. It now also reads `Female` off it and returns two companion
columns beside the declared `predicted_sex`: `recorded_sex` and `sex_mismatch`.

**The recorded sex is read from the caller's `pheno`, not from the record, and that is forced.**
`resolve_pheno()` narrows `$pheno` to the id column plus the covariates the run *required*, and the
two `DNAmSex_Wang` members declare none -- so `Female` never reaches `$pheno` on a `predict_sex()`
run. There is no version of this that reads the record.

**So it is a left join, and the join key is the id column.** Not row order, and not row names --
`match(out[[pheno_id]], pheno[[pheno_id]])`, with `pheno_id` read back from
`$provenance$pheno_id` rather than re-derived, because `...` may have carried a non-default one
into `calc_clocks()`. The match is total and one-to-one for a reason worth writing down rather than
re-checking: `calc_clocks()` has already run, and `check_pheno()` refuses a duplicated or NA id
column while `resolve_pheno()` refuses a pheno that does not cover every `DNAm` row. An `NA` from
the match is therefore a package bug and is raised as one, not handled.

**`Female` is validated here because nothing else does.** It is not a required covariate for these
clocks, so `check_pheno()`'s `assert_integerish(lower = 0, upper = 1)` never fires on it. The same
assertion runs in `recorded_from_female()`, so a factor or an `"M"`/`"F"` column is refused with
the message it would have got from `calc_clocks()`, rather than being guessed at.

**Only an unambiguous binary disagreement is flagged.** The rule table emits `47,XXY` and `45,XO`,
so a flat mismatch would fire on biology; those are shown against the record and never flagged, as
are an unscored sample (NA call) and an unrecorded one (NA `Female`). `BINARY_CALLS` is checked
against the declared `karyotype_calls(kc)` on every run, so an upstream rename fails loudly instead
of silently never flagging. The flag is an invitation to investigate -- either side can be the
wrong one -- and `say_mismatch()` says so in as many words.

**Not done, and not to be re-proposed: auto-resolving sex inside `calc_clocks()`** when a requested
clock needs `Female`. (a) Sex-chromosome probes are routinely filtered out -- `cohort_450K` has
none, which is why both `DNAmSex_Wang_*@cohort_450K` sit in `KNOWN_PARITY_GAPS` -- so an implicit
check would be unavailable on an unpredictable fraction of matrices, and an explicit surface can
refuse where an implicit one can only shrug. (b) It would put the sex panel under the coverage gate
on runs that do not need it, turning a working `DNAmFitAge` call into a hard `ratio == 0` stop on
any sex-filtered matrix -- avoidable only by exempting one clock from the gate, a special case in a
system whose pitch is that routing is total. (c) It is quality-of-life, not a correctness guard.
The residual gap -- the user who never calls `predict_sex` -- belongs in the docs for the
sex-requiring clocks, not in a runtime hint that would fire on every GrimAge and FitAge run.

---

## 2026-08-03 -- `col_stats()` carries the observed range, not two booleans

`any_lt0` / `any_gt1` are gone. The kernel now carries `min_val` / `max_val`, **seeded at 0.0 and
1.0** so only an out-of-range value ever moves them, plus `min_col` / `max_col` -- the 1-based
position within `cols`, the same convention `overflow_col` already uses, so R can name the probe.
The old flags are derived (`min_val < 0`, `max_val > 1`) and nothing is lost.

Cost is unchanged: the same two comparisons on the same branch, two assignments on the rare side,
no extra pass and no new pass structure. The `else if` stays correct because `min_val <= 0 <= 1 <=
max_val` holds by construction, so the two branches remain exclusive. The kernel is serial -- no
OpenMP anywhere in `src/` -- so the reference-accumulation pattern the booleans used carries over
with no reduction; the four fields are one struct only to keep the signatures readable.

**Only the panel columns are scanned, and that is enough.** Scale is a whole-matrix property, so
the panel is a valid sample of it. Pass 2 (`sweep_moments_remaining`) still tracks nothing, exactly
as before.

The point of the change is the message. The `< 0` warning already named M-values and gave the
conversion; the `> 1` one only said "double-check the scale". Both now report the observed extreme
(at `signif(, 4)` -- a diagnostic, not a value to compute with) and the column it came from, and
above **50** the `> 1` warning names percent methylation and gives `DNAm / 100`. 50 is not a
guess at a boundary: a units error is an order-of-magnitude error, so anything between 1 and 50 is
not a scale story and gets the honest "check the scale" instead.

---

## 2026-08-03 -- The coverage floors go into `$provenance`, batch-wise

`min_clocks_coverage` and `min_samples_coverage` were arguments that reached no result field, so a
saved record could not say what floor it was scored under and the `check_row_coverage()` warning
was unreproducible from the record. Both now sit in `$provenance`, **keyed by batch label** like
`$coverage$per_clock`.

**Batch-wise, not record-wise, and `rbind` reconciles nothing** -- the same line every other bind
gate follows: record what batching forced, refuse what the caller chose differently. A differing
floor across batches is not an error and does not throw. It cannot be: the raw per-sample
`coverage` column survives the bind, so which samples in which batch sat low stays answerable
whatever the floors were.

**The exits finalize it, the way the finalizers resolve `pending`.** `samples_coverage()` takes the
**most restrictive** floor across the bound batches (`max`) and re-warns under it. That is what
makes a post-`rbind` `sc[["coverage"]] < threshold` filter well defined at all -- without it there
is no single number to compare against.

**No `below_min` logical column.** The cell axis already exists -- one row per (sample, clock,
panel) carrying `coverage` -- and a conditional second column would mean different things on
different rows after a bind, which is precisely the failure the batch-keyed storage avoids.

Asymmetry between the two is deliberate and follows from what each gate does. `min_clocks_coverage`
aborts, so a record's existence already proves it passed and nothing reads it back; it is stored
for the record's own account of itself. `min_samples_coverage` only warns, so the raw per-sample
numbers are what matter -- and those were already carried.

Resolved while scoping, recorded so it is not re-derived: NA in `$scores` has exactly four sources
-- NA covariates, unknown sex on a routed alias (both recoverable from the retained `$pheno`), BMIQ
unfit samples and Wang domain failures (both in `$provenance$scoring_failures`). None come from the
beta matrix. Unverified corner: MiAge L-BFGS-B non-convergence.

---

## 2026-08-03 -- The test-suite trim is the last step before public alpha, not the next one

The queued audit of the suite (assert output not wiring, let parity own the goldens it already
owns, delete what a no-behavior refactor would break) is **deferred until immediately before
public alpha**, and it is the last piece of work before it. It was previously slotted first, on
the reasoning that a faster suite makes every later iteration faster.

**Why it moves to last.** The suite is the thing that has to be stable when `R CMD check` starts
running, and check does not run yet -- it is maintainer-on-demand precisely because the suite is
bloated. So the trim and the first real check run are one piece of work, and doing the trim now
buys a faster suite for a period in which the code it tests is still moving. Two things in
particular are still unsettled and both rewrite test surface: **roxygen prose does not exist**
(the exported surface still carries a placeholder block, and turning prose on is its own pending
decision), and the validation/message pass will relocate and reword checks across `R/`. Trimming
against a surface that is about to move means auditing the same files twice.

**What this is not.** Not a reversal of the altitude rules -- they stand and bind on every test
written meanwhile, which is what keeps the eventual trim from growing. Not permission to add
tests loosely on the theory that a cleanup is coming. And not a change to the standing
prohibition on running `R CMD check`: it stays maintainer-on-demand until the trim lands, which
is the point at which running it is expected to become routine.

**Ordering consequence.** The message/validation pass (validate at the boundary, then tighten the
bounds, then tone) is a deliberate forcing function for the trim: those passes reword and
relocate messages, and by the altitude rule tests assert *that* an error fires rather than its
wording, so anything that breaks under them was too tight and is already on the trim's list.
Doing them first means arriving at the trim with the list half-written.

---

## 2026-08-03 -- `check_DNAm()` diagnoses shape and replicate probes; it never dedups

Three changes to `check_DNAm()`, and one standing refusal.

**Orientation moved ahead of the matrix refusal, and now runs on a data.frame too.** `dim()`,
`colnames()` and `rownames()` all work on a data.frame, so the orientation and replicate checks are
computed before `is.data.frame()` throws. A data.frame caller therefore gets the actual problem --
and the throw itself adapts, offering `t(as.matrix(DNAm))` rather than `as.matrix(DNAm)` when the
probe ids are in the rows. Previously they got only "must be a matrix" and had to discover the
orientation trap on the next call.

**`nrow > ncol` is evidence, not a verdict.** The obvious cheap orientation test false-positives on
a real run: 1000 samples x 353 CpGs, one clock over a large cohort, is correctly oriented and
taller than it is wide. So probe ids in the rows is the decisive signal, and the dimension ratio
only warns when the columns *also* fail to look like probe ids. Pinned by a test.

**EPICv2/MSA replicate suffixes are now named.** Both arrays suffix every probe with its address
(`cg00002033_TC11`) and ship several rows per CpG -- 8523 duplicated stems on MSA (up to 8 copies),
5225 on EPICv2 (up to 10). Panels are declared on the unsuffixed id, so every such column matches
nothing and is silently vendor-filled or dropped as absent. `clocks_coverage()` already surfaced
this as elevated `score_absent`; what was missing was the diagnosis.

`PROBE_REPLICATE_SUFFIX` is `_[BT][CO][0-9]+$`. Measured against the manifests rather than guessed:
it matches **all** 937055 EPICv2 and **all** 281806 MSA ids, and **zero** EPICv1 (865918) or 450K
(485577) ids, which carry no underscore at all. `[0-9]+` and not `{2}` because EPICv2 has exactly
one five-character suffix, `cg06373096_TC110`. The package's own panels are unaffected: 3 of 452499
panel ids contain an underscore (`ch.13.39564907R_II_R_O_37491` and two siblings, from the
Retroelement clocks) and none match.

**The scans are a bounded stride sample, which replaces the old `ncol < 2e5` guard.** That guard
was sound for orientation -- 2e5 columns cannot be samples -- but it points the wrong way for this
check, because EPICv2 is 937k columns wide, so any width threshold disables the replicate warning
on exactly the array that needs it. Lowering the threshold makes it strictly worse. Sampling 2000
ids is decisive rather than probabilistic here, because the suffix is a whole-array property: every
EPICv2/MSA id carries one, no EPICv1/450K id does. Cost is then constant in the matrix width. (For
the record the full scan was affordable anyway -- 0.17s of `grepl` at 937k -- so this is about
keeping a per-call check free, not about rescuing an expensive one.)

**Standing refusal: `calc_clocks()` will not collapse replicate probes.** Do not re-propose it. (a)
It needs an external array manifest, which brings manifest versioning fragility and a tail of edge
cases (chr0 probes among them) into a package that otherwise ships a closed, self-contained
contract and reaches no network. (b) Doing it means allocating a second full copy of a very large
matrix inside the scoring call -- the same objection that sank `coerce_dnam()`'s
`as.matrix(data.frame)` in PR #3 sec 3.4. The collapse is the user's, done outside `calc_clocks()`,
where they can choose the manifest version and the aggregation rule. The package's job here is to
tell them it is needed, which is what the warning now does.

---

## 2026-08-03 -- One beta entry point, and no pre-flight surface

Written down because it was already true and nobody had said it: **`calc_clocks()` is the only
public surface that reads a beta matrix.** Verified over the exported surface -- only
`calc_clocks` and `predict_sex` take a `DNAm` argument, `predict_sex` reads it exclusively through
`calc_clocks`, `sim_DNAm` generates rather than reads, and every remaining export takes either
catalog arguments or an `mc_result`.

**Why state it now.** It settles a class of proposals in one line instead of re-arguing each one.
PR #3's `build_coverage_table()` (per-clock coverage on a bare matrix), the `report(DNAm)` arm, and
any future "dry run" or preflight helper are all the same shape: a **second beta reader**. The
objection is not duplication, it is decoupling -- a second reader is handed its own matrix, so its
verdict can be about a different object than the one that eventually gets scored, and nothing in
the package can detect the substitution. `predict_sex()` already shows the shape that is fine:
it is a `calc_clocks()` call whose output feeds a later call, which is composition, not a
pre-check.

**Nothing is bought by the second reader.** Scoring is a matmul over a matrix that is already
resident; the costly parts (materializing the betas, loading packs) are paid by any caller either
way. And both coverage gates are arguments, so `calc_clocks(min_clocks_coverage = 0,
min_samples_coverage = 0)` is already the full-report dry run, with the real numbers rather than a
prediction of them.

**Why the pre-flight model feels obligatory anyway, and why it does not transfer.** It is inherited
from upstream, where it is correct: an ENmix or minfi pipeline threads one object through its
steps, caches an expensive IDAT parse at the front, and has genuine cross-sample and cross-probe
stages where dropping a sample changes what follows. Within a coupled pipeline there is no
decoupling hazard -- the object *is* the state. Neither condition holds here. Users will still
arrive with the habit; the answer is that the model is right where they learned it and does not
apply to a calculator.

**The premise, kept visible.** This rests on scoring being cheap enough that running it is not a
commitment. A chunked or streaming path over an on-disk store weakens exactly that, which is the
one change that would put a preflight surface back on the table -- and it would need an explicit
decision at that point, not an inherited one. See `dev/to-do.md` sec 7, where the chunked front end
is still an open question.

**Not in scope:** internals under `calc_clocks()` obviously touch the matrix (`check_DNAm()`,
`col_stats()`, the scan and fill machinery). The rule is about the public surface and where a
matrix enters the package, not about who may hold a pointer to it.

---

## 2026-08-03 -- Working trees get native line endings; only the index is pinned to LF

`.gitattributes` said `* text=auto eol=lf` -- LF in the repo **and in every working tree, on every
platform**. The second half is now dropped: `* text=auto`, so the index is still always LF and the
working tree follows `core.eol` (CRLF on Windows).

**Why.** `Rcpp::compileAttributes()` -- which `devtools::document()` and `load_all()` both call --
generates `R/RcppExports.R` and `src/RcppExports.cpp` inside its compiled
`.Call("compileAttributes", ...)`, writing through a text-mode `std::ofstream`. That is CRLF on
Windows and there is no R-level knob for it. Under `eol=lf` those two files came back ` M` after
every document run, forever, on every Windows machine. `git diff` showed nothing (it normalizes
before comparing) while `git status` showed the modification, which is the confusing part: git's
index refresh short-circuits on a size mismatch and never reaches the content comparison, so the
CRLF file reads as changed even though its filtered hash matches the blob exactly.

**Why not just live with it.** It is cosmetic -- `git add` normalizes, so no CRLF can reach the
index -- but it trained every Windows collaborator to ignore a dirty `git status`, which is the one
signal that has to stay trustworthy. Cost of the fix is one attributes line; cost of the noise is
paid on every commit.

**What stays pinned to LF**, because these are read on a platform other than the one that checked
them out: `src/Makevars` and `src/Makevars.win` (they ship inside the source tarball, and a stray CR
lands in a GNU make variable value), `.Rbuildignore` (`readLines()` does not strip a CR off it
outside Windows, so the ignore patterns silently stop matching), plus `*.sh` and `*.py` on the same
reasoning. Everything else is native.

**Do not "fix" a Windows worktree by re-normalizing the whole tree.** Existing LF files stay clean
because their recorded stat still matches; only a file some tool *rewrites* can churn, which today
is exactly the two generated ones. The one-time repair is `rm` + `git checkout --` on those two --
a plain `git checkout` alone is a no-op, since git skips writing an entry it already considers
up to date.

---

## 2026-08-02 -- `score_associations()` ships as a disposable advisory, and it is the one sanctioned `cor()`

**This is a deliberate, scoped carve-out of "Correlation is never a numeric gate."** The invariant
stands, and its subject is unchanged: an **agreement gate** -- a test that asks "do we match the
oracle" -- may never be a correlation, because `cor()` is offset- and scale-invariant and cannot
tell "correct" from "uniformly wrong". Nothing about parity, unit tests or any numeric bound moves.

`score_associations()` is a different use. The correlation is not an agreement statistic against a
reference implementation; it **is the estimand** -- the cohort's score-age association, which is the
quantity the reference table reports. It gates nothing: it returns a frame, stops no scoring, filters
no clock, and emits no verdict. Read the invariant as binding on gates, not on reported statistics.

**The reference intervals are wide, and that is measured, not suspected.** 31 of the 69 `age_r`
prediction intervals include zero, median width 0.71 on a 2.0 scale, so for ~45% of clocks "no age
association" falls inside the expected range. This was quantified before the function was written.
Shipping a v1 on that basis is a deliberate call: the flags are a starting point for a user who wants
one, not a measurement anyone should rely on.

**The function reports and says nothing else.** It emits no message and returns only the frame. A
caveat on every call is noise in programmatic use, and the appropriate place for a limitation of this
kind is documentation. The cost is accepted: a caller who reads neither this entry nor
`dev/PR3-respond.md` gets two booleans without context. There is still no PASS/WARN/FAIL and there
must not be one -- that was the specific thing declined in PR #3 (see `dev/PR3-respond.md` sec 3.6).

**The reference table is taken as given, and we differ from the author on its construction.**
`inst/extdata/clock_reference.csv` and `data-raw/build_clock_reference.R` are shipped unmodified,
authored by `dsborrus`, whose meta-analytic work is the only artifact in PR #3 that could not be
sourced elsewhere -- the prediction intervals use the Higgins-Thompson-Spiegelhalter form, pooling
is DerSimonian-Laird, correlations are pooled on the Fisher-z scale, and `MIN_N = 20` is a
reasonable floor. The disagreement is about what the two-stage design can support downstream, not
about the execution. Stage one fits a separate `lm` per (dataset, clock) pair; stage two pools those
estimates. A pool of that shape summarizes datasets rather than samples, so the individual level is
not recoverable from it, and the only comparison available at runtime is a user-cohort statistic
against a reference-cohort statistic -- which inherits the user's study design, and is why the
intervals have to be as wide as they are to stay honest.

Our position is that this wants a one-stage hierarchical model instead (`score ~ age + sex + tissue +
(1 | dataset)` fit on pooled individual-level rows), shipping fixed effects + covariance + tau^2 +
residual sigma so a `predict` step gives a closed-form per-sample interval and covariates can be
marginalized when absent. That version has a known null -- 5% of samples outside a 95% interval --
so no threshold has to be chosen anywhere. It needs the per-sample tables behind
`HigginsChenLab/TranslAGE-workflows` and is a separate project, which is why the v1 here ships on
the aggregate table rather than waiting.

**Disposability is the design constraint, so it is written down as a contract.** The whole feature is
`R/score_associations.R`, `inst/extdata/clock_reference.csv`, `data-raw/build_clock_reference.R`, and
one `export(score_associations)`. Delete those four things and nothing else in the package changes.
It reaches the record through exactly one internal, `finalized()` -- the same re-finalize hook
`as.data.frame()` and `calc_accel()` use, so a multi-batch record with pending cross-sample columns
is not correlated stale -- plus the documented `$scores` / `$pheno` fields. It adds no dependency,
no S3 method, no catalog field, and no coupling to routing, coverage or the pack machinery. Keep it
that way: when the hierarchical version lands, this should be removable in one commit.

## 2026-08-02 -- Wang scores as a matmul plus two scalars, and the scalars stay runtime

**`score_DNAmSex_Wang()` no longer materializes the z-scored or centred matrix.**
`sum_j ((x_ij - m_i)/s_i - c_j) * r_j` is algebraically `(x_i . r - m_i * sum(r)) / s_i -
sum(c * r)`, so the projection is one `n x p` matmul against a vector plus two reductions over
`p`. The two `n x p` temporaries -- the z-score and the `rep(center, each = n)` broadcast -- and
the `rep()` itself all vanish. Same rearrangement `score_Zhang2019()` already used, so this is the
established form here, not a new trick.

**Measured** (ChrX, p = 4047, real tensors): n=500 30x, n=2000 33x (0.99s -> 0.03s over 10 reps),
and 247 MB of transient allocation per call gone at n=2000. The win grows with n because the old
form's cost is `O(n*p)` elementwise work while the new one's is the matmul BLAS was going to do
anyway.

**It reorders the summation, so it is not bit-identical.** Old vs new on the shipped tensors, over
100%/90%/50% coverage and both members: worst 1.1e-12 absolute on scores of scale ~230, worst
1.5e-11 relative (that relative is inflated by samples whose score is near zero, where a 1e-12
absolute miss is large in ratio). Against the 1e-10 abs / 1e-10 rel `core` parity gates that is
~100x and ~7x of margin respectively. **Re-run parity before trusting this**: EPICv1 previously
passed at 5.5e-12 abs (ChrX), so expect ~6.5e-12; the relative axis is the tighter one and is the
one to read.

**The two scalars are computed at scoring time, from `present`, and must stay there.** The
tempting next step is precomputing `sum(center * rotation)` upstream as an intercept -- it looks
like a catalog constant. It is not: both Wang members declare `imputation: omit`, so an absent CpG
is *dropped*, and the correct constant is over `present`, not the declared panel. Measured drift of
`sum(center*rotation)` on ChrX as coverage falls: 0.37 at 1% absent, 1.9 at 5%, 3.8 at 10%, against
a score scale of ~+/-137 -- i.e. 0.3% to 2.8%, applied as a **uniform offset to every sample**. That
is orders of magnitude past the parity gate and is exactly the failure a correlation check cannot
see, which is why the gate is a bounded per-element difference. `sum(r)` in the z-score half is
coverage-dependent for the same reason and drifts faster (0.55 at 1% absent).

**So the contrast with the SystemsAge sync precompute is the point:** that one survived review
because its arithmetic does not depend on which CpGs the user measured. Wang looks like the same
shape and is not. A precomputed constant here would be correct only at exactly 100% coverage and
silently wrong everywhere else.

---

## 2026-08-02 -- Wang parity: EPICv1 passes, cohort_450K is a declared gap

**Parity was run** (maintainer-authorized). **FAIL 0 / SKIP 32 / PASS 699**, 61s. Re-measured
standing state below; the figures in `CLAUDE.md` were stale and are updated. `R CMD check` not run.

**The first run failed 8 targets, all Wang, and the cause was ours.** `run_parity_target()` carried
its own projection -- `panels_union(clock_panels(seq_ids, packs))` -- so it fetched the 4047 / 284
panels and none of the 442533-probe ref. Every EPICv1 sample scored `NA`. This is the **same defect
as the `clock_cpgs()` one two entries below, in a second copy of the same logic**, which is the
argument for the fix that landed: `sequence_cpgs()` (`R/clock_cpgs.R`) is now the one union, called
by both, with an always-on test in `test-score-wang.R` asserting they agree. A private copy of "what
must I measure" is the bug; deleting the copy is the fix.

**EPICv1 then passed with room:** ChrX 5.5e-12 abs / 2.3e-13 rel, ChrY 9.4e-13 / 9.2e-14, against
`core`'s 1e-10 on both axes. First evidence the branch is right against something other than a
re-implementation of it.

**Free finding, since the cohort carries `Female`:** the karyotype call agrees with reported sex
**71/71** on EPICv1 (43 Female, 28 Male, no aneuploid calls). Recorded as an observation, **not
wired as a test** -- see the reasoning in `dev/moment-domains-plan.md` sec 12: parity gates "we match
the oracle", and per-sample agreement with a binary `Female` cannot represent `47,XXY` / `45,XO`, so
any true aneuploid would be a permanent red. What it does settle cheaply is inversion: a swapped X/Y
binding scores 0/71, not 71/71.

**cohort_450K is a genuine gap and is now declared** -- the first two entries in the deliberately
empty `KNOWN_PARITY_GAPS`. The deposited 450K matrix carries **no sex-chromosome probes** (473034 of
485512), so both panels are 0% present; upstream's own fixture declares all 4047 / 284 missing and
expects `0`, which is what the author's code returns from summing an empty panel. We refuse instead:
`check_coverage()` treats `ratio == 0` under a non-`vendor_mean` policy as an unconditional stop,
independent of `min_clocks_coverage`. **That rule is right and was not relaxed to make a fixture
pass** -- a `0` here is not a small score, it is the `Female` quadrant of the sign map, so scoring it
would be a meaningless number wearing a real answer's clothes. Upstream may want to drop those two
fixtures; they can only ever assert `0 == 0` from a run that scored nothing.

**Re-measured standing state**, replacing the pre-Zhang-split figures:

| block   | targets | note                                  |
|---------|---------|---------------------------------------|
| core    | 146     | includes Zhang2019BLUP and Wang@EPICv1 |
| fitage  | 28      |                                       |
| packs   | 56      |                                       |
| horvath | 30      | all skipped (DECISIONS 2026-07-25)    |

260 targets + 2 PhysAge + 1 census = **263 blocks**. 228 targets run x 3 expectations, + PhysAge
2 x 6, + census 3 = **699**. Skips are 30 horvath + 2 Wang@450K = **32**.

`core` grew from the recorded 130 to 146. Six of those are accounted for (Zhang2019BLUP x 2 cohorts,
Wang x 2 members x 2 cohorts); the other ten arrived with the uncommitted `R/sysdata.rda`
regeneration and are **not** explained here -- stated as a measurement, not a claim.

---

## 2026-08-02 -- `predict_sex()` reads the karyotype call; it does not reimplement it

Always-on suite **1179 pass / 0 fail / 264 skip / 0 warn**. Parity not run; `R CMD check` not run.
Implies one new export: `export(predict_sex)`. `document()` also re-sorted `export(calc_accel)`
into alphabetical position -- incidental, not a surface change.

`R/predict_sex.R`: `calc_clocks()` on both `DNAmSex_Wang` members, `as.data.frame(long = FALSE)`,
then `apply_karyotype()`. The whole call is `default` + `rules` read off
`group_entry("DNAmSex_Wang")[["routing"]][["karyotype_call"]]` -- **the first consumer of
`mc_groups` in `R/`**, which is why `group_entry()` (`R/accessors.R`) exists at all: group
declarations are read through an accessor like clock ones, never off `mc_groups` in place.
Verified against all four quadrants: `X<0,Y>0 -> Male`, `X>0,Y>0 -> 47,XXY`,
`X<0,Y<0 -> 45,XO`, and `X>0,Y<0 -> Female` **because no rule covers it**, which is also what an
exact 0 on both axes gives. That last pair is the whole reason this is read rather than written: a
symmetric four-quadrant table agrees on the interior and diverges on the boundary, and the boundary
is every sample in `cohort_450K`.

**Two deliberate divergences from the author.**

1. **A sample missing either score gets `NA`, not the default label.** `wateRmelon::estimateSex`
   overwrites with `predicted_sex[which(...)]`, and `which()` drops `NA`, so an unscorable sample
   silently keeps `Female`. We can produce that state -- a matrix carrying the panels but not the
   z-score ref -- and reporting a sex for a sample nothing was measured for is the same error as
   reporting coverage for a sample it is not true of.
2. **The operand -> input binding is checked against the clock id.** The catalog pairs rule keys
   (`chrX`, `chrY`) with `inputs` by declared order only; the actual binding lives in the prose
   `by_chromosome` field, which is not machine-readable. Positional pairing alone means an upstream
   reorder inverts every call with nothing to catch it -- fixture goldens store scores, not calls.
   So `karyotype_inputs()` also asserts `endsWith(tolower(id), tolower(key))` and stops otherwise.
   This is **not** the banned accessor search: the payload is already declared in `inputs`, and the
   string test only cross-checks two declarations against each other.

**The rule engine is unit-tested, against the usual altitude rule, on purpose.** No fixture covers
it in either repo (parity goldens are scores) and `random_betas()` cannot be steered into a
quadrant, so an output-level test can reach the shape and the label set but never the mapping.
`apply_karyotype()` therefore takes `key -> score vector` and is tested directly on synthetic
quadrants including both boundary cases. If a `predicted_sex` fixture ever lands upstream, that
becomes the golden and this drops to a smoke.

---

## 2026-08-02 -- `clock_cpgs()` reports declared moment refs; panels are unchanged

Always-on suite **1173 pass / 0 fail / 264 skip / 0 warn**. Parity not run; `R CMD check` not run.

Settles the question the entry below left open. `clock_cpgs()` is now
`panels_union(...)` unioned with `unlist(resolve_moment_domains(sequence))`.

**Two placements got conflated, and only one of them is dangerous.** Making the ref a **panel role**
inside `clock_panels()` is wrong: `needed_union` is `panels_union(panels)` over both roles, so it
would widen Wang's coverage denominators from 4047 / 284 to 442533 and break "a moment domain is not
a panel". But `clock_cpgs()` is a **leaf** -- `clock_panels_union()` has exactly one caller, and
`mc_spec()` builds `needed_union` from its own `clock_panels()` call -- so adding the ref there
cannot reach coverage at all. The first was briefly taken as an argument against the second, and it
is not one.

**What decided it: `clock_cpgs()` is on a shipped path, not just in front of the simulator.**
`dev/id-streaming-plan.md` sec 8 makes "project with `clock_cpgs()`, block, score, bind" the
supported route for a cohort that does not fit. A user following that advice for `DNAmSex_Wang` would
project away the ref and get an all-`NA` column with no error -- so under-reporting here is a bug on
a documented workflow. The name is also a promise: this function answers "what must I measure", and
a CpG whose absence turns the score into `NA` is measured input by any reading.

**The rule is "is the domain declarable", not a clock.** `resolve_moment_domains()` already carries
`NULL` for the whole-matrix domain, so `Zhang2019`'s `"full"` drops out of `unlist()` on its own --
there is no set to name -- while Wang's ref contributes its 442533. Same distinction the kernel's
`moment_sets` keys on, reused rather than restated: no clock is named, and a future ref-declaring
clock is served without an edit. `Zhang2019EN` is therefore still exactly its 514-CpG panel, and
what a full-panel clock needs beyond that is still carried by `note_full_panel_clocks()` at
`calc_clocks()` time. Both are tested.

**`sim_DNAm()` stays exactly `clock_cpgs()`.** An earlier pass put this union in `sim_DNAm()`
instead; that left the public answer wrong, split one rule across two functions, and would have made
the simulator the only place that knew the real requirement. The blank/NA screen moved up with it,
out of `clock_panels_union()` and onto the whole answer, so it is applied once.

**Costs, accepted.** `clock_cpgs("DNAmSex_Wang_ChrX")` now answers 446580 rather than 4047, and a
Wang sim is that wide (~14 MB at n = 4, transient). `remove =` is diluted for this family -- 5
dropped columns out of 446580 hit a panel probe ~1% of the time, so it stops being a way to force
absent-panel behaviour there. Nothing uses `remove` today. And the smoke tier's 2 expected warnings
are gone, since it now scores Wang for real -- which leaves the `NA`-with-no-reference path covered
**only** by its named test in `test-score-wang.R`. Better place for it, but load-bearing now: do not
delete it as redundant.

---

## 2026-08-02 -- the Wang branch reads its own domain, and says when it cannot

Always-on suite **1167 pass / 0 fail / 264 skip / 2 warn**. The 4 red tests from the two entries
below are green. Parity not run; `R CMD check` not run. The skip count jumping 2 -> 264 is not a
regression: `test-fixtures-parity.R` used to die at **file** level on `score_type()` (one of the 4
failures), so it emitted no targets at all; now it loads and its parity tier skips normally.

`R/score_DNAmSex_Wang.R` + a `(DNAmSex_Wang, wrapper) -> "DNAmSex_Wang"` group hook. The branch is
the declared recipe and nothing else: `sample_scale` against the `DNAmSex_Wang:zscore_ref` domain,
`center_scale` by the declared `center`, `project` onto `rotation`. Verified against an independent
R implementation on both members -- max abs difference 1.4e-13 on scores of magnitude ~40, i.e. 3e-15
relative.

**The operand names are read off the recipe, not hardcoded.** `recipe_step_op(id, op)` finds the step and
the step names its component (`center`, `rotation`); `SystemsAge` hardcodes its component names and
that was the tempting precedent. Reading the declaration costs six lines and means a rename upstream
is a `catalog_bug()` naming the component instead of a silently-NA score vector. Same reason the
branch stops when `center_scale` declares a `scale` it does not apply, and when `center` and
`rotation` do not cover the same CpGs: `center[present]` on a missing name returns `NA`, which would
propagate through the projection and produce an all-`NA` column with no diagnostic.

**A sample with fewer than 2 observed reference CpGs is scored `NA`, noted, and warned about.**
This is the `n < 2` guard in `split_moments()` arriving at a consumer. It has to be said out loud
because **coverage cannot see it**: the ref is not a panel, so a sample can hold 4047/4047 of the
scoring panel, report 100% coverage, and still be unscorable. The mechanism already existed for
exactly this -- `note_scoring_failure()` + a plain `warning()`, the shape `score_normalized()` uses
for a failed BMIQ fit -- so the samples land in `$provenance$scoring_failures` rather than only in a
message the user may have suppressed.

**Consequence, and it is load-bearing for how the smoke tier reads:** `sim_DNAm()` materializes
declared panels, and a moment ref is not one, so the smoke tier hands both Wang members a matrix
their ref meets nowhere and gets `NA` plus that warning back. The tier still does its job (default
configuration, no error), but it is **not** a numeric check on this family, and the 2 warnings in a
green run are expected rather than a smell. `test-score-wang.R` builds panels plus a slice of the
ref to get finite scores. Whether `clock_cpgs()` should report a clock's moment ref as required
input -- which would make `sim_DNAm("DNAmSex_Wang_ChrX")` scorable and fold the ref into the public
"what must I measure" answer -- is left open, not decided by silence: see
`dev/moment-domains-plan.md` sec 12 item 3.

---

## 2026-08-02 -- `DNAmSex_Wang` stays in the callable pool

Decision only; no code. Resolves the contradiction between `dev/moment-domains-plan.md` sec 9
("take Wang out of the pool", left open) and the settled `predict_sex()` shape (thin sugar over
`calc_clocks(DNAm, c("DNAmSex_Wang_ChrX", "DNAmSex_Wang_ChrY"))`, which requires both members to be
callable by name). Both could not hold. **The design wins: `resolve_clocks()` accepts both.**

**Two of the three arguments for removal had expired**, which is what made this lopsided rather than
a genuine toss-up. Removal was offered mainly to buy K = 1 in both front doors -- but the
multi-domain sweep is built and tested, so that simplification no longer exists to be bought. And
the kernel was the stated blocker for the whole family; it no longer is. What was a
cost-of-delay argument in favour of the smaller option is now an argument for nothing.

**The surviving argument against is real but misfiled.** A sex PC in `$scores` is an `n x k` double
a user can hand to `calc_accel()` and get confident nonsense from, since nothing in the type says
only the sign is meaningful. That is a fact about **output typing**, and it generalizes to every
score that is not an age -- `EpiTOC2`'s mitotic index has the same shape. Solving it by removing one
clock from the pool would fix one instance of a general problem while creating specific work:
Wang would never return an `mc_result`, so its coverage record needs a new home, and `predict_sex()`
would have to drive `mc_spec()` / `mc_cohort()` / `score_cohort()` directly instead of the one
public entry point. If the hazard is worth addressing it should be addressed as typing, for all such
clocks, not as pool membership for one.

**Consequence to expect:** `calc_clocks(DNAm, "all")` will span `"full"` and
`DNAmSex_Wang:zscore_ref`, so **K = 2 becomes reachable through the front door** for the first time
-- the case the moment-domain work was built for, and one no test can currently reach.

---

## 2026-08-02 -- moments are keyed domains, not one banked pair

Always-on suite 1154 pass / 4 fail / 2 skip. The 4 are the same parked `DNAmSex_Wang` routing gap
as the entry below (`score_type()` stops on both members, so smoke plus the two census tests that
sweep every catalog clock fail); none are new. Parity not run; `R CMD check` not run.

**`spec[["needs_moments"]]` (logical) becomes `spec[["moment_domains"]]` (key -> cpgs).** The
logical could only ever say "bank the whole-matrix moments", which is why the entry below had to
record Wang banking nothing at all as a deliberate consequence. A request spanning both kinds --
`calc_clocks(DNAm, "all")` the moment Wang is callable -- had no representation, and the failure
mode was silent: Wang would have taken Zhang's whole-matrix moments. Now `mc_cohort()` banks
`key -> list(mean, sd)` and a branch reaches its moments by clock id (`block_domain_moments(block,
id)`, which derives the key), so reaching for an unbanked domain is a `stop()` rather than a wrong
number and **no branch ever spells a domain key**.

**The key is derived, never assigned:** `"full"` (`FULL_MOMENT_KEY`) for a ref-less step, else
`<group_id>:<ref_name>`, minted in `clock_moment_key()` (`R/accessors.R`). `clock_moment_key()` is
split out of `clock_moment_domain()` so a caller wanting only the key -- the `resolve_moment_domains()`
dedup, `clock_needs_full_panel()`, every score branch -- never resolves the ref's CpGs (442533 of
them for Wang) just to throw them away. Minting it in the accessor rather than in
`mc_spec()` is what makes two clocks sharing a ref collapse to one domain by construction -- both
Wang members land on `DNAmSex_Wang:zscore_ref` without anything comparing CpG sets. The `:` is what
keeps a declared domain from colliding with `"full"`, and a group id cannot contain one.

**One pass, whatever K is.** `col_stats(obj, cols, moment_sets)` labels each column with the bitmask
of the sets containing it, accumulates into one Welford atom per distinct mask, and merges atoms per
set with Chan's formula. A column in several domains is read once. Welford rather than the additively
obvious `(n, sum, sum_sq)`: on betas in [0,1] the cancellation is about one digit in sixteen, which
would be unremarkable except that Wang's output is a **sign**, so the error concentrates exactly on
the samples near a quadrant boundary, where a lost digit flips a call instead of nudging a number.
Atoms are indexed by observed mask, not `2^k` -- fine at k = 3, not at k = 8.

**The rejected cheaper option is one sweep per domain**, which needs no kernel change and about
30 lines of R. It re-reads every overlapping column once per domain (~+50% scan on a mixed request).
That was the fallback if the mask proved fiddly; it did not.

**Element validation lives in R (`check_moment_sets()`), not in the kernel.** Not a style call: on
this toolchain `as<IntegerVector>()` on a `NULL` or character element is **not a catchable
condition** -- it terminates the process (exit 127, `tryCatch` bypassed), and the same throw is
catchable under plain `sourceCpp`, so the cause is build configuration (`~/.R/Makevars.win` carries
`-UNDEBUG -g -O0`; the package adds `-fopenmp` with `-static-libgcc`). Validating in R removes the
only path that reaches it. Worth knowing independently: `expect_error()` on any future kernel path
relying on a C++ throw is unusable locally.

**The `n < 2` guard is load-bearing, not defensive.** The kernel reports an unobserved row as
`n = 0, mean = 0, m2 = 0` -- counts disambiguate rather than the kernel emitting NaN -- so R applies
two different thresholds in `split_moments()`: a mean needs `n >= 1`, an sd needs `n >= 2`. `n = 1`
yields `NaN` naturally (`0/0`); `n = 0` yields `sqrt(0 / -1) = -0`, which reads as real zero spread
and divides to `Inf`. Nothing upstream makes this unreachable: the dead-sample gate keys on the
**scoring** panels, and for Wang the scoring panel and the moment ref are **disjoint** (0 shared
probes, 4047 and 284 sex-chromosome probes against a 442533 autosomal ref), so a sample can clear
every existing gate with full sex-chromosome coverage and still have zero ref observations. An
empty domain is likewise a data fact reported as `NA`, not a usage error.

**Coverage is untouched, deliberately.** A moment domain is not a panel: the sets index `DNAm`
directly, so a ref never widens `needed_union` and the declared `n_cpgs` do not move.

**The 1 GiB accumulator guard was written and then removed.** It refused `NS * nr * 20` bytes above
a ceiling, on the theory that `NS` is emergent -- it counts distinct membership *patterns*, not sets
-- so a set system the caller thinks is small could allocate more than it looks like. The bound that
kills the guard is in the same sentence: a signature is a **per-column** fact, so `NS <= ncol`
always, and the accumulators can never exceed `20 * nr * nc` -- **2.5x an `obj` R has already
materialized**. The check could not fire before R itself had failed to allocate, so it was buying a
different error message, not a different outcome. The only shape approaching the ratio is a matrix
narrow enough that nearly every column has a unique pattern (measured: ~430 MB of input at
`nc = 3`), which is unreachable through `scan_missing_cpgs()` -- `col_stats()` is internal, and its
sets come from the catalog, where `K <= 2` gives `NS <= 3`. What survives is the *fact*, as a
three-line comment at the allocation; the ceiling constant, the branch and the four-argument `stop()`
are gone.

**The mask-width check stays, and is not the same kind of thing.** `1u << 8` does not fit a
`uint8_t`, so that bound is correctness. Do not read the removal above as licence to drop it: one
guard was a resource heuristic against an unreachable state, the other is the type's own limit.

**The mask is a `uint8_t`, and K is dynamic.** The width went `uint64_t` -> `uint8_t`: `mask[]` is
one entry per column, so at EPICv2 width that is 7.5 MB -> 0.94 MB, and -- the larger win -- an
8-bit signature has only 256 values, so the signature -> slot map is a flat 256-entry table instead
of an `unordered_map`, and `<unordered_map>` leaves the file. This does **not** undo "index atoms by
observed mask, not by `2^k`": that argument is about the `nr`-length accumulator **blocks**, which
still get compact ids. Only the lookup became a table, because 1 KB is free at any width a byte
holds.

**What K is, since this was gotten wrong once.** K is the number of distinct domains **the requested
sequence** needs: 0 for a clock with no `sample_scale`, **1 for a Zhang arm on its own** (the common
case today), 2 for a run spanning Zhang and Wang. The catalog-wide count of 2 is a *ceiling* over
every clock that exists, not a per-call value. An intermediate version hardcoded `K = 2` and derived
a closed-form slot layout from it; that pinned the kernel to the one value the front door never
produces, so `calc_clocks(DNAm, "Zhang2019EN")` -- the most ordinary call a `sample_scale` clock has
-- failed with "exactly 2 moment sets are required", and the suite went from 4 failures to 18. Only
the *width* is fixed. Do not hardcode K, and do not read a census of the catalog as a contract on
one request.

**The width is enforced where a maintainer sees it.** Dropping 64 -> 8 moves the ceiling closer to a
plausible upstream future, and the refusal would otherwise fire at runtime inside a user's
`calc_clocks()`. So `MAX_MOMENT_SETS` (`R/missingness.R`) mirrors the kernel, one test asserts the
two agree on the boundary, and an always-on census asserts the shipped catalog's distinct domain
count fits. A ninth domain is then a red suite for whoever synced it, not an error for whoever
scored with it -- which is what makes the tighter type safe rather than merely smaller.

**K is still 1 through the front door.** Wang has no scoring branch, so `mc_spec()` only ever mints
`"full"` today; the K > 1 path is covered by unit tests on `col_stats()` and `scan_missing_cpgs()`,
not by `calc_clocks()`. That is the point of doing the seam first -- the Wang branch is now a branch,
not a re-plumbing. Whether Wang stays in the callable pool at all is still open and independent
(`dev/moment-domains-plan.md` sec 9).

---

## 2026-08-02 -- `shared[]` is a declaration, not build scrap; full-panel splits on `ref`

Always-on suite 1074 pass / 4 fail / 2 skip. The 4 are the parked `DNAmSex_Wang` routing gap
(`score_type()` stops on both members, so smoke + the two census tests that sweep every catalog
clock fail); none are new. Parity not run; `R CMD check` not run.

**`shared` leaves `CATALOG_BUILD_ONLY_FIELDS`.** The handoff in `dev/update-DNAmSex.md` asked
upstream to re-declare `zscore_ref` as a `probe_sets[]` entry, on the premise that the trim left
the tensor with no declared pointer. Upstream declined (`dev/reply-DNAmSex.md`) and was right on
the facts, which were checkable here: `build_group_bundles()` runs *before*
`trim_build_only_fields()` (`sync.R:2184` vs `:2187`) and `mc_bundles` / `mc_groups` are assigned
untrimmed (`:2192-93`), so the payload was always in the bundle and the path was always in
`mc_groups[[gid]][["shared_tensors"]]`.

What the trim actually destroyed was narrower and worse-shaped: the **`name` -> `file` binding**.
`shared_tensors` is paths only, so nothing could resolve `recipe[["Xz"]][["ref"]] == "zscore_ref"`
to a file. That is a resolution gap, and the accessor invariant forbids closing it by searching the
bundle. Retaining `shared` closes it exactly, and `SHARED_FIELDS` is already `c("name", "file")`,
so the entry carries the binding and nothing else -- 33 clocks, two strings each. Measured: the
regenerated `sysdata.rda` did not grow.

**Why not accept the `probe_sets[]` copy anyway, since it was additive and cheap.** It would be a
second owner of a fact the recipe operand already owns, and it would be *inert* -- `sample_scale`
resolves through the shared namespace, so nothing would ever compare the two. Drift would be
silent on both sides. Upstream's ownership rule and our "accessors read declarations" rule are the
same rule seen from two ends; the fix belonged wherever the duplication would not be created, and
that was here.

**`shared` is keyed by `name` in `key_catalog_lists()`**, joining `components` / `probe_sets` /
`recipe`. A resolver over an unkeyed list is a scan, and the point of the change was to make the
lookup a lookup.

**`clock_needs_full_panel()` now means "a `sample_scale` step with no `ref`", not "has a
`sample_scale` step".** It was user-visible and wrong: it told a caller that Wang "scores against
every column of `DNAm`" when Wang's moments come from a declared, closed 442533-probe set. The
distinction is not size -- Zhang's moment set is *whatever the caller supplied*, so it has no
closed membership at any time, including sync time. That is a difference in kind, and `ref`
presence is the seam that expresses it.

Note the knock-on, which is deliberate: `spec[["needs_moments"]]` is `length(full_panel) > 0`, so
Wang now banks no moments at all. That is correct while Wang has no scoring branch, and it means
whoever writes that branch cannot get whole-matrix moments by accident -- they have to do the
`col_stats()` work first.

**Still parked, and the block moved.** `col_stats(row_moments = TRUE)` sweeps the subset *plus*
its complement by construction (`col_stats.cpp:180`), so there is no way to obtain moments over a
declared subset today. That blocks the Wang scoring branch, hence the `score_type()` group hook,
hence `predict_sex()`. The upstream contract is no longer the blocker; the kernel is.

**Do not hard-code the karyotype quadrants.** Upstream found our prose wrong while structuring it:
`wateRmelon::estimateSex` assigns `Female` unconditionally and overwrites with three rules, so
`X>0 & Y<0` is never evaluated and a four-quadrant table diverges wherever a score is exactly 0.
`cohort_450K` is that case -- every score 0, all 80 samples labelled Female, which no quadrant
matches. Both suites store scores, not calls, so neither would have caught it. The map now ships
as `mc_groups[["DNAmSex_Wang"]][["routing"]][["karyotype_call"]]` (a `default` plus three rules);
derive from it.

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
This entry settles `dev/pr3-triage.md` sec 5.4 for D1 and D2, which are in. D3 (`codebook`) was
kept out here and that was **reversed on 2026-08-04** -- see the entry of that date; do not read
this paragraph as the current position.

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
