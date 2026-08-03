# every CpG a clocks= request needs measured -- panels plus declared moment refs

#' @export
clock_cpgs <- function(
  clocks,
  normalize = NULL,
  ext_data = NULL,
  ask = TRUE
) {
  # the sequence, not the request: a composite reads its dependencies' panels
  clock_sequence <- resolve_clocks_sequence(resolve_clocks(clocks))
  normalize <- resolve_normalize(normalize, clock_sequence)
  packs <- load_mc_assets(pack_groups_needed(clock_sequence), ext_data, ask)
  sequence_cpgs(clock_sequence, packs, normalize)
}

# panels plus declared moment refs for a resolved sequence (one union).
sequence_cpgs <- function(clock_sequence, packs = NULL, normalize = NULL) {
  cpgs <- union(
    clock_panels_union(clock_sequence, packs, normalize),
    unlist(resolve_moment_domains(clock_sequence), use.names = FALSE)
  )
  cpgs[nzchar(cpgs) & !is.na(cpgs)]
}

# scoring panels plus, where a clock normalizes, its background panel
clock_panels_union <- function(clock_ids, packs, normalize) {
  panels <- clock_panels(clock_ids, packs, normalize)
  score <- panels[["score"]]
  # an empty scoring panel is fine only for a sex-routed alias (owns no panel)
  unresolved <- clock_ids[vapply(
    seq_along(clock_ids),
    function(i) {
      !length(score[["uniq"]][[score[["idx"]][[i]]]]) &&
        !length(clock_depends_on(clock_ids[[i]]))
    },
    logical(1)
  )]

  if (length(unresolved)) {
    cli::cli_abort(
      c(
        "Couldn't resolve any scoring CpGs for {.val {unresolved}}.",
        "i" = "If these are external clocks, try loading their packs first
               with {.fn load_mc_assets}."
      ),
      call = NULL
    )
  }

  # the caller filters: one blank/NA screen over the whole answer, not two
  panels_union(panels)
}
