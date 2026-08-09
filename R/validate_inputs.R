# dnam/pheno structure checks, run before any clock is resolved

# probe-id prefixes across 450K / EPICv1 / EPICv2 / MSA.
PROBE_ID_PREFIXES <- c("cg", "ch", "rs", "nv")

# EPICv2/MSA probe id with address suffix (cg00002033_TC11). no match on EPICv1/450K.
PROBE_REPLICATE_SUFFIX <- "_[BT][CO][0-9]+$"

# orientation and replicate suffixes are whole-array properties. a bounded stride sample decides both.
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
  # diagnose orientation and suffixes before the matrix refusal.
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

  # probe ids in the rows is decisive. more rows than columns is only suspicious.
  transposed <- rn_probes && !cn_probes
  if (length(cn) && !cn_probes && (transposed || d[[1L]] > d[[2L]])) {
    cli::cli_warn(
      c(
        if (transposed) {
          "{.arg DNAm} looks transposed. The probe ids are in the rows."
        } else {
          "No {.arg DNAm} column name looks like a probe id
           ({.val {PROBE_ID_PREFIXES}}), and the matrix has more rows than
           columns."
        },
        "i" = "{.fn calc_clocks} reads the samples from the rows and the CpGs
               from the columns.",
        "i" = "Use {.code t(DNAm)} if the matrix has the other orientation."
      ),
      call = NULL
    )
  }

  # EPICv2/MSA replicate probes. panels use the unsuffixed id.
  suffixed <- cn[grepl(PROBE_REPLICATE_SUFFIX, cn)]
  if (length(suffixed)) {
    cli::cli_warn(
      c(
        "{.arg DNAm} holds EPICv2 or MSA chip probes, for example
         {.val {suffixed[[1L]]}}.",
        "i" = "Most clocks need one column per CpG, so deduplicate the probes
               before you score.",
        "i" = "{.fn clock_cpgs} gives the CpGs a clock needs."
      ),
      call = NULL
    )
  }

  if (is.data.frame(DNAm)) {
    conv <- if (transposed) "t(as.matrix(DNAm))" else "as.matrix(DNAm)"
    cli::cli_abort(
      c(
        "{.arg DNAm} is a {.cls data.frame}. {.fn calc_clocks} needs a numeric
         {.cls matrix}.",
        "i" = "Convert the {.cls data.frame} with {.code {conv}}.",
        if (!transposed && !cn_probes) {
          c(
            "i" = "Most methylation tables hold the CpGs in the rows.",
            "i" = "Check the orientation before you convert."
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
  checkmate::assert_character(
    colnames(DNAm),
    any.missing = FALSE,
    unique = TRUE,
    min.chars = 1L,
    null.ok = FALSE
  )
  # sample ids are mandatory
  if (is.null(rownames(DNAm))) {
    cli::cli_abort(
      c(
        "{.arg DNAm} needs sample ids as {.fn rownames}.",
        "i" = "The score rows carry those ids.",
        "i" = "Name unnamed rows with
               {.code rownames(DNAm) <- paste0(\"sample\", seq_len(nrow(DNAm)))}."
      ),
      call = NULL
    )
  }
  # the other half of the pheno join key, held to the same rule as check_pheno's
  checkmate::assert_character(
    rownames(DNAm),
    any.missing = FALSE,
    unique = TRUE,
    min.chars = 1L,
    null.ok = FALSE
  )
  invisible(NULL)
}

# say_* emits to the user. mc_note_* records into the block's collector.
say_full_panel_clocks <- function(clock_ids) {
  full <- clock_ids[vapply(clock_ids, clock_needs_full_panel, logical(1))]
  if (!length(full)) {
    return(invisible(full))
  }
  cli::cli_inform(
    c(
      "i" = "{.val {full}} use{cli::qty(full)}{?s/} every column of
             {.arg DNAm}, not only {cli::qty(full)}{?its/their} own CpG list.",
      "i" = "Pass the full matrix you measured. A smaller set of columns
             changes {cli::qty(full)}{?this/these} score{?s}."
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
  # NA is allowed on purpose: a missing covariate warns and scores NA below,
  # rather than refusing the whole cohort
  checkmate::assert_data_frame(pheno, min.rows = 1, any.missing = TRUE)
  # front-door pheno structure (cli).
  if (!ID %in% names(pheno)) {
    cli::cli_abort(
      c(
        "The sample id column {.val {ID}} is not in {.arg pheno}.",
        "i" = "{.arg pheno_id} names the column that holds the sample ids.",
        "i" = "{.arg pheno} has {.field {capped_vals(names(pheno))}}."
      ),
      call = NULL
    )
  }
  # deparse names an internal arg. .var.name must be spelled out.
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
    # gated on extra_columns. units check fires only when age is consumed.
    warn_age_units(pheno, ID, sample_id)
  }
  warn_missing_covariates(pheno, ID, extra_columns, sample_id)
  invisible(NULL)
}

# age unit bounds at the edge of biological possibility.
AGE_MAX_YEARS <- 122
# pre-birth as a fraction of a year (-0.5, -1) is ok. gestational age in weeks is not.
AGE_MIN_YEARS <- -2

# rows of pheno that survive the id-join, in sample order.
joined_rows <- function(pheno, ID, sample_id) {
  if (is.null(sample_id)) {
    return(seq_len(nrow(pheno)))
  }
  id_index(sample_id, pheno[[ID]], "joined_rows", unmatched = "drop")
}

# per-row age units gate.
warn_age_units <- function(pheno, ID, sample_id) {
  rows <- joined_rows(pheno, ID, sample_id)
  age <- pheno[["Age"]][rows]
  ids <- as.character(pheno[[ID]][rows])
  # na is an unrecorded age, not a units error. Inf cannot reach here.
  ok <- !is.na(age)

  high <- ok & age > AGE_MAX_YEARS
  if (any(high)) {
    at <- which.max(replace(age, !high, -Inf))
    cli::cli_warn(
      c(
        "{sum(high)} of {length(age)} {.field Age} {cli::qty(sum(high))}value{?s}
         {?is/are} above {.val {AGE_MAX_YEARS}}.",
        "x" = "The largest is {.val {signif(age[[at]], 6)}}, for sample
               {.val {ids[[at]]}}.",
        "i" = "{.field Age} should be in years. {.val {AGE_MAX_YEARS}} is the
               verified human maximum.",
        "i" = "{.fn calc_accel} reads this column."
      ),
      call = NULL
    )
  }

  low <- ok & age < AGE_MIN_YEARS
  if (any(low)) {
    at <- which.min(replace(age, !low, Inf))
    cli::cli_warn(
      c(
        "{sum(low)} of {length(age)} {.field Age} {cli::qty(sum(low))}value{?s}
         {?is/are} below {.val {AGE_MIN_YEARS}}.",
        "x" = "The smallest is {.val {signif(age[[at]], 6)}}, for sample
               {.val {ids[[at]]}}.",
        "i" = "{.field Age} should be in years. A small negative value is
               normal for pre-birth samples, but these are lower than that."
      ),
      call = NULL
    )
  }

  # the flagged ids, on the same axis as sample_id
  invisible(ids[high | low])
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
  rows <- joined_rows(pheno, ID, sample_id)

  n_na <- vapply(cols, function(cl) sum(is.na(pheno[[cl]][rows])), integer(1L))
  n_na <- n_na[n_na > 0L]
  if (!length(n_na)) {
    return(invisible(NULL))
  }

  cli::cli_warn(
    c(
      "{length(n_na)} {.arg pheno} covariate{?s} {?has/have} missing values.",
      capped_bullets(seq_along(n_na), function(i) {
        vapply(
          i,
          function(k) {
            cli::format_inline(
              "{.field {names(n_na)[[k]]}}: {n_na[[k]]} sample{?s}"
            )
          },
          character(1L)
        )
      }),
      "i" = "A sample with a missing covariate scores {.code NA} for the
             clocks that need it.",
      if ("Female" %in% names(n_na)) {
        c(
          "i" = "{.fn predict_sex} estimates sex from {.arg DNAm} when
                 {.field Female} is unknown."
        )
      },
      "i" = "Fill the column in {.arg pheno} before you score."
    ),
    call = NULL
  )
  invisible(NULL)
}

# point the canonical covariate names at the caller's own columns.
# runs at the top of a front door, so every downstream read sees canonical names.
canonicalize_covariates <- function(pheno, covariates, reads, arg = "pheno") {
  if (is.null(covariates)) {
    return(pheno)
  }
  checkmate::assert_character(
    covariates,
    any.missing = FALSE,
    min.len = 1L,
    min.chars = 1L,
    unique = TRUE
  )
  nm <- names(covariates)
  if (is.null(nm) || !all(nzchar(nm))) {
    cli::cli_abort(
      c(
        "Every {.arg covariates} element needs the covariate it points at as
         its name.",
        "i" = "Write {.code covariates = c(Age = \"age_yrs\")}, with the
               covariate on the left and your own column on the right."
      ),
      call = NULL
    )
  }
  if (is.null(pheno)) {
    cli::cli_abort(
      c(
        "{.arg covariates} points at columns of {.arg {arg}}, which is
         {.code NULL}.",
        "i" = "Supply {.arg {arg}}, or drop {.arg covariates}."
      ),
      call = NULL
    )
  }
  # only a covariate this call reads can be pointed anywhere
  if (!length(reads)) {
    cli::cli_abort(
      c(
        "{.arg covariates} names {.field {capped_vals(nm)}}, but this call
         reads no covariate.",
        "i" = "Drop {.arg covariates}."
      ),
      call = NULL
    )
  }
  # deparse would say `nm`, which names nothing the caller wrote
  checkmate::assert_subset(
    nm,
    reads,
    empty.ok = FALSE,
    .var.name = "names(covariates)"
  )

  # the caller's own words, so the message says what they wrote
  absent <- covariates[!covariates %in% names(pheno)]
  if (length(absent)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} has no {cli::qty(absent)}column{?s}
         {.val {capped_vals(unname(absent))}}.",
        "i" = "{.arg covariates} points {.field {names(absent)[[1L]]}} at
               {.val {absent[[1L]]}}.",
        "i" = "{.arg {arg}} has {.field {capped_vals(names(pheno))}}."
      ),
      call = NULL
    )
  }
  # renaming onto a column that is already there would make two of one name
  clash <- nm[nm %in% setdiff(names(pheno), covariates)]
  if (length(clash)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} already has {cli::qty(clash)}{?a /}column{?s}
         {.field {capped_vals(clash)}}.",
        "i" = "{.arg covariates} would give that name to
               {.val {capped_vals(unname(covariates[clash]))}} as well.",
        "i" = "Drop or rename the {.field {clash[[1L]]}} column of
               {.arg {arg}}."
      ),
      call = NULL
    )
  }
  # a names swap on a fresh frame -- the caller's object is never touched
  names(pheno)[match(covariates, names(pheno))] <- nm
  pheno
}

# align pheno by id-join. none supplied -> id column alone.
resolve_pheno <- function(DNAm, pheno, pheno_id, keep) {
  sample_id <- rownames(DNAm)
  out <- if (is.null(pheno)) {
    stats::setNames(data.frame(sample_id, stringsAsFactors = FALSE), pheno_id)
  } else {
    idx <- id_index(
      sample_id,
      pheno[[pheno_id]],
      "resolve_pheno",
      unmatched = "na"
    )
    missing <- sample_id[is.na(idx)]
    if (length(missing)) {
      cli::cli_abort(
        c(
          "{.arg pheno} is missing {length(missing)} sample id{?s} that appear
           in {.arg DNAm}:",
          "x" = "{.val {capped_vals(missing)}}",
          "i" = "Every {.arg DNAm} row needs a matching id in the
                 {.arg pheno_id} column."
        ),
        call = NULL
      )
    }
    # id column + required covariates only
    pheno[idx, unique(c(pheno_id, keep)), drop = FALSE]
  }
  # keyed by the id column, never by row names
  rownames(out) <- NULL
  out
}
