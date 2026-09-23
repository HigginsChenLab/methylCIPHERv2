# beta-matrix statistics for qc_report(). descriptive only: nothing here decides
# whether a clock scores. calc_clocks() still owns that, and reads the matrix on
# its own. every pass walks the columns in blocks, so a whole-array matrix is
# never copied at once.

# columns per block. one block of 1000 samples is ~160 MB of doubles.
QC_BLOCK <- 20000L

# the beta distribution is drawn from this many evenly spaced columns
QC_DIST_COLS <- 20000L

# samples drawn as their own density line
QC_DIST_SAMPLES <- 150L

# a sample above this fraction of missing CpGs is flagged
QC_SAMPLE_MISS <- 0.05

# a variable above this fraction of missing values is flagged
QC_VAR_MISS <- 0.2

# evenly spaced positions, the same stride rule id_sample() uses for names
stride_idx <- function(n, k) {
  if (n <= k) {
    return(seq_len(n))
  }
  unique(as.integer(round(seq(1L, n, length.out = k))))
}

# one pass over the matrix: missingness on both axes, value range, sample means
qc_dnam_stats <- function(DNAm, block = QC_BLOCK) {
  n <- nrow(DNAm)
  p <- ncol(DNAm)
  st <- new.env(parent = emptyenv())
  st[["row_na"]] <- numeric(n)
  st[["row_sum"]] <- numeric(n)
  st[["row_n"]] <- numeric(n)
  st[["col_na"]] <- integer(p)
  st[["lo"]] <- Inf
  st[["hi"]] <- -Inf
  st[["below"]] <- 0
  st[["above"]] <- 0
  st[["nonfinite"]] <- 0

  starts <- seq.int(1L, max(p, 1L), by = block)
  for (s in starts) {
    idx <- seq.int(s, min(s + block - 1L, p))
    b <- DNAm[, idx, drop = FALSE]
    miss <- is.na(b)
    inf <- is.infinite(b)
    st[["nonfinite"]] <- st[["nonfinite"]] + sum(inf) + sum(is.nan(b))
    st[["row_na"]] <- st[["row_na"]] + rowSums(miss)
    st[["col_na"]][idx] <- as.integer(colSums(miss))
    b[miss | inf] <- NA
    fin <- !is.na(b)
    if (any(fin)) {
      r <- range(b, na.rm = TRUE)
      st[["lo"]] <- min(st[["lo"]], r[[1L]])
      st[["hi"]] <- max(st[["hi"]], r[[2L]])
      st[["below"]] <- st[["below"]] + sum(b < 0, na.rm = TRUE)
      st[["above"]] <- st[["above"]] + sum(b > 1, na.rm = TRUE)
      st[["row_sum"]] <- st[["row_sum"]] + rowSums(b, na.rm = TRUE)
      st[["row_n"]] <- st[["row_n"]] + rowSums(fin)
    }
  }

  row_mean <- st[["row_sum"]] / st[["row_n"]]
  row_mean[st[["row_n"]] == 0] <- NA_real_
  list(
    n = n,
    p = p,
    cells = as.numeric(n) * p,
    n_missing = sum(st[["row_na"]]),
    sample_miss = st[["row_na"]] / p,
    sample_mean = row_mean,
    cpg_na = st[["col_na"]],
    n_cpg_all_na = sum(st[["col_na"]] == n),
    n_cpg_any_na = sum(st[["col_na"]] > 0L),
    lo = if (is.finite(st[["lo"]])) st[["lo"]] else NA_real_,
    hi = if (is.finite(st[["hi"]])) st[["hi"]] else NA_real_,
    n_below = st[["below"]],
    n_above = st[["above"]],
    n_nonfinite = st[["nonfinite"]]
  )
}

# per-sample densities on a histogram grid, from an evenly spaced column subset
qc_beta_density <- function(DNAm, lo, hi, n_bins = 100L) {
  cols <- stride_idx(ncol(DNAm), QC_DIST_COLS)
  sub <- DNAm[, cols, drop = FALSE]
  sub[!is.finite(sub)] <- NA
  rng <- c(min(0, lo, na.rm = TRUE), max(1, hi, na.rm = TRUE))
  br <- seq(rng[[1L]], rng[[2L]], length.out = n_bins + 1L)
  wid <- diff(br)[[1L]]
  mids <- (br[-1L] + br[-length(br)]) / 2
  dens <- t(apply(sub, 1L, function(v) {
    v <- v[!is.na(v)]
    if (!length(v)) {
      return(rep(NA_real_, n_bins))
    }
    tabulate(findInterval(v, br, all.inside = TRUE), n_bins) / (length(v) * wid)
  }))
  if (n_bins == 1L) {
    dens <- t(dens)
  }
  list(
    x = mids,
    dens = dens,
    overall = colMeans(dens, na.rm = TRUE),
    range = rng,
    n_cols = length(cols)
  )
}

chart_beta_density <- function(bd) {
  dens <- bd[["dens"]]
  rows <- stride_idx(nrow(dens), QC_DIST_SAMPLES)
  ymax <- max(dens[rows, ], bd[["overall"]], na.rm = TRUE)
  if (!is.finite(ymax) || ymax <= 0) {
    return(p_note("No finite beta values to draw."))
  }
  p <- svg_panel(bd[["range"]], c(0, ymax * 1.05), 680, 280)
  lines <- vapply(
    rows,
    function(i) {
      svg_line(p, bd[["x"]], dens[i, ], SVG_SERIES[[1L]], width = 1,
               opacity = 0.28, title = rownames(dens)[[i]])
    },
    character(1L)
  )
  body <- paste0(
    svg_axes(p, "Beta value", "Density"),
    paste(lines, collapse = ""),
    svg_line(p, bd[["x"]], bd[["overall"]], SVG_SERIES[[2L]], width = 2.5,
             title = "Mean over samples")
  )
  figure(
    svg_doc(p, body, "Beta value density for each sample"),
    legend = html_legend(
      c(
        if (length(rows) < nrow(dens)) {
          sprintf("One sample (%d of %d shown)", length(rows), nrow(dens))
        } else {
          "One sample"
        },
        "Mean over samples"
      ),
      SVG_SERIES[1:2]
    ),
    caption = sprintf(
      paste(
        "Density of the beta values in each sample, over %s CpGs spaced evenly",
        "across the columns. A clean beta matrix has two peaks, near 0 and near 1."
      ),
      fmt_int(bd[["n_cols"]])
    )
  )
}

# per-sample missingness, ranked, as one path of thin bars per status
chart_sample_miss <- function(miss, threshold = QC_SAMPLE_MISS) {
  o <- order(miss, decreasing = TRUE)
  v <- miss[o]
  n <- length(v)
  # scaled to the data. the threshold line shows only when a sample nears it.
  ymax <- max(v, na.rm = TRUE) * 1.15
  if (!is.finite(ymax) || ymax <= 0) {
    ymax <- 0.01
  }
  p <- svg_panel(c(0.5, n + 0.5), c(0, ymax), 680, 240)
  bw <- max((p[["right"]] - p[["left"]]) / n - 0.6, 0.6)
  seg <- function(keep, color) {
    if (!any(keep)) {
      return("")
    }
    x <- f1(p[["sx"]](which(keep)))
    paste0(
      "<path stroke=\"", color, "\" stroke-width=\"", f1(bw), "\" d=\"",
      paste0("M", x, ",", f1(p[["bottom"]]), "V", f1(p[["sy"]](v[keep])), collapse = ""),
      "\"/>"
    )
  }
  over <- !is.na(v) & v > threshold
  body <- paste0(
    svg_axes(p, "Samples, ranked by missingness", "Missing CpGs",
             xticks = numeric(0), yfmt = function(y) fmt_pct(y, if (ymax < 0.05) 2L else 0L)),
    seg(!over & !is.na(v), SVG_SERIES[[1L]]),
    seg(over, "var(--crit)"),
    svg_hline(p, threshold, label = paste(fmt_pct(threshold, 0L), "threshold"))
  )
  svg_doc(p, body, "Missing CpGs for each sample, ranked")
}

# --- array identity ------------------------------------------------------------

QC_ARRAYS <- c("450K", "EPICv1", "EPICv2", "MSA")

# an array is named only when this share of its exclusive loci is present
QC_ARRAY_MIN_HIT <- 0.2

array_reference <- function() {
  path <- system.file("extdata", "array_reference.rds", package = "methylCIPHERv2")
  if (!nzchar(path)) {
    stop("The array reference is missing from the package.", call. = FALSE)
  }
  readRDS(path)
}

bare_locus <- function(x) sub(PROBE_REPLICATE_SUFFIX, "", x)

qc_array <- function(cols, ref = array_reference()) {
  loci <- unique(bare_locus(cols))
  present <- ref[["locus"]] %in% loci
  rows <- lapply(QC_ARRAYS, function(a) {
    on <- ref[[paste0("on_", a)]]
    excl <- ref[["exclusive"]] %in% a
    data.frame(
      array = a,
      exclusive_found = sum(present & excl),
      exclusive_total = sum(excl),
      exclusive_rate = sum(present & excl) / max(sum(excl), 1L),
      reference_found = sum(present & on),
      reference_total = sum(on),
      reference_rate = sum(present & on) / max(sum(on), 1L),
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)
  best <- which.max(tab[["exclusive_rate"]])
  inferred <- if (length(best) && tab[["exclusive_rate"]][[best]] >= QC_ARRAY_MIN_HIT) {
    tab[["array"]][[best]]
  } else {
    NA_character_
  }
  list(
    table = tab,
    inferred = inferred,
    n_suffixed = sum(grepl(PROBE_REPLICATE_SUFFIX, cols)),
    n_probe_like = sum(grepl("^(cg|ch|rs|nv)", cols))
  )
}

# chrX / chrY loci present against the inferred array, or the union of all four
qc_sex_chrom <- function(cols, cpg_na, n, inferred, ref = array_reference()) {
  on <- if (is.na(inferred)) {
    Reduce(`|`, lapply(QC_ARRAYS, function(a) ref[[paste0("on_", a)]]))
  } else {
    ref[[paste0("on_", inferred)]]
  }
  loci <- bare_locus(cols)
  one <- function(ch) {
    expected <- ref[["locus"]][on & ref[["chr"]] %in% ch]
    hit <- loci %in% expected
    found <- length(unique(loci[hit]))
    miss <- if (any(hit)) sum(cpg_na[hit]) / (sum(hit) * n) else NA_real_
    data.frame(
      chromosome = paste0("chr", ch),
      expected = length(expected),
      present = found,
      coverage = found / max(length(expected), 1L),
      cell_missing = miss,
      stringsAsFactors = FALSE
    )
  }
  out <- rbind(one("X"), one("Y"))
  attr(out, "against") <- if (is.na(inferred)) "all four arrays" else inferred
  out
}

# --- clock panels ---------------------------------------------------------------

# the loaded assets for the external groups a request needs, never downloading.
# returns list(packs, absent) where absent names the groups with no asset.
qc_packs <- function(groups, ext_data) {
  if (!length(groups)) {
    return(list(packs = NULL, absent = character(0)))
  }
  canon <- mc_canonicalize_ext_data(ext_data)
  have <- if (is.list(canon)) {
    intersect(groups, names(canon))
  } else {
    dir <- mc_resolve_assets_dir(canon)
    files <- mc_pack_paths(dir, lapply(groups, mc_asset))
    groups[unname(fs::file_exists(files))]
  }
  packs <- if (length(have)) load_mc_assets(have, ext_data, ask = FALSE) else NULL
  list(packs = packs, absent = setdiff(groups, have))
}

# each requested clock's scoring panel (its dependencies' panels for a composite)
# counted against the matrix columns. descriptive: it grades nothing.
qc_clock_panels <- function(cols, cpg_na, n, clocks, ext_data) {
  ids <- resolve_clocks(clocks)
  seqs <- lapply(ids, resolve_clocks_sequence)
  names(seqs) <- ids
  all_ids <- unique(unlist(seqs, use.names = FALSE))
  groups <- pack_groups_needed(all_ids)
  pk <- qc_packs(groups, ext_data)
  ext <- all_ids[vapply(all_ids, clock_is_external, logical(1L))]
  blocked <- ext[vapply(ext, clock_group_id, character(1L)) %in% pk[["absent"]]]

  panel <- lapply(setdiff(all_ids, blocked), clock_scoring_cpgs, packs = pk[["packs"]])
  names(panel) <- setdiff(all_ids, blocked)
  col_pos <- stats::setNames(seq_along(cols), cols)
  min_cov <- formals(calc_clocks)[["min_clocks_coverage"]]

  rows <- lapply(ids, function(id) {
    s <- seqs[[id]]
    lacks <- intersect(s, blocked)
    need <- if (length(lacks)) character(0) else unique(unlist(panel[s], use.names = FALSE))
    need <- need[!is.na(need) & nzchar(need)]
    pos <- col_pos[need]
    pos <- pos[!is.na(pos)]
    n_need <- length(need)
    n_present <- length(pos)
    na_cells <- sum(cpg_na[pos])
    cov <- if (n_need) n_present / n_need else NA_real_
    # samples at or above min_cov, counted on the columns that hold any NA
    partial <- pos[cpg_na[pos] > 0L]
    per_sample <- if (!n_need) {
      NA_integer_
    } else if (!length(partial)) {
      if (cov >= min_cov) n else 0L
    } else {
      NA_integer_
    }
    status <- if (length(lacks)) {
      "asset not on disk"
    } else if (!n_need) {
      "no panel"
    } else if (n_present == n_need) {
      "complete"
    } else if (n_present == 0L) {
      "none present"
    } else if (cov >= min_cov) {
      "partial"
    } else {
      "below threshold"
    }
    list(
      row = data.frame(
        clock_id = id,
        group_id = clock_group_id(id),
        n_needed = n_need,
        n_present = n_present,
        coverage = cov,
        cell_missing = if (n_present) na_cells / (n_present * n) else NA_real_,
        samples_ok = per_sample,
        status = status,
        stringsAsFactors = FALSE
      ),
      partial = partial,
      n_need = n_need
    )
  })
  out <- do.call(rbind, lapply(rows, `[[`, "row"))
  # per-sample coverage needs the NA pattern, read once per distinct column set
  todo <- which(is.na(out[["samples_ok"]]) & out[["n_needed"]] > 0L)
  list(table = out, todo = todo, partial = lapply(rows, `[[`, "partial"),
       min_cov = min_cov, absent_groups = pk[["absent"]])
}

# fills samples_ok for the clocks whose present panel holds any NA
qc_fill_samples_ok <- function(cp, DNAm) {
  tab <- cp[["table"]]
  for (i in cp[["todo"]]) {
    cols <- cp[["partial"]][[i]]
    miss <- rowSums(is.na(DNAm[, cols, drop = FALSE]))
    observed <- tab[["n_present"]][[i]] - miss
    tab[["samples_ok"]][[i]] <- sum(observed / tab[["n_needed"]][[i]] >= cp[["min_cov"]])
  }
  cp[["table"]] <- tab
  cp
}

# --- sex, through the one beta reader -------------------------------------------

qc_predict_sex <- function(DNAm, pheno, pheno_id) {
  pf <- NULL
  if (!is.null(pheno) && "Female" %in% names(pheno)) {
    keep <- pheno[[pheno_id]] %in% rownames(DNAm)
    pf <- pheno[keep, c(pheno_id, "Female"), drop = FALSE]
    names(pf)[[1L]] <- "ID"
    if (!nrow(pf) || !all(rownames(DNAm) %in% pf[["ID"]])) {
      pf <- NULL
    }
  }
  predict_sex(DNAm, pheno = pf, pheno_id = "ID")
}
