# Markdown to PDF: Document Conversion for Claude Code

## What is this and why?

You write documentation, guides, and reports in Markdown - but sometimes you need a PDF. For sending to clients, for printing, for sharing with people who don't know what markdown is.

**Markdown to PDF** is a skill (slash command) for Claude Code that converts `.md` files to high-quality PDFs with a single command:

```
/md-to-pdf docs/my-report.md
```

Under the hood it uses Puppeteer (headless Chrome) - so the PDF looks exactly like markdown renders in a browser. Tables, syntax-highlighted code, headings - everything is preserved.

### What you get:

- **Fast conversion** - 2-3 seconds, Chrome launches only during conversion and closes after
- **Auto-open** - PDF opens automatically after generation
- **Smart edge cases** - directories, raw text, custom output path
- **Layout verification** - optional check that pages look correct
- **CSS control** - page-break rules for tables, code blocks, headings

### What this does NOT do:

- Does not convert other formats (only .md -> .pdf)
- No GUI - works only through Claude Code CLI
- No custom fonts or themes (uses default Chrome styling)

---

## Prerequisites

### 1. Claude Code

Install if you haven't already: https://claude.ai/code

### 2. md2pdf CLI

A Node.js package that uses Puppeteer for conversion.

**Install via npm:**
```bash
npm install -g md-to-pdf
```

After installation, the `md2pdf` (or `md-to-pdf`) command should be available in your terminal.

### 3. pdftoppm (optional)

Only needed for layout verification (converting PDF pages to PNG for visual inspection).

```bash
# macOS
brew install poppler

# Ubuntu/Debian
sudo apt-get install poppler-utils
```

---

## Skill Installation

### Automatic (via agent)

Copy the following text and give it to your AI agent:

`Go to https://github.com/AlexSerbinov/ai-agent-guides/blob/main/md-to-pdf/prompt-eng.md, read the skill text and install it as a skill on my computer.`

The agent will read the prompt, create the file `~/.claude/commands/md-to-pdf.md`, and the skill will be available as `/md-to-pdf`.

### Manual

1. Create the directory (if it doesn't exist):
```bash
mkdir -p ~/.claude/commands
```

2. Copy the contents of [prompt-eng.md](./prompt-eng.md) to:
```bash
~/.claude/commands/md-to-pdf.md
```

3. Restart Claude Code.

4. Verify the skill appears:
```
/md-to-pdf --help
```

---

## How it works

### Basic usage

```
/md-to-pdf docs/report.md
```

This converts `docs/report.md` to `docs/report.pdf` and opens the PDF.

### With custom output path

```
/md-to-pdf docs/report.md output/final-report.pdf
```

### Edge cases

| Situation | Behavior |
|-----------|----------|
| Given a directory | Looks for README.md or a single .md file inside |
| Given raw text | Saves to a temp .md file, converts, reports the output path |
| File doesn't exist | Shows an error |
| No output path | PDF is saved next to the .md file |

### Layout verification (optional)

If you ask Claude to verify the layout, it will:

1. Convert PDF pages to PNG using `pdftoppm`
2. Visually review each page
3. Look for issues:
   - **Orphaned heading** - heading at the bottom of a page, content on the next
   - **Split table/code block** - table or code split across pages
   - **Empty/sparse page** - page with less than ~30% content
4. Fix via CSS page-break rules
5. Regenerate the PDF

### CSS for page-break control

Add at the top of your .md file for better layout:

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

For forced page breaks before major sections:

```html
<div style="page-break-before: always;"></div>
```

---

## FAQ

**Q: Does Chrome stay running after conversion?**
A: No. Chrome launches only during conversion (2-3 seconds) and closes automatically.

**Q: Does it work with large files?**
A: Yes, but very large documents (100+ pages) may take longer. Timeout is set to 30 seconds.

**Q: Does it support mermaid diagrams?**
A: Depends on your md2pdf configuration. By default - no, you need an additional plugin.

**Q: Can I convert multiple files at once?**
A: The skill accepts one file at a time. For batch conversion, ask Claude to do it in a loop.

---

## Compatible agents

| Agent | Support | Notes |
|-------|---------|-------|
| Claude Code | Full | Native slash command `/md-to-pdf` |
| Cursor | Partial | Can be added as a custom command, but slash commands work differently |
| Codex CLI | Partial | Can use the prompt directly, but without slash command integration |
