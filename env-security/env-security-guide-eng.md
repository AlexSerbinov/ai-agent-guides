# Protecting .env Files from AI Agents

## Problem

AI coding agents (Claude Code, Codex, Cursor, etc.) can directly read your `.env` file and see all API keys, passwords, and secrets. Even if the agent doesn't leak them intentionally, they end up in the context window, logs, and potentially in training data.

## Solution

We build protection in multiple layers:

1. **Auto-generate `.env.example`** — a Stop hook automatically creates `.env.example` (keys without values) at the end of every session
2. **Block `.env` reads** — PreToolUse hook + deny rules prevent the agent from opening `.env`
3. **Agent instructions** — in CLAUDE.md / AGENTS.md we tell the agent: "read `.env.example`, not `.env`"

The agent sees **which variables exist** but **never sees their values**.

---

## Step 1: The script that keeps .env.example current

### 🚨 The trap first: .env.example generators DELETE other people's keys

The obvious approach is an off-the-shelf utility (`@nielse63/copy-env` and friends) that reads `.env`, strips the values after `=`, and saves the result as `.env.example`. That is what I did originally, and that is exactly where the trap is.

**These utilities do not merge — they OVERWRITE.** `.env.example` is regenerated strictly from whatever sits in your local `.env`. Anything this machine does not happen to have silently disappears from the file.

And what is missing locally is usually the interesting part:

- keys that only live in GitHub Secrets or in production (partner refcodes, payment tokens);
- variables a colleague added that have not reached your local `.env` yet;
- **the comments** documenting each of those keys: where to obtain it, why it is empty, what breaks without it.

This is not hypothetical. On a production project it wiped 8 affiliate keys three separate times (`FIXED_FLOAT_REFCODE`, `SWAPGATE_REFERRER_ID`, `BITCOINVN_REFERRER` and others) — precisely the ones our commission payouts depended on. Each time it went unnoticed for a while and was patched with a `chore: restore .env.example entries` commit. The cause only surfaced once someone matched the timing against the Stop hook: it ran **after every agent session** and neatly trimmed everything "extra".

The sneaky part is that such an overwrite looks innocent in a git diff: lines are gone, but nobody "deleted" anything — the file was merely "regenerated".

### The fix: merge instead of overwrite

Replace the external utility with a small script that follows a single rule: **appending is allowed, deleting never is.**

What it does:

- reads key names from `.env` (it never reads or writes values — same security posture);
- appends to `.env.example` only the keys that are not there yet;
- **deletes nothing** — existing keys, ordering and comments stay untouched;
- treats commented-out lines (`# OPTIONAL_KEY=`) as documented and does not resurrect them;
- is idempotent: run it any number of times, no duplicates.

Create `~/.claude/hooks/merge-env-example.sh` ([ready-made file](scripts/merge-env-example.sh)):

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

Make it executable:

```bash
chmod +x ~/.claude/hooks/merge-env-example.sh
```

New keys land at the end of the file under a dated heading on purpose: it is immediately visible that they arrived automatically and still need a human comment explaining what they are and where to get them.

---

## Step 2: Setup for Claude Code

### 2.1. Stop hook: refresh .env.example after every session

Create file `~/.claude/hooks/generate-env-example.sh`:

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

Make it executable:

```bash
chmod +x ~/.claude/hooks/generate-env-example.sh
```

> ⚠️ If you followed an earlier version of this guide that used `copy-env` — check `git log -p -- .env.example` in your projects. Keys have quite possibly already vanished from it without anyone noticing.

### 2.2. PreToolUse hook: block .env reads

Create file `~/.claude/hooks/block-env-read.sh`:

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

Make it executable:

```bash
chmod +x ~/.claude/hooks/block-env-read.sh
```

### 2.3. Add hooks and deny rules to settings.json

Open `~/.claude/settings.json` and add/update the following sections:

**Deny rules** (in the `permissions` section):

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

**Hooks** (in the `hooks` section):

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

### 2.4. Add instructions to CLAUDE.md

Add this to your global `~/.claude/CLAUDE.md`:

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

## Step 3: Setup for Codex CLI

### 3.1. env-security skill

Create the directory and file `~/.codex/skills/env-security/SKILL.md`:

```bash
mkdir -p ~/.codex/skills/env-security
```

Contents of `SKILL.md`:

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

### 3.2. Deny rules for commands

Add to `~/.codex/rules/default.rules`:

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

### 3.3. Add instructions to AGENTS.md

Add to the top of `AGENTS.md` in your project root:

```markdown
## .env Security Policy

**NEVER read `.env` files directly.** Reading `.env` is blocked by security hooks — use `.env.example` instead. It contains all variable names without secret values and is auto-generated from `.env` on every session end.

- To check which env variables exist → read `.env.example`
- To check if a variable has a value → ask the user
- Never run `cat .env`, `head .env`, `source .env` etc.
```

---

## How it works

```
┌─────────────────────────────────────────────────────────────┐
│               AI Agent wants to read .env                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Layer 1: permissions.deny / prefix_rule                    │
│  ├─ Claude Code: Read(**/.env) → BLOCKED                    │
│  └─ Codex: cat .env → FORBIDDEN                             │
│                                                             │
│  Layer 2: PreToolUse hook (Claude Code)                     │
│  ├─ Read .env → {"decision":"block"}                        │
│  └─ Bash "cat .env" → {"decision":"block"}                  │
│                                                             │
│  Layer 3: CLAUDE.md / AGENTS.md / Skill instructions        │
│  └─ "Read .env.example, not .env"                           │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Stop hook: on session end                                  │
│  └─ merge .env → .env.example (appends new keys only,       │
│     never deletes, never writes values)                      │
│                                                             │
│  Result: agent sees GOOGLE_API_KEY=                          │
│          but NOT GOOGLE_API_KEY=sk-abc123...                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Verification

After setup, start a new Claude Code session and try:

```
> Read the .env file
```

Expected result — the agent receives a block with the message:
> "Reading .env files is blocked for security. Use .env.example instead."

---

## Notes

- **The Stop hook generates `.env.example`** for every `.env` file in the project (up to 3 levels deep), ignoring `node_modules` and `.git`
- **`.env.example` can be committed** to the repository — it contains no secrets
- **Codex has weaker enforcement** than Claude Code: `prefix_rule` only blocks specific commands, not the built-in file read. That's why the skill with `always-loaded: true` is critical
- **Dependency:** `jq` is required for JSON parsing in hooks. On macOS: `brew install jq`
- **No external dependency** for generation — `merge-env-example.sh` is plain bash. Off-the-shelf utilities (`@nielse63/copy-env` and friends) are deliberately avoided: they overwrite `.env.example` and delete keys that are not present locally (see Step 1)
