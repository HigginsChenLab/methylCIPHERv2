# Build an n x length(cpgs) U(0,1) beta matrix. seed=NULL uses ambient RNG.
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

sim_DNAm <- function(
  clocks,
  n = 10,
  Age = FALSE,
  Female = FALSE,
  remove = 0,
  assets = NULL,
  ask = TRUE
) {
  checkmate::assert_flag(Age)
  checkmate::assert_flag(Female)
  checkmate::assert_int(remove, lower = 0)

  # Include transitive deps so composites have their input CpGs.
  clock_sequence <- resolve_clocks_sequence(resolve_clocks(clocks))
  packs <- load_mc_assets(pack_groups_needed(clock_sequence), assets, ask)
  cpgs <- clock_cpgs(clock_sequence, packs)
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

# Print a methylCIPHER_sim list (DNAm + pheno preview).
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

clock_cpgs <- function(clock_ids, packs = NULL) {
  results <- lapply(clock_ids, function(cid) {
    scoring <- clock_scoring_cpgs(cid, packs)
    if (!length(scoring)) {
      return(NULL)
    }
    # Include norm panel so simulated data exercises QN.
    c(scoring, clock_norm_cpgs(cid))
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
