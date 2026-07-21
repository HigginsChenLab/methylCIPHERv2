# Internal: an n x length(cpgs) matrix of U(0, 1) surrogate betas, rownames sample1..n and
# colnames = cpgs. `seed = NULL` draws from the ambient RNG (sim_DNAm's default); an integer
# seed gives a reproducible draw (the self-contained scorer tests). The single place surrogate
# beta matrices are constructed -- sim_DNAm() and the test helper synthetic_betas() both route here.
random_betas <- function(cpgs, n = 10L, seed = NULL) {
  draw <- function() {
    matrix(
      stats::runif(n * length(cpgs)),
      nrow = n,
      dimnames = list(paste0("sample", seq_len(n)), cpgs)
    )
  }
  if (is.null(seed)) draw() else withr::with_seed(seed, draw())
}

sim_DNAm <- function(clocks, n = 10, Age = FALSE, Female = FALSE, remove = 0) {
  checkmate::assert_flag(Age)
  checkmate::assert_flag(Female)
  checkmate::assert_int(remove, lower = 0)

  # include transitive deps so composites have their input CpGs on the panel
  cpgs <- clock_cpgs(resolve_clocks_sequence(resolve_clocks(clocks)))
  if (remove > 0) {
    n_drop <- min(remove, length(cpgs))
    cpgs <- cpgs[-sample.int(length(cpgs), n_drop)]
  }
  ID <- paste0("sample", seq_len(n))
  DNAm <- random_betas(cpgs, n = n)
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
