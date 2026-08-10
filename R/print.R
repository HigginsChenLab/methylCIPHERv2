# shared print grammar for every print.mc_* method.

# two spaces under every section header, so each block shares a left edge.
MC_INDENT <- "  "

# two spaces between columns, and a rule under the header.
MC_GAP <- "  "

# "row" or "rows", by count.
plural_noun <- function(n, noun, suffix = "s") {
  paste0(noun, if (n == 1) "" else suffix)
}

# one count phrase for everything we print.
plural_count <- function(n, noun, suffix = "s") {
  sprintf("%d %s", n, plural_noun(n, noun, suffix))
}

# "6 of 10 rows" where the axis is cut, "10 rows" where it is whole.
shown_count <- function(i, n, noun, suffix = "s") {
  whole <- plural_count(n, noun, suffix)
  if (i >= n) whole else sprintf("%d of %s", i, whole)
}

# "4 more rows", or nothing when the axis is whole
more_count <- function(i, n, noun, suffix = "s") {
  if (i >= n) {
    return(character(0))
  }
  sprintf("%d more %s", n - i, plural_noun(n - i, noun, suffix))
}

# "<mc_result> 10 samples x 3 clocks"
fmt_header <- function(cls, n, n_noun, k, k_noun) {
  sprintf(
    "<%s> %s x %s",
    cls,
    plural_count(n, n_noun),
    plural_count(k, k_noun)
  )
}

# "mc_batch_id [2 batches]". a section that is not a component of the record.
fmt_named_section <- function(name, ...) {
  sprintf("%s [%s]", name, paste(c(...), collapse = ", "))
}

# "$scores [6 of 10 rows, 3 clocks]"
fmt_section <- function(name, ...) {
  fmt_named_section(paste0("$", name), ...)
}

# every cell as text. a data.frame formats each column on its own, so each
# keeps its own digits; a matrix formats as one grid, the way print() does.
grid_cells <- function(x) {
  if (is.data.frame(x)) {
    return(lapply(x, format, trim = TRUE))
  }
  # column by column, so each clock keeps its own digits the way print() does
  cells <- lapply(seq_len(ncol(x)), function(j) format(x[, j], trim = TRUE))
  names(cells) <- colnames(x)
  cells
}

# numbers right, text left, the way print() aligns them.
grid_right <- function(x) {
  if (is.data.frame(x)) {
    return(!vapply(x, is.character, logical(1L)))
  }
  rep(!is.character(x), ncol(x))
}

# a matrix carries its sample ids in its row names, so they lead each row. a
# data.frame's are a 1..n index that names nothing, so they are left out.
grid_labels <- function(x) {
  if (is.data.frame(x)) NULL else rownames(x)
}

pad_cells <- function(v, w, right) {
  formatC(v, width = if (right) w else -w)
}

# the columns of each block, so a grid too wide for the terminal continues
# below rather than being folded mid-cell by the terminal itself.
grid_chunks <- function(w, avail) {
  out <- integer(length(w))
  chunk <- 1L
  used <- 0L
  for (j in seq_along(w)) {
    need <- w[[j]] + if (used) nchar(MC_GAP) else 0L
    if (used && used + need > avail) {
      chunk <- chunk + 1L
      used <- w[[j]]
    } else {
      used <- used + need
    }
    out[[j]] <- chunk
  }
  out
}

# a matrix or data.frame as text: a header row, a rule under it, then the
# cells. returns the lines, so a cli printer and a cat printer agree.
fmt_grid <- function(x, width = getOption("width")) {
  cells <- grid_cells(x)
  if (!length(cells)) {
    return(character(0))
  }
  nms <- names(cells)
  if (is.null(nms)) {
    nms <- rep("", length(cells))
  }
  right <- grid_right(x)
  w <- vapply(
    seq_along(cells),
    function(j) max(nchar(nms[[j]]), nchar(cells[[j]]), 0L),
    integer(1L)
  )
  col <- lapply(seq_along(cells), function(j) {
    c(
      pad_cells(nms[[j]], w[[j]], right[[j]]),
      strrep("-", w[[j]]),
      pad_cells(cells[[j]], w[[j]], right[[j]])
    )
  })
  # the labels repeat in every chunk, or a continued row loses its name
  lab <- grid_labels(x)
  if (length(lab)) {
    lw <- max(nchar(lab), 0L)
    lab <- c(strrep(" ", lw), strrep("-", lw), pad_cells(lab, lw, FALSE))
    width <- width - lw - nchar(MC_GAP)
  }
  chunks <- grid_chunks(w, max(width, 1L))
  lines <- lapply(split(col, chunks), function(part) {
    # dropped, not passed: a NULL column pastes as an empty leading field
    part <- c(if (length(lab)) list(lab), part)
    # padding a column leaves a ragged right edge
    sub("[[:space:]]+$", "", do.call(paste, c(part, list(sep = MC_GAP))))
  })
  unlist(lines, use.names = FALSE)
}

# a block's body, under the section header that names it.
print_grid <- function(x) {
  lines <- fmt_grid(x, getOption("width") - nchar(MC_INDENT))
  cat(paste0(MC_INDENT, lines, "\n"), sep = "")
  invisible(NULL)
}

# the "... N more" tail every block ends with. nothing when the axis is whole.
print_more <- function(...) {
  tail <- c(...)
  if (length(tail)) {
    cat(MC_INDENT, "... ", paste(tail, collapse = ", "), "\n", sep = "")
  }
  invisible(NULL)
}

# one named section over a character vector, comma-joined and cut to ni.
print_vector <- function(name, v, ni, noun, ...) {
  cat("\n", fmt_named_section(name, ...), "\n", sep = "")
  body <- paste(utils::head(v, ni), collapse = ", ")
  if (nzchar(body)) {
    # wrapped, because one long line of ids is the widest thing a digest prints
    wrapped <- strwrap(body, width = getOption("width"), prefix = MC_INDENT)
    cat(paste0(wrapped, "\n"), sep = "")
  }
  print_more(more_count(ni, length(v), noun))
}

# one named section over a data.frame. noun names the row axis, because a
# section keyed by batch counts batches and not rows.
print_table <- function(name, df, n, noun = "row", suffix = "s") {
  nr <- nrow(df)
  ni <- min(n, nr)
  cat(
    "\n",
    fmt_named_section(name, shown_count(ni, nr, noun, suffix)),
    "\n",
    sep = ""
  )
  if (!ni) {
    return(invisible(NULL))
  }
  print_grid(df[seq_len(ni), , drop = FALSE])
  print_more(more_count(ni, nr, noun, suffix))
}

# one component block. cut_cols = false when columns stay whole.
print_block <- function(name, x, ni, pi, col_noun, cut_cols = TRUE) {
  nr <- nrow(x)
  nc <- ncol(x)
  cols <- if (cut_cols) {
    shown_count(pi, nc, col_noun)
  } else {
    plural_count(nc, col_noun)
  }
  cat("\n", fmt_section(name, shown_count(ni, nr, "row"), cols), "\n", sep = "")
  print_grid(x[seq_len(ni), seq_len(pi), drop = FALSE])

  print_more(more_count(ni, nr, "row"), more_count(pi, nc, col_noun))
}
