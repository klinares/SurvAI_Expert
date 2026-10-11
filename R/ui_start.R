# ui_start.R -- tab 1: documentation, the key, and the store status.

mod_start_ui <- function(id) {
  ns <- shiny::NS(id)
  bslib::layout_columns(
    col_widths = c(7, 5),
    bslib::card(bslib::card_header("Start here"), help_html(),
                shiny::tags$details(shiny::tags$summary(shiny::strong("Reflexes")),
                                    reflex_table_html())),
    bslib::card(
      bslib::card_header("API key"),
      shiny::uiOutput(ns("key_status")),
      # The paste box shows only when no key is in use (or on request).
      shiny::conditionalPanel(
        "output.need_key || input.change_key % 2 == 1", ns = ns,
        shiny::passwordInput(ns("key"), NULL, width = "100%",
                             placeholder = "Paste your key (or the passphrase)"),
        shiny::div(shiny::actionButton(ns("save"), "Use this key", class = "btn-primary"),
                   shiny::actionButton(ns("clear"), "Forget it"))),
      shiny::hr(),
      shiny::h6("Configuration"),
      shiny::uiOutput(ns("config"))))
}

mod_start_server <- function(id, state) {
  shiny::moduleServer(id, function(input, output, session) {
    token <- session$token
    bump <- function() state$key_version <- (state$key_version %||% 0L) + 1L

    shiny::observeEvent(input$save, {
      k <- trimws(input$key %||% "")
      if (!nzchar(k)) return(shiny::showNotification("Nothing pasted.", type = "warning"))
      shiny::updateTextInput(session, "key", value = "")
      if (llm_try_unlock(k)) {
        shiny::showNotification("Unlocked: using the owner's key for this session.", type = "message")
        return(bump())
      }
      llm_set_session_key(k)
      # One embedding call proves the key works before the analyst relies on it.
      ok <- try(embed_texts("key check"), silent = TRUE)
      if (inherits(ok, "try-error")) {
        llm_clear_session_key(token)
        shiny::showNotification(paste("That key did not work:",
                                      conditionMessage(attr(ok, "condition"))),
                                type = "error", duration = NULL)
      } else shiny::showNotification("Key accepted for this session.", type = "message")
      bump()
    })
    # Bookmarkable unlock: https://<app>/?pass=<passphrase>
    shiny::observe({
      q <- shiny::parseQueryString(session$clientData$url_search %||% "")
      if (!is.null(q$pass) && llm_try_unlock(q$pass)) bump()
    })
    shiny::observeEvent(input$clear, { llm_clear_session_key(token); bump() })
    session$onSessionEnded(function() llm_clear_session_key(token))

    has_key <- shiny::reactive({
      state$key_version
      !is.null(llm_session_key()) ||
        (server_key_open() && nzchar(Sys.getenv(svy_profile()$key_var)))
    })
    output$need_key <- shiny::reactive(!has_key())
    shiny::outputOptions(output, "need_key", suspendWhenHidden = FALSE)

    output$key_status <- shiny::renderUI({
      if (has_key())
        shiny::p(class = "text-success", "\u2713 Key in use. You're ready: open the Methodologist tab. ",
                 shiny::actionLink(session$ns("change_key"), "Use a different key"))
      else shiny::p(class = "text-warning", "No key yet. The Methodologist tab needs one.")
    })

    output$config <- shiny::renderUI({
      prof <- svy_profile(); m <- state$store$meta %||% list()
      shiny::tags$table(class = "table table-sm small",
        shiny::tags$tbody(purrr::imap(list(
          Provider = prof$name, Endpoint = prof$base_url,
          `Chat model` = prof$chat,
          `Embedding` = paste0(prof$embed, " (", SVY_SETTINGS$embed_dims, " dims)"),
          `Store built` = m$built_at %||% "--",
          `Store contents` = if (length(m)) paste0(m$n_docs, " files, ", m$n_chunks, " chunks") else "--",
          `Store status` = state$store_error %||% "ready",
          `Owner key on server` = if (nzchar(Sys.getenv(prof$key_var))) "yes" else "no",
          `Passphrase set` = if (nzchar(Sys.getenv("RAGTIME_PASSPHRASE"))) "yes" else "no"),
          function(v, k) shiny::tags$tr(shiny::tags$th(k), shiny::tags$td(v)))))
    })
  })
}
