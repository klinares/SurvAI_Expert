# catalog_equations.R -- ONE-TIME (re-run when materials change): a catalogue
#   of every displayed equation in the coursework, named and explained, saved
#   as UMD_JPSM_coursework/equation_catalog.csv.
#
#   source("catalog_equations.R")            # after convert_pdfs.R
#
# Reads the LaTeX that is already there -- Quarto/R Markdown sources, the
#   markdown twins convert_pdfs.R wrote for the PDFs, the textbook chapters --
#   so finding equations costs nothing. The worker model then names each one
#   (one structured call per file, up to 30 equations each).
#
# build_store.R turns each row into a small searchable "formula card", so a
#   question like "Kish design effect formula" lands on the formula itself and
#   the page it came from. The CSV lives in the coursework repo: the work build
#   reads it and makes no naming calls.

suppressPackageStartupMessages({ library(dplyr); library(purrr); library(stringr); library(tibble) })
invisible(lapply(c(sort(list.files("R", "^(config|llm.*)\\.R$", full.names = TRUE)), "build/extract.R"), source))

CATALOG <- list(
  corpus   = Sys.getenv("SVYMETH_CORPUS"),
  cache    = file.path(tools::R_user_dir("ragtime", "cache"), "equations"),
  per_call = 30L,
  parallel = 8L)

EQ_BLOCK_RX <- "(?s)\\$\\$(.+?)\\$\\$|\\\\begin\\{(equation|align|eqnarray|gather|multline)\\*?\\}(.+?)\\\\end\\{\\2\\*?\\}"

# Text of every file that can carry LaTeX, keyed by its origin (PDF path for twins).
latex_sources <- function(corpus) {
  ef  <- eligible_files(corpus)
  ext <- tolower(tools::file_ext(ef))
  src <- if_else(ext == "pdf", map_chr(ef, md_twin), ef)
  keep <- !is.na(src) & tolower(tools::file_ext(src)) %in% c("md", "qmd", "rmd")
  tibble(origin = rel_of(ef[keep], corpus), path = src[keep])
}

extract_equations <- function(txt) {
  m <- str_locate_all(txt, EQ_BLOCK_RX)[[1]]
  if (!nrow(m)) return(NULL)
  pages <- str_locate_all(txt, "## Page (\\d+)")[[1]]
  pnum  <- as.integer(str_match_all(txt, "## Page (\\d+)")[[1]][, 2])
  tibble(start = m[, 1], end = m[, 2]) |>
    mutate(raw = str_sub(txt, start, end),
           latex = str_squish(str_remove_all(raw, "^\\$\\$|\\$\\$$")),
           page = map_int(start, function(s) { i <- which(pages[, 1] < s); if (length(i)) pnum[max(i)] else NA_integer_ }),
           context = str_squish(paste(str_sub(txt, pmax(1, start - 500), start - 1), "[EQUATION]",
                                      str_sub(txt, end + 1, end + 150)))) |>
    filter(nchar(latex) >= 8, str_detect(latex, "=|\\\\approx|\\\\propto|\\\\le|\\\\ge|\\\\sim")) |>
    mutate(key = str_remove_all(latex, "\\s")) |>
    distinct(key, .keep_all = TRUE) |>
    select(page, latex, context)
}

NAME_SYS <- paste(
  "You catalogue equations from graduate survey-methodology course materials (sampling, weighting,",
  "variance estimation, nonresponse, measurement, statistics). For each numbered equation, using its",
  "surrounding text: give a short standard name a methodologist would search for (e.g. 'Kish design",
  "effect for cluster sampling', 'Horvitz-Thompson estimator of a total'); one sentence on what it",
  "computes or states; and the meaning of its main symbols. If an equation is only an algebra step or a",
  "numeric example, name it as such. Do not change the LaTeX.")

EQ_TYPE <- ellmer::type_object(items = ellmer::type_array(ellmer::type_object(
  i = ellmer::type_integer("equation number as given"),
  name = ellmer::type_string(),
  description = ellmer::type_string(),
  symbols = ellmer::type_string("e.g. 'n: sample size; b: elements per cluster'"))))

catalog_equations <- function(corpus = CATALOG$corpus) {
  stopifnot("Set SVYMETH_CORPUS" = dir.exists(corpus))
  t0 <- Sys.time(); dir.create(CATALOG$cache, recursive = TRUE, showWarnings = FALSE)
  src <- latex_sources(corpus)
  eqs <- src |>
    mutate(eq = map(path, function(p) extract_equations(paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")))) |>
    select(-path) |> tidyr::unnest(eq) |>
    mutate(group = paste0(origin, "#", (row_number() - 1L) %/% CATALOG$per_call), .by = origin) |>
    mutate(i = row_number(), .by = group,
           cache_file = file.path(CATALOG$cache, paste0(gsub("[^A-Za-z0-9]+", "_", group), ".rds")))
  message(nrow(eqs), " equations in ", n_distinct(eqs$origin), " files; ",
          n_distinct(eqs$group), " naming calls (", n_distinct(eqs$group[file.exists(eqs$cache_file)]), " cached)")

  todo <- eqs |> filter(!file.exists(cache_file)) |> group_by(group, cache_file) |>
    summarise(prompt = paste0("Source: ", first(origin), "\n\n",
                              paste0("Equation ", i, ":\n$$", latex, "$$\nContext: ", str_trunc(context, 650), collapse = "\n\n")),
              .groups = "drop")
  if (nrow(todo)) {
    batches <- split(seq_len(nrow(todo)), ceiling(seq_len(nrow(todo)) / (CATALOG$parallel * 4)))
    iwalk(batches, function(ix, b) {
      chat <- llm_chat("worker", NAME_SYS, temperature = 0)
      res <- tryCatch(ellmer::parallel_chat_structured(chat, as.list(todo$prompt[ix]), type = EQ_TYPE,
                                                        max_active = CATALOG$parallel, convert = FALSE),
                      error = function(e) { message("  batch ", b, " failed: ", conditionMessage(e)); NULL })
      if (is.null(res)) return(invisible())
      walk2(todo$cache_file[ix], res, function(f, r)
        if (length(r$items)) saveRDS(map(r$items, function(x) as_tibble(map(x, function(v) v %||% NA))) |> list_rbind(), f))
      message(sprintf("  named batch %s/%d", b, length(batches)))
    })
  }
  named <- eqs |> distinct(group, cache_file) |> filter(file.exists(cache_file)) |>
    mutate(n = map(cache_file, readRDS)) |> select(group, n) |> tidyr::unnest(n) |>
    mutate(i = as.integer(i))
  out <- eqs |> left_join(named, by = c("group", "i")) |>
    mutate(course = doc_meta(origin)$course) |>
    select(origin, course, page, name, description, symbols, latex)
  f <- file.path(corpus, "equation_catalog.csv")
  readr::write_csv(out, f, na = "")
  message(sprintf("%d equations (%d named) -> %s in %.1f min", nrow(out), sum(!is.na(out$name)), f,
                  as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  invisible(out)
}

if (sys.nframe() == 0L || identical(environment(), globalenv())) catalog_equations()
