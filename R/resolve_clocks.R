resolve_clocks <- function(clocks) {
  members <- split(mc_index$clock_id, mc_index$group_id)

  lookup <- c(
    members,
    stats::setNames(as.list(mc_index$clock_id), mc_index$clock_id),
    list(all = mc_index$clock_id)
  )

  bad <- setdiff(clocks, names(lookup))
  if (length(bad)) {
    stop("Unknown clock token(s): ", paste(bad, collapse = ", "), call. = FALSE)
  }

  out <- unlist(lookup[clocks], use.names = FALSE)
  out[!duplicated(out)]
}
