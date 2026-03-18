# Automatic Changelog & Daily Report with Claude Code

## What is this and why?

When working with an AI coding agent, it handles many tasks per day — fixing bugs, adding features, refactoring. But without logging, you lose context: what exactly was done, what problem was solved, and why that approach was chosen.

This instruction forces Claude Code to **automatically maintain two log files** after every task:

- **Changelog** (`changelog.md`) — detailed journal with problem description, solution, and details
- **Daily Report** (`docs/reports/YYYY-MM-DD-daily-report.md`) — short daily standup-style summary

Claude Code **cannot finish a task** without writing to both files — it's a blocking requirement.

### What you get:
- **PM** sees what's happening on the project without asking the developer
- **Developer** has a complete log — easy to recall what was done and when
- **Team** has a shared changelog — fewer conflicts, everyone stays in context
- **Standups** become easier — the daily report is already written

---

## How to set up

There are two ways:

### Way 1: Automatic (give this instruction to Claude Code)

Just tell Claude Code:

> "Set up automatic logging to changelog and daily report. Here's the instruction: [paste URL of this file or copy Step 1 and Step 2 below]"

Claude Code will create/update `~/.claude/CLAUDE.md` with the required prompt itself.

### Way 2: Manual

Copy the prompt from Step 1 below into `~/.claude/CLAUDE.md`.

---

## Step 1: Add the prompt to Claude Code global config

File: `~/.claude/CLAUDE.md`

If the file doesn't exist yet — create it:

```bash
mkdir -p ~/.claude
touch ~/.claude/CLAUDE.md
```

Add the following section to this file:

````markdown
## End of Task Routine (Logging) — BLOCKING REQUIREMENT

**CRITICAL:** You CANNOT finish a task until you update **BOTH** log files below. This is not optional — it's a mandatory step for completing every task. If you finished a task without updating changelog and daily report — that's an error.

**Checklist before finishing a task (every time, no exceptions):**
- [ ] Wrote to `changelog.md`
- [ ] Wrote to `docs/reports/YYYY-MM-DD-daily-report.md`
- [ ] Only then finish the response

You (the main agent) do this, not a subagent — because you have the full conversation context and understand the business task.

**What to write:** Focus on **business context** — what problem was solved, what task the user described, what the outcome is. Not "changed file X", but "fixed USDT swaps failing because we sent ticker without network".

### 1. Changelog — MANDATORY

File: `changelog.md` in the project root (or wherever it already exists in the project).

**Entry format — detailed problem and solution description:**

```
## YYYY-MM-DD HH:MM — ProjectName

**Problem:** Describe in detail what the problem was — what wasn't working, how it manifested, why it mattered. 1-2 sentences.

**Solution:** What exactly was done to resolve it — what approach was chosen, what changed, what the result is. 1-3 sentences.

**Details:** Additional nuances — which files/modules were affected, does it impact frontend or other services, edge cases. Optional.
```

**Changelog rules:**
- Each entry is a separate `##` block with date, time, and project name
- Write in **business language** — not "changed file X", but "USDT swaps were failing because we sent ticker without network"
- **New task** → new `##` block
- **Continuation/follow-up** of the same task → **add a new `##` block** noting it's an update. Don't edit the previous entry — append a new one to maintain change history
- If the file doesn't exist — create it with the heading `# Changelog`

**Example:**

```markdown
## 2026-03-18 14:35 — MyProject

**Problem:** Changee provider was returning an error when creating a USDT order. Users couldn't swap USDT to any other cryptocurrency through this provider.

**Solution:** Found that we were sending the ticker "USDT" without specifying the network. Changee API requires the format "USDT-TRC20". Added network mapping in the Changee adapter.

**Details:** Affected changee.adapter.ts. Impacts frontend — the response now includes a network field in the currency object.

---

## 2026-03-18 15:20 — MyProject

**Update to previous task (Changee USDT mapping):** Added mapping for USDC and DAI as well — same issue. Also added unit tests for all network mappings.
```

### 2. Daily Report — MANDATORY

File: `docs/reports/YYYY-MM-DD-daily-report.md` in the project directory.

```markdown
# Report for DD.MM.YYYY

**Summary:**
- What was done (business language, standup-style)
- Another thing done
```

- One file per day, appended throughout the day
- Bullet points, informal style
- **New task** → new bullet point
- **Follow-up on existing task** → update the existing bullet point (don't create a new one, modify the text)
````

---

## Step 2: Verify it works

After adding the prompt to `~/.claude/CLAUDE.md`, just give Claude Code any task. At the end it should:

1. Create/update `changelog.md` in the project root
2. Create/update `docs/reports/YYYY-MM-DD-daily-report.md`
3. Only then finish the response

If it doesn't — remind it: "You forgot to update the changelog and daily report".

---

## File structure after setup

```
~/.claude/CLAUDE.md              ← Your global config (one for all projects)

your-project/
├── changelog.md                           ← Detailed change journal (automatic)
├── docs/
│   └── reports/
│       ├── 2026-03-17-daily-report.md     ← Yesterday's report
│       └── 2026-03-18-daily-report.md     ← Today's report
```

---

## FAQ

**Q: Do I need to create `changelog.md` manually?**
A: No, Claude Code will create it automatically on the first task.

**Q: What if I work on multiple projects?**
A: `~/.claude/CLAUDE.md` is global — it applies to all projects. Changelog and daily report are created in each project root separately.

**Q: My colleague also maintains the changelog — won't there be conflicts?**
A: Each entry is a separate `##` block. Git merge conflicts are unlikely since entries are always appended at the end of the file.

**Q: Can I change the format?**
A: Yes, the prompt is fully under your control. Change the format in `~/.claude/CLAUDE.md` however you like.

**Q: Does this work only with Claude Code?**
A: This prompt is written for Claude Code (`~/.claude/CLAUDE.md`), but the concept can be adapted for other AI agents — just place a similar instruction in their config file (`.cursorrules` for Cursor, `AGENTS.md` for Codex CLI).

## Compatible agents

| Agent | Config file | Status |
|-------|------------|--------|
| Claude Code | `~/.claude/CLAUDE.md` | Full support |
| Cursor | `.cursorrules` | Needs prompt adaptation |
| Codex CLI | `AGENTS.md` | Needs prompt adaptation |
