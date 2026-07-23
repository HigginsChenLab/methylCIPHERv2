# DNAm/pheno validation and clock-id resolution

check_DNAm <- function(DNAm) {
  checkmate::assert_matrix(
    DNAm,
    mode = "double",
    min.rows = 1,
    min.cols = 1
  )
  checkmate::assert_character(colnames(DNAm), unique = TRUE, null.ok = FALSE)
  checkmate::assert_character(rownames(DNAm), unique = TRUE, null.ok = FALSE)
  # orientation guard: CpG ids belong in columns (cg prefix)
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

# Zhang2019 full-panel notice only
resolve_DNAm_extra <- function(clock_ids) {
  if ("Zhang2019" %in% clock_ids) {
    message(
      "Zhang2019's original code computes per-sample moments over all CpGs. ",
      "A large-enough subset of CpGs is usually sufficient."
    )
  }
  invisible(TRUE)
}

# structure/dtype validation for pheno
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

# warn once when required covariates contain NA
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
  # count only rows that will survive the id-join
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

# align pheno onto sample_id (id-join, or row-order when positional)
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

# user tokens -> catalog clock_ids -- precedence: "all" > group_id > clock_id
resolve_clocks <- function(clocks) {
  checkmate::assert_character(
    clocks,
    min.len = 1L,
    any.missing = FALSE,
    min.chars = 1L,
    .var.name = "clocks"
  )

  members <- split(mc_index[["clock_id"]], mc_index[["group_id"]])
  clock_ids <- mc_index[["clock_id"]]

  # a routed member is one sex's model -- scoring it directly would return a
  # plausible number for every sample of the other sex -- it stays internal
  # machinery, reached only as its alias's dependency
  routed <- sex_routed_members()
  asked_routed <- intersect(clocks, names(routed$alias))
  if (length(asked_routed)) {
    stop(
      "Clock(s) not directly callable -- sex is resolved per sample, not by id: ",
      paste0(
        asked_routed,
        " (use '",
        routed$alias[asked_routed],
        "')",
        collapse = ", "
      ),
      call. = FALSE
    )
  }
  callable <- setdiff(clock_ids, names(routed$alias))

  resolve_one <- function(tok) {
    if (tok == "all") {
      return(callable)
    }
    if (!is.null(members[[tok]])) {
      return(intersect(members[[tok]], callable))
    }
    if (tok %in% callable) {
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

# transitive depends_on_clocks closure, deps before dependents
resolve_clocks_sequence <- function(clocks) {
  st <- new.env(parent = emptyenv())
  st$out <- character(length(mc_index[["clock_id"]]))
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

# map identical CpG panels onto a shared set -- every member of an external pack
# group carries the same panel, so the set math runs once instead of once per
# clock
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

# scoring + norm panels for the compute sequence, fetched once and deduped --
# external panels come from `packs`, so resolve those before calling this
clock_panels <- function(clock_sequence, packs = NULL) {
  list(
    clock_id = clock_sequence,
    score = dedup_panels(lapply(
      clock_sequence,
      clock_scoring_cpgs,
      packs = packs
    )),
    norm = dedup_panels(lapply(clock_sequence, clock_norm_cpgs))
  )
}

# union of scoring + norm CpGs across the compute sequence
panels_union <- function(panels) {
  unique(unlist(c(panels$score$uniq, panels$norm$uniq), use.names = FALSE))
}

# per-clock present/absent CpG sets over usable_cols
resolve_cpgs <- function(usable_cols, panels) {
  usable <- unique(usable_cols)
  clock_sequence <- panels$clock_id

  # split each distinct panel once -- member clocks share the resulting vectors
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

# graded coverage gate, run once before any scoring -- under `threshold` (or 0
# observed CpGs on a panel) stops, clearing it by under 10% warns
WARN_COVERAGE_MARGIN <- 1.1

# mass failure is usually one root cause (transposed DNAm, wrong array), so cap
coverage_block <- function(lines) {
  shown <- utils::head(lines, 10L)
  paste0(
    paste(shown, collapse = "\n"),
    if (length(lines) > length(shown)) {
      sprintf("\n  ... and %d more", length(lines) - length(shown))
    } else {
      ""
    }
  )
}

check_coverage <- function(cpg_list, threshold = 0.75) {
  checkmate::assert_number(threshold, lower = 0, upper = 1)
  warn_below <- min(1, threshold * WARN_COVERAGE_MARGIN)

  # panels a clock actually has -- a clock with none is gated elsewhere
  clock_panels_used <- function(x) {
    Filter(
      function(q) length(q$needed) > 0L,
      list(
        list(
          label = "scoring",
          present = x$score_present,
          needed = x$score_needed
        ),
        list(
          label = "normalization",
          present = x$norm_present,
          needed = x$norm_needed
        )
      )
    )
  }

  # worst panel per clock -> "stop", "warn", or "" (fine)
  classify <- function(x) {
    worst <- NULL
    worst_ratio <- Inf
    for (q in clock_panels_used(x)) {
      ratio <- length(q$present) / length(q$needed)
      if (ratio < worst_ratio) {
        worst_ratio <- ratio
        worst <- q
      }
    }
    if (is.null(worst)) {
      return(list(level = "", line = NA_character_))
    }
    level <- if (worst_ratio == 0 || worst_ratio < threshold) {
      "stop"
    } else if (worst_ratio < warn_below) {
      # full coverage is never marginal, whatever the threshold
      "warn"
    } else {
      ""
    }
    list(
      level = level,
      line = sprintf(
        "  %s: %d/%d %s CpGs (%.1f%%)",
        x$clock_id,
        length(worst$present),
        length(worst$needed),
        worst$label,
        100 * worst_ratio
      )
    )
  }

  graded <- lapply(cpg_list$per_clock, classify)
  levels <- vapply(graded, function(g) g$level, character(1L))
  lines_for <- function(lvl) {
    vapply(graded[levels == lvl], function(g) g$line, character(1L))
  }

  fail <- lines_for("stop")
  if (length(fail)) {
    stop(
      sprintf(
        "%d clock(s) lack the CpG coverage to score (min_col_coverage = %s):\n%s\nDrop them from `clocks`, or lower `min_col_coverage` (a clock with 0 observed CpGs never scores).",
        length(fail),
        format(threshold),
        coverage_block(fail)
      ),
      call. = FALSE
    )
  }

  marginal <- lines_for("warn")
  if (length(marginal)) {
    warning(
      sprintf(
        "%d clock(s) clear min_col_coverage = %s by under 10%% -- scores are usable but rest on an imputed fraction of the panel:\n%s",
        length(marginal),
        format(threshold),
        coverage_block(marginal)
      ),
      call. = FALSE
    )
  }

  invisible(names(levels)[levels != ""])
}

# per-sample observed fraction of a clock's needed panel
row_coverage <- function(r) {
  cov <- r[["coverage"]]
  if (is.null(cov) || is.null(r[["sample_miss"]])) {
    return(NULL)
  }
  # denominator matches the panel sample_miss counted over (norm when present)
  qn <- isTRUE(cov[["norm_needed"]] > 0L)
  needed <- if (qn) cov[["norm_needed"]] else cov[["score_needed"]]
  present <- if (qn) cov[["norm_present"]] else cov[["score_present"]]
  if (!length(needed) || needed == 0L) {
    return(NULL)
  }
  (present - r[["sample_miss"]]) / needed
}

# post-score per-sample coverage gate -- warns only, never NA-s scores
check_row_coverage <- function(results, threshold = 0.75) {
  checkmate::assert_number(threshold, lower = 0, upper = 1)

  line_for <- function(id) {
    rc <- row_coverage(results[[id]])
    if (is.null(rc)) {
      return(NA_character_)
    }
    low <- !is.na(rc) & rc < threshold
    if (!any(low)) {
      return(NA_character_)
    }
    sprintf(
      "  %s: %d of %d sample(s), worst %.1f%% of %d CpGs",
      id,
      sum(low),
      sum(!is.na(rc)),
      100 * min(rc[low]),
      results[[id]][["coverage"]][["score_needed"]]
    )
  }

  lines <- vapply(names(results), line_for, character(1L))
  lines <- lines[!is.na(lines)]
  if (length(lines)) {
    warning(
      sprintf(
        "%d clock(s) scored sample(s) under min_row_coverage = %s -- those scores rest on imputed CpGs for the samples listed:\n%s",
        length(lines),
        format(threshold),
        coverage_block(lines)
      ),
      call. = FALSE
    )
  }

  invisible(names(lines))
}
