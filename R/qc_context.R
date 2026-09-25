# qc_report(context =): notes, cards, findings and whole sections that the
# caller adds to the page. the package draws all of it. every string in a
# context is text and is escaped, so a context can never inject markup.
#
# a NULL context leaves the page byte for byte as it was: every hook below
# returns "" or its input unchanged when st[["ctx"]] is NULL.

QC_CTX_KEYS <- c(
  "version", "source", "cards", "comparisons", "findings", "notes",
  "sample_groups", "sections"
)
QC_CTX_STATUS <- c("ok", "warn", "bad", "na", "info")
QC_CTX_KINDS <- c("fact", "account")
QC_CTX_ON <- c("section", "variable", "sample")
# ids that become html ids: sections, sub-heads, blocks
QC_CTX_ID <- "^[A-Za-z][A-Za-z0-9_-]*$"
# sample notes beyond this many go behind a disclosure
QC_CTX_OPEN_ROWS <- 20L
# sample groups: fewest complete groups for a correlation, and the lowest
# correlation between the two samples of a group that reads as agreement
QC_GROUP_MIN <- 5L
QC_GROUP_MIN_R <- 0.8

# --- reading and checks ---------------------------------------------------------

qc_context_read <- function(context) {
  if (is.null(context)) {
    return(NULL)
  }
  if (checkmate::test_string(context)) {
    checkmate::assert_file_exists(context, access = "r", .var.name = "context")
    if (!requireNamespace("jsonlite", quietly = TRUE)) {
      cli::cli_abort(
        c(
          "Reading {.arg context} from a file needs the {.pkg jsonlite} package.",
          "i" = "Install {.pkg jsonlite}, or pass {.arg context} as a list."
        ),
        call = NULL
      )
    }
    context <- jsonlite::read_json(context, simplifyVector = FALSE)
  }
  check_qc_context(context)
}

# a string, or a list of strings as JSON reads an array, as a character vector
ctx_chr <- function(x, path, min.len = 1L, null.ok = TRUE) {
  if (is.null(x) && null.ok) {
    return(NULL)
  }
  if (is.list(x)) {
    checkmate::assert_list(x, types = "character", any.missing = FALSE, .var.name = path)
    x <- unlist(x, use.names = FALSE)
  }
  checkmate::assert_character(x, any.missing = FALSE, min.len = min.len, .var.name = path)
  x
}

ctx_str <- function(x, path, null.ok = TRUE, choices = NULL, pattern = NULL) {
  checkmate::assert_string(x, min.chars = 1L, null.ok = null.ok, .var.name = path)
  if (!is.null(x) && !is.null(choices)) {
    checkmate::assert_choice(x, choices, .var.name = path)
  }
  if (!is.null(x) && !is.null(pattern)) {
    checkmate::assert_string(x, pattern = pattern, .var.name = path)
  }
  x
}

# a link target: an anchor in the page, or a relative path. no scheme, so a
# context cannot add a javascript: link or send the reader off the machine.
ctx_href <- function(x, path) {
  x <- ctx_str(x, path)
  if (!is.null(x) && (grepl("^[A-Za-z][A-Za-z0-9+.-]*:", x) || startsWith(x, "//"))) {
    cli::cli_abort(
      c(
        "{.arg {path}} must be an anchor or a relative path.",
        "x" = "It starts with a scheme: {.val {x}}.",
        "i" = "Use a value such as {.val #section} or {.val ../file.txt}."
      ),
      call = NULL
    )
  }
  x
}

ctx_obj <- function(x, path, keys, required = character(0), null.ok = TRUE) {
  if (is.null(x) && null.ok) {
    return(NULL)
  }
  checkmate::assert_list(x, names = "unique", .var.name = path)
  checkmate::assert_names(names(x), subset.of = keys, must.include = required, .var.name = path)
  x
}

ctx_items <- function(x, path) {
  if (is.null(x)) {
    return(list())
  }
  checkmate::assert_list(x, types = "list", .var.name = path)
  unname(x)
}

ctx_path <- function(...) paste0("context", paste0("[[", c(...), "]]", collapse = ""))

# the whole context, checked and brought to one shape
check_qc_context <- function(context) {
  checkmate::assert_list(context, names = "unique", .var.name = "context")
  checkmate::assert_names(names(context), subset.of = QC_CTX_KEYS, must.include = "version", .var.name = "context")
  version <- context[["version"]]
  if (is.list(version)) {
    version <- unlist(version)
  }
  checkmate::assert_choice(as.character(version), "1", .var.name = ctx_path("\"version\""))
  out <- list(
    source = ctx_str(context[["source"]], ctx_path("\"source\"")),
    cards = ctx_check_cards(context[["cards"]]),
    comparisons = lapply(seq_along(ctx_items(context[["comparisons"]], ctx_path("\"comparisons\""))), function(i) {
      ctx_check_comparison(context[["comparisons"]][[i]], ctx_path("\"comparisons\"", i))
    }),
    findings = lapply(seq_along(ctx_items(context[["findings"]], ctx_path("\"findings\""))), function(i) {
      ctx_check_finding(context[["findings"]][[i]], ctx_path("\"findings\"", i))
    }),
    notes = lapply(seq_along(ctx_items(context[["notes"]], ctx_path("\"notes\""))), function(i) {
      ctx_check_note(context[["notes"]][[i]], ctx_path("\"notes\"", i))
    }),
    sample_groups = ctx_check_groups(context[["sample_groups"]]),
    sections = lapply(seq_along(ctx_items(context[["sections"]], ctx_path("\"sections\""))), function(i) {
      ctx_check_section(context[["sections"]][[i]], ctx_path("\"sections\"", i))
    })
  )
  ids <- vapply(out[["sections"]], `[[`, character(1L), "id")
  taken <- c("overview", "dnam", "pheno", "clocks", "bib", "notes")
  if (anyDuplicated(ids) || any(ids %in% taken)) {
    cli::cli_abort(
      c(
        "Each section in {.arg context} needs its own {.field id}.",
        "i" = "Do not repeat an id, and do not use {.val {taken}}."
      ),
      call = NULL
    )
  }
  out
}

ctx_check_cards <- function(x) {
  p <- ctx_path("\"cards\"")
  x <- ctx_obj(x, p, c("heading", "items"), "items")
  if (is.null(x)) {
    return(NULL)
  }
  items <- ctx_items(x[["items"]], ctx_path("\"cards\"", "\"items\""))
  list(
    heading = ctx_str(x[["heading"]], ctx_path("\"cards\"", "\"heading\"")),
    items = lapply(seq_along(items), function(i) {
      pi <- ctx_path("\"cards\"", "\"items\"", i)
      cd <- ctx_obj(items[[i]], pi, c("label", "value", "status", "detail"), c("label", "value"), null.ok = FALSE)
      card(
        ctx_str(cd[["label"]], paste0(pi, "[[\"label\"]]"), null.ok = FALSE),
        ctx_str(cd[["value"]], paste0(pi, "[[\"value\"]]"), null.ok = FALSE),
        ctx_str(cd[["status"]], paste0(pi, "[[\"status\"]]"), choices = QC_CTX_STATUS) %||% "info",
        ctx_str(cd[["detail"]], paste0(pi, "[[\"detail\"]]"))
      )
    })
  )
}

ctx_check_comparison <- function(x, p) {
  keys <- c("id", "label", "stated", "stated_from", "measured", "measured_from", "status", "ref", "note")
  x <- ctx_obj(x, p, keys, c("label", "stated", "measured", "status"), null.ok = FALSE)
  list(
    label = ctx_str(x[["label"]], paste0(p, "[[\"label\"]]"), null.ok = FALSE),
    stated = ctx_str(x[["stated"]], paste0(p, "[[\"stated\"]]"), null.ok = FALSE),
    stated_from = ctx_str(x[["stated_from"]], paste0(p, "[[\"stated_from\"]]")),
    measured = ctx_str(x[["measured"]], paste0(p, "[[\"measured\"]]"), null.ok = FALSE),
    measured_from = ctx_str(x[["measured_from"]], paste0(p, "[[\"measured_from\"]]")),
    status = ctx_str(x[["status"]], paste0(p, "[[\"status\"]]"), null.ok = FALSE, choices = QC_CTX_STATUS),
    ref = ctx_chr(x[["ref"]], paste0(p, "[[\"ref\"]]")),
    note = ctx_str(x[["note"]], paste0(p, "[[\"note\"]]"))
  )
}

ctx_check_finding <- function(x, p) {
  x <- ctx_obj(x, p, c("status", "text", "ref"), c("status", "text"), null.ok = FALSE)
  list(
    status = ctx_str(x[["status"]], paste0(p, "[[\"status\"]]"), null.ok = FALSE, choices = QC_CTX_STATUS),
    text = ctx_str(x[["text"]], paste0(p, "[[\"text\"]]"), null.ok = FALSE),
    ref = ctx_chr(x[["ref"]], paste0(p, "[[\"ref\"]]"))
  )
}

# a note, and also a text block or a list item, which take the same fields
ctx_check_text <- function(x, p, extra = character(0), required = "text") {
  keys <- c("text", "kind", "badge", "details", "fields", "ref", "href", extra)
  x <- ctx_obj(x, p, keys, required, null.ok = FALSE)
  badge <- ctx_obj(x[["badge"]], paste0(p, "[[\"badge\"]]"), c("text", "status"), "text")
  fields <- x[["fields"]]
  if (!is.null(fields)) {
    checkmate::assert_list(fields, types = "character", names = "unique", min.len = 1L, .var.name = paste0(p, "[[\"fields\"]]"))
    for (nm in names(fields)) {
      checkmate::assert_string(fields[[nm]], .var.name = paste0(p, "[[\"fields\"]][[\"", nm, "\"]]"))
    }
    fields <- unlist(fields)
  }
  list(
    text = ctx_str(x[["text"]], paste0(p, "[[\"text\"]]"), null.ok = !("text" %in% required)),
    kind = ctx_str(x[["kind"]], paste0(p, "[[\"kind\"]]"), choices = QC_CTX_KINDS) %||% "fact",
    badge = if (!is.null(badge)) {
      list(
        text = ctx_str(badge[["text"]], paste0(p, "[[\"badge\"]][[\"text\"]]"), null.ok = FALSE),
        status = ctx_str(badge[["status"]], paste0(p, "[[\"badge\"]][[\"status\"]]"), choices = QC_CTX_STATUS) %||% "info"
      )
    },
    details = ctx_str(x[["details"]], paste0(p, "[[\"details\"]]")),
    fields = fields,
    ref = ctx_chr(x[["ref"]], paste0(p, "[[\"ref\"]]")),
    href = ctx_href(x[["href"]], paste0(p, "[[\"href\"]]"))
  )
}

ctx_check_note <- function(x, p) {
  out <- ctx_check_text(x, p, c("on", "key", "topic"), c("on", "key", "text"))
  out[["on"]] <- ctx_str(x[["on"]], paste0(p, "[[\"on\"]]"), null.ok = FALSE, choices = QC_CTX_ON)
  out[["key"]] <- ctx_str(
    x[["key"]], paste0(p, "[[\"key\"]]"), null.ok = FALSE,
    pattern = if (out[["on"]] == "section") QC_CTX_ID
  )
  out[["topic"]] <- ctx_str(x[["topic"]], paste0(p, "[[\"topic\"]]"), choices = "missing")
  out
}

ctx_check_groups <- function(x) {
  p <- ctx_path("\"sample_groups\"")
  x <- ctx_obj(x, p, c("label", "text", "ref", "groups"), c("label", "groups"))
  if (is.null(x)) {
    return(NULL)
  }
  pg <- ctx_path("\"sample_groups\"", "\"groups\"")
  checkmate::assert_list(x[["groups"]], names = "unique", min.len = 1L, .var.name = pg)
  groups <- lapply(names(x[["groups"]]), function(g) {
    ids <- ctx_chr(x[["groups"]][[g]], paste0(pg, "[[\"", g, "\"]]"), min.len = 2L, null.ok = FALSE)
    checkmate::assert_character(ids, unique = TRUE, .var.name = paste0(pg, "[[\"", g, "\"]]"))
    ids
  })
  names(groups) <- names(x[["groups"]])
  list(
    label = ctx_str(x[["label"]], paste0(p, "[[\"label\"]]"), null.ok = FALSE),
    text = ctx_str(x[["text"]], paste0(p, "[[\"text\"]]")),
    ref = ctx_chr(x[["ref"]], paste0(p, "[[\"ref\"]]")),
    groups = groups
  )
}

ctx_check_section <- function(x, p) {
  x <- ctx_obj(x, p, c("id", "heading", "blocks"), c("id", "heading", "blocks"), null.ok = FALSE)
  blocks <- ctx_items(x[["blocks"]], paste0(p, "[[\"blocks\"]]"))
  list(
    id = ctx_str(x[["id"]], paste0(p, "[[\"id\"]]"), null.ok = FALSE, pattern = QC_CTX_ID),
    heading = ctx_str(x[["heading"]], paste0(p, "[[\"heading\"]]"), null.ok = FALSE),
    blocks = lapply(seq_along(blocks), function(i) ctx_check_block(blocks[[i]], paste0(p, "[[\"blocks\"]][[", i, "]]")))
  )
}

ctx_check_block <- function(x, p) {
  checkmate::assert_list(x, names = "unique", .var.name = p)
  type <- ctx_str(x[["type"]], paste0(p, "[[\"type\"]]"), null.ok = FALSE, choices = c("text", "list", "table"))
  id <- ctx_str(x[["id"]], paste0(p, "[[\"id\"]]"), pattern = QC_CTX_ID)
  heading <- ctx_str(x[["heading"]], paste0(p, "[[\"heading\"]]"))
  common <- c("type", "id", "heading")
  if (type == "text") {
    out <- ctx_check_text(x[setdiff(names(x), common)], p)
  } else if (type == "list") {
    x <- ctx_obj(x, p, c(common, "items"), "items", null.ok = FALSE)
    items <- ctx_items(x[["items"]], paste0(p, "[[\"items\"]]"))
    out <- list(items = lapply(seq_along(items), function(i) ctx_check_text(items[[i]], paste0(p, "[[\"items\"]][[", i, "]]"))))
  } else {
    out <- ctx_check_table(x, p, common)
  }
  c(list(type = type, id = id, heading = heading), out)
}

ctx_check_table <- function(x, p, common) {
  keys <- c(common, "text", "columns", "rows", "anchor", "details", "filters", "flag", "refs", "sort_flagged")
  x <- ctx_obj(x, p, keys, c("columns", "rows"), null.ok = FALSE)
  cols <- x[["columns"]]
  checkmate::assert_list(cols, types = "character", names = "unique", min.len = 1L, .var.name = paste0(p, "[[\"columns\"]]"))
  cols <- unlist(cols)
  one_col <- function(nm) {
    v <- ctx_str(x[[nm]], paste0(p, "[[\"", nm, "\"]]"))
    if (!is.null(v)) {
      checkmate::assert_choice(v, names(cols), .var.name = paste0(p, "[[\"", nm, "\"]]"))
    }
    v
  }
  some_cols <- function(nm) {
    v <- ctx_chr(x[[nm]], paste0(p, "[[\"", nm, "\"]]"))
    if (!is.null(v)) {
      checkmate::assert_subset(v, names(cols), .var.name = paste0(p, "[[\"", nm, "\"]]"))
    }
    v
  }
  anchor <- one_col("anchor")
  details <- one_col("details")
  flag <- one_col("flag")
  rows <- ctx_items(x[["rows"]], paste0(p, "[[\"rows\"]]"))
  rows <- lapply(seq_along(rows), function(i) {
    pr <- paste0(p, "[[\"rows\"]][[", i, "]]")
    r <- ctx_obj(rows[[i]], pr, names(cols), null.ok = FALSE)
    lapply(stats::setNames(names(cols), names(cols)), function(nm) ctx_check_cell(r[[nm]], paste0(pr, "[[\"", nm, "\"]]")))
  })
  sort_flagged <- x[["sort_flagged"]] %||% FALSE
  checkmate::assert_flag(sort_flagged, .var.name = paste0(p, "[[\"sort_flagged\"]]"))
  list(
    text = ctx_str(x[["text"]], paste0(p, "[[\"text\"]]")),
    columns = cols,
    rows = rows,
    anchor = anchor,
    details = details,
    filters = some_cols("filters"),
    flag = flag,
    refs = some_cols("refs"),
    sort_flagged = sort_flagged
  )
}

# a table cell: text, a list of texts, text with a link, or text with a status
ctx_check_cell <- function(v, p) {
  if (is.null(v)) {
    return(list(text = character(0)))
  }
  if (is.list(v) && !is.null(names(v))) {
    v <- ctx_obj(v, p, c("text", "href", "status"), "text", null.ok = FALSE)
    return(list(
      text = ctx_str(v[["text"]], paste0(p, "[[\"text\"]]"), null.ok = FALSE),
      href = ctx_href(v[["href"]], paste0(p, "[[\"href\"]]")),
      status = ctx_str(v[["status"]], paste0(p, "[[\"status\"]]"), choices = QC_CTX_STATUS)
    ))
  }
  if (is.list(v) && !length(v)) {
    return(list(text = character(0)))
  }
  list(text = ctx_chr(v, p, min.len = 0L, null.ok = FALSE))
}

# --- small builders -------------------------------------------------------------

ctx_on <- function(st) !is.null(st[["ctx"]])

ctx_slug <- function(x) gsub("[^A-Za-z0-9_-]+", "-", x)

ctx_ref_anchor <- function(id) paste0("ref-", ctx_slug(id))

ctx_var_anchor <- function(v) paste0("var-", ctx_slug(v))

# an id a note cites. a link when some table in the page holds that id,
# plain code otherwise, so no link in the page points at nothing.
ctx_refs_html <- function(st, ids) {
  if (!length(ids)) {
    return("")
  }
  known <- st[["ctx_anchors"]] %||% character(0)
  one <- vapply(ids, function(id) {
    code <- tag("code", html_escape(id))
    if (id %in% known) {
      paste0("<a class=\"ctx-ref\" href=\"#", ctx_ref_anchor(id), "\">", code, "</a>")
    } else {
      tag("span", code, attrs = c(class = "ctx-ref"))
    }
  }, character(1L))
  paste0(" <span class=\"ctx-refs\">", paste(one, collapse = " "), "</span>")
}

ctx_kind_label <- function(st, kind) {
  src <- st[["ctx"]][["source"]]
  if (kind == "account") {
    tag("span", "Account", attrs = c(class = "ctx-kind", title = if (is.null(src)) "A written account" else paste("Written by", src)))
  } else {
    tag("span", "Recorded", attrs = c(class = "ctx-kind", title = if (is.null(src)) "Taken from a record" else paste("Taken from the records of", src)))
  }
}

# one note, text block or list item
ctx_note_html <- function(st, n, wrap = "div") {
  cls <- paste("ctx-note", paste0("ctx-", n[["kind"]]))
  paste0(
    "<", wrap, " class=\"", cls, "\">",
    ctx_kind_label(st, n[["kind"]]),
    if (!is.null(n[["badge"]])) paste0(" ", chip(n[["badge"]][["text"]], n[["badge"]][["status"]])),
    if (!is.null(n[["text"]])) paste0(" ", html_escape(n[["text"]])),
    if (!is.null(n[["href"]])) paste0(" <a href=\"", html_escape(n[["href"]]), "\">", html_escape(ctx_link_text(n[["href"]])), "</a>"),
    ctx_refs_html(st, n[["ref"]]),
    if (!is.null(n[["fields"]])) {
      html_table(
        data.frame(field = names(n[["fields"]]), value = unname(n[["fields"]]), stringsAsFactors = FALSE),
        c("Field", "Value"),
        class = "qc-table ctx-fields"
      )
    },
    if (!is.null(n[["details"]])) {
      paste0("<details><summary>Full text</summary><pre class=\"ctx-details\">", html_escape(n[["details"]]), "</pre></details>")
    },
    "</", wrap, ">"
  )
}

# the text of a link: the file name of a path, or "Open" for an anchor
ctx_link_text <- function(href) {
  if (startsWith(href, "#")) "Open" else basename(sub("[?#].*$", "", href))
}

ctx_notes_on <- function(st, on, key = NULL) {
  notes <- st[["ctx"]][["notes"]]
  keep <- vapply(notes, function(n) n[["on"]] == on && (is.null(key) || n[["key"]] %in% key), logical(1L))
  notes[keep]
}

# --- flags the report raises on a variable --------------------------------------

# a pheno column the report itself flagged, and why. kept whether or not a
# context is given, and read only by a context table with a flag column.
ctx_flag <- function(st, variable, why) {
  if (!length(variable)) {
    return(invisible())
  }
  fl <- st[["flagged"]] %||% list()
  for (v in variable) {
    fl[[v]] <- unique(c(fl[[v]], why))
  }
  st[["flagged"]] <- fl
  invisible()
}

# " See the notes on Female." when the context has notes on that variable
ctx_see <- function(st, variable) {
  if (!ctx_on(st) || !length(ctx_notes_on(st, "variable", variable))) {
    return("")
  }
  sprintf(" <a href=\"#%s\">See the notes on %s.</a>", ctx_var_anchor(variable), html_escape(variable))
}

# --- pheno section hooks ----------------------------------------------------------

# the stated reason for each variable's missing values, or NULL
ctx_missing_reasons <- function(st, variables) {
  if (!ctx_on(st)) {
    return(NULL)
  }
  notes <- ctx_notes_on(st, "variable", variables)
  notes <- notes[vapply(notes, function(n) identical(n[["topic"]], "missing"), logical(1L))]
  if (!length(notes)) {
    return(NULL)
  }
  vapply(variables, function(v) {
    mine <- notes[vapply(notes, `[[`, character(1L), "key") == v]
    paste(vapply(mine, function(n) paste0(html_escape(n[["text"]] %||% ""), ctx_refs_html(st, n[["ref"]])), character(1L)), collapse = "<br>")
  }, character(1L), USE.NAMES = FALSE)
}

# "Notes on variables": one row per variable with a note, in the order the
# context gives them. `ps` is qc_pheno_stats() or NULL.
ctx_variables_html <- function(st, ps) {
  if (!ctx_on(st)) {
    return("")
  }
  notes <- ctx_notes_on(st, "variable")
  if (!length(notes)) {
    return("")
  }
  keys <- unique(vapply(notes, `[[`, character(1L), "key"))
  rows <- vapply(keys, function(v) {
    i <- if (is.null(ps)) NA_integer_ else match(v, ps[["variable"]])
    about <- if (is.na(i)) {
      tag("span", "Not in pheno", attrs = c(class = "note"))
    } else {
      sprintf("%s, %s missing", html_escape(ps[["type"]][[i]]), fmt_pct(ps[["pct_missing"]][[i]]))
    }
    mine <- notes[vapply(notes, `[[`, character(1L), "key") == v]
    body <- paste(vapply(mine, function(n) {
      if (identical(n[["topic"]], "missing")) {
        n[["text"]] <- paste("Missing values:", n[["text"]] %||% "")
      }
      ctx_note_html(st, n)
    }, character(1L)), collapse = "")
    paste0(
      "<tr id=\"", ctx_var_anchor(v), "\"><td><strong>", html_escape(v), "</strong><br><span class=\"note\">",
      about, "</span></td><td>", body, "</td></tr>"
    )
  }, character(1L))
  paste0(
    sub_head("pheno-context", "Notes on variables"),
    tag("p", "How each variable was made, from the supplied context. A variable that pheno does not hold is marked."),
    "<div class=\"table-wrap\"><table class=\"qc-table ctx-table\"><thead><tr><th>Variable</th><th>Notes</th></tr></thead><tbody>",
    paste(rows, collapse = ""), "</tbody></table></div>"
  )
}

# "Notes on samples", under the sample id table
ctx_samples_html <- function(st) {
  if (!ctx_on(st)) {
    return("")
  }
  notes <- ctx_notes_on(st, "sample")
  if (!length(notes)) {
    return("")
  }
  rows <- vapply(notes, function(n) {
    paste0("<tr><td>", html_escape(n[["key"]]), "</td><td>", ctx_note_html(st, n), "</td></tr>")
  }, character(1L))
  tab <- paste0(
    "<div class=\"table-wrap\"><table class=\"qc-table ctx-table\"><thead><tr><th>Sample</th><th>Note</th></tr></thead><tbody>",
    paste(rows, collapse = ""), "</tbody></table></div>"
  )
  k <- length(unique(vapply(notes, `[[`, character(1L), "key")))
  paste0(
    tag("h4", "Notes on samples"),
    if (length(notes) > QC_CTX_OPEN_ROWS) {
      paste0("<details><summary>", length(notes), " notes on ", fmt_int(k), " sample", if (k == 1L) "" else "s", "</summary>", tab, "</details>")
    } else {
      tab
    }
  )
}

# the note text for each sample id, or NULL when no id has one. for the sex
# mismatch and flagged sample tables.
ctx_sample_col <- function(st, ids) {
  if (!ctx_on(st)) {
    return(NULL)
  }
  notes <- ctx_notes_on(st, "sample", ids)
  if (!length(notes)) {
    return(NULL)
  }
  keys <- vapply(notes, `[[`, character(1L), "key")
  txt <- vapply(notes, function(n) n[["text"]] %||% "", character(1L))
  vapply(as.character(ids), function(id) paste(txt[keys == id], collapse = " "), character(1L), USE.NAMES = FALSE)
}

# --- sample groups -----------------------------------------------------------------

# the first two scored samples of each group, compared clock by clock
qc_group_agreement <- function(m, groups) {
  pairs <- lapply(groups, function(g) {
    g <- g[g %in% rownames(m)]
    if (length(g) >= 2L) g[1:2]
  })
  pairs <- pairs[!vapply(pairs, is.null, logical(1L))]
  k <- length(pairs)
  if (!k) {
    return(list(k = 0L))
  }
  a <- m[vapply(pairs, `[[`, character(1L), 1L), , drop = FALSE]
  b <- m[vapply(pairs, `[[`, character(1L), 2L), , drop = FALSE]
  d <- a - b
  both <- is.finite(a) & is.finite(b)
  per_clock <- data.frame(
    clock_id = colnames(m),
    n = colSums(both),
    r = vapply(seq_len(ncol(m)), function(j) {
      ok <- both[, j]
      if (sum(ok) < QC_GROUP_MIN || stats::sd(a[ok, j]) == 0 || stats::sd(b[ok, j]) == 0) {
        return(NA_real_)
      }
      stats::cor(a[ok, j], b[ok, j])
    }, numeric(1L)),
    med_diff = vapply(seq_len(ncol(m)), function(j) {
      if (any(both[, j])) stats::median(abs(d[both[, j], j])) else NA_real_
    }, numeric(1L)),
    stringsAsFactors = FALSE
  )
  # a group differs on a clock when its difference sits more than QC_OUTLIER_Z
  # robust standard deviations from the typical difference for that clock
  far <- matrix(NA, k, ncol(m))
  for (j in seq_len(ncol(m))) {
    ok <- both[, j]
    if (sum(ok) < QC_GROUP_MIN) {
      next
    }
    s <- stats::mad(d[ok, j])
    if (!is.finite(s) || s == 0) {
      next
    }
    far[ok, j] <- abs(d[ok, j] - stats::median(d[ok, j])) > QC_OUTLIER_Z * s
  }
  n_judged <- rowSums(!is.na(far))
  n_far <- rowSums(far, na.rm = TRUE)
  per_group <- data.frame(
    group = names(pairs),
    samples = vapply(pairs, paste, character(1L), collapse = ", "),
    n_far = n_far,
    n_judged = n_judged,
    stringsAsFactors = FALSE
  )
  per_group[["flag"]] <- per_group[["n_judged"]] > 0 & per_group[["n_far"]] > per_group[["n_judged"]] / 2
  list(k = k, per_clock = per_clock, per_group = per_group)
}

# the sub-head under Clock results, or NULL when the context has no groups
ctx_groups_section <- function(st, m) {
  if (!ctx_on(st) || is.null(st[["ctx"]][["sample_groups"]])) {
    return(NULL)
  }
  g <- st[["ctx"]][["sample_groups"]]
  label <- g[["label"]]
  refs <- ctx_refs_html(st, g[["ref"]])
  intro <- tag("p", paste0(
    sprintf("The supplied context names %s groups of samples that should score alike: %s. ",
            fmt_int(length(g[["groups"]])), html_escape(label)),
    "The first two scored samples of each group are compared on every clock.",
    if (!is.null(g[["text"]])) paste0(" ", html_escape(g[["text"]])),
    refs
  ))
  ag <- qc_try(st, "x", qc_group_agreement(m, g[["groups"]]))
  head <- sub_head("clocks-groups", "Agreement within sample groups")
  if (is_qc_error(ag)) {
    return(list(html = paste0(head, intro, qc_failed(ag)), findings = character(0)))
  }
  if (ag[["k"]] < QC_GROUP_MIN) {
    why <- sprintf(
      "Only %d of the %s have two scored samples. The agreement check needs %d.",
      ag[["k"]], label, QC_GROUP_MIN
    )
    return(list(
      html = paste0(head, intro, not_computable(why)),
      findings = finding("na", paste0(html_escape(why), refs))
    ))
  }
  pc <- ag[["per_clock"]]
  low <- !is.na(pc[["r"]]) & pc[["r"]] < QC_GROUP_MIN_R
  status <- ifelse(is.na(pc[["r"]]), "na", ifelse(low, "warn", "ok"))
  word <- ifelse(is.na(pc[["r"]]), "not computed", ifelse(low, "low", "agrees"))
  o <- order(is.na(pc[["r"]]), pc[["r"]], pc[["clock_id"]])
  shown <- data.frame(
    clock_id = pc[["clock_id"]],
    n = pc[["n"]],
    r = pc[["r"]],
    med_diff = pc[["med_diff"]],
    status = vapply(seq_along(word), function(i) chip(word[[i]], status[[i]]), character(1L)),
    stringsAsFactors = FALSE
  )[o, , drop = FALSE]
  quiet <- status[o] == "ok"
  labels <- c("Clock", "Groups", "Correlation", "Median absolute difference", "Status")
  loud <- shown[!quiet, , drop = FALSE]
  rest <- shown[quiet, , drop = FALSE]
  pg <- ag[["per_group"]]
  bad_g <- pg[pg[["flag"]], , drop = FALSE]
  findings <- character(0)
  if (any(low)) {
    ids <- pc[["clock_id"]][low][order(pc[["r"]][low])]
    findings <- c(findings, finding("warn", sprintf(
      "%d of %d clocks correlate below %s between the two samples of each group in the %s: %s.%s",
      sum(low), sum(!is.na(pc[["r"]])), QC_GROUP_MIN_R, html_escape(label),
      html_escape(paste(utils::head(ids, 12L), collapse = ", ")), refs
    )))
  }
  if (nrow(bad_g)) {
    findings <- c(findings, finding("warn", sprintf(
      "%d of the %s differ on most clocks: %s. A sample mix-up is one possible cause.%s",
      nrow(bad_g), html_escape(label), html_escape(paste(utils::head(bad_g[["group"]], 12L), collapse = ", ")), refs
    )))
  }
  if (!length(findings)) {
    findings <- finding("ok", sprintf("Clock scores agree within the %d %s.%s", ag[["k"]], html_escape(label), refs))
  }
  html <- paste0(
    head, intro,
    tag("p", sprintf(
      "%d groups compared. A correlation below %s is marked low. A group is flagged when its two samples differ by more than %d robust standard deviations on more than half of the clocks.",
      ag[["k"]], QC_GROUP_MIN_R, QC_OUTLIER_Z
    )),
    if (nrow(bad_g)) {
      paste0(tag("h4", "Groups that differ on most clocks"), html_table(
        bad_g[c("group", "samples", "n_far", "n_judged")],
        c("Group", "Samples", "Clocks that differ", "Clocks compared")
      ))
    },
    if (nrow(loud)) html_table(loud, labels, html = "status") else p_note("Every clock with a correlation agrees."),
    if (nrow(rest)) {
      paste0("<details><summary>", nrow(rest), " clocks that agree</summary>",
             html_table(rest, labels, html = "status"), "</details>")
    }
  )
  list(html = html, findings = findings)
}

# --- overview -------------------------------------------------------------------------

ctx_findings_html <- function(st) {
  if (!ctx_on(st)) {
    return(character(0))
  }
  ctx <- st[["ctx"]]
  src <- if (is.null(ctx[["source"]])) "" else paste0(" <span class=\"ctx-src\">", html_escape(ctx[["source"]]), "</span>")
  own <- vapply(ctx[["findings"]], function(f) {
    finding(f[["status"]], paste0(html_escape(f[["text"]]), ctx_refs_html(st, f[["ref"]]), src))
  }, character(1L))
  cmp <- ctx[["comparisons"]]
  cmp <- cmp[vapply(cmp, function(cc) cc[["status"]] %in% c("warn", "bad"), logical(1L))]
  differ <- vapply(cmp, function(cc) {
    finding(cc[["status"]], paste0(
      html_escape(sprintf(
        "%s: the stated value is %s%s, the measured value is %s%s.",
        cc[["label"]], cc[["stated"]], if (is.null(cc[["stated_from"]])) "" else paste0(" (", cc[["stated_from"]], ")"),
        cc[["measured"]], if (is.null(cc[["measured_from"]])) "" else paste0(" (", cc[["measured_from"]], ")")
      )),
      if (!is.null(cc[["note"]])) paste0(" ", html_escape(cc[["note"]])),
      ctx_refs_html(st, cc[["ref"]]), src
    ))
  }, character(1L))
  c(own, differ)
}

ctx_overview_html <- function(st) {
  if (!ctx_on(st)) {
    return("")
  }
  ctx <- st[["ctx"]]
  who <- if (is.null(ctx[["source"]])) "the supplied context" else html_escape(ctx[["source"]])
  legend <- p_note(paste0(
    "This report includes a context from ", who, ". Notes marked ",
    "<span class=\"ctx-kind\">Recorded</span> are taken from its records. Notes marked ",
    "<span class=\"ctx-kind ctx-kind-account\">Account</span> are a summary that it wrote, and each one cites the records it rests on."
  ))
  cmp <- ctx[["comparisons"]]
  cmp_html <- if (length(cmp)) {
    word <- c(ok = "agree", warn = "differ", bad = "differ", na = "not measured", info = "note")
    df <- data.frame(
      label = vapply(cmp, `[[`, character(1L), "label"),
      stated = vapply(cmp, function(cc) paste0(
        html_escape(cc[["stated"]]),
        if (!is.null(cc[["stated_from"]])) paste0("<br><span class=\"note\">", html_escape(cc[["stated_from"]]), "</span>")
      ), character(1L)),
      measured = vapply(cmp, function(cc) paste0(
        html_escape(cc[["measured"]]),
        if (!is.null(cc[["measured_from"]])) paste0("<br><span class=\"note\">", html_escape(cc[["measured_from"]]), "</span>")
      ), character(1L)),
      status = vapply(cmp, function(cc) paste0(
        chip(word[[cc[["status"]]]], cc[["status"]]),
        if (!is.null(cc[["note"]])) paste0("<br><span class=\"note\">", html_escape(cc[["note"]]), "</span>")
      ), character(1L)),
      ref = vapply(cmp, function(cc) ctx_refs_html(st, cc[["ref"]]), character(1L)),
      stringsAsFactors = FALSE
    )
    paste0(
      tag("h3", "Stated and measured", attrs = c(id = "overview-compare")),
      tag("p", paste0("Each value that ", who, " states, beside the value measured from the data.")),
      html_table(df, c("Quantity", "Stated", "Measured", "Status", "Record"), html = c("stated", "measured", "status", "ref"))
    )
  } else {
    ""
  }
  own <- ctx_notes_on(st, "section", "overview")
  lost <- st[["ctx_unplaced"]] %||% list()
  paste0(
    legend,
    paste(vapply(own, function(n) ctx_note_html(st, n), character(1L)), collapse = ""),
    cmp_html,
    if (length(lost)) {
      paste0(
        tag("h4", "Notes on parts of the page that are not shown"),
        paste(vapply(lost, function(n) {
          ctx_note_html(st, utils::modifyList(n, list(text = paste0("[", n[["key"]], "] ", n[["text"]] %||% ""))))
        }, character(1L)), collapse = "")
      )
    }
  )
}

ctx_cards_html <- function(st) {
  cd <- st[["ctx"]][["cards"]]
  if (!ctx_on(st) || is.null(cd) || !length(cd[["items"]])) {
    return("")
  }
  paste0(
    "<div class=\"card-group ctx-cards\"><h3>", html_escape(cd[["heading"]] %||% "From the supplied context"), "</h3><div class=\"cards\">",
    paste(vapply(cd[["items"]], function(c1) stat_card(c1[["label"]], c1[["value"]], c1[["status"]], c1[["detail"]]), character(1L)), collapse = ""),
    "</div></div>"
  )
}

# --- section notes ---------------------------------------------------------------------

# notes on a section go under its heading, notes on a sub-head go under that
# sub-head. a note whose key is nowhere in the page goes to the overview.
ctx_place_notes <- function(st, sections) {
  if (!ctx_on(st)) {
    return(sections)
  }
  notes <- ctx_notes_on(st, "section")
  notes <- notes[vapply(notes, `[[`, character(1L), "key") != "overview"]
  placed <- rep(FALSE, length(notes))
  for (s in seq_along(sections)) {
    body <- sections[[s]][["body"]]
    for (i in seq_along(notes)) {
      key <- notes[[i]][["key"]]
      html <- ctx_note_html(st, notes[[i]])
      if (key == sections[[s]][["id"]]) {
        body <- paste0(html, body)
        placed[[i]] <- TRUE
        next
      }
      at <- regexpr(paste0("<h3 id=\"", key, "\">"), body, fixed = TRUE)
      if (at > 0) {
        end <- regexpr("</h3>", substring(body, at), fixed = TRUE)
        cut <- at + end + attr(end, "match.length") - 1L
        body <- paste0(substring(body, 1L, cut - 1L), html, substring(body, cut))
        placed[[i]] <- TRUE
      }
    }
    sections[[s]][["body"]] <- body
  }
  st[["ctx_unplaced"]] <- notes[!placed]
  sections
}

# --- extra sections --------------------------------------------------------------------

# the ids that tables in the extra sections anchor, so refs can link to them
ctx_collect_anchors <- function(ctx) {
  ids <- unlist(lapply(ctx[["sections"]], function(s) {
    lapply(s[["blocks"]], function(b) {
      if (b[["type"]] == "table" && !is.null(b[["anchor"]])) {
        vapply(b[["rows"]], function(r) paste(r[[b[["anchor"]]]][["text"]], collapse = " "), character(1L))
      }
    })
  }), use.names = FALSE)
  unique(ids[nzchar(ids)])
}

ctx_sections <- function(st) {
  if (!ctx_on(st)) {
    return(list())
  }
  lapply(st[["ctx"]][["sections"]], function(s) {
    body <- paste(vapply(seq_along(s[["blocks"]]), function(i) {
      ctx_block_html(st, s[["blocks"]][[i]], paste0(s[["id"]], "-", i))
    }, character(1L)), collapse = "")
    qc_section(s[["id"]], s[["heading"]], body)
  })
}

ctx_block_html <- function(st, b, auto_id) {
  head <- if (!is.null(b[["heading"]])) {
    if (is.null(b[["id"]])) tag("h3", html_escape(b[["heading"]])) else sub_head(b[["id"]], b[["heading"]])
  } else {
    ""
  }
  body <- switch(
    b[["type"]],
    text = ctx_note_html(st, b),
    list = paste0(
      "<ul class=\"ctx-list\">",
      paste(vapply(b[["items"]], function(n) ctx_note_html(st, n, wrap = "li"), character(1L)), collapse = ""),
      "</ul>"
    ),
    table = ctx_table_html(st, b, b[["id"]] %||% auto_id)
  )
  paste0(head, body)
}

ctx_cell_html <- function(st, cell, is_ref) {
  txt <- cell[["text"]]
  if (!length(txt)) {
    return("")
  }
  if (is_ref) {
    return(ctx_refs_html(st, txt))
  }
  if (!is.null(cell[["status"]])) {
    return(chip(txt, cell[["status"]]))
  }
  out <- html_escape(paste(txt, collapse = ", "))
  if (!is.null(cell[["href"]])) {
    out <- paste0("<a href=\"", html_escape(cell[["href"]]), "\">", out, "</a>")
  }
  out
}

ctx_table_html <- function(st, b, tid) {
  cols <- b[["columns"]]
  rows <- b[["rows"]]
  if (!length(rows)) {
    return(paste0(if (!is.null(b[["text"]])) tag("p", html_escape(b[["text"]])), p_note("No rows.")))
  }
  flagged <- st[["flagged"]] %||% list()
  flag_of <- function(r) {
    if (is.null(b[["flag"]])) {
      return(character(0))
    }
    unlist(flagged[intersect(r[[b[["flag"]]]][["text"]], names(flagged))], use.names = FALSE)
  }
  if (!is.null(b[["flag"]]) && isTRUE(b[["sort_flagged"]])) {
    rows <- rows[order(!vapply(rows, function(r) length(flag_of(r)) > 0, logical(1L)))]
  }
  wrap_id <- paste0("tbl-", tid)
  filt <- b[["filters"]] %||% character(0)
  filter_html <- ""
  css <- character(0)
  if (length(filt)) {
    groups <- lapply(seq_along(filt), function(f) {
      nm <- paste0(wrap_id, "-f", f)
      vals <- sort(unique(unlist(lapply(rows, function(r) r[[filt[[f]]]][["text"]]))))
      vals <- vals[nzchar(vals)]
      list(
        css = sprintf(
          "#%s:has(input[name=\"%s\"][value=\"%s\"]:checked) tbody tr:not([data-f%d~=\"%s\"]){display:none}",
          wrap_id, nm, ctx_slug(vals), f, ctx_slug(vals)
        ),
        html = paste0(
          "<fieldset class=\"ctx-filter\"><legend>", html_escape(cols[[filt[[f]]]]), "</legend>",
          "<label><input type=\"radio\" name=\"", nm, "\" value=\"\" checked> All</label>",
          paste0("<label><input type=\"radio\" name=\"", nm, "\" value=\"", ctx_slug(vals), "\"> ", html_escape(vals), "</label>", collapse = ""),
          "</fieldset>"
        )
      )
    })
    css <- unlist(lapply(groups, `[[`, "css"))
    filter_html <- paste0("<div class=\"ctx-filters\">", paste(vapply(groups, `[[`, character(1L), "html"), collapse = ""), "</div>")
  }
  st[["ctx_css"]] <- c(st[["ctx_css"]], css)
  refs <- b[["refs"]] %||% character(0)
  shown_cols <- setdiff(names(cols), b[["details"]])
  th <- paste0("<th>", html_escape(unname(cols[shown_cols])), "</th>", collapse = "")
  if (!is.null(b[["flag"]])) {
    th <- paste0(th, "<th>Flagged by this report</th>")
  }
  if (!is.null(b[["details"]])) {
    th <- paste0(th, "<th>", html_escape(cols[[b[["details"]]]]), "</th>")
  }
  body <- vapply(rows, function(r) {
    attrs <- ""
    if (!is.null(b[["anchor"]]) && length(r[[b[["anchor"]]]][["text"]])) {
      attrs <- paste0(attrs, " id=\"", ctx_ref_anchor(paste(r[[b[["anchor"]]]][["text"]], collapse = " ")), "\"")
    }
    for (f in seq_along(filt)) {
      attrs <- paste0(attrs, " data-f", f, "=\"", paste(ctx_slug(r[[filt[[f]]]][["text"]]), collapse = " "), "\"")
    }
    cells <- vapply(shown_cols, function(nm) ctx_cell_html(st, r[[nm]], nm %in% refs), character(1L))
    fl <- if (!is.null(b[["flag"]])) {
      why <- flag_of(r)
      paste0("<td>", if (length(why)) paste0(chip("flagged", "warn"), "<br><span class=\"note\">", html_escape(paste(why, collapse = ". ")), "</span>") else "", "</td>")
    } else {
      ""
    }
    det <- if (!is.null(b[["details"]])) {
      txt <- paste(r[[b[["details"]]]][["text"]], collapse = "\n")
      paste0("<td>", if (nzchar(txt)) paste0("<details><summary>Show</summary><pre class=\"ctx-details\">", html_escape(txt), "</pre></details>") else "", "</td>")
    } else {
      ""
    }
    paste0("<tr", attrs, ">", paste0("<td>", cells, "</td>", collapse = ""), fl, det, "</tr>")
  }, character(1L))
  paste0(
    if (!is.null(b[["text"]])) tag("p", html_escape(b[["text"]])),
    "<div class=\"ctx-filterable\" id=\"", wrap_id, "\">", filter_html,
    "<div class=\"table-wrap\"><table class=\"qc-table ctx-table\"><thead><tr>", th, "</tr></thead><tbody>",
    paste(body, collapse = ""), "</tbody></table></div></div>"
  )
}

# --- css -------------------------------------------------------------------------------

# added to the page only when a context is given
QC_CONTEXT_CSS <- "
.ctx-note{margin:6px 0;padding:6px 10px;border-left:3px solid var(--axis);background:var(--page);border-radius:0 6px 6px 0}
.ctx-account{border-left:3px dashed var(--s7);background:var(--info-bg);font-style:italic}
.ctx-account .ctx-kind,.ctx-kind-account{border-color:var(--s7);color:var(--s7);font-style:normal}
.ctx-kind{display:inline-block;font-size:.72rem;font-weight:600;text-transform:uppercase;letter-spacing:.04em;color:var(--ink-2);border:1px solid var(--axis);border-radius:4px;padding:0 5px;margin-right:4px;vertical-align:1px}
.ctx-refs code,.ctx-ref code{font-size:.78rem;background:var(--na-bg);border-radius:4px;padding:0 4px;font-style:normal}
.ctx-src{font-size:.76rem;color:var(--ink-3);margin-left:4px}
.ctx-details{white-space:pre-wrap;font-size:.8rem;background:var(--surface);border-radius:6px;padding:8px;margin:0;max-height:360px;overflow:auto;font-style:normal}
.ctx-fields{margin:4px 0}
.ctx-list{list-style:none;padding:0}
.ctx-table td{max-width:60ch}
.ctx-table tr:target{background:var(--warn-bg)}
.ctx-filters{display:flex;flex-wrap:wrap;gap:8px 18px;margin:8px 0}
.ctx-filter{border:1px solid var(--ring);border-radius:8px;padding:4px 10px;margin:0;font-size:.84rem;color:var(--ink-2)}
.ctx-filter label{margin-right:10px;white-space:nowrap;cursor:pointer}
"
