# qc_report(context =): what a supplied context adds to the page.

ctx_fixture <- function(n = 12L) {
  withr::local_seed(7L, .local_envir = parent.frame())
  qc_fixture(n)
}

ctx_page <- function(fx, context, ...) {
  path <- withr::local_tempfile(fileext = ".html", .local_envir = parent.frame())
  qc_report(fx$DNAm, fx$pheno, fx$result, clocks = fx$clocks, file = path,
            open = FALSE, context = context, ...)
  read_page(path)
}

ctx_full <- function(ids) {
  list(
    version = 1L,
    source = "Curator",
    cards = list(heading = "How the data were made", items = list(
      list(label = "Decisions", value = "3", status = "info", detail = "2 agents")
    )),
    comparisons = list(
      list(label = "Number of replicates", stated = "1", stated_from = "record",
           measured = "2", measured_from = "table", status = "warn", ref = "col.site"),
      list(label = "Number of samples", stated = "12", measured = "12", status = "ok")
    ),
    findings = list(list(status = "info", text = "Three columns were derived.", ref = "col.site")),
    notes = list(
      list(on = "variable", key = "site", text = "From the title column.", ref = "col.site",
           badge = list(text = "confidence low", status = "warn"), details = "Long <reason>."),
      list(on = "variable", key = "site", topic = "missing", text = "Read as not applicable."),
      list(on = "variable", key = "Female", text = "Mapped from gender."),
      list(on = "variable", key = "cRACE", text = "Not in the source."),
      list(on = "section", key = "dnam", text = "Values copied without conversion.",
           fields = list(`Source file` = "betas.txt.gz", Probes = "485,000")),
      list(on = "section", key = "clocks-age", kind = "account", text = "The age came from the record.", ref = "col.Age"),
      list(on = "section", key = "no-such-part", text = "Lost note."),
      list(on = "sample", key = ids[[1L]], text = "Replicate set 1.")
    ),
    sections = list(list(id = "record", heading = "What was done", blocks = list(
      list(type = "text", kind = "account", text = "It mapped three columns.", ref = list("col.site", "q.unknown")),
      list(type = "table", id = "decisions", heading = "Decisions",
           columns = list(id = "Decision", agent = "Agent", variable = "Variable", why = "Rationale"),
           anchor = "id", details = "why", filters = "agent", flag = "variable", refs = "id",
           rows = list(
             list(id = "col.site", agent = "data", variable = "site", why = "Because."),
             list(id = "col.Age", agent = "meta", variable = "Age", why = "")
           ))
    )))
  )
}

test_that("a NULL context gives the same page as no context", {
  withr::local_seed(20260925L)
  fx <- qc_fixture()
  local_mocked_bindings(qc_now = function() as.POSIXct("2026-01-01 12:00", tz = "UTC"))
  a <- withr::local_tempfile(fileext = ".html")
  b <- withr::local_tempfile(fileext = ".html")
  qc_report(fx$DNAm, fx$pheno, fx$result, clocks = fx$clocks, file = a, open = FALSE)
  qc_report(fx$DNAm, fx$pheno, fx$result, clocks = fx$clocks, file = b, open = FALSE, context = NULL)
  expect_identical(readLines(a), readLines(b))
  expect_no_match(read_page(a), "ctx-", fixed = TRUE)
})

test_that("each part of a context lands in its place", {
  fx <- ctx_fixture()
  page <- ctx_page(fx, ctx_full(rownames(fx$DNAm)))
  # overview: legend, comparisons, cards, findings
  expect_match(page, "includes a context from Curator", fixed = TRUE)
  expect_match(page, "<h3 id=\"overview-compare\">Stated and measured</h3>", fixed = TRUE)
  expect_match(page, "Number of replicates: the stated value is 1 (record), the measured value is 2 (table).", fixed = TRUE)
  expect_match(page, "<h3>How the data were made</h3>", fixed = TRUE)
  expect_match(page, "Three columns were derived.", fixed = TRUE)
  expect_no_match(page, "Number of samples: the stated value", fixed = TRUE)
  # pheno: variable notes, the missing reason, a variable not in pheno
  expect_match(page, "<tr id=\"var-site\">", fixed = TRUE)
  expect_match(page, "Missing values: Read as not applicable.", fixed = TRUE)
  expect_match(page, "<th>Stated reason</th>", fixed = TRUE)
  expect_match(page, "Not in pheno", fixed = TRUE)
  expect_match(page, "Long &lt;reason&gt;.", fixed = TRUE)
  # a note under a section heading and under a sub-head
  expect_match(page, "<h2>Methylation data</h2><div class=\"ctx-note ctx-fact\">", fixed = TRUE)
  expect_match(page, "Age correlation against blood</h3><div class=\"ctx-note ctx-account\">", fixed = TRUE)
  expect_match(page, "betas.txt.gz", fixed = TRUE)
  # a note on a part the page does not have goes to the overview
  expect_match(page, "[no-such-part] Lost note.", fixed = TRUE)
  # samples
  expect_match(page, "<h4>Notes on samples</h4>", fixed = TRUE)
  expect_match(page, "Replicate set 1.", fixed = TRUE)
  # the extra section: nav, anchors, filters, folded details
  expect_match(page, "<a href=\"#record\">What was done</a>", fixed = TRUE)
  expect_match(page, "<tr id=\"ref-col-site\" data-f1=\"data\">", fixed = TRUE)
  expect_match(page, "<a class=\"ctx-ref\" href=\"#ref-col-site\"><code>col.site</code></a>", fixed = TRUE)
  expect_match(page, "<span class=\"ctx-ref\"><code>q.unknown</code></span>", fixed = TRUE)
  expect_match(page, "#tbl-decisions:has(input[name=\"tbl-decisions-f1\"][value=\"data\"]:checked)", fixed = TRUE)
  expect_match(page, "<details><summary>Show</summary><pre class=\"ctx-details\">Because.</pre>", fixed = TRUE)
  # the section sits between the clock results and the bibliography
  expect_lt(regexpr("<section id=\"clocks\">", page, fixed = TRUE), regexpr("<section id=\"record\">", page, fixed = TRUE))
  expect_lt(regexpr("<section id=\"record\">", page, fixed = TRUE), regexpr("<section id=\"bib\">", page, fixed = TRUE))
})

test_that("every ref link in the page points at an id in the page", {
  fx <- ctx_fixture()
  page <- ctx_page(fx, ctx_full(rownames(fx$DNAm)))
  hrefs <- regmatches(page, gregexpr("href=\"#[^\"]+\"", page))[[1L]]
  targets <- unique(sub("^href=\"#(.*)\"$", "\\1", hrefs))
  ids <- sub("^id=\"(.*)\"$", "\\1", regmatches(page, gregexpr("id=\"[^\"]+\"", page))[[1L]])
  expect_true(all(targets %in% ids), label = paste(setdiff(targets, ids), collapse = ", "))
})

test_that("context text is escaped, never read as markup", {
  fx <- ctx_fixture()
  ctx <- list(version = 1L, source = "<b>me</b>",
              findings = list(list(status = "warn", text = "<script>alert(1)</script>")),
              notes = list(list(on = "variable", key = "site", text = "a & b <i>")))
  page <- ctx_page(fx, ctx)
  expect_no_match(page, "<script>", fixed = TRUE)
  expect_match(page, "&lt;script&gt;alert(1)&lt;/script&gt;", fixed = TRUE)
  expect_match(page, "a &amp; b &lt;i&gt;", fixed = TRUE)
  expect_match(page, "&lt;b&gt;me&lt;/b&gt;", fixed = TRUE)
})

test_that("findings on Age and Female link to the notes on them", {
  fx <- ctx_fixture()
  # no chrX or chrY CpGs, so no sex call: the finding points at Female
  page <- ctx_page(fx, list(version = 1L, notes = list(list(on = "variable", key = "Female", text = "From gender."))))
  expect_match(page, "could not be checked. <a href=\"#var-Female\">See the notes on Female.</a>", fixed = TRUE)
})

test_that("a table with a flag column marks the variables the report flagged", {
  fx <- ctx_fixture()
  fx$pheno[["site"]][1:6] <- NA
  ctx <- list(version = 1L, sections = list(list(id = "queue", heading = "Queue", blocks = list(
    list(type = "table", columns = list(v = "Variable", q = "Question"), flag = "v", sort_flagged = TRUE,
         rows = list(list(v = "Age", q = "First?"), list(v = "site", q = "Second?")))
  ))))
  page <- ctx_page(fx, ctx)
  expect_match(page, "<th>Flagged by this report</th>", fixed = TRUE)
  expect_match(page, "More than 20% missing", fixed = TRUE)
  # the flagged row moved first
  expect_lt(regexpr("Second?", page, fixed = TRUE), regexpr("First?", page, fixed = TRUE))
})

test_that("a JSON file gives the same page as the list it holds", {
  fx <- ctx_fixture()
  ctx <- ctx_full(rownames(fx$DNAm))
  json <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(ctx, json, auto_unbox = TRUE)
  local_mocked_bindings(qc_now = function() as.POSIXct("2026-01-01 12:00", tz = "UTC"))
  expect_identical(ctx_page(fx, json), ctx_page(fx, ctx))
})

test_that("a malformed context is refused before anything is written", {
  fx <- ctx_fixture()
  bad <- list(
    no_version = list(notes = list()),
    version_2 = list(version = 2L),
    unknown_key = list(version = 1L, extra = 1),
    bad_status = list(version = 1L, findings = list(list(status = "red", text = "x"))),
    bad_on = list(version = 1L, notes = list(list(on = "clock", key = "a", text = "x"))),
    bad_section_key = list(version = 1L, notes = list(list(on = "section", key = "a b", text = "x"))),
    js_href = list(version = 1L, notes = list(list(on = "sample", key = "a", text = "x", href = "javascript:alert(1)"))),
    web_href = list(version = 1L, notes = list(list(on = "sample", key = "a", text = "x", href = "https://example.org"))),
    taken_id = list(version = 1L, sections = list(list(id = "pheno", heading = "x", blocks = list()))),
    bad_anchor = list(version = 1L, sections = list(list(id = "s", heading = "x", blocks = list(
      list(type = "table", columns = list(a = "A"), rows = list(), anchor = "b")
    )))),
    one_sample_group = list(version = 1L, sample_groups = list(label = "sets", groups = list(g1 = "a"))),
    number_text = list(version = 1L, findings = list(list(status = "ok", text = 3)))
  )
  for (nm in names(bad)) {
    path <- withr::local_tempfile(fileext = ".html")
    expect_error(
      qc_report(pheno = fx$pheno, file = path, open = FALSE, context = bad[[nm]]),
      label = nm
    )
    expect_false(file.exists(path), label = nm)
  }
  expect_error(qc_report(pheno = fx$pheno, open = FALSE, context = tempfile(fileext = ".json")))
})

test_that("sample groups: agreeing pairs pass, a swapped pair is flagged", {
  withr::local_seed(11L)
  clocks <- c("Horvath1", "Hannum", "PhenoAge")
  n_g <- 8L
  base <- random_betas(clock_cpgs(clocks), n = n_g)
  # each group: a sample and a near copy of it
  noise <- matrix(stats::rnorm(length(base), sd = 0.002), nrow(base))
  twin <- pmin(pmax(base + noise, 0), 1)
  rownames(twin) <- paste0(rownames(base), "_r")
  DNAm <- rbind(base, twin)
  pheno <- mc_pheno(rownames(DNAm), Age = rep(mc_ages(n_g), 2L), Female = rep(0:1, n_g))
  res <- calc_clocks(DNAm, clocks, pheno = pheno)
  groups <- stats::setNames(lapply(seq_len(n_g), function(i) c(rownames(base)[[i]], rownames(twin)[[i]])),
                            paste0("set", seq_len(n_g)))
  m <- as.matrix(res)
  ag <- qc_group_agreement(m, groups)
  expect_equal(ag[["k"]], n_g)
  expect_true(all(ag[["per_clock"]][["r"]] > 0.9))
  expect_false(any(ag[["per_group"]][["flag"]]))
  # swap one twin for another group's sample: that group now differs everywhere
  swapped <- groups
  swapped[["set1"]] <- c(rownames(base)[[1L]], rownames(twin)[[5L]])
  ag2 <- qc_group_agreement(m, swapped)
  expect_equal(ag2[["per_group"]][["group"]][ag2[["per_group"]][["flag"]]], "set1")

  path <- withr::local_tempfile(fileext = ".html")
  qc_report(pheno = pheno, x = res, file = path, open = FALSE,
            context = list(version = 1L, sample_groups = list(label = "replicate sets", ref = "col.id", groups = swapped)))
  page <- read_page(path)
  expect_match(page, "<h3 id=\"clocks-groups\">Agreement within sample groups</h3>", fixed = TRUE)
  expect_match(page, "1 of the replicate sets differ on most clocks: set1.", fixed = TRUE)
})

test_that("sample groups: too few complete groups is not computable", {
  fx <- ctx_fixture()
  ids <- rownames(fx$DNAm)
  ctx <- list(version = 1L, sample_groups = list(label = "sets", groups = list(
    a = ids[1:2], b = ids[3:4], c = c(ids[[5L]], "not-scored")
  )))
  page <- ctx_page(fx, ctx)
  expect_match(page, "Only 2 of the sets have two scored samples. The agreement check needs 5.", fixed = TRUE)
})
