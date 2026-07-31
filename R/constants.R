# constants read from more than one file. a value used in exactly one file stays
# next to its caller -- this file is for the shared ones only.

# reserved batch label: both coverage frames, provenance, the formula namespace
MC_BATCH <- "mc_batch_id"

# schemes expressible as a declared panel + a vendored target
NORM_SCHEMES <- c("quantile", "bmiq")

# schemes score_normalized() implements (quantile routes via Dunedin)
NORM_SCHEMES_ROUTED <- "bmiq"

# schemes that are part of the clock's definition and cannot be declined
NORM_CONSTITUTIVE <- "quantile"

# schemes that fill an absent background cpg with the target value
NORM_SCHEMES_FILL <- "quantile"
