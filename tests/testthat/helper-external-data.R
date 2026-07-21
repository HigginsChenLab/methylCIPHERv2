# Fake external packs for unit tests: tiny qs2 over file://, never the network.

# Build one fake pack on disk; returns the provenance row it corresponds to.
fake_asset <- function(dir, group = "FakeGroup", payload = NULL) {
  if (is.null(payload)) {
    payload <- list(
      group_id = group,
      encoding = "canonical_matrices",
      encoding_version = 3L,
      cpgs = c("cg00000029", "cg00000108"),
      coefficient_matrix = matrix(1:4, 2)
    )
  }
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  # Content hash matches the package's mc_payload_hash(): no drift warning on load.
  phash <- mc_payload_hash(payload)
  file <- sprintf("%s-%s.qs2", tolower(group), phash)
  rtag <- sub("\\.qs2$", "", file) # tag = filename stem; bare hex tags rejected by GitHub.
  src <- file.path(dir, file)
  qs2::qs_save(payload, src)
  list(
    group_id = group,
    payload_hash = phash,
    release_tag = rtag,
    file = file,
    size_bytes = as.numeric(file.size(src)),
    encoding = payload$encoding,
    encoding_version = payload$encoding_version,
    n_clocks = 1L,
    n_cpgs = length(payload$cpgs),
    .payload = payload,
    .src = as.character(src)
  )
}

# Synthetic SystemsAge pack over `cpgs`: organ/system coef columns, an age vector, and
# vendor means, plus a small self-consistent systems_PCA tensor tree keyed by the
# catalog's component file paths. Values are deterministic (seeded); goldens are the
# recipe math computed in-test. Mirrors the real encode_systemsage() layout.
fake_systemsage_pack <- function(cpgs, seed = 1L) {
  order <- systemsage_stack_order("SystemsAge") # 12 labels, stack order
  organs <- setdiff(order, "Age_prediction") # 11 organ labels
  ncpg <- length(cpgs)
  pcs <- paste0("PC", seq_len(12L))
  comp_file <- function(name) {
    comp <- Filter(function(x) identical(x$name, name), clock_components("SystemsAge"))
    comp[[1]]$file
  }
  withr::with_seed(seed, {
    organs_mat <- matrix(
      stats::rnorm(ncpg * 11L), ncpg, 11L, dimnames = list(NULL, organs)
    )
    systems_mat <- matrix(
      stats::rnorm(ncpg * 11L), ncpg, 11L, dimnames = list(NULL, organs)
    )
    age_vec <- stats::rnorm(ncpg)
    impute_vec <- stats::runif(ncpg)
    rot <- matrix(stats::rnorm(144L), 12L, 12L)
    center <- stats::setNames(stats::rnorm(12L), order)
    scale <- stats::setNames(stats::runif(12L, 0.5, 1.5), order)
    model <- stats::setNames(stats::rnorm(12L), pcs)
  })
  rot_df <- cbind(
    data.frame(system = order, stringsAsFactors = FALSE),
    stats::setNames(as.data.frame(rot), pcs)
  )
  list(
    group_id = "SystemsAge",
    cpgs = cpgs,
    organs = organs_mat,
    systems = systems_mat,
    age = age_vec,
    impute = impute_vec,
    tensors = stats::setNames(
      list(center, scale, rot_df, model),
      c(
        comp_file("systems_pca_center"),
        comp_file("systems_pca_scale"),
        comp_file("systems_pca_rotation"),
        comp_file("systems_model")
      )
    )
  )
}

# Mock the provenance registry + file:// download URLs for the calling test.
local_fake_registry <- function(rows, .env = parent.frame()) {
  if (!is.null(rows$group_id)) {
    rows <- stats::setNames(list(rows), rows$group_id)
  }
  testthat::local_mocked_bindings(
    mc_external_groups = function() names(rows),
    mc_asset = function(group_id) {
      row <- rows[[group_id]]
      if (is.null(row)) {
        stop("Not an external clock group: ", group_id, call. = FALSE)
      }
      row
    },
    # mustWork=FALSE so a deleted source still yields a URL and the download 404s.
    mc_asset_url = function(row) {
      paste0("file:///", normalizePath(row$.src, winslash = "/", mustWork = FALSE))
    },
    .env = .env
  )
  invisible(rows)
}
