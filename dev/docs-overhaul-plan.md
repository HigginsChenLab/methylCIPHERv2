# Docs overhaul plan

Branch: `docs-overhaul`. Written 2026-09-17.

This file is a staging doc, not a record. It is force-added past the `dev/*` ignore so the branch
carries it, and it is deleted in the last stage before the PR merges. Nothing here is a rule until
it lands in `.claude/CLAUDE.md` or a rules file.

## Why

`.claude/CLAUDE.md` is 1237 lines and 107 KB, roughly 27k tokens, loaded in full at every session
start and again by every non-Explore subagent, including each `/code-review` reviewer. The Claude
Code docs give a target of under 200 lines per file and say longer files reduce adherence.

Where the weight sits (chars):

| Section | Size | Share |
|---|---|---|
| Non-negotiable invariants | 56k | 53% |
| Testing | 19k | 18% |
| sync.R workflow | 12k | 12% |
| everything else | 17k | 16% |

One bullet, "Result is an S3 record", is 25.6k on its own. The file carries 80 `(DECISIONS <date>)`
tags and 126 dated lines.

Diagnosis: the header promises "the rule and the shortest reason" and no evidence. When the
decision log left git, this file became the only tracked home for the why, and it absorbed the
log: measurements, reversal stories, and standing-state snapshots. Drift is already visible (a
doubled `$per_clock`, the trim quoted as both 799 and 801, a stale memory note about check).

## Decisions already made

1. Evidence and history move to a tracked `dev/RATIONALE.md`. It is keyed by rule and never by
   date, it is closed against the rules (an entry exists only if a rule cites it, and deleting the
   rule deletes the entry), and it holds only what could already be public. It is not the retired
   decision log and must not be named like it. Change rationale still goes in commit messages.
2. The `(DECISIONS <date>)` tags become slugs that resolve to a heading in that file, written
   `(why: slug)`. The date moves into the entry.
3. Snapshots (test counts, block counts, token-set sizes, skip counts) are deleted, not moved. A
   dated measurement is evidence and stays true; a standing count rots.
4. Area rules move to path-scoped files under `.claude/rules/`, loaded when a matching file is
   read. The core keeps only cross-cutting rules and workflow bans.
5. No separate architecture map. The `paths:` line of each rules file is the slice's file list, the
   "looks wrong, is decided" list sits in the same rules file, and the `calc_clocks()` spine is a
   short block in the core.
6. No `REVIEW.md`. Only the managed GitHub review reads it, it must sit at the repo root, and a
   root markdown file risks becoming a pkgdown page. Revisit only if that product is adopted.
7. Nothing is cut until the audit table has been read and its verdicts approved.

## Verified facts (Claude Code docs, checked 2026-09-17)

- `.claude/rules/*.md` load at launch unless frontmatter carries `paths:` globs. A scoped file
  loads when Claude reads a matching file. A file with no `paths:` loads always, so the rationale
  file must not live in that folder.
- `@path` imports load eagerly at launch and save no context.
- Nested `CLAUDE.md` files load on demand, but cannot split `R/`, which is one flat directory.
- Non-fork subagents receive the whole CLAUDE.md hierarchy. Explore and Plan skip it.
- Local `/code-review` runs as a background subagent, follows CLAUDE.md, does not read
  `REVIEW.md`, and accepts a file path, PR number, branch, or ref range as target.

Not documented, so tested in stage 0 or treated as unknown:

- Whether scoped rules fire inside the `/code-review` subagent.
- Whether a `/code-review` target can be several paths.
- Whether the ultra cloud variant sees untracked files or honors CLAUDE.md.

## Target layout

```
.claude/CLAUDE.md            core: what the package is, getting started, cross-cutting rules,
                             workflow bans, the spine, an imperative index of the rules files
.claude/rules/<area>.md      one per area, with paths: globs. Rules first, then the
                             "looks wrong, is decided" list. No evidence.
dev/RATIONALE.md             one heading per slug: rule in one line, date decided, evidence,
                             rejected alternatives
dev/WRITING.md               unchanged in role, light pass only
```

Draft areas, to be fixed in stage 2: front door and gates, engine and branches, normalization
and kernels, record and bind, coverage, exits and print, catalog and accessors, assets, sync
(`data-raw/**`), testing (`tests/**`).

The index in the core is an instruction: before editing, reviewing, or designing in an area, read
its rules file by hand. This covers an agent that never reads a matching file, and it covers the
reviewer subagent whatever stage 0 finds.

Size target for the core: near 200 lines. This is a target, not a measurement.

## Stages

Each stage ends with a stop for approval unless marked otherwise.

### Stage 0 - canary

Make one throwaway scoped rules file holding a distinctive sentence. Run `/code-review` at low
effort on a matching file and see whether the sentence reaches the reviewer. In the same run, test
whether the target accepts more than one path. Record both answers in this file. Delete the canary.

Exit: both unknowns answered. If scoped rules do not fire in the reviewer, the layout stands and
the core index carries the load, but each rules file gains a line saying so.

### Stage 1 - deep audit of CLAUDE.md (read-only)

Walk the file paragraph by paragraph and produce `dev/docs-overhaul-audit.md`, one row per block:

| Column | Meaning |
|---|---|
| location | heading and line range |
| size | chars |
| kind | rule, reason, guard, evidence, history, snapshot, shipped-behavior, workflow |
| checkable | can a reviewer test this against a diff, yes or no |
| verified | every named function, constant, and file still exists in the tree |
| verdict | keep, compress, move, delete |
| destination | core, a rules area, a rationale slug, or nowhere |

Kinds, and what happens to each by default:

- rule, guard ("do not simplify X back"), one-clause reason: keep, in imperative wording.
- evidence (a measurement, a bit-flip count, a timing): move to the rationale entry.
- history and tombstones ("it was X until <date>", "reversing the same-day decision"): move to
  the rationale entry, or delete where the rule no longer leans on it.
- snapshot: delete.
- shipped-behavior (a description of what the code does that the code already states): delete,
  unless it is the only warning against a silent wrong answer.
- duplicate statements of one rule: one home, the rest removed.

The test for every sentence: would an agent act differently without it. If no, it does not stay in
a loaded file.

Also in this stage: list contradictions and typos found, and list every `dev/to-do.md` id cited,
since those stay unresolvable for anyone without the file.

Exit: the table, a proposed slug list, and a size forecast per destination. Approval of verdicts.

### Stage 2 - fix the partition

Settle the area list and write each area's `paths:` globs. Every `R/*.R` and `src/*.cpp` file
matches at least one area. Files that belong to two areas are named and the overlap is accepted or
resolved. Decide which rules are cross-cutting and stay in the core.

Exit: the area table. Approval.

### Stage 3 - trim and move

One commit per area, smallest first, so the pattern is proven before the hard cases. For each:
write the rules file, write the rationale entries it cites, remove the text from CLAUDE.md. The
"Result is an S3 record" bullet goes last. Then rewrite the core: header, spine, index.

Rules for the trim:

- Every explicit "do not" survives with its one-clause reason.
- A rule is worded so its check is obvious.
- No dates in a loaded file except inside a `(why: slug)` target.
- No counts that a sync or a new test can move.

Exit: CLAUDE.md near target size, all areas written. Approval of the diff per area.

### Stage 4 - rewrite the docs-about-docs

The "Source-of-truth docs" section currently forbids a decision file. Rewrite it to say what
`dev/RATIONALE.md` is and why it is not the retired log. Add `!dev/RATIONALE.md` to `.gitignore`
and fix the comment block above it. Confirm `.Rbuildignore` already covers `dev` and `.claude`.
Drop the header sentence that says a `(DECISIONS <date>)` tag is not a pointer.

### Stage 5 - make drift a test failure

Add to `tests/testthat/test-source-hygiene.R` (already `.Rbuildignore`d):

- every `R/*.R` and `src/*.cpp` file matches some rules file's globs,
- every `(why: slug)` resolves to a heading, and every heading is cited,
- every backticked `fn()` in CLAUDE.md and the rules files is defined in `R/`.

Keep it to these three. The suite has a budget.

### Stage 6 - related docs

Light pass over `dev/WRITING.md` with the same kinds (it loads on demand, so the bar is lower).
Consolidate the memory files: at least `never-run-r-cmd-check` and `external-scoring-focus` are
stale. Local-only `dev/` files are out of scope.

### Stage 7 - verify

- `devtools::test()` green. Check is not run unless asked.
- Measure core and per-area sizes against the forecast.
- Re-run the stage 0 canary against a real rules file.
- Fresh-agent probe: ask a new subagent a handful of questions whose answers lived in cut text
  (why `rbind` reconciles nothing, why there is no `below_min` column, why `not_finite` excludes a
  plain `NA`) and confirm each rule is still found and its reason still reachable.

### Stage 8 - first `/code-review`

Slice by slice, as the first real user of the layout. Order: kernels and normalization, engine
and branches, front door and gates, record and bind, coverage, exits and print, catalog, assets.
`data-raw/sync.R` last or not at all. Findings that contradict a documented decision are a signal
the rules file needs a "looks wrong, is decided" line, not a code change.

### Stage 9 - close out

Delete this file and the audit file. Open the PR with the rationale for the restructure in the body.

## Risks

- **Over-trimming.** Evidence is part of what stops an agent reversing a decision. Mitigation: the
  guard sentences stay, the slug is one hop away, and stage 7 probes for it.
- **Scoped rules not loading where expected.** Mitigation: the imperative index, and stage 0.
- **The rationale file growing into a log.** Mitigation: the closure rule and its hygiene check.
- **A second partition drifting from the first.** Mitigation: there is only one; the globs are it.

## Out of scope

Any change under `R/`, `src/`, or `data-raw/`. The contents of `dev/to-do.md` and the local
decision log. A `REVIEW.md`. Restructuring `R/` into subdirectories.
