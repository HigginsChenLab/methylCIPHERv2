# Decisions log (package rewrite)

Append-only, date-stamped. Records **why** we chose a design during the rewrite under
`dev/migration-plan.md` — the “we tried X / other maintainers will ask this” history that
should not bloat the plan’s operational sections.

**Scope:** R package rewrite, packaging, API, and local maintainer workflow. Upstream
metadata contract decisions live in `data-raw/methylCIPHER-meta/control/DECISIONS.md`.

Newest first. Add an entry when a decision reverses a prior approach or is likely to be
second-guessed; do not restate rules already stated in the migration / detail plans.

---

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
`clock_group_bundle()`. Their roxygen states the fields/types; a `testthat` test asserts
`names(mc_index)` and a sample `mc_catalog` entry's structure, so a shape change breaks a test
and forces the doc update. `calc_clocks` code consumes only accessors -- never raw
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
