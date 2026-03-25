# Scrapling Skill

## Skill identity
- **Name**: `scrapling`
- **Owner**: `task-runner`
- **Purpose**: Web scraping and data extraction via Scrapling framework
- **Status**: operational (HTTP mode); browser mode not installed

## Prerequisites
- Scrapling installed in container image (pip install scrapling)
- Network access via openclaw-task-net
- Python 3.10+

## What this skill does
Uses the Scrapling framework to fetch and parse web content. Supports:
- HTTP requests with adaptive HTML parsing
- CSS/XPath selectors with auto-relocation (survives site layout changes)
- Structured data extraction
- Note: Browser automation (Playwright/Camoufox) is NOT installed in the
  current image. Only HTTP-based scraping is available.

## When to use this skill
- Task requires extracting data from web pages
- Task requires monitoring web content changes
- Task requires building a dataset from web sources

## Workflow
1. Identify target URLs and data requirements
2. Write Python script using Scrapling API
3. Execute scraping script
4. Parse and structure extracted data
5. Write results to /workspace/outputs/

## Example usage
```python
from scrapling import Fetcher

fetcher = Fetcher(auto_match=True)
page = fetcher.get("https://example.com")

# CSS selector extraction
titles = page.css("h2.title")
for t in titles:
    print(t.text)

# Structured extraction
data = page.css("div.item").extract({
    "title": "h2::text",
    "price": "span.price::text",
    "url": "a::attr(href)"
})
```

## Output format
Scraped data goes to /workspace/outputs/scraped-data.json or .csv:
```json
{
  "source_url": "https://example.com",
  "scraped_at": "2026-03-25T10:00:00Z",
  "items": [
    {"title": "...", "price": "...", "url": "..."}
  ]
}
```

## Safety rules
- Respect robots.txt: check before scraping
- Respect rate limits: add delays between requests (min 1s)
- Do not scrape authenticated/paywalled content without authorization
- Do not store personal information (PII) in outputs
- Container IP is the host's IP — be aware of IP-based rate limiting
- Do not use for DDoS or mass automated access
