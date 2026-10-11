# deploy.R -- publish the app (shinyapps.io or Posit Connect, whichever
#   rsconnect account is set up).
#
#   source("deploy.R")
#
# Only what the running app needs is sent: shiny_app.R, R/, the store. The build
#   scripts, the extraction cache and the evaluation stay behind.
#
# OWNER'S KEY (optional). If the profile's key variable (OPENROUTER_API_KEY or
#   OPENAI_API_KEY) and RAGTIME_PASSPHRASE are set
#   in your environment (or as GitHub Actions secrets), they are written to a
#   temporary key.env that ships inside the deployed bundle only -- never to
#   git -- and is deleted after the upload. In the app, typing the passphrase
#   in the key box (or opening https://<app>/?pass=<passphrase>) uses your key.
#   Without the passphrase, visitors must paste their own key; a key without a
#   passphrase is not shipped (it would let anyone with the link spend credit).
#   On Posit Connect prefer the Vars pane: set the key and RAGTIME_PASSPHRASE
#   there and no key.env is needed.
#
# On Connect you can instead set these in the content's Vars pane:
#   SVYMETH_KEY_SOURCE     = analyst          (each analyst pastes their own key)
#   RAGTIME_CLASSIFICATION = <your marking>   (banner text; default UNCLASSIFIED)
# The embedding model and dims in config.R must match the store you deploy;
#   the app checks and refuses otherwise. Any R/llm_*.R provider file present
#   is deployed too, so delete R/llm_openrouter.R where it is not used.

# The key variable comes from the active profile (R/config.R, or the optional
#   R/llm_openrouter.R): OPENROUTER_API_KEY at home, OPENAI_API_KEY at work.
deploy_key_var <- function() {
  e <- new.env()
  invisible(lapply(sort(list.files("R", "\\.R$", full.names = TRUE)), sys.source, envir = e))
  e$svy_profile()$key_var
}

write_key_env <- function(key_var = deploy_key_var()) {
  vars <- c(key_var, "RAGTIME_PASSPHRASE")
  vals <- Sys.getenv(vars)
  if (!nzchar(vals[[1]])) return(FALSE)
  if (!nzchar(vals[[2]])) {
    message(key_var, " is set but RAGTIME_PASSPHRASE is not, so the key is NOT shipped: ",
            "visitors paste their own. (On Posit Connect, set both in the Vars pane instead.)")
    return(FALSE)
  }
  writeLines(paste0(vars, "=", vals), "key.env")
  TRUE
}

deploy_files <- function(with_key = FALSE)
  c("shiny_app.R", list.files("R", "\\.R$", full.names = TRUE), "store/jpsm.duckdb",
    if (with_key) "key.env")

if (sys.nframe() == 0L || identical(environment(), globalenv())) {
  with_key <- write_key_env()
  message(if (with_key) "Deploying with your key (passphrase-protected)."
          else "Deploying without a server key: visitors paste their own.")
  tryCatch(
    rsconnect::deployApp(appDir = ".", appFiles = deploy_files(with_key),
                         appName = "SurvAI_Expert", appTitle = "SurvAI Expert", appPrimaryDoc = "shiny_app.R",
                         forceUpdate = TRUE),
    finally = unlink("key.env"))
}
