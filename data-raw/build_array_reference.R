# build the compact array reference that qc_report() reads (maintainer-run).
# input: the TranslAGE DoQC array_ref.csv, itself built from the four Illumina
# manifests (450K, EPICv1, EPICv2, MSA) by DoQC's data/build_array_ref.py.
# output: inst/extdata/array_reference.rds, read at runtime via system.file().
#
# one row per bare locus (cg00050873, never cg00050873_BC11). EPICv2 and MSA
# ids carry an address suffix on the chip, and a matrix prepared for
# calc_clocks() has usually had it stripped, so the report matches on the bare
# locus and the suffix never decides the array.
#
# rows kept:
#   - every chrX / chrY locus on any of the four arrays (sex-chromosome coverage)
#   - the autosomal discriminating loci DoQC samples, 200 per sharing pattern.
#     the four only_<array> patterns are what infer the array. the shared
#     patterns only feed the per-array hit-rate table.

SRC <- Sys.getenv(
  "MC_ARRAY_REF_CSV",
  "../TranslAGE-workflows/WORKFLOWS/0_Preprocessing/03_DoQC/data/array_ref.csv"
)
OUT <- "inst/extdata/array_reference.rds"

ARRAYS <- c("450K" = "id_450k", EPICv1 = "id_epicv1", EPICv2 = "id_epicv2", MSA = "id_msa")
EXCLUSIVE <- c(
  only_450k = "450K",
  only_epicv1 = "EPICv1",
  only_epicv2 = "EPICv2",
  only_msa = "MSA"
)

bare <- function(x) sub("_[BT][CO][0-9]+$", "", x)

src <- utils::read.csv(SRC, stringsAsFactors = FALSE, na.strings = c("", "NA"))

# the bare locus of a row is the first id any array gives it
locus <- bare(Reduce(
  function(a, b) ifelse(is.na(a), b, a),
  lapply(ARRAYS, function(col) src[[col]])
))
if (anyNA(locus)) {
  stop("array_ref.csv has a row with no id on any array", call. = FALSE)
}

on <- lapply(ARRAYS, function(col) !is.na(src[[col]]))
chr <- ifelse(src[["row_type"]] == "sex_chrom", src[["chr"]], NA_character_)
excl <- unname(EXCLUSIVE[src[["disc_category"]]])

# replicate probes collapse onto one locus. any() over the rows keeps presence.
key <- factor(locus, levels = unique(locus))
first <- !duplicated(locus)
ref <- data.frame(
  locus = locus[first],
  chr = chr[first],
  exclusive = excl[first],
  stringsAsFactors = FALSE
)
for (a in names(ARRAYS)) {
  ref[[paste0("on_", a)]] <- as.vector(tapply(on[[a]], key, any))
}

# one locus, one chromosome: a disagreement is an upstream manifest problem
chr_n <- tapply(chr, key, function(v) length(unique(v[!is.na(v)])))
if (any(chr_n > 1L)) {
  stop("a locus maps to two sex chromosomes", call. = FALSE)
}

saveRDS(ref, OUT, compress = "xz", version = 2)
message(
  sprintf(
    "%s: %d loci (%d chrX, %d chrY, %d exclusive)",
    OUT,
    nrow(ref),
    sum(ref[["chr"]] %in% "X"),
    sum(ref[["chr"]] %in% "Y"),
    sum(!is.na(ref[["exclusive"]]))
  )
)
