# DNAm/pheno validation and clock-id resolution.

check_DNAm <- function(DNAm) {
  checkmate::assert_matrix(
    DNAm,
    mode = "double",
    min.rows = 1,
    min.cols = 1
  )
  checkmate::assert_character(colnames(DNAm), unique = TRUE, null.ok = FALSE)
  checkmate::assert_character(rownames(DNAm), unique = TRUE, null.ok = FALSE)
  # Orientation guard: CpG ids belong in columns (cg prefix).
  if (ncol(DNAm) < 2e5 && !any(startsWith(colnames(DNAm), "cg"))) {
    warning(
      if (any(startsWith(rownames(DNAm), "cg"))) {
        "DNAm looks transposed: CpG ids (cg...) are in the rows. "
      } else {
        "No DNAm column names look like CpG ids (cg...). "
      },
      "calc_clocks() expects samples in rows and CpGs in columns; pass t(DNAm) to transpose.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

# Zhang2019 full-panel notice only.
resolve_DNAm_extra <- function(clock_ids) {
  if ("Zhang2019" %in% clock_ids) {
    message(
      "Zhang2019's original code computes per-sample moments over all CpGs. ",
      "A large-enough subset of CpGs is usually sufficient."
    )
  }
  invisible(TRUE)
}

# Structure/dtype validation for pheno.
check_pheno <- function(
  pheno,
  ID = NULL,
  extra_columns = NULL,
  positional = FALSE,
  sample_id = NULL
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
  warn_missing_covariates(pheno, ID, extra_columns, positional, sample_id)
  invisible(TRUE)
}

# Warn once when required covariates contain NA.
warn_missing_covariates <- function(
  pheno,
  ID,
  extra_columns,
  positional,
  sample_id
) {
  cols <- intersect(extra_columns, names(pheno))
  if (!length(cols)) {
    return(invisible(character(0)))
  }
  # Count only rows that will survive the id-join.
  rows <- if (positional || is.null(sample_id)) {
    seq_len(nrow(pheno))
  } else {
    idx <- match(sample_id, pheno[[ID]])
    idx[!is.na(idx)]
  }

  n_na <- vapply(cols, function(cl) sum(is.na(pheno[[cl]][rows])), integer(1L))
  n_na <- n_na[n_na > 0L]
  if (!length(n_na)) {
    return(invisible(character(0)))
  }

  warning(
    "pheno has missing values in covariate(s) ",
    paste0(names(n_na), " (", n_na, " sample(s))", collapse = ", "),
    ". Clocks that need them return NA for those samples; every other sample scores normally.",
    call. = FALSE
  )
  invisible(names(n_na))
}

# Align pheno onto sample_id (id-join, or row-order when positional).
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

# Transitive depends_on_clocks closure, deps before dependents.
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

# Map identical CpG panels onto a shared set. Every member of an external pack
# group carries the same panel, so the set math runs once instead of once per clock.
dedup_panels <- function(panels) {
  uniq <- list()
  idx <- integer(length(panels))
  for (i in seq_along(panels)) {
    hit <- 0L
    for (j in seq_along(uniq)) {
      if (identical(panels[[i]], uniq[[j]])) {
        hit <- j
        break
      }
    }
    if (!hit) {
      uniq[[length(uniq) + 1L]] <- panels[[i]]
      hit <- length(uniq)
    }
    idx[[i]] <- hit
  }
  list(uniq = uniq, idx = idx)
}

# Scoring + norm panels for the compute sequence, fetched once and deduped.
clock_panels <- function(clock_sequence) {
  list(
    clock_id = clock_sequence,
    score = dedup_panels(lapply(clock_sequence, clock_scoring_cpgs)),
    norm = dedup_panels(lapply(clock_sequence, clock_norm_cpgs))
  )
}

# Union of scoring + norm CpGs across the compute sequence.
panels_union <- function(panels) {
  unique(unlist(c(panels$score$uniq, panels$norm$uniq), use.names = FALSE))
}

needed_cpgs_union <- function(clock_sequence) {
  panels_union(clock_panels(clock_sequence))
}

# Per-clock present/absent CpG sets over usable_cols.
resolve_cpgs <- function(usable_cols, panels) {
  usable <- unique(usable_cols)
  clock_sequence <- panels$clock_id

  # Split each distinct panel once; member clocks share the resulting vectors.
  split_panels <- function(d) {
    lapply(d$uniq, function(p) {
      hit <- match(p, usable, 0L) > 0L
      list(needed = p, present = p[hit], absent = p[!hit])
    })
  }
  score_parts <- split_panels(panels$score)
  norm_parts <- split_panels(panels$norm)

  per_clock <- lapply(seq_along(clock_sequence), function(i) {
    s <- score_parts[[panels$score$idx[[i]]]]
    nm <- norm_parts[[panels$norm$idx[[i]]]]
    list(
      clock_id = clock_sequence[[i]],
      score_needed = s$needed,
      score_present = s$present,
      score_absent = s$absent,
      norm_needed = nm$needed,
      norm_present = nm$present,
      norm_absent = nm$absent,
      norm_scheme = clock_norm_scheme(clock_sequence[[i]])
    )
  })
  names(per_clock) <- clock_sequence

  present_needed_union <- unique(unlist(
    lapply(c(score_parts, norm_parts), function(x) x$present),
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
