# methylCIPHERv2 Rewrite Plan (overview)

Compressed product plan for the catalog-driven CRAN rewrite. **Detailed design, contracts,
and worked examples live in [`detail-plan.md`](detail-plan.md).** Design *why* / reversals:
[`DECISIONS.md`](DECISIONS.md). Per-clock agent tracking: `clock_tracker.csv` (regen via
`build_clock_tracker.py`).

These plans state **current truth only**. Superseded designs are not kept inline; their history
(the "we tried X, reversed to Y") lives solely in [`DECISIONS.md`](DECISIONS.md).

---

## Objective

> Pick clocks -> pure scores -> optionally `augment()` with phenotype.

- One public scorer: `calc_clocks()`.
- Catalog + tensors from [methylCIPHER-meta](https://github.com/hhp94/methylCIPHER-meta.git);
  fixtures are the scientific gate.
- CRAN, not Bioconductor.
- Legacy per-clock `calc*` are not the implementation model. Optional thin wrappers that call
  `calc_clocks` may exist for one deprecation window (or longer if collaborators insist) --
  never reimplemented old bodies.

Bocklandt / Garagnani stay out (no published coefficients).

---

## Source of truth (one screen)

| Item | Rule |
|---|---|
| Remote | `https://github.com/hhp94/methylCIPHER-meta.git` |
| Inputs R may read | `manifest.json`, `weights/**`, `bibliography/{papers.csv,clocks.bib}` (never `control/`, `papers/`, `scripts/`) |
| Clock meta | `weights/{group_id}/{clock_id}.meta.json` |
| Group sidecar | `weights/{group_id}/_group.meta.json` (multi-member only) |
| Discovery | Recursive `*.meta.json`; clock vs group by basename |

The package carries no commit pin as product identity: correctness is proven by fixtures, not a
SHA. The only sync-internal identity is the external packs' content-address `payload_hash`; a
gitignored `lockfile.rds` skips just their rebuild -> [`detail-plan.md`](detail-plan.md) sec 9.

---

## Runtime architecture (current intent)

Runtime is **one linear engine + a small, closed set of branches** -- not a clock-function
factory and not a recipe interpreter. Each work unit is dispatched on the catalog pair
`(weights_format, computation_type)`. Meta/fixtures remain the scientific contract; the branches
are optimized implementations of that contract.

```text
calc_clocks(DNAm, clocks, pheno = NULL, ...)
  prepare once          # DNAm check, pheno align-by-ID, covariate requirements
  resolve requests      # callable pool only; group ids expand; routing targets refused
  expand deps           # transitive depends_on_clocks, deps first
  route each unit on (weights_format, computation_type):
    linear engine       # most cpg_coefficient (+ optional pre-transforms)
    family packs        # GrimAge, SystemsAge, Dunedin (shared intermediates; not generic)
    sex-routed alias    # picks a sex-resolved member per sample
    external / custom   # MiAge
  mask routing targets  # blank rows a one-sex model does not apply to
  assemble              # mc_result record: scores + coverage + provenance
summary(result)         # data.frame from coverage (free if scorers recorded it)
augment(result, data)   # join scores to analysis tables
```

| Bucket | Role |
|---|---|
| **Linear engine** | Impute policy -> subset probes -> sum(w*x) + intercept -> optional transform |
| **Transform modules** | e.g. Zhang `sample_scale`: row moments on **full** matrix, apply to coef subset only |
| **Family orchestrators** | GrimAge / SystemsAge / DNAmFitAge composite: pack UX, shared work, multi-column return |
| **Sex-routed aliases** | The 7 DNAmFitAge stems: no weights of their own; select a member per sample |
| **One-offs** | `external_package`, `custom` (MiAge) |

Packs may own their orchestration (shared intermediates, column assembly) but call the shared
linear/impute helpers for every linear sub-step -- imputation lives in exactly one place.

**Memory:** pass the raw beta into scorers; no global intersect/copy in `calc_clocks`. Each
scorer subsets to the probes it needs (small copy). Do not micro-optimize further until
profiling says so.

**Full-panel notice:** hard-coded to `Zhang2019` (the only `sample_scale` clock today) -- a
`message()` (not a warning) that its moments are computed over all CpGs but a big-enough subset
usually suffices. No generic flagged-clock warning; not on every call.

Details, imputation table, coverage/`summary()`, GrimAge pack policy, batch rules ->
[`detail-plan.md`](detail-plan.md).

---

## Public API (summary)

| Function | Purpose |
|---|---|
| `list_clocks()` / `get_clock()` / `get_clock_probes()` | Discover and inspect |
| `calc_clocks(DNAm, clocks, pheno = NULL, ...)` | Score -> `mc_result` record |
| `summary(x)` | Coverage table (per-role needed / used / imputed / missing) |
| `augment()` | Join scores to phenotype / analysis data |
| `clear_mc_cache()` + download helpers | Heavy assets |
| Optional legacy `calc*()` | Thin -> `calc_clocks`; not the engine |

`calc_clocks()` returns an S3 record over `list` (class `"mc_result"`): `$scores` (n x k
double), `$coverage`, `$provenance`. Verbs are methods (`as.matrix`, `as.data.frame`, `[`,
`cbind`, `augment`, `summary`, `codebook`, `citation`, `print`) -- so subsetting never
silently drops coverage/provenance. Results are **scores only** (no auto-appended pheno). Align
pheno by sample id, never row order. `rownames(DNAm)` is the canonical sample id; rowname-less
DNAm gets inline positional ids (`sample1..N`) unless `allow_positional_ids = FALSE`, and such
records are refused by `cbind` (footgun closed at the bind step, not the front door). Canonical
covariates: `Age`, `Female` (0/1).

The sysdata schema is the **accessor layer** (`get_clock`, `clock_scoring_cpgs`, ...) plus a
structural test -- not a hand-written schema doc. Accessors read the catalog with `[[` (never
`$`, which partial-matches) and resolve declared pointers rather than searching for them.
Covariate requirements are one flattened catalog field, read once, never re-derived in the
scoring path.

**Callable pool != catalog.** Some clock_ids exist only as routing targets: the 14 sex-resolved
DNAmFitAge members are scored and returned as columns, but requesting one by name is a hard error
naming its alias (`DNAmGrip_wAge_Female` -> use `DNAmGrip_wAge`), because a one-sex model returns
a plausible number for the other sex rather than failing. `"all"` and group ids expand to
callables only. A planned discovery helper (available options + Levenshtein "did you mean") reads
the same routing tables, so the pool, the refusal and the suggestion cannot drift apart.

**Coverage never describes a sample it is not true of.** A clock assembled from other clocks'
scores reports coverage only when every component contributes to every sample; a sex-routed alias
therefore reports none (its members cover disjoint halves of the cohort) and coverage stays on
the members -> [`detail-plan.md`](detail-plan.md) sec 4.

---

## Packaging (summary)

| Tier | What | Where |
|---|---|---|
| Bundled | Catalog + small tensors | `R/sysdata.rda` |
| External | SystemsAge, PCClocks, PCBrainAge | Release assets + user cache |

No install/check-time network. Sync via `data-raw/sync.R` (a gitignored `lockfile.rds` skips only
external-pack rebuild; not a product pin).

Where the upstream contract does not match what a caller needs, sync adapts it in a **small closed
registry** rather than pushing a change upstream or adding a runtime code path: `CUSTOM_GROUPS`
(MiAge's frozen payload) and `attach_sex_routed_aliases()` (one alias per `routing.sex` stem).
Both emit ordinary catalog entries, so nothing downstream is special-cased.

---

## Testing (summary)

| Tier | Runs where | Job |
|---|---|---|
| Engine units + `sim_DNAm` smoke | Always (no meta dependency) | `linear_score` arithmetic, impute accounting, accessors, coverage math, result methods (golden values hand-authored in-test); plus `sim_DNAm` `expect_no_error` over every shipped clock |
| Parity fixtures | `MC_PARITY=1` + cohort staged (`file.exists` gate); dev `test_parity()` | Upstream golden fixtures vs `cohort_EPIC/beta.duckdb` -- the single clock-golden source |

No shipped slice of the golden cohort (it would drift). CI may stage the cohort and run parity;
CRAN skips it. Details -> [`detail-plan.md`](detail-plan.md) sec 10.

---

## Implementation sequence (high level)

1. Accessor layer over `sysdata` (executable schema) + catalog readers.
2. Prepare path + result record + `summary()`.
3. Linear engine + impute policies + fixture batch for `cpg_coefficient`.
4. Zhang-style pre-transform into linear engine.
5. GrimAge / SystemsAge orchestrators; then other packs as needed.
6. External + MiAge; asset resolver. **(done)**
7. Full fixture suite; optional legacy wrappers; CRAN cleanup. **(current)**

Per-clock status: `dev/clock_tracker.csv`.

---

## Non-goals (short)

No new per-clock exported calculators as the real API; no recipe-walker runtime; no pheno tables
from scorers; no silent downloads; no float32 coefs; no Bioconductor; no SHA/pin as result
provenance; no rewriting published clock math; no crossing the impute sources (partial=cohort,
absent=vendor); no `$` on catalog structures; no searching for a payload an accessor should have
had declared; no coverage figure that is true of no sample.

---

## Doc map

| File | Contents |
|---|---|
| **This file** | Overview and pointers |
| [`detail-plan.md`](detail-plan.md) | Full design: API, engines, memory, packs, sync, fixtures, sequence |
| [`DECISIONS.md`](DECISIONS.md) | Dated why/reversals -- the only home for superseded design |
| `clock_tracker.csv` | Temporary per-clock agent board |
| `legacy/` | Frozen pre-rewrite `R/` sources |
