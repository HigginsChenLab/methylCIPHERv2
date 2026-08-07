# normalize-then-linear over the clock's declared panel and target

score_normalized <- function(id, cpgs, block, results) {
  # declined or not requested -- score raw
  if (!cpgs[["normalizes"]]) {
    return(linear_score(cpgs, block))
  }

  scheme <- clock_norm_scheme(id)
  target <- clock_norm_target(id)
  # scoring CpGs are a subset of the background panel
  obs <- observed_panel(
    cpgs[["norm_present"]],
    cpgs[["norm_present_idx"]],
    block
  )

  # unimplemented scheme already stopped in score_type()
  calibrated <- switch(
    scheme,
    bmiq = bmiq_panel(obs, target, id, block, cpgs[["norm_panel_key"]]),
    stop(
      sprintf(
        "No normalization branch for scheme %s (clock %s).",
        scheme,
        id
      ),
      call. = FALSE
    )
  )

  linear_score(
    cpgs,
    block,
    observed = list(
      cols = cpgs[["score_present"]],
      values = calibrated[, cpgs[["score_present"]], drop = FALSE]
    )
  )
}

# bmiq onto vendored gold (absent probes dropped, unfit samples -> NA + notes)
bmiq_panel <- function(obs, target, id, block, key) {
  fit <- bmiq_fit(obs, target, id, block, key)

  failed <- block[["sample_id"]][!fit[["success"]]]
  note_scoring_failure(block, id, failed)
  say_scored_na(
    id,
    failed,
    cli::format_inline(
      "BMIQ calibration failed for {length(failed)} sample{?s}:"
    )
  )

  # h.applied stays NA unless the sample calibrated, so FALSE is the one state
  # that means H was skipped on a sample that scored.
  partial <- block[["sample_id"]][fit[["h.applied"]] %in% FALSE]
  say_partial_calibration(id, partial)

  fit[["calibrated"]]
}

# calibration costs about 80 ms a sample, so this is roughly two seconds of
# work. under it the run ends before a reader looks up.
BMIQ_SAY_AT <- 25L

# one calibration per (scheme, background panel) in a block. `key` is NULL where
# no second clock can reuse it, so a lone normalizing clock retains nothing.
#
# the betas are not in `args` and do not need to be: within one block the panel
# index fixes norm_present and norm_present_idx, so it fixes what
# observed_panel() returns. everything else the kernel reads is in `args`, which
# is stored beside the result and compared whole. a tuning argument cannot join
# the call without joining the key, which a hand-listed key cannot promise.
norm_cached <- function(block, key, args, compute) {
  cache <- block[["norm_cache"]]
  hit <- if (is.null(key)) NULL else cache[[key]]
  if (!is.null(hit) && identical(hit[["args"]], args)) {
    return(hit[["value"]])
  }

  value <- compute()
  if (!is.null(key)) {
    cache[[key]] <- list(args = args, value = value)
  }
  value
}

# the calibration is a fact about the background, not about the clock, so two
# clocks on one background share it. the reporting above stays per clock: each
# one really does score NA for a sample the calibration could not fit.
bmiq_fit <- function(obs, target, id, block, key) {
  betas <- obs[["values"]]
  args <- list(
    goldstandard.beta = target[obs[["cols"]]],
    nfit = ncol(betas),
    verbose = FALSE,
    on.sample.error = "continue",
    failed.sample = "NA"
  )

  norm_cached(
    block,
    if (is.null(key)) NULL else paste0("bmiq/", key),
    args,
    function() {
      n <- nrow(betas)
      if (n >= BMIQ_SAY_AT) {
        cli::cli_progress_step("Normalizing {n} sample{?s} for {.val {id}}.")
      }
      do.call(bmiq_calibration, c(list(betas), args))
    }
  )
}
