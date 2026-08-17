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

## Крок 1: Скрипт, який тримає .env.example в актуальному стані

### 🚨 Спершу про граблі: генератори .env.example ВИДАЛЯЮТЬ чужі ключі

Найочевидніший шлях — взяти готову утиліту (`@nielse63/copy-env` та подібні), яка бере `.env`, зрізає значення після `=` і зберігає як `.env.example`. Я сам так робив, і саме тут ховається пастка.

**Ці утиліти не мержать, вони ПЕРЕЗАПИСУЮТЬ.** `.env.example` щоразу генерується строго з того, що лежить у твоєму локальному `.env`. Наслідок: усе, чого на цій машині немає, тихо зникає з файлу.

А немає там зазвичай найцікавішого:

- ключів, які живуть тільки в GitHub Secrets / на проді (партнерські refcode-и, платіжні токени);
- змінних, які додав колега і які ще не доїхали до твого локального `.env`;
- **коментарів**, що пояснювали кожен такий ключ: де його взяти, чому він порожній, що зламається без нього.

І це не теорія. У бойовому проєкті так тричі зникали 8 партнерських ключів (`FIXED_FLOAT_REFCODE`, `SWAPGATE_REFERRER_ID`, `BITCOINVN_REFERRER` тощо) — тих самих, від яких залежало нарахування комісії. Кожного разу це помічали не одразу і лікували окремим комітом `chore: restore .env.example entries`. Причину знайшли лише тоді, коли зіставили час зникнення з Stop-хуком: хук відпрацьовував **після кожної сесії агента** і акуратно вирізав усе зайве.

Окремо підступність у тому, що git-diff такого перезапису виглядає невинно: рядки зникли — але ж ніхто ж не «видаляв», просто файл «згенерувався».

### Рішення: merge замість overwrite

Замість зовнішньої утиліти — маленький скрипт, який дотримується одного правила: **дописувати можна, видаляти не можна ніколи**.

Що робить:

- бере імена ключів з `.env` (значення не читає й не пише — безпека та сама);
- дописує в кінець `.env.example` тільки ті, яких там ще немає;
- **нічого не видаляє** — існуючі ключі, порядок і коментарі лишаються недоторканими;
- закоментовані рядки (`# OPTIONAL_KEY=`) вважає задокументованими і не воскрешає;
- ідемпотентний: скільки б разів не запустився — дублікатів не наплодить.

Створи `~/.claude/hooks/merge-env-example.sh` ([готовий файл](scripts/merge-env-example.sh)):

```bash
#!/bin/bash
# Keep .env.example in sync with .env WITHOUT ever losing what is already there.
# Appends missing keys only; never deletes lines, never touches comments,
# never writes values.
#
# Usage: merge-env-example.sh <dir-containing-.env>

set -uo pipefail

dir="${1:?usage: merge-env-example.sh <dir>}"
env_file="$dir/.env"
example_file="$dir/.env.example"

[ -f "$env_file" ] || exit 0

# Key names present in .env, in file order. Accepts optional `export ` prefix.
env_keys=$(grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$env_file" 2>/dev/null \
  | sed -E 's/^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/')

[ -n "$env_keys" ] || exit 0

if [ ! -f "$example_file" ]; then
  # First run: nothing to preserve, so a plain listing is safe.
  printf '%s=\n' $env_keys > "$example_file"
  exit 0
fi

# Keys already documented — commented-out ones count too, so a deliberately
# disabled `# OPTIONAL_KEY=` is not re-added as if it were missing.
existing_keys=$(grep -E '^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' "$example_file" 2>/dev/null \
  | sed -E 's/^[[:space:]]*#?[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=.*/\2/')

missing=""
for key in $env_keys; do
  if ! printf '%s\n' $existing_keys | grep -qx -- "$key"; then
    case " $missing " in
      *" $key "*) ;;                 # already queued (duplicate in .env)
      *) missing="$missing $key" ;;
    esac
  fi
done

[ -n "${missing// /}" ] || exit 0

# Append under a dated heading so it is obvious these arrived automatically and
# still need a human comment explaining what they are for.
{
  printf '\n# --- added automatically %s (document these) ---\n' "$(date +%Y-%m-%d)"
  for key in $missing; do printf '%s=\n' "$key"; done
} >> "$example_file"
```

Зроби виконуваним:

```bash
chmod +x ~/.claude/hooks/merge-env-example.sh
```

Нові ключі падають у кінець файлу під датованим заголовком — це навмисно: одразу видно, що приїхало автоматично і ще чекає людського коментаря «що це і де взяти».

---

## Крок 2: Налаштування для Claude Code

### 2.1. Stop-хук: оновлення .env.example після кожної сесії

Створи файл `~/.claude/hooks/generate-env-example.sh`:

```bash
#!/bin/bash
# Stop hook: keeps .env.example in sync for every .env found in the project.
# Uses a MERGE (see Step 1) — appends missing keys, never deletes anything.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

if [ -n "$CWD" ]; then
  find "$CWD" -maxdepth 3 -name ".env" \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" 2>/dev/null | while read -r envfile; do
    "$HOME/.claude/hooks/merge-env-example.sh" "$(dirname "$envfile")" 2>/dev/null
  done
fi
```

Зроби його виконуваним:

```bash
chmod +x ~/.claude/hooks/generate-env-example.sh
```

> ⚠️ Якщо ти вже користувався попередньою версією цього гайда з `copy-env` — перевір `git log -p -- .env.example` у своїх проєктах. Цілком імовірно, що звідти вже зникли ключі, і ніхто цього не помітив.

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

**Use `.env.example` instead.** It contains all variable names (keys) without secret values and is kept in sync with the real `.env` by a Stop hook that MERGES new keys into it (it appends only — it never deletes keys or comments, so entries that exist solely in production or in a colleague's `.env` survive).

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
│  └─ merge .env → .env.example (дописує нові ключі,          │
│     нічого не видаляє, значень не пише)                     │
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
- **Жодних зовнішніх залежностей** для генерації — `merge-env-example.sh` це чистий bash. Готові утиліти (`@nielse63/copy-env` тощо) свідомо не використовуються: вони перезаписують `.env.example` і видаляють ключі, яких нема локально (див. Крок 1)
