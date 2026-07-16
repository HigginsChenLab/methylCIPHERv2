sim_DNAm <- function(n = 10, clocks) {
  cpgs <- clock_cpgs(resolve_clocks(clocks))
  matrix(
    stats::runif(n * length(cpgs)),
    nrow = n,
    dimnames = list(paste0("sample", seq_len(n)), cpgs)
  )
}

clock_cpgs <- function(clock_ids) {
  results <- lapply(clock_ids, function(cid) {
    entry <- mc_catalog[[cid]]
    scoring <- Filter(
      function(p) identical(p$role, "scoring"),
      entry$probe_sets
    )
    if (!length(scoring)) {
      return(NULL)
    }
    unlist(lapply(scoring, function(ps) ps$cpgs), use.names = FALSE)
  })

  unresolved <- clock_ids[vapply(results, is.null, logical(1))]

  if (length(unresolved)) {
    stop(
      "No resolved scoring CpGs for ",
      paste(unresolved, collapse = ", "),
      " (SystemsAge, PCClocks, PCBrainAge)",
      call. = FALSE
    )
  }

  cpgs <- unlist(results, use.names = FALSE)
  unique(cpgs[nzchar(cpgs) & !is.na(cpgs)])
}
