# constants shared across files. single-use values stay next to their caller.

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
