# dnam/pheno structure checks, run before any clock is resolved

# probe-id prefixes across 450K / EPICv1 / EPICv2 / MSA.
PROBE_ID_PREFIXES <- c("cg", "ch", "rs", "nv")

# EPICv2 and MSA suffix every probe with its address (cg00002033_TC11) and ship
# several rows per CpG. Matches all 937055 EPICv2 and all 281806 MSA ids, and
# nothing on EPICv1/450K, which carry no underscore at all.
PROBE_REPLICATE_SUFFIX <- "_[BT][CO][0-9]+$"

# orientation and replicate suffixes are whole-array properties -- every EPICv2
# and MSA id carries a suffix, no EPICv1/450K id does -- so a bounded stride
# sample decides both, and the cost does not grow with a 900k-column matrix.
id_sample <- function(x, n = 2000L) {
  if (!length(x)) {
    return(character(0))
  }
  if (length(x) <= n) {
    return(x)
  }
  x[unique(as.integer(seq(1L, length(x), length.out = n)))]
}

has_probe_ids <- function(x) {
  length(x) > 0L &&
    any(vapply(
      PROBE_ID_PREFIXES,
      function(p) any(startsWith(x, p)),
      logical(1)
    ))
}

check_DNAm <- function(DNAm) {
  # dim/dimnames work on a data.frame too, so orientation and suffixes are
  # diagnosed before the matrix refusal -- a data.frame caller gets the real
  # problem, not just "not a matrix".
  d <- dim(DNAm)
  if (length(d) != 2L) {
    cli::cli_abort(
      "{.arg DNAm} must be two-dimensional, with samples in rows and CpGs
       in columns.",
      call = NULL
    )
  }
  cn <- id_sample(colnames(DNAm))
  rn <- id_sample(rownames(DNAm))
  cn_probes <- has_probe_ids(cn)
  rn_probes <- has_probe_ids(rn)

  # probe ids in the rows is decisive; more rows than columns is only
  # suspicious, since one clock over a large cohort is legitimately tall.
  transposed <- rn_probes && !cn_probes
  if (length(cn) && !cn_probes && (transposed || d[[1L]] > d[[2L]])) {
    cli::cli_warn(
      c(
        if (transposed) {
          "{.arg DNAm} looks transposed -- probe ids are in the rows."
        } else {
          "No {.arg DNAm} column names look like probe ids
           ({.val {PROBE_ID_PREFIXES}}), and there are more rows than columns."
        },
        "i" = "{.fn calc_clocks} reads samples from rows and CpGs from columns.
               Try {.code t(DNAm)} if yours is the other way around."
      ),
      call = NULL
    )
  }

  # EPICv2/MSA replicate probes. Panels are declared on the unsuffixed id, so a
  # suffixed column matches nothing and is filled or dropped as absent.
  suffixed <- cn[grepl(PROBE_REPLICATE_SUFFIX, cn)]
  if (length(suffixed)) {
    cli::cli_warn(
      c(
        "{.arg DNAm} carries EPICv2/MSA replicate suffixes, for example
         {.val {suffixed[[1L]]}}.",
        "i" = "Clock panels are declared on the unsuffixed id, so every
               suffixed column counts as absent and is vendor-filled or
               dropped by policy rather than read.",
        "i" = "Collapse replicates to one column per CpG before scoring.
               {.fn calc_clocks} does not do it for you -- that needs the
               array manifest."
      ),
      call = NULL
    )
  }

  if (is.data.frame(DNAm)) {
    conv <- if (transposed) "t(as.matrix(DNAm))" else "as.matrix(DNAm)"
    cli::cli_abort(
      c(
        "{.arg DNAm} is a data.frame; {.fn calc_clocks} needs a numeric matrix.",
        "i" = "Convert with {.code {conv}}.",
        if (!transposed && !cn_probes) {
          c(
            "i" = "Methylation tables usually ship CpGs as rows. Check the
                   orientation before converting."
          )
        }
      ),
      call = NULL
    )
  }

  checkmate::assert_matrix(
    DNAm,
    mode = "double",
    min.rows = 1,
    min.cols = 1
  )
  checkmate::assert_character(colnames(DNAm), unique = TRUE, null.ok = FALSE)
  # sample ids are mandatory
  if (is.null(rownames(DNAm))) {
    cli::cli_abort(
      c(
        "{.arg DNAm} needs sample ids as rownames so scores can be matched
         to samples.",
        "i" = "If the rows are anonymous, you can name them with:
               {.code rownames(DNAm) <- paste0(\"sample\", seq_len(nrow(DNAm)))}"
      ),
      call = NULL
    )
  }
  checkmate::assert_character(rownames(DNAm), unique = TRUE, null.ok = FALSE)
  invisible(NULL)
}

# note when a clock scores against the whole matrix, not its panel.
note_full_panel_clocks <- function(clock_ids) {
  full <- clock_ids[vapply(clock_ids, clock_needs_full_panel, logical(1))]
  if (!length(full)) {
    return(invisible(full))
  }
  cli::cli_inform(
    c(
      "i" = "{.val {full}} score{cli::qty(full)}{?s/} against every column of
             {.arg DNAm}, not just {cli::qty(full)}{?its/their} own panel.",
      "i" = "Pass every CpG you measured -- a pre-subset {.arg DNAm} changes
             {cli::qty(full)}{?this/these} score{?s}."
    )
  )
  invisible(full)
}

# pheno structure checks
check_pheno <- function(
  pheno,
  ID = NULL,
  extra_columns = NULL,
  sample_id = NULL
) {
  if (is.null(pheno)) {
    return(invisible(NULL))
  }
  checkmate::assert_data_frame(pheno, min.rows = 1)
  # front-door pheno structure, so cli -- and checkmate's own message here reads
  # "Assertion on 'ID' failed", naming an argument the caller never typed.
  if (!ID %in% names(pheno)) {
    cli::cli_abort(
      c(
        "{.arg pheno} has no column {.val {ID}} to match samples on.",
        "i" = "{.arg pheno_id} names the id column; {.arg pheno} has
               {.field {names(pheno)}}."
      ),
      call = NULL
    )
  }
  # the expression deparses to pheno[[ID]], which names an internal argument --
  # so this is one of the few sites that needs .var.name spelled out
  checkmate::assert_character(
    pheno[[ID]],
    any.missing = FALSE,
    unique = TRUE,
    null.ok = FALSE,
    .var.name = paste0("pheno$", ID)
  )
  # required covariates must exist -- the score branches read them unguarded
  miss <- setdiff(extra_columns, names(pheno))
  if (length(miss)) {
    cli::cli_abort(
      c(
        "{.arg pheno} is missing {length(miss)} column{?s} the requested
         clocks need: {.field {miss}}.",
        "i" = "Add {cli::qty(miss)}{?it/them} to {.arg pheno} and try again."
      ),
      call = NULL
    )
  }
  if ("Female" %in% extra_columns) {
    checkmate::assert_integerish(
      pheno[["Female"]],
      lower = 0,
      upper = 1,
      null.ok = FALSE,
      any.missing = TRUE
    )
  }
  if ("Age" %in% extra_columns) {
    checkmate::assert_numeric(
      pheno[["Age"]],
      finite = TRUE,
      null.ok = FALSE,
      any.missing = TRUE
    )
  }
  warn_missing_covariates(pheno, ID, extra_columns, sample_id)
  invisible(NULL)
}

# warn on NA in required covariates
warn_missing_covariates <- function(
  pheno,
  ID,
  extra_columns,
  sample_id
) {
  cols <- intersect(extra_columns, names(pheno))
  if (!length(cols)) {
    return(invisible(NULL))
  }
  # only rows that survive the id-join
  rows <- if (is.null(sample_id)) {
    seq_len(nrow(pheno))
  } else {
    idx <- match(sample_id, pheno[[ID]])
    idx[!is.na(idx)]
  }

  n_na <- vapply(cols, function(cl) sum(is.na(pheno[[cl]][rows])), integer(1L))
  n_na <- n_na[n_na > 0L]
  if (!length(n_na)) {
    return(invisible(NULL))
  }

  cli::cli_warn(
    c(
      "Missing values in {length(n_na)} pheno covariate{?s}:",
      bullets(vapply(
        seq_along(n_na),
        function(i) {
          cli::format_inline(
            "{.field {names(n_na)[[i]]}}: {n_na[[i]]} sample{?s}"
          )
        },
        character(1L)
      )),
      "i" = "Those samples will score NA."
    ),
    call = NULL
  )
  invisible(NULL)
}

# align pheno by id-join. none supplied -> id column alone.
resolve_pheno <- function(DNAm, pheno, pheno_id, keep) {
  sample_id <- rownames(DNAm)
  out <- if (is.null(pheno)) {
    stats::setNames(data.frame(sample_id, stringsAsFactors = FALSE), pheno_id)
  } else {
    missing <- setdiff(sample_id, pheno[[pheno_id]])
    if (length(missing)) {
      cli::cli_abort(
        c(
          "{.arg pheno} is missing {length(missing)} sample id{?s} that appear
           in DNAm:",
          "x" = "{.val {utils::head(missing, 10L)}}",
          "i" = "Every DNAm row needs a matching id in the pheno id column."
        ),
        call = NULL
      )
    }
    # id column + required covariates only
    pheno[
      match(sample_id, pheno[[pheno_id]]),
      unique(c(pheno_id, keep)),
      drop = FALSE
    ]
  }
  # keyed by the id column, never by row names
  rownames(out) <- NULL
  out
}
