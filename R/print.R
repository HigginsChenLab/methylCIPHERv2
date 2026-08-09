# shared print grammar for every print.mc_* method.

# one plural form for every count we print.
plural_count <- function(n, noun, suffix = "s") {
  sprintf("%d %s(%s)", n, noun, suffix)
}

# "6 of 10 row(s)" -- the "of" form means the axis can be cut
shown_count <- function(i, n, noun, suffix = "s") {
  sprintf("%d of %s", i, plural_count(n, noun, suffix))
}

# "4 more row(s)", or nothing when the axis is whole
more_count <- function(i, n, noun, suffix = "s") {
  if (i >= n) {
    return(character(0))
  }
  sprintf("%d more %s(%s)", n - i, noun, suffix)
}

# "<mc_result> 10 sample(s) x 3 clock(s)"
fmt_header <- function(cls, n, n_noun, k, k_noun) {
  sprintf(
    "<%s> %s x %s",
    cls,
    plural_count(n, n_noun),
    plural_count(k, k_noun)
  )
}

# "mc_batch_id [2 batch(es)]". a section that is not a component of the record.
fmt_named_section <- function(name, ...) {
  sprintf("%s [%s]", name, paste(c(...), collapse = ", "))
}

# "$scores [6 of 10 row(s), 3 of 3 clock(s)]"
fmt_section <- function(name, ...) {
  fmt_named_section(paste0("$", name), ...)
}

# the "... N more" tail every block ends with. nothing when the axis is whole.
print_more <- function(...) {
  tail <- c(...)
  if (length(tail)) {
    cat("... ", paste(tail, collapse = ", "), "\n", sep = "")
  }
  invisible(NULL)
}

# one named section over a character vector, comma-joined and cut to ni.
print_vector <- function(name, v, ni, noun, ...) {
  cat(
    "\n",
    fmt_named_section(name, ...),
    "\n",
    paste(utils::head(v, ni), collapse = ", "),
    "\n",
    sep = ""
  )
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
  print(df[seq_len(ni), , drop = FALSE], row.names = FALSE)
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
  print(x[seq_len(ni), seq_len(pi), drop = FALSE])

  print_more(more_count(ni, nr, "row"), more_count(pi, nc, col_noun))
}
