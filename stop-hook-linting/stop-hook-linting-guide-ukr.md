# Stop Hook: автоматичне виправлення помилок перед завершенням AI-агента

## Проблема

AI coding-агенти пишуть код швидко — але так само швидко вносять баги. Типовий сценарій:

1. Агент пише новий код або змінює існуючі файли
2. Агент каже "Готово!" і зупиняється
3. Ви знаходите TypeScript помилки типів, невикористані змінні або lint-порушення
4. Доводиться вручну просити агента виправити

Найгірше: агент **не знає**, що зробив помилки, поки ви не вкажете на них. Автоматичного контролю якості немає.

## Рішення

Використовуємо **Stop hook** — скрипт, що запускається автоматично кожного разу, коли AI-агент намагається завершити відповідь. Він працює як quality gate:

1. **oxlint** — швидкий Rust-based лінтер (ловить невикористані змінні, eval, debugger, дублікати ключів тощо)
2. **tsc --noEmit** — TypeScript компілятор в режимі перевірки (ловить помилки типів, відсутні поля, неправильні аргументи)

Якщо будь-який інструмент знаходить нові проблеми у змінених файлах, хук **блокує зупинку агента** і повертає помилки назад. Агент бачить помилки, виправляє їх і намагається зупинитись знову. Цей цикл продовжується, поки всі проблеми не будуть вирішені.

### Що ви отримаєте:

- **Нуль TypeScript помилок** — агент виправляє їх до завершення
- **Чистіший код** — lint-порушення ловляться автоматично
- **Без ручного ревʼю** базових помилок — помилки типів, невикористані імпорти, неправильні return-типи
- **Працює з новими файлами** — untracked файли також перевіряються

### Що це НЕ ловить:

- Логічні помилки (неправильний алгоритм, некоректна бізнес-логіка)
- Runtime помилки (падіння API, мережеві проблеми)
- Вразливості безпеки (SQL injection, XSS — використовуйте окремі інструменти)

---

## Крок 1: Встановіть залежності

### oxlint (швидкий лінтер)

```bash
npm install -D oxlint
```

Або глобально:

```bash
npm install -g oxlint
```

Перевірка:

```bash
npx oxlint --version
# 1.50.0 (або новіша)
```

### jq (парсинг JSON для хуків)

На macOS:

```bash
brew install jq
```

На Ubuntu/Debian:

```bash
sudo apt install jq
```

### TypeScript компілятор

Якщо TypeScript вже є у проекті (скоріш за все є):

```bash
npx tsc --version
# Version 5.x.x
```

---

## Крок 2: Створіть скрипт хука

Створіть файл `.claude/hooks/lint-check.sh` у **корені проекту** (не в глобальному `~/.claude/`):

```bash
mkdir -p .claude/hooks
```

Файл: `.claude/hooks/lint-check.sh`

```bash
#!/bin/bash
# Stop hook — запускає oxlint + tsc type-checking на змінених файлах
# Блокує тільки на НОВИХ проблемах (before/after порівняння для oxlint)
# Блокує на БУДЬ-ЯКИХ помилках типів у змінених файлах (tsc)

INPUT=$(cat)

PROJECT_DIR="$CLAUDE_PROJECT_DIR"
cd "$PROJECT_DIR" || exit 0

# ─── Збираємо всі змінені, unstaged та НОВІ (untracked) .ts файли ─────
MODIFIED_FILES=$(git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null | grep '\.ts$' || true)
UNSTAGED_FILES=$(git diff --name-only --diff-filter=ACMR 2>/dev/null | grep '\.ts$' || true)
UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null | grep '\.ts$' || true)

ALL_FILES=$(echo -e "$MODIFIED_FILES\n$UNSTAGED_FILES\n$UNTRACKED_FILES" | sort -u | grep -v '^$' || true)

if [[ -z "$ALL_FILES" ]]; then
  echo "No TypeScript files modified - skipping lint check" >&2
  exit 0
fi

FILE_COUNT=$(echo "$ALL_FILES" | wc -l | tr -d ' ')
echo "Checking $FILE_COUNT modified files..." >&2

ERRORS=""

# ─── Крок 1: oxlint з before/after порівнянням ────────────────────────
# Для кожного зміненого файлу порівнюємо oxlint output на HEAD версії
# з поточною версією. Повідомляються тільки НОВІ проблеми.
# Нові (untracked) файли не мають HEAD версії — всі їх проблеми "нові".

TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

while IFS= read -r f; do
  mkdir -p "$TMPDIR/$(dirname "$f")"
  git show "HEAD:$f" > "$TMPDIR/$f" 2>/dev/null || true
done <<< "$ALL_FILES"

# oxlint на HEAD версіях (baseline)
BEFORE_RAW=$(echo "$ALL_FILES" | while IFS= read -r f; do echo "$TMPDIR/$f"; done | xargs npx oxlint --format unix 2>/dev/null || true)

# oxlint на поточних версіях
AFTER_RAW=$(echo "$ALL_FILES" | xargs npx oxlint --format unix 2>/dev/null || true)

# Нормалізація: прибираємо temp dir prefix та line:col
normalize_oxlint() {
  local prefix="$1"
  if [[ -n "$prefix" ]]; then
    sed "s|^${prefix}/||"
  else
    cat
  fi | grep -E '^\S+\.ts:[0-9]+:[0-9]+:' | sed -E 's/^([^:]+):[0-9]+:[0-9]+:/\1:/' | sort
}

BEFORE_NORMALIZED=$(echo "$BEFORE_RAW" | normalize_oxlint "$TMPDIR")
AFTER_NORMALIZED=$(echo "$AFTER_RAW" | normalize_oxlint "")

# Знаходимо тільки НОВІ проблеми
NEW_ISSUES=$(comm -13 <(echo "$BEFORE_NORMALIZED") <(echo "$AFTER_NORMALIZED"))
NEW_ISSUES=$(echo "$NEW_ISSUES" | grep -v '^$' || true)

if [[ -n "$NEW_ISSUES" ]]; then
  ISSUE_COUNT=$(echo "$NEW_ISSUES" | wc -l | tr -d ' ')
  ERRORS="oxlint: $ISSUE_COUNT new issue(s) introduced:\n${NEW_ISSUES}"
fi

# ─── Крок 2: tsc type-checking ────────────────────────────────────────
# Запускаємо tsc --noEmit і фільтруємо помилки тільки у змінених файлах.
# Адаптуйте шлях до tsconfig під ВАШУ структуру проекту.

TSCONFIG="tsconfig.json"
if [[ ! -f "$TSCONFIG" ]]; then
  TSCONFIG="tsconfig.app.json"
fi

if [[ -f "$TSCONFIG" ]]; then
  TSC_OUTPUT=$(npx tsc -p "$TSCONFIG" --noEmit 2>&1)
  TSC_EXIT=$?

  if [[ $TSC_EXIT -ne 0 ]]; then
    FILTERED_TSC=""
    while IFS= read -r file; do
      FILE_ERRORS=$(echo "$TSC_OUTPUT" | grep "$file" || true)
      if [[ -n "$FILE_ERRORS" ]]; then
        FILTERED_TSC="${FILTERED_TSC}\n${FILE_ERRORS}"
      fi
    done <<< "$ALL_FILES"

    if [[ -n "$FILTERED_TSC" ]]; then
      if [[ -n "$ERRORS" ]]; then
        ERRORS="${ERRORS}\n\n"
      fi
      ERRORS="${ERRORS}TypeScript type errors:\n${FILTERED_TSC}"
    fi
  fi
fi

# ─── Результат ─────────────────────────────────────────────────────────
if [[ -z "$ERRORS" ]]; then
  echo "All checks passed (oxlint + tsc)" >&2
  exit 0
fi

echo "Linting/type errors found - blocking" >&2

jq -n \
  --arg reason "$(echo -e "$ERRORS")" \
  '{decision: "block", reason: $reason}'

exit 0
```

Зробіть його виконуваним:

```bash
chmod +x .claude/hooks/lint-check.sh
```

---

## Крок 3: Налаштуйте хуки Claude Code

Створіть або оновіть `.claude/settings.json` у **корені проекту**:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/lint-check.sh",
            "timeout": 60,
            "statusMessage": "Checking linting & types..."
          }
        ]
      }
    ]
  }
}
```

---

## Крок 4: Адаптація для Nx монорепо (опціонально)

Якщо ви використовуєте **Nx монорепо** з кількома apps/libs (кожен зі своїм `tsconfig.app.json` або `tsconfig.lib.json`), замініть tsc-крок на цю версію, яка автоматично визначає зачеплені проекти:

```bash
# ─── Крок 2: tsc type-checking per affected project (Nx monorepo) ─────
AFFECTED_PROJECTS=$(echo "$ALL_FILES" | grep -oE '^(apps|libs)/[^/]+' | sort -u || true)

for project in $AFFECTED_PROJECTS; do
  TSCONFIG="$project/tsconfig.app.json"
  if [[ ! -f "$TSCONFIG" ]]; then
    TSCONFIG="$project/tsconfig.lib.json"
  fi
  if [[ ! -f "$TSCONFIG" ]]; then
    continue
  fi

  TSC_OUTPUT=$(npx tsc -p "$TSCONFIG" --noEmit 2>&1)
  TSC_EXIT=$?

  if [[ $TSC_EXIT -ne 0 ]]; then
    FILTERED_TSC=""
    while IFS= read -r file; do
      FILE_ERRORS=$(echo "$TSC_OUTPUT" | grep "$file" || true)
      if [[ -n "$FILE_ERRORS" ]]; then
        FILTERED_TSC="${FILTERED_TSC}\n${FILE_ERRORS}"
      fi
    done <<< "$ALL_FILES"

    if [[ -n "$FILTERED_TSC" ]]; then
      if [[ -n "$ERRORS" ]]; then
        ERRORS="${ERRORS}\n\n"
      fi
      ERRORS="${ERRORS}TypeScript type errors in $project:\n${FILTERED_TSC}"
    fi
  fi
done
```

---

## Як це працює

```
┌─────────────────────────────────────────────────────────────┐
│   AI-агент завершив писати код → намагається зупинитись      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Stop hook запускається: lint-check.sh                       │
│                                                              │
│  1. Збирає файли:                                            │
│     ├─ git diff HEAD          → змінені tracked файли        │
│     ├─ git diff               → unstaged зміни               │
│     └─ git ls-files --others  → НОВІ untracked файли         │
│                                                              │
│  2. oxlint (before/after diff):                              │
│     ├─ На HEAD версіях        → baseline проблеми            │
│     ├─ На поточному коді      → поточні проблеми             │
│     └─ comm -13               → тільки НОВІ проблеми         │
│                                                              │
│  3. tsc --noEmit:                                            │
│     ├─ Повна перевірка типів  → всі помилки типів            │
│     └─ Фільтр по змінених     → тільки в змінених файлах     │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Немає помилок? → exit 0 (агент зупиняється нормально)       │
│                                                              │
│  Є помилки? → {"decision":"block","reason":"..."}            │
│  ├─ Агент бачить: "TS2322: Type 'string' not assignable..."  │
│  ├─ Агент ВИПРАВЛЯЄ код                                      │
│  └─ Хук запускається ЗНОВУ → цикл поки код не чистий         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Перевірка

Після налаштування запустіть нову сесію Claude Code і попросіть:

> "Створи новий файл `test-hook.ts` з кодом: `const num: number = 'hello'; export { num };`"

Коли агент закінчить писати файл і спробує зупинитись, ви побачите в статусі:

> "Checking linting & types..."

І агент повинен **автоматично виправити** помилку типу перед завершенням.

Після перевірки видаліть тестовий файл:

```bash
rm test-hook.ts
```

---

## Що ловить oxlint vs що ловить tsc

Розподіл відповідальності:

| Інструмент | Що ловить | Швидкість | Потрібна інфо про типи? |
|-----------|----------|-----------|------------------------|
| **oxlint** | Невикористані змінні, `eval()`, `debugger`, дублікати ключів, константні умови, аліасинг `this` | ~40мс на файл | Ні (тільки AST) |
| **tsc** | Невідповідність типів (`string` vs `number`), відсутні поля інтерфейсів, неправильні аргументи, помилки return-типів | ~2-5с на проект | Так (повний type resolution) |

**Важливо:** oxlint — це НЕ TypeScript type checker. Це швидкий лінтер, що працює на AST (структурі коду) без розуміння типів. Тому потрібні обидва інструменти разом.

---

## Кастомізація

### Додавання правил oxlint

За замовчуванням oxlint вмикає ~108 правил. Деякі корисні правила вимкнені. Можна їх увімкнути:

```bash
# В хуці змініть команду oxlint на:
npx oxlint --deny no-var --deny eqeqeq --deny no-console --format unix
```

### Збільшення таймауту

Якщо проект великий і tsc працює довго, збільште таймаут у `settings.json`:

```json
"timeout": 120
```

### Тимчасове вимкнення

Якщо потрібно пропустити перевірку:

```bash
mv .claude/hooks/lint-check.sh .claude/hooks/lint-check.sh.disabled
```

---

## Примітки

- **oxlint** в ~50-100 разів швидший за ESLint — він не уповільнить агента
- **tsc --noEmit** перевіряє типи без створення файлів
- Хук працює тільки на **змінених файлах** — він не буде повідомляти про проблеми в незмінених файлах
- Для **нових (untracked) файлів** всі проблеми вважаються "новими" і будуть показані
- **Залежності:** `jq` (парсинг JSON), `oxlint` (лінтинг), `typescript` (перевірка типів)
- Before/after порівняння для oxlint означає, що вас не заблокують через вже існуючі lint-проблеми — тільки проблеми, які ви внесли в цій сесії
- Цей гайд для **TypeScript проектів**. Для інших мов замініть oxlint + tsc на лінтер та type checker вашої мови (наприклад, `clippy` + `cargo check` для Rust, `pylint` + `mypy` для Python)
