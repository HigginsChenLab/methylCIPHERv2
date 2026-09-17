---
paths:
  - "R/predict_sex.R"
---

# predict-sex

`predict_sex()` and the karyotype call it builds from the two `DNAmSex_Wang` scores. It is
composition over `calc_clocks()`, and it returns a data.frame, not a record.

## Rules

- **The frame carries `<score>_coverage` and `<score>_note` for each score, and stays a
  data.frame.** Per clock, never summarized across the pair. The two panels are of very different
  sizes, so one `min()` would put one number on two panels where it means different things, and
  it would erase the case where one chromosome's probes were kept and the other's were stripped
  (why: predict-sex-columns).
- **`_note` is not redundant with `_coverage`.** The Wang branch emits `fit_spread`, so a sample
  can read full coverage and still score `NA`.
- **`clocks_coverage()` is not joined, and cannot be.** It has no sample axis, so every column it
  contributed would be constant down the frame.
- **Euploidy is read from the declared `euploid` map, never from a label's text.**
  `karyotype_euploid()` reads what sync validated and attached. A string test on the karyotype
  label fails soft: it classifies a label it does not recognise, where a missing declaration
  stops with a `catalog_bug()` (why: euploid-is-declared).
- **`BINARY_CALLS` is not a leftover.** Nothing declares which emitted label a binary `Female`
  column records as, and deriving it would mean testing the karyotype string for `XX`. It does
  that one job. `sex_mismatch` gates on the declared euploidy, not on it.
- **`sex_aneuploidy` is `NA` for an unscorable sample, where `sex_mismatch` is `FALSE`.** No call
  is not a disagreement. It is also not a euploid verdict.

## Looks wrong, is decided

- `attach_coverage()` calls the internal `sample_coverage_rows()` and not the exported
  `samples_coverage()`. The export would warn a second time about a fact `calc_clocks()` already
  warned about. The coverage rules hold the full rule.
- `recorded_from_female()` carries a `checkmate` assertion although it is internal. It reads
  `pheno$Female`, which no export validated on the way in.
- `predict_sex()` takes `DNAm` and is still not a second beta reader. It touches the matrix only
  through `calc_clocks()`.
- `Female` is read from the caller's `pheno`, not from the record. The record keeps only the
  covariates the run required, and the two Wang clocks require none.
- A sample no rule matches gets the declared default label, `Female`. That is the published
  classifier, and it is why upstream cannot declare `Female` as positively euploid.
