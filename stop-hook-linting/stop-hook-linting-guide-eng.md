# Stop Hook: Auto-Fix Lint & Type Errors Before AI Agent Finishes

## Problem

AI coding agents write code fast — but they also introduce bugs fast. A common scenario:

1. Agent writes new code or modifies existing files
2. Agent says "Done!" and stops
3. You discover TypeScript type errors, unused variables, or lint violations
4. You have to tell the agent to fix them manually

The worst part: the agent **doesn't know** it made mistakes until you point them out. There's no automatic quality gate.

## Solution

We use a **Stop hook** — a script that runs automatically every time the AI agent tries to finish its response. It acts as a quality gate:

1. **oxlint** — fast Rust-based linter (catches unused vars, eval, debugger, duplicate keys, etc.)
2. **tsc --noEmit** — TypeScript compiler in check-only mode (catches type mismatches, missing properties, wrong arguments)

If either tool finds new issues in the modified files, the hook **blocks the agent from stopping** and sends the errors back. The agent sees the errors, fixes them, and tries to stop again. This loop continues until all issues are resolved.

### What you get:

- **Zero TypeScript errors** committed — the agent fixes them before finishing
- **Cleaner code** — lint violations caught automatically
- **No manual review** for basic mistakes — type errors, unused imports, wrong return types
- **Works with new files too** — untracked files are included in the check

### What this does NOT catch:

- Logic errors (wrong algorithm, incorrect business logic)
- Runtime errors (API failures, network issues)
- Security vulnerabilities (SQL injection, XSS — use separate tools for that)

---

## Step 1: Install dependencies

### oxlint (fast linter)

```bash
npm install -D oxlint
```

Or install globally:

```bash
npm install -g oxlint
```

Verify:

```bash
npx oxlint --version
# 1.50.0 (or newer)
```

### jq (JSON parsing for hooks)

On macOS:

```bash
brew install jq
```

On Ubuntu/Debian:

```bash
sudo apt install jq
```

### TypeScript compiler

If you already have TypeScript in your project (you probably do):

```bash
npx tsc --version
# Version 5.x.x
```

---

## Step 2: Create the hook script

Create the file `.claude/hooks/lint-check.sh` in your **project root** (not the global `~/.claude/`):

```bash
mkdir -p .claude/hooks
```

File: `.claude/hooks/lint-check.sh`

```bash
#!/bin/bash
# Stop hook — runs oxlint + tsc type-checking on modified files
# Only blocks on NEW issues (before/after comparison for oxlint)
# Blocks on ANY type errors in modified files (tsc)

INPUT=$(cat)

PROJECT_DIR="$CLAUDE_PROJECT_DIR"
cd "$PROJECT_DIR" || exit 0

# ─── Collect all modified, unstaged, and NEW (untracked) .ts files ─────
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

# ─── Step 1: oxlint with before/after comparison ───────────────────────
# For each modified file, we compare oxlint output on the HEAD version
# vs the current version. Only NEW issues are reported.
# New (untracked) files have no HEAD version, so ALL their issues are "new".

TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

while IFS= read -r f; do
  mkdir -p "$TMPDIR/$(dirname "$f")"
  git show "HEAD:$f" > "$TMPDIR/$f" 2>/dev/null || true
done <<< "$ALL_FILES"

# Run oxlint on HEAD versions (baseline)
BEFORE_RAW=$(echo "$ALL_FILES" | while IFS= read -r f; do echo "$TMPDIR/$f"; done | xargs npx oxlint --format unix 2>/dev/null || true)

# Run oxlint on current versions
AFTER_RAW=$(echo "$ALL_FILES" | xargs npx oxlint --format unix 2>/dev/null || true)

# Normalize: strip temp dir prefix and line:col (lines shift when code changes)
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

# Find NEW issues only
NEW_ISSUES=$(comm -13 <(echo "$BEFORE_NORMALIZED") <(echo "$AFTER_NORMALIZED"))
NEW_ISSUES=$(echo "$NEW_ISSUES" | grep -v '^$' || true)

if [[ -n "$NEW_ISSUES" ]]; then
  ISSUE_COUNT=$(echo "$NEW_ISSUES" | wc -l | tr -d ' ')
  ERRORS="oxlint: $ISSUE_COUNT new issue(s) introduced:\n${NEW_ISSUES}"
fi

# ─── Step 2: tsc type-checking ────────────────────────────────────────
# Run tsc --noEmit and filter errors to only show those in modified files.
# Adjust the tsconfig path to match YOUR project structure.

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

# ─── Result ────────────────────────────────────────────────────────────
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

Make it executable:

```bash
chmod +x .claude/hooks/lint-check.sh
```

---

## Step 3: Configure Claude Code hooks

Create or update `.claude/settings.json` in your **project root**:

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

## Step 4: Adapt for Nx monorepo (optional)

If you use an **Nx monorepo** with multiple apps/libs (each with its own `tsconfig.app.json` or `tsconfig.lib.json`), replace the tsc step with this version that auto-detects affected projects:

```bash
# ─── Step 2: tsc type-checking per affected project (Nx monorepo) ─────
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

This iterates through each affected Nx project separately, using its own tsconfig.

---

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│         AI Agent finishes writing code → tries to stop       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Stop hook runs: lint-check.sh                               │
│                                                              │
│  1. Collect files:                                           │
│     ├─ git diff HEAD          → modified tracked files       │
│     ├─ git diff               → unstaged changes             │
│     └─ git ls-files --others  → NEW untracked files          │
│                                                              │
│  2. oxlint (before/after diff):                              │
│     ├─ Run on HEAD versions   → baseline issues              │
│     ├─ Run on current code    → current issues               │
│     └─ comm -13               → only NEW issues              │
│                                                              │
│  3. tsc --noEmit:                                            │
│     ├─ Full type check        → all type errors              │
│     └─ Filter by modified     → only errors in changed files │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  No errors? → exit 0 (agent stops normally)                  │
│                                                              │
│  Errors found? → {"decision":"block","reason":"..."}         │
│  ├─ Agent sees: "TS2322: Type 'string' not assignable..."    │
│  ├─ Agent FIXES the code                                     │
│  └─ Hook runs AGAIN → loop until clean                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Verification

After setup, start a new Claude Code session and ask:

> "Create a new file `test-hook.ts` with this code: `const num: number = 'hello'; export { num };`"

When the agent finishes writing the file and tries to stop, you should see the status line:

> "Checking linting & types..."

And the agent should **automatically fix** the type error before finishing.

After verification, delete the test file:

```bash
rm test-hook.ts
```

---

## What oxlint catches vs what tsc catches

Understanding the division of responsibility:

| Tool | What it catches | Speed | Needs type info? |
|------|----------------|-------|-----------------|
| **oxlint** | Unused variables, `eval()`, `debugger`, duplicate keys, constant conditions, empty patterns, `this` aliasing | ~40ms per file | No (AST only) |
| **tsc** | Type mismatches (`string` vs `number`), missing interface properties, wrong function arguments, return type errors | ~2-5s per project | Yes (full type resolution) |

**Important:** oxlint is NOT a TypeScript type checker. It's a fast linter that works on the AST (code structure) without understanding types. That's why both tools are needed together.

---

## Customization

### Adding more oxlint rules

By default, oxlint enables ~108 rules. Some useful rules are disabled by default. You can enable them:

```bash
# In the hook, change the oxlint command to:
npx oxlint --deny no-var --deny eqeqeq --deny no-console --format unix
```

### Adjusting timeout

If your project is large and tsc takes a long time, increase the timeout in `settings.json`:

```json
"timeout": 120
```

### Disabling for specific sessions

If you need to skip the check temporarily, you can rename the hook file:

```bash
mv .claude/hooks/lint-check.sh .claude/hooks/lint-check.sh.disabled
```

---

## Notes

- **oxlint** is ~50-100x faster than ESLint — it won't slow down your agent
- **tsc --noEmit** checks types without producing output files
- The hook only runs on **modified files** — it won't report pre-existing issues in untouched files
- For **new (untracked) files**, all issues are considered "new" and will be reported
- **Dependencies:** `jq` (JSON parsing), `oxlint` (linting), `typescript` (type checking)
- The before/after comparison for oxlint means you won't be blocked by pre-existing lint issues — only issues you introduced in this session
- This guide is for **TypeScript projects**. For other languages, replace oxlint + tsc with your language's linter and type checker (e.g., `clippy` + `cargo check` for Rust, `pylint` + `mypy` for Python)
