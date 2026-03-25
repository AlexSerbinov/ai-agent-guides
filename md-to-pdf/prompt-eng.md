---
description: "Convert Markdown file to PDF. Usage: /md-to-pdf <path-to-file.md> [output-path.pdf]"
parse-arguments: true
---

Convert a Markdown file to a high-quality PDF using md-to-pdf (Puppeteer/Chrome).

## Instructions

1. The user provides arguments in `$ARGUMENTS`.
2. Parse the arguments:
   - First argument: path to the `.md` file (REQUIRED)
   - Second argument (optional): output PDF path. If not provided, the PDF is saved next to the source file with `.pdf` extension.
3. Verify the source file exists.
4. Run the conversion using Bash:
   ```
   md2pdf <input-file> [output-file]
   ```
   Set timeout to 30000ms. The command outputs the result path, size, and time.
5. After conversion, open the PDF with `open <file.pdf>` so the user sees the result.
6. Open the directory containing the output PDF with `open <directory>` so the user can drag the file wherever needed.
7. Report success with file path and size.

## Edge cases
- If the user provides just a filename without path, resolve it relative to the current working directory.
- If the user provides a directory, look for README.md or any single .md file inside and convert it.
- If the user provides raw markdown text instead of a file path (no .md extension, contains spaces/newlines), save it to a temp file, convert, and report the output path.
- If conversion fails, show the error message.

## Page layout verification (optional, on user request)

After generating the PDF, verify that all elements are on the correct pages — no orphaned headings, no split tables/code blocks, no empty pages, and no pages with mostly white space (less than ~30% content).

### How to verify

1. Convert PDF pages to images using `pdftoppm`:
   ```
   mkdir -p /tmp/pdf_pages && rm -f /tmp/pdf_pages/*.png
   pdftoppm -png -r 150 <output.pdf> /tmp/pdf_pages/p 2>/dev/null
   ```
   This creates `/tmp/pdf_pages/p-01.png`, `p-02.png`, etc.

2. Count pages: `ls /tmp/pdf_pages/ | wc -l`

3. Review each page using the Read tool on the PNG files: `Read /tmp/pdf_pages/p-01.png`
   - Check 4-5 pages at a time in parallel for speed.

4. Look for these problems:
   - **Orphaned heading**: heading at bottom of page, content on next page (big empty space)
   - **Split code block**: code block starts on one page, continues on next
   - **Split table**: table header on one page, rows on next
   - **Empty/near-empty page**: only 2-3 lines of text, rest is white space
   - **Sparse page**: page has content only in the top ~30%, rest is empty. This happens when a forced page-break comes after a short section. Pages should be reasonably filled — aim for at least 50% content per page (except title page and last page)
   - **Title page issues**: TOC or content bleeding into title page

### How to fix

- **Orphaned heading**: Change `**Bold heading**` to `#### Heading` — CSS `h4 { page-break-after: avoid }` prevents orphans
- **Empty page from forced page-break**: Remove `<div style="page-break-before: always;"></div>` before short sections
- **Sparse page**: Remove page-break before the next section so content flows up and fills the page. Only use forced page-breaks before major sections that have enough content to fill most of the next page
- **Large code block split**: Break into smaller code blocks with text between them
- **Large table split**: Split table into two smaller tables (e.g., P1 tools and P2 tools)
- **Content too close to page break**: Remove page-break and let content flow naturally

### CSS for Markdown files (add at top of .md file)

```html
<style>
table { page-break-inside: avoid; margin-bottom: 1em; }
pre { page-break-inside: avoid; }
blockquote { page-break-inside: avoid; }
h2, h3, h4 { page-break-after: avoid; orphans: 3; widows: 3; }
p { orphans: 3; widows: 3; }
li { page-break-inside: avoid; }
</style>
```

Use `<div style="page-break-before: always;"></div>` before major sections only. Don't overuse — causes empty pages.

### Iterate

After fixing, regenerate PDF and re-verify. Repeat until all pages look correct.

## Notes
- Chrome launches only during conversion (~2-3 seconds) and closes after. No persistent processes.
- If `md2pdf` is not found, install it: `npm install -g md-to-pdf`
- `pdftoppm` is from poppler (`brew install poppler` if not available).
