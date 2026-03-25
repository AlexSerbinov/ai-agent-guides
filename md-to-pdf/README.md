# Markdown to PDF

Скіл для Claude Code який конвертує Markdown файли у високоякісні PDF через Puppeteer/Chrome. Одна команда - і документація, гайди чи звіти перетворюються на готовий PDF.

## Як працює

1. Ви запускаєте `/md-to-pdf report.md` в Claude Code
2. Puppeteer (headless Chrome) рендерить markdown у PDF
3. Файл автоматично відкривається (~2-3 секунди)

Додатково вміє: конвертувати директорії (шукає README.md), приймати raw текст, верифікувати layout сторінок (orphaned headings, split tables, empty pages).

## Як поставити собі

```bash
mkdir -p ~/.claude/commands
```

Скопіюйте вміст [prompt-ukr.md](./prompt-ukr.md) в `~/.claude/commands/md-to-pdf.md` та перезапустіть Claude Code.

Або попросіть свого агента: "Встанови собі цей скіл" та дайте йому посилання на промпт.

## Передумови

- Claude Code
- `md2pdf` CLI (агент встановить автоматично якщо не знайде)
- `pdftoppm` з poppler (опціонально - для верифікації layout)

## Файли

| Файл | Опис |
|------|------|
| [prompt-ukr.md](./prompt-ukr.md) | Промпт скілу українською (для встановлення) |
| [prompt-eng.md](./prompt-eng.md) | Промпт скілу англійською |
| [md-to-pdf-guide-ukr.md](./md-to-pdf-guide-ukr.md) | Детальний гайд українською |
| [md-to-pdf-guide-eng.md](./md-to-pdf-guide-eng.md) | Детальний гайд англійською |
| [telegram-post.md](./telegram-post.md) | Текст Telegram посту |
