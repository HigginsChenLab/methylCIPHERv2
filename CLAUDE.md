# CLAUDE.md

Guidance for Claude Code in this repo. This file holds **invariants** that rarely change.
Volatile detail (per-clock status, exact designs, dated reversals) lives in `dev/` -- see
"Source-of-truth docs" and prefer it for specifics.

## What this package is

`methylCIPHERv2` scores CpG-based DNA-methylation ("epigenetic clock") ages. One public scorer,
`calc_clocks()`, drives everything. The scoring contract (clock catalog + coefficient tensors) is
synced from the separate `methylCIPHER-meta` repo; fixtures are the scientific gate. Target is
**CRAN**, not Bioconductor. R (>= 4.4).

## Getting started (collaborators)

`R/sysdata.rda` (the compiled catalog) is **committed**, so you can develop, load, and test with no
meta repo and no downloads. Only regenerating it needs `sync()` (below), which you do not need to
contribute.

```r
# from the package root, in R:
install.packages("pak")
pak::local_install_deps(dependencies = TRUE)  # reads DESCRIPTION incl. GitHub-only Remotes
devtools::load_all()   # attach for interactive work (no document() -- roxygen deferred)
devtools::test()       # always-on tiers (cohort parity auto-skips if not staged)
devtools::check()      # full R CMD check
```

Soft deps (`betanorm`, `duckdb`, `DBI`, `curl`) back specific paths only; tests skip when absent.

## Non-negotiable invariants

Do not reverse these without a `dev/DECISIONS.md` entry explaining why.

- **One engine + a finite, closed branch set.** Every work unit routes on the catalog pair
  `(weights_format, computation_type)` to shared `linear_score()` or a named branch (pre-transform,
  family orchestrator, sex-routed alias, external, custom). There is **no** recipe
  interpreter/walker, not even as a fallback.
- **Result is an S3 record over `list`** (class `mc_result`): `$scores` (n x k double),
  `$coverage`, `$provenance`. Never a `matrix` subclass (drops class + attrs on first subset). All
  verbs are methods (`as.matrix`, `as.data.frame`, `[`, `cbind`, `augment`, `summary`, ...).
- **Scores only.** No auto-appended phenotype columns. Align pheno by sample id, never row order.
- **Imputation in one place, never crossing sources.** Partial NA on a present probe -> cohort mean
  (shared cache); a fully absent probe -> the clock's vendored ref, or drop by policy.
- **Accessors are the executable schema.** `calc_clocks` consumes accessors (`get_clock`,
  `clock_coefs`, ...), never raw nested catalog lists. No hand-written `schema.md`.
- **Read the catalog with `[[`, never `$`.** `$` partial-matches on lists, so a missing exact
  field silently resolves to a longer one (`entry$covariates` -> `covariates_required`) and the
  caller gets a wrong value, not an error. This is a hard rule in `R/accessors.R` and anywhere
  else catalog/pack/tensor structures are read. `options(warnPartialMatchDollar)` is **not** the
  fix -- a package cannot set a session global for its users and it does not fire under
  `R CMD check`.
- **Accessors read declarations; they never search.** No `grep`/regex/fuzzy match over tensor
  names, clock ids, or file paths to find a payload. Resolve the declared pointer (component,
  `probe_sets[[i]]$file`, `imputation$ref`) and `stop()` when it is absent or ambiguous -- an
  accessor that cannot find its declaration has done its job by failing. Searching hides an
  upstream/sync gap and can silently return a sibling clock's tensor.
- **Coverage is never reported for a sample it is not true of.** A clock assembled from other
  clocks' scores records coverage **iff every component contributes to every sample**
  (`GrimAgeV1`, `DNAmFitAge_{Sex}` do). Where components are selected per sample -- sex-routed
  aliases -- the entry is `NULL` and the per-sample column all-`NA`; coverage lives on the
  components, which appear as their own columns.
- **The callable pool is not the catalog.** Clocks that exist only as routing targets (the 14
  sex-resolved DNAmFitAge members) are internal machinery: scored, returned as columns, but a
  hard error if requested by name, pointing at their alias. The pool, the refusal and its
  suggestion all derive from one source (`sex_routed_members()`), so they cannot drift.
- **No network at install/build/check/CRAN test.** Double-precision coefficients only.
- **No commit SHA / pin as result provenance.** Correctness is proven by fixtures.
- **No roxygen yet.** Do not write roxygen blocks or run `devtools::document()`; use short `#`
  comments (see "Comments"). Turning roxygen on is a human-decided override tied to the alpha --
  no automatic trigger. `NAMESPACE` and `man/*.Rd` stay hand-managed; do not regenerate them.

## sync.R workflow (`data-raw/sync.R`)

Pulls the scoring contract from `methylCIPHER-meta` into the package. Not run at build/check -- a
maintainer runs it and commits the regenerated `R/sysdata.rda`. **You do not need this to
contribute** (the catalog is committed). `sync()` needs read access to `methylCIPHER-meta`
(private, pre-release); `sync(upload = TRUE)` also needs a release-write token (maintainer-only).

- **Remote:** `https://github.com/hhp94/methylCIPHER-meta.git`.
- **Inputs R may read:** `manifest.json`, `weights/**`, `bibliography/{papers.csv,clocks.bib}`.
  **Never** `control/`, `papers/`, or `scripts/`.
- **Entry point:** `sync(source_git_sha = NULL, upload = FALSE, force = FALSE)`.
  1. Resolve + checkout meta at `source_git_sha` (clone under `data-raw/methylCIPHER-meta/`).
  2. **Always** rebuild catalog + accessor objects + small bundles -> `R/sysdata.rda` (~2s, no
     build-skip cache).
     - Two **small closed registries** adapt the upstream contract package-side rather than
       asking upstream to change it: `CUSTOM_GROUPS` (a loader + component declaration for a
       `custom` group's frozen payload -- MiAge) and `attach_sex_routed_aliases()` (one alias
       clock per `_group.meta.json` `routing.sex` stem). Both run inside the build so everything
       downstream sees ordinary catalog entries. Add to a registry; do not add a code path.
     - Verify a sync change by **dry-running the build in memory first** (build catalog +
       bundles, diff every panel against the committed `R/sysdata.rda`) before regenerating.
  3. **External packs** (SystemsAge, PCClocks, PCBrainAge): reuse when `force = FALSE` and
     `data-raw/assets/lockfile.rds` hits (same `source_git_sha`, every staged pack on disk); else
     rebuild the three content-addressed `<group>-<payload_hash>.qs2` packs and rewrite the lockfile.
  4. `upload = TRUE` publishes packs to GitHub Releases; idempotent (content-address + remote
     "asset already present" skip mean unchanged weights are never re-uploaded).
- **Distribution tiers:** small groups ship **bundled** in `R/sysdata.rda`; the three heavy packs
  ship **external** as release assets, cached at runtime in
  `tools::R_user_dir("methylCIPHERv2", "cache")`. No silent first-use download.
- **Identity key:** `payload_hash` (pack content-address) only -- it sets the pack filename and
  release tag, which is what makes re-upload of unchanged weights a no-op. It stays maintainer-side
  and never reaches a result record. Transfer integrity and bit rot are qs2's own
  `validate_checksum`; there is no second hash and no runtime re-hash of a loaded pack.
- **Gitignored, do not commit:** `data-raw/assets/` and `data-raw/methylCIPHER-meta/`.

## Testing

Three tiers. Pre-alpha and fast-moving, so tests guard **core functionality and observable
output**, not implementation detail (see "Test altitude").

- **Crash smoke (always):** `test-sim-smoke.R` scores every bundled, supported clock in the
  **callable pool** (`resolve_clocks("all")`, not `names(mc_catalog)`) through `sim_DNAm()` +
  `calc_clocks()` with `expect_no_error`. Cheapest, most refactor-robust net; catches "a clock
  stopped running" without pinning a value. External clocks excluded (pack-only); routing targets
  are covered as their alias's dependencies.
- **Value goldens (always, no meta dep):** hand-authored engine/machinery unit tests with goldens
  written in-test, one per scoring path (linear sum/mean, sex-split, imputation offset, bundled
  composites). External-pack scoring is smoke-only here; parity owns those goldens.
- **Cohort-gated parity fixtures** (science gate; only clock-golden source): run against
  `data-raw/methylCIPHER-meta/fixtures/cohort_EPIC/beta.duckdb`, skipped unless BOTH
  `MC_PARITY=1` and the cohort is staged (`file.exists()`). Run locally via the dev-only
  `test_parity()` (`R/dev-utils.R`). CRAN skips this tier; CI must stage the cohort + set the flag.

### Test altitude -- keep tests loose enough to move fast

Assert what `calc_clocks()` *produces*, not how it is wired. A test that breaks on a no-behavior
refactor is too tight -- loosen or delete it.

- **Errors: assert *that*, not the wording.** `expect_error(expr)` with no regex. Pin a message or
  condition class only when a test must otherwise confuse two distinct failure modes.
- **No internal dispatch-tag tables.** Do not hard-code `clock_reduction()` / `score_type()` per
  clock; prove routing through output. The one allowed invariant: every catalog clock maps to a
  *known* tag.
- **No maintainer-side plumbing shapes.** Do not assert asset filenames, release tags, download
  URLs, or cache-dir order -- none reach a result. Test behavior (verifies on fetch, leaves no
  scratch, warns-not-stops on hash drift, closed set never downloads).
- **Re-derive a recipe in-test only until parity covers it.** Once a clock has a passing parity
  fixture, that fixture owns the numeric golden and only a smoke stays. In-test re-derivation is
  allowed where parity is still skip-listed -- the only numeric gate meanwhile.
- **Coverage counts and provenance flags are output** -- asserting
  `res$coverage$...$score_imputed_full` or `res$provenance$batch_set_id` is fair game.
- **Minimize test-helper files.** A fixture builder/mock lives atop the one test file that uses it;
  promote to `helper-*.R` only when >= 2 files genuinely share it (currently none). `sim_DNAm` /
  `random_betas` are package functions in `R/`, not test helpers.
- **Cohort/duckdb parity lives in one file** (`test-fixtures-parity.R`): a single file-scoped
  read-only connection behind the `MC_PARITY` + `file.exists()` guard, torn down with
  `withr::defer(..., testthat::teardown_env())` -- not a module-global caching env.
- **Random inputs are unseeded.** Build DNAm with `random_betas()` (no seed); goldens are computed
  in-test from that same matrix, so they are seed-invariant. Derive the golden from the input, do
  not add a seed to pin a value.

## ASCII-only

Write **plain ASCII** in every file you create or edit -- no "smart" punctuation or symbols.
Use `--`, `->`, `<=` / `>=`, `x` (not em-dash, arrow, inequality/multiplication glyphs), and spell
out set notation.

- **Hard requirement** in package sources (`R/`, `man/`, `DESCRIPTION`, `NAMESPACE`, `tests/`,
  `data-raw/*.R`): non-ASCII triggers R CMD check warnings and breaks on Windows encodings.
- **Default everywhere else** (markdown, commit messages) too, for portability. Some old `dev/*.md`
  lines predate this rule -- do not add more, and prefer ASCII when editing them.

## Comments

- Plain `#` comments are the only in-source docs right now -- no roxygen (see invariants).
- Keep them **short**: 1-2 sentences on *what* the code does, not a rationale essay.
- The *why*, and every decision or reversal, goes only in `dev/DECISIONS.md`.

## Source-of-truth docs (`dev/`)

The `dev/` folder is local-only **except** these three, which are tracked:

- `dev/migration-plan.md` -- compressed overview and pointers.
- `dev/detail-plan.md` -- **canonical** long-form design (API, engine, memory, packs, sync,
  fixtures). Put behavior specs here; keep the overview short.
- `dev/DECISIONS.md` -- append-only, newest-first, date-stamped log of *why* / reversals. Add an
  entry when a decision reverses a prior approach or is likely second-guessed; do not restate rules
  already in the plans.

Plans state **current truth only** -- superseded design is not annotated inline; its history lives
solely in `dev/DECISIONS.md`. When code and a plan disagree, the code is truth: fix the plan and
record the reconciliation in `dev/DECISIONS.md`.

Local-only (gitignored): `dev/legacy/` (frozen pre-rewrite sources), `dev/scratch.R`,
`dev/clock_tracker.csv`, and the `dev/*.py` build scripts.

## Contributing

- Branch off `main` and open a PR; do not push to `main`.
- Run `devtools::test()` before pushing. Do **not** run `devtools::document()` (no roxygen yet).
- Reversing or second-guessing a design? Add a dated, newest-first `dev/DECISIONS.md` entry.
- Keep new or edited content ASCII.

## Environment and personal overrides

Keep **this** file environment-agnostic -- it is shared across operating systems and shells.

- The tracked `.Rprofile` auto-attaches `devtools` + `testthat` in interactive sessions. For a
  clean, profile-free parse or check, use `Rscript --vanilla` or `R CMD check`.
- Put machine-specific or personal notes (OS, shell, local paths, private scratch) in
  `CLAUDE.local.md` -- gitignored, loaded automatically, never reaches a collaborator.
