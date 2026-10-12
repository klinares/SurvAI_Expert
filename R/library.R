# library.R -- the external books on the shelf beside the coursework.
#
# Each book's chapters are converted to markdown by fetch_external.R into
#   external/<id>/, and build_store.R indexes them with origin
#   "ext/<id>/<chapter>.md". Here the app learns, for each book, its title and
#   where a chapter lives on the web, so a source link opens the published
#   chapter rather than a file in the coursework repo.
#
# To add a book: add an entry here, add its fetcher to fetch_external.R, run
#   fetch_external.R, then build_store.R.

SVY_LIBRARY <- list(
  `tidy-survey` = list(
    title   = "Exploring Complex Survey Data Analysis Using R (Zimmer, Powell & Velasquez)",
    short   = "Tidy Survey Book",
    url     = "https://tidy-survey-r.github.io/tidy-survey-book/{page}",
    license = "CC BY-NC-ND 4.0"),
  `sampling-techniques` = list(
    title   = "Sampling and Survey Techniques (Siregar)",
    short   = "Sampling & Survey Techniques",
    url     = "https://bookdown.org/dsciencelabs/sampling_and_survey_techniques/{page}",
    license = "not stated by the author"))

is_external <- function(origin) startsWith(origin, "ext/")

ext_book <- function(origin) stringr::str_split_i(origin, "/", 2)

# "ext/tidy-survey/c05-descriptive-analysis.md" -> the published chapter page
ext_url <- function(origin) purrr::map_chr(origin, function(o) {
  b <- SVY_LIBRARY[[ext_book(o)]]
  if (!is_external(o) || is.null(b)) return(NA_character_)
  sub("{page}", sub("\\.md$", ".html", basename(o)), b$url, fixed = TRUE)
})

# Shown to the model and in the source list, so it is clear which passages
#   are the analyst's own coursework and which come from a book.
ext_label <- function(origin) purrr::map_chr(origin, function(o) {
  b <- SVY_LIBRARY[[ext_book(o)]]
  paste0(if (is.null(b)) ext_book(o) else b$short, ": ", sub("\\.md$", "", basename(o)))
})
