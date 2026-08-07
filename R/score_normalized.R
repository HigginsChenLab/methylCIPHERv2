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
    bmiq = bmiq_panel(obs, target, id, block),
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
bmiq_panel <- function(obs, target, id, block) {
  fit <- bmiq_calibration(
    obs[["values"]],
    goldstandard.beta = target[obs[["cols"]]],
    nfit = ncol(obs[["values"]]),
    verbose = FALSE,
    on.sample.error = "continue",
    failed.sample = "NA"
  )

  failed <- block[["sample_id"]][!fit[["success"]]]
  if (length(failed)) {
    note_scoring_failure(block, id, failed)
    say_scored_na(
      id,
      failed,
      cli::format_inline(
        "BMIQ calibration failed for {length(failed)} sample{?s}:"
      )
    )
  }

  # H skipped: scored, but on a partly calibrated panel. not a failure, so it
  # takes no note -- a note would read as an NA the sample does not have.
  partial <- block[["sample_id"]][
    fit[["success"]] & !is.na(fit[["h.applied"]]) & !fit[["h.applied"]]
  ]
  if (length(partial)) {
    cli::cli_warn(
      c(
        "BMIQ calibration skipped the intermediate component for
         {length(partial)} sample{?s}:",
        capped_bullets(partial, val_lines),
        "i" = "{.val {id}} scores
               {cli::qty(partial)}{?this sample/these samples} from partly
               calibrated data."
      ),
      call = NULL
    )
  }

  fit[["calibrated"]]
}
