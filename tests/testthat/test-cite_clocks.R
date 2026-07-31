test_that("every catalog clock reaches at least one citation", {
  ids <- mc_index[["clock_id"]]
  aliases <- unique(unname(sex_routed_members()$alias))

  # aliases are package-minted and cite through their donor
  expect_true(all(setdiff(ids, aliases) %in% mc_citations[["clock_id"]]))
  donors <- vapply(
    mc_catalog[aliases],
    function(e) as.character(e[["donor_clock_id"]]),
    character(1L)
  )
  expect_true(all(donors %in% mc_citations[["clock_id"]]))

  expect_true(all(mc_index[["n_citations"]] >= 1L))
  expect_equal(
    mc_index[["n_citations"]][match("Hannum", ids)],
    sum(mc_citations[["clock_id"]] == "Hannum")
  )
  # exactly one primary per cited clock
  expect_true(all(
    tapply(
      mc_citations[["role"]] == "primary",
      mc_citations[["clock_id"]],
      sum
    ) ==
      1L
  ))
})

test_that("cite_clocks speaks the same clock tokens as calc_clocks", {
  one <- cite_clocks("Hannum")
  expect_s3_class(one, "mc_citation")
  expect_equal(unique(as.data.frame(one)$clock_id), "Hannum")
  expect_true(any(grepl("^@", one$bibtex)))

  grp <- cite_clocks("GrimAge")
  expect_setequal(
    unique(as.data.frame(grp)$clock_id),
    resolve_clocks("GrimAge")
  )
  expect_setequal(
    unique(as.data.frame(cite_clocks("all"))$clock_id),
    resolve_clocks("all")
  )

  # one entry per distinct paper, however many clocks share it
  many <- cite_clocks(c("Hannum", "Horvath1", "PhenoAge"))
  expect_equal(
    sum(grepl("^@", many$bibtex)),
    length(unique(as.data.frame(many)$bib_key))
  )

  expect_error(cite_clocks(42))
  expect_error(cite_clocks("DNAmFitAge_Female"))
})

test_that("a sex-routed alias cites through its donor", {
  alias <- unique(unname(sex_routed_members()$alias))[[1L]]
  donor <- mc_catalog[[alias]][["donor_clock_id"]]
  links <- as.data.frame(cite_clocks(alias))

  expect_equal(unique(links$clock_id), alias)
  expect_equal(
    links$bib_key,
    mc_citations$bib_key[mc_citations$clock_id == donor]
  )
})

test_that("a result cites the clocks it reported", {
  sim <- sim_DNAm(c("Hannum", "PhenoAge"), n = 3L, Age = TRUE, Female = TRUE)
  res <- calc_clocks(sim$DNAm, c("Hannum", "PhenoAge"), pheno = sim$pheno)
  cit <- cite_clocks(res)

  expect_setequal(unique(as.data.frame(cit)$clock_id), colnames(res$scores))

  # toBibtex is the export path: every key survives a round-trip to disk
  path <- withr::local_tempfile(fileext = ".bib")
  writeLines(toBibtex(cit), path, useBytes = TRUE)
  written <- grep("^@", readLines(path), value = TRUE)
  expect_true(all(
    unique(as.data.frame(cit)$bib_key) %in%
      sub("^@[^{]+\\{([^,]+),.*$", "\\1", written)
  ))
})

test_that("every shipped bib_key resolves in clocks.bib", {
  bib <- system.file("bibliography", "clocks.bib", package = "methylCIPHERv2")
  skip_if(!nzchar(bib) || !file.exists(bib))
  keys <- sub(
    "^@[^{]+\\{([^,]+),.*$",
    "\\1",
    grep(
      "^@",
      readLines(bib, warn = FALSE),
      value = TRUE
    )
  )
  expect_true(all(unique(mc_citations[["bib_key"]]) %in% trimws(keys)))
})

test_that("the citation frame carries the paper's own fields", {
  df <- as.data.frame(cite_clocks("all"))

  paper_cols <- c("title", "author", "year", "journal", "doi", "url")
  expect_true(all(paper_cols %in% names(df)))
  # every .bib entry declares these, so a NA here means the join lost a key
  for (col in paper_cols) {
    expect_false(anyNA(df[[col]]))
  }

  # one paper, one set of field values, however many clocks cite it
  expect_true(all(
    vapply(
      split(df[["title"]], df[["bib_key"]]),
      function(v) {
        length(unique(v)) == 1L
      },
      logical(1L)
    )
  ))
})

test_that("the stored paper fields are the vendored clocks.bib text", {
  bib <- system.file("bibliography", "clocks.bib", package = "methylCIPHERv2")
  skip_if(!nzchar(bib) || !file.exists(bib))

  # brace-stripped, so the {DNA}/{eLife} casing protection does not block a match
  txt <- gsub(
    "[{}]",
    "",
    paste(readLines(bib, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  )
  df <- unique(as.data.frame(cite_clocks("all"))[, c(
    "title",
    "doi",
    "journal"
  )])

  for (col in names(df)) {
    hit <- vapply(df[[col]], grepl, logical(1L), x = txt, fixed = TRUE)
    expect_true(all(hit))
  }
})
