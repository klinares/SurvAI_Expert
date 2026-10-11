# Moving SurvAI Expert to work (OpenAI + Posit Connect)

Do these on the `work` branch (`git checkout work`), so the home version on
`main` (OpenRouter + shinyapps.io) stays separate.

## 1. Repoint the code

1. Fill in the `WORK` list at the top of `switch_to_work.R` (coursework repo
   URL, local coursework path, OpenAI base URL, chat model, classification).
2. From the project folder: `source("switch_to_work.R")`. It rewrites the
   defaults in `R/config.R`, deletes `R/llm_openrouter.R`, writes paths to a
   git-ignored `.Renviron`, and prints `ok` / `FIX` checks.
3. Check `R/config.R`: `base_url`, `chat`, `SVY_SOURCE_URL` should be the
   work values. Then delete `switch_to_work.R` and commit.

## 2. Key

Put `OPENAI_API_KEY=...` in your user `.Renviron` (`usethis::edit_r_environ()`),
never in the project. Restart R and confirm:

```r
nzchar(Sys.getenv("OPENAI_API_KEY"))   # TRUE
```

## 3. Rebuild the store

`source("build_store.R")` (embeddings only, resumes if interrupted). The app
refuses to search if the embedding model or dimensions differ from the store,
so rebuild whenever the embedding model changes. `text-embedding-3-small`
at 512 dims matches the current store; other models need a rebuild.

## 4. Test locally

`shiny::runApp("shiny_app.R")`, ask "What is the design effect?", click a
source link (it should open the work repo). The R console shows
`[ask] retrieved N chunks in X s` and `[ask] answered at X s`.

## 5. Deploy to Connect

`source("deploy.R")`. It ships `shiny_app.R`, `R/` and the store only. Do not
set `RAGTIME_PASSPHRASE` in your local environment for this: on Connect the
key goes in the **Vars** pane, not in the upload.

In the content's **Vars** pane set:

| Variable | Value |
|---|---|
| `RAGTIME_CLASSIFICATION` | your marking (banner text) |
| `SVYMETH_KEY_SOURCE` | `analyst` (each person pastes a key), or leave `server` and set the next two |
| `OPENAI_API_KEY` | shared key, only if using `server` |
| `RAGTIME_PASSPHRASE` | optional: then the shared key is used only after typing it |
| `SVYMETH_DUCKDB_MEMORY` | e.g. `2GB` (default `300MB`, sized for shinyapps.io) |
| `SVYMETH_DUCKDB_THREADS` | e.g. `4` (default `1`) |
| `SVYMETH_SOURCE_URL` | optional override for the source links |

Type the passphrase in the key box; avoid the `?pass=` link at work (it lands
in browser history and proxy logs).

## If something breaks

| Symptom | Likely cause / fix |
|---|---|
| "No API key" | Key not in the environment the app sees: Vars pane on Connect, `.Renviron` + restart R locally. |
| "The store was built with ... but this profile embeds with ..." | Embedding model/dims changed: rebuild the store. |
| SSL / certificate / "could not resolve host" errors | Company proxy: set `HTTPS_PROXY` and `CURL_CA_BUNDLE` (ask IT for the CA bundle path). |
| HTTP 404 or "model not found" | Wrong model name or base URL for your endpoint. Azure OpenAI uses deployment names and an `api-version` parameter, which needs a code change in `R/llm.R`. |
| HTTP 429 | Rate limit: wait, or lower "Sources per answer". |
| Hangs with no `[ask] answered` line in the log | The model call is stuck: check the endpoint is reachable from the server. |
| Stops after `[ask] retrieving...` | Search: raise `SVYMETH_DUCKDB_MEMORY`. |
| App dies after a refresh | Should be fixed (one shared DuckDB handle); if it returns, check the logs for memory errors. |
