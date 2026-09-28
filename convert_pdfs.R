# convert_pdfs.R -- ONE-TIME: turn the coursework PDFs (and the textbook) into
#   markdown with the mathematics written as LaTeX, using a vision model.
#
#   source("convert_pdfs.R")      # from the rag_time folder: runs the whole job
#   (~1 h). Best as an RStudio background job so the console stays free.
#
# Output goes into the coursework repo, so the store build (at work too) never
#   needs a vision model:
#     <course>/lectures/Lecture6.pdf  ->  <course>/lectures/Lecture6.md
#     textbook pages -> practical_tools_textbook/chNN-*.md (via parse_textbook.R)
#   build_store.R reads Lecture6.md in place of Lecture6.pdf but keeps the PDF
#   as the source link, so citations still open the PDF at the page.
#
# Only pages that need it go to the model: pages whose extracted text shows
#   mathematics, or whose text is garbled or missing (image-only slides). All
#   other pages keep the plain PDF text. Every converted page is cached, so the
#   run can be stopped and restarted without paying twice.
#
# Calls: one per converted page (about 3,500 for the full coursework and
#   textbook), sent in parallel through ellmer. Uses the "worker" model, which
#   must accept images.

suppressPackageStartupMessages({ library(dplyr); library(purrr); library(stringr); library(tibble) })
invisible(lapply(c(sort(list.files("R", "^(config|llm.*)\\.R$", full.names = TRUE)), "build/extract.R"), source))

CONVERT <- list(
  corpus    = Sys.getenv("SVYMETH_CORPUS"),
  book      = Sys.getenv("SVYMETH_BOOK"),
  cache     = file.path(tools::R_user_dir("ragtime", "cache"), "pages"),
  dpi       = 110L,
  parallel  = 16L,         # requests in flight
  batch     = 96L)         # pages per saved batch

VISION_SYS <- paste(
  "You transcribe one page of graduate survey-statistics course material into Markdown.",
  "Write ALL mathematics in LaTeX: inline as $...$, displayed equations as $$...$$ on their own lines.",
  "Keep the page's headings, bullet points and tables (as Markdown tables). Put R or other code in",
  "fenced blocks. If a figure carries information, describe it in one italic sentence.",
  "Output only the transcription: no preamble, no commentary, no page numbers or footers.")

# Signals of mathematics in extracted PDF text (Greek letters, operators,
#   accents that pdftools splits off, x = ..., hats, Var(), E()).
MATH_RX <- paste0("[∑Σ√∏∫≈≤≥±∈θπσ",
                  "ρμλβαγδε̂̄¯ˆ−]",
                  "|\\b[a-zA-Z]\\s*=\\s*[^=]|\\^|\\bvar\\b|\\bV\\(|\\bE\\(")

needs_vision <- function(txt) {
  g <- map_dbl(txt, garble)
  is.na(g) | g > GARBLE_MAX | grepl(MATH_RX, txt, perl = TRUE)
}

page_cache <- function(key, page) file.path(CONVERT$cache, key, sprintf("p%04d.md", page))

# Sends the listed pages to the vision model, caching each answer.
convert_pages <- function(jobs) {
  todo <- jobs |> filter(!file.exists(cache_file))
  if (!nrow(todo)) return(invisible(0L))
  batches <- split(seq_len(nrow(todo)), ceiling(seq_len(nrow(todo)) / CONVERT$batch))
  message(nrow(todo), " pages to convert in ", length(batches), " batches")
  iwalk(batches, function(ix, b) {
    t0 <- Sys.time(); j <- todo[ix, ]
    png <- pmap_chr(select(j, pdf, page), function(pdf, page) {
      out <- tempfile(fileext = ".png")
      pdftools::pdf_convert(pdf, format = "png", pages = page, dpi = CONVERT$dpi,
                            filenames = out, verbose = FALSE)
      out
    })
    prompts <- map(png, function(f) list("Transcribe this page.", ellmer::content_image_file(f)))
    chat <- llm_chat("worker", VISION_SYS, temperature = 0)
    txt <- tryCatch(
      ellmer::parallel_chat_text(chat, prompts, max_active = CONVERT$parallel),
      error = function(e) { message("  batch ", b, " failed: ", conditionMessage(e)); rep(NA_character_, length(prompts)) })
    walk2(j$cache_file, txt, function(f, t) {
      if (is.na(t) || !nzchar(str_trim(t))) return(invisible())
      dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
      con <- file(f, open = "w", encoding = "UTF-8"); writeLines(t, con); close(con)
    })
    unlink(png)
    message(sprintf("  batch %s/%d: %d pages in %.0f s", b, length(batches), length(ix),
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  })
  invisible(nrow(todo))
}

# One PDF -> markdown next to it: converted pages where they exist, PDF text otherwise.
write_pdf_markdown <- function(pdf, key, raw) {
  pages <- imap_chr(raw, function(txt, i) {
    f <- page_cache(key, i)
    body <- if (file.exists(f)) paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
            else drop_furniture(tidy_text(txt, dehyphen = TRUE))
    if (!nzchar(str_trim(body))) return("")
    t <- slide_title(txt)
    paste0(if (nzchar(t)) sprintf("## Page %d -- %s", i, t) else sprintf("## Page %d", i), "\n\n", body)
  })
  md <- sub("\\.pdf$", ".md", pdf, ignore.case = TRUE)
  con <- file(md, open = "w", encoding = "UTF-8")
  writeLines(c(sprintf("<!-- converted from %s by convert_pdfs.R; math transcribed to LaTeX -->", basename(pdf)),
               "", paste(pages[nzchar(pages)], collapse = "\n\n")), con)
  close(con)
  md
}

convert_pdfs <- function(corpus = CONVERT$corpus, book = CONVERT$book, only = NULL) {
  stopifnot("Set SVYMETH_CORPUS" = dir.exists(corpus))
  t0 <- Sys.time()
  pdfs <- eligible_files(corpus)
  pdfs <- pdfs[tolower(tools::file_ext(pdfs)) == "pdf"]
  if (!is.null(only)) pdfs <- pdfs[str_detect(pdfs, only)]
  raw  <- map(pdfs, function(p) tryCatch(pdftools::pdf_text(p), error = function(e) character(0)))
  keys <- gsub("[/\\\\:. ]+", "_", rel_of(pdfs, corpus))
  jobs <- pmap(list(pdfs, keys, raw), function(p, k, r)
    if (length(r)) tibble(pdf = p, page = which(needs_vision(r)), key = k) else NULL) |> list_rbind()
  has_book <- nzchar(book) && file.exists(book) && is.null(only)
  if (has_book) {
    braw <- pdftools::pdf_text(book)
    jobs <- bind_rows(jobs, tibble(pdf = book, page = which(needs_vision(braw)), key = "BOOK__practical_tools"))
  }
  jobs <- jobs |> mutate(cache_file = page_cache(key, page))
  message(length(pdfs), " PDFs; ", nrow(jobs), " pages need the vision model (",
          sum(file.exists(jobs$cache_file)), " already converted)")
  convert_pages(jobs)
  md <- pmap_chr(list(pdfs, keys, raw), function(p, k, r) if (length(r)) write_pdf_markdown(p, k, r) else NA_character_)
  if (has_book) {                                   # textbook chapters, from the converted pages
    source("parse_textbook.R", local = TRUE)
    parse_textbook(book, corpus, cache = dirname(CONVERT$cache))
  }
  message(sprintf("%d markdown files written in %.1f min", sum(!is.na(md)),
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  invisible(tibble(pdf = rel_of(pdfs, corpus), md = !is.na(md)))
}

if (sys.nframe() == 0L || identical(environment(), globalenv())) convert_pdfs()
