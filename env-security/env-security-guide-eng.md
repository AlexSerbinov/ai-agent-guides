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

## Step 1: Install the utility for generating .env.example

```bash
npm install -g @nielse63/copy-env@1.1.0
```

This utility takes `.env`, strips values after `=`, and saves the result as `.env.example`. [Repository](https://github.com/nielse63/copy-env).

> **Security note:** this is a lesser-known library, but I performed a full security and malware scan of the source code — nothing suspicious was found. The code is trivial: it only uses standard `fs` and `path`, no runtime dependencies, no network requests, no `exec`/`spawn`, no destructive operations. The only runtime dependency is `commander` (a standard CLI library). That said, I recommend you also scan the package yourself before installing if you wish.
>
> **Version note:** the repository has `semantic-release` configured, which automatically updates dependencies and publishes new versions. This is generally safe, but for extra confidence the command above pins version `1.1.0`, which I have reviewed. If you want to update to a newer version — review the changelog and diff first.

Verify the installation:

```bash
copy-env --version
# 1.1.0
```

---

## Step 2: Setup for Claude Code

### 2.1. Stop hook: auto-generate .env.example

Create file `~/.claude/hooks/generate-env-example.sh`:

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

Make it executable:

```bash
chmod +x ~/.claude/hooks/generate-env-example.sh
```

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

**Use `.env.example` instead.** It contains all variable names (keys) without secret values and is always kept in sync with the real `.env` via a Stop hook that auto-generates it using `copy-env`.

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
│  └─ copy-env .env → .env.example (keys without values)      │
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
- **`@nielse63/copy-env`** is the only dependency, installed globally via npm
