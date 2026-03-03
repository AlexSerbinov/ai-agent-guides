# Захист .env файлів від AI-агентів

## Проблема

AI coding-агенти (Claude Code, Codex, Cursor тощо) можуть напряму читати твій `.env` файл і бачити всі API-ключі, паролі та секрети. Навіть якщо агент не зливає їх навмисно — вони потрапляють у контекстне вікно, логи, і потенційно в тренувальні дані.

## Рішення

Ми будуємо захист у кілька шарів:

1. **Auto-генерація `.env.example`** — Stop-хук автоматично створює `.env.example` (ключі без значень) при завершенні кожної сесії
2. **Блокування читання `.env`** — PreToolUse хук + deny-правила забороняють агенту відкривати `.env`
3. **Інструкції агенту** — в CLAUDE.md / AGENTS.md пояснюємо: "читай `.env.example`, не `.env`"

Агент бачить **які змінні існують**, але **не бачить їх значень**.

---

## Крок 1: Встановити утиліту для генерації .env.example

```bash
npm install -g @nielse63/copy-env@1.1.0
```

Ця утиліта бере `.env`, видаляє значення після `=`, і зберігає результат як `.env.example`. [Репозиторій](https://github.com/nielse63/copy-env).

> **Про безпеку пакету:** бібліотека маловідома, але я провів повне security та malware сканування вихідного коду — нічого підозрілого не знайдено. Код тривіальний: використовує лише стандартні `fs` та `path`, без runtime-залежностей, без мережевих запитів, без `exec`/`spawn`, без деструктивних операцій. Єдина runtime-залежність — `commander` (стандартна CLI-бібліотека). Тим не менш, додатково раджу вам також самостійно просканувати пакет перед встановленням, якщо бажаєте.
>
> **Про версію:** в репозиторії налаштований `semantic-release`, який автоматично оновлює залежності та публікує нові версії. Це в цілому безпечно, але для додаткової впевненості команда вище фіксує конкретну версію `1.1.0`, яку я перевірив. Якщо хочете оновитись на новішу — спершу перегляньте changelog та diff змін.

Перевір що встановилось:

```bash
copy-env --version
# 1.1.0
```

---

## Крок 2: Налаштування для Claude Code

### 2.1. Stop-хук: автогенерація .env.example

Створи файл `~/.claude/hooks/generate-env-example.sh`:

```bash
#!/bin/bash
# Stop hook: auto-generates .env.example for every .env found in the project

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

if [ -n "$CWD" ]; then
  find "$CWD" -maxdepth 3 -name ".env" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" 2>/dev/null | while read -r envfile; do
    envdir=$(dirname "$envfile")
    copy-env --cwd "$envdir" --src .env --dest .env.example 2>/dev/null
  done
fi
```

Зроби його виконуваним:

```bash
chmod +x ~/.claude/hooks/generate-env-example.sh
```

### 2.2. PreToolUse хук: блокування читання .env

Створи файл `~/.claude/hooks/block-env-read.sh`:

```bash
#!/bin/bash
# PreToolUse hook: blocks reading .env files (but allows .env.example)
# Returns JSON with "decision":"block" to prevent tool execution

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // "{}"')

block() {
  echo "{\"decision\":\"block\",\"reason\":\"$1\"}"
  exit 0
}

# Check Read tool
if [ "$TOOL_NAME" = "Read" ]; then
  FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // ""')
  BASENAME=$(basename "$FILE_PATH")

  # Block .env but allow .env.example, .env.sample, .env.template
  if [[ "$BASENAME" == ".env" || "$BASENAME" =~ ^\.env\. && ! "$BASENAME" =~ \.(example|sample|template)$ ]]; then
    block "Reading .env files is blocked for security. Use .env.example instead — it contains all variable names without secret values."
  fi
fi

# Check Bash tool for commands that read .env
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // ""')

  # Block cat/head/tail/less/more/bat/sed/awk/grep reading .env files (but not .env.example)
  if echo "$COMMAND" | grep -qE '(cat|head|tail|less|more|bat|sed|awk|grep|rg|source|\.)\s+.*\.env(\s|$|")' && \
     ! echo "$COMMAND" | grep -qE '\.env\.(example|sample|template)'; then
    block "Reading .env files via shell is blocked for security. Use .env.example instead."
  fi
fi

# Allow everything else (no output = passthrough)
```

Зроби його виконуваним:

```bash
chmod +x ~/.claude/hooks/block-env-read.sh
```

### 2.3. Додай хуки та deny-правила в settings.json

Відкрий `~/.claude/settings.json` і додай/оновив наступні секції:

**Deny-правила** (в секцію `permissions`):

```json
"deny": [
  "Read(**/.env)",
  "Read(**/.env.local)",
  "Read(**/.env.development)",
  "Read(**/.env.production)",
  "Read(**/.env.staging)",
  "Read(.env)",
  "Read(.env.*)",
  "Read(**/.env.*)",
  "!Read(**/.env.example)",
  "!Read(**/.env.sample)",
  "!Read(**/.env.template)"
]
```

**Хуки** (в секцію `hooks`):

```json
"Stop": [
  {
    "matcher": "*",
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/generate-env-example.sh"
      }
    ]
  }
],
"PreToolUse": [
  {
    "matcher": "Read|Bash",
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/block-env-read.sh",
        "timeout": 5
      }
    ]
  }
]
```

### 2.4. Додай інструкцію в CLAUDE.md

Додай це в свій глобальний `~/.claude/CLAUDE.md`:

```markdown
# .env Security Policy

**Reading `.env` files is FORBIDDEN.** A PreToolUse hook and deny rules enforce this — any attempt to Read `.env` or `cat .env` will be blocked.

**Use `.env.example` instead.** It contains all variable names (keys) without secret values and is always kept in sync with the real `.env` via a Stop hook that auto-generates it using `copy-env`.

Rules:
- To check which environment variables exist → read `.env.example`
- To check if a specific variable is set → ask the user, do not attempt to read `.env`
- Never try to bypass this restriction (e.g., via `grep`, `sed`, `source`, or subshells)
- `.env.example` is auto-generated on every Claude Code session end and reflects the current `.env` structure
```

---

## Крок 3: Налаштування для Codex CLI

### 3.1. Скіл env-security

Створи директорію та файл `~/.codex/skills/env-security/SKILL.md`:

```bash
mkdir -p ~/.codex/skills/env-security
```

Вміст `SKILL.md`:

```markdown
---
name: env-security
description: Security policy for .env files. Prevents reading plaintext secrets from .env files. Always use .env.example instead — it contains variable names without values and is auto-generated.
metadata:
  short-description: Block .env reads, use .env.example
  always-loaded: true
---

# .env Security Policy

## Rule

**NEVER read `.env` files directly.** They contain plaintext API keys and secrets.

**Use `.env.example` instead.** It contains all variable names (keys) without secret values and is always kept in sync with the real `.env` automatically.

## What to do

- To check which environment variables exist → read `.env.example`
- To check if a specific variable is set → ask the user
- Never run: `cat .env`, `head .env`, `grep .env`, `source .env`, or any command that outputs `.env` contents

## Why

`.env.example` is auto-generated from `.env` on every coding session end. It always reflects the current structure. You get all the information you need (variable names) without exposing secrets.
```

### 3.2. Deny-правила для команд

Додай в `~/.codex/rules/default.rules`:

```
# === .env security: block reading secret files ===
prefix_rule(pattern=["cat", ".env"], decision="forbidden")
prefix_rule(pattern=["head", ".env"], decision="forbidden")
prefix_rule(pattern=["tail", ".env"], decision="forbidden")
prefix_rule(pattern=["less", ".env"], decision="forbidden")
prefix_rule(pattern=["more", ".env"], decision="forbidden")
prefix_rule(pattern=["bat", ".env"], decision="forbidden")
prefix_rule(pattern=["source", ".env"], decision="forbidden")
```

### 3.3. Додай інструкцію в AGENTS.md

Додай на початок `AGENTS.md` у корені проєкту:

```markdown
## .env Security Policy

**NEVER read `.env` files directly.** Reading `.env` is blocked by security hooks — use `.env.example` instead. It contains all variable names without secret values and is auto-generated from `.env` on every session end.

- To check which env variables exist → read `.env.example`
- To check if a variable has a value → ask the user
- Never run `cat .env`, `head .env`, `source .env` etc.
```

---

## Як це працює

```
┌─────────────────────────────────────────────────────────────┐
│                    AI Agent хоче прочитати .env              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Шар 1: permissions.deny / prefix_rule                      │
│  ├─ Claude Code: Read(**/.env) → BLOCKED                    │
│  └─ Codex: cat .env → DENIED                                │
│                                                             │
│  Шар 2: PreToolUse hook (Claude Code)                       │
│  ├─ Read .env → {"decision":"block"}                        │
│  └─ Bash "cat .env" → {"decision":"block"}                  │
│                                                             │
│  Шар 3: CLAUDE.md / AGENTS.md / Skill інструкції            │
│  └─ "Читай .env.example, не .env"                           │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Stop hook: при завершенні сесії                            │
│  └─ copy-env .env → .env.example (ключі без значень)        │
│                                                             │
│  Результат: агент бачить GOOGLE_API_KEY=                     │
│             але НЕ бачить GOOGLE_API_KEY=sk-abc123...        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Перевірка

Після налаштування запусти нову сесію Claude Code і спробуй:

```
> Прочитай файл .env
```

Очікуваний результат — агент отримає блок з повідомленням:
> "Reading .env files is blocked for security. Use .env.example instead."

---

## Примітки

- **Stop-хук генерує `.env.example`** для кожного `.env` файлу в проєкті (до 3 рівнів вкладеності), ігноруючи `node_modules` та `.git`
- **`.env.example` можна комітити** в репозиторій — він не містить секретів
- **Codex має слабший enforcement** ніж Claude Code: `prefix_rule` блокує лише конкретні команди, але не вбудований file read. Тому скіл з `always-loaded: true` — критично важливий
- **Залежність:** потрібен `jq` для парсингу JSON в хуках. На macOS: `brew install jq`
- **`@nielse63/copy-env`** — єдина залежність, встановлюється глобально через npm
