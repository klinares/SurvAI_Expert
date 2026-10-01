# classification.R -- the classification marking shown above every screen.
#
# The text comes from an option (or an environment variable on Connect) rather
#   than being written into the code: the marking is a deployment decision and
#   has to change without anyone editing R/. Set it wherever the app starts --
#     options(ragtime.classification = "YOUR MARKING")
#   -- or set RAGTIME_CLASSIFICATION in the Connect content's Vars pane. Unset,
#   it falls back to UNCLASSIFIED rather than to nothing, so a deployment that
#   forgets shows a marking that is visibly wrong instead of no marking at all.
classification_text <- function()
  getOption("ragtime.classification",
            Sys.getenv("RAGTIME_CLASSIFICATION", "UNCLASSIFIED"))

classification_banner <- function() {
  shiny::tags$div(
    class = "classification-banner", role = "banner",
    style = paste("background:#b40404; color:#fff; text-align:center;",
                  "font-weight:700; letter-spacing:0.06em;",
                  "padding:5px 0; font-size:13px;"),
    classification_text())
}
