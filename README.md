# AI Agent Guides

Збірка практичних інструкцій для безпечної та ефективної роботи з AI coding-агентами.

Кожен гайд — це готова інструкція, яку можна дати своєму AI-агенту, і він все налаштує сам.

## Гайди

| Гайд | Опис | Агенти |
|------|------|--------|
| [Protecting .env files (EN)](./env-security/env-security-guide-eng.md) | Block AI agents from reading `.env` files with secrets. Auto-generate `.env.example`. | Claude Code, Codex CLI |
| [Захист .env файлів (UA)](./env-security/env-security-guide-ukr.md) | Заборона AI-агентам читати `.env` файли з секретами. Автогенерація `.env.example`. | Claude Code, Codex CLI |
| [Changelog & Daily Report (EN)](./changelog-reports/changelog-reports-guide-eng.md) | Auto-maintain changelog and daily reports after every task. Blocking requirement — agent can't finish without logging. | Claude Code |
| [Changelog & Daily Report (UA)](./changelog-reports/changelog-reports-guide-ukr.md) | Автоматичне ведення changelog та daily report після кожної задачі. Blocking — агент не може завершити без логування. | Claude Code |
| [Stop Hook: Lint & Type Check (EN)](./stop-hook-linting/stop-hook-linting-guide-eng.md) | Auto-fix TypeScript type errors and lint violations before AI agent finishes. Uses oxlint + tsc as a quality gate. | Claude Code |
| [Stop Hook: Lint & Type Check (UA)](./stop-hook-linting/stop-hook-linting-guide-ukr.md) | Автоматичне виправлення TypeScript помилок типів та lint-порушень перед завершенням агента. oxlint + tsc як quality gate. | Claude Code |
| [Review Loop: Multi-Agent Code Review (EN)](./review-loop/review-loop-guide-eng.md) | Iterative code review with 6 parallel agents (4 Claude + 1 Codex + 1 Gemini). Auto-fixes issues, loops until quality >= 95%. | Claude Code, Codex CLI, Gemini CLI |
| [Review Loop: мультиагентне код-рев'ю (UA)](./review-loop/review-loop-guide-ukr.md) | Ітеративне код-рев'ю з 6 паралельними агентами (4 Claude + 1 Codex + 1 Gemini). Авто-фіксить проблеми, крутить цикл поки якість >= 95%. | Claude Code, Codex CLI, Gemini CLI |
| [Markdown to PDF (EN)](./md-to-pdf/md-to-pdf-guide-eng.md) | Convert Markdown files to high-quality PDFs with a single command. Layout verification, smart edge cases, CSS page-break control. | Claude Code |
| [Markdown to PDF (UA)](./md-to-pdf/md-to-pdf-guide-ukr.md) | Конвертація Markdown файлів у високоякісні PDF однією командою. Верифікація layout, розумні edge cases, CSS page-break контроль. | Claude Code |

## Як користуватись

1. Відкрий потрібний гайд
2. Скопіюй інструкцію
3. Дай її своєму AI-агенту (Claude Code, Codex, тощо)
4. Агент все налаштує сам

## Ліцензія

MIT
