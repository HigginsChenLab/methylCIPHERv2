# gp_age: closed-form golden over a hand-built model, through an in-memory
# pack. parity owns the shipped numbers.

test_that("calc_clocks() scores GP_age from a pack and fills an absent CpG", {
  skip_on_cran()
  id <- "GP_age_10_cpgs"
  panel <- mc_fake_cpgs(3L)
  X <- matrix(
    c(0.1, 0.5, 0.9, 0.2, 0.4, 0.8, 0.3, 0.6, 0.7),
    3L,
    3L,
    dimnames = list(NULL, panel)
  )
  alpha <- c(1.5, -0.5, 2)
  fill <- stats::setNames(c(0.2, 0.5, 0.8), panel)
  variance <- 2
  lengthscale <- 0.7
  pack <- list(
    group_id = "GP_age",
    cpgs = panel,
    member_cpgs = stats::setNames(list(panel), id),
    models = stats::setNames(
      list(list(
        cpgs = panel,
        X = X,
        variance = variance,
        lengthscale = lengthscale,
        fill = fill
      )),
      id
    ),
    derived = stats::setNames(list(list(alpha = alpha)), id)
  )

  # the second CpG is absent, so it takes the fill
  DNAm <- random_betas(panel, n = 4L)[, panel[-2L], drop = FALSE]
  res <- calc_clocks(
    DNAm,
    id,
    ext_data = pack,
    min_clocks_coverage = 0,
    min_samples_coverage = 0
  )

  x <- cbind(DNAm[, panel[[1L]]], fill[[2L]], DNAm[, panel[[3L]]])
  golden <- vapply(
    seq_len(nrow(x)),
    function(i) {
      k <- variance * exp(-0.5 * colSums((t(X) - x[i, ])^2) / lengthscale^2)
      sum(k * alpha)
    },
    numeric(1)
  )
  expect_equal(unname(res$scores[, id]), golden)
  expect_equal(res$coverage$per_clock[[1]][[id]]$score_imputed_full, 1L)
})
