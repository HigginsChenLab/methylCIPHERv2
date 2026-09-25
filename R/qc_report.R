# qc_report(): one self-contained html page over any of a beta matrix, a
# pheno, and a finished mc_result. every section is optional, and a section
# whose input is absent says so rather than disappearing.
#
# DNAm here is a second reader of a beta matrix beside calc_clocks(). it is
# descriptive only: it grades nothing and refuses nothing, and every clock
# verdict it prints is labelled as a count of panel CpGs against the columns,
# not as what calc_clocks() will do (see CLAUDE.md, 2026-09-22).

#' Quality Control Report
#'
#' Writes an HTML report on a beta matrix, its sample metadata, and the clocks
#' scored from it.
#'
#' @param DNAm A numeric matrix. The methylation beta values, with samples in
#'   the rows and CpGs in the columns. Default is `NULL`, which leaves the
#'   methylation sections out.
#' @param pheno A data frame. The sample metadata, with one row for each
#'   sample. Default is `NULL`, which reads the `pheno` stored in `x` when `x`
#'   is given.
#' @param x An `mc_result` object. The value returned by [calc_clocks()].
#'   Default is `NULL`, which leaves the clock result sections out.
#' @param clocks A character vector. The clocks whose CpGs are counted
#'   against the columns of `DNAm`, named by clock id, group id, or tag.
#'   Default is `"all"`.
#' @param file A string. The path of the HTML file to write. Default is
#'   `NULL`, which writes to a temporary file.
#' @param pheno_id A string. The name of the column in `pheno` that holds the
#'   sample ids. Default is `"ID"`.
#' @inheritParams mc-params
#' @param ext_data A string. The path to the directory that holds the clock
#'   assets. Default is `NULL`, which uses the assets directory.
#' @param title A string. The title at the top of the report. Default is
#'   `"methylCIPHERv2 QC report"`.
#' @param open A boolean. Opens the report in a browser after it is written.
#'   Default is `interactive()`.
#' @param context A list. Notes, cards, findings and sections to add to the
#'   report. A string with the path of a JSON file that holds them is also
#'   accepted. Default is `NULL`, which adds nothing. See the Context section.
#'
#' @inheritSection mc-params Covariate columns
#'
#' @section Context:
#' A context describes how the data were made. The report shows it beside its
#' own checks. Every string in a context is shown as text, never as HTML. A
#' JSON file needs the jsonlite package. The list, or the JSON object, has
#' these fields. Only `version` is required.
#'
#' * `version`: the number `1`.
#' * `source`: a string that names who wrote the context.
#' * `cards`: a `heading` and a list of `items`. Each item has a `label`, a
#'   `value`, and optionally a `status` and a `detail`. The cards are added to
#'   the overview.
#' * `comparisons`: a list. Each entry has a `label`, a `stated` value, a
#'   `measured` value and a `status`. It can also have `stated_from`,
#'   `measured_from`, `note` and `ref`. The overview shows them in one table.
#'   A `status` of `"warn"` or `"bad"` also adds a key finding.
#' * `findings`: a list. Each entry has a `status`, a `text` and optionally a
#'   `ref`. They are added to the key findings.
#' * `notes`: a list. Each note has `on`, `key` and `text`. `on` is
#'   `"section"`, `"variable"` or `"sample"`. The `key` is a section id or a
#'   sub-heading id, a column of `pheno`, or a sample id. A note on a variable
#'   with `topic = "missing"` gives the reason for its missing values.
#' * `sample_groups`: a `label` and a named list of `groups`. Each group holds
#'   the ids of samples that should score alike, such as technical
#'   replicates. The clock results compare the first two scored samples of
#'   each group.
#' * `sections`: a list. Each section has an `id`, a `heading` and a list of
#'   `blocks`. A block has a `type`: `"text"`, `"list"` or `"table"`. A table
#'   has `columns` and `rows`. It can also name an `anchor` column, whose
#'   values a `ref` links to, a `details` column that is folded, and
#'   `filters` columns that the reader can filter on.
#'
#' A note, a text block and a list item can have a `kind`, a `badge`, a
#' `details` text that is folded, named `fields`, a `ref` and an `href`. The
#' `kind` is `"fact"`, for a value taken from a record, or `"account"`, for a
#' summary written by the source. The two are drawn in different styles. A
#' `status` is `"ok"`, `"warn"`, `"bad"`, `"na"` or `"info"`. An `href` is an
#' anchor or a relative path.
#'
#' @details
#' Every argument is optional, but at least one of `DNAm`, `pheno` and `x` is
#' needed. A section whose input is not given says that it is not computable.
#' The overview at the top gives the key counts from every section.
#'
#' The overview also plots the `Horvath1` and `Zhang2019EN` scores against
#' age. A sample is flagged when its score is far from the trend with age, or
#' when its predicted sex differs from the `Female` column. The scores come
#' from `x` where it holds them, and from `DNAm` otherwise. Each kind of flag
#' has a box above the plots. Clear a box to hide those samples.
#'
#' The `DNAm` sections describe the beta values, the missing values for each
#' sample and each CpG, the array that the probe ids match, and the coverage
#' of the X and Y chromosomes. They also count the CpGs of each clock in
#' `clocks` against the columns of `DNAm`. These counts describe the matrix
#' and decide nothing. [calc_clocks()] reads the matrix again when it scores,
#' and [clocks_coverage()] gives what it counted. A clock whose weights are in
#' an asset is counted only when that asset is already in the assets
#' directory, or in `ext_data`. The report never downloads an asset. When
#' `DNAm` is given, [predict_sex()] also runs on it.
#'
#' The `pheno` sections give summary statistics and missing values for each
#' column, and the age distribution. Age is read from an `Age` column and sex
#' from a `Female` column, coded `0` or `1`, as in [calc_clocks()]. The age
#' distribution is also split by sex and by every column with two to eight
#' distinct values.
#'
#' The `x` sections list each scoring problem from [summary.mc_result()] with
#' the clocks it applies to. They also give the age correlation of each clock
#' against the blood reference from [score_associations()]. A bibliography of
#' the scored clocks from [cite_clocks()] closes the report.
#'
#' Warnings and messages raised while the report is built are listed at the
#' end of the report, not printed.
#'
#' @returns A string. The path of the written file, invisibly.
#'
#' @examples
#' clocks <- c("Horvath1", "Hannum")
#' sim <- sim_DNAm(clocks, n = 20, Age = TRUE, Female = TRUE)
#' res <- calc_clocks(sim[["DNAm"]], clocks, pheno = sim[["pheno"]])
#' path <- qc_report(sim[["DNAm"]], sim[["pheno"]], res, clocks = clocks,
#'                   open = FALSE)
#' file.exists(path)
#'
#' @export
qc_report <- function(
  DNAm = NULL,
  pheno = NULL,
  x = NULL,
  clocks = "all",
  file = NULL,
  pheno_id = "ID",
  covariates = NULL,
  ext_data = NULL,
  title = "methylCIPHERv2 QC report",
  open = interactive(),
  context = NULL
) {
  checkmate::assert_string(pheno_id, min.chars = 1L)
  checkmate::assert_string(title, min.chars = 1L)
  checkmate::assert_flag(open)
  if (is.null(DNAm) && is.null(pheno) && is.null(x)) {
    cli::cli_abort(
      c(
        "{.fn qc_report} has nothing to report on.",
        "i" = "Pass at least one of {.arg DNAm}, {.arg pheno} and {.arg x}."
      ),
      call = NULL
    )
  }
  if (!is.null(DNAm)) {
    check_DNAm(DNAm)
  }
  if (!is.null(x)) {
    check_mc_result(x)
  }
  pheno_src <- "pheno"
  if (is.null(pheno) && !is.null(x)) {
    pheno <- x[["pheno"]]
    pheno_id <- x[["provenance"]][["pheno_id"]]
    pheno_src <- "x"
  }
  if (!is.null(pheno)) {
    checkmate::assert_data_frame(pheno, min.rows = 1L)
    if (!(pheno_id %in% names(pheno))) {
      cli::cli_abort(
        c(
          "{.arg pheno} has no {.field {pheno_id}} column.",
          "i" = "Pass the name of the sample id column to {.arg pheno_id}."
        ),
        call = NULL
      )
    }
    pheno <- canonicalize_covariates(pheno, covariates, c("Age", "Female"))
  }
  if (is.null(file)) {
    file <- tempfile("qc_report_", fileext = ".html")
  }
  checkmate::assert_path_for_output(file, overwrite = TRUE)
  ctx <- qc_context_read(context)

  st <- new.env(parent = emptyenv())
  st[["notes"]] <- list()
  st[["ctx"]] <- ctx
  if (!is.null(ctx)) {
    st[["ctx_anchors"]] <- ctx_collect_anchors(ctx)
  }

  dn <- qc_section_dnam(st, DNAm, pheno, pheno_id, clocks, ext_data)
  ph <- qc_section_pheno(st, pheno, pheno_id, pheno_src, DNAm, x)
  cr <- qc_section_result(st, x, pheno, pheno_id)
  bib <- qc_section_bib(st, x)
  # after the DNAm section, which leaves the sex calls in st
  ov <- qc_overview_age(st, DNAm, pheno, pheno_id, x)

  # after every other section, which leave their flagged variables in st
  sections <- ctx_place_notes(st, c(list(dn, ph, cr), ctx_sections(st), list(bib)))

  page <- qc_page(title, sections, st, DNAm, pheno, x, ov)
  con <- file(file, open = "w", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  writeLines(page, con, useBytes = TRUE)
  if (open) {
    utils::browseURL(normalizePath(file))
  }
  invisible(normalizePath(file))
}

# --- condition capture --------------------------------------------------------

# runs expr, keeping its warnings and messages for the report instead of the
# console. an error becomes a qc_error value, so one section cannot sink the page.
qc_try <- function(st, section, expr) {
  keep <- function(type, cnd) {
    text <- cli::ansi_strip(conditionMessage(cnd))
    st[["notes"]][[length(st[["notes"]]) + 1L]] <- data.frame(
      section = section,
      type = type,
      text = trimws(text),
      stringsAsFactors = FALSE
    )
  }
  withCallingHandlers(
    tryCatch(
      expr,
      error = function(e) {
        keep("error", e)
        structure(list(message = cli::ansi_strip(conditionMessage(e))), class = "qc_error")
      }
    ),
    warning = function(w) {
      keep("warning", w)
      invokeRestart("muffleWarning")
    },
    message = function(m) {
      keep("message", m)
      invokeRestart("muffleMessage")
    }
  )
}

is_qc_error <- function(v) inherits(v, "qc_error")

qc_failed <- function(v) {
  not_computable(paste("An error stopped this step:", v[["message"]]))
}

# --- section shape --------------------------------------------------------------

# every section returns this: its html, its overview cards, its key findings.
qc_section <- function(id, heading, body, cards = list(), findings = character(0)) {
  list(id = id, heading = heading, body = body, cards = cards, findings = findings)
}

card <- function(label, value, status = "info", detail = NULL) {
  list(label = label, value = value, status = status, detail = detail)
}

# a finding is one sentence with a status chip in front
finding <- function(status, text) {
  word <- c(ok = "OK", warn = "Check", bad = "Problem", na = "Not computable", info = "Note")
  paste0("<li>", chip(word[[status]], status), " ", text, "</li>")
}

sub_head <- function(id, text) tag("h3", html_escape(text), attrs = c(id = id))

# --- DNAm -------------------------------------------------------------------------

qc_section_dnam <- function(st, DNAm, pheno, pheno_id, clocks, ext_data) {
  labels <- c(
    "Samples", "CpGs", "Array", "Beta range", "chrX CpGs", "chrY CpGs",
    "Clock panels complete", "Sex mismatches"
  )
  if (is.null(DNAm)) {
    return(qc_section(
      "dnam", "Methylation data",
      not_computable("No DNAm matrix was supplied."),
      cards = lapply(labels, function(l) card(l, "Not computable", "na", "No DNAm supplied")),
      findings = finding("na", "The methylation checks need a DNAm matrix.")
    ))
  }
  cards <- list()
  findings <- character(0)
  body <- character(0)

  s <- qc_try(st, "DNAm", qc_dnam_stats(DNAm))
  if (is_qc_error(s)) {
    return(qc_section("dnam", "Methylation data", qc_failed(s)))
  }
  n <- s[["n"]]
  cards <- c(cards, list(
    card("Samples", fmt_int(n)),
    card("CpGs", fmt_int(s[["p"]]))
  ))

  # array
  arr <- qc_try(st, "DNAm", qc_array(colnames(DNAm)))
  arr_html <- if (is_qc_error(arr)) {
    qc_failed(arr)
  } else {
    inferred <- arr[["inferred"]]
    cards <- c(cards, list(card(
      "Array", if (is.na(inferred)) "Unknown" else inferred,
      if (is.na(inferred)) "warn" else "ok",
      "From probe ids"
    )))
    if (is.na(inferred)) {
      findings <- c(findings, finding(
        "warn",
        "The probe ids do not match one array. The matrix may be heavily filtered, or its column names may not be probe ids."
      ))
    }
    tab <- arr[["table"]]
    shown <- data.frame(
      array = ifelse(tab[["array"]] %in% inferred, paste(tab[["array"]], "(inferred)"), tab[["array"]]),
      exclusive = cell_bar(tab[["exclusive_rate"]], "info",
                           sprintf("%d of %d", tab[["exclusive_found"]], tab[["exclusive_total"]])),
      reference = cell_bar(tab[["reference_rate"]], "info",
                           sprintf("%s of %s", fmt_int(tab[["reference_found"]]), fmt_int(tab[["reference_total"]]))),
      stringsAsFactors = FALSE
    )
    paste0(
      tag("p", if (is.na(inferred)) {
        "The array could not be inferred. No array has more than 20% of its exclusive loci in the matrix."
      } else {
        sprintf("The probe ids match the <strong>%s</strong> array best.", html_escape(inferred))
      }),
      html_table(
        shown,
        c("Array", "Exclusive loci present", "Reference loci present"),
        html = c("exclusive", "reference")
      ),
      p_note(paste(
        "Exclusive loci are CpG sites on one array only. The reference loci are the",
        "sex chromosome sites and a sample of autosomal sites for each array, from the",
        "Illumina manifests. Probe ids are matched without the EPICv2 and MSA address suffix."
      )),
      if (arr[["n_suffixed"]] > 0L) {
        p_note(sprintf(
          "%s column names carry an EPICv2 or MSA address suffix. Most clocks need one column for each CpG, without the suffix.",
          fmt_int(arr[["n_suffixed"]])
        ))
      }
    )
  }

  # beta values
  out_range <- s[["n_below"]] + s[["n_above"]]
  rng_txt <- if (is.na(s[["lo"]])) "No finite values" else sprintf("%.3f to %.3f", s[["lo"]], s[["hi"]])
  cards <- c(cards, list(card(
    "Beta range", rng_txt,
    if (is.na(s[["lo"]]) || out_range > 0) "bad" else "ok",
    if (out_range > 0) sprintf("%s values outside 0 to 1", fmt_int(out_range)) else "All values in 0 to 1"
  )))
  if (out_range > 0) {
    findings <- c(findings, finding(
      "bad",
      sprintf(
        "%s values fall outside 0 to 1. The clocks expect beta values. An M-value matrix or percent methylation is a common cause.",
        fmt_int(out_range)
      )
    ))
  }
  if (s[["n_nonfinite"]] > 0) {
    findings <- c(findings, finding(
      "warn",
      sprintf("%s values are NaN or infinite. They are counted as missing.", fmt_int(s[["n_nonfinite"]]))
    ))
  }
  bd <- qc_try(st, "DNAm", qc_beta_density(DNAm, s[["lo"]], s[["hi"]]))
  beta_stats <- data.frame(
    measure = c("Smallest value", "Largest value", "Values below 0", "Values above 1",
                "NaN or infinite values", "Median of sample means", "Range of sample means"),
    value = c(
      fmt_num(s[["lo"]]), fmt_num(s[["hi"]]), fmt_int(s[["n_below"]]), fmt_int(s[["n_above"]]),
      fmt_int(s[["n_nonfinite"]]), fmt_num(stats::median(s[["sample_mean"]], na.rm = TRUE)),
      if (all(is.na(s[["sample_mean"]]))) "NA" else paste(fmt_num(range(s[["sample_mean"]], na.rm = TRUE)), collapse = " to ")
    ),
    stringsAsFactors = FALSE
  )
  beta_html <- paste0(
    if (is_qc_error(bd)) qc_failed(bd) else chart_beta_density(bd),
    html_table(beta_stats, c("Measure", "Value"))
  )

  # missingness
  miss_all <- if (s[["cells"]] > 0) s[["n_missing"]] / s[["cells"]] else NA_real_
  hi_miss <- which(s[["sample_miss"]] > QC_SAMPLE_MISS)
  if (length(hi_miss)) {
    findings <- c(findings, finding(
      "bad",
      sprintf("%s sample%s miss more than %s of the CpGs.", fmt_int(length(hi_miss)),
              if (length(hi_miss) == 1L) "" else "s", fmt_pct(QC_SAMPLE_MISS, 0L))
    ))
  }
  o <- order(s[["sample_miss"]], decreasing = TRUE)
  worst <- data.frame(
    sample = rownames(DNAm)[o],
    missing = s[["sample_miss"]][o],
    mean_beta = s[["sample_mean"]][o],
    stringsAsFactors = FALSE
  )
  worst <- worst[worst[["missing"]] > 0, , drop = FALSE]
  worst[["missing"]] <- fmt_pct(worst[["missing"]], 2L)
  miss_html <- paste0(
    tag("p", sprintf(
      "%s of the %s cells are missing (%s). %s CpGs are missing in every sample, and %s CpGs have at least one missing value.",
      fmt_int(s[["n_missing"]]), fmt_int(s[["cells"]]), fmt_pct(miss_all, 3L),
      fmt_int(s[["n_cpg_all_na"]]), fmt_int(s[["n_cpg_any_na"]])
    )),
    figure(
      chart_sample_miss(s[["sample_miss"]]),
      caption = paste(
        "The share of CpGs missing in each sample, ranked from highest to lowest.",
        if (max(s[["sample_miss"]]) > QC_SAMPLE_MISS * 0.87) {
          sprintf("The dashed line marks %s, and samples above it are red.", fmt_pct(QC_SAMPLE_MISS, 0L))
        } else {
          sprintf("Every sample is well below the %s threshold.", fmt_pct(QC_SAMPLE_MISS, 0L))
        }
      )
    ),
    if (nrow(worst)) {
      paste0(tag("h4", "Samples with the most missing CpGs"),
             html_table(worst, c("Sample", "Missing CpGs", "Mean beta"), cap = 15L))
    } else {
      p_note("No sample has a missing value.")
    }
  )

  # sex chromosomes
  inferred <- if (is_qc_error(arr)) NA_character_ else arr[["inferred"]]
  sx <- qc_try(st, "DNAm", qc_sex_chrom(colnames(DNAm), s[["cpg_na"]], n, inferred))
  sex_html <- if (is_qc_error(sx)) {
    qc_failed(sx)
  } else {
    for (i in 1:2) {
      cov <- sx[["coverage"]][[i]]
      lim <- if (i == 1L) 0.5 else 0.2
      cards <- c(cards, list(card(
        c("chrX CpGs", "chrY CpGs")[[i]], fmt_pct(cov, 0L),
        if (cov == 0) "bad" else if (cov < lim) "warn" else "ok",
        sprintf("%s of %s", fmt_int(sx[["present"]][[i]]), fmt_int(sx[["expected"]][[i]]))
      )))
      if (cov < lim) {
        findings <- c(findings, finding(
          "warn",
          sprintf("Only %s of the %s CpGs are present. They were likely removed in preprocessing, so the sex prediction may fail.",
                  fmt_pct(cov, 0L), sx[["chromosome"]][[i]])
        ))
      }
    }
    shown <- data.frame(
      chromosome = sx[["chromosome"]],
      present = sprintf("%s of %s", fmt_int(sx[["present"]]), fmt_int(sx[["expected"]])),
      coverage = cell_bar(sx[["coverage"]], "info"),
      cell_missing = fmt_pct(sx[["cell_missing"]], 2L),
      stringsAsFactors = FALSE
    )
    paste0(
      tag("p", sprintf("Sex chromosome CpGs present, counted against %s.", html_escape(attr(sx, "against")))),
      html_table(shown, c("Chromosome", "CpGs present", "Coverage", "Missing values in those CpGs"),
                 html = "coverage")
    )
  }
  ps <- qc_try(st, "DNAm", qc_predict_sex(DNAm, pheno, pheno_id))
  sexpred_html <- if (is_qc_error(ps)) {
    cards <- c(cards, list(card("Sex mismatches", "Not computable", "na", "Sex prediction failed")))
    qc_failed(ps)
  } else {
    # the overview plots flag these samples
    st[["sex"]] <- ps
    calls <- table(ps[["predicted_sex"]], useNA = "ifany")
    call_df <- data.frame(
      predicted_sex = ifelse(is.na(names(calls)), "No call", names(calls)),
      samples = as.integer(calls),
      stringsAsFactors = FALSE
    )
    mm_html <- ""
    # an uncalled sample reads sex_mismatch = FALSE, so only called samples count
    called <- !is.na(ps[["predicted_sex"]])
    if ("sex_mismatch" %in% names(ps) && !any(called)) {
      cards <- c(cards, list(card("Sex mismatches", "Not computable", "na", "No sample has a predicted sex")))
      findings <- c(findings, finding(
        "na",
        paste0("No sample has a predicted sex, so the Female column could not be checked.", ctx_see(st, "Female"))
      ))
    } else if ("sex_mismatch" %in% names(ps)) {
      mm <- which(ps[["sex_mismatch"]] %in% TRUE)
      cards <- c(cards, list(card(
        "Sex mismatches", fmt_int(length(mm)), if (length(mm)) "bad" else "ok",
        sprintf("of %s samples with both sexes", fmt_int(sum(called & !is.na(ps[["sex_mismatch"]]))))
      )))
      if (length(mm)) {
        ctx_flag(st, "Female", "Predicted sex differs")
        findings <- c(findings, finding(
          "bad",
          paste0(sprintf("%s sample%s have a predicted sex that differs from the Female column.",
                         fmt_int(length(mm)), if (length(mm) == 1L) "" else "s"), ctx_see(st, "Female"))
        ))
        mm_df <- ps[mm, intersect(c("ID", "predicted_sex", "recorded_sex"), names(ps)), drop = FALSE]
        mm_labels <- c("Sample", "Predicted sex", "Recorded sex")[seq_along(mm_df)]
        mm_note <- ctx_sample_col(st, mm_df[[1L]])
        if (!is.null(mm_note)) {
          mm_df[["note"]] <- mm_note
          mm_labels <- c(mm_labels, "Note")
        }
        mm_html <- paste0(tag("h4", "Samples with a sex mismatch"),
                          html_table(mm_df, mm_labels, cap = 20L))
      }
    } else {
      cards <- c(cards, list(card("Sex mismatches", "Not computable", "na", "No Female column in pheno")))
    }
    paste0(
      tag("h4", "Predicted sex"),
      html_table(call_df, c("Predicted sex", "Samples")),
      mm_html,
      p_note("From predict_sex(), which scores the DNAmSex_Wang_ChrX and DNAmSex_Wang_ChrY clocks.")
    )
  }

  # clock panels
  cp <- qc_try(st, "DNAm", {
    x0 <- qc_clock_panels(colnames(DNAm), s[["cpg_na"]], n, clocks, ext_data)
    qc_fill_samples_ok(x0, DNAm)
  })
  panel_out <- new.env(parent = emptyenv())
  panel_html <- if (is_qc_error(cp)) {
    cards <- c(cards, list(card("Clock panels complete", "Not computable", "na")))
    qc_failed(cp)
  } else {
    qc_panel_html(cp, n, panel_out)
  }
  if (!is_qc_error(cp)) {
    cards <- c(cards, list(panel_out[["card"]]))
    findings <- c(findings, panel_out[["findings"]])
  }

  body <- paste0(
    sub_head("dnam-beta", "Beta value distribution"), beta_html,
    sub_head("dnam-missing", "Missing values"), miss_html,
    sub_head("dnam-array", "Array identification"), arr_html,
    sub_head("dnam-sex", "Sex chromosome coverage"), sex_html, sexpred_html,
    sub_head("dnam-clocks", "Clock CpG coverage in DNAm"), panel_html
  )
  # keep the card order fixed, whatever order the steps above ran in
  by_label <- stats::setNames(cards, vapply(cards, `[[`, character(1L), "label"))
  cards <- lapply(labels, function(l) by_label[[l]] %||% card(l, "Not computable", "na"))
  if (!length(findings)) {
    findings <- finding("ok", "The methylation checks found no problem.")
  }
  qc_section("dnam", "Methylation data", body, cards, findings)
}

QC_STATUS_ORDER <- c(
  "none present", "below threshold", "asset not on disk", "partial", "complete", "no panel"
)

qc_panel_html <- function(cp, n, out) {
  tab <- cp[["table"]]
  min_cov <- cp[["min_cov"]]
  counted <- tab[["status"]] != "asset not on disk"
  k_full <- sum(tab[["status"]] == "complete")
  k_low <- sum(tab[["status"]] %in% c("below threshold", "none present"))
  out[["card"]] <- card(
    "Clock panels complete", sprintf("%d of %d", k_full, sum(counted)),
    if (k_low) "warn" else "ok",
    sprintf("%d below %s", k_low, fmt_pct(min_cov, 0L))
  )
  out[["findings"]] <- c(
    if (k_low) {
      finding("warn", sprintf(
        "%d clock%s %s fewer than %s of %s CpGs in DNAm: %s.",
        k_low, if (k_low == 1L) "" else "s", if (k_low == 1L) "has" else "have",
        fmt_pct(min_cov, 0L), if (k_low == 1L) "its" else "their",
        html_escape(paste(utils::head(tab[["clock_id"]][tab[["status"]] %in% c("below threshold", "none present")], 12L), collapse = ", "))
      ))
    },
    if (length(cp[["absent_groups"]])) {
      finding("info", sprintf(
        "The %s asset%s %s not in the assets directory, so %s clocks were not counted.",
        html_escape(paste(cp[["absent_groups"]], collapse = ", ")),
        if (length(cp[["absent_groups"]]) == 1L) "" else "s",
        if (length(cp[["absent_groups"]]) == 1L) "is" else "are",
        if (length(cp[["absent_groups"]]) == 1L) "its" else "their"
      ))
    }
  )
  status_cls <- c(
    "complete" = "ok", "partial" = "warn", "below threshold" = "bad",
    "none present" = "bad", "asset not on disk" = "na", "no panel" = "na"
  )
  o <- order(match(tab[["status"]], QC_STATUS_ORDER), tab[["coverage"]], tab[["clock_id"]])
  tab <- tab[o, , drop = FALSE]
  shown <- data.frame(
    clock_id = tab[["clock_id"]],
    group_id = tab[["group_id"]],
    n_present = ifelse(tab[["n_needed"]] > 0L,
                       sprintf("%s of %s", fmt_int(tab[["n_present"]]), fmt_int(tab[["n_needed"]])), "NA"),
    coverage = cell_bar(tab[["coverage"]], unname(status_cls[tab[["status"]]])),
    cell_missing = fmt_pct(tab[["cell_missing"]], 2L),
    samples_ok = ifelse(is.na(tab[["samples_ok"]]), "NA", sprintf("%s of %s", fmt_int(tab[["samples_ok"]]), fmt_int(n))),
    status = vapply(seq_len(nrow(tab)), function(i) chip(tab[["status"]][[i]], status_cls[[tab[["status"]][[i]]]]), character(1L)),
    stringsAsFactors = FALSE
  )
  counts <- table(factor(tab[["status"]], levels = QC_STATUS_ORDER))
  counts <- counts[counts > 0]
  paste0(
    tag("p", paste0(
      sprintf("The scoring CpGs of %d clock%s, counted against the columns of DNAm. Clocks by status: ", nrow(tab), if (nrow(tab) == 1L) "" else "s"),
      paste(sprintf("%s %d", names(counts), as.integer(counts)), collapse = ", "), "."
    )),
    panel_tables(shown, tab[["status"]] %in% c("complete", "asset not on disk", "no panel"), min_cov),
    p_note(paste0(
      "A clock built from other clocks is counted on the CpGs of the clocks it reads. ",
      "The threshold is the default min_clocks_coverage of calc_clocks(), ", fmt_pct(min_cov, 0L),
      ". These counts describe the matrix. calc_clocks() decides what scores, and clocks_coverage() gives what it counted."
    ))
  )
}

# rows that need attention open, the rest behind a disclosure
panel_tables <- function(shown, quiet, min_cov) {
  labels <- c("Clock", "Group", "CpGs present", "Coverage", "Missing values in panel",
              paste("Samples at", fmt_pct(min_cov, 0L), "or more"), "Status")
  loud <- shown[!quiet, , drop = FALSE]
  rest <- shown[quiet, , drop = FALSE]
  paste0(
    if (nrow(loud)) html_table(loud, labels, html = c("coverage", "status")) else p_note("Every counted clock has its full panel."),
    if (nrow(rest)) {
      paste0(
        "<details><summary>", nrow(rest), " clocks with a complete panel or no asset on disk</summary>",
        html_table(rest, labels, html = c("coverage", "status")), "</details>"
      )
    }
  )
}

# --- pheno -----------------------------------------------------------------------

qc_section_pheno <- function(st, pheno, pheno_id, pheno_src, DNAm, x) {
  labels <- c("Age", "Sex", "Variables with missing values", "Sample ids matched")
  if (is.null(pheno)) {
    return(qc_section(
      "pheno", "Phenotype data",
      paste0(not_computable("No pheno data frame was supplied."), ctx_variables_html(st, NULL), ctx_samples_html(st)),
      cards = lapply(labels, function(l) card(l, "Not computable", "na", "No pheno supplied")),
      findings = finding("na", "The phenotype checks need a pheno data frame.")
    ))
  }
  cards <- list()
  findings <- character(0)
  ids <- as.character(pheno[[pheno_id]])

  # ids
  dup <- sum(duplicated(ids[!is.na(ids)]))
  na_id <- sum(is.na(ids) | !nzchar(ids))
  id_rows <- list(c("Rows in pheno", fmt_int(nrow(pheno))),
                  c("Missing ids", fmt_int(na_id)),
                  c("Repeated ids", fmt_int(dup)))
  matched_card <- card("Sample ids matched", "Not computable", "na", "No DNAm or x supplied")
  if (!is.null(DNAm)) {
    both <- sum(rownames(DNAm) %in% ids)
    id_rows <- c(id_rows, list(
      c("DNAm samples found in pheno", sprintf("%s of %s", fmt_int(both), fmt_int(nrow(DNAm)))),
      c("pheno rows not in DNAm", fmt_int(sum(!(ids %in% rownames(DNAm)))))
    ))
    matched_card <- card("Sample ids matched", sprintf("%s of %s", fmt_int(both), fmt_int(nrow(DNAm))),
                         if (both < nrow(DNAm)) "bad" else "ok", "DNAm samples in pheno")
    if (both < nrow(DNAm)) {
      findings <- c(findings, finding("bad", sprintf(
        "%s DNAm sample%s %s no row in pheno.", fmt_int(nrow(DNAm) - both),
        if (nrow(DNAm) - both == 1L) "" else "s", if (nrow(DNAm) - both == 1L) "has" else "have"
      )))
    }
  }
  if (!is.null(x) && pheno_src == "pheno") {
    xs <- rownames(x[["scores"]])
    both <- sum(xs %in% ids)
    id_rows <- c(id_rows, list(c("Scored samples found in pheno", sprintf("%s of %s", fmt_int(both), fmt_int(length(xs))))))
    if (is.null(DNAm)) {
      matched_card <- card("Sample ids matched", sprintf("%s of %s", fmt_int(both), fmt_int(length(xs))),
                           if (both < length(xs)) "bad" else "ok", "Scored samples in pheno")
    }
  }
  if (dup) {
    findings <- c(findings, finding("bad", sprintf("%s sample id%s repeated in pheno.", fmt_int(dup), if (dup == 1L) " is" else "s are")))
  }
  id_df <- as.data.frame(do.call(rbind, id_rows), stringsAsFactors = FALSE)
  names(id_df) <- c("measure", "value")

  ps <- qc_try(st, "pheno", qc_pheno_stats(pheno, pheno_id))
  stats_html <- if (is_qc_error(ps)) {
    qc_failed(ps)
  } else if (is.null(ps)) {
    findings <- c(findings, finding("info", sprintf("pheno holds only the %s column, so there is nothing to describe.", html_escape(pheno_id))))
    p_note(sprintf("pheno holds only the %s column.", html_escape(pheno_id)))
  } else {
    n_missvar <- sum(ps[["n_missing"]] > 0)
    n_hivar <- sum(ps[["pct_missing"]] > QC_VAR_MISS)
    cards <- c(cards, list(
      card("Variables with missing values", fmt_int(n_missvar),
           if (n_hivar) "warn" else if (n_missvar) "info" else "ok",
           sprintf("%d above %s missing", n_hivar, fmt_pct(QC_VAR_MISS, 0L)))
    ))
    ctx_flag(st, ps[["variable"]][ps[["pct_missing"]] > QC_VAR_MISS], sprintf("More than %s missing", fmt_pct(QC_VAR_MISS, 0L)))
    ctx_flag(st, ps[["variable"]][!is.na(ps[["n_outliers"]]) & ps[["n_outliers"]] > 0], sprintf("Values beyond %d SD", QC_OUTLIER_Z))
    if (n_hivar) {
      findings <- c(findings, finding("warn", sprintf(
        "%d variable%s miss more than %s of values: %s.", n_hivar, if (n_hivar == 1L) "" else "s",
        fmt_pct(QC_VAR_MISS, 0L), html_escape(paste(ps[["variable"]][ps[["pct_missing"]] > QC_VAR_MISS], collapse = ", "))
      )))
    }
    n_out <- sum(ps[["n_outliers"]] > 0, na.rm = TRUE)
    if (n_out) {
      findings <- c(findings, finding("warn", sprintf(
        "%d numeric variable%s %s values more than %d standard deviations from the mean.",
        n_out, if (n_out == 1L) "" else "s", if (n_out == 1L) "has" else "have", QC_OUTLIER_Z
      )))
    }
    num <- ps[ps[["type"]] == "numeric", , drop = FALSE]
    cat_ <- ps[ps[["type"]] != "numeric", , drop = FALSE]
    num_html <- if (nrow(num)) {
      shown <- num[c("variable", "n", "n_missing", "mean", "sd", "min", "p10", "p25", "median", "p75", "p90", "max", "n_outliers")]
      shown[["counts"]] <- num[["counts"]]
      paste0(
        tag("h4", "Numeric variables"),
        html_table(shown, c("Variable", "N", "Missing", "Mean", "SD", "Min", "P10", "P25", "Median",
                            "P75", "P90", "Max", sprintf("Beyond %d SD", QC_OUTLIER_Z), "Values"),
                   html = "counts")
      )
    } else {
      ""
    }
    cat_html <- if (nrow(cat_)) {
      shown <- cat_[c("variable", "type", "n", "n_missing", "n_distinct", "counts")]
      paste0(
        tag("h4", "Categorical variables"),
        html_table(shown, c("Variable", "Type", "N", "Missing", "Levels", "Counts"), html = "counts")
      )
    } else {
      ""
    }
    miss_df <- data.frame(
      variable = ps[["variable"]],
      n_missing = ps[["n_missing"]],
      pct = cell_bar(ps[["pct_missing"]], ifelse(ps[["pct_missing"]] > QC_VAR_MISS, "bad",
                                                 ifelse(ps[["pct_missing"]] > 0, "warn", "ok"))),
      stringsAsFactors = FALSE
    )
    miss_labels <- c("Variable", "Missing", "Share missing")
    reasons <- ctx_missing_reasons(st, ps[["variable"]])
    if (!is.null(reasons)) {
      miss_df[["reason"]] <- reasons
      miss_labels <- c(miss_labels, "Stated reason")
    }
    miss_df <- miss_df[order(-ps[["pct_missing"]], ps[["variable"]]), , drop = FALSE]
    paste0(
      sub_head("pheno-stats", "Descriptive statistics"), num_html, cat_html,
      sub_head("pheno-missing", "Missing values"),
      html_table(miss_df, miss_labels, html = c("pct", "reason"))
    )
  }

  # age
  age_html <- if (!("Age" %in% names(pheno))) {
    cards <- c(cards, list(card("Age", "Not computable", "na", "No Age column")))
    not_computable("pheno has no Age column. Pass the name of the age column to covariates, as in covariates = c(Age = \"age_yrs\").")
  } else {
    age <- suppressWarnings(as.numeric(pheno[["Age"]]))
    ok <- is.finite(age)
    if (!any(ok)) {
      cards <- c(cards, list(card("Age", "Not computable", "na", "No numeric Age values")))
      not_computable("The Age column holds no numeric values.")
    } else {
      cards <- c(cards, list(card(
        "Age", sprintf("%s mean", fmt_num(mean(age[ok]), 3L)), "info",
        sprintf("%s to %s, SD %s", fmt_num(min(age[ok])), fmt_num(max(age[ok])),
                if (sum(ok) > 1L) fmt_num(stats::sd(age[ok])) else "NA")
      )))
      if (max(age[ok]) > 120 || min(age[ok]) < 0) {
        ctx_flag(st, "Age", "Values below 0 or above 120")
        findings <- c(findings, finding("warn", paste0("Some Age values are below 0 or above 120. Check that Age is in years.", ctx_see(st, "Age"))))
      }
      parts <- chart_hist(age, "Age", label = "Age distribution")
      if ("Female" %in% names(pheno)) {
        parts <- c(parts, tag("h4", "Age by sex"),
                   chart_density_groups(age, female_label(pheno[["Female"]]), "Age", "Age distribution by sex"))
      }
      for (v in utils::head(qc_split_vars(pheno, pheno_id), 8L)) {
        parts <- c(parts, tag("h4", paste("Age by", html_escape(v))),
                   chart_density_groups(age, pheno[[v]], "Age", paste("Age distribution by", v)))
      }
      paste(parts, collapse = "")
    }
  }
  sex_card <- if ("Female" %in% names(pheno)) {
    f <- female_label(pheno[["Female"]])
    if (anyNA(f)) {
      ctx_flag(st, "Female", "Missing or not coded 0 or 1")
    }
    card("Sex", sprintf("%s F / %s M", fmt_int(sum(f %in% "Female")), fmt_int(sum(f %in% "Male"))),
         if (anyNA(f)) "warn" else "info",
         sprintf("%s missing or not coded 0 or 1", fmt_int(sum(is.na(f)))))
  } else {
    card("Sex", "Not computable", "na", "No Female column")
  }
  cards <- c(cards, list(sex_card, matched_card))

  src_note <- if (pheno_src == "x") {
    p_note("pheno was not supplied, so this section reads the pheno stored in x. calc_clocks() keeps only the id column and the covariates the clocks need.")
  } else {
    ""
  }
  body <- paste0(
    src_note,
    sub_head("pheno-ids", "Sample ids"), html_table(id_df, c("Measure", "Value")), ctx_samples_html(st),
    stats_html, ctx_variables_html(st, if (is_qc_error(ps)) NULL else ps),
    sub_head("pheno-age", "Age distribution"), age_html
  )
  by_label <- stats::setNames(cards, vapply(cards, `[[`, character(1L), "label"))
  cards <- lapply(labels, function(l) by_label[[l]] %||% card(l, "Not computable", "na"))
  if (!length(findings)) {
    findings <- finding("ok", "The phenotype checks found no problem.")
  }
  qc_section("pheno", "Phenotype data", body, cards, findings)
}

# --- mc_result ---------------------------------------------------------------------

# the age vector for x: the supplied pheno first, then the pheno stored in x
qc_age_for <- function(x, pheno, pheno_id) {
  xs <- rownames(x[["scores"]])
  if (!is.null(pheno) && "Age" %in% names(pheno)) {
    m <- match(xs, as.character(pheno[[pheno_id]]))
    return(suppressWarnings(as.numeric(pheno[["Age"]][m])))
  }
  NULL
}

qc_section_result <- function(st, x, pheno, pheno_id) {
  labels <- c("Clocks scored", "Failed clocks", "Age correlation outside blood range")
  if (is.null(x)) {
    return(qc_section(
      "clocks", "Clock results",
      not_computable("No mc_result object was supplied. Pass the value of calc_clocks() to x."),
      cards = lapply(labels, function(l) card(l, "Not computable", "na", "No x supplied")),
      findings = finding("na", "The clock result checks need an mc_result object from calc_clocks().")
    ))
  }
  cards <- list()
  findings <- character(0)
  prov <- x[["provenance"]]

  m <- qc_try(st, "x", as.matrix(x))
  if (is_qc_error(m)) {
    return(qc_section("clocks", "Clock results", qc_failed(m)))
  }
  n <- nrow(m)
  cards <- c(cards, list(card("Clocks scored", fmt_int(ncol(m)), "info", sprintf("%s samples", fmt_int(n)))))

  run_df <- data.frame(
    measure = c("Samples", "Clocks returned", "Clocks requested", "Batches", "Clocks normalized",
                "min_clocks_coverage", "min_samples_coverage"),
    value = c(
      fmt_int(n), fmt_int(ncol(m)), fmt_int(length(prov[["requested"]])),
      fmt_int(length(unique(prov[[MC_BATCH]]))),
      if (length(prov[["normalized"]])) paste(prov[["normalized"]], collapse = ", ") else "None",
      paste(unique(unlist(prov[["min_clocks_coverage"]])), collapse = ", "),
      paste(unique(unlist(prov[["min_samples_coverage"]])), collapse = ", ")
    ),
    stringsAsFactors = FALSE
  )

  # problems, from summary()
  sm <- qc_try(st, "x", summary(x))
  prob_html <- if (is_qc_error(sm)) {
    cards <- c(cards, list(card("Failed clocks", "Not computable", "na")))
    qc_failed(sm)
  } else {
    failed <- sm[["failed"]] %||% character(0)
    cards <- c(cards, list(card("Failed clocks", fmt_int(length(failed)), if (length(failed)) "bad" else "ok",
                                "NA for every sample")))
    if (length(failed)) {
      findings <- c(findings, finding("bad", sprintf(
        "%d clock%s scored NA for every sample: %s.", length(failed), if (length(failed) == 1L) "" else "s",
        html_escape(paste(failed, collapse = ", "))
      )))
    }
    qc_problems_html(sm[["by_clock"]], n)
  }

  # age associations
  age <- qc_age_for(x, pheno, pheno_id)
  assoc <- qc_try(st, "x", score_associations(x, age = age))
  assoc_html <- if (is_qc_error(assoc)) {
    cards <- c(cards, list(card(labels[[3L]], "Not computable", "na", "No Age for the scored samples")))
    findings <- c(findings, finding("na", "The age correlation check needs an Age column in pheno, or in the pheno stored in x."))
    not_computable(paste("The age correlation check needs an Age value for each scored sample.", assoc[["message"]]))
  } else if (!nrow(assoc)) {
    cards <- c(cards, list(card(labels[[3L]], "Not computable", "na", "No clock in the blood reference")))
    not_computable("No scored clock has an entry in the blood reference, or too few samples have both a score and an age.")
  } else {
    k_out <- sum(assoc[["outside"]])
    k_sign <- sum(assoc[["wrong_sign"]])
    cards <- c(cards, list(
      card(labels[[3L]], sprintf("%d of %d", k_out, nrow(assoc)), if (k_out) "warn" else "ok", "Outside the 95% prediction range")
    ))
    if (k_out) {
      findings <- c(findings, finding("warn", sprintf(
        "%d clock%s %s an age correlation outside the range expected in blood: %s.",
        k_out, if (k_out == 1L) "" else "s", if (k_out == 1L) "has" else "have",
        html_escape(paste(utils::head(assoc[["clock_id"]][assoc[["outside"]]], 12L), collapse = ", "))
      )))
    }
    if (k_sign) {
      findings <- c(findings, finding("bad", sprintf(
        "%d clock%s %s an age correlation with the opposite sign from blood: %s.",
        k_sign, if (k_sign == 1L) "" else "s", if (k_sign == 1L) "has" else "have",
        html_escape(paste(assoc[["clock_id"]][assoc[["wrong_sign"]]], collapse = ", "))
      )))
    }
    if (!k_out && !k_sign) {
      findings <- c(findings, finding("ok", sprintf(
        "All %d clocks in the blood reference have an age correlation in the expected range.", nrow(assoc)
      )))
    }
    qc_assoc_html(assoc, m, age)
  }

  groups <- ctx_groups_section(st, m)
  findings <- c(findings, groups[["findings"]])
  body <- paste0(
    sub_head("clocks-run", "Run"), html_table(run_df, c("Measure", "Value")),
    sub_head("clocks-problems", "Scoring problems"), prob_html,
    sub_head("clocks-age", "Age correlation against blood"), assoc_html,
    groups[["html"]]
  )
  by_label <- stats::setNames(cards, vapply(cards, `[[`, character(1L), "label"))
  cards <- lapply(labels, function(l) by_label[[l]] %||% card(l, "Not computable", "na"))
  if (!length(findings)) {
    findings <- finding("ok", "The clock result checks found no problem.")
  }
  qc_section("clocks", "Clock results", body, cards, findings)
}

# one line per problem, then the clocks it applies to. a clock hit on fewer
# than all n samples carries its sample count, summed over batches.
qc_problems_html <- function(bc, n) {
  if (is.null(bc) || !nrow(bc)) {
    return(p_note("Every clock scored every sample."))
  }
  key <- paste(bc[["panel"]], bc[["note"]])
  items <- vapply(unique(key), function(k) {
    rows <- bc[key == k, , drop = FALSE]
    ids <- unique(rows[["clock_id"]])
    k_samples <- vapply(ids, function(id) sum(rows[["n_samples"]][rows[["clock_id"]] == id]), numeric(1L))
    shown <- ifelse(k_samples < n, sprintf("%s (%s of %s samples)", ids, fmt_int(k_samples), fmt_int(n)), ids)
    what <- rows[["explanation"]][[1L]]
    paste0(
      "<li><strong>", html_escape(paste0(toupper(substring(what, 1L, 1L)), substring(what, 2L))), "</strong> (",
      length(ids), " clock", if (length(ids) == 1L) "" else "s", ")",
      "<span class=\"clocks\">", html_escape(paste(shown, collapse = ", ")), "</span></li>"
    )
  }, character(1L))
  paste0(
    tag("p", "Each problem that left a score NA or a calibration partial, and the clocks it applies to. From summary(x)."),
    "<ul class=\"problems\">", paste(items, collapse = ""), "</ul>"
  )
}

# at most this many scatter plots under the association table
QC_ASSOC_PLOTS <- 12L

# the association table, a range chart, and the most telling scatter plots
qc_assoc_html <- function(assoc, m, age) {
  flag <- assoc[["outside"]] | assoc[["wrong_sign"]]
  status <- ifelse(assoc[["wrong_sign"]], "bad", ifelse(assoc[["outside"]], "warn", "ok"))
  word <- ifelse(assoc[["wrong_sign"]], "wrong sign", ifelse(assoc[["outside"]], "outside range", "in range"))
  shown <- data.frame(
    clock_id = assoc[["clock_id"]],
    n = assoc[["n"]],
    obs = assoc[["obs_age_r"]],
    exp = assoc[["exp_age_r"]],
    range = sprintf("%s to %s", fmt_num(assoc[["exp_lo"]]), fmt_num(assoc[["exp_hi"]])),
    status = vapply(seq_along(word), function(i) chip(word[[i]], status[[i]]), character(1L)),
    stringsAsFactors = FALSE
  )
  # scatter: flagged clocks first, then the clocks that track age most in blood
  pick <- order(!flag, -abs(assoc[["exp_age_r"]]))
  pick <- utils::head(assoc[["clock_id"]][pick], QC_ASSOC_PLOTS)
  age_x <- if (is.null(age)) NULL else age
  scatters <- if (is.null(age_x)) {
    ""
  } else {
    paste0(
      "<div class=\"plots\">",
      paste(vapply(pick, function(id) {
        i <- match(id, assoc[["clock_id"]])
        paste0(
          "<div class=\"cell\"><div class=\"cell-title\">", html_escape(id), " ",
          chip(sprintf("r = %s", fmt_num(assoc[["obs_age_r"]][[i]], 2L)), status[[i]]), "</div>",
          chart_scatter(age_x, m[, id], "Age", id, paste(id, "against age"),
                        titles = sprintf("%s: age %s, score %s", rownames(m), fmt_num(age_x), fmt_num(m[, id]))),
          "</div>"
        )
      }, character(1L)), collapse = ""),
      "</div>"
    )
  }
  paste0(
    tag("p", paste(
      "Each clock's correlation with age in this data, against the pooled correlation and",
      "95% prediction range from a meta-analysis of blood datasets. A clock outside the range",
      "tracks age unlike it does in blood. Non-blood tissue, a narrow age range, or a",
      "processing problem can each cause that."
    )),
    chart_assoc(assoc, status),
    html_table(shown, c("Clock", "Samples", "Observed r", "Blood r", "Blood 95% range", "Status"), html = "status"),
    if (nzchar(scatters)) paste0(tag("h4", "Scores against age"), p_note("Clocks out of range first, then the clocks that track age most closely in blood."), scatters) else ""
  )
}

# one row per clock: the blood range as a band, the blood r as a ring, and the
# observed r as a dot
chart_assoc <- function(assoc, status) {
  k <- nrow(assoc)
  row_h <- 18
  width <- 680
  height <- 40 + k * row_h + 30
  p <- svg_panel(c(-1, 1), c(0.5, k + 0.5), width, height,
                 margin = c(top = 12, right = 20, bottom = 44, left = 170))
  y <- rev(seq_len(k))
  lo <- pmax(assoc[["exp_lo"]], -1)
  hi <- pmin(assoc[["exp_hi"]], 1)
  ok_band <- is.finite(lo) & is.finite(hi)
  bands <- if (!any(ok_band)) "" else paste0(
    "<line class=\"band\" x1=\"", f1(p[["sx"]](lo[ok_band])), "\" x2=\"", f1(p[["sx"]](hi[ok_band])),
    "\" y1=\"", f1(p[["sy"]](y[ok_band])), "\" y2=\"", f1(p[["sy"]](y[ok_band])), "\"/>",
    collapse = ""
  )
  exp_pts <- paste0(
    "<circle class=\"exp\" cx=\"", f1(p[["sx"]](assoc[["exp_age_r"]])), "\" cy=\"", f1(p[["sy"]](y)),
    "\" r=\"4\"><title>", html_escape(sprintf("%s blood r = %s", assoc[["clock_id"]], fmt_num(assoc[["exp_age_r"]]))),
    "</title></circle>",
    collapse = ""
  )
  col <- ifelse(status == "bad", "var(--crit)", ifelse(status == "warn", "var(--serious)", SVG_SERIES[[1L]]))
  obs_pts <- svg_points(p, assoc[["obs_age_r"]], y, col, r = 4.5,
                        titles = sprintf("%s observed r = %s", assoc[["clock_id"]], fmt_num(assoc[["obs_age_r"]])),
                        opacity = 1)
  names_txt <- paste0(
    "<text class=\"tick\" text-anchor=\"end\" x=\"", f1(p[["left"]] - 8), "\" y=\"", f1(p[["sy"]](y) + 4),
    "\">", html_escape(assoc[["clock_id"]]), "</text>",
    collapse = ""
  )
  zero <- paste0("<line class=\"ref\" x1=\"", f1(p[["sx"]](0)), "\" x2=\"", f1(p[["sx"]](0)),
                 "\" y1=\"", f1(p[["top"]]), "\" y2=\"", f1(p[["bottom"]]), "\"/>")
  body <- paste0(
    svg_axes(p, "Correlation with age (r)", "", yticks = numeric(0)),
    zero, bands, exp_pts, obs_pts, names_txt
  )
  figure(
    svg_doc(p, body, "Observed age correlation of each clock against the blood reference"),
    legend = html_legend(
      c("Observed r, in range", "Observed r, out of range", "Observed r, wrong sign", "Blood r and 95% range"),
      c(SVG_SERIES[[1L]], "var(--serious)", "var(--crit)", "var(--ink-3)")
    )
  )
}

# --- bibliography --------------------------------------------------------------------

short_authors <- function(a) {
  parts <- trimws(strsplit(a, " and ", fixed = TRUE)[[1L]])
  parts <- sub(",.*$", "", parts)
  if (length(parts) > 3L) paste(paste(parts[1:3], collapse = ", "), "et al.") else paste(parts, collapse = ", ")
}

qc_section_bib <- function(st, x) {
  if (is.null(x)) {
    return(qc_section("bib", "Bibliography", not_computable("No clocks were scored, so there is nothing to cite. Pass an mc_result object to x.")))
  }
  cit <- qc_try(st, "bibliography", cite_clocks(x))
  if (is_qc_error(cit)) {
    return(qc_section("bib", "Bibliography", qc_failed(cit)))
  }
  links <- as.data.frame(cit)
  keys <- unique(links[["bib_key"]])
  items <- vapply(keys, function(k) {
    r <- links[links[["bib_key"]] == k, , drop = FALSE]
    one <- r[1L, ]
    clocks_for <- unique(r[["clock_id"]])
    vol <- if (!is.na(one[["volume"]]) && nzchar(one[["volume"]])) {
      paste0(" ", one[["volume"]], if (!is.na(one[["number"]]) && nzchar(one[["number"]])) paste0("(", one[["number"]], ")") else "")
    } else {
      ""
    }
    pages <- if (!is.na(one[["pages"]]) && nzchar(one[["pages"]])) paste0(", ", gsub("-+", "-", one[["pages"]])) else ""
    doi <- if (!is.na(one[["doi"]]) && nzchar(one[["doi"]])) {
      paste0(" <a href=\"https://doi.org/", html_escape(one[["doi"]]), "\">doi:", html_escape(one[["doi"]]), "</a>")
    } else {
      ""
    }
    paste0(
      "<li><span class=\"ref-main\">", html_escape(short_authors(one[["author"]])), " (",
      html_escape(one[["year"]]), "). ", html_escape(one[["title"]]), ". <em>",
      html_escape(one[["journal"]]), "</em>", html_escape(vol), html_escape(pages), ".", doi,
      "</span><span class=\"ref-clocks\">Cited for ", html_escape(paste(clocks_for, collapse = ", ")), "</span></li>"
    )
  }, character(1L))
  pkg <- qc_try(st, "bibliography", paste(format(utils::citation("methylCIPHERv2"), style = "text"), collapse = " "))
  if (is_qc_error(pkg)) {
    pkg <- ""
  }
  body <- paste0(
    tag("p", sprintf("%d paper%s for the %d clock%s in x, from cite_clocks(x).",
                     length(keys), if (length(keys) == 1L) "" else "s",
                     ncol(x[["scores"]]), if (ncol(x[["scores"]]) == 1L) "" else "s")),
    "<ol class=\"refs\">", paste(items, collapse = ""), "</ol>",
    if (nzchar(pkg)) paste0(tag("h4", "Citing methylCIPHERv2"), tag("p", html_escape(pkg))),
    "<details><summary>BibTeX</summary><pre class=\"bibtex\">",
    html_escape(paste(cit[["bibtex"]], collapse = "\n")), "</pre></details>"
  )
  qc_section("bib", "Bibliography", body)
}

# --- overview: clock age against age ---------------------------------------------------

# the two age clocks the overview plots. both are bundled, so scoring them from
# DNAm never needs an asset.
QC_AGE_CLOCKS <- c("Horvath1", "Zhang2019EN")

# a named score vector per clock: the column of x where it has one, else a
# calc_clocks() run on DNAm
qc_age_scores <- function(st, DNAm, x) {
  out <- list()
  if (!is.null(x)) {
    m <- qc_try(st, "overview", as.matrix(x))
    if (!is_qc_error(m)) {
      for (id in intersect(QC_AGE_CLOCKS, colnames(m))) {
        out[[id]] <- stats::setNames(m[, id], rownames(m))
      }
    }
  }
  need <- setdiff(QC_AGE_CLOCKS, names(out))
  if (length(need) && !is.null(DNAm)) {
    res <- qc_try(st, "overview", as.matrix(calc_clocks(DNAm, need)))
    if (!is_qc_error(res)) {
      for (id in intersect(need, colnames(res))) {
        out[[id]] <- stats::setNames(res[, id], rownames(res))
      }
    }
  }
  out[intersect(QC_AGE_CLOCKS, names(out))]
}

# TRUE where a sample sits far off the least-squares line of score on age,
# at more than QC_OUTLIER_Z robust standard deviations of the residuals
qc_age_outliers <- function(age, score) {
  flag <- rep(FALSE, length(age))
  ok <- is.finite(age) & is.finite(score)
  if (sum(ok) < 5L || stats::sd(age[ok]) == 0) {
    return(flag)
  }
  r <- stats::lm.fit(cbind(1, age[ok]), score[ok])[["residuals"]]
  s <- stats::mad(r)
  if (!is.finite(s) || s == 0) {
    return(flag)
  }
  flag[ok] <- abs(r - stats::median(r)) > QC_OUTLIER_Z * s
  flag
}

qc_overview_age <- function(st, DNAm, pheno, pheno_id, x) {
  head_html <- tag("h3", "Clock age against age")
  out <- function(body, findings = character(0)) list(html = paste0(head_html, body), findings = findings)
  if (is.null(DNAm) && is.null(x)) {
    return(out(not_computable("The plots need a DNAm matrix or an mc_result object.")))
  }
  if (is.null(pheno) || !("Age" %in% names(pheno))) {
    return(out(not_computable("The plots need an Age column in pheno.")))
  }
  sc <- qc_age_scores(st, DNAm, x)
  if (!length(sc)) {
    return(out(not_computable("Neither Horvath1 nor Zhang2019EN could be scored.")))
  }
  ids <- as.character(pheno[[pheno_id]])
  age_all <- suppressWarnings(as.numeric(pheno[["Age"]]))
  ps <- st[["sex"]]
  sex_bad <- if (!is.null(ps) && "sex_mismatch" %in% names(ps)) {
    as.character(ps[["ID"]][ps[["sex_mismatch"]] %in% TRUE])
  } else {
    character(0)
  }
  cls <- c(none = SVG_SERIES[[1L]], age = "var(--serious)", sex = "var(--s7)", both = "var(--crit)")

  per_clock <- lapply(names(sc), function(id) {
    v <- sc[[id]]
    s_ids <- names(v)
    age <- age_all[match(s_ids, ids)]
    af <- qc_age_outliers(age, v)
    sf <- s_ids %in% sex_bad
    kind <- ifelse(af & sf, "both", ifelse(af, "age", ifelse(sf, "sex", "none")))
    hit <- af | sf
    rows <- data.frame(sample = s_ids[hit], clock = rep(id, sum(hit)), age = age[hit],
                       score = unname(v[hit]), age_flag = af[hit], sex_flag = sf[hit],
                       stringsAsFactors = FALSE)
    # flagged samples draw last, on top
    o <- order(match(kind, names(cls)))
    cell <- paste0(
      "<div class=\"cell\"><div class=\"cell-title\">", html_escape(id), "</div>",
      chart_scatter(age[o], v[o], "Age", id, paste(id, "against age"),
                    col = unname(cls[kind[o]]), width = 420, height = 300,
                    pt_class = paste0("k-", kind[o]),
                    titles = sprintf("%s: age %s, score %s", s_ids[o], fmt_num(age[o]), fmt_num(v[o])),
                    title_keep = kind[o] != "none"),
      "</div>"
    )
    list(cell = cell, rows = rows)
  })
  cells <- vapply(per_clock, `[[`, character(1L), "cell")
  fl <- do.call(rbind, lapply(per_clock, `[[`, "rows"))

  findings <- character(0)
  table_html <- ""
  if (nrow(fl)) {
    n_age <- length(unique(fl[["sample"]][fl[["age_flag"]]]))
    if (n_age) {
      ctx_flag(st, "Age", "Clock age far from the trend")
      findings <- finding("warn", paste0(sprintf(
        "%s sample%s %s a Horvath1 or Zhang2019EN age far from the trend with Age.",
        fmt_int(n_age), if (n_age == 1L) "" else "s", if (n_age == 1L) "has" else "have"
      ), ctx_see(st, "Age")))
    }
    fl[["flag"]] <- ifelse(fl[["age_flag"]] & fl[["sex_flag"]], "age and sex",
                           ifelse(fl[["age_flag"]], "age", "sex"))
    fl <- fl[order(fl[["sample"]], fl[["clock"]]), c("sample", "clock", "age", "score", "flag"), drop = FALSE]
    fl_labels <- c("Sample", "Clock", "Age", "Score", "Flag")
    fl_note <- ctx_sample_col(st, fl[["sample"]])
    if (!is.null(fl_note)) {
      fl[["note"]] <- fl_note
      fl_labels <- c(fl_labels, "Note")
    }
    table_html <- paste0(
      "<details><summary>", fmt_int(length(unique(fl[["sample"]]))), " flagged sample",
      if (length(unique(fl[["sample"]])) == 1L) "" else "s", "</summary>",
      html_table(fl, fl_labels, cap = 50L), "</details>"
    )
  }
  src <- if (!is.null(x) && all(names(sc) %in% colnames(x[["scores"]]))) "x" else "DNAm"
  out(paste0(
    figure(
      paste0("<div class=\"plots\">", paste(cells, collapse = ""), "</div>"),
      caption = paste0(
        "Each point is a sample. The dashed line is the least-squares line. ",
        sprintf("An age flag marks a sample more than %d robust standard deviations from that line. ", QC_OUTLIER_Z),
        "A sex flag marks a sample whose predicted sex differs from the Female column. ",
        "Clear a box above the plots to hide that group of points. ",
        if (src == "x") "The scores are from x." else "Scores not in x are scored from DNAm."
      ),
      legend = toggle_legend(names(cls), c("No flag", "Age flag", "Sex flag", "Age and sex flag"), unname(cls))
    ),
    table_html
  ), findings)
}

# --- page ---------------------------------------------------------------------------

qc_notes_html <- function(st) {
  notes <- st[["notes"]]
  if (!length(notes)) {
    return(p_note("No warning or message was raised."))
  }
  df <- do.call(rbind, notes)
  df <- df[!duplicated(df[c("section", "type", "text")]), , drop = FALSE]
  df[["text"]] <- paste0("<pre class=\"msg\">", html_escape(df[["text"]]), "</pre>")
  html_table(df, c("Section", "Type", "Text"), html = "text")
}

qc_inputs_html <- function(DNAm, pheno, x) {
  df <- data.frame(
    input = c("DNAm", "pheno", "x"),
    value = c(
      if (is.null(DNAm)) "Not supplied" else sprintf("%s samples, %s CpGs", fmt_int(nrow(DNAm)), fmt_int(ncol(DNAm))),
      if (is.null(pheno)) "Not supplied" else sprintf("%s rows, %s column%s", fmt_int(nrow(pheno)), fmt_int(ncol(pheno)), if (ncol(pheno) == 1L) "" else "s"),
      if (is.null(x)) "Not supplied" else sprintf("%s samples, %s clocks", fmt_int(nrow(x[["scores"]])), fmt_int(ncol(x[["scores"]])))
    ),
    stringsAsFactors = FALSE
  )
  html_table(df, c("Input", "Shape"))
}

# the time stamped in the page header. a function, so a test can fix it.
qc_now <- function() Sys.time()

qc_page <- function(title, sections, st, DNAm, pheno, x, age_plot) {
  cards_html <- vapply(sections[1:3], function(s) {
    paste0(
      "<div class=\"card-group\"><h3>", html_escape(s[["heading"]]), "</h3><div class=\"cards\">",
      paste(vapply(s[["cards"]], function(cd) {
        stat_card(cd[["label"]], cd[["value"]], cd[["status"]], cd[["detail"]])
      }, character(1L)), collapse = ""),
      "</div></div>"
    )
  }, character(1L))
  findings <- c(unlist(lapply(sections, `[[`, "findings"), use.names = FALSE), age_plot[["findings"]], ctx_findings_html(st))
  rank <- function(f) {
    if (grepl("chip bad", f, fixed = TRUE)) 1L
    else if (grepl("chip warn", f, fixed = TRUE)) 2L
    else if (grepl("chip info", f, fixed = TRUE)) 3L
    else if (grepl("chip na", f, fixed = TRUE)) 4L
    else 5L
  }
  findings <- findings[order(vapply(findings, rank, integer(1L)))]
  nav <- paste0(
    "<nav><a href=\"#overview\">Overview</a>",
    paste0("<a href=\"#", vapply(sections, `[[`, character(1L), "id"), "\">",
           html_escape(vapply(sections, `[[`, character(1L), "heading")), "</a>", collapse = ""),
    "<a href=\"#notes\">Messages</a></nav>"
  )
  body_sections <- paste0(
    "<section id=\"", vapply(sections, `[[`, character(1L), "id"), "\"><h2>",
    html_escape(vapply(sections, `[[`, character(1L), "heading")), "</h2>",
    vapply(sections, `[[`, character(1L), "body"), "</section>",
    collapse = ""
  )
  ver <- tryCatch(as.character(utils::packageVersion("methylCIPHERv2")), error = function(e) "unknown")
  paste0(
    "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\">",
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    "<title>", html_escape(title), "</title><style>", QC_CSS,
    toggle_css(c("none", "age", "sex", "both")),
    if (ctx_on(st)) paste(c(QC_CONTEXT_CSS, st[["ctx_css"]]), collapse = "\n"),
    "</style></head><body>",
    "<header><h1>", html_escape(title), "</h1><p class=\"meta\">",
    html_escape(sprintf("Written %s by methylCIPHERv2 %s, %s.",
                        format(qc_now(), "%Y-%m-%d %H:%M"), ver, R.version.string)),
    "</p>", nav, "</header><main>",
    "<section id=\"overview\"><h2>Overview</h2>", qc_inputs_html(DNAm, pheno, x),
    ctx_overview_html(st),
    "<h3>Key findings</h3><ul class=\"findings\">", paste(findings, collapse = ""), "</ul>",
    age_plot[["html"]], paste(cards_html, collapse = ""), ctx_cards_html(st), "</section>",
    body_sections,
    "<section id=\"notes\"><h2>Messages raised while building the report</h2>", qc_notes_html(st), "</section>",
    "</main></body></html>"
  )
}

QC_CSS <- "
:root{color-scheme:light;
--page:#f9f9f7;--surface:#fcfcfb;--ink-1:#0b0b0b;--ink-2:#52514e;--ink-3:#898781;
--grid:#e1e0d9;--axis:#c3c2b7;--ring:rgba(11,11,11,.10);
--s1:#2a78d6;--s2:#eb6834;--s3:#1baf7a;--s4:#eda100;--s5:#e87ba4;--s6:#008300;--s7:#4a3aa7;--s8:#e34948;
--good:#0ca30c;--warn:#fab219;--serious:#ec835a;--crit:#d03b3b;--good-ink:#006300;
--good-bg:rgba(12,163,12,.10);--warn-bg:rgba(250,178,25,.16);--crit-bg:rgba(208,59,59,.10);--na-bg:rgba(137,135,129,.12);--info-bg:rgba(42,120,214,.08)}
@media (prefers-color-scheme:dark){:root:not([data-theme=\"light\"]){color-scheme:dark;
--page:#0d0d0d;--surface:#1a1a19;--ink-1:#fff;--ink-2:#c3c2b7;--ink-3:#898781;
--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);
--s1:#3987e5;--s2:#d95926;--s3:#199e70;--s4:#c98500;--s5:#d55181;--s6:#008300;--s7:#9085e9;--s8:#e66767;--good-ink:#0ca30c}}
:root[data-theme=\"dark\"]{color-scheme:dark;
--page:#0d0d0d;--surface:#1a1a19;--ink-1:#fff;--ink-2:#c3c2b7;--ink-3:#898781;
--grid:#2c2c2a;--axis:#383835;--ring:rgba(255,255,255,.10);
--s1:#3987e5;--s2:#d95926;--s3:#199e70;--s4:#c98500;--s5:#d55181;--s6:#008300;--s7:#9085e9;--s8:#e66767;--good-ink:#0ca30c}
*{box-sizing:border-box}
body{margin:0;background:var(--page);color:var(--ink-1);font:15px/1.55 system-ui,-apple-system,'Segoe UI',sans-serif}
header{background:var(--surface);border-bottom:1px solid var(--ring);padding:20px 16px 0;position:sticky;top:0;z-index:2}
header h1{margin:0;font-size:1.45rem;font-weight:600}
.meta{margin:4px 0 10px;color:var(--ink-2);font-size:.86rem}
nav{display:flex;gap:4px;overflow-x:auto;padding-bottom:8px}
nav a{color:var(--ink-2);text-decoration:none;padding:4px 10px;border-radius:6px;white-space:nowrap;font-size:.9rem}
nav a:hover{background:var(--info-bg);color:var(--ink-1)}
main{max-width:1180px;margin:0 auto;padding:8px 16px 60px}
section{background:var(--surface);border:1px solid var(--ring);border-radius:10px;padding:8px 20px 20px;margin:18px 0;scroll-margin-top:110px}
h2{font-size:1.25rem;font-weight:600;margin:14px 0 8px}
h3{font-size:1.05rem;font-weight:600;margin:22px 0 8px;scroll-margin-top:110px}
h4{font-size:.95rem;font-weight:600;margin:18px 0 6px;color:var(--ink-2)}
p{max-width:80ch}
.note{color:var(--ink-2);font-size:.86rem}
.na-box{background:var(--na-bg);border-radius:8px;padding:10px 14px;color:var(--ink-2);margin:8px 0}
.table-wrap{overflow-x:auto;margin:8px 0}
.qc-table{border-collapse:collapse;font-size:.86rem;min-width:40%}
.qc-table th{text-align:left;font-weight:600;color:var(--ink-2);border-bottom:1px solid var(--axis);padding:6px 10px;white-space:nowrap}
.qc-table td{border-bottom:1px solid var(--grid);padding:5px 10px;vertical-align:top}
.qc-table .num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.qc-table tbody tr:hover{background:var(--info-bg)}
.bar{display:inline-block;width:90px;height:8px;background:var(--grid);border-radius:4px;vertical-align:middle;margin-right:8px;overflow:hidden}
.bar-fill{display:block;height:100%;border-radius:4px}
.bar-fill.ok{background:var(--good)}.bar-fill.warn{background:var(--warn)}.bar-fill.bad{background:var(--crit)}
.bar-fill.info{background:var(--s1)}.bar-fill.na{background:var(--ink-3)}
.bar-val{font-variant-numeric:tabular-nums}
.bar-cell{white-space:nowrap}
.chip{display:inline-flex;align-items:center;gap:5px;border-radius:999px;padding:1px 9px 1px 3px;font-size:.8rem;font-weight:500;white-space:nowrap}
.chip-icon{display:inline-flex;align-items:center;justify-content:center;width:16px;height:16px;border-radius:50%;font-size:.68rem;font-weight:700;color:#fff}
.chip.ok{background:var(--good-bg)}.chip.ok .chip-icon{background:var(--good)}
.chip.warn{background:var(--warn-bg)}.chip.warn .chip-icon{background:var(--warn);color:#0b0b0b}
.chip.bad{background:var(--crit-bg)}.chip.bad .chip-icon{background:var(--crit)}
.chip.na{background:var(--na-bg)}.chip.na .chip-icon{background:var(--ink-3)}
.chip.info{background:var(--info-bg)}.chip.info .chip-icon{background:var(--s1)}
.findings{list-style:none;padding:0;margin:8px 0 12px}
.findings li{padding:5px 0;border-bottom:1px solid var(--grid)}
.card-group h3{margin-top:18px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px}
.card{border:1px solid var(--ring);border-left:4px solid var(--ink-3);border-radius:8px;padding:8px 12px;background:var(--surface)}
.card.ok{border-left-color:var(--good)}.card.warn{border-left-color:var(--warn)}.card.bad{border-left-color:var(--crit)}
.card.info{border-left-color:var(--s1)}.card.na{border-left-color:var(--ink-3);background:var(--na-bg)}
.card-lbl{font-size:.78rem;color:var(--ink-2)}
.card-val{font-size:1.2rem;font-weight:600;margin:2px 0}
.card.na .card-val{font-size:.95rem;color:var(--ink-2);font-weight:500}
.card-detail{font-size:.76rem;color:var(--ink-3)}
figure{margin:10px 0 16px}
figcaption{color:var(--ink-2);font-size:.84rem;margin-top:4px;max-width:80ch}
svg.chart{width:100%;max-width:720px;height:auto;display:block}
svg .grid{stroke:var(--grid);stroke-width:1}
svg .axis{stroke:var(--axis);stroke-width:1}
svg .tick{fill:var(--ink-3);font-size:11px;font-variant-numeric:tabular-nums}
svg .axis-title{fill:var(--ink-2);font-size:12px}
svg .ref{stroke:var(--ink-3);stroke-width:1;stroke-dasharray:4 4}
svg .ref-label{fill:var(--ink-2);font-size:11px}
svg .band{stroke:var(--ink-3);stroke-opacity:.35;stroke-width:8;stroke-linecap:round}
svg .exp{fill:var(--surface);stroke:var(--ink-3);stroke-width:2}
svg .pts circle{stroke:var(--surface);stroke-width:1.5}
svg .pts circle:hover{stroke:var(--ink-1)}
svg rect.bin:hover{opacity:.8}
.legend{display:flex;flex-wrap:wrap;gap:6px 16px;font-size:.84rem;color:var(--ink-2);margin-bottom:4px}
.lg-item{display:inline-flex;align-items:center;gap:6px}
.lg-sw{width:12px;height:12px;border-radius:3px;display:inline-block}
.lg-toggle{cursor:pointer;user-select:none}.lg-toggle input{margin:0}
.problems{list-style:none;padding:0;margin:8px 0 12px}
.problems li{padding:6px 0;border-bottom:1px solid var(--grid)}
.problems .clocks{display:block;color:var(--ink-2);font-size:.86rem;margin-top:2px}
.plots{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}
.cell{border:1px solid var(--ring);border-radius:8px;padding:8px}
.cell-title{font-size:.86rem;font-weight:600;margin-bottom:4px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.cell svg.chart{max-width:none}
.refs li{margin:6px 0}
.ref-clocks{display:block;color:var(--ink-3);font-size:.8rem}
a{color:var(--s1)}
pre.bibtex,pre.msg{white-space:pre-wrap;font-size:.8rem;background:var(--page);border-radius:6px;padding:8px;margin:0;max-height:420px;overflow:auto}
pre.msg{background:transparent;padding:0;max-height:none}
details summary{cursor:pointer;color:var(--ink-2);margin:10px 0 6px}
@media (max-width:640px){section{padding:6px 12px 14px}.cards{grid-template-columns:1fr 1fr}}
"
