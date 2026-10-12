# fetch_external.R -- ONE-TIME (re-run when a book changes): turn the external
#   books into markdown under external/<book>/, committed to this repo.
#
#   source("fetch_external.R")              # from the SurvAI_Expert folder
#
# Run it at home. The markdown travels with the repo through GitHub, so the
#   build at work (build_store.R) needs neither the clone nor web access to the
#   books: it only embeds.
#
#   tidy-survey          from your local clone of tidy-survey-r/tidy-survey-book
#                        (SVYMETH_TIDY, default D:/repos/tidy-survey-book).
#                        Read from the .Rmd sources: real LaTeX, real code chunks.
#   sampling-techniques  no public source repo, so the rendered chapters are
#                        downloaded from bookdown.org and converted with pandoc
#                        (ships with RStudio). Needs xml2 and rmarkdown.
#
# Each chapter file starts with an HTML comment naming its web page; the
#   app's source links use R/library.R, not that comment.

suppressPackageStartupMessages({ library(purrr); library(stringr); library(tibble) })

EXT_DIR <- "external"

write_chapter <- function(book, page, md, url) {
  dir.create(file.path(EXT_DIR, book), recursive = TRUE, showWarnings = FALSE)
  f <- file.path(EXT_DIR, book, paste0(page, ".md"))
  con <- file(f, open = "w", encoding = "UTF-8")
  writeLines(c(sprintf("<!-- source: %s -->", url), "", md), con)
  close(con)
  f
}

# --- tidy-survey: bookdown .Rmd -> markdown ----------------------------------
# Kept: prose, LaTeX, every code chunk the reader sees (including eval: FALSE).
# Dropped: chunks the book hides (include/echo FALSE: setup, saving output),
#   knitr option lines, \index{} entries, heading attributes, ::: fences.
TIDY_SKIP <- c("91-AppendixB-ANES-CB.Rmd", "92-AppendixC-RECS-CB.Rmd",   # codebook includes only
               "94-AppendixE-Corrections-Remarks.Rmd", "99-references.Rmd")

# Chunk number of every line (0 = prose), from a small state machine.
chunk_ids <- function(lines) {
  st <- accumulate(lines, function(s, x) {
    if (!s$inside && str_detect(x, "^```\\{r")) list(n = s$n + 1L, inside = TRUE,  id = s$n + 1L)
    else if (s$inside && str_detect(x, "^```\\s*$")) list(n = s$n, inside = FALSE, id = s$n)
    else list(n = s$n, inside = s$inside, id = if (s$inside) s$n else 0L)
  }, .init = list(n = 0L, inside = FALSE, id = 0L))[-1]
  map_int(st, "id")
}

rmd_to_md <- function(lines) {
  chunk <- chunk_ids(lines)
  hidden <- map_lgl(split(lines, chunk), function(ch) {
    hd <- paste(ch[str_detect(ch, "^```\\{r|^#\\|")], collapse = " ")
    str_detect(hd, regex("(include|echo)\\s*[:=]\\s*(false|F)\\b", ignore_case = TRUE))
  })
  drop_ids <- setdiff(as.integer(names(hidden)[hidden]), 0L)
  keep <- !(chunk %in% drop_ids) & !(chunk > 0 & str_detect(lines, "^#\\|"))
  lines[keep] |>
    discard(function(x) str_detect(x, "^# \\((PART|APPENDIX)\\)")) |>
    # inline knitr that switches text between HTML and PDF: keep the HTML text
    str_replace_all("`r if \\(!knitr:::is_html_output\\(\\)\\) '[^']*'`", "") |>
    str_replace_all("`r if \\(knitr:::is_html_output\\(\\)\\) '([^']*)'`", "\\1") |>
    str_replace("^```\\{r[^}]*\\}", "```r") |>
    str_replace_all("\\\\index\\{(?:[^{}]|\\{(?:[^{}]|\\{[^{}]*\\})*\\})*\\}", "") |>
    str_replace("^(#+ .*?)\\s*\\{[-#.][^}]*\\}\\s*$", "\\1") |>
    discard(function(x) str_detect(x, "^:::")) |>
    paste(collapse = "\n") |>
    str_replace_all("(?s)<!--.*?-->", "") |>
    str_replace_all("\n{3,}", "\n\n")
}

fetch_tidy_survey <- function(src = Sys.getenv("SVYMETH_TIDY", "D:/repos/tidy-survey-book")) {
  stopifnot("Set SVYMETH_TIDY to your clone of tidy-survey-book" = dir.exists(src))
  yml <- readLines(file.path(src, "_bookdown.yml"), warn = FALSE)
  files <- str_extract_all(str_subset(yml, "^\\s*html:")[1], "[\\w.-]+\\.Rmd")[[1]]
  files <- setdiff(files, TIDY_SKIP)
  url <- SVY_LIBRARY_URLS[["tidy-survey"]]
  map_chr(files, function(f) {
    lines <- readLines(file.path(src, f), warn = FALSE, encoding = "UTF-8")
    # bookdown names each chapter page after the first heading's {#id}
    id <- str_match(str_subset(lines, "^# .*\\{#")[1], "\\{#([^ }]+)")[, 2]
    page <- if (f == "index.Rmd") "index" else id %|% tools::file_path_sans_ext(f)
    write_chapter("tidy-survey", page, rmd_to_md(lines), sub("{page}", paste0(page, ".html"), url, fixed = TRUE))
  })
}
`%|%` <- function(a, b) if (length(a) && !is.na(a)) a else b

# --- sampling-techniques: rendered Quarto pages -> markdown ------------------
SAMPLING_PAGES <- c("index", "Preface", "01-Principles-of-Sampling",
  "02-Probability-and-Distributions", "03-Sampling-Methods", "04-Margin-of-Error",
  "05-Questionnaire-Design", "06-Digital-Data-Collection", "07-Data-Validation",
  "08-Seven-Tools-Analysis", "09-GForm_into_R", "10-Case-Study-in-Surveys")

# Math is swapped for tokens before pandoc and put back after, as $...$ /
#   $$...$$: pandoc's HTML reader otherwise escapes the \( \) delimiters.
html_to_md <- function(html_file) {
  doc <- xml2::read_html(html_file)
  main <- xml2::xml_find_first(doc, "//main[@id='quarto-document-content'] | //main | //div[contains(@class,'book-body')]")
  if (inherits(main, "xml_missing")) main <- xml2::xml_find_first(doc, "//body")
  xml2::xml_remove(xml2::xml_find_all(main, paste(
    ".//nav", ".//script", ".//style", ".//button", ".//img",
    ".//*[contains(@class,'quarto-title-meta')]", ".//*[contains(@class,'page-navigation')]",
    sep = " | ")))
  math <- xml2::xml_find_all(main, ".//span[contains(@class,'math')]")
  tex  <- xml2::xml_text(math) |> str_remove("^\\\\[(\\[]") |> str_remove("\\\\[)\\]]$") |> str_trim()
  disp <- str_detect(xml2::xml_attr(math, "class"), "display")
  tok  <- sprintf("MATHTOKEN%04dZ", seq_along(math))
  walk2(math, tok, function(node, t) xml2::xml_text(node) <- t)
  # code blocks: give pandoc a plain language class
  walk(xml2::xml_find_all(main, ".//pre[contains(@class,'sourceCode')]"),
       function(node) xml2::xml_attr(node, "class") <- if (grepl("\\br\\b", xml2::xml_attr(node, "class"))) "r" else "")
  tmp_in <- tempfile(fileext = ".html"); tmp_out <- tempfile(fileext = ".md")
  writeLines(as.character(main), tmp_in, useBytes = TRUE)
  rmarkdown::pandoc_convert(tmp_in, to = "gfm-raw_html", from = "html",
                            output = tmp_out, options = "--wrap=none")
  md <- readLines(tmp_out, warn = FALSE, encoding = "UTF-8") |>
    discard(function(x) str_detect(x, "^:::|^<div|^</div")) |>
    paste(collapse = "\n")
  md <- reduce(seq_along(tok), function(m, i)
    str_replace(m, fixed(tok[i]), if (disp[i]) paste0("\n\n$$", tex[i], "$$\n\n") else paste0("$", tex[i], "$")),
    .init = md)
  md |> str_replace_all("``` (r|sourceCode)", "```r") |> str_replace_all("\n{3,}", "\n\n")
}

fetch_sampling_techniques <- function(pages = SAMPLING_PAGES) {
  stopifnot("pandoc not found (install RStudio or pandoc)" = rmarkdown::pandoc_available())
  url <- SVY_LIBRARY_URLS[["sampling-techniques"]]
  map(pages, function(p) {
    u <- sub("{page}", paste0(p, ".html"), url, fixed = TRUE)
    tmp <- tempfile(fileext = ".html")
    ok <- tryCatch({ utils::download.file(u, tmp, quiet = TRUE, mode = "wb"); TRUE },
                   error = function(e) { message("  could not download ", u); FALSE })
    if (!ok) return(NULL)
    write_chapter("sampling-techniques", p, html_to_md(tmp), u)
  }) |> compact() |> unlist()
}

# --- run ------------------------------------------------------------------------
source("R/library.R")
SVY_LIBRARY_URLS <- map(SVY_LIBRARY, "url")

fetch_external <- function() {
  t0 <- Sys.time()
  res <- list(`tidy-survey` = fetch_tidy_survey(),
              `sampling-techniques` = fetch_sampling_techniques())
  out <- imap(res, function(f, b) tibble(book = b, file = basename(f), kb = round(file.size(f) / 1024))) |>
    purrr::list_rbind()
  message(sprintf("%d chapters written under %s/ in %.0f s. Next: source(\"build_store.R\")",
                  nrow(out), EXT_DIR, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  invisible(out)
}

if (sys.nframe() == 0L || identical(environment(), globalenv())) print(fetch_external(), n = Inf)
