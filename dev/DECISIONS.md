# Decisions log (package rewrite)

Append-only, date-stamped. Records **why** we chose a design during the rewrite under
`dev/migration-plan.md` — the “we tried X / other maintainers will ask this” history that
should not bloat the plan’s operational sections.

**Scope:** R package rewrite, packaging, API, and local maintainer workflow. Upstream
metadata contract decisions live in `data-raw/methylCIPHER-meta/control/DECISIONS.md`.

Newest first. Add an entry when a decision reverses a prior approach or is likely to be
second-guessed; do not restate rules already stated in the migration / detail plans.

---

## 2026-07-22 -- External scoring panels live in the pack, not the bundled catalog

**Decision.** `clock_scoring_cpgs(id, packs)` returns `pack$cpgs` for an external clock and never
consults the catalog; `sync()` correspondingly stops writing those CpGs into `mc_catalog`
(`drop_external_probe_cpgs()`). Panels for bundled clocks are unchanged. `clock_panels()` and
`needed_cpgs_union()` gained a `packs` argument, and `calc_clocks()` now resolves packs *before*
panels, since the panel is in the pack.

**Why -- correctness first.** The panel was stored twice: in `mc_catalog` and in the pack. Verified
`identical()` for all 28 external clocks today, but nothing enforced it. Packs are content-addressed
and independently re-uploadable, so a weights update that shifted the panel would silently disagree
with the bundled copy, and the failure mode is misaligned scoring rather than an error. One source
kills that class of bug. It also matches the existing convention -- `clock_coefs(id, packs)` and
`clock_impute_ref(id, packs)` already read external data from the pack; the panel was the outlier.

**Why it is also the big perf lever.** External panels are 3 distinct vectors but **92%** of all
panel elements (561,491 of 610,619; PCClocks 78,464 x 14 members, SystemsAge 125,175 x 13,
PCBrainAge 357,852). Dropping them takes `mc_catalog` from 1.79 MB / 1.26s to **0.09 MB / 0.021s**.
Separately, all 14 PCClocks members now receive the *same SEXP* from `pack$cpgs`, so `dedup_panels()`
short-circuits on pointer identity and there is no per-clock `unique()` over 78k strings:
`clock_panels()` 0.112s -> **0.008s**.

**Why not a keyed panel store in sysdata.** The alternative was splitting panels into a separate
lazy object (or per-group objects) so the catalog stays cheap while pack-free `sim_DNAm("PCClocks")`
keeps working. Rejected: it preserves the duplication that is the actual hazard, and buys a dev
convenience that is not worth it -- an external clock cannot be *scored* without its pack anyway, so
a pack-free simulated panel only ever exercises machinery.

**Consequence.** `sim_DNAm()` takes `assets` / `ask` and requires the pack for external clocks;
with a cached pack the old call still works. `test-score-external.R` now mints synthetic panels for
its in-memory packs instead of borrowing the real ones (faster, and it was circular once the pack
owns the panel). The code change and the data change are independent: until `sync()` is re-run the
bundled copy is simply ignored, so there is no flag day.

**Not yet landed.** The 0.09 MB / 0.021s catalog needs a `sync()` re-run to regenerate
`R/sysdata.rda`; that is maintainer-side and was not done here.

---

## 2026-07-22 -- sysdata.rda ships xz, not use_data()'s bzip2 default

**Decision.** `sync()` passes `compress = "xz"` to `usethis::use_data()`, and the committed
`R/sysdata.rda` was recompressed in place to match (content verified `identical()` per object, so
no `sync()` re-run was needed).

**Why.** `use_data(internal = TRUE)` defaults to `compress = "bzip2"`, which is the worst of both
worlds for this blob. Measured on the same five objects: bzip2 11.89 MB / 4.36s load, gzip
13.40 MB / 2.06s, **xz 2.31 MB / 1.85s**, uncompressed 55.22 MB / 1.34s. xz wins on size *and*
load; nothing trades off. Relevant to the CRAN target too -- 11.89 MB blew the 5 MB tarball
guidance on its own, 2.31 MB does not.

**Why this is the lever for the dev loop.** Every `load_all()` / `test()` / `check()` / `document()`
pays this deserialization eagerly (pkgload `load()`s `sysdata.rda` directly); `document()` in
particular is ~all sysdata, since parsing all 15 `R/*.R` is 0.015s.

**Sharing SEXPs does nothing; restructuring does.** Making the 114 stored probe-set vectors share
one SEXP per distinct panel was measured and is a no-op -- 1.79 MB either way, load 2.14s -> 2.01s
-- because R's serializer writes each vector out in full and only ref-caches the CHARSXPs.
*Structurally* splitting the panels out of `mc_catalog` into a keyed store is a different thing and
does work: catalog metadata alone is 0.01 MB / **0.009s**, the 84-panel store is 1.76 MB / **0.385s**,
versus 1.79 MB / 2.05s monolithic. The win is element count -- 3.1M nested elements collapse to
590k, so the string-cache does 5x less work. (Supersedes the first version of this entry, which
concluded from the SEXP-sharing result that catalog dedupe was a dead end. It is not.)

---

## 2026-07-22 -- CpG set math: dedupe identical panels, not special-case external groups

**Decision.** `resolve_cpgs()` runs the present/absent split **once per distinct CpG panel**, not
once per clock. `clock_panels()` fetches each clock's scoring + norm panels a single time and maps
identical vectors onto a shared set (`dedup_panels()`, linear scan on `identical()`); member clocks
then share the resulting `present`/`absent` vectors by reference. `calc_clocks()` calls
`clock_panels()` once and feeds both `panels_union()` (missingness scan) and `resolve_cpgs()`.

**Why.** Every member of an external pack group carries the *same* panel: PCClocks is 14 clocks x
one 78,464-CpG panel, SystemsAge 13 x 125,175. The old code hashed that panel once per clock, and
did the whole fetch twice -- `needed_cpgs_union()` and `resolve_cpgs()` each called
`clock_scoring_cpgs()` for all 14. Measured on `sim_DNAm("PCClocks")`: `resolve_cpgs` 0.333s ->
0.022s, whole set-math path 0.486s -> 0.140s. It also drops 14 redundant copies of a 78k character
vector out of `cpg_list`.

**Why not scope it to PCClocks/SystemsAge.** The obvious fix is a group-keyed branch for external
packs, but that buys a new special case for a property that is not actually about externality --
it is about panels being equal. Deduping on `identical()` needs no group knowledge, keeps the
closed branch set closed, and stays correct if a bundled family ever shares a panel. Bundled groups
pay only the dedupe scan, which is a no-op for them (GrimAge: 12 clocks / 11 distinct panels, all
under 1030 CpGs); `clocks = "all"` is 115 clocks / 85 distinct panels and the scan short-circuits
on length mismatch.

**Verified.** Deduped per-clock sets are `identical()` to the old per-clock math, and cohort parity
runs green (198 passed / 0 failed), so the shared vectors reach the pack scorers unchanged.

**Not addressed here.** The remaining ~1.1s of a cold `calc_clocks("PCClocks")` is `load_mc_assets()`
reading the qs2 pack from the runtime cache; passing `assets =` an already-loaded pack drops the call
to ~0.3s and steady-state scoring is ~0.09s. Pack I/O is a separate question from the set math.

---

## 2026-07-22 -- Missing Age/Female: propagate NA, warn once in check_pheno

**Decision.** An `NA` in a required covariate (`Age`, `Female`) is a **legal input**. It propagates
through the linear algebra to an `NA` score for that sample and nothing else: the row is never
dropped, no error is thrown, and every other sample scores normally. `check_pheno()` emits **one**
warning naming each affected covariate column and its NA sample count.

**Why warn upstream, not per clock.** Propagation already worked (`X %*% cox` in `score_grimage()`,
`cov_mat %*% cov_coefs` in `linear_predictor()`), but it was *silent* -- a user with a few missing
ages got an `NA` column with no pointer back to `pheno`. Warning at the single validation site is
succinct and clock-count-invariant: one message regardless of how many clocks consume the covariate,
emitted before any scoring. A per-clock or per-scorer warning would fire N times for the same root
cause and would have to be threaded through every branch.

**Why not error or drop.** Dropping rows silently changes `nrow(scores)` and breaks id alignment
against the caller's pheno; erroring makes one bad row block a whole cohort. `NA` in, `NA` out is
the least surprising contract and keeps the result rectangular.

**Scoping.** The count is taken over rows that survive the id-join (`match(sample_id, pheno[[ID]])`),
so an `NA` on a cohort row that is not being scored does not warn. Under positional alignment all
rows count, since all are scored.

**Consequence.** Surrogates inherit the `NA` only where they declare the covariate: with `Age`
missing, `DNAmPAI1` / `DNAmLeptin` / `DNAmlogCRP` (no covariates) still score finite while the
Age-consuming surrogates and both GrimAge composites go `NA`. Coverage counters are unaffected --
they track CpGs, not covariates.

**Sites.** `check_pheno()` / `warn_missing_covariates()` in `R/resolve_inputs.R`; call site in
`calc_clocks()` now passes `sample_id`. Tests in `tests/testthat/test-score-grimage.R`.

---

## 2026-07-21 -- Dunedin is a bundled QN family (not an external adapter); Hybrid missing data

**Decision (routing).** DunedinPoAm38 and DunedinPACE ship **bundled** (`cpg_coefficient` /
`linear`, group `Dunedin`), not as external `computation_type=wrapper` adapters as the early
plan assumed. Both route to a shared `score_dunedin()` branch. PoAm38 is plain linear; PACE
quantile-normalizes a 20000-CpG gold panel to `gold_standard_means` (via `betanorm::quantile_norm`,
bit-exact with the author's `preprocessCore::normalize.quantiles.use.target`) and then scores
linearly on its 173 model CpGs (a subset of the panel). The gold panel ships as the
`gold_standard_means` tensor; its names are the QN background (there is no inlined
`quantile_normalization_background` probe_set in the compiled catalog), so `clock_norm_cpgs()`
falls back to those names and `dunedin_gold_means()` reads the tensor. `present_needed_union`
now also unions `norm_present`, so partial-NA gold-panel CpGs get the shared cohort cache.

**Why bundled + betanorm.** Both clocks reproduce the author fixtures to machine epsilon on the
EPIC cohort (PoAm38 4.4e-16; PACE 1.8e-15). `betanorm` stays a **Suggests** soft dep: it is a
GitHub-only (`hhp94/betanorm`) compiled package, so a CRAN target cannot Import it; PACE errors
cleanly and sim-smoke / value goldens skip when it is absent. Reimplementing preprocessCore's QN
in pure R was rejected -- betanorm already matches it exactly and is the maintainer's own package.

**Decision (missing data -- Hybrid).** The author's `PACEProjector`/`PoAmProjector` cascade uses a
single `proportionOfProbesRequired` threshold to (a) NA a whole clock under-covered on its model
(PACE also gold) panel, (b) NA a sample observing too few panel cells, (c) impute lightly-missing
present probes to the cohort mean, (d) replace heavily-missing present probes with vendor means,
and PACE fills fully-absent gold probes with `gold_standard_means` before QN. We adopt a **Hybrid**:
keep methylCIPHER-native imputation (partial NA -> shared cohort cache; fully-absent -> vendor
means (PoAm) / gold fill (PACE)), and add only the two coarse **NA-gates** (a) and (b). We drop the
per-probe threshold split (d) and the author's quirk that leaves heavily-missing non-model gold
probes as NA. The gates reuse the existing `min_coverage` argument (default 0.8) -- it *is* the
author's proportion-of-probes-required -- so no new per-clock argument was added; `min_coverage = 0`
disables warning and gating together. The parity cohort has full coverage, so the divergent
degraded-coverage rules are exercised only by always-on value goldens, not parity.

**Decision (error handling -- deliberately not defensive).** `score_dunedin()` mirrors the author
projectors' stance: **fill or drop to NA, never stop.** Insufficient coverage yields NA (whole clock
or per sample); a missing scoring CpG is filled. The author's only `stop()` is a non-numeric-matrix
check, and ours is likewise a single one -- `betanorm` missing -- placed at the **point of use**
(inside the scoring block) so an under-covered PACE call still returns NA without needing the
package, exactly as the author reaches `preprocessCore` only after its NA-gate. Three earlier guards
were removed as dead defensiveness: "model CpGs absent from the gold panel" and "absent CpG lacks a
fill value" can never fire (model CpGs are a subset of the gold panel; `gold_standard_means` and
`model_means` are complete by construction), and a `cov_ratio()` divide-by-zero helper guarded a
panel that is never empty. Catalog-integrity assertions belong to sync, not to a scorer.

**Why not a general per-clock arg mechanism / `...`.** Only one override (the coverage threshold)
exists and it already had a home (`min_coverage`), so a `clock_args` dict or a `...`-intersection
dispatch would be speculative. A `...` that silently swallows a mistyped argument is a correctness
hazard in a scoring package (a typo'd threshold changes results with no signal) and is the same
arg-walker anti-pattern the engine forbids -- the dead `...` in `calc_clocks()` was removed. If a
general mechanism is ever needed (>= 2-3 real params), it will be an explicit `clock_args` list that
errors on an unknown clock id or arg name, never `...`.

**Parity.** PACE's catalog `fixture$parity_policy` is still `skipped` (a meta-repo value that the
portable path could not previously recompute). Now that betanorm makes it bit-exact, flipping it to
`exact` is a meta.json + re-`sync()` step (maintainer-side); until then PACE's numeric correctness
rests on the always-on value goldens (allowed while parity is skip-listed). PoAm38 (policy `exact`)
is picked up automatically by `parity_targets()` and passes.

**Also fixed here.** `test-fixtures-parity.R` wrapped its parity loop in
`if (skip_if_no_cohort() | skip_if_no_pack(clock_id))`, referencing an undefined `clock_id` at file
scope -- it errored on any enabled parity run. Moved both skips inside each `test_that` (matching the
PhysAge block), which is what the 2026-07-21 parity-gating entry below intended.

## 2026-07-21 -- External clock tests smoke-only; check_DNAm orientation keys on ^cg

**Decision (external tests).** `test-score-external.R` no longer re-derives scoring values. Every
external member (PCClocks, PCBrainAge, SystemsAge, incl. the SystemsAge systems_PCA composite) has
a passing `exact` cohort-parity fixture, so parity owns the goldens; this file keeps only always-on
coverage parity cannot give: the in-memory `assets=pack` closed-set path runs and returns the right
shape (smoke), the wrong-pack error, the PCClocks no-family-expansion subset contract, and the
vendor-fill coverage flags (`score_imputed_full`). Completes the partial removal in the "test
altitude" entry below -- the composite golden had survived in the tree; now all external in-test
goldens are gone. Trade-off: external numeric correctness now rests entirely on the (CRAN-skipped,
pack-gated) parity tier, mirroring how bundled clocks lean on sim-smoke + parity. Shared per-group
packs are built once at file scope (they were rebuilt byte-identically per test).

**Decision (check_DNAm).** The orientation guard drops the `nrow > ncol` dimensional heuristic --
it false-positived whenever samples outnumber a small CpG panel (every parity fixture) -- and keys
solely on the `^cg` prefix: warn when no column looks like a CpG, naming the transposed case when
the rows do. A genuinely transposed matrix is also caught downstream by `warn_low_coverage`.

## 2026-07-21 -- Cohort parity tier gated behind METHYLCIPHER_PARITY, not just file.exists()

**Decision.** `test-fixtures-parity.R` now skips unless `METHYLCIPHER_PARITY=1` is set (in
addition to the cohort duckdb being staged). The env flag gates both the file-scoped duckdb
connection and each test's `skip_if_no_cohort()`. A dev-only, build-ignored helper
`test_parity()` (`R/dev-utils.R`) sets the flag via `withr::with_envvar()` for one run.

**Why.** The parity tier is ~34s of a ~37s suite (one duckdb query + a real `calc_clocks()`
per fixtured clock), so on a machine with the cohort staged every `devtools::test()` paid it
on each change. Default runs are now ~4s; the science gate runs on demand via `test_parity()`
(or any env set). No CI workflow exists yet; whatever runs the gate must export the flag.
`R/dev-utils.R` is git-tracked but `.Rbuildignore`d, so it is available after `load_all()`
yet never ships to CRAN.

## 2026-07-21 -- Batched pack scorers for PCClocks / SystemsAge; no general grouping layer

**Decision.** External groups whose members share one large CpG panel (PCClocks, SystemsAge) are
now scored per *group* in a single shared `DNAm[, present]` subset + one matmul over all requested
columns (`score_pack_group()` in `R/score_pack.R`), instead of routing each member through
`linear_score()`. `resolve_clocks()` is unchanged -- no family expansion, no reverse-resolve, no
member-input restriction; requesting one member returns one member, and the batch just collapses
whatever pack members are in the plan into one matmul.

**Why.** The dominating cost of scoring a pack member is the panel-wide subset, not the matmul.
Per clock it is repeated once per member: measured **13.7x** for 14 PC clocks (78k-wide panel);
the SystemsAge composite repeats it ~24 times across its age/organs/systems sub-steps. Batching
pays the subset once. It reproduces the exact imputation contract (partial-NA cohort cache; absent
-> vendor-mean offset from `pack$impute`), so parity holds within fp tolerance -- guarded by the
in-test goldens (multi-member PC with covariates + `anti.trafo`; the SystemsAge systems_PCA
composite re-derived) and cohort parity.

**Why not a general `calc_group` layer** (fold *all* same-recipe linear clocks into one matmul).
Considered and rejected. The win only exists where the panel is huge *and shared*: the bundled
clocks' scoring CpGs overlap just **1.6x** (sum 33,249 vs union 20,724), so batching all 86 saves
~26ms on a ~60ms operation while the dense union matmul does ~50x more (zero-filled) flops -- and
it would fold per-clock vendor refs (bundled refs differ per clock, unlike the packs' single shared
`pack$impute`), mean denominators, covariates, output transforms, and coverage into a batched
engine: the recipe-ish per-clock logic the "one engine + closed branch set" invariant keeps out.
Not worth it. Batching earns its complexity only for the two shared-panel packs.

**Why GrimAge is excluded** though it is a family. Its surrogates have disjoint CpG sets (no shared
panel -> no subset win), and `"GrimAge"` as a group token already expands to its members. Member ->
family expansion was dropped entirely: it made output unwieldy (one member request -> 14 columns)
and required reverse-resolve, while buying nothing the group token doesn't already give.

## 2026-07-21 -- Test suite deliberately loosened; "test altitude" policy set

**Decision.** The suite had grown too tight for a fast-moving pre-alpha: it pinned exact
error-message strings, maintainer-side plumbing shapes (asset filenames, release tags, download
URLs, the 4-layer cache-dir precedence order), per-clock internal dispatch-tag tables
(`clock_reduction()`, `score_type()`), and re-derived full recipes in-test. All of these break on
refactors that change no observable behavior. Loosened them so tests assert on `calc_clocks()`
output and the parity science gate only; the policy now lives in CLAUDE.md "Test altitude".

- Error/warning/message assertions drop the regex -> bare `expect_error/warning/message`; the
  behavior after the throw (writes nothing, still returns the payload, etc.) is still asserted.
- Dropped the per-clock reduction/route tag tables; kept the closed-set "every clock maps to a
  known tag" guard. Routing is proven through `calc_clocks()` output.
- Dropped filename/release-tag/URL format asserts and the cache-dir precedence spec; kept the
  download *behaviors* (verify, no scratch, warn-not-stop on hash drift, closed-set, never
  auto-delete).
- Removed the SystemsAge composite recipe re-derivation -- cohort parity passes it at ~1e-11, so
  the fixture owns the golden. **Kept** the DNAmFitAge KDM re-derivation: its parity is skip-listed,
  so the in-test math is currently its only numeric gate. Revisit when that parity lands.

**Added.** `test-sim-smoke.R` -- `expect_no_error` over every bundled, supported clock via
`sim_DNAm()` + `calc_clocks()`. This is the always-on crash net the Testing section had described
but no test implemented. Net: ~256 lines of brittle assertions removed, ~84 crash-smoke cases
added; full suite 363 pass / 0 fail.

**Not done.** S3 record-verb tests (`as.matrix` / `[` / `cbind` / ...) -- the generics are not
implemented yet, so there is nothing to test; add them when the methods land.

---

## 2026-07-21 -- SystemsAge orchestrator landed (external.md step 4); external scoring complete

**Decision.** Wired the SystemsAge family (Sehgal 2024, 13 members) -- the last external.md gap.
All 13 members now pass cohort parity at exact tolerance (max_abs_diff ~1e-11, gate 1e-6), so the
three external groups (PCClocks, PCBrainAge, SystemsAge) are fully scored.

1. **Organ sub-clocks go through the shared linear engine, not the orchestrator.** The 11
   organ/system members (Blood..MusculoSkeletal) are `cpg_coefficient`/`linear` -- literally
   `intercept + sum(coef*beta)` with vendor-mean fill. `score_type()` now returns `"linear"` for
   them; `clock_coefs()` gained a one-line SystemsAge branch sourcing the column from `pack$organs`
   (PCClocks/PCBrainAge use `pack$coefficient_matrix`; SystemsAge's pack carries `$organs` +
   `$systems` + `$age`). This maximizes reuse of the tested engine (coverage, transform, reduction,
   impute) -- the alternative of routing all 13 through the orchestrator would re-implement
   `linear_score`'s vendor accounting 11 extra times for no gain. Rejected the earlier
   "hold the organ members back with the composite as one slice" framing: the members are
   independent (the composite recomputes its own raw system vectors), so each of the 13 dispatches
   on its own.

2. **The two composites (`Age_prediction`, `SystemsAge`) are one named branch,
   `score_systemsage()`.** They are not linear in the CpGs, so they get a family orchestrator (like
   GrimAge/FitAge/PhysAge), NOT a recipe walker. The branch hard-codes the pipeline *shape* --
   age-linear front -> quadratic; and for the composite: 11 raw system predictors + poly-scaled age
   -> center/scale -> systems_PCA project -> linear head -- and reads every *constant* from the
   catalog recipe via targeted accessors (`systemsage_step/_age_intercept/_poly/_raw_intercepts/
   _stack_order/_final_intercept`), never hand-copied into R source. Every linear stage reuses the
   shared `linear_predictor()` kernel via a small `sa_linpred()` (present cols + partial-cohort
   cache + vendor offset for absent).

3. **The systems_PCA tensor tree stays in the pack `$tensors`, consumed as-is.** `encode_systemsage`
   already leaves the four small tensors (center[12], scale[12], model[12], rotation[12x12]) in
   `$tensors` keyed by their `weights/` paths; `systemsage_pca()` resolves them by component name
   (from the catalog) and aligns rows/cols to the recipe stack order. Deliberately did **not** bump
   the pack encoding to promote them into named `$pca` fields: the accessor is small, the pack is
   already built/verified, and a re-encode would churn the payload_hash and re-staging for no
   scoring benefit. Column-order care: the pack `$organs`/`$systems` matrices are alphabetical while
   the systems_PCA order is the recipe stack order (Blood, Brain, **Inflammation, Heart**, ...,
   **Metabolic, Lung**, ..., Age_prediction) -- everything is indexed by name, never position.

4. **`Age_prediction` vs the composite's `ap_scaled` use different poly coefs, on purpose.** The
   standalone `Age_prediction` clock folds the author's `transformation_coefs` affine + /12 into its
   quadratic; the composite feeds the un-transformed age (just /12) into systems_PCA, so its
   `ap_scaled` poly differs. Both come straight from their own catalog recipe step, so the scorer
   never conflates them.

## 2026-07-21 -- external scoring landed for PCClocks + PCBrainAge (external.md steps 1-5); SystemsAge deferred

**Decision.** Wired external.md steps 1-5 for the two plain-linear external groups (PCClocks,
PCBrainAge): accessors read external coef/impute from the loaded pack, `load_mc_assets` is the
single loader, `calc_clocks()` resolves packs upfront and scores them on the shared linear engine.
SystemsAge (organ members and its component-matrices composite) stays `"unsupported"` -- its
orchestrator is its own later slice.

1. **`external_pack()` -> `load_mc_assets(groups, assets = NULL, ask = TRUE)`** (renamed, verb-named)
   in [`R/methylCIPHER_data.R`](../R/methylCIPHER_data.R). Returns a **named list of packs keyed by
   `group_id`** (even for one group), not a single pack. It is the sole consent/download/read site.
   The single-pack read/validate/drift-warn body is now the internal helper `mc_read_pack()`;
   `mc_download()` split into pure `mc_fetch()` (stage -> qs2-validate -> atomic rename, no prompt)
   plus `mc_consent()` (one **batched** prompt for the union of missing packs, refusing
   non-interactively). `mc_data_download()` reuses both.

2. **Closed-vs-open `assets`.** `assets = NULL` -> default cache dir, missing packs consent-downloaded
   (open set). `assets` **explicitly provided** -> **closed set, never downloads**, a coverage gap is
   fatal. `assets` accepts a cache-dir path **or** loaded object(s) -- a bare pack, a list of packs,
   or a path all canonicalize (via `mc_canonicalize_assets()`) to the named-list registry; objects
   key by their own `$group_id`. This reverses the old semantics where `assets` was only a cache-dir
   path that downloads landed into. Data-layer tests were rewritten to drive open-mode downloads via
   `options(methylCIPHER.cache_dir=)` and to cover the closed path/object modes.

3. **Accessors take the registry on the external path.** `clock_coefs(id, packs = NULL)` and
   `clock_impute_ref(id, packs = NULL)` gained an external branch: for an `external_group` clock they
   pull the coef column from `packs[[group_id]]$coefficient_matrix[, id]` (named by `$cpgs`) and the
   vendor ref from `$impute`, via the new `clock_pack()` helper (errors if the group's pack is not in
   the registry). The bundled path is unchanged; `packs` defaults to `NULL`, so every existing
   bundled caller (`linear_score`, `score_physage`, tests) is untouched. `linear_score()` gained
   `packs` and forwards it.

4. **Upfront resolution is gated on `score_type() != "unsupported"`, not merely "is external".**
   `calc_clocks()` collects the external groups whose clocks route to a pack-consuming scorer and
   calls `load_mc_assets()` once before the pure loop. `assets`/`ask` were added to the
   `calc_clocks()` signature.

5. **Dispatch flip (step 3), narrowly.** `score_type()` now routes external + `cpg_coefficient` /
   {`linear`,`linear_transformed`} -> `"linear"`, **except** the SystemsAge group, which stays
   `"unsupported"`. So PCClocks + PCBrainAge score (step 4 for them is pure fall-through to
   `linear_score`); SystemsAge's cpg_coefficient organ members are held back with the composite so
   the group is enabled as one orchestrated slice, and the gating in point 4 means SystemsAge never
   downloads-then-errors.

6. **Tests (step 5).** `test-score-external.R` drives `calc_clocks()` end-to-end on PCBrainAge with
   an **in-memory pack** (closed set -> no disk, no network): full-coverage golden, vendor-fill
   golden (absent CpGs from `$impute`), and the closed-set "pack absent" error. Real cohort parity
   is now **pack-gated** too: `skip_if_no_pack()` skips an external clock's parity unless its pack is
   cached, and open-mode `calc_clocks()` then reads the cached pack without a download prompt.

**Why hold SystemsAge back.** Its composite is `component_matrices`/`wrapper` (organs -> systems ->
age -> composite over the pack's `$organs`/`$systems`/`$age` matrices), a genuinely new branch;
enabling only its linear organ members would half-support the group and download-then-error on the
headline composite. It ships as one slice.

---

## 2026-07-21 -- external asset layer simplified: qs2 checksum is the integrity guard, payload_hash drift WARNs, no memoise

**Decision.** Rewrote [`R/methylCIPHER_data.R`](../R/methylCIPHER_data.R) from ~479 to ~230 lines.
The module now reads as one flow: resolve cache dir -> find expected file -> consent-gated download
if absent -> `qs2::qs_read(validate_checksum = TRUE)` -> WARN-only content-hash check -> return
pack. `external_pack(group_id, assets = NULL, ask = TRUE)` is the single runtime entry; see
detail-plan 9.4.

**What changed and why (reverses two earlier stances).**

1. **Transfer integrity is qs2's own `validate_checksum`, not a parallel `file_sha256` recompute.**
   This reverses the 2026-07-20 "kept, deliberately ... runtime download-integrity `file_sha256`"
   line. qs2 already stores and verifies a checksum on read; recomputing a separate sha256 over the
   file was redundant. `file_sha256` stays in `mc_provenance` as a maintainer-side record but is no
   longer read by R (candidate for later removal). The `.part`-stage -> qs2-validate -> atomic
   rename gives the same "a corrupt transfer never counts as cached" guarantee the old sha256 +
   staging dance did, in three lines.

2. **`payload_hash` mismatch WARNs, never errors.** The old `external_pack()` hard-errored on four
   structural identity fields (`group_id`/`encoding`/`encoding_version`/`n_cpgs`). Replaced by one
   `mc_payload_hash(pack)` vs provenance `payload_hash` compare that only `warning()`s. The filename
   already embeds `payload_hash`, so a name match is strong; the recompute is cheap belt-and-braces
   and a drift is a "your scores may not match this version" signal, not a reason to refuse to
   score. (`mc_payload_hash` mirrors sync's `payload_hash_of`; the saved object *is* the stripped
   stable payload, so the hashes line up with no re-derivation.)

3. **No memoise -- confirmed by benchmark, not assumed.** Cold `qs_read` of the three packs is
   ~0.10s (PCClocks 13.5 MB), ~0.13s (PCBrainAge 8.6 MB), ~0.20s (SystemsAge 30.7 MB), and
   `validate_checksum` is free within noise. So there is no session-cache/global-env tier and no
   `clear_clock_cache()`-clears-a-memo semantics; `calc_clocks()` loads each needed group's pack
   once per call and passes it down. This also retires the stale detail-plan 9.4 "session cache ->
   bundled -> R_user_dir -> download" order (external packs are never "bundled").

4. **`ask = TRUE` default, not `ask = interactive()`.** `interactive()` as the default silently
   auto-downloads in scripts/CI (evaluates to `FALSE` = "consent given"). `ask = TRUE` prompts when
   interactive, **refuses** non-interactively, and `ask = FALSE` is the explicit-consent signal --
   matching the "no download without consent" invariant.

**Cut as over-engineering** (the module treated our own compiled `mc_provenance` as a hostile wire
contract): `mc_validate_row` field-by-field validation, `mc_resolve_groups` multi-group ceremony,
`mc_cache_status` data.frame, `mc_release_repo` slug regex, `mc_chr1`/`mc_num1`, the elaborate
`mc_confirm`, and the separate sha256 verify + `.part-<pid>` machinery.

**Cache-dir model.** `assets` arg (per-call) > session option `methylCIPHER.cache_dir` (via
`mc_set_cache_dir()`, a session-consistent setter) > `METHYLCIPHER_CACHE_DIR` (.Renviron) >
`mc_default_cache_dir()` (`R_user_dir`).

**Kept.** `clear_clock_cache()` as a must-have **stub** -- it reports what is cached and never
auto-unlinks; the interactive delete flow is deferred by design. A thin `mc_data_download()`
pre-fetch verb for offline/CI staging.

**Sites.** `R/methylCIPHER_data.R` (rewrite); `tests/testthat/{test-methylCIPHER_data.R,
helper-external-data.R}`; `dev/detail-plan.md` 1.1, 9.1, 9.4. Full suite after: 0 failures (the 13
parity warnings are the pre-existing per-clock-subset orientation notice, unrelated).

## 2026-07-21 -- no roxygen yet; plain `#` comments are the only in-source docs pre-alpha

**Decision.** The package carries **no roxygen** during the rewrite. Do not author roxygen
blocks and do not run `devtools::document()`. In-source documentation is short `#` comments
only (the existing "Comments" rule: 1-2 sentences on *what*, not *why*).

**Why.** The API surface is still moving; regenerating `NAMESPACE` / `man/*.Rd` on every change
is churn with no reader yet, and half-written roxygen would rot against the code. `man/*.Rd` and
the live `NAMESPACE` remain the hand-managed pre-rewrite leftovers noted below until roxygen is
switched on.

**Trigger.** Turning roxygen on is a **human-decided override** tied to the alpha release --
there is **no** automatic condition (no version tag, no milestone gate). Claude must not enable
it on its own initiative.

**Supersedes.** The earlier CLAUDE.md guidance to "run `devtools::document()` after any
export/doc change" and to treat `NAMESPACE` / `man/*.Rd` as roxygen-generated. Those lines were
rewritten to the "No roxygen yet" invariant.

## 2026-07-21 -- maintainer handoff to Hung Pham; license is BSD-3 (not the anticipated GPL-2)

**Decision.** Two DESCRIPTION-level facts recorded now that they are set in package metadata.

1. **Authorship / maintainer.** Hung Pham (ORCID 0000-0002-8271-9355) is now `aut` + `cre`
   (maintainer). Kyra L. Thrush stays `aut` (prior author). Copyright holder stays the **Albert
   Higgins-Chen Lab, Yale University** (`cph`) -- Hung takes authorship / maintenance, not copyright.
   DESCRIPTION moves from the malformed plain-text `Author:` / `Maintainer:` pair (which held a
   literal `person(...)` string) to a proper `Authors@R` block, clearing that `checking DESCRIPTION
   meta-information` NOTE.

2. **License is `BSD_3_clause`, superseding the GPL-2 anticipation.** The 2026-07-17 third-party
   weights entry assumed a future GPL-2 finalization; the package instead ships `BSD_3_clause + file
   LICENSE` (LICENSE stub + LICENSE.md, copyright the Lab). **Caveat unchanged:** BSD-3 is more
   permissive than GPL-2 but does **not** dissolve the redistribution question for bundled
   third-party clock weights carrying NC / ND / research-only / unspecified terms. That
   pre-submission gate (chase grants, lean on the facts stance, or move to the external tier) still
   applies whatever license the package itself ships under; only the CRAN GPL-2-sublicensing framing
   from 2026-07-17 is moot.

**Sites.** `DESCRIPTION` (`Authors@R`, `License`); `LICENSE` / `LICENSE.md` (copyright unchanged).

---

## 2026-07-21 -- plan/code reconciliation: sync §9 lockfile story, dead `impute_DNAm.R` path

**Decision.** Documentation-only reconciliation of `dev/migration-plan.md` and `dev/detail-plan.md`
with what `data-raw/sync.R` actually does after the 2026-07-20 prune. No behavior change.

1. **`manifest_key` is gone from the plans.** The 2026-07-20 prune removed the catalog build-skip
   cache (`manifest_key` / `build_key` / `data-raw/lockfile.json`), but both plans still described it
   as current truth in six places (migration §Source-of-truth + §Packaging; detail §7, §9.1, §9.2,
   §14 diagram). Rewritten to the current reality: the full `sysdata.rda` rebuild is uncached (~2s),
   and the only remaining sync-side identity is the external packs' content-address `payload_hash`
   (filename / release tag / reupload skip) plus runtime `file_sha256` in `mc_provenance`.
2. **The lockfile survived, narrower.** The 2026-07-20 entry below overstated the removal: a
   gitignored `data-raw/assets/lockfile.rds` (+ `read/write_lockfile`, `lockfile_hit`, `sync(force=)`)
   remains, but its only job now is to skip **external qs2 pack rebuild** when the meta
   `source_git_sha` and the staged packs are unchanged -- not catalog-change detection. detail §9.1 /
   §9.2 now describe this instead of the old `manifest.json -> manifest_key -> no-op` flow.
3. **Dead path fixed.** The plans (and the 2026-07-18 entry below) referenced `R/impute_DNA.R`; the
   file is `R/impute_DNAm.R`. Corrected in detail §2.3a; the 2026-07-18 entry is left as-was
   (append-only).

**Why documentation-only.** The plans state current truth; these were plan<->code drifts left by the
2026-07-20 prune, not new design. DECISIONS stays append-only, so this entry records the drift rather
than silently rewriting history.

**Sites.** `dev/migration-plan.md` (Source of truth, Packaging); `dev/detail-plan.md` §7, §9.1, §9.2,
§9.5, §14, §2.3a.

---

## 2026-07-20 -- `data-raw/sync.R` pruned to two requirements: consume upstream, don't re-upload unchanged assets

**Decision.** Cut `data-raw/sync.R` from 2172 to ~1350 lines (~40%). The script's only jobs are (1)
pull the scoring contract + tensors from methylCIPHER-meta into `R/sysdata.rda` + `inst/` + the three
external qs2 packs, and (2) not re-upload an external pack whose stable weights didn't change.
Everything not serving those two was removed.

**Removed.** (a) The **build-skip cache** entirely -- `read/write_lockfile`, `manifest_key`,
`build_key`, `missing_outputs`, `data-raw/lockfile.json`, the `prior_assets` reuse path, and the
`force`/`dry_run` modes. The full build takes ~2s, so caching it bought nothing but cache-invalidation
edge cases (which `missing_outputs` existed to patch). (b) **Trust-upstream input validation** --
manifest field/dup checks, `papers.csv` uniqueness/column checks, `assert_repo_rel` path-escape
guards, `verification_status` threading, sha-format and post-checkout existence assertions. methylCIPHER-meta
owns provenance integrity; re-policing it here is redundant. (c) The `manifest_generated_at_sha`
parent-commit lag-stamp. (d) ~250 lines of rationale-essay comments -- the "why" lives here in
DECISIONS.md and `dev/*.md`.

**Kept, deliberately.** The scoring-correctness guards, because a silent failure there produces a
confident wrong number (the class of bug the whole design fights): `align_double`/`cbind_aligned`
alignment checks, the missing-tensor stop in `build_group_bundles`, `resolve_cpgs` probe-set-mismatch,
`materialize_probe_set`'s empty/duplicate-CpG stops, and `read_tensor_csv`'s duplicate-key stop. Also
kept the runtime **download-integrity `file_sha256`** in the shipped `mc_provenance` registry (protects
the consumer, not the maintainer) and the git subprocess error surfacing.

**Why no re-upload without the lockfile.** Idempotency was never the lockfile's job. The content-address
(`payload_hash` -> filename -> release tag) plus `gh_upload.py`'s remote skip (`get_release(tag)` +
"asset name already present") together guarantee it: unchanged weights -> same hash -> tag+asset already
on the release -> skipped. Upstream moving without touching the three external groups leaves their
hashes untouched (pin fields are stripped by `stable_external_payload`). Verified: a full `sync()`
rebuilds all outputs in ~2s and the three packs keep stable hashes across runs.

---

## 2026-07-20 -- external asset content-address hashes over a version-pinned serialization, not `rlang::hash`

**Decision.** `payload_hash_of()` in `data-raw/sync.R` now hashes `serialize(payload, connection =
NULL, version = 2L, xdr = TRUE)` with `digest::digest(algo = "sha256")`, replacing `rlang::hash(payload)`.
`EXTERNAL_ENCODING_VERSION` bumped 2 -> 3; `rlang` dropped from the sync `library()` preflight (it
was the only use). This is the content-address for the three external qs2 release assets (SystemsAge,
PCClocks, PCBrainAge) -- it sets the filename, the GitHub release tag, and the reuse/skip key.

**Why.** `rlang::hash()` hashes R's *serialization* of the object, so it inherits ALTREP compaction
and serialization-version drift: an R/rlang upgrade could flip the hash with **zero content change**
and force a spurious rehash + reupload of a blob that is meant to be frozen. `version = 2L` predates
ALTREP (the object is written fully expanded) and `xdr = TRUE` fixes endianness, so the byte stream
depends only on content. `rlang::hash` exposes no knob to pin its serialization, so it could not be
fixed in place. The new form also matches the `digest::digest(..., serialize = FALSE)` idiom already
used by `manifest_key()` and `build_key()` -- `rlang::hash` was the lone outlier.

**Why the one-time reupload is acceptable.** Switching the hash function is itself a genuine
content-address change: the three current blobs rehash once on the next `sync(upload = TRUE)`, then
never move again unless their group's own contents change. The package is private and pre-release, so
there are no pinned installs in the wild to strand, and old release tags are never deleted anyway.

**Scope note.** Only SystemsAge/PCClocks/PCBrainAge are content-addressed qs2 assets. Clocks added to
ship groups (GrimAge, Dunedin, ...) live in `mc_bundles` inside `R/sysdata.rda` and never touch these
hashes -- so in normal development the three external hashes are effectively constants, which is
exactly why removing the R-version drift vector matters.

---

## 2026-07-20 -- dependency clocks are returned as columns (reverses "compute-only intermediates"); `sim_DNAm` mirrors the compute plan; a prepare-time coverage floor

**Decision.** Three coupled changes, all traceable to one bug: `calc_clocks(sim_DNAm("DNAmFitAge"),
"DNAmFitAge")` returned a confident, meaningless number.

1. **Auto-added dependency clocks are RETURNED as score columns.** This **reverses** the
   2026-07-17 rule that they are compute-only intermediates. `calc_clocks()` assembles
   `results[output_ids]` where `output_ids = c(clock_ids, setdiff(clock_sequence, clock_ids))` —
   requested first in request order, deps after in compute order — and
   `$provenance$requested` / `$dependencies` partition `$provenance$clocks`.
2. **`sim_DNAm()` resolves through `resolve_clocks_sequence(resolve_clocks(clocks))`**, not
   `resolve_clocks()` alone.
3. **A coverage floor at prepare time.** `warn_low_coverage(cpg_list, min_coverage = 0.8)` in
   `R/resolve_inputs.R`, called from `calc_clocks()` right after `resolve_cpgs()`.

**The bug that forced all three.** `sim_DNAm` resolved namespace only, so `"DNAmFitAge"` produced
the group's 627 CpGs while the compute plan needs 1643 — the 1016 missing belong to `GrimAgeV1` and
its 8 surrogates, pulled in as cross-group deps. Those surrogates are `imputation_policy = omit`, so
at 0 present CpGs they collapse to intercept-only, `GrimAgeV1` is built on them, and `DNAmFitAge`'s
KDM `DNAmGrimAge` term becomes a constant. It did not error. It returned 37–67 where the correct
panel gives 90–127. Three independent layers were each silent, hence three fixes.

**Why return deps rather than propagate their coverage into the composite's row.** The considered
alternative was to keep deps hidden and fold their coverage into `DNAmFitAge`'s tier-1 row (or add a
`dep_coverage` field). Returning the columns is strictly better: the deps *were* computed, each
already carries its own complete coverage row, and stacking them costs nothing. Folding would also
make `score_needed` stop matching the clock's own panel. Consequence: `score_fitage_composite()` and
`score_grimage()` need no change at all — the transparency problem was in assembly, not in them.

**Why not keep deps hidden for a stable column set.** That was the original argument, and it loses
to the failure above: `calc_clocks(x, "DNAmFitAge")` returning 16 columns is surprising once; a
composite silently resting on a collapsed input is dangerous every time. Callers who want a fixed
set subset downstream, which is cheap and explicit. Note the column set was never truly stable
anyway — it already varied with group-vs-clock token expansion.

**Why the floor warns instead of erroring.** A partial panel is often legitimate: `vendor_mean`
clocks fill, `omit` clocks degrade smoothly, and a user may knowingly score a 27k array. Silence is
what is indefensible. 0.8 is a judgment call, not a derived threshold — hence `min_coverage` is an
argument, with `0` to silence.

**Why the floor runs over the plan, not the request.** That is the whole point: the collapsed clock
was `GrimAgeV1`, which nobody requested. Over the request alone the motivating bug stays invisible.

**Why it is not inside `resolve_cpgs()`.** `resolve_cpgs()` is pure set math over the catalog (no
numerics, no `pheno`, no side effects) — 2026-07-18 established that purity, and scope creep into it
was already flagged once as a tell. The floor is a separate consumer of the skeleton it returns.

**Why the floor is sample-invariant only.** It reads `score_present / score_needed`, so it catches
panel/array mismatch, never per-sample NA concentration. The per-sample analogue (a threshold read
off the tier-2 `n × k` matrix, §4.2) is deliberately **left unbuilt** — record-and-report stays the
default there, and no per-sample gate ships until there is a concrete case for one.

**Sites.** `R/sim_DNAm.R` (`clock_cpgs` call site), `R/calc_clocks.R` (`output_ids`,
`min_coverage` arg, `construct_methylCIPHER(requested_ids)` + provenance fields),
`R/resolve_inputs.R` (`warn_low_coverage`). Plan text: detail-plan §1.3, §2.1, §4.1, §7, §10.1.

---

## 2026-07-18 -- partial-NA is a shared cohort cache; all-NA columns reclassify absent; empty rows throw; coverage gains a per-sample tier

**Decision.** Four coupled rules for the missingness front end, settling how partial-NA (cohort)
imputation is organized and how degenerate inputs are handled. Numeric machinery in
`R/impute_DNA.R` (`scan_missing_cpgs`, `build_partial_cache`); pure set math in `R/resolve_inputs.R`
(`resolve_cpgs`). Order in `calc_clocks()`: `scan_missing_cpgs → resolve_cpgs → build_partial_cache`.

1. **Partial-NA fill is a shared, precomputed cache — not per-scorer.** Component families reuse the
   same CpGs, so per-clock cohort-mean imputation would recompute the identical column mean once per
   clock. Build it **once** over `intersect(present_needed_union, partial_na_cols)` via
   `slideimp::mean_imp_col(DNAm[, cache_cpgs])`; every scorer reads the same filled column. This is
   also a **consistency** guarantee (shared CpG ⇒ identical imputed value across clocks), not only
   speed. Subset-columns-first is load-bearing: `mean_imp_col` returns an input-width matrix, so
   running it on the full panel allocates a second `n × p` copy (the §3 spike); narrowing bounds the
   cache to the partial-NA needed probes (empty when clean).
2. **All-NA present column → reclassify ABSENT.** Zero observed values ⇒ no cohort mean exists ⇒
   informationally identical to a probe off the panel. Removed from `usable_cols` via `setdiff` (a
   name-set op, **not** a `DNAm[, keep]` copy) so it routes to the vendor/drop path and is counted in
   `n_cpg_score_miss`. `mean_imp_col`'s own "0 observed → unchanged" branch therefore never fires in
   our path.
3. **Empty sample (all-NA row) → HARD ERROR (no permissive dial).** The reason it is an error, not a
   warning: cohort-mean imputation would otherwise fill its every cached cell with the column mean and
   emit a plausible-looking **fabricated** score instead of an honest `NA`. (An all-NA row is
   `isnan`-skipped in every column mean, so it does not bias others — the damage is its own fake
   score, but that suffices to refuse it.) Unlike rowname-less DNAm (§5.1 `allow_positional_ids`),
   there is no opt-in; empty rows are always fatal.
4. **Coverage gains a tier-2 per-sample matrix.** Tier 1 (`summary()`) stays the per-clock aggregate;
   tier 2 is an `n × k` per-clock × per-sample missingness matrix (`sample_coverage(x)`) for a QC
   heatmap. Motivation: a sample fine *globally* can be ~100% missing *for one clock* if its gaps
   concentrate in that clock's set — and that is **recorded, never thrown**. Each scorer emits a
   length-`n` row-wise NA count over its own present scoring CpGs, computed on the **raw** subset
   before the cache fills it (post-fill reads ~0). It is the row-wise decomposition of tier 1's
   `score_imputed_partial`, so no new mechanism.

**Gate cascade (both cache and tier 2).** Global `anyNA(DNAm)` is the monotone loose upper bound —
clean betas skip everything. Per clock, `intersect(score_present, partial_na_cols)` is a **free** set
op reusing the single prepare-side `mat_miss(col = TRUE)` result; a local `anyNA(subset)` gate is
rejected — on a clean subset it full-scans (nothing to short-circuit on), costing the same as
`mat_miss` while telling you less. `mat_miss(col = FALSE)` then runs only over a clock's NA-bearing
columns.

**Boundary (why `resolve_cpgs` stays pure).** `resolve_cpgs` does **no** numerics and takes **no**
`pheno` (an earlier draft signature `resolve_cpgs(DNAm, pheno, clock_ids)` was the scope-creep tell —
`pheno` is only needed by sex-keyed *vendor* fill, which is per-clock and downstream). It maps
`usable_cols` + the compute plan to the per-clock present/absent skeleton + `present_needed_union`.
Partial (cohort, shared cache) and absent (vendor, per-clock, needs `Female`) stay two separate
inputs to one gather; they are never merged upstream (the §2.3 never-cross invariant).

**Rejected.** (a) Per-clock partial-NA fill (recomputes shared column means; loses the cross-clock
consistency guarantee). (b) A union submatrix / full-panel `mean_imp_col` (the §3 memory spike; the
bounded cache is a narrow, evidenced exception to §3's blanket "no union submatrix" and §12's "no
copy-opt before evidence" — the evidence is shared component CpGs, and it is empty in the clean
case). (c) Warning (not error) on empty rows (lets imputation fabricate a cohort-average score). (d)
Baking absent counts into the tier-2 vector (absent is sample-invariant — keep it as tier 1's scalar,
combine at render).

**Sites.** `R/impute_DNA.R` (`scan_missing_cpgs`, `build_partial_cache`), `R/resolve_inputs.R`
(`resolve_cpgs`), `R/calc_clocks.R` (wiring), `R/score.R` (scorer emits tier-2 vector; consumes
cache), `dev/detail-plan.md` §2.3a, §4.1/§4.2. Uses `slideimp::{mat_miss, mean_imp_col}` (already in
Imports).

---

## 2026-07-17 -- clock resolution: maximal group expansion + a `resolve_clocks_sequence` dep topo-plan

**Decision.** Two settled rules for turning user tokens into a compute worklist, both in
`R/resolve_inputs.R`:

1. **`resolve_clocks()` — maximal expansion on a name clash.** A token resolves by fixed
   precedence, MOST clock ids first: `"all"` -> every clock; a `group_id` -> all members; a bare
   `clock_id` -> itself. When a token is **both** a `group_id` and a `clock_id` (e.g. `"DNAmFitAge"`
   names both the 7-member group and one composite member), the **group wins** -- a group request
   returns as many member ids as possible. One rule covers every shape: a group_id that is no
   clock_id (`GrimAge`, `SystemsAge`, `PCClocks`), a group_id that is also a member id
   (`DNAmFitAge`), and a singleton group (`group_id == its sole clock_id`, e.g. `MiAge`); the last
   two coincide at one member. This was previously an *accident* of `c()` ordering + `[`
   first-match; now it is explicit (`resolve_one()` checks group before clock) and documented.
2. **`resolve_clocks_sequence()` — the dependency plan step.** This settles the "orchestrator
   nesting vs. a resolve/plan step that topo-sorts on `depends_on_clocks`" question that
   detail-plan §2.1 left open: it is a **topo-sort plan step**. It takes `resolve_clocks()` output
   and returns the **transitive closure** over `depends_on_clocks` (read via the new
   `clock_depends_on()` accessor), topologically ordered so every clock comes AFTER its deps, with a
   cycle guard. Only 3 clocks declare any dep (`GrimAgeV1`, `GrimAgeV2`, `DNAmFitAge`), so like the
   covariate union, deps are pulled in **on demand** -- `SystemsAge` and its organ/system members
   declare none and pass through unchanged.

**Coupled fix.** Auto-added deps (in the plan, not in the requested set) are compute-only
intermediates; the caller returns score columns for the requested set only. Because a dep can need
a covariate the request does not, `calc_clocks()`'s covariate union (and the `check_DNAm_extra`
worklist) now run over the **plan**, not the raw `clock_ids`: the single `DNAmFitAge` clock declares
only `Female`, but its `GrimAgeV1` / `DNAmVO2max` deps also need `Age`. (In current data this is a
robustness fix -- the `"DNAmFitAge"` *token* resolves to the group, which already includes an
Age-needing member -- but it is reachable for the single clock id and if the catalog shifts.)

**Why.** `resolve_clocks` stays a pure token->id map; dependency logic lives in one named plan step
rather than smeared into each pack orchestrator, mirroring how the covariate union is computed once
over the worklist. Maximal expansion is the least-surprising reading of a group name and is what the
code already did.

**Rejected.** (a) Clock-beats-group (minimal expansion) on a clash -- makes `DNAmFitAge` return one
column when the user named the group. (b) Pure reorder without auto-adding missing deps -- leaves
`resolve_clocks_sequence` unable to actually satisfy a `DNAmFitAge`-only request. (c) Handling deps
inside the GrimAge/FitAge orchestrators only -- keeps the covariate-union coupling invisible and
duplicates topo logic per pack.

**Sites.** `R/resolve_inputs.R` (`resolve_clocks`, `resolve_clocks_sequence`), `R/accessors.R`
(`clock_depends_on`), `R/calc_clocks.R` (plan step + union over plan), `dev/detail-plan.md` §2.1.

---

## 2026-07-17 -- rowname-less DNAm: positional ids, refuse at cbind (not a front-door error)

**Decision.** `rownames(DNAm)` is no longer a hard requirement at the front door. `calc_clocks()`
handles identity **inline** before `check_DNAm`: when rownames are absent it stamps positional ids
`sample1..sampleN` (gated on `allow_positional_ids`). Such a call is flagged
`$provenance$positional_ids = TRUE`, and `cbind.methylCIPHER` gains a **gate 0** that throws on any
positional record. `check_DNAm` keeps `null.ok = FALSE` (an unconditional invariant, since ids exist
by the time it runs). `calc_clocks(..., allow_positional_ids = FALSE)` restores the strict
hard-error behavior. (Stamping is silent -- no warning; the `cbind` gate 0 is the guard.)

**Why.** The prior contract hard-errored on rowname-less DNAm to prevent a `cbind` footgun (two
matrices with `seq_len` ids binding as if the same samples). But that put maximal defensiveness at
the front door, which some workflows don't want -- they legitimately score by row order and never
`cbind`. The footgun only bites at the *bind* step, so guard it *there*: manufacture ids at the
boundary (keeping the "unique id everywhere" invariant every downstream consumer, incl. `cbind`,
relies on), warn, and quarantine positional records from `cbind` rather than corrupting it. Real
rownames remain preferred and are what enable binding + `Reduce(cbind, ...)`.

**pheno alignment follows the mode** (`resolve_pheno()`). When DNAm has real rownames, pheno is
**id-joined**: `rownames(DNAm) ⊆ pheno[[pheno_id]]` (superset ok, subset + reorder). When DNAm is
positional, there is no id to match on, so pheno is **row-order joined**: `pheno_id` ignored,
`nrow(pheno)` must equal `nrow(DNAm)` **exactly** (taller = ambiguous, shorter = short), row *i* is
sample *i*. This is the only way covariate-needing clocks can pair Age/Female to rowname-less
samples. Both modes keep the record scores-only; the aligned pheno feeds scorers, it is not
appended.

**Rejected.** (a) Flipping `check_DNAm`'s `null.ok = TRUE` and letting a positional `sample_id`
flow unlabeled -- reopens the silent-bind footgun and leaks positional semantics into
provenance/cbind. (b) Row-order join with a **superset** pheno (`nrow(pheno) >= nrow(DNAm)`) -- in
positional mode a taller pheno gives no way to know which rows are the samples, so require exact
equality. (c) Auto-appending pheno onto the scores (`cbind(scores, pheno)`) -- the record stays
scores-only regardless of mode; joining is `augment()`'s / `as.data.frame()`'s job.

**Sites.** `R/calc_clocks.R` (`allow_positional_ids` arg + inline positional-id stamping),
`R/resolve_inputs.R` (`resolve_pheno`, `check_DNAm` / `check_pheno`), `R/generics.R` (identity
contract + cbind gate 0), `dev/detail-plan.md` §1.3/§5.1/§7/§7.1, `dev/migration-plan.md`
(Public API).

---

## 2026-07-17 -- drop `covers` / `shared` from the shipped catalog (runtime-catalog trim)

**Decision.** `covers` and `shared` are no longer shipped on `mc_catalog` entries. They stay in
`FIELD_REGISTRY` (so the build-time resolver can still read them), then a new
`CATALOG_BUILD_ONLY_FIELDS` strip in `build_sysdata()` removes them from every clock entry
immediately after `resolve_group_scoring_probe_sets()`.

**Why.** Both duplicate `mc_groups`, and are dead weight at runtime: `covers` (composite
membership) mirrors `mc_groups$members` and is only ever consumed by the build-time CpG resolver
(`resolve_scoring_cpgs()` tier 5); once `probe_sets[role=scoring]` is materialized nothing reads
it again. `shared` (clock-level shared-tensor name list) mirrors `mc_groups$shared_tensors` and
is redundant with `imputation$ref` + the group bundle -- it was write-only (pruned in, never read
by sync's logic). Removing them sharpens the invariant "an `mc_catalog` entry is one clock's
runtime scoring contract" and drops two drift-prone copies of group facts. (~662 -> ~647 KB.)

**Ordering (load-bearing).** The strip runs *after* resolution, not by dropping the fields from
`FIELD_REGISTRY`: `resolve_scoring_cpgs()` reads `entry$covers` from the *pruned* catalog entry,
so deleting it pre-resolution would silently empty composite scoring sets (GrimAgeV1's 1030-CpG
union resolves through its `covers` list). Verified post-rebuild: GrimAgeV1 still resolves 1030
scoring CpGs with `covers`/`shared` absent from all 113 entries.

**Kept.** `components` and `recipe` stay -- they are the pack scorers' runtime instruction set,
not group duplication. Membership at runtime comes from `mc_groups$members`, never a resurrected
`covers`. Added `clock_covariate_coefs()` so the just-confirmed uniform `$covariates` coef map is
read through the accessor layer.

**Sites.** `data-raw/sync.R` (`CATALOG_BUILD_ONLY_FIELDS`, `build_sysdata`); `R/accessors.R`
(`clock_covariate_coefs`, `clock_coefs` now routes on `weights_format`).

---

## 2026-07-17 -- GrimAge V1/V2: do not symmetrize upstream; components emit V2 precision

**Decision.** Leave `weights/GrimAge/v1` and `v2` as-is upstream. Do **not** restructure
GrimAgeV1 to carry an inline component set mirroring V2. The GrimAge pack orchestrator
(`score_grimage`) absorbs the version asymmetry.

**Why.** The asymmetry encodes a real published difference, not a modeling accident: V1's 8
surrogates *are* the exposed standalone component clocks (DNAmADM, DNAmB2M, ...), so V1 reuses
them via `depends_on_clocks` with no duplication; V2's 8 surrogates differ by ~1e-4 to 1e-9,
were never published as standalone clocks, and so live as private `v2/_internal` components.
Forcing symmetry would either duplicate the published surrogate coefficients into GrimAgeV1's
meta (a one-writer violation) or mint ~1e-4-apart near-duplicate clock_ids that pollute
`list_clocks()`. Downstream gains nothing: `score_grimage` is a hand-written orchestrator
(detail-plan sec 2.5), explicitly not a generic recipe path, so it reads V1's `depends_on_clocks`
and V2's `components` and does the right thing per version.

**Component columns come from the V2 path** (detail-plan sec 2.5): when a user requests the
component id `DNAmADM`, the pack emits the V2-precision value from `v2/_internal/DNAmADM`; the
standalone V1-precision `DNAmADM` clock_id stays available by explicit name. The `_internal`
tensors do not become addressable clock_ids.

**Rejected.** (a) Inline components on V1 for uniformity -- duplicates published coefs. (b)
Expose V2 `_internal` surrogates as clock_ids -- near-duplicate namespace pollution. If the
`component_matrices` format doing double duty (surrogate-by-ref vs surrogate-by-inline-component)
ever bothers a schema consumer, that is a `weights_extraction.md` doc clarification upstream, not
a data restructure.

**Sites.** Upstream `weights/GrimAge/` (unchanged); future `score_grimage` in `R/`.

---

## 2026-07-17 -- sync identity keys no longer bleed into shipped `sysdata` (F1/F2)

**Decision.** Enforce sec 9.1 literally -- the sync-internal identity keys live **only** in
`data-raw/lockfile.json`, never in `R/sysdata.rda`:

- **F1.** `bundle_hash` and `out_sha256` are no longer written onto `mc_catalog` entries
  ([sync.R](../data-raw/sync.R) `build_catalog`). They were write-only (no reader in `R/`, in the
  accessors, or in sync itself -- `manifest_key()` reads `man$clocks` directly) and were leaking
  into the external `payload_hash` via `bundle$catalog`, so a manifest-only hash change could
  re-mint a release with identical scoring content. The upstream-freshness reasoning is kept as a
  comment; the values are not recomputed or stored.
- **F2.** `manifest_key` is no longer put in `mc_provenance`, and `catalog$manifest_key` is no
  longer set. It reaches the lockfile via `mkey -> write_lockfile()` as before. `source_git_sha`
  and `manifest_generated_at_sha` **stay** in `mc_provenance` as honest build provenance (only
  written on rebuild, so they accurately name the bytes -- not covered by the lockfile-only
  clause). The `external_assets` registry stays too (runtime download integrity, sec 9.4).

Also completes the `verification_status` code follow-up flagged in the reconciliation entry
below: it is dropped from both `mc_index` and `mc_catalog` (validated maintainer-side only).

**Why.** These fields answered exactly one question -- "has the catalog changed since last
sync?" -- which is the lockfile's job. Shipping them in `sysdata` contradicted sec 9.1, bloated
the catalog, and coupled the content-addressed release hash to manifest bookkeeping.

**Rejected.** Rewording sec 9.1 to bless identity keys in `sysdata`. Nothing consumes them there,
so removal is strictly cleaner than relaxing the rule.

**Sites.** `data-raw/sync.R` (`build_catalog`, `build_sysdata` `mc_provenance`, `sync`);
`dev/detail-plan.md` sec 9.1. A future `names(mc_index)` structural test must match the trimmed
schema (no `verification_status`).

---

## 2026-07-17 -- third-party weight licenses: audit + CRAN-vs-GitHub contingency

**Context.** A GPL-2 CRAN package that **bundles** third-party clock coefficients may only
redistribute weights whose own license permits GPL-2 sublicensing. CRAN additionally rejects
non-commercial, no-derivatives, research-use-only, and unlicensed ("all rights reserved")
content outright. Audited `weights/**/*.meta.json`'s `license` field (already kept via sync's
`FIELD_REGISTRY`, so this is queryable from the catalog).

**Findings.**

- **Clean (GPL-2-redistributable / CRAN-OK):** MIT (CellPopAge, Knight, PCBrainAge); GPL-2(+)
  (Bohlin96/251, DunedinPoAm38); GPL-3 (StocClocks P/H/Z); GPL-3 / CC-BY-4.0 (EpiTOC2,
  HypoClock); CC BY (Horvath1, RepliTali(Norm), RetroAge 450K/EPICv2); `open-redistributable`
  (HRSInChPhenoAge, all PCClocks, all SystemsAge, all SenescenceAge).
- **Blocked / unclear (NOT clearly redistributable; CRAN blockers):**
  - `non-commercial`: IntrinClock 370/380, the entire **PhysAge** family (DNAmCRP, DNAmHbA1c,
    DNAmDHEAS, DNAmHDL, DNAmPeakflow, DNAmPhysAge(_years), DNAmWHR, DNAmPulsePr,
    DNAmCystatinC_PhysAge).
  - `CC BY-NC-ND 4.0`: Mayne (NC **and** ND).
  - `research-use-only`: DunedinPACE.
  - `unspecified`: entire **GrimAge** family (all DNAm* components + GrimAgeV1/V2), MiAge.
  - `public-github-unspecified` (= no grant = default all-rights-reserved): DNAmFitAge family,
    CellDRIFT, DNAmClockCortical, Zhang2019, PedBE.
  - `journal-supp` (published as supplementary; license usually unstated): Hannum, PhenoAge,
    Horvath2, Lin, Weidner, McCartney family, Lee* placental, EpiTOC, DNAmTL, DNAmStress,
    VidalBralo, ZhangMortality, DNAmFI_Li, DNAmIC, CausalityAge (Caus/Dam/Adapt).

**Reasoning.** The technical "can't ship blobs needing rev-eng" concern (DunedinPACE's historic
obfuscation) is **orthogonal** to license: even plaintext, freely downloadable coefficients can
carry NC/ND/unspecified terms that forbid GPL-2 redistribution. A counter-argument -- raw
regression coefficients may be uncopyrightable facts (Feist), making the labels unenforceable on
the numbers -- exists but CRAN will not adjudicate it; a clean grant is required regardless.
Moving to a GitHub release **sidesteps CRAN policy** but does not by itself cure the underlying
redistribution grant (it leans on the facts argument + academic precedent, e.g. the current
methylCIPHER already redistributes many of these).

**Decision (contingency, not yet locked).** Treat license as a **pre-submission gate**: before
any CRAN attempt, resolve each non-clean clock -- chase the author for an explicit grant, rely on
the facts stance, or move it to the external / user-fetched tier -- so the CRAN-bundled set is
clean-only. If that leaves too little to be worth CRAN, ship the whole package as a **GitHub
release** instead (accepted fallback). License compatibility, not the stale `DESCRIPTION` string,
is the real CRAN risk.

**Sites.** `data-raw/methylCIPHER-meta/weights/**/*.meta.json` (`license`); `dev/detail-plan.md`
sec 9.3 / sec 10.2 (packaging + CRAN checklist); `DESCRIPTION` (License, when finalized to GPL-2).

---

## 2026-07-17 -- plan/code reconciliation: bibliography input, verification_status is dev-only, sim_DNAm smoke, self-contained `%||%`

**Decision.** Four corrections aligning the plans (and one code hygiene fix) with what
`data-raw/sync.R` and `R/sim_DNAm.R` actually do:

1. **Sync inputs include `bibliography/`.** The "inputs R may read" contract now lists
   `bibliography/{papers.csv,clocks.bib}` alongside `manifest.json` + `weights/**`. Sync joins
   `pmid -> bib_key` from `papers.csv` in memory and vendors `clocks.bib` to `inst/`; `papers.csv`
   is never shipped. (`control/`, `papers/`, `scripts/` remain unread.)
2. **`verification_status` is a maintainer/dev signal, not user surface.** It records why a clock
   is deliberately `skipped` (e.g. Horvath online variants) for the human running sync. It is
   **not** exposed by `list_clocks` and should not be canonicalized into `mc_index` / `mc_catalog`
   -- it stays on the maintainer side (manifest / lockfile). Sync still validates the value at
   build time. **Code follow-up (not yet done):** drop `verification_status` from `build_index`
   ([sync.R:1366](../data-raw/sync.R)) and the `mc_catalog` entry ([sync.R:766](../data-raw/sync.R));
   nothing in `R/` consumes it, and it needs a re-sync to take effect.
3. **`sim_DNAm` smoke tier documented.** The always-run test tier now names the shipped
   `sim_DNAm()` `expect_no_error` machinery check over every bundled clock (random uniforms on the
   catalog's scoring probe sets; no cohort, no golden, no drift). Distinct from the hand-authored
   engine-arithmetic units and from the cohort-gated parity gold.
4. **Self-contained `%||%` in sync.** Restored the small `%||%` helper (was commented out, leaving
   the script silently dependent on base R >= 4.4 shipping its own). Audited all ~55 call sites:
   every LHS is freshly built or from `fromJSON(simplifyVector = FALSE)` (NULL, never scalar NA),
   so base's null-only `%||%` and the restored NA-aware one are behaviourally identical on shipped
   output; the restore only removes the hidden version dependency.

**Why.** These were plan<->code drifts I would rather kill than annotate -- the plans state current
truth only. None reverse a design; they correct descriptions that had fallen behind the
implementation.

**Sites.** `dev/migration-plan.md` (Source of truth, Testing); `dev/detail-plan.md` sec 5, sec 8,
sec 9.5, sec 10.1; `data-raw/sync.R` (`%||%`; `build_index`/`build_catalog` follow-up);
`R/sim_DNAm.R`.

---

## 2026-07-17 -- runtime is `linear_score` + a finite branch set (walker fully dropped)

**Decision.** No recipe interpreter, not even as a reference/fallback. Runtime is one shared
`linear_score()` plus a small, closed set of branches dispatched on the catalog pair
`(weights_format, computation_type)`: linear, linear + pre-transform (Zhang `sample_scale`),
sex-split, family orchestrators (GrimAge, SystemsAge), `external_package`, `custom` (MiAge).

**Rejected.** Keeping a "14-verb recipe walker as reference/fallback for remaining
`component_matrices` clocks" (the language that lived in detail-plan sec 2.2 / sec 11). It was
Schrodinger's deliverable -- simultaneously rejected and planned -- and a third scoring path
that would have to agree with the engine and the packs on every fixture.

**Why.** Every remaining clock resolves to either the linear engine or a named pack. A walker
buys a third code path and more fixture surface for zero clocks it alone can score.

**Sites.** `dev/migration-plan.md` (Runtime), `dev/detail-plan.md` sec 2.2, sec 11. Extends
the 2026-07-15 "engines + packs" entry (which already rejected the walker *as the only
runtime*); this removes it entirely.

---

## 2026-07-17 -- result object inherits `list`, not `matrix`

**Decision.** `calc_clocks()` returns an S3 record over `list`, class `"methylCIPHER"`:
`list(scores = <n x k double>, coverage = <per-column>, provenance = <clocks, covariates_used,
batch_set_id>)`. Verbs are methods: `as.matrix` (naked scores / escape hatch), `as.data.frame`,
`[` (subsets scores **and** the matching coverage/provenance), `cbind` (binds columns, checks
`batch_set_id`), `augment` (imported from the `generics` generic, not a home-grown one),
`statistics`, `codebook`, `citation`, `print`.

**Rejected.** `class = c("methylCIPHER", "matrix")` carrying coverage/provenance in attributes.
Base R drops class and attributes on the first `x[, "Horvath"]`, `t()`, or arithmetic, so a
user's first subset silently discards provenance. A bare matrix subclass with load-bearing
attrs is a known R foot-gun.

**Sites.** `dev/detail-plan.md` sec 1.3, sec 4, sec 7.

---

## 2026-07-17 -- imputation source split: partial = cohort, absent = vendor; never cross

**Decision.** Two missing-kinds, two sources, non-interchangeable:

- **Partial NA** (probe present in `DNAm`, `NA` in some samples): impute from the **current
  cohort** (mean over observed samples for that probe). Cohort-dependent by definition -- that
  is what imputation is -- and it is a **fallback**: the contract is that users pre-handle their
  NAs; we only avoid crashing.
- **Completely absent** (probe not in `DNAm` at all): no cohort data exists to borrow, so fill
  from the **vendored** ref the clock specifies (mean / median / sex-wise) or drop per policy.

Crossing them is the bug: vendored-filling a partial-NA injects a foreign cohort's data into the
user's samples; cohort-filling a fully-absent probe is impossible.

**Rejected.** An earlier framing that partial-NA should use the vendor ref "to stay
batch-independent." Batch-independence is not a goal here -- imputation borrows within-cohort
information on purpose. `mean` is merely the current fallback statistic, not a fixed rule.

**Sites.** `dev/detail-plan.md` sec 2.3, sec 4 (coverage splits cohort-borrowed
`score_imputed_partial` from vendor-borrowed `score_imputed_full`), sec 6.

---

## 2026-07-17 -- no SHA / pin provenance in the R package (correctness gated by fixtures)

**Decision.** The package carries **no** commit pin as product identity. `manifest_key` /
`bundle_hash` / `out_sha256` in `data-raw/sync.R` are **sync-internal skip keys only** (answer
"has the catalog changed since last sync?") and never reach `mc_provenance` or a result attr.
Result provenance is: clock ids scored, covariates actually used, coverage, and batch-set id
when applicable. Correctness is proven by **fixtures**, not by a pin.

**Rejected.** Stamping results with the resolved checkout SHA (former detail-plan sec 7 / sec
9.1). Because a no-op sync (`manifest_key` unchanged) leaves `sysdata.rda` lagging the checkout,
a SHA stamp could disagree with the data actually bundled -- provenance that can lie. Dropped
rather than patched.

**Sites.** `dev/detail-plan.md` sec 7, sec 9; `dev/migration-plan.md` (Source of truth,
Packaging).

---

## 2026-07-17 -- fixtures: always-run engine units + cohort-gated parity (no shipped golden)

**Decision.** Two test tiers doing **different jobs**:

- **Engine / machinery unit tests -- always run, no meta dependency.** Hand-authored toy inputs
  (a few probes x a few samples, coefficients chosen so the expected dot product is written by
  hand in the test). They verify `linear_score` arithmetic, impute accounting, accessors,
  coverage math, and result-class methods. Golden values tie to nothing upstream -> zero drift.
- **Parity fixtures -- the single clock-golden source, cohort-gated.** The upstream golden
  fixtures vs `fixtures/cohort_EPIC/beta.duckdb`, skipped via `file.exists()` when the cohort is
  not staged under `data-raw/methylCIPHER-meta`. CI may stage/regenerate the cohort and run the
  full gate; CRAN skips it.

**Rejected.** Committing a small slice of the real cohort's golden values into `tests/` to make
parity run on CRAN. That is a second copy of upstream golden values -> it drifts. A 5-sample
slice also cannot validate a `correlation`-policy clock anyway; only `exact` policy is reliable
at small n, and those do not need a bespoke shipped fixture once engine units cover the wiring.

**Sites.** `dev/detail-plan.md` sec 10.

---

## 2026-07-17 -- sysdata schema lives in accessors + a structural test, not a schema.md

**Decision.** No hand-written `schema.md`. The sysdata shape is defined by `build_index()` /
`build_catalog()` in `data-raw/sync.R`, and the **accessor layer is the executable schema**:
`get_clock()`, `clock_scoring_cpgs()`, `clock_norm_cpgs()`, `clock_impute()`, `clock_coefs()`,
`clock_group_bundle()`. Their `#` comments state the fields/types (roxygen deferred to alpha, per
the 2026-07-21 entry); a `testthat` test asserts `names(mc_index)` and a sample `mc_catalog`
entry's structure, so a shape change breaks a test and forces the comment update. `calc_clocks` code consumes only accessors -- never raw
`entry$components[[i]]$file`. Covariate requirements are one flattened catalog field
(`covariates_required`, computed by sync's `extract_covariates`), read once at runtime, never
re-derived from three meta keys in the scoring path.

**Rejected.** A prose `schema.md` for future agents -- the exact prose<->code drift class the
meta repo's `meta_schema.py` exists to eliminate. If a browsable schema is ever wanted, generate
it from the objects; do not hand-maintain it.

**Sites.** `dev/detail-plan.md` sec 5, sec 8; `data-raw/sync.R` (`build_index`,
`extract_covariates`).

---

## 2026-07-15 -- engines + packs (not pure recipe VM; not 113 calc*)

**Decision.** Runtime is a shared **linear engine**, small **pre-transforms** (e.g. Zhang
`sample_scale` via full-panel moments then coef subset), and a few **family orchestrators**
(GrimAge, SystemsAge), plus external/custom one-offs. Public scorer is `calc_clocks`.
Meta/fixtures remain the scientific contract; orchestrators are optimized implementations.

**Rejected.** (1) Pure “one recipe interpreter walks all 113 clocks” as the only runtime.
(2) Restoring per-clock unexported `calc*` bodies as the engine. (3) Global probe intersect
in `calc_clocks` before scoring. (4) Full-panel size warning on every call — localize to
clocks that need full-probe-panel stats (Zhang today).

**Also.** Pass raw beta into scorers; small subset copies inside scorers are fine. Coverage
is recorded at score time; `statistics()` only formats attrs. GrimAge UX prefers pack /
components, not V1/V2 as primary ids (see detail plan).

**Sites.** `dev/migration-plan.md` (overview), `dev/detail-plan.md` (full design).

---

## 2026-07-15 -- archive legacy `R/*.R` outside the package tree

**Decision.** Snapshot every pre-rewrite `R/*.R` into one reference file
`dev/legacy/R-pre-rewrite.R` with `# ---- <filename> ----` separators, remove those sources
from `R/`, keep `R/sysdata.rda`. Rebuild via `uv run --no-project python dev/legacy/archive_R.py`
(simple: for each `R/*.R`, emit separator, append body). Also snapshot
`NAMESPACE` → `dev/legacy/NAMESPACE-pre-rewrite`.

**Why not wipe without archive.** Legacy calculators still encode edge-case math, imputation
quirks, and API shapes worth grepping while porting verbs. Pure delete forces `git show`
archaeology for every question.

**Why not leave sources in `R/` (even as one mega-file).** `load_all()` / install load all
`R/*.R`. Legacy in `R/` keeps the old export surface and collides with the rewrite.

**Why one file under `dev/legacy/`.** Frozen reference for `rg`; separators recover original
filenames. Not multi-file because we are not editing the legacy tree further.

**How to use.**

```text
rg calcHannum dev/legacy/R-pre-rewrite.R
# rebuild archive from git history only if R/*.R still exist:
# uv run --no-project python dev/legacy/archive_R.py
```

**What stays in `R/` after archive.** `R/sysdata.rda` plus new rewrite sources as they land.

**Related leftovers.** `man/*.Rd` and live `NAMESPACE` still describe old exports until
roxygen is regenerated. Do not reintroduce deleted `R/` sources just for old `.Rd` files.

**Sites.** `dev/legacy/archive_R.py`, `dev/legacy/R-pre-rewrite.R`,
`dev/legacy/NAMESPACE-pre-rewrite`, emptied `R/*.R`, `R/sysdata.rda` retained.
