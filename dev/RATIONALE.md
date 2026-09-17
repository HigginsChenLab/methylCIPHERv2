# Rationale

The evidence and history behind the rules in `.claude/CLAUDE.md` and `.claude/rules/*.md`. Those
files state a rule and the shortest reason. This file holds what made the rule: the measurement,
the alternative that was tried and dropped, the date.

**It is not a decision log, and it must not become one.** Four things keep it from that:

- **It is keyed by rule, never by date.** One heading per slug. A rule cites its entry as
  `(why: slug)`. Entries are sorted by slug, so two authors touch different regions.
- **It is closed against the rules.** An entry exists only while a rule cites it. Delete the rule
  and the entry goes with it; git keeps the old text. Nothing here is append-only.
- **It is public.** Anything that cannot be read on the open web does not go in.
- **The rationale for a change still goes in the commit message and the PR body.** This file is
  for a rule that outlives the change that made it.

An entry holds no number the code, the catalog or a test run can produce on demand. A dated
measurement that decided something is evidence and belongs here.

Read an entry when you are about to argue with a rule. You do not need it to follow one.

## euploid-is-declared

Rule: euploidy is read from a declared `euploid` map, never parsed from a label's text. In
`.claude/rules/predict-sex.md`. Decided 2026-08-10.

Upstream declares the karyotype binding and deliberately does not declare `euploid`. `Female` is
the classifier's unconditional default, the label a sample gets when no rule matches, so upstream
cannot positively assert it as a euploid verdict. The sync side therefore states the fact itself,
in a hard-coded registry checked against every label the rule table can emit, and attaches the
map it validated.

Upstream's suggested alternative was a string test, `startsWith(karyotype, "46,")`. It was
refused. A string parse standing in for a flag fails soft: it silently classifies a label it does
not recognise. The assertion stops the build and names the offending label.

`BINARY_CALLS` survived this change for a reason of its own. The `euploid` map says which labels
are euploid. Nothing says which emitted label a binary `Female` column records as, and deriving
that would be the same string parse under another name.

## predict-sex-columns

Rule: `predict_sex()` carries a coverage column and a note column for each score. In
`.claude/rules/predict-sex.md`. Decided 2026-08-10.

Three narrower shapes were considered and dropped.

- One summary across the pair, such as the `min()` of the two coverages. The two panels differ in
  size by more than an order of magnitude, so the same number would mean different things on
  each. It would also hide the open case of a matrix that kept its chrX probes and had its chrY
  probes stripped, which is the case the columns exist to show.
- Coverage alone, without the note. The Wang branch records `fit_spread` for a sample with no
  spread across the reference domain. That sample reads full coverage and scores `NA`, and only
  the note says why.
- Joining `clocks_coverage()`. It has no sample axis, so each column it added would repeat one
  value down the frame.

The same day settled how the rows are obtained: from the internal frame builder, not from the
exported `samples_coverage()`, which would raise a second warning about a fact the run had
already reported. That rule lives with the coverage rules.
