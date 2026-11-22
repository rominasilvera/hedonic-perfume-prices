library(httr2)
library(rvest)
library(tidyverse)
library(jsonlite)


page_url <- "https://www.druni.es/perfumes/mujer"


# HTTP helper -----------------------------------------------------------------

# Polite GET: identifies the client, limits the request rate and retries on
# transient errors (429 / 503). Returns a parsed xml_document.
fetch_html <- function(url) {
  request(url) |>
    req_user_agent("hedonic-perfume-prices (portfolio research scraper)") |>
    req_throttle(capacity = 1, fill_time_s = 2) |> # ~1 request every 2 s
    req_retry(max_tries = 3) |>
    req_perform() |>
    resp_body_string() |>
    read_html()
}


# Step 1: walk the listing pages ----------------------------------------------

# Collects product URLs from a listing page and follows the "Siguiente"
# link (<a class="action next">) until there is no next page.
get_product_urls <- function(start_url, max_pages = Inf) {
  urls <- character()
  next_url <- start_url
  page_n <- 0

  while (!is.na(next_url) && page_n < max_pages) {
    page_n <- page_n + 1
    message("Listing page ", page_n, ": ", next_url)

    page <- fetch_html(next_url)

    urls <- c(
      urls,
      page |>
        html_elements(".product-item-link") |>
        html_attr("href")
    )

    # NA when the pagination link is absent (last page)
    next_url <- page |>
      html_element("a.action.next") |>
      html_attr("href")
  }

  unique(urls)
}


# Step 2: parse a single product page -----------------------------------------

# Returns one row per variant (size). Handles both JSON-LD shapes:
#   - "ProductGroup" with variants in `hasVariant`
#   - plain "Product" with `offers` on the product itself
parse_product <- function(url) {
  blocks <- fetch_html(url) |>
    html_elements('script[type="application/ld+json"]') |>
    html_text2() |>
    map(\(x) fromJSON(x, simplifyVector = FALSE))

  product <- detect(blocks, \(x) x$`@type` %in% c("ProductGroup", "Product"))
  if (is.null(product)) {
    stop("No Product/ProductGroup JSON-LD found")
  }

  variants <- product$hasVariant %||% list(product)

  map(variants, \(v) {
    offer <- v$offers
    # `offers` can be a single object or a list of them
    if (is.null(offer$price) && length(offer) > 0) offer <- offer[[1]]

    tibble(
      url          = url,
      group_id     = product$productGroupID %||% NA_character_,
      name         = product$name %||% NA_character_,
      brand        = product$brand$name %||% NA_character_,
      variant_name = v$name %||% NA_character_,
      sku          = v$sku %||% NA_character_,
      size         = v$size %||% NA_character_,
      price        = as.numeric(offer$price %||% NA),
      currency     = offer$priceCurrency %||% NA_character_,
      availability = str_remove(offer$availability %||% NA_character_,
                                "https?://schema.org/"),
      rating       = as.numeric(product$aggregateRating$ratingValue %||% NA),
      review_count = as.integer(product$aggregateRating$reviewCount %||% NA),
      description  = product$description %||% NA_character_
    )
  }) |>
    list_rbind()
}


# Step 3: run the pipeline ----------------------------------------------------

product_urls <- get_product_urls(page_url)

# `possibly()` keeps the loop going if a single product page fails;
# failed URLs are collected so they can be retried later.
safe_parse <- possibly(parse_product, otherwise = NULL)

results <- map(product_urls, safe_parse, .progress = TRUE)

failed_urls <- product_urls[map_lgl(results, is.null)]

scraped_at <- Sys.Date()

products <- results |>
  list_rbind() |>
  mutate(
    size_ml = parse_number(size), .after = size
  ) |>
  mutate(scraped_at = scraped_at)

# One dated file per run, so repeated runs build a price panel over time
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
write_csv(products, file.path("data/raw", paste0("products_mujer_", scraped_at, ".csv")))

message(
  "Scraped ", nrow(products), " variants from ", length(product_urls),
  " products; ", length(failed_urls), " failed."
)
if (length(failed_urls) > 0) {
  write_lines(failed_urls, file.path("data/raw", paste0("failed_urls_", scraped_at, ".txt")))
}
