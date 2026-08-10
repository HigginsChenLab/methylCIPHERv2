# beta-mixture quantile calibration (vendored from hhp94/betanorm; internal).
#
# Deliberate divergences from upstream, kept across re-vendors:
#   no RNG: every mixture is fitted on the whole panel (DECISIONS 2026-08-08)
#   gold arrives as a sync-minted prefit, not a vector (DECISIONS 2026-08-10)
#   no debug/verbose/diagnostics surface: nothing here ever set them
#   values are checked per sample, not per matrix (DECISIONS 2026-08-10)
#   comments are ours, terse per CLAUDE.md, not upstream's rationale prose
# The nL = 2 arm is unreachable as shipped (every prefit is nL = 3) and is
# kept only because this file tracks upstream.

check_thresholds <- function(thresholds, nL, name) {
  if (!is.numeric(thresholds) || length(thresholds) != nL - 1L) {
    stop(
      name,
      " must be a numeric vector of length ",
      nL - 1L,
      ".",
      call. = FALSE
    )
  }
  if (any(!is.finite(thresholds))) {
    stop(name, " must contain only finite values.", call. = FALSE)
  }
  if (any(diff(thresholds) <= 0)) {
    stop(name, " must be strictly increasing.", call. = FALSE)
  }
  invisible(thresholds)
}

class_by_thresh <- function(beta, thresholds) {
  class <- rep.int(1L, length(beta))
  for (boundary in seq_along(thresholds)) {
    class[beta > thresholds[boundary]] <- boundary + 1L
  }
  class
}

require_all_classes <- function(class, nL, context, min.count = 1L) {
  counts <- tabulate(class, nbins = nL)
  if (any(counts < min.count)) {
    stop(
      context,
      " has insufficient class counts [",
      paste(counts, collapse = ", "),
      "]; need >= ",
      min.count,
      " per class.",
      call. = FALSE
    )
  }
  counts
}

density_thresholds <- function(
  a,
  b,
  eta,
  component.means,
  context
) {
  a <- as.numeric(a)
  b <- as.numeric(b)
  eta <- as.numeric(eta)
  means <- as.numeric(component.means)
  nL <- length(means)

  if (
    nL < 2L ||
      length(a) != nL ||
      length(b) != nL ||
      length(eta) != nL
  ) {
    stop(context, " has inconsistent mixture dimensions.", call. = FALSE)
  }

  if (
    any(!is.finite(c(a, b, eta, means))) ||
      any(a <= 0) ||
      any(b <= 0) ||
      any(eta <= 0) ||
      any(means <= 0 | means >= 1) ||
      any(diff(means) <= 0)
  ) {
    stop(
      context,
      " has invalid or unordered mixture parameters.",
      call. = FALSE
    )
  }

  # Boundary between components k and k+1 (by mean): lower stops dominating higher.
  find_crossing <- function(k) {
    lo <- means[k]
    hi <- means[k + 1L]

    da <- a[k] - a[k + 1L]
    db <- b[k] - b[k + 1L]

    constant <-
      log(eta[k]) -
      lbeta(a[k], b[k]) -
      log(eta[k + 1L]) +
      lbeta(a[k + 1L], b[k + 1L])

    log_score_diff <- function(x) {
      constant + da * log(x) + db * log1p(-x)
    }

    slope <- function(x) {
      da / x - db / (1 - x)
    }

    # The log-density ratio has at most one interior stationary point.
    cuts <- c(lo, hi)
    denominator <- da + db

    if (denominator != 0) {
      turning.point <- da / denominator
      if (
        is.finite(turning.point) &&
          turning.point > lo &&
          turning.point < hi
      ) {
        cuts <- sort(c(lo, turning.point, hi))
      }
    }

    values <- vapply(cuts, log_score_diff, numeric(1L))
    if (any(!is.finite(values))) {
      stop(
        context,
        " produced a non-finite density ratio for boundary ",
        k,
        ".",
        call. = FALSE
      )
    }

    for (i in seq_len(length(cuts) - 1L)) {
      left <- cuts[i]
      right <- cuts[i + 1L]
      f.left <- values[i]
      f.right <- values[i + 1L]

      # Exact endpoint root with the required lower-to-higher orientation.
      if (f.left == 0 && slope(left) < 0) {
        return(left)
      }
      if (f.right == 0 && slope(right) < 0) {
        return(right)
      }

      # Component k dominates on the left and k + 1 on the right.
      if (f.left > 0 && f.right < 0) {
        return(
          stats::uniroot(
            log_score_diff,
            interval = c(left, right),
            tol = sqrt(.Machine[["double.eps"]])
          )[["root"]]
        )
      }
    }

    stop(
      context,
      " has no lower-to-higher weighted-density crossing between means ",
      signif(lo, 8),
      " and ",
      signif(hi, 8),
      " for boundary ",
      k,
      ".",
      call. = FALSE
    )
  }

  thresholds <- vapply(
    seq_len(nL - 1L),
    find_crossing,
    numeric(1L)
  )

  if (any(diff(thresholds) <= 0)) {
    stop(
      context,
      " density boundaries are not ordinal: ",
      paste(signif(thresholds, 8), collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  thresholds
}

# nL=2 class-wise quantile map joined at gold cut t_g (sample cut t_s).
normalize_nl2 <- function(
  beta,
  class,
  sample.a,
  sample.b,
  gold.a,
  gold.b,
  sample.threshold,
  gold.threshold,
  context = "nL=2 truncated map"
) {
  beta <- as.numeric(beta)
  class <- as.integer(class)
  sample.a <- as.numeric(sample.a)
  sample.b <- as.numeric(sample.b)
  gold.a <- as.numeric(gold.a)
  gold.b <- as.numeric(gold.b)
  sample.threshold <- as.numeric(sample.threshold)[1L]
  gold.threshold <- as.numeric(gold.threshold)[1L]

  if (
    length(sample.a) != 2L ||
      length(sample.b) != 2L ||
      length(gold.a) != 2L ||
      length(gold.b) != 2L
  ) {
    stop(context, " expects length-2 component shapes.", call. = FALSE)
  }
  if (
    !is.finite(sample.threshold) ||
      !is.finite(gold.threshold) ||
      sample.threshold <= 0 ||
      sample.threshold >= 1 ||
      gold.threshold <= 0 ||
      gold.threshold >= 1
  ) {
    stop(
      context,
      " thresholds must lie strictly in (0, 1); got sample = ",
      signif(sample.threshold, 8),
      ", gold = ",
      signif(gold.threshold, 8),
      ".",
      call. = FALSE
    )
  }

  # Conditional CDF in log-prob (avoids pbeta underflow); clamp, then qbeta.
  check_log_mass <- function(value, label) {
    # log-mass > 0 is rounding noise; -Inf means no usable conditioning mass.
    if (!is.finite(value)) {
      stop(
        context,
        " ",
        label,
        " at threshold is unusable (log = ",
        signif(value, 8),
        ").",
        call. = FALSE
      )
    }
    min(0, value)
  }

  log.FsU.ts <- check_log_mass(
    stats::pbeta(
      sample.threshold,
      sample.a[1L],
      sample.b[1L],
      lower.tail = TRUE,
      log.p = TRUE
    ),
    "sample U CDF"
  )
  log.FsM.ts <- check_log_mass(
    stats::pbeta(
      sample.threshold,
      sample.a[2L],
      sample.b[2L],
      lower.tail = FALSE,
      log.p = TRUE
    ),
    "sample M upper-tail CDF"
  )
  log.FgU.tg <- check_log_mass(
    stats::pbeta(
      gold.threshold,
      gold.a[1L],
      gold.b[1L],
      lower.tail = TRUE,
      log.p = TRUE
    ),
    "gold U CDF"
  )
  log.FgM.tg <- check_log_mass(
    stats::pbeta(
      gold.threshold,
      gold.a[2L],
      gold.b[2L],
      lower.tail = FALSE,
      log.p = TRUE
    ),
    "gold M upper-tail CDF"
  )

  out <- beta
  u_idx <- which(class == 1L)
  m_idx <- which(class == 2L)

  if (length(u_idx)) {
    log.u <- pmin(
      0,
      stats::pbeta(
        beta[u_idx],
        sample.a[1L],
        sample.b[1L],
        lower.tail = TRUE,
        log.p = TRUE
      ) -
        log.FsU.ts
    )
    out[u_idx] <- stats::qbeta(
      log.u + log.FgU.tg,
      gold.a[1L],
      gold.b[1L],
      lower.tail = TRUE,
      log.p = TRUE
    )
  }

  if (length(m_idx)) {
    log.r <- pmin(
      0,
      stats::pbeta(
        beta[m_idx],
        sample.a[2L],
        sample.b[2L],
        lower.tail = FALSE,
        log.p = TRUE
      ) -
        log.FsM.ts
    )
    out[m_idx] <- stats::qbeta(
      log.r + log.FgM.tg,
      gold.a[2L],
      gold.b[2L],
      lower.tail = FALSE,
      log.p = TRUE
    )
  }

  if (any(!is.finite(out))) {
    stop(context, " produced non-finite calibrated values.", call. = FALSE)
  }
  out
}

estimate_mode <- function(x, context) {
  if (!length(x)) {
    stop(context, " is empty; cannot estimate mode.", call. = FALSE)
  }
  if (length(x) == 1L || all(x == x[1L])) {
    return(x[1L])
  }
  estimate <- stats::density(x)
  # clamp density() mode into (0, 1) for init thresholds.
  mode <- estimate[["x"]][which.max(estimate[["y"]])]
  min(1, max(0, mode))
}

# Sort full component tuples by mean (U first, M last); never sort params alone.
canonicalize_em_components <- function(em, context) {
  a <- as.numeric(em[["a"]][, 1L])
  b <- as.numeric(em[["b"]][, 1L])
  eta <- as.numeric(em[["eta"]])
  mu <- as.numeric(em[["mu"]][, 1L])

  if (
    any(!is.finite(c(a, b, eta, mu))) ||
      any(a <= 0) ||
      any(b <= 0) ||
      any(eta <= 0) ||
      any(mu <= 0 | mu >= 1)
  ) {
    stop(context, " returned invalid mixture parameters.", call. = FALSE)
  }

  ord <- order(mu)

  em[["a"]] <- em[["a"]][ord, , drop = FALSE]
  em[["b"]] <- em[["b"]][ord, , drop = FALSE]
  em[["mu"]] <- em[["mu"]][ord, , drop = FALSE]
  em[["eta"]] <- em[["eta"]][ord]
  em[["w"]] <- em[["w"]][, ord, drop = FALSE]
  em[["fit_status"]] <- em[["fit_status"]][ord]
  em[["fit_reason"]] <- em[["fit_reason"]][ord]

  mu <- as.numeric(em[["mu"]][, 1L])
  if (any(diff(mu) <= 0)) {
    stop(
      context,
      " has indistinguishable component means: ",
      paste(signif(mu, 8), collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  em
}

fit_mixture <- function(
  beta,
  thresholds,
  nL,
  niter,
  tol,
  beta.maxit,
  beta.score.tol,
  context
) {
  initial.class <- class_by_thresh(beta, thresholds)

  # kept for its stop() on an under-filled class, not for its counts
  require_all_classes(
    class = initial.class,
    nL = nL,
    context = paste0(context, " initial mixture"),
    min.count = 2L
  )

  # One-hot responsibilities over the whole panel (no subsample, no RNG).
  w.init <- matrix(0, nrow = length(beta), ncol = nL)
  w.init[cbind(seq_along(beta), initial.class)] <- 1

  # Clip endpoints toward nearest interior; floor at endpoint.eps (avoid log(0)).
  y_fit <- as.numeric(beta)
  endpoint.eps <- sqrt(.Machine[["double.eps"]])
  positive <- y_fit[y_fit > 0]
  below.one <- y_fit[y_fit < 1]
  lower.clip <- if (length(positive)) {
    max(endpoint.eps, min(positive) / 2)
  } else {
    endpoint.eps
  }
  upper.clip <- if (length(below.one)) {
    min(1 - endpoint.eps, 1 - (1 - max(below.one)) / 2)
  } else {
    1 - endpoint.eps
  }
  if (!(lower.clip < upper.clip)) {
    stop(
      context,
      " could not construct a valid open-interval clipping range.",
      call. = FALSE
    )
  }
  y_fit <- pmin(upper.clip, pmax(lower.clip, y_fit))

  em <- beta_mixture_em_cpp(
    y = y_fit,
    initial_responsibility = w.init,
    nL = nL,
    maxiter = niter,
    tol = tol,
    beta_maxit = beta.maxit,
    beta_score_tol = beta.score.tol
  )

  em <- canonicalize_em_components(
    em,
    paste0(context, " mixture")
  )

  # Components are already canonicalized by increasing mean.
  component.means <- as.numeric(em[["mu"]][, 1L])

  # Drop responsibilities: the n x K matrix has no reader past the EM.
  em[["w"]] <- NULL

  posterior.thresholds <- density_thresholds(
    a = as.numeric(em[["a"]][, 1L]),
    b = as.numeric(em[["b"]][, 1L]),
    eta = as.numeric(em[["eta"]]),
    component.means = component.means,
    context = paste0(context, " posterior mixture")
  )

  full.class <- class_by_thresh(
    beta = beta,
    thresholds = posterior.thresholds
  )

  # kept for its stop() on an empty class, not for its counts
  require_all_classes(
    class = full.class,
    nL = nL,
    context = paste0(context, " complete mixture"),
    min.count = 1L
  )

  list(
    em = em,
    component_means = component.means,
    thresholds = posterior.thresholds,
    full_class = full.class
  )
}

map_beta_q <- function(x, a.sample, b.sample, a.gold, b.gold, lower.tail) {
  stats::qbeta(
    stats::pbeta(x, a.sample, b.sample, lower.tail = lower.tail),
    a.gold,
    b.gold,
    lower.tail = lower.tail
  )
}

# BMIQ calibrate beta matrix onto a gold prefit (defaults follow legacy BMIQ).
# Every sample mixture is fitted on the whole panel; legacy BMIQ subsampled it.
bmiq_calibration <- function(
  datM,
  gold,
  doH = NULL,
  niter = 5L,
  tol = 0.001,
  beta.maxit = 50L,
  beta.score.tol = 1e-10,
  h.policy = c("optional", "require"),
  on.sample.error = c("stop", "continue"),
  failed.sample = c("NA", "original")
) {
  h.policy <- match.arg(h.policy)
  on.sample.error <- match.arg(on.sample.error)
  failed.sample <- match.arg(failed.sample)

  # values are graded per sample, in process_sample().
  checkmate::assert_matrix(
    datM,
    mode = "numeric",
    min.rows = 1L,
    min.cols = 1L
  )
  storage.mode(datM) <- "double"

  # a sync-minted prefit carries no probe axis, so it never aligns with datM.
  if (!is.list(gold) || !length(gold[["a"]])) {
    stop("bmiq gold prefit is malformed.", call. = FALSE)
  }
  nL <- as.integer(gold[["nL"]])

  if (is.null(doH)) {
    doH <- nL == 3L
  } else {
    checkmate::assert_flag(doH)
    if (nL == 2L && isTRUE(doH)) {
      stop(
        "doH = TRUE is not valid when nL = 2 (no H component).",
        call. = FALSE
      )
    }
  }

  niter <- as.integer(checkmate::assert_int(niter, lower = 1L))
  beta.maxit <- as.integer(checkmate::assert_int(beta.maxit, lower = 1L))
  checkmate::assert_number(tol, lower = 0, finite = TRUE)
  checkmate::assert_true(tol > 0, .var.name = "tol")
  checkmate::assert_number(beta.score.tol, lower = 0, finite = TRUE)
  checkmate::assert_true(beta.score.tol > 0, .var.name = "beta.score.tol")

  number.of.samples <- nrow(datM)
  number.of.probes <- ncol(datM)

  if (number.of.probes < 2L * nL) {
    stop(
      "Too few probes (",
      number.of.probes,
      ") to fit nL = ",
      nL,
      ".",
      call. = FALSE
    )
  }

  sample.names <- rownames(datM)
  if (is.null(sample.names)) {
    sample.names <- rep.int("", number.of.samples)
  }

  # Fresh output matrix for in-place C++ scatter.
  calibrated <- matrix(
    NA_real_,
    nrow = number.of.samples,
    ncol = number.of.probes,
    dimnames = dimnames(datM)
  )

  success <- rep.int(FALSE, number.of.samples)
  h.applied.vec <- rep(NA, number.of.samples)

  # constant across samples: sync fitted them once, and stores them numeric.
  gold.a <- gold[["a"]]
  gold.b <- gold[["b"]]
  gold.thresholds <- gold[["thresholds"]]
  mod1U <- gold[["unmethylated.mode"]]
  mod1M <- gold[["methylated.mode"]]

  process_sample <- function(ii, beta2.v) {
    beta2.v <- as.numeric(beta2.v)
    sample.name <- sample.names[ii]
    stage <- "value check"

    tryCatch(
      {
        # closed [0, 1]: fit_mixture() clips the endpoints inward.
        scan_finite_unit_interval_cpp(
          beta2.v,
          name = "The sample",
          require_open = FALSE
        )

        stage <- "sample mode estimation"

        low.mode.values <- beta2.v[beta2.v < 0.4]
        high.mode.values <- beta2.v[beta2.v > 0.6]

        mod2U <- estimate_mode(
          low.mode.values,
          paste0("Sample ", ii, " values below 0.4")
        )

        mod2M <- estimate_mode(
          high.mode.values,
          paste0("Sample ", ii, " values above 0.6")
        )

        stage <- "initial threshold construction"

        unmethylated.shift <- mod2U - mod1U
        methylated.shift <- mod2M - mod1M

        # Mode-shift init cuts: per-boundary (nL=3) or averaged (nL=2).
        if (nL == 3L) {
          th2.initial <- c(
            gold.thresholds[1L] + unmethylated.shift,
            gold.thresholds[2L] + methylated.shift
          )
        } else {
          th2.initial <- gold.thresholds[1L] +
            0.5 * (unmethylated.shift + methylated.shift)
        }

        # Init cuts only; sorting crossed mode-shifts is safe (not fitted thresholds).
        th2.initial <- sort(th2.initial)

        check_thresholds(
          th2.initial,
          nL = nL,
          name = paste0("Sample ", ii, " initial thresholds")
        )

        stage <- "sample mixture fitting"

        sample.fit <- fit_mixture(
          beta = beta2.v,
          thresholds = th2.initial,
          nL = nL,
          niter = niter,
          tol = tol,
          beta.maxit = beta.maxit,
          beta.score.tol = beta.score.tol,
          context = paste0("Sample ", ii)
        )

        em2.o <- sample.fit[["em"]]
        classAV2.v <- sample.fit[["component_means"]]
        class2.v <- sample.fit[["full_class"]]

        nbeta2.v <- beta2.v

        U <- 1L
        M <- nL
        # Assign every U/M observation to one tail (including exact mean).
        selU.idx <- which(class2.v == U)
        selUL.idx <- selU.idx[beta2.v[selU.idx] <= classAV2.v[U]]
        selUR.idx <- selU.idx[beta2.v[selU.idx] > classAV2.v[U]]
        selM.idx <- which(class2.v == M)
        selML.idx <- selM.idx[beta2.v[selM.idx] < classAV2.v[M]]
        selMR.idx <- selM.idx[beta2.v[selM.idx] >= classAV2.v[M]]

        if (nL == 2L) {
          stage <- "nL=2 truncated U/M quantile normalization"
          nbeta2.v <- normalize_nl2(
            beta = beta2.v,
            class = class2.v,
            sample.a = as.numeric(em2.o[["a"]][, 1L]),
            sample.b = as.numeric(em2.o[["b"]][, 1L]),
            gold.a = gold.a,
            gold.b = gold.b,
            sample.threshold = sample.fit[["thresholds"]][1L],
            gold.threshold = gold.thresholds[1L],
            context = paste0("Sample ", ii, " nL=2 map")
          )
        } else {
          stage <- "unmethylated quantile normalization"

          if (length(selUL.idx)) {
            nbeta2.v[selUL.idx] <- map_beta_q(
              beta2.v[selUL.idx],
              em2.o[["a"]][U, 1L],
              em2.o[["b"]][U, 1L],
              gold.a[U],
              gold.b[U],
              lower.tail = TRUE
            )
          }

          if (length(selUR.idx)) {
            nbeta2.v[selUR.idx] <- map_beta_q(
              beta2.v[selUR.idx],
              em2.o[["a"]][U, 1L],
              em2.o[["b"]][U, 1L],
              gold.a[U],
              gold.b[U],
              lower.tail = FALSE
            )
          }

          stage <- "methylated quantile normalization"

          if (length(selMR.idx)) {
            nbeta2.v[selMR.idx] <- map_beta_q(
              beta2.v[selMR.idx],
              em2.o[["a"]][M, 1L],
              em2.o[["b"]][M, 1L],
              gold.a[M],
              gold.b[M],
              lower.tail = FALSE
            )
          }
        }

        h.applied <- FALSE
        if (doH) {
          h.attempt <- tryCatch(
            {
              stage <- "intermediate/H normalization"

              # Means already ordered in fit_mixture().
              if (!length(selMR.idx)) {
                stop(
                  "H normalization needs methylated probes above the ",
                  "methylated-component mean.",
                  call. = FALSE
                )
              }

              selH.idx <- unique(c(which(class2.v == 2L), selML.idx))
              if (!length(selH.idx)) {
                stop(
                  "Intermediate/H normalization set is empty.",
                  call. = FALSE
                )
              }

              minH <- min(beta2.v[selH.idx])
              maxH <- max(beta2.v[selH.idx])
              deltaH <- maxH - minH
              nminH <- max(nbeta2.v[selU.idx])
              nmaxH <- min(nbeta2.v[selMR.idx])
              ndeltaH <- nmaxH - nminH

              if (!(deltaH > 0) || !(ndeltaH > 0)) {
                stop(
                  "H conformal map is degenerate ",
                  "(deltaH = ",
                  signif(deltaH, 8),
                  ", ndeltaH = ",
                  signif(ndeltaH, 8),
                  ").",
                  call. = FALSE
                )
              }

              hf <- ndeltaH / deltaH
              nbeta2.v[selH.idx] <-
                nminH + hf * (beta2.v[selH.idx] - minH)

              TRUE
            },
            error = function(e) e
          )

          if (isTRUE(h.attempt)) {
            h.applied <- TRUE
          } else if (h.policy == "optional") {} else {
            stop(h.attempt)
          }
        }

        stage <- "sample output validation"

        if (
          any(!is.finite(nbeta2.v)) ||
            any(nbeta2.v < -1e-12 | nbeta2.v > 1 + 1e-12)
        ) {
          stop(
            "Normalization produced invalid beta values; range: [",
            paste(signif(range(nbeta2.v, finite = TRUE), 8), collapse = ", "),
            "].",
            call. = FALSE
          )
        }
        nbeta2.v <- pmin(1, pmax(0, nbeta2.v))

        list(
          beta = nbeta2.v,
          h_applied = h.applied
        )
      },
      error = function(error) {
        if (inherits(error, "bmiq_sample_error")) {
          stop(error)
        }

        stop(
          structure(
            list(
              message = paste0(
                "Sample ",
                ii,
                if (nzchar(sample.name)) {
                  paste0(" (", sample.name, ")")
                } else {
                  ""
                },
                " failed during ",
                stage,
                ": ",
                conditionMessage(error)
              ),
              call = NULL,
              parent = error
            ),
            class = c("bmiq_sample_error", "error", "condition")
          )
        )
      }
    )
  }

  # Process samples in contiguous probes x block chunks (cache-friendly).
  sample.block.size <- 8L

  for (block.start in seq.int(1L, number.of.samples, by = sample.block.size)) {
    block.count <- min(
      sample.block.size,
      number.of.samples - block.start + 1L
    )

    block <- gather_sample_block_cpp(
      datM,
      first_sample = block.start,
      sample_count = block.count
    )

    for (local.sample in seq_len(block.count)) {
      ii <- block.start + local.sample - 1L

      attempt <- tryCatch(
        process_sample(ii, block[, local.sample]),
        bmiq_sample_error = function(error) error
      )

      if (inherits(attempt, "bmiq_sample_error")) {
        if (on.sample.error == "stop") {
          stop(attempt)
        }

        success[ii] <- FALSE

        if (failed.sample == "NA") {
          block[, local.sample] <- NA_real_
        }
        # failed.sample == "original": leave the gathered originals in place.

        next
      }

      block[, local.sample] <- attempt[["beta"]]
      success[ii] <- TRUE
      if (doH) {
        h.applied.vec[ii] <- attempt[["h_applied"]]
      }
    }

    scatter_sample_block_cpp(
      destination = calibrated,
      block = block,
      first_sample = block.start
    )

    rm(block)
  }

  # Caller reports failures / h.applied (has clock id and sample ids).
  list(
    calibrated = calibrated,
    success = success,
    h.applied = h.applied.vec
  )
}
