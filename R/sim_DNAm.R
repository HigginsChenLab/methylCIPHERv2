sim_DNAm <- function(clocks, n = 10, Age = FALSE, Female = FALSE, remove = 0) {
  checkmate::assert_flag(Age)
  checkmate::assert_flag(Female)
  checkmate::assert_int(remove, lower = 0)

  # Must mirror calc_clocks' plan, not just its namespace resolution: the simulated panel has to
  # cover the transitive deps too, or e.g. sim_DNAm("DNAmFitAge") emits the group's 627 CpGs while
  # calc_clocks needs 1643 (GrimAgeV1 + its 8 surrogates). Those surrogates are policy 'omit', so
  # they would score intercept-only and DNAmFitAge would come back plausible-looking but meaningless.
  cpgs <- clock_cpgs(resolve_clocks_sequence(resolve_clocks(clocks)))
  if (remove > 0) {
    n_drop <- min(remove, length(cpgs))
    cpgs <- cpgs[-sample.int(length(cpgs), n_drop)]
  }
  ID <- paste0("sample", seq_len(n))
  DNAm <- matrix(
    stats::runif(n * length(cpgs)),
    nrow = n,
    dimnames = list(ID, cpgs)
  )
  pheno <- data.frame(ID = ID)
  if (Age) {
    pheno$Age <- stats::rnorm(n, mean = 45, sd = 5)
  }
  if (Female) {
    pheno$Female <- numeric(n)
    pheno$Female[sample.int(n, floor(n / 2))] <- 1
  }
  out <- list(
    DNAm = DNAm,
    pheno = pheno
  )
  class(out) <- c("methylCIPHER_sim", "list")
  out
}

#' @export
print.methylCIPHER_sim <- function(x, n = 6, p = 6, ...) {
  DNAm <- x$DNAm
  pheno <- x$pheno
  nr <- nrow(DNAm)
  nc <- ncol(DNAm)
  ni <- min(n, nr)
  pi <- min(p, nc)

  cat(sprintf("<methylCIPHER_sim> %d sample(s) x %d CpG(s)\n\n", nr, nc))
  cat(sprintf("DNAm [showing %d x %d]:\n", ni, pi))
  print(DNAm[seq_len(ni), seq_len(pi), drop = FALSE])
  if (ni < nr || pi < nc) {
    cat(sprintf("... %d more row(s), %d more col(s)\n", nr - ni, nc - pi))
  }

  cat(sprintf(
    "\npheno [showing %d of %d row(s)]:\n",
    min(n, nrow(pheno)),
    nrow(pheno)
  ))
  print(utils::head(pheno, n))

  invisible(x)
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
