# CLAUDE.md

Guidance for Claude Code working in this repository. This file holds **invariants** that
rarely change. Volatile detail (per-clock status, exact designs, dated reversals) lives in the
`dev/` planning docs -- see "Source-of-truth docs" below and prefer those for specifics.

## What this package is

`methylCIPHER` scores CpG-based DNA-methylation ("epigenetic clock") ages. One public scorer,
`calc_clocks()`, drives everything. The scoring contract (clock catalog + coefficient tensors)
is synced from the separate `methylCIPHER-meta` repo; fixtures are the scientific gate.
Target is **CRAN**, not Bioconductor. R (>= 4.4).

## Getting started (collaborators)

`R/sysdata.rda` (the compiled clock catalog) is **committed**, so you can develop, load, and test
without the `methylCIPHER-meta` repo or any downloads. Only regenerating the catalog needs `sync()`
(see below), and you do not need that to contribute.

```r
# from the package root, in R:
install.packages("pak")
pak::local_install_deps(dependencies = TRUE)  # reads DESCRIPTION incl. GitHub-only Remotes
devtools::load_all()      # attach the package for interactive work
devtools::document()      # regenerate NAMESPACE + man/ from roxygen; run after any export/doc change
devtools::test()          # always-on test tiers (cohort parity auto-skips if not staged)
devtools::check()         # full R CMD check
```

Optional/soft deps (`betanorm`, `duckdb`, `DBI`, `curl`) back specific paths only; tests skip
cleanly when they are absent.

## Non-negotiable invariants

Do not reverse these without a `dev/DECISIONS.md` entry explaining why.

- **One engine + a finite, closed branch set.** Every work unit routes on the catalog pair
  `(weights_format, computation_type)` to a shared `linear_score()` or a named branch
  (pre-transform, sex-split, family orchestrator, external, custom). There is **no** recipe
  interpreter / walker, not even as a fallback.
- **Result is an S3 record over `list`** (class `methylCIPHER`): `$scores` (n x k double),
  `$coverage`, `$provenance`. Never a `matrix` subclass (it drops class + attrs on first subset).
  All verbs are methods (`as.matrix`, `as.data.frame`, `[`, `cbind`, `augment`, `summary`, ...).
- **Scores only.** No auto-appended phenotype columns. Align pheno by sample id, never row order.
- **Imputation lives in one place and never crosses sources.** Partial NA on a present probe ->
  cohort mean (shared cache); a fully absent probe -> the clock's vendored ref, or drop by policy.
- **Accessors are the executable schema.** `calc_clocks` consumes accessors
  (`get_clock`, `clock_coefs`, ...), never raw nested catalog lists. No hand-written `schema.md`.
- **No network at install / build / check / CRAN test.** Double-precision coefficients only.
- **No commit SHA / pin as result provenance.** Correctness is proven by fixtures.
- **`NAMESPACE` and `man/*.Rd` are generated, never hand-edited.** Edit the roxygen comments in
  `R/*.R` and run `devtools::document()` after any change to exports or docs (roxygen2 8.0.0).

## sync.R workflow (`data-raw/sync.R`)

Pulls the scoring contract from `methylCIPHER-meta` into the package. Not run at build/check --
a maintainer runs it explicitly and commits the regenerated `R/sysdata.rda`. **You do not need
this to contribute** (the catalog is committed). Running `sync()` needs read access to
`methylCIPHER-meta` (private, pre-release); `sync(upload = TRUE)` additionally needs a GitHub
token with release-write scope and is maintainer-only.

- **Remote:** `https://github.com/hhp94/methylCIPHER-meta.git`.
- **Inputs R may read:** `manifest.json`, `weights/**`, `bibliography/{papers.csv,clocks.bib}`.
  **Never** `control/`, `papers/`, or `scripts/`.
- **Entry point:** `sync(source_git_sha = NULL, upload = FALSE, force = FALSE)`.
  1. Resolve + checkout meta at `source_git_sha` (clone under `data-raw/methylCIPHER-meta/`).
  2. **Always** rebuild catalog + accessor backing objects + small bundles -> `R/sysdata.rda`.
     There is no build-skip cache; the rebuild is ~2s. (`manifest_key` was removed 2026-07-20.)
  3. **External packs** (SystemsAge, PCClocks, PCBrainAge): if `force = FALSE` and
     `data-raw/assets/lockfile.rds` hits (same `source_git_sha` and every staged pack still on
     disk), reuse them; else rebuild the three content-addressed `<group>-<payload_hash>.qs2`
     packs and rewrite the lockfile.
  4. `upload = TRUE` publishes packs to GitHub Releases. Reupload is idempotent: the
     `payload_hash` content-address (filename -> release tag) plus the remote "asset already
     present" skip mean unchanged weights are never re-uploaded.
- **Distribution tiers:** small groups ship **bundled** in `R/sysdata.rda`; the three heavy
  packs ship **external** as release assets, cached at runtime in
  `tools::R_user_dir("methylCIPHER", "cache")`. No silent first-use download.
- **Identity keys:** `payload_hash` (external-pack content-address) and `file_sha256` (runtime
  download integrity, shipped in `mc_provenance`). Both stay maintainer-side; neither reaches a
  result record.
- **Gitignored, do not commit:** `data-raw/assets/` and `data-raw/methylCIPHER-meta/`.

## Testing

- **Always run, no meta dependency:** hand-authored engine/machinery unit tests (golden values
  written in-test) plus the `sim_DNAm()` `expect_no_error` smoke over every bundled clock.
- **Cohort-gated parity fixtures** (the only clock-golden source): run against
  `data-raw/methylCIPHER-meta/fixtures/cohort_EPIC/beta.duckdb`, skipped via `file.exists()`
  when the cohort is not staged. CRAN skips this tier; CI may stage it.

## ASCII-only

Write **plain ASCII** in every file you create or edit -- no "smart" punctuation or symbols.

- **Hard requirement** in package sources (`R/`, `man/`, `DESCRIPTION`, `NAMESPACE`, `tests/`,
  `data-raw/*.R`): non-ASCII triggers R CMD check warnings and breaks on Windows encodings.
- **Default everywhere else** (markdown, commit messages) too, for portability on this Windows /
  PowerShell setup. Use `--` not an em-dash, `->` not an arrow, `"section" / "sec"` not a section
  sign, `<=` / `>=` not the inequality glyphs, `x` not the multiplication sign, `<=` set-notation
  spelled out. (Some existing `dev/*.md` predate this rule and still contain such glyphs; do not
  add more, and prefer ASCII when editing those lines.)

## Comments

- Code comments are **short**: 1-2 sentences saying *what* the code does, not a rationale essay.
- The *why* behind a design, and every decision or reversal, goes **only** in `dev/DECISIONS.md` --
  never as a long explanatory comment in the source.

## Source-of-truth docs (`dev/`)

The whole `dev/` folder is local-only **except** these three, which are tracked (see `.gitignore`):

- `dev/migration-plan.md` -- compressed overview and pointers.
- `dev/detail-plan.md` -- **canonical** long-form design (API, engine, memory, packs, sync,
  fixtures). Prefer updating behavior specs **here**; keep the overview short.
- `dev/DECISIONS.md` -- append-only, newest-first, date-stamped log of **why** / reversals. Add
  an entry when a decision reverses a prior approach or is likely to be second-guessed; do not
  restate rules already in the plans.

The plans state **current truth only** -- superseded design is not annotated inline; its history
lives solely in `dev/DECISIONS.md`. When code and a plan disagree, the code is truth: fix the
plan and record the reconciliation in `dev/DECISIONS.md`.

Local-only (gitignored, not on a fresh clone): `dev/legacy/` (frozen pre-rewrite sources),
`dev/scratch.R`, `dev/clock_tracker.csv`, and the `dev/*.py` build scripts.

## Contributing

- Branch off `main` and open a PR; do not push directly to `main`.
- Run `devtools::document()` and `devtools::test()` before pushing.
- Reversing or second-guessing a design? Add a dated, newest-first entry to `dev/DECISIONS.md`.
- Keep new or edited content ASCII (see above).

## Environment and personal overrides

Keep **this** file environment-agnostic -- it is shared with collaborators on other operating
systems and shells, so it must not assume any one machine.

- The tracked `.Rprofile` auto-attaches `devtools` + `testthat` in interactive sessions. For a
  clean, profile-free parse or check, use `Rscript --vanilla` or `R CMD check`.
- Put machine-specific or personal notes (your OS, shell, local paths, private scratch workflow)
  in `CLAUDE.local.md`. It is gitignored and loaded automatically alongside this file, so it
  never reaches a collaborator.
