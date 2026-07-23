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
  # cg... ids should be columns
  if (ncol(DNAm) < 2e5 && !any(startsWith(colnames(DNAm), "cg"))) {
    cli::cli_warn(
      c(
        if (any(startsWith(rownames(DNAm), "cg"))) {
          "DNAm looks transposed -- CpG ids (cg...) are in the rows."
        } else {
          "No DNAm column names look like CpG ids (cg...)."
        },
        "i" = "{.fn calc_clocks} wants samples in rows and CpGs in columns.
               Try {.code t(DNAm)} if yours is the other way around."
      ),
      call = NULL
    )
  }
  invisible(TRUE)
}

# Zhang2019 uses full-matrix moments
resolve_DNAm_extra <- function(clock_ids) {
  if ("Zhang2019" %in% clock_ids) {
    cli::cli_inform(c(
      "i" = "Zhang2019 takes per-sample moments over all CpGs -- a large subset
             is usually enough."
    ))
  }
  invisible(TRUE)
}

# pheno structure checks
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

# warn on NA in required covariates
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
  # only rows that survive the id-join
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
      "i" = "Clocks that need them score NA for those samples."
    ),
    call = NULL
  )
  invisible(names(n_na))
}

# align pheno to sample_id (id-join, or row-order when positional)
resolve_pheno <- function(DNAm, pheno, pheno_id, positional_ids) {
  if (is.null(pheno)) {
    return(NULL)
  }
  sample_id <- rownames(DNAm)

  if (positional_ids) {
    if (nrow(pheno) != nrow(DNAm)) {
      cli::cli_abort(
        c(
          "DNAm has no rownames, so pheno is matched by row order and needs
           exactly {nrow(DNAm)} row{?s} (got {nrow(pheno)}).",
          "i" = "Set DNAm rownames to join pheno by id instead."
        ),
        call = NULL
      )
    }
    pheno[[pheno_id]] <- sample_id
    return(pheno)
  }
  missing <- setdiff(sample_id, pheno[[pheno_id]])
  if (length(missing)) {
    cli::cli_abort(
      c(
        "pheno is missing {length(missing)} sample id{?s} from DNAm:",
        "x" = "{.val {utils::head(missing, 10L)}}"
      ),
      call = NULL
    )
  }
  pheno <- pheno[match(sample_id, pheno[[pheno_id]]), , drop = FALSE]
  pheno
}

# suggestion pools: names are matched, values are recommended tokens
suggestion_pools <- function() {
  routed <- sex_routed_members()
  callable <- setdiff(mc_index[["clock_id"]], names(routed$alias))
  groups <- unique(mc_index[["group_id"]])
  list(
    clock = c(stats::setNames(callable, callable), routed$alias),
    group = stats::setNames(groups, groups)
  )
}

# nearest pool entries for a typo (case-insensitive, substring-friendly)
did_you_mean <- function(tok, pool, n = 5L) {
  d <- utils::adist(tok, names(pool), ignore.case = TRUE, partial = TRUE)[1L, ]
  utils::head(unique(unname(pool[order(d, nchar(names(pool)))])), n)
}

# one unmatched token with nearest groups and clocks
suggestion_bullets <- function(toks, pools = suggestion_pools(), n = 5L) {
  unlist(lapply(toks, function(tok) {
    c(
      "*" = cli::format_inline("{.val {tok}}"),
      " " = cli::format_inline(
        "groups: {.or {.val {did_you_mean(tok, pools$group, n)}}}"
      ),
      " " = cli::format_inline(
        "clocks: {.or {.val {did_you_mean(tok, pools$clock, n)}}}"
      )
    )
  }))
}

# user tokens -> catalog clock_ids
# precedence: "all" > tag > group_id > clock_id
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

  # sex-routed members are internal; request the alias instead
  routed <- sex_routed_members()
  asked_routed <- intersect(clocks, names(routed$alias))
  if (length(asked_routed)) {
    cli::cli_abort(
      c(
        "Can't request {length(asked_routed)} sex-specific model{?s}
         directly:",
        bullets(vapply(
          asked_routed,
          function(tok) {
            cli::format_inline(
              "{.val {tok}} -- try {.val {routed$alias[[tok]]}} instead"
            )
          },
          character(1L)
        )),
        "i" = "Sex is chosen per sample from {.arg pheno}."
      ),
      call = NULL
    )
  }
  callable <- setdiff(clock_ids, names(routed$alias))

  resolve_member <- function(tok) {
    if (!is.null(members[[tok]])) {
      return(intersect(members[[tok]], callable))
    }
    if (tok %in% callable) {
      return(tok)
    }
    NULL
  }

  resolve_one <- function(tok) {
    if (tok == "all") {
      return(callable)
    }
    tag <- MC_TAGS[[tok]]
    if (!is.null(tag)) {
      hits <- lapply(tag, resolve_member)
      dead <- tag[vapply(hits, is.null, logical(1L))]
      if (length(dead)) {
        cli::cli_abort(
          c(
            "Keyword {.val {tok}} points at missing token{?s}: {.val {dead}}.",
            "i" = "This is a package bug -- please report it."
          ),
          call = NULL
        )
      }
      return(unique(unlist(hits, use.names = FALSE)))
    }
    resolve_member(tok)
  }

  resolved <- lapply(clocks, resolve_one)
  bad <- clocks[vapply(resolved, is.null, logical(1L))]

  if (length(bad)) {
    bad <- unique(bad)
    cli::cli_abort(
      c(
        "{length(bad)} bad input{?s} passed: {.val {bad}}.",
        "i" = "Closest matches:",
        suggestion_bullets(bad),
        "i" = "See {.fn list_clocks} or {.fn list_tags}
               ({.val {names(MC_TAGS)}})."
      ),
      call = NULL
    )
  }

  out <- unlist(resolved, use.names = FALSE)
  out[!duplicated(out)]
}

# depends_on_clocks closure, deps before dependents
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
      cycle <- c(stack[match(id, stack):length(stack)], id)
      cli::cli_abort(
        "Dependency cycle among clocks: {paste(cycle, collapse = ' -> ')}",
        call = NULL
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

# collapse identical CpG panels
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

# scoring + norm panels for the compute sequence (load packs first)
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

# union of scoring + norm CpGs
panels_union <- function(panels) {
  unique(unlist(c(panels$score$uniq, panels$norm$uniq), use.names = FALSE))
}

# per-clock present/absent CpG sets over usable_cols
resolve_cpgs <- function(usable_cols, panels) {
  usable <- unique(usable_cols)
  clock_sequence <- panels$clock_id

  # split each distinct panel once
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

# pre-score scoring-panel coverage gate
WARN_COVERAGE_MARGIN <- 1.1

# cap long failure lists
coverage_bullets <- function(lines) {
  shown <- utils::head(lines, 10L)
  if (length(lines) > length(shown)) {
    shown <- c(shown, sprintf("... and %d more", length(lines) - length(shown)))
  }
  bullets(shown)
}

check_coverage <- function(cpg_list, threshold = 0.75) {
  checkmate::assert_number(threshold, lower = 0, upper = 1)
  warn_below <- min(1, threshold * WARN_COVERAGE_MARGIN)

  panel_line <- function(id, present, needed, label) {
    sprintf(
      "%s: %d/%d %s CpGs (%.1f%%)",
      id,
      length(present),
      length(needed),
      label,
      100 * length(present) / length(needed)
    )
  }

  classify <- function(x) {
    if (!length(x$score_needed)) {
      return(list(level = "", line = NA_character_))
    }
    ratio <- length(x$score_present) / length(x$score_needed)
    level <- if (ratio == 0 || ratio < threshold) {
      "stop"
    } else if (ratio < warn_below) {
      "warn"
    } else {
      ""
    }
    list(
      level = level,
      line = panel_line(x$clock_id, x$score_present, x$score_needed, "scoring")
    )
  }

  graded <- lapply(cpg_list$per_clock, classify)
  levels <- vapply(graded, function(g) g$level, character(1L))
  lines_for <- function(lvl) {
    vapply(graded[levels == lvl], function(g) g$line, character(1L))
  }

  fail <- lines_for("stop")
  if (length(fail)) {
    cli::cli_abort(
      c(
        "{length(fail)} clock{?s} {?doesn't/don't} have enough CpGs to score
         ({.arg min_col_coverage} = {format(threshold)}):",
        coverage_bullets(fail),
        "i" = "Drop them from {.arg clocks}, or lower {.arg min_col_coverage}."
      ),
      call = NULL
    )
  }

  marginal <- lines_for("warn")
  if (length(marginal)) {
    cli::cli_warn(
      c(
        "{length(marginal)} clock{?s} just clear{?s/} {.arg min_col_coverage}
         = {format(threshold)}:",
        coverage_bullets(marginal),
        "i" = "Scores still run, but more of the panel is imputed."
      ),
      call = NULL
    )
  }

  # thin QN backgrounds warn only
  thin <- vapply(
    cpg_list$per_clock,
    function(x) {
      if (
        !length(x$norm_needed) ||
          length(x$norm_present) / length(x$norm_needed) >= threshold
      ) {
        return(NA_character_)
      }
      panel_line(x$clock_id, x$norm_present, x$norm_needed, "normalization")
    },
    character(1L)
  )
  thin <- thin[!is.na(thin)]
  if (length(thin)) {
    cli::cli_warn(
      c(
        "{length(thin)} clock{?s} {?has/have} a thin normalization background
         (under {.arg min_col_coverage} = {format(threshold)}):",
        coverage_bullets(thin),
        "i" = "Missing background CpGs are filled from the reference mean."
      ),
      call = NULL
    )
  }

  invisible(unique(c(names(levels)[levels != ""], names(thin))))
}

# per-sample observed fraction of a clock's needed panel
row_coverage <- function(r) {
  cov <- r[["coverage"]]
  if (is.null(cov) || is.null(r[["sample_miss"]])) {
    return(NULL)
  }
  # same panel sample_miss used (norm when present)
  qn <- isTRUE(cov[["norm_needed"]] > 0L)
  needed <- if (qn) cov[["norm_needed"]] else cov[["score_needed"]]
  present <- if (qn) cov[["norm_present"]] else cov[["score_present"]]
  if (!length(needed) || needed == 0L) {
    return(NULL)
  }
  list(cov = (present - r[["sample_miss"]]) / needed, needed = needed)
}

# post-score per-sample coverage gate (warn only)
check_row_coverage <- function(results, threshold = 0.75) {
  checkmate::assert_number(threshold, lower = 0, upper = 1)

  line_for <- function(id) {
    rc <- row_coverage(results[[id]])
    if (is.null(rc)) {
      return(NA_character_)
    }
    cov <- rc[["cov"]]
    low <- !is.na(cov) & cov < threshold
    if (!any(low)) {
      return(NA_character_)
    }
    sprintf(
      "%s: %d of %d sample(s), worst %.1f%% of %d CpGs",
      id,
      sum(low),
      sum(!is.na(cov)),
      100 * min(cov[low]),
      rc[["needed"]]
    )
  }

  lines <- vapply(names(results), line_for, character(1L))
  lines <- lines[!is.na(lines)]
  if (length(lines)) {
    cli::cli_warn(
      c(
        "{length(lines)} clock{?s} scored some samples under
         {.arg min_row_coverage} = {format(threshold)}:",
        coverage_bullets(lines),
        "i" = "Those sample scores lean on imputed CpGs."
      ),
      call = NULL
    )
  }

  invisible(names(lines))
}
