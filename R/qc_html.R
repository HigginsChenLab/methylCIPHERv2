# html and inline-svg builders for qc_report(). no dependency beyond base R:
# every chart is an <svg> string, coloured through css custom properties so the
# page follows the reader's light or dark theme.

# --- text ------------------------------------------------------------------

html_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

# a number for a table cell. NA prints as NA, which is what an R user reads.
fmt_num <- function(x, digits = 3L) {
  # very small or very large magnitudes read better in scientific notation
  sci <- !is.na(x) & x != 0 & (abs(x) < 1e-3 | abs(x) >= 1e7)
  out <- ifelse(
    is.na(x),
    "NA",
    ifelse(
      sci,
      formatC(x, format = "g", digits = digits),
      formatC(signif(x, digits), format = "fg", digits = digits, big.mark = ",")
    )
  )
  trimws(out)
}

fmt_int <- function(x) {
  ifelse(is.na(x), "NA", formatC(x, format = "d", big.mark = ","))
}

fmt_pct <- function(x, digits = 1L) {
  ifelse(is.na(x), "NA", paste0(formatC(100 * x, format = "f", digits = digits), "%"))
}

tag <- function(name, ..., attrs = NULL) {
  a <- if (length(attrs)) {
    paste0(" ", paste0(names(attrs), "=\"", html_escape(attrs), "\""), collapse = "")
  } else {
    ""
  }
  paste0("<", name, a, ">", paste0(..., collapse = ""), "</", name, ">")
}

p_note <- function(text) tag("p", text, attrs = c(class = "note"))

# the one shape a section takes when its input was not supplied or it failed.
not_computable <- function(why) {
  tag(
    "div",
    tag("strong", "Not computable. "),
    html_escape(why),
    attrs = c(class = "na-box")
  )
}

# a status chip. the word carries the meaning, so colour is never alone.
chip <- function(text, status = c("ok", "warn", "bad", "na", "info")) {
  status <- status[[1L]]
  icon <- switch(
    status,
    ok = "&#10003;",
    warn = "!",
    bad = "&#10005;",
    na = "&#8211;",
    info = "i"
  )
  tag(
    "span",
    tag("span", icon, attrs = c(class = "chip-icon", "aria-hidden" = "true")),
    html_escape(text),
    attrs = c(class = paste("chip", status))
  )
}

# --- tables ----------------------------------------------------------------

# df -> <table>. `html` names the columns whose cells are already markup, every
# other cell is escaped. numeric columns are right aligned.
html_table <- function(df, labels = names(df), html = character(0), cap = NULL,
                       class = "qc-table") {
  if (!nrow(df)) {
    return(p_note("No rows."))
  }
  n_all <- nrow(df)
  if (!is.null(cap) && n_all > cap) {
    df <- df[seq_len(cap), , drop = FALSE]
  }
  num <- vapply(df, is.numeric, logical(1L))
  th <- paste0(
    "<th", ifelse(num, " class=\"num\"", ""), ">", html_escape(labels), "</th>",
    collapse = ""
  )
  cells <- lapply(names(df), function(nm) {
    v <- df[[nm]]
    if (nm %in% html) {
      return(as.character(v))
    }
    if (is.numeric(v)) {
      if (is.integer(v) || all(is.na(v) | v == round(v))) fmt_int(v) else fmt_num(v)
    } else if (is.logical(v)) {
      ifelse(is.na(v), "NA", ifelse(v, "yes", "no"))
    } else {
      html_escape(ifelse(is.na(v), "NA", as.character(v)))
    }
  })
  td_open <- ifelse(num, "<td class=\"num\">", "<td>")
  rows <- vapply(
    seq_len(nrow(df)),
    function(i) {
      paste0(
        "<tr>",
        paste0(td_open, vapply(cells, `[[`, character(1L), i), "</td>", collapse = ""),
        "</tr>"
      )
    },
    character(1L)
  )
  more <- if (nrow(df) < n_all) {
    p_note(sprintf("Showing %d of %s rows.", nrow(df), fmt_int(n_all)))
  } else {
    ""
  }
  paste0(
    "<div class=\"table-wrap\"><table class=\"", class, "\"><thead><tr>", th,
    "</tr></thead><tbody>", paste(rows, collapse = ""), "</tbody></table></div>",
    more
  )
}

# an inline bar for a fraction in a table cell. `status` picks the fill.
cell_bar <- function(frac, status = "ok", text = fmt_pct(frac)) {
  w <- ifelse(is.na(frac), 0, pmin(pmax(frac, 0), 1) * 100)
  paste0(
    "<span class=\"bar-cell\"><span class=\"bar\"><span class=\"bar-fill ", status,
    "\" style=\"width:", formatC(w, format = "f", digits = 1L), "%\"></span></span>",
    "<span class=\"bar-val\">", html_escape(text), "</span></span>"
  )
}

# --- overview cards ----------------------------------------------------------

stat_card <- function(label, value, status = "info", detail = NULL) {
  tag(
    "div",
    tag("div", html_escape(label), attrs = c(class = "card-lbl")),
    tag("div", html_escape(value), attrs = c(class = "card-val")),
    if (!is.null(detail)) tag("div", html_escape(detail), attrs = c(class = "card-detail")),
    attrs = c(class = paste("card", status))
  )
}

# --- svg ---------------------------------------------------------------------

# categorical series slots, fixed order (css --s1 .. --s8).
SVG_SERIES <- paste0("var(--s", 1:8, ")")

# a plotting panel: data limits mapped onto a width x height viewBox.
svg_panel <- function(xlim, ylim, width = 640, height = 260,
                      margin = c(top = 14, right = 18, bottom = 46, left = 62)) {
  widen <- function(lim) {
    lim <- as.numeric(lim)
    if (!all(is.finite(lim))) lim <- c(0, 1)
    if (diff(lim) == 0) lim <- lim + c(-0.5, 0.5)
    lim
  }
  xlim <- widen(xlim)
  ylim <- widen(ylim)
  pw <- width - margin[["left"]] - margin[["right"]]
  ph <- height - margin[["top"]] - margin[["bottom"]]
  list(
    xlim = xlim,
    ylim = ylim,
    width = width,
    height = height,
    margin = margin,
    sx = function(v) margin[["left"]] + (v - xlim[[1L]]) / diff(xlim) * pw,
    sy = function(v) margin[["top"]] + ph - (v - ylim[[1L]]) / diff(ylim) * ph,
    left = margin[["left"]],
    right = width - margin[["right"]],
    top = margin[["top"]],
    bottom = height - margin[["bottom"]]
  )
}

f1 <- function(x) formatC(x, format = "f", digits = 1L)

tick_label <- function(v) {
  trimws(formatC(v, format = "fg", digits = 4L, big.mark = ","))
}

# gridlines, ticks and axis titles for a panel
svg_axes <- function(p, xlab = "", ylab = "", xticks = NULL, yticks = NULL,
                     xfmt = tick_label, yfmt = tick_label, xlabels = NULL) {
  xticks <- xticks %||% pretty(p[["xlim"]], n = 6L)
  xticks <- xticks[xticks >= p[["xlim"]][[1L]] & xticks <= p[["xlim"]][[2L]]]
  yticks <- yticks %||% pretty(p[["ylim"]], n = 5L)
  yticks <- yticks[yticks >= p[["ylim"]][[1L]] & yticks <= p[["ylim"]][[2L]]]
  sx <- p[["sx"]]
  sy <- p[["sy"]]
  # paste0() drops a zero-length argument and keeps the literals, so an empty
  # tick set must short-circuit or it emits one malformed element
  each <- function(ticks, ...) if (length(ticks)) paste0(..., collapse = "") else ""
  grid <- each(yticks,
    "<line class=\"grid\" x1=\"", f1(p[["left"]]), "\" x2=\"", f1(p[["right"]]),
    "\" y1=\"", f1(sy(yticks)), "\" y2=\"", f1(sy(yticks)), "\"/>"
  )
  ylab_txt <- each(yticks,
    "<text class=\"tick\" text-anchor=\"end\" x=\"", f1(p[["left"]] - 8),
    "\" y=\"", f1(sy(yticks) + 4), "\">", html_escape(yfmt(yticks)), "</text>"
  )
  xl <- xlabels %||% xfmt(xticks)
  xlab_txt <- each(xticks,
    "<text class=\"tick\" text-anchor=\"middle\" x=\"", f1(sx(xticks)),
    "\" y=\"", f1(p[["bottom"]] + 17), "\">", html_escape(xl), "</text>"
  )
  base <- paste0(
    "<line class=\"axis\" x1=\"", f1(p[["left"]]), "\" x2=\"", f1(p[["right"]]),
    "\" y1=\"", f1(p[["bottom"]]), "\" y2=\"", f1(p[["bottom"]]), "\"/>"
  )
  titles <- paste0(
    "<text class=\"axis-title\" text-anchor=\"middle\" x=\"",
    f1((p[["left"]] + p[["right"]]) / 2), "\" y=\"", f1(p[["height"]] - 6), "\">",
    html_escape(xlab), "</text>",
    "<text class=\"axis-title\" text-anchor=\"middle\" transform=\"translate(14,",
    f1((p[["top"]] + p[["bottom"]]) / 2), ") rotate(-90)\">", html_escape(ylab),
    "</text>"
  )
  paste0(grid, base, ylab_txt, xlab_txt, titles)
}

svg_doc <- function(p, body, label) {
  paste0(
    "<svg class=\"chart\" viewBox=\"0 0 ", p[["width"]], " ", p[["height"]],
    "\" role=\"img\" aria-label=\"", html_escape(label), "\">",
    "<title>", html_escape(label), "</title>", body, "</svg>"
  )
}

# one polyline, broken at NA, as a single path
svg_line <- function(p, x, y, color = SVG_SERIES[[1L]], width = 2,
                     opacity = 1, title = NULL, dash = NULL) {
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 2L) {
    return("")
  }
  px <- f1(p[["sx"]](x))
  py <- f1(p[["sy"]](y))
  cmd <- ifelse(c(TRUE, !ok[-length(ok)]), "M", "L")
  d <- paste0(cmd[ok], px[ok], ",", py[ok], collapse = "")
  paste0(
    "<path d=\"", d, "\" fill=\"none\" stroke=\"", color, "\" stroke-width=\"",
    width, "\" stroke-opacity=\"", opacity, "\" stroke-linejoin=\"round\"",
    if (!is.null(dash)) paste0(" stroke-dasharray=\"", dash, "\""),
    ">", if (!is.null(title)) paste0("<title>", html_escape(title), "</title>"),
    "</path>"
  )
}

# a point carries its own hover title only up to this many points. past it,
# only the points `title_keep` marks keep one: a title is ~80 bytes, and on a
# cohort of thousands the titles were most of the page.
QC_TITLE_MAX <- 300L

# dots with a surface ring and a hover title each. the colour and opacity sit
# on one <g> per colour, and each point carries only its position, so a
# cohort-sized scatter stays small: a circle is ~40 bytes, not ~170.
svg_points <- function(p, x, y, color = SVG_SERIES[[1L]], r = 4, titles = NULL,
                       opacity = 0.85, cls = NULL, title_keep = NULL) {
  ok <- is.finite(x) & is.finite(y)
  if (!any(ok)) {
    return("")
  }
  n <- length(x)
  color <- rep_len(color, n)
  cls_attr <- if (is.null(cls)) rep("", n) else paste0(" class=\"", rep_len(cls, n), "\"")
  if (!is.null(titles) && n > QC_TITLE_MAX) {
    keep <- if (is.null(title_keep)) rep(FALSE, n) else rep_len(title_keep, n)
    titles[!keep] <- NA_character_
  }
  has <- if (is.null(titles)) rep(FALSE, n) else !is.na(titles)
  # a point with no title closes itself, which saves the closing tag
  tail <- rep("/>", n)
  tail[has] <- paste0("><title>", html_escape(titles[has]), "</title></circle>")
  pts <- paste0(
    "<circle", cls_attr, " cx=\"", f1(p[["sx"]](x)), "\" cy=\"", f1(p[["sy"]](y)),
    "\" r=\"", r, "\"", tail
  )
  # one group per colour, in order of first appearance. the draw order within
  # a colour is kept, and callers sort so the colour drawn last is on top.
  lv <- unique(color[ok])
  paste(vapply(lv, function(cl) {
    paste0(
      "<g class=\"pts\" fill=\"", cl, "\" fill-opacity=\"", opacity, "\">",
      paste(pts[ok & color == cl], collapse = ""), "</g>"
    )
  }, character(1L)), collapse = "")
}

# vertical bars from the baseline, one per bin (histogram). 1px gap each side.
svg_bars <- function(p, x0, x1, y, color = SVG_SERIES[[1L]], titles = NULL) {
  keep <- is.finite(y) & y > 0
  if (!any(keep)) {
    return("")
  }
  left <- p[["sx"]](x0[keep]) + 1
  right <- p[["sx"]](x1[keep]) - 1
  w <- pmax(right - left, 0.6)
  top <- p[["sy"]](y[keep])
  h <- pmax(p[["bottom"]] - top, 0)
  tt <- if (is.null(titles)) "" else paste0("<title>", html_escape(titles[keep]), "</title>")
  paste0(
    "<rect class=\"bin\" x=\"", f1(left), "\" y=\"", f1(top), "\" width=\"",
    f1(w), "\" height=\"", f1(h), "\" fill=\"", color, "\">", tt, "</rect>",
    collapse = ""
  )
}

svg_hline <- function(p, y, cls = "ref", label = NULL) {
  if (!is.finite(y) || y < p[["ylim"]][[1L]] || y > p[["ylim"]][[2L]]) {
    return("")
  }
  paste0(
    "<line class=\"", cls, "\" x1=\"", f1(p[["left"]]), "\" x2=\"",
    f1(p[["right"]]), "\" y1=\"", f1(p[["sy"]](y)), "\" y2=\"", f1(p[["sy"]](y)),
    "\"/>",
    if (!is.null(label)) {
      paste0(
        "<text class=\"ref-label\" text-anchor=\"end\" x=\"", f1(p[["right"]]),
        "\" y=\"", f1(p[["sy"]](y) - 5), "\">", html_escape(label), "</text>"
      )
    }
  )
}

# html legend: a swatch and a name per series. identity is never colour alone.
html_legend <- function(labels, colors = SVG_SERIES[seq_along(labels)]) {
  items <- paste0(
    "<span class=\"lg-item\"><span class=\"lg-sw\" style=\"background:", colors,
    "\"></span>", html_escape(labels), "</span>",
    collapse = ""
  )
  tag("div", items, attrs = c(class = "legend"))
}

# a legend of checkboxes: clearing one hides the points of class k-<key> in the
# same figure. css only (:has), so the page needs no script.
toggle_legend <- function(keys, labels, colors) {
  items <- paste0(
    "<label class=\"lg-item lg-toggle\"><input type=\"checkbox\" checked data-k=\"", keys,
    "\"><span class=\"lg-sw\" style=\"background:", colors, "\"></span>",
    html_escape(labels), "</label>",
    collapse = ""
  )
  tag("div", items, attrs = c(class = "legend"))
}

# one hide rule per key, for QC_CSS
toggle_css <- function(keys) {
  paste0(
    "figure:has(input[data-k=\"", keys, "\"]:not(:checked)) .k-", keys, "{display:none}",
    collapse = "\n"
  )
}

figure <- function(svg, caption = NULL, legend = NULL) {
  paste0(
    "<figure>", legend %||% "", svg,
    if (!is.null(caption)) paste0("<figcaption>", caption, "</figcaption>"),
    "</figure>"
  )
}

# --- charts -------------------------------------------------------------------

# a histogram of one numeric vector
chart_hist <- function(v, xlab, ylab = "Samples", bins = 30L, label = xlab,
                       color = SVG_SERIES[[1L]], width = 640, height = 240) {
  v <- v[is.finite(v)]
  if (length(v) < 2L) {
    return(p_note("Too few values to draw."))
  }
  br <- pretty(range(v), n = bins)
  h <- graphics_free_hist(v, br)
  p <- svg_panel(range(br), c(0, max(h[["counts"]]) * 1.05), width, height)
  titles <- sprintf("%s to %s: %d", tick_label(br[-length(br)]), tick_label(br[-1L]), h[["counts"]])
  body <- paste0(
    svg_axes(p, xlab, ylab),
    svg_bars(p, br[-length(br)], br[-1L], h[["counts"]], color, titles)
  )
  svg_doc(p, body, label)
}

# bin counts without graphics::hist() (graphics is not imported)
graphics_free_hist <- function(v, br) {
  idx <- findInterval(v, br, rightmost.closed = TRUE, all.inside = TRUE)
  list(counts = tabulate(idx, nbins = length(br) - 1L))
}

# overlaid kernel densities, one line per group, shared bandwidth
chart_density_groups <- function(v, g, xlab, label, width = 640, height = 220) {
  ok <- is.finite(v) & !is.na(g)
  v <- v[ok]
  g <- droplevels(as.factor(g[ok]))
  lv <- levels(g)
  sizes <- table(g)
  lv <- lv[sizes[lv] >= 2L]
  if (length(lv) < 1L || length(v) < 3L) {
    return(p_note("Too few values in each group to draw."))
  }
  bw <- tryCatch(stats::bw.nrd0(v), error = function(e) NA_real_)
  if (!is.finite(bw) || bw <= 0) {
    return(p_note("The values do not vary, so there is no distribution to draw."))
  }
  rng <- range(v) + c(-2, 2) * bw
  dens <- lapply(lv, function(l) {
    stats::density(v[g == l], bw = bw, from = rng[[1L]], to = rng[[2L]], n = 256L)
  })
  ymax <- max(vapply(dens, function(d) max(d[["y"]]), numeric(1L)))
  p <- svg_panel(rng, c(0, ymax * 1.08), width, height)
  lines <- vapply(
    seq_along(lv),
    function(i) {
      svg_line(
        p, dens[[i]][["x"]], dens[[i]][["y"]], SVG_SERIES[[i]],
        title = sprintf("%s (n = %d)", lv[[i]], sizes[[lv[[i]]]])
      )
    },
    character(1L)
  )
  body <- paste0(svg_axes(p, xlab, "Density", yfmt = function(x) ""), paste(lines, collapse = ""))
  figure(
    svg_doc(p, body, label),
    legend = html_legend(sprintf("%s (n = %d)", lv, as.integer(sizes[lv])))
  )
}

# a scatter with an optional least-squares line. `col` gives one colour per
# point and wins over `flag`. `pt_class` adds a css class per point.
chart_scatter <- function(x, y, xlab, ylab, label, flag = NULL, titles = NULL,
                          width = 320, height = 250, fit = TRUE, col = NULL,
                          pt_class = NULL, title_keep = NULL) {
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 2L) {
    return(p_note("Too few paired values to draw."))
  }
  pad <- function(r) r + c(-0.04, 0.04) * max(diff(r), 1e-8)
  p <- svg_panel(pad(range(x[ok])), pad(range(y[ok])), width, height,
                 margin = c(top = 10, right = 12, bottom = 42, left = 54))
  col <- col %||% if (is.null(flag)) SVG_SERIES[[1L]] else ifelse(flag, "var(--crit)", SVG_SERIES[[1L]])
  line <- ""
  if (fit && sum(ok) >= 3L && stats::sd(x[ok]) > 0) {
    cf <- stats::coef(stats::lm.fit(cbind(1, x[ok]), y[ok]))
    xs <- p[["xlim"]]
    line <- svg_line(p, xs, cf[[1L]] + cf[[2L]] * xs, "var(--ink-2)", width = 1.5,
                     opacity = 0.9, dash = "5 4", title = "Least-squares line")
  }
  body <- paste0(
    svg_axes(p, xlab, ylab),
    svg_points(p, x, y, col, r = 3.5, titles = titles, opacity = 0.75, cls = pt_class,
               title_keep = title_keep),
    line
  )
  svg_doc(p, body, label)
}
