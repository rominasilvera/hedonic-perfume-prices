# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Portfolio project: a hedonic price model for women's perfumes, built on data scraped daily from druni.es (`https://www.druni.es/perfumes/mujer`). Written in R with the tidyverse (native pipe `|>`).

## Environment

- Packages are managed with **renv** (`.Rprofile` activates it; snapshot type is `implicit`, so packages are detected from `library()` calls in the code). After adding a package to any script, run `Rscript -e "renv::snapshot(prompt = FALSE)"` and commit `renv.lock`. The CI runner installs **only** what is in the lockfile.
- Run scripts from the repo root (paths like `data/raw/...` are relative to it).
- Platform is Windows; the GitHub CLI (`gh`) may not be installed.

## Commands

```sh
Rscript R/scraper.R                     # full scrape: ~66 listing pages, ~1,600 product pages, ~1 hour
Rscript -e "renv::status()"             # check lockfile vs. library
```

Do not run the full scrape locally to test changes. Source the function definitions (everything above `# Step 3` in `R/scraper.R`) and call `get_product_urls(page_url, max_pages = 2)` and `parse_product()` on a couple of URLs.

## Data pipeline

`R/scraper.R` has three stages:

1. `get_product_urls()` walks listing pages, collecting `.product-item-link` hrefs and following the `a.action.next` ("Siguiente") link until it is absent.
2. `parse_product()` reads the page's `script[type="application/ld+json"]` blocks and returns **one row per size variant**. Products are either `@type: "ProductGroup"` (variants in `hasVariant`) or a plain `"Product"` (offers on the product itself); both shapes must stay supported. `data/example_product_card.json` is a saved ProductGroup example of the JSON-LD structure.
3. Each URL runs through `possibly()`. Output goes to `data/raw/products_mujer_<YYYY-MM-DD>.csv` (with a `scraped_at` column) and failures to `data/raw/failed_urls_<date>.txt`.

All HTTP goes through `fetch_html()` (user agent, ~1 request / 2 s throttle, retries). Keep new requests polite and routed through it.

Data caveats: gift sets ("Cofre ...") have no `size`, so `size_ml` is `NA`; a few product pages fail each run.

## GitHub Actions

`.github/workflows/scrape.yml` runs the scraper daily and commits the new files in `data/raw/` to `main` as `github-actions[bot]` ("data: scrape <date>"). GitHub can delay scheduled runs by hours or skip them, so there are two triggers: a main run at 04:17 UTC and a backup at 16:17 UTC. The `check-date` job skips the scrape if today's CSV is already on `origin/main` or if the date is past `END_DATE` (2027-01-31). Manual `workflow_dispatch` runs always go ahead. The goal is one snapshot per day; the exact time of day doesn't matter.

Consequences:

- `data/raw/` is written by CI, so don't hand-edit or regenerate those files. The daily CSVs together form the price panel.
- The remote gets a new commit every day: `git pull` before starting work or pushing.

## Commit style

Conventional-ish prefixes as used in history: `feat: scraper`, `data: ...`, `build(deps) ...`.

Standard:

- `feat` New functionality
- `fix` Fix bug
- `docs` Comments, code documentation
- `style` Format (non logic changes)
- `refactor` Code reorganization
- `perf` Performance improvements
- `test` Tests
- `build` Dependencies and environment
- `ci` GitHub actions
- `chore` Maintenance
- `revert` Revert commits

Data science related:

- `data` New data or changes in existing data
- `eda` Exploratory data analysis
- `model` Model related
- `exp` Experiments that may not make the cut
- `viz` Plots and visualization
- `report` Quarto, posted results
