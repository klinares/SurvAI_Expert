# RAG Time

```
  ♪ ♫  ─────────────────────────────────────────────────────────  ♫ ♪
   ___    _    ___    _____ _
  | _ \  /_\  / __|  |_   _(_)_ __  ___
  |   / / _ \| (_ |    | | | | '  \/ -_)     an AI Survey Methodologist
  |_|_\/_/ \_\\___|    |_| |_|_|_|_\___|     in syncopated time
  ─────────────────────────────────────────────────────────────────────
   𝄞  retrieve · augment · generate  —  left hand keeps the design,
                                         right hand plays the answer
  ─────────────────────────────────────────────────────────────────────
```

*Ragtime is two hands doing different jobs: a steady bass (the stride) and a
syncopated melody on top. RAG Time works the same way. The **left hand** is
steady and never improvises — your JPSM coursework, searched the same way every
time. The **right hand** is the model, free to phrase the answer, but only over
the chords the left hand plays.*

---

## The score  (what's in the folder)

```
rag_time/
├── shiny_app.R          ♩  THE app. Run this, deploy this.
├── R/                   ♩  everything the app needs (sourced by shiny_app.R)
│   ├── classification.R    the classification banner above every screen
│   ├── config.R            endpoints, models, settings  ← edit model names here
│   ├── llm.R               keys (per session), chat + embedding calls
│   ├── retrieve.R          vector + keyword search in DuckDB, rank fusion
│   ├── reflexes.R          the methodologist's habits, prohibitions, answer audit
│   ├── render.R            markdown + LaTeX (KaTeX → MathML), sources
│   ├── library.R           the external books: titles, web links
│   ├── help.R, ui_start.R  tab 1: Start here (docs + your key)
│   ├── ui_chat.R           tab 2: Methodologist (the chat)
│   └── llm_openrouter.R    optional provider override — delete where not used
├── store/jpsm.duckdb    ♩  the index (~70 MB, fits GitHub)
├── build_store.R        𝄽  rebuilds the store from the coursework + external/ (not deployed)
├── fetch_external.R     𝄽  one-time: external books → external/<book>/*.md
├── external/            𝄽  converted book chapters (committed; travels to work)
├── convert_pdfs.R       𝄽  one-time: PDFs → markdown with LaTeX math (vision model)
├── parse_textbook.R     𝄽  textbook PDF → one markdown file per chapter
├── catalog_equations.R  𝄽  one-time: named catalogue of every equation
├── build/extract.R      𝄽  PDF/Quarto text extraction for the build
├── eval/eval_rag.R      𝄽  accuracy check (not deployed)
├── deploy.R             𝄽  publish to Posit Connect
├── switch_to_work.R     𝄽  one-time: repoint repo links, paths, endpoint, models
└── _archive/            𝄽  earlier attempts, kept only for reference — not used
```

♩ = played on stage (deployed) · 𝄽 = rest (stays on your machine)

## Tempo marking  (how to play it)

Every model call goes through **ellmer** to an OpenAI endpoint (`R/llm.R`,
settings in `R/config.R`). Embeddings go to the same endpoint's `/embeddings`.

1. Fill in the `WORK` list at the top of `switch_to_work.R` (work repo URL,
   coursework path, endpoint, model names) and `source("switch_to_work.R")`.
   It rewrites the defaults in `R/config.R`, removes the OpenRouter file,
   writes the paths to a git-ignored `.Renviron` and checks the folder.
   Put `OPENAI_API_KEY` in your user `.Renviron`. Delete the script after.
2. Source links under each answer point to `SVY_SOURCE_URL` in `R/config.R`
   (`{path}` = the file's path in the coursework repo), so they follow the
   work repo. `SVYMETH_SOURCE_URL` overrides it on Connect without editing.
3. `source("build_store.R")` — embeddings only (~110 calls, no chat model).
   Resumes if interrupted.
4. `shiny::runApp("shiny_app.R")` to check, then `source("deploy.R")`.
   On Connect set `SVYMETH_KEY_SOURCE=analyst` and `RAGTIME_CLASSIFICATION`
   to your marking (the red banner on every screen; default UNCLASSIFIED).

Tab **1. Start here** has the docs and a box for your key. Tab **2.
Methodologist** is the chat. Every answer cites `[S1]`, `[S2]`… with links to
the files, renders formulas from LaTeX, and ends with an audit line that flags
any formula or citation not found in the retrieved sources.

**Other providers.** `R/llm_openrouter.R` is an optional override that points
the same code at OpenRouter. Where that is not available, delete the file.

**The textbook.** `parse_textbook.R` splits the Practical Tools PDF into one
markdown file per chapter under `UMD_JPSM_coursework/practical_tools_textbook/`
(`SVYMETH_BOOK` = the PDF). The build then indexes those files like any other
course file. The textbook is copyrighted: keep that repository private.

**The external books.** Two open books back up the coursework: the Tidy
Survey Book (from its `.Rmd` sources in your clone, `SVYMETH_TIDY`, default
`D:/repos/tidy-survey-book`) and *Sampling and Survey Techniques* (downloaded
from bookdown.org; it has no public source repo). Run `fetch_external.R` at
home; it writes `external/<book>/<chapter>.md`, which you commit. The build
indexes those with `tier = "external"`, and retrieval multiplies their scores
by `external_weight` (0.85, `R/config.R`) so your coursework wins ties. Source
links open the published chapter (`R/library.R`). At work nothing changes:
`build_store.R` reads `external/` from the repo and only embeds. To add a book,
add it to `R/library.R` and a fetcher to `fetch_external.R`.

**Scoring the melody (one-time, then committed to the coursework repo).**
`convert_pdfs.R` sends each PDF page that holds mathematics, or has no usable
text, to a vision model and writes `Lecture6.md` beside `Lecture6.pdf`, with
the equations in LaTeX. `catalog_equations.R` then collects every displayed
equation into `equation_catalog.csv`, each with a name, a one-line meaning and
its symbols. The build reads both (the PDF stays the source link), and turns
each equation into a small "formula card" that search can land on. Because
the results live in the coursework repo, the build at work needs neither step.

## The rests  (what the build leaves out on purpose)

So the build never stalls on the wrong files:
rendered PDFs in `assignments/` (their `.qmd` is used), any PDF with a
`.qmd`/`.Rmd` twin, `readings/`, `data/`, `*_files/` figure folders, syllabi and
admin PDFs, data/binary files. Image-only PDFs are listed and skipped.

## Models  (who plays which part)

| Part | Model | Set in |
|---|---|---|
| Chat (talks to analysts) | your endpoint's main model | `R/config.R` |
| Build-time only (PDF conversion, equation names) | a vision-capable model | `SVYMETH_BUILD_MODEL` |
| Embeddings | text-embedding-3-small, 512 dims | `R/config.R` (must match the store) |

The embedding model must match the store; the app refuses to search otherwise.

## Last recital  (accuracy check, 108 questions)

Right source file in top 5: **88%** · top 10: **92%** · right course in top 5: **93%**.
Judged answer score (40 questions): 0.86 with a frontier chat model, 0.68 with
a small open model. Weakest spot: R-code questions, where models substitute a package
for the course's own code.

## Instruments

shiny, bslib, shinychat, ellmer, httr2, duckdb, DBI, dplyr, purrr, stringr,
tibble, katex, commonmark, htmltools — plus ragnar, pdftools, stringi, fs,
tidyr, rlang to build, and xml2 + rmarkdown (pandoc) to fetch the books.

```
  ♪  fin.  "Don't play this piece fast. It is never right to play ragtime fast."
                                                    — Scott Joplin
```
