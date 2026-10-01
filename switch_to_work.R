# switch_to_work.R -- ONE-TIME helper for the move to the work machine.
#   Fill in WORK below, then from the rag_time folder:
#
#     source("switch_to_work.R")
#
#   It rewrites the defaults in R/config.R (endpoint, model names, where the
#   "Sources" links point), removes the OpenRouter override, writes the paths
#   into this project's .Renviron, and checks the coursework folder. Run it
#   again after changing WORK if needed; then DELETE THIS FILE.
#   It never writes an API key: put OPENAI_API_KEY in your user .Renviron.

WORK <- list(
  # the coursework repo as it lives at work
  source_url = "https://github.com/YOUR-ORG/UMD_JPSM_coursework/blob/main/{path}",  # {path} = file path in the repo
  corpus     = "C:/path/to/UMD_JPSM_coursework",                                 # local clone, for build_store.R
  # the OpenAI endpoint and the chat model it serves
  base_url   = "https://api.openai.com/v1",
  chat       = "gpt-4.1",
  cache      = "",   # optional scratch folder for build caches ("" = R's user cache dir)
  classification = "UNCLASSIFIED")   # text of the red banner on every screen

switch_to_work <- function(w = WORK) {
  stopifnot("Run from the rag_time folder" = file.exists("R/config.R"),
            "source_url must contain {path}" = grepl("{path}", w$source_url, fixed = TRUE))

  # 1. defaults in R/config.R (each replacement must hit exactly once)
  cfg <- paste(readLines("R/config.R", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  swaps <- list(
    c('(Sys\\.getenv\\("SVYMETH_BASE_URL", *")[^"]*(")',     w$base_url),
    c('(Sys\\.getenv\\("SVYMETH_CHAT_MODEL", *")[^"]*(")',   w$chat),
    c('(Sys\\.getenv\\("SVYMETH_SOURCE_URL",\\s*")[^"]*(")', w$source_url))
  hits <- purrr::map_int(swaps, function(s) lengths(regmatches(cfg, gregexpr(s[1], cfg, perl = TRUE))))
  if (any(hits != 1)) stop("R/config.R did not match as expected; edit it by hand. Hits: ",
                           paste(hits, collapse = ", "))
  cfg <- purrr::reduce(swaps, function(txt, s)
    sub(s[1], paste0("\\1", gsub("\\\\", "\\\\\\\\", s[2]), "\\2"), txt, perl = TRUE), .init = cfg)
  writeLines(cfg, "R/config.R", useBytes = TRUE)
  message("R/config.R: endpoint, chat model and source links updated")

  # 2. no OpenRouter at work
  if (file.exists("R/llm_openrouter.R")) { file.remove("R/llm_openrouter.R"); message("removed R/llm_openrouter.R") }

  # 3. paths for the build scripts, in this project's .Renviron (git-ignored)
  env <- if (file.exists(".Renviron")) readLines(".Renviron", warn = FALSE) else character()
  set <- c(SVYMETH_CORPUS = w$corpus, SVYMETH_CACHE = w$cache, RAGTIME_CLASSIFICATION = w$classification)
  set <- set[nzchar(set)]
  env <- c(env[!sub("=.*", "", env) %in% names(set)], paste0(names(set), "=", set))
  writeLines(env, ".Renviron"); do.call(Sys.setenv, as.list(set))
  gi <- if (file.exists(".gitignore")) readLines(".gitignore", warn = FALSE) else character()
  if (!".Renviron" %in% gi) writeLines(c(gi, ".Renviron"), ".gitignore")
  message(".Renviron: ", paste(names(set), collapse = ", "))

  # 4. checks
  ok <- c(
    `coursework folder found`       = dir.exists(w$corpus),
    `textbook chapters present`     = dir.exists(file.path(w$corpus, "practical_tools_textbook")),
    `equation_catalog.csv present`  = file.exists(file.path(w$corpus, "equation_catalog.csv")),
    `OPENAI_API_KEY set`            = nzchar(Sys.getenv("OPENAI_API_KEY")),
    `no placeholders left`          = !any(grepl("YOUR-ORG|path/to", unlist(w))))
  purrr::iwalk(ok, function(v, k) message(if (v) "  ok   " else "  FIX  ", k))
  message("\nNext: restart R, source(\"build_store.R\"), shiny::runApp(\"shiny_app.R\") and click a source ",
          "link to check it opens the work repo, then source(\"deploy.R\") ",
          "(on Connect set SVYMETH_KEY_SOURCE=analyst). Then delete switch_to_work.R.")
  invisible(ok)
}

if (sys.nframe() == 0L || identical(environment(), globalenv())) switch_to_work()
