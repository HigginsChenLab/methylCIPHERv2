# methylCIPHER Rewrite -- Detail Plan

Canonical long-form design for the rewrite. Overview: [`migration-plan.md`](migration-plan.md).
Decisions log: [`DECISIONS.md`](DECISIONS.md).

This document folds the architecture discussion (engines, packs, memory, coverage) and the
operational contracts that used to live only in the overview plan. Prefer updating **here**
when behavior is specified; keep the overview short.

**Current truth only.** Superseded designs are removed from these sections, not annotated inline;
their history lives solely in [`DECISIONS.md`](DECISIONS.md).

---

## 1. Product and public API

### 1.1 Exported surface

| Function | Purpose |
|---|---|
| `list_clocks()` | Discover / filter (format, covariates, batch_dependent, external, ...) |
| `get_clock(id)` | Lightweight metadata for one id |
| `get_clock_probes(id)` | Required probes + imputation refs |
| `calc_clocks(DNAm, clocks, pheno = NULL, ...)` | Main scorer |
| `summary(x)` | Coverage data.frame from the result record |
| `augment(scores, data, ...)` | Join scores to analysis / pheno tables |
| `clear_clock_cache()` | Report cached external packs; consent-gated removal (never auto-deletes) |
| `mc_data_download()` / `mc_set_cache_dir()` | Explicit pre-fetch; session cache-dir override |

### 1.2 Removed or non-primary surface

- Per-clock exported `calc*` as the **implementation** (optional thin legacy wrappers OK).
- Exported `MiAge_*` helpers, `calcUserClocks`.
- Return types that flip between vector and pheno-appended data.frame as the default.
- Row-order phenotype alignment.
- `library()` / `require()` inside scoring paths.

### 1.3 Result contract

`calc_clocks()` returns an **S3 record over `list`**, class `"methylCIPHER"`:

```r
structure(
  list(
    scores     = <n x k double matrix>,   # dimnames = samples x clock ids
    coverage   = <per-column coverage>,   # see sec 4
    provenance = <clocks, requested, dependencies, covariates_used, batch_set_id>
  ),
  class = "methylCIPHER"
)
```

Inherits `list`, **not** `matrix`: a matrix subclass drops class + attributes on the first
`x[, "Horvath"]` / `t()` / arithmetic, silently discarding coverage and provenance. Verbs are
methods so no operation loses data:

| Method | Behavior |
|---|---|
| `as.matrix` | `$scores` -- the naked-numbers escape hatch |
| `as.data.frame` | scores as a data.frame (sample id column + score columns) |
| `[` | subset rows/cols of `$scores` **and** the matching coverage/provenance -> `methylCIPHER` |
| `cbind` | bind score columns; check `batch_set_id` compatibility |
| `augment` | join `$scores` to a table by sample id (generic imported from `generics`) |
| `summary` | format `$coverage`; never re-touches beta |
| `codebook` | per-column clock metadata from the catalog |
| `citation` | `bib_key` -> BibTeX for the columns present |
| `print` | dims + coverage summary, not a full matrix dump |

Rules:

- One clock -> still `n x 1` scores, never a bare vector.
- Scores only; no automatic pheno columns.
- Multi-output / pack requests -> multiple columns.
- **Dependency clocks are returned as columns**, after the requested ones (§2.1). They were
  genuinely computed and each carries its own coverage row, so dropping them would hide the state
  of a composite's inputs — a `DNAmFitAge` resting on a `GrimAgeV1` scored from few CpGs must be
  inspectable. Column order is requested-first (request order), then auto-added deps (compute
  order); `$provenance$requested` / `$dependencies` partition `$provenance$clocks`. Callers wanting
  only what they asked for subset downstream.
- `augment()` is the join step; optional `augment = TRUE` sugar may exist later (non-default).

### 1.4 Legacy `calc*` (collaborators)

If collaborators need old names:

- Generate thin wrappers -> `calc_clocks()` + optional legacy return shape (append pheno).
- Do **not** reimplement old bodies from `dev/legacy/R-pre-rewrite.R`.
- Deprecate for one release, or keep as permanent soft compatibility -- product choice in
  `DECISIONS.md` when locked.
- Fixtures and tracker always target `calc_clocks` / catalog ids.

---

## 2. Runtime architecture

### 2.1 Mental model

```text
calc_clocks
  |- normalize / expand aliases (packs)
  |- prepare_inputs (once)
  |    check_dnam, align_pheno by ID, covariates_required
  |    full-panel warn if needed (localized)
  |- for each work unit -> score_*  (engine or pack)
  |    returns list(score = matrix, coverage = list(...))
  \- assemble_methylCIPHER -> record (scores + coverage + provenance)
summary(x)  # pure read of x$coverage
```

**Resolve + prepare-once front end** (in `R/resolve_inputs.R`). Two phases, both *before* any
scoring, both run exactly once — never inside the per-clock loop:

- `resolve_clocks(clocks)` — **pure namespace resolution**: user tokens -> catalog `clock_id`s.
  Accepts (any mix) the alias `"all"`, a `group_id` (expanded to its members), or a bare
  `clock_id`, resolved by a fixed precedence, **maximal clock-id set first**: `"all"` > `group_id`
  (whole group) > bare `clock_id`. When a token is **both** a `group_id` and a `clock_id` (e.g.
  `"DNAmFitAge"` names both the 7-member group and one composite member), the **group wins** so a
  group request returns as many member ids as possible — one rule covering a non-clock group_id
  (`GrimAge`, `SystemsAge`), a group_id that is also a member id (`DNAmFitAge`), and a singleton
  (`group_id == sole clock_id`, `MiAge`). Returns unique ids in first-seen order. Unknown tokens
  are an error naming them. It does *no* math and *no* ordering, and does **not** resolve
  dependencies — that is `resolve_clocks_sequence`'s job (next bullet). **Input contract
  (enforced):** `clocks` must be a non-empty character vector; `NULL` / missing / `character(0)` /
  `NA` / empty-string tokens error at the front door (callers that want everything pass `"all"`), so
  an empty request can never silently resolve to nothing.
- `resolve_clocks_sequence(clock_ids)` — **the dependency plan step** (settles the mechanism §2.1
  used to leave open; see DECISIONS 2026-07-17). Takes the resolved set and returns its **transitive
  closure** over `depends_on_clocks` (read via `clock_depends_on()`), **topologically sorted** so a
  clock always comes after everything it depends on (cycle-guarded; stable first-seen otherwise).
  Cross-clock deps DO exist and are declared in the catalog — only 3 clocks: `GrimAgeV1/V2` -> their
  CpG surrogates; `DNAmFitAge` -> gait/grip/VO2max + `GrimAgeV1`, which **crosses group boundaries**.
  Like the covariate union, deps are pulled in **on demand** (a request that never touches them adds
  nothing). **Auto-added ids** (in the plan, not in the requested set) are scored *and returned* as
  columns (§1.3), tracked apart in `$provenance$dependencies`. This is why the prepare-once unions
  below run over the **plan**, not the raw request.
- prepare-once, **parametrized by the resolved set, not per clock**:
  - sample identity runs first, **inline** in `calc_clocks()`: identity-less DNAm gets positional
    ids `sample1..N` (or a hard error if `allow_positional_ids = FALSE`), flagged
    `$provenance$positional_ids` so `cbind` can refuse it (§5.1, §7.1).
  - `check_DNAm(DNAm)` — *universal* invariants only: double matrix; unique CpG colnames; unique
    sample-id rownames (non-NULL by now — real or positional); orientation and `^cg`-prefix
    warnings. Carries no clock knowledge.
  - covariate check is a **union over the compute plan** (requested + auto-added deps):
    `extra_columns <- unique(unlist(lapply(plan, clock_covariates_required)))`, fed once to
    `check_pheno(pheno, ID, extra_columns)`. Unioning over `plan` (not the raw `clock_ids`) is
    load-bearing: a dep can require a covariate the request does not — the single `DNAmFitAge` clock
    declares only `Female`, but its `GrimAgeV1` / `DNAmVO2max` deps also need `Age`. Requirements are
    a per-clock catalog field (`covariates_required`), so requesting a single component vs. a whole
    group is automatically correct — **no per-clock/per-group check registry, nothing hand-coded per
    clock.**
  - **coverage floor** — `warn_low_coverage(cpg_list, min_coverage = 0.8)`, run once on the
    `resolve_cpgs()` skeleton (§2.3a): one warning naming every clock whose
    `score_present / score_needed` falls under `min_coverage`, with counts and percentage.
    `min_coverage = 0` silences it. **Sample-invariant** — it reads set sizes, so it fires on
    panel/array mismatch (wrong array, a group's weights off-manifest, a simulated panel built from
    too narrow a clock set), never on per-sample NA, which is tier 2's job (§4.2). It **warns and
    proceeds**: a partial panel still yields a defensible score for many clocks (`vendor_mean`
    fills; `omit` degrades smoothly) and the caller may knowingly be scoring a 27k array — what is
    not defensible is silence. Running it over the **plan** is what makes a collapsed *input*
    visible: a `GrimAgeV1` at 0 present CpGs is named even when only `DNAmFitAge` was requested.
    It lives in `calc_clocks()`, not inside `resolve_cpgs()`, which stays pure set math (§2.3a).

Deliberately **not** in this front end: the full-panel warning (it is the `sample_scale`
transform's own precondition — §2.4), imputation checks (they live with the impute step — §2.3),
and array-normalization (never executed — §2.4a). Same principle throughout: a clock-specific
precondition lives with the step that consumes it, not hoisted into the universal prepare path.

### 2.2 Dispatch: linear engine + a finite branch set

There is no recipe interpreter -- not even as a reference/fallback. Every work unit routes on
the catalog pair `(weights_format, computation_type)` to one of a small, closed set of branches.
Meta `weights_format` / recipes still **define** the math (and fixtures check it); the branches
are pragmatic, hand-optimized implementations of that contract.

| Bucket | Implementation | Typical content |
|---|---|---|
| Linear engine | Shared `linear_score()` | Most `cpg_coefficient` clocks |
| Pre-transforms | Small modules feeding linear | Zhang `sample_scale` (stats on full panel -> apply to coef subset) |
| Sex-split | Linear engine, female/male coef selected on `Female` | DNAmFitAge surrogates |
| Family orchestrators | Dedicated internal functions | **GrimAge pack** (bundled, per-clock) |
| Batched pack scorers | One shared subset + one matmul per group | **PCClocks**, **SystemsAge** packs |
| External | Soft dependency adapters | DunedinPoAm38, DunedinPACE |
| Custom | Dedicated helper | MiAge |

Bundled packs may own their orchestration (shared intermediates, multi-column assembly) but call
the shared `linear_score()` / impute helper for every linear sub-step, so imputation lives in
exactly one place (sec 2.3).

**Batched pack scorers** (`score_pack_group()` in `R/score_pack.R`) are the exception, for the two
external groups whose members share one large CpG panel (PCClocks ~78k, SystemsAge ~125k). Scoring
those per clock repeats the panel-wide `DNAm[, present]` subset once per member -- the dominating
cost (13.7x measured for 14 PC clocks; the matmul itself is negligible). So a group is scored in a
single `pack_design()` (one subset, reused) + one `pack_linpred()` matmul over all requested
columns, with per-clock intercept, covariate, and output transform applied to the resulting
columns. This is a *batched* linear kernel, not `linear_score()` -- but it reproduces the identical
imputation contract (partial-NA -> cohort cache; absent -> vendor-mean offset from `pack$impute`),
so imputation semantics still live in one described place. It is **only** worth it where the panel
is huge and shared: the bundled clocks (union ~20.7k CpGs, 1.6x overlap) score all 86 in ~60ms, so
they stay on the per-clock engine -- no general "group linear clocks" layer (see DECISIONS
2026-07-21). Requesting a single pack member returns just that member (no family expansion); the
batch simply collapses however many members are in the plan into one matmul.

### 2.3 Linear engine

```r
linear_score(DNAm, coefs, intercept, impute_spec, transform = NULL)
```

Imputation / missingness -- **two missing-kinds, two sources, never crossed** (implement in one
place):

| Case | Source | Behavior |
|---|---|---|
| **Partial NA** on a probe **present** in `DNAm` | current cohort | Fill from the cohort (mean over observed samples for that probe). Cohort-dependent by design; a **fallback** for users who did not pre-handle NAs |
| **Completely absent** probe (not in `DNAm`), policy fill | vendor | Fill from the clock's vendored ref (mean / median / sex-wise, per meta), then weight |
| Completely absent, policy `drop` (default) | -- | Drop the term (zero contribution) |
| Sex-keyed vendor ref | vendor | Require `Female` before fill; pick female/male ref vector |

The split is load-bearing: vendored-filling a partial NA injects a foreign cohort's data into the
user's samples; cohort-filling a fully-absent probe is impossible (no data to borrow). `mean` is
the current fallback statistic, not a fixed rule. Never apply one package-wide impute policy to
all clocks -- the vendor spec comes from meta (`imputation`, recipe steps).

### 2.3a Partial-NA is a shared cohort cache, not per-scorer work

The partial-NA (cohort) fill is **precomputed once per call and shared**, not redone inside each
scorer. Component families (DNAmFitAge's 7 members, GrimAge surrogates) reuse the same CpGs, so a
shared missing probe would otherwise get its cohort mean recomputed once per clock; hoisting it also
makes every scorer read the **identical** filled column for a shared CpG (a consistency guarantee,
not just a speed win). Prepare-side pipeline, gated so clean betas pay nothing:

- **Global gate.** `anyNA(DNAm)` is monotone: no NA anywhere ⇒ no clock can have a partial NA ⇒ skip
  the whole cache + per-sample layer. This is the common case (pre-handled betas).
- **One classifying pass.** `slideimp::mat_miss(DNAm, col = TRUE)` (per-column NA counts, no logical
  mask) splits every column three ways: `0` clean, `1..nrow-1` partial, `nrow` **all-NA**. `mat_miss`
  keeps the pass allocation-free.
- **All-NA present column → reclassify ABSENT.** Zero observed values ⇒ no cohort mean exists ⇒ it is
  informationally identical to a probe off the panel. Drop it from the **usable** column universe
  (`setdiff(colnames(DNAm), all_na_cols)` — a name-set op, **not** a `DNAm[, keep]` copy) so it flows
  to the vendor/drop path and is counted in `n_cpg_score_miss` (§4). This is why `mean_imp_col`'s
  own "0 observed → unchanged" branch never has to fire in our path.
- **Empty sample (all-NA row) → HARD ERROR.** `mat_miss(DNAm, col = FALSE)`; `row_miss == ncol`
  cannot be scored. Load-bearing reason it errors rather than warns: cohort-mean imputation would
  otherwise fill its every cached cell with the column mean and emit a plausible-looking
  **fabricated** score instead of an honest `NA`. (An all-NA row is `isnan`-skipped in every column
  mean, so it never biases other samples; the damage is confined to its own fake score, but that is
  reason enough to refuse it. Analogous to the `allow_positional_ids` strictness dial in §5.1 — but
  here there is no permissive mode; empty rows are always an error.)
- **Cache build.** `cache_cpgs = intersect(present_needed_union, partial_na_cols)` — present (a mean
  exists), needed by some clock (don't cache dead columns), and actually partial. Subset **first**,
  then impute: `slideimp::mean_imp_col(DNAm[, cache_cpgs])`. `mean_imp_col` returns a matrix the same
  width as its input (untouched columns are `memcpy`'d), so calling it on the full panel would
  allocate a second `n × p` copy (the §3 spike); narrowing columns first bounds the cache to the
  handful of partial-NA needed probes (empty when clean). The cache is an `n × k` matrix scorers read
  from; raw `DNAm` is never mutated.

Front end split (which function owns what): `scan_missing_cpgs()` (numeric — the gate, the classify,
the empty-row throw, `usable_cols`) and `build_partial_cache()` live with the impute machinery
(`R/impute_DNAm.R`); `resolve_cpgs()` (pure set math over `usable_cols`, §4 aggregate skeleton +
`present_needed_union`) lives with the other resolvers (`R/resolve_inputs.R`). Order in
`calc_clocks()`: `scan_missing_cpgs → resolve_cpgs → build_partial_cache` (the cache needs
`resolve_cpgs`'s present union; `resolve_cpgs` needs `scan`'s `usable_cols`).

### 2.4 Zhang / `sample_scale` transform

Do **not** scale and keep a full `n x p` matrix.

```text
For each sample i:
  mu_i, sigma_i <- moments over ALL probes in DNAm[i, ]
Keep only EN / coef probes j:
  z_{ij} <- (DNAm[i,j] - mu_i) / sigma_i
linear_score(Z, coefs, policy = drop)
```

- Moments need full width -> user should pass full beta (450k/EPIC).
- Scoring only needs the small coef submatrix after stats.
- This is a **transform module** in front of the linear engine, not a separate scientific
  family.

**Full-panel notice (Zhang2019-only, hard-coded):** do **not** fire a generic
`needs_full_probe_panel` / `ncol(DNAm) < 1e5` warning across flagged clocks. Only `Zhang2019`
needs this today, so hard-code the exception: when the worklist includes `Zhang2019`, emit a
`message()` (not `warning()`) — Zhang2019's original code computes per-sample moments over **all**
CpGs, but a large-enough subset is usually sufficient. Fired here in the transform, not in the
prepare front end.

The `sample_scale ∈ batch_ops` catalog marker stays (that's how we know this clock is the
transform case). **Intended direction:** retire `clock_needs_full_panel()` and collapse
`check_DNAm_extra()` into this single `clock_ids == "Zhang2019"` hard-coded special case, since
no other clock exercises it.

### 2.4a Normalization policy — annotate, never execute

`sample_scale` above is a *scoring-recipe* transform, not array normalization. Array
normalization proper is the per-clock `normalization` field: `none` ×104, `BMIQ` ×7,
`quantile` ×1 (DunedinPACE), `noob` ×1 (Horvath2). **The package executes none of it.**

- BMIQ / noob / quantile are squarely **upstream** (sesame / minfi) — the user's responsibility.
- Horvath's BMIQ-to-golden-mean is **deliberately skipped**: a correctness bug in RPMM. Parity
  fixtures show ~0.9999 correlation of no-BMIQ vs the Horvath server, so re-implementing it buys
  nothing and inherits the bug. Users who want BMIQ run the RPMM pipeline themselves first
  (most won't).
- DunedinPACE's `quantile` runs **inside its external wrapper** (`computation_type=wrapper`), not
  ours.

So `normalization` is a **coverage / provenance annotation** — surfaced via a (future)
`clock_norm_scheme()` accessor feeding `norm_needed` (§4) — **not a compute step and not a
check**. There is no shared "norm intermediate" layer: nothing is jointly normalized by us
(`sample_scale` is per-sample and Zhang-only today; QN is external), so building one would be
speculative. The only norm-adjacent thing the package runs is the `sample_scale` transform.

### 2.5 GrimAge pack (orchestrator)

**User-facing:**

- Prefer `"GrimAge"` and/or **component** ids (`DNAmADM`, `DNAmPACKYRS`, ...).
- Do not push `GrimAgeV1` / `GrimAgeV2` as the primary UX (catalog may still retain those ids
  for fixtures and provenance).

**Under the hood (product policy):**

- Always compute enough shared work for both V1 and V2 pipelines (fast enough).
- Component columns come from the **V2** path (not duplicate V1 surrogates).
- Full pack return includes V2 components + GrimAgeV1 + GrimAgeV2 columns (exact set TBD in
  implementation; fixtures pin catalog ids).

Too special to force through a generic path -> `score_grimage()`.

### 2.6 SystemsAge pack

External asset bundle carrying `$organs`/`$systems`/`$age`/`$impute` matrices + a small
systems_PCA tensor tree; loaded **once** upfront and threaded to every member (no per-member
reload). The 11 organ sub-clocks are plain `cpg_coefficient` linear (coef from `$organs`, shared
engine). The two component-matrices composites (`Age_prediction`, `SystemsAge`) are the
`score_systemsage()` family orchestrator: age-linear front -> quadratic, and for the overall index
11 raw system predictors + poly-scaled age -> center/scale -> systems_PCA project -> linear head.
Pipeline *shape* is hard-coded (no recipe walker); constants come from the catalog recipe via
`systemsage_*` accessors. Each member is scored independently on the shared linear kernel -- the
composite recomputes its raw system vectors (cheap; no shared-intermediate cache).

### 2.7 Worked call

```r
calc_clocks(DNAm, c("Zhang2019", "GrimAge"), pheno = pheno)
```

1. Resolve: Zhang2019 -> linear+sample_scale transform; `"GrimAge"` -> pack orchestrator.
2. Prepare: check DNAm; if Zhang in list and `p < 1e5` -> warn; align pheno; require Age +
   Female for GrimAge pack.
3. Zhang: full-matrix row moments -> EN subset -> scale -> linear(drop) -> 1 column + coverage.
4. GrimAge: orchestrator -> multi-column matrix + per-column coverage.
5. Assemble -> `methylCIPHER` record; `summary(out)` without re-touching DNAm.

---

## 3. Memory and copies

| Do | Don't |
|---|---|
| Pass **raw** `DNAm` into scorers (no upfront global intersect) | Build union-of-all-clocks submatrix in `calc_clocks` before dispatch |
| Let each scorer `DNAm[, probes]` -> small copy | Scale full DNAm in place for Zhang |
| Pack orchestrators may extract **one** union for the pack | Micro-optimize column views / sparse before profiling |

R: passing `DNAm` does not copy; `DNAm[, j]` does allocate the subset -- expected and fine for
clock-sized `j`.

---

## 4. Coverage and `summary()`

Scorers **must** return coverage; assembly stores it on `x$coverage`. Coverage has **two tiers** at
two granularities, both recorded at score time (never re-intersecting beta):

### 4.1 Tier 1 — per-clock aggregate (`summary()`)

Recorded **per role** (a clock's scoring CpG set and its normalization/background set are different
sizes) and splitting the two impute sources. **Sample-invariant** — these are set sizes against the
usable column universe, the same for every sample:

| Field | Meaning |
|---|---|
| `clock_id` | Score column / catalog id |
| `norm_needed` / `norm_present` | Normalization / background panel (Zhang, QN clocks); `NA` when none |
| `score_needed` | Scoring CpGs (materialized `probe_sets[role=scoring]`) |
| `score_present` | Scoring CpGs found in `usable_cols` (colnames minus all-NA, §2.3a) |
| `score_used` | Terms that entered the sum |
| `score_imputed_partial` | Present-but-NA cells filled from the **cohort** cache |
| `score_imputed_full` | Absent probes filled from the **vendor** ref |
| `score_dropped` | Absent probes dropped by policy |
| `missing_cpgs` | Character vector of absent probes (incl. all-NA columns reclassified per §2.3a) |
| `policy` | Impute policy used |

```r
summary(x)  # data.frame, one row per score column; NA where a stage does not apply
```

The `n_cpg_score` / `n_cpg_norm` / `n_cpg_score_miss` / `n_cpg_norm_miss` counts are just
`length()` of these sets — `resolve_cpgs()` (§2.3a) already computes the present/absent split, so
they ride the skeleton to assembly and `summary()` only **formats**; it never recomputes.

- **Free** if recorded at score time; `summary()` must not re-intersect beta.
- Zhang: `score_needed` = EN coef count (not full array); `norm_needed` = panel size.
- Messaging that implies confidence must not ship without coverage context.

The `score_present / score_needed` ratio is also read at **prepare** time by the coverage floor
(§2.1), which warns before any scoring happens rather than waiting for the user to call `summary()`.
Same numbers, two moments: the floor is the unmissable signal, `summary()` the full account.

### 4.2 Tier 2 — per-clock × per-sample missingness (QC matrix)

Tier 1 collapses the sample axis; tier 2 keeps it. Absence is sample-invariant, but **partial NA is
sample-specific**: a sample 10% missing *globally* can be ~100% missing *for one clock* if its gaps
concentrate in that clock's scoring set — invisible to the global empty-row check (§2.3a), and **not
an error** (one clock being locally empty for one sample must not fail the batch — record it, don't
throw). Each scorer emits a length-`n` vector = row-wise NA count over its **own** present scoring
CpGs, computed on the **raw** subset *before* the cache fills it (post-fill it reads ~0 — the
imputation masks exactly the QC signal). Assembly stacks the `k` vectors into an `n × k` matrix
behind a method (`sample_coverage(x)`), for a sample × clock coverage heatmap.

It is literally the row-wise decomposition of tier 1's `score_imputed_partial` (sum the sample axis
and you get the scalar back), so no new mechanism — same `slideimp::mat_miss` primitive, `col = FALSE`.
Efficient by the same gate cascade: skip entirely when `!scan$has_na`; per clock,
`intersect(score_present, partial_na_cols)` is a **free** set op (reuses the prepare-side
`mat_miss(col = TRUE)` result — no re-scan), and `mat_miss(col = FALSE)` runs only over that clock's
NA-bearing columns (clean columns add 0 to every sample). Store only the partial vector; combine with
tier 1's absent scalar at render (`observed_fraction[i,c] = (score_needed − absent − sample_miss[i,c])
/ score_needed`). Optional future hook: a soft policy that flags/`NA`s a cell below a coverage
threshold reads this matrix — default stays record-and-report.

---

## 5. Phenotype and covariates

| Name | Encoding |
|---|---|
| `Age` | Numeric |
| `Female` | `1` female, `0` male |

- Only canonical names at scoring (aliases may be documented later, applied in prepare).
- Align by sample id only, never row order; full identity/alignment contract in §5.1.
- Covariate requirements are **one flattened catalog field** (`covariates_required`, computed by
  sync's `extract_covariates`). It unions every source that can imply a covariate: top-level
  `covariates`, any recipe step key ending in `covariates` (incl. `female_covariates` /
  `male_covariates`), a `linear_sex` recipe op, `sex_params.{female,male}.covariates`, a
  `sex_stratified: true` flag, and sex-keyed imputation refs (`imputation.ref.{female,male}`) --
  the last three all contribute `Female`. R reads the flattened field once at runtime; it does
  **not** re-derive from the meta keys in the scoring path. (The source set is empirical -- it
  grew as clocks were implemented -- so it is the accessor/fixture surface, not a fixed grammar;
  a wrong extraction surfaces as a covariate error or score mismatch in that clock's golden
  fixture.)
- Sex-keyed impute clocks need `Female` before impute (FitAge / VO2max / grip / gait / FEV1
  family members -- see catalog).
- `calc_clocks` fails clearly when required covariates are missing.

### 5.1 Sample identity and pheno alignment

`rownames(DNAm)` is the canonical `sample_id`: unique, and **preferred**. Identity-less DNAm is
**not** a hard error by default -- `calc_clocks()` stamps positional ids `sample1..sampleN` inline
(before `check_DNAm`), so a workflow that leans on row order rather than ids can still score without
maximal front-door defensiveness. The `cbind` footgun this used to
guard against is closed instead **at the bind step**: positional ids are row-order artifacts, not
comparable across separate matrices, so such records are flagged `$provenance$positional_ids = TRUE`
and `cbind.methylCIPHER` **refuses** them (§7.1 gate 0). `allow_positional_ids = FALSE` on
`calc_clocks()` restores the strict hard-error contract. A caller with genuine sample duplicates
must give each its own id; a caller wanting a clock's score twice duplicates the score column, not
the input rows. `sample_id` is derived **once**, from DNAm (real or positional), stamped on
`$provenance$sample_id`, and used as `rownames($scores)`. pheno is never the identity.

`pheno_id` (the id column name) always has a default; only `pheno` itself may be `NULL`. Alignment
(`resolve_pheno()`) has **two modes**, chosen by whether DNAm had real rownames (i.e. by
`positional_ids`), never mixed:

| Case | Mode | Rule |
|---|---|---|
| `pheno = NULL` | — | `sample_id = rownames(DNAm)`; no covariate side-table |
| `pheno` given, DNAm had rownames | **id join** | `pheno[[pheno_id]]` present, **unique**, non-missing, and `rownames(DNAm) ⊆ pheno[[pheno_id]]`; else error naming missing ids. Subset + reorder pheno to `rownames(DNAm)` order |
| `pheno` given, DNAm had **no** rownames | **row-order join** | **`nrow(pheno)` must equal `nrow(DNAm)` exactly** (taller = ambiguous, shorter = short → throw). Row *i* of pheno is sample *i*, taken in given order; the `pheno_id` column is then **overwritten** with the positional `sample_id` |

- **Id join.** `rownames(DNAm) ⊆ pheno[[pheno_id]]`, so we filter first; no `unique(pheno)` dedup
  -- duplicate ids are the caller's error, never silently collapsed. pheno may carry **extra** rows
  (other cohorts); they are ignored after the subset.
- **Row-order join** is the only alignment available when DNAm carries no ids (positional mode):
  there is no key to match on, so covariate-needing clocks can only pair pheno to samples by
  position, which is why the row counts must match exactly. Such records are already flagged
  `positional_ids` and refused by `cbind` (§7.1 gate 0).
- Post-condition (both modes): the returned pheno has `nrow(DNAm)` rows in `sample_id` order, with
  `pheno[[pheno_id]] == rownames(pheno) == sample_id` (id mode reaches this for free since it matched
  on that column; positional mode overwrites it). The record stays scores-only (§1.3); this aligned
  pheno feeds covariate scorers and is not appended. `as.data.frame()` surfaces `sample_id` under the
  `pheno_id` name beside the scores.

---

## 6. Batch-dependent clocks

| Clock | Op | Scope |
|---|---|---|
| `DNAmPhysAge` | `cohort_zscore` | Samples in current call |
| `DNAmPhysAge_years` | `cohort_zscore` | Samples in current call |
| `Zhang2019` | `sample_scale` | All probes within each sample (moments) |

Rules:

- Subsetting samples before vs after scoring can change batch-dependent outputs. Different
  cohorts are analyzed separately (dedupe samples); there is no "same sample across cohorts."
- Partial-NA imputation (sec 2.3) is also cohort-dependent by design -- imputation borrows
  within-cohort information -- but it is a fallback, not a scoring op, so it is not listed here.
- Do not global-union-probe-optimize away Zhang's full panel.
- Store sample-set id on batch-dependent results; `cbind.methylCIPHER` rejects incompatible
  sets.

---

## 7. Provenance (result record)

`x$provenance` carries:

- `sample_id`
- `positional_ids` (logical) -- `TRUE` when `sample_id` was manufactured inline by `calc_clocks()`
  from a rowname-less DNAm; `cbind.methylCIPHER` refuses records flagged `TRUE` (§7.1 gate 0)
- `clocks` — every scored column's catalog id, in `$scores` column order
- `requested` / `dependencies` — the partition of `clocks` into what the caller asked for and what
  the plan pulled in (§1.3, §2.1). The only place that distinction survives; both are real columns
- Covariates actually used — unioned over **all** returned columns, deps included, so a request for
  `DNAmFitAge` alone reports `Age` (its deps' requirement) and not just `Female`
- Coverage (see sec 4)
- Batch sample-set id when applicable

No commit SHA / pin is stamped on the result: correctness is proven by fixtures. The one sync-side
identity key that remains -- the external packs' content-address `payload_hash` -- stays in
`data-raw/` and never reaches a result record.

`augment()` compares covariates actually used; mismatch = error by default (warn/ignore
overrides optional).

### 7.1 `cbind` compatibility

`cbind.methylCIPHER` ([`R/generics.R`](../R/generics.R)) binds score columns of two or more records
only after a **positional guard** then **three** independent gates:

0. **Positional-id guard.** If any record has `$provenance$positional_ids = TRUE`, throw. Its
   `sample1..N` ids are row-order artifacts, not real identity, so the set/order comparisons below
   are meaningless against another matrix. Positional records score fine; they just cannot be bound
   -- give DNAm real rownames to opt back in.
1. **`sample_id` set.** Sets must be equal. Equal set + same order binds directly; equal set +
   different order reorders the later records to the first record's `sample_id` order and
   re-verifies `identical(sample_id)` before binding; unequal sets throw (different samples).
2. **Shared-covariate consistency** -- evaluated **per covariate**, only for covariates that appear
   in `covariates_used` of **more than one** record. Their per-sample values (keyed by `sample_id`)
   must agree, so the same `Age` / `Female` is bound to the same sample across records. Moot when
   only one side carries covariates, or both do but they are disjoint (nothing shared to compare); a
   covariate used by exactly one record is never checked. Hashes each shared covariate keyed by
   `sample_id` -- never the whole pheno table (§12 non-goal).
3. **`batch_set_id`** (§6) -- required equal for any batch-dependent column; a hash of the sample
   *set*, invariant to gate 1's reorder, so it catches "same samples, scored in two cohorts".

---

## 8. Source of truth and catalog discovery

Canonical remote: `https://github.com/hhp94/methylCIPHER-meta.git`.

Sync-time crawl (`data-raw/sync.R`):

```r
metas <- list.files("weights", pattern = "\\.meta\\.json$", recursive = TRUE, full.names = TRUE)
clock_metas <- metas[basename(metas) != "_group.meta.json"]
group_metas <- metas[basename(metas) == "_group.meta.json"]
```

- Discriminate clock vs group by basename, not depth.
- Singleton: `group_id == clock_id`; multi-member groups have `_group.meta.json`.
- At **sync time** R reads `weights/`, `manifest.json`, and `bibliography/{papers.csv,clocks.bib}`
  (the last joins `pmid -> bib_key` in memory and vendors `clocks.bib` to `inst/`; `papers.csv` is
  never shipped). Nothing under `control/`, `papers/`, or `scripts/` is read. At **runtime** R reads
  only the built `sysdata` objects, via the accessor layer -- never the meta tree.
- Family membership from `group_id` / sidecar path, not free text.

**Schema = accessors, not a doc.** The sysdata shape is defined by `build_index()` /
`build_catalog()`. The executable schema is the accessor layer -- `get_clock()`,
`clock_scoring_cpgs()`, `clock_norm_cpgs()`, `clock_impute()`, `clock_coefs()`,
`clock_group_bundle()` -- documented via short `#` comments for now (roxygen deferred to alpha)
and whose structural `testthat` test asserts `names(mc_index)` + a sample `mc_catalog` entry. A
shape change breaks the test and forces the comment update. `calc_clocks` code consumes only accessors, never raw nested lists. No
hand-written `schema.md` (it would drift, the class the meta repo's `meta_schema.py` exists to
eliminate); generate one from the objects if ever needed.

Meta remains the scientific contract; Python `ops.py` / `transforms.py` / `covariates.py` in
upstream are reference implementations for parity thinking.

---

## 9. Sync, lockfile, packaging

### 9.1 Sync-internal identity (not product provenance)

The full `sysdata.rda` rebuild is cheap (~2s), so there is **no** catalog build-skip cache and no
`manifest_key` (removed 2026-07-20). The identity keys that remain are scoped to the three external
qs2 packs (SystemsAge, PCClocks, PCBrainAge):

- `payload_hash` -- content-address over a version-pinned serialization (`serialize(version = 2L,
  xdr = TRUE)` + `digest` sha256); sets the pack filename `<group>-<payload_hash>.qs2`, its GitHub
  release tag, and the reupload skip key. It is also read at runtime by `external_pack()` for a
  **WARN-only** content-drift check (`mc_payload_hash()` mirrors it); the warning never gates or
  errors, so it is not correctness provenance.
- `file_sha256` -- maintainer-side record in `mc_provenance`. It is **no longer read at runtime**:
  transfer integrity is now qs2's own `validate_checksum` on read (see 9.4), so R never recomputes a
  file hash. (Candidate for removal from the shipped registry later.)

A gitignored `data-raw/assets/lockfile.rds` (keyed on the meta `source_git_sha` + presence of the
staged packs) skips only the external-pack rebuild; it is **not** a product pin, not stamped on
results, and not a catalog-change detector. No SHA is treated as scientific identity.

### 9.2 Sync workflow (`data-raw/sync.R`)

1. Resolve meta commit; checkout (`source_git_sha`).
2. **Always** build catalog + accessors' backing objects + small bundles -> `R/sysdata.rda` (no
   build-skip cache; the rebuild is ~2s).
3. External packs: if `force = FALSE` and the asset `lockfile.rds` hits (same `source_git_sha` and
   every staged pack still on disk), reuse them and restore their resolved probe sets from the
   lockfile; else rebuild the three content-addressed packs and rewrite the lockfile.
4. `upload = TRUE` publishes packs to GitHub Releases; the content-address (`payload_hash` ->
   filename -> tag) plus the remote "asset already present" skip make reupload idempotent.

Rules: no tensor rehash in R; sync does not score clocks; bundle inputs only whole `weights/`
paths (never `papers/` or `scripts/`); missing referenced weights path = error.

### 9.3 Distribution tiers

| Tier | Contents | Delivery |
|---|---|---|
| Bundled | Small groups (~0.8 MB class) | `R/sysdata.rda` |
| External | SystemsAge, PCClocks, PCBrainAge | Release assets |

- `data-raw/` not in tarball; no large tensors in `inst/`.
- No download at install / build / check / CRAN test.
- Double precision coefs only (no float32).

### 9.4 External asset resolution

`load_mc_assets(groups, assets = NULL, ask = TRUE)` in [`R/methylCIPHER_data.R`](../R/methylCIPHER_data.R)
is the single runtime entry (deliberately small -- see the 2026-07-21 DECISIONS entries). It returns
a **named list of packs keyed by `group_id`** (even for one group). `calc_clocks()` calls the
identical function internally, so a pre-loaded object and an auto-loaded one cannot drift. Flow:

1. **Cache dir precedence:** an `assets` **path** > session option `methylCIPHER.cache_dir` (set via
   `mc_set_cache_dir()`) > `METHYLCIPHER_CACHE_DIR` (.Renviron) > `tools::R_user_dir(.., "cache")`
   (`mc_default_cache_dir()`).
2. **Open vs closed set (from `assets`).** `assets = NULL` -> **open**: resolve each group from the
   cache dir; missing packs are consent-downloaded. `assets` **explicitly provided** -> **closed**:
   resolve only from what is given, **never download**; a needed group not covered is a hard error.
   `assets` accepts a cache-dir path **or** loaded object(s) -- a bare pack (a list with `$group_id`),
   a list of packs, or a path all canonicalize to the named-list registry (objects key by their own
   `$group_id`); an asset the plan does not need warns and is ignored.
3. **Expected file** = `mc_provenance$external_assets[[group_id]]$file` (`<group>-<payload_hash>.qs2`).
   Present -> read it. Open-set download is consent-gated: `ask = TRUE` prompts interactively (one
   **batched** prompt for the union of missing packs) and **refuses** non-interactively; `ask = FALSE`
   is the explicit-consent signal. Staged to `<file>.part`, validated by a qs2 read, then atomically
   renamed -- a truncated transfer never lands as cached.
4. **Read** with `qs2::qs_read(validate_checksum = TRUE)`; qs2's own checksum is the transfer
   integrity guard (no separate sha256 recompute).
5. **WARN-only drift:** `mc_payload_hash(pack)` vs the provenance `payload_hash`. Mismatch warns;
   it never errors and never blocks scoring.

**No memoise.** A cold `qs_read` is ~0.1-0.2s for all three packs (benchmarked 2026-07-21), so
`calc_clocks()` resolves the needed groups **once per call** (in the prepare phase, before the pure
scoring loop) and threads the registry down; there is no session-cache/global-env tier. No silent
first-use download.

Pack encoding (`canonical_matrices`) is per-group: PCClocks/PCBrainAge carry one
`coefficient_matrix` + `impute` vector; SystemsAge carries `organs`/`systems`/`age` matrices +
`impute`. Within a group the probe set is shared once as matrix columns.

Verbs: `mc_data_download(groups, assets, ask)` pre-fetches; `clear_clock_cache(groups, assets)`
reports what is cached (deletion flow still to be designed; it never auto-unlinks).

### 9.5 Verification status

From manifest: `"" | pending | verified | disputed | skipped`. Separate from format / fixture
parity. It is a **maintainer/dev signal only** -- it records why a clock is (e.g.) `skipped`
(Horvath online variants we deliberately omit) for the human running sync. It is **not** part of
the user surface: `list_clocks` does not expose it and it is not canonicalized into the shipped
catalog. Sync still validates the value against the allowed set at build time (a warning on an
unexpected value), but the field itself stays on the maintainer side (manifest), not in
`mc_index` / `mc_catalog`. R does not read upstream ledger files.

---

## 10. Fixtures and CRAN

### 10.1 Two test tiers, different jobs

- **Engine / machinery unit tests -- always run, no meta dependency.** Hand-authored toy inputs
  (a few probes x a few samples, coefficients chosen so the expected dot product is written by
  hand in the test). Cover `linear_score` arithmetic, the impute accounting (partial vs full),
  accessors, coverage math, and result-class methods. Golden values tie to nothing upstream ->
  zero drift.
- **`sim_DNAm` smoke -- always run, no meta/cohort dependency, no golden.** `sim_DNAm(n, clocks)`
  ([`R/sim_DNAm.R`](../R/sim_DNAm.R)) reads the shipped `mc_catalog` scoring probe sets and throws
  random uniforms at them; scoring is asserted with `expect_no_error` (the data need not be
  scientifically meaningful). This exercises dispatch, coef loading, and assembly over every
  bundled clock -- and it fails loudly if a clock resolved to an empty scoring set -- without any
  `expect_equal` and so without any drift risk. It is a *machinery* check, not a correctness one.
  It resolves its panel through **`resolve_clocks_sequence(resolve_clocks(clocks))`**, the same plan
  `calc_clocks()` computes — mirroring namespace resolution alone would emit a panel missing every
  cross-clock dependency's CpGs (`"DNAmFitAge"` -> the group's 627, where the plan needs 1643), and
  since the GrimAge surrogates are policy `omit` they would score intercept-only and the composite
  would come back a plausible-looking number rather than an error. `remove = k` drops `k` CpGs to
  exercise the missingness path, and is the intended way to trip the §2.1 coverage floor in tests.
- **Parity fixtures -- the single clock-golden source, cohort-gated.** Upstream golden fixtures
  vs `fixtures/cohort_EPIC/beta.duckdb` (gitignored; regenerable via `fixtures/build_cohort.R`;
  path under the meta clone `data-raw/methylCIPHER-meta/fixtures/cohort_EPIC/beta.duckdb`).
  Skipped via `file.exists()` when the cohort is not staged. Parity policy `exact` |
  `correlation` | `skipped`; failures print clock id + policy.

No slice of the golden cohort is committed into `tests/` -- that is a second copy of upstream
golden values and it drifts; a small slice also cannot validate a `correlation`-policy clock.
CI may stage/regenerate the cohort and run the full parity gate; CRAN skips it. DuckDB is for
fixture lookups only, not a runtime tensor store.

### 10.2 CRAN checklist

- Drop or clearly deprecate legacy exports before submission as required.
- Valid License; no `library`/`require` in scoring; Suggests soft-fail for optionals.
- Teaching deps must not block install; tests without external assets; no network at check.

---

## 11. Implementation sequence

1. Accessor layer over `sysdata` (executable schema) + its structural test; catalog readers.
2. `prepare_inputs`, result record, coverage, `summary()`.
3. Linear engine + impute policies (partial/full split); fixture-drive `cpg_coefficient` batch.
4. `sample_scale` / Zhang transform -> linear; localized full-panel warn.
5. GrimAge orchestrator (alias + components + V1/V2 columns).
6. SystemsAge (and PC\* as needed) + asset resolver.
7. Remaining component_matrices as more branches/packs; external + MiAge.
8. Full fixture suite; optional legacy wrappers; docs / CRAN cleanup.

Track clocks in `dev/clock_tracker.csv` (`uv run python dev/build_clock_tracker.py`).

---

## 12. Non-goals

- Expanding per-clock exported calculators as the real engine.
- A recipe-walker runtime (rejected outright, not kept as fallback).
- Returning full phenotype tables from scorers.
- Hashing entire phenotype tables.
- Silent network downloads.
- Deep OOP for weighted sums.
- Rewriting published clock mathematics.
- Overriding metadata `drop` / impute policies package-wide.
- Crossing the impute sources (partial=cohort, absent=vendor).
- float32 coefficients.
- Bioconductor.
- SHA / pin as result provenance; R-side tensor rehashing.
- A `matrix`-subclass result; a hand-written `schema.md`.
- Micro-optimizing matrix copies before evidence.

---

## 13. Follow-ups

- Whether SystemsAge members can be derived from shared components only.
- Whether fixture cohort should be published for cross-language consumers.
- Permanent vs one-release legacy `calc*` wrappers.
- Exact GrimAge pack column set and alias errors (`GrimAgeV1` typed by user -> ?).
- **Finalize license + author/copyright credits before the alpha / public release.** Copyright
  holder is currently Yale University (DESCRIPTION `cph`, LICENSE / LICENSE.md); the BSD-3 choice
  vs bundled third-party weight terms is still open (see DECISIONS 2026-07-17 / 2026-07-21).

---

## 14. Pipeline diagram

```text
methylCIPHER-meta
  weights/ + manifest.json + fixtures/
           |
    data-raw/sync.R  (lockfile.rds = external-pack rebuild skip)
           |
    R/sysdata.rda  +  external family assets
           |
    accessor layer (executable schema)
           |
    calc_clocks()
      prepare | linear engine | pack orchestrators | external/custom
           |
    methylCIPHER record  --summary()--> coverage data.frame
           |
        augment() --> analysis join
```
