# mc_provenance
# mc_groups
# mc_catalog |> lengths()
# mc_bundles |> lengths()
# mc_catalog$DNAmIC
#
# mc_catalog |> sapply(\(x) {x$computation_type})

# mc_catalog$DunedinPACE$probe_sets
calc_clocks <- function(DNAm, clocks, pheno = NULL, pheno_id = NULL,
                        allow_positional_ids = TRUE, ...) {
}

# input
clocks <- "Bohlin"
set.seed(1234)
sim <- sim_DNAm(clocks = clocks)
DNAm <- sim$DNAm
pheno <- sim$pheno
pheno_id <- "ID"
# function body
clock_ids <- resolve_clocks(clocks)

# sample identity (inlined boundary handling). rownames(DNAm) is the canonical, preferred id.
# Identity-less DNAm is not a hard error by default: stamp positional ids sample1..N so less-defensive
# workflows can score by row order. positional_ids flows to $provenance$positional_ids and makes
# cbind.methylCIPHER refuse the record (footgun closed at the bind step). allow_positional_ids = FALSE
# restores the strict hard-error contract. Capture positional-ness BEFORE stamping.
positional_ids <- is.null(rownames(DNAm))
if (positional_ids) {
  if (!allow_positional_ids) {
    stop(
      "DNAm has no rownames. Set them, or pass ",
      "`allow_positional_ids = TRUE` to score with positional ids (sample1..sampleN).",
      call. = FALSE
    )
  }
  rownames(DNAm) <- paste0("sample", seq_len(nrow(DNAm)))
}

# DNAm check
check_DNAm(DNAm) # universal invariants (rownames now non-NULL)
check_DNAm_extra(DNAm, clock_ids) # Zhang2019 and etc.

# union of covariate names across resolved clocks
extra_columns <- unique(unlist(lapply(clock_ids, clock_covariates_required)))
# pheno: validate dtypes (mode-aware), then align onto sample_id. id mode -> join on pheno_id
# (superset ok); positional mode -> row-order join, requires nrow(pheno) == nrow(DNAm).
check_pheno(pheno, ID = pheno_id, extra_columns = extra_columns, positional = positional_ids)
pheno <- resolve_pheno(DNAm, pheno, pheno_id, positional_ids)
pheno
