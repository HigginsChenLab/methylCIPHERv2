# shared print grammar for every print.mc_* method.

# two spaces under every section header, so each block shares a left edge.
MC_INDENT <- "  "

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

# left-align the text columns and leave the numbers alone. print.data.frame
# has one `right` flag for the whole frame, so each column is padded here. the
# name is padded with it, or the header sits off its own column's left edge.
justify_cols <- function(x) {
  if (!is.data.frame(x)) {
    return(x)
  }
  nms <- names(x)
  for (j in seq_along(x)) {
    v <- x[[j]]
    if (!is.character(v)) {
      next
    }
    w <- max(nchar(nms[[j]]), nchar(v))
    x[[j]] <- format(v, width = w, justify = "left")
    nms[[j]] <- format(nms[[j]], width = w, justify = "left")
  }
  names(x) <- nms
  x
}

# our own indent, over whatever gutter print() left. row.names = FALSE leads
# every line with a space, so the common prefix comes off first and two spaces
# do not become three. padding a column also leaves a ragged right edge.
reindent <- function(lines) {
  if (!length(lines)) {
    return(lines)
  }
  gutter <- min(nchar(lines) - nchar(sub("^ +", "", lines)))
  paste0(MC_INDENT, sub("[[:space:]]+$", "", substring(lines, gutter + 1L)))
}

# a block's body, indented. print() writes straight to stdout, so the lines
# are captured, and the capture wraps at a width the indent comes out of
# first. spaces rather than a tab, which renders at the terminal's tab stop.
print_indented <- function(expr) {
  old <- options(width = max(20L, getOption("width") - nchar(MC_INDENT)))
  on.exit(options(old), add = TRUE)
  cat(paste0(reindent(utils::capture.output(expr)), "\n"), sep = "")
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
  shown <- justify_cols(df[seq_len(ni), , drop = FALSE])
  print_indented(print(shown, row.names = FALSE))
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
  print_indented(print(justify_cols(x[seq_len(ni), seq_len(pi), drop = FALSE])))

  print_more(more_count(ni, nr, "row"), more_count(pi, nc, col_noun))
}
