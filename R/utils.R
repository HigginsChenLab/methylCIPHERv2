# shared cross-cutting helpers

# cli renders one line per element, so a list the user can grow is capped
# before it reaches cli. one cap for every message in the package.
MC_MSG_CAP <- 10L

# cli parses every bullet it is handed as a template, so a bullet built from
# data (or already rendered by format_inline) has its braces escaped on the way
# in. without this a "{" in a sample id or a file name replaces the diagnostic
# with a cli parse error.
cli_escape <- function(x) {
  out <- gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
  stats::setNames(out, names(x))
}

# name a character vector as cli "*" bullets
bullets <- function(x) {
  stats::setNames(cli_escape(x), rep("*", length(x)))
}

# cli "*" bullets. cap first, then format, so per-line markup only ever runs
# on the lines that survive the cap.
capped_bullets <- function(x, fmt = identity, n = MC_MSG_CAP) {
  bullets(fmt(utils::head(x, n)))
}

# capped values for the inline "{.val {capped_vals(x)}}" form
capped_vals <- function(x, n = MC_MSG_CAP) {
  utils::head(x, n)
}

# comma-joined head, for a plain stop()/warning() that is not a cli template
capped <- function(x, n = MC_MSG_CAP) {
  paste(utils::head(x, n), collapse = ", ")
}

# polynomial eval, lowest degree first (horner-style, 1-row safe)
poly_eval <- function(x, coef) {
  out <- rep(0, length(x))
  for (k in seq_along(coef)) {
    out <- out + coef[[k]] * x^(k - 1L)
  }
  out
}
