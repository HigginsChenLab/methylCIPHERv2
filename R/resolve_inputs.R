# DNAm/pheno validation and clock-id resolution (identity settled in calc_clocks).

check_DNAm <- function(DNAm) {
  checkmate::assert_matrix(
    DNAm,
    mode = "double",
    min.rows = 1,
    min.cols = 1
  )
  checkmate::assert_character(colnames(DNAm), unique = TRUE, null.ok = FALSE)
  checkmate::assert_character(rownames(DNAm), unique = TRUE, null.ok = FALSE)
  # Orientation heuristics; skip on wide panels where orientation is unambiguous.
  if (ncol(DNAm) < 2e5) {
    if (nrow(DNAm) > ncol(DNAm)) {
      warning(
        "DNAm should be formatted as samples * CpG. Currently DNAm has more rows (samples) than columns (CpGs), which is highly unlikely. Pass the full DNAm matrix without pre-subsetting to `calc_clock()`."
      )
    }
    if (!any(startsWith(colnames(DNAm), "cg"))) {
      warning(
        "It looks like you may need to format DNAm using t(DNAm) to get samples as rows!"
      )
    }
  }
  invisible(TRUE)
}

# Zhang2019 full-panel notice only (side effect).
resolve_DNAm_extra <- function(clock_ids) {
  if ("Zhang2019" %in% clock_ids) {
    message(
      "Zhang2019's original code computes per-sample moments over all CpGs. ",
      "A large-enough subset of CpGs is usually sufficient."
    )
  }
  invisible(TRUE)
}

# Structure/dtype validation; identity alignment is resolve_pheno()'s job.
check_pheno <- function(
  pheno,
  ID = NULL,
  extra_columns = NULL,
  positional = FALSE
) {
  if (is.null(pheno)) {
    return(invisible(TRUE))
  }
  checkmate::assert_data_frame(pheno, min.rows = 1)
  if (!positional) {
    checkmate::assert_string(ID, null.ok = FALSE)
    checkmate::assert_choice(ID, names(pheno))
    checkmate::assert_character(
      pheno[[ID]],
      any.missing = FALSE,
      unique = TRUE,
      null.ok = FALSE
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
  invisible(TRUE)
}

# Align pheno onto sample_id (id-join, or row-order when positional). Returns ordered pheno or NULL.
resolve_pheno <- function(DNAm, pheno, pheno_id, positional_ids) {
  if (is.null(pheno)) {
    return(NULL)
  }
  sample_id <- rownames(DNAm)

  if (positional_ids) {
    if (nrow(pheno) != nrow(DNAm)) {
      stop(
        "DNAm has no rownames, so pheno is aligned by row order and must have exactly ",
        nrow(DNAm),
        " row(s) to match DNAm (got ",
        nrow(pheno),
        "). ",
        "Give DNAm rownames to align pheno by id instead.",
        call. = FALSE
      )
    }
    pheno[[pheno_id]] <- sample_id
    return(pheno)
  }
  missing <- setdiff(sample_id, pheno[[pheno_id]])
  if (length(missing)) {
    stop(
      "pheno is missing ",
      length(missing),
      " sample id(s) present in rownames(DNAm): ",
      paste(utils::head(missing, 10L), collapse = ", "),
      if (length(missing) > 10L) ", ..." else "",
      call. = FALSE
    )
  }
  pheno <- pheno[match(sample_id, pheno[[pheno_id]]), , drop = FALSE]
  pheno
}

# User tokens -> catalog clock_ids. Precedence: "all" > group_id > clock_id.
resolve_clocks <- function(clocks) {
  checkmate::assert_character(
    clocks,
    min.len = 1L,
    any.missing = FALSE,
    min.chars = 1L,
    .var.name = "clocks"
  )

  members <- split(mc_index$clock_id, mc_index$group_id)
  clock_ids <- mc_index$clock_id

  resolve_one <- function(tok) {
    if (tok == "all") {
      return(clock_ids)
    }
    if (!is.null(members[[tok]])) {
      return(members[[tok]])
    }
    if (tok %in% clock_ids) {
      return(tok)
    }
    NULL
  }

  resolved <- lapply(clocks, resolve_one)
  bad <- clocks[vapply(resolved, is.null, logical(1L))]

  if (length(bad)) {
    stop(
      "Unknown clock requested(s): ",
      paste(unique(bad), collapse = ", "),
      call. = FALSE
    )
  }

  out <- unlist(resolved, use.names = FALSE)
  out[!duplicated(out)]
}

# Transitive depends_on_clocks closure, deps before dependents. Input must be catalog ids.
resolve_clocks_sequence <- function(clocks) {
  st <- new.env(parent = emptyenv())
  st$out <- character(length(mc_index$clock_id))
  st$n <- 0L
  st$seen <- new.env(parent = emptyenv())

  visit <- function(id, stack) {
    if (!is.null(st$seen[[id]])) {
      return(invisible())
    }
    if (id %in% stack) {
      stop(
        "Dependency cycle among clocks: ",
        paste(c(stack[match(id, stack):length(stack)], id), collapse = " -> "),
        call. = FALSE
      )
    }
    for (dep in clock_depends_on(id)) {
      visit(dep, c(stack, id))
    }
    st$n <- st$n + 1L
    st$out[[st$n]] <- id
    st$seen[[id]] <- TRUE
    invisible()
  }

  for (id in clocks) {
    visit(id, character(0))
  }
  st$out[seq_len(st$n)]
}

# Union of scoring + norm CpGs across the compute sequence.
needed_cpgs_union <- function(clock_sequence) {
  unique(unlist(
    lapply(clock_sequence, function(id) {
      c(clock_scoring_cpgs(id), clock_norm_cpgs(id))
    }),
    use.names = FALSE
  ))
}

# Per-clock present/absent CpG sets over usable_cols (pure set math).
resolve_cpgs <- function(usable_cols, clock_sequence) {
  usable <- unique(usable_cols)

  one <- function(id) {
    score_needed <- clock_scoring_cpgs(id)
    norm_needed <- clock_norm_cpgs(id)
    list(
      clock_id = id,
      score_needed = score_needed,
      score_present = intersect(score_needed, usable),
      score_absent = setdiff(score_needed, usable),
      norm_needed = norm_needed,
      norm_present = intersect(norm_needed, usable),
      norm_absent = setdiff(norm_needed, usable),
      norm_scheme = clock_norm_scheme(id)
    )
  }

  per_clock <- lapply(clock_sequence, one)
  names(per_clock) <- clock_sequence

  present_needed_union <- unique(unlist(
    lapply(per_clock, function(x) x$score_present),
    use.names = FALSE
  ))

  list(per_clock = per_clock, present_needed_union = present_needed_union)
}

# Warn when a clock's present/needed scoring ratio falls below threshold.
warn_low_coverage <- function(cpg_list, threshold = 0.8) {
  checkmate::assert_number(threshold, lower = 0, upper = 1)
  if (threshold <= 0) {
    return(invisible(character(0)))
  }

  ratios <- vapply(
    cpg_list$per_clock,
    function(x) {
      n <- length(x$score_needed)
      if (!n) NA_real_ else length(x$score_present) / n
    },
    numeric(1L)
  )
  low <- which(!is.na(ratios) & ratios < threshold)
  if (!length(low)) {
    return(invisible(character(0)))
  }

  ids <- names(ratios)[low]
  lines <- vapply(
    low,
    function(i) {
      x <- cpg_list$per_clock[[i]]
      sprintf(
        "  %s: %d/%d (%.1f%%)",
        x$clock_id,
        length(x$score_present),
        length(x$score_needed),
        100 * ratios[[i]]
      )
    },
    character(1L)
  )
  warning(
    sprintf(
      "%d clock(s) score on under %.0f%% of their scoring CpGs:\n%s",
      length(low),
      100 * threshold,
      paste(lines, collapse = "\n")
    ),
    call. = FALSE
  )
  invisible(ids)
}
