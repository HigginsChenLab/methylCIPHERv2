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
  mc_note_scoring_failure(block, id, failed)
  say_scored_na(
    id,
    failed,
    cli::format_inline(
      "BMIQ calibration failed for {length(failed)} sample{?s}:"
    )
  )

  # h.applied == FALSE is a sample that scored from a partly calibrated panel
  partial <- block[["sample_id"]][fit[["h.applied"]] %in% FALSE]
  mc_note_partial_calibration(block, id, partial)

  fit[["calibrated"]]
}

BMIQ_SAY_AT <- 25L

# one calibration per (scheme, background) in a block; key is NULL if unshared.
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

# shared background cache; NA reporting stays per clock.
bmiq_fit <- function(obs, target, id, block, key) {
  betas <- obs[["values"]]
  args <- list(
    goldstandard.beta = target[obs[["cols"]]],
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
