# Review Loop: Iterative Multi-Agent Code Review for Claude Code

## What is this and why?

AI coding agents write code fast — but who reviews the reviewer? When an AI agent finishes a task, you're left manually checking for bugs, security issues, and architectural problems. That's slow and defeats the purpose of AI-assisted development.

**Review Loop** solves this by running **6 parallel review agents** against your uncommitted changes:

| # | Agent | Tool | Focus |
|---|-------|------|-------|
| 1 | General Review #1 | Claude Code | Bugs, logic errors, edge cases |
| 2 | General Review #2 | Claude Code | Independent second opinion |
| 3 | Breaking Changes | Claude Code | API contracts, regressions |
| 4 | Security Audit | Claude Code | OWASP Top 10, injections, auth |
| 5 | General Review | Codex CLI | OpenAI's perspective |
| 6 | Architecture | Gemini CLI | Code quality, DRY, naming |

After all agents report, the system:
1. **Aggregates** all findings into a single deduplicated list
2. **Scores** your changes (0-100) based on severity
3. **Auto-fixes** safe issues (bugs, security, dead code, missing types)
4. **Re-runs** the entire loop on the fixed code
5. **Repeats** until the score reaches 95% or higher

### What you get:

- **Multi-perspective review** — 6 agents catch more than 1
- **Cross-validation** — if multiple agents flag the same issue, it's definitely real
- **Automatic fixes** — Critical/High/Medium issues are fixed without asking
- **Iterative improvement** — each cycle reviews the latest state after previous fixes
- **Detailed log** — every agent's output and every fix is recorded in `docs/review-logs/`
- **Never commits** — only reviews and fixes, you decide when to commit

### What this does NOT do:

- Does not commit changes (that's your call)
- Does not change business logic (unless it's clearly broken)
- Does not refactor surrounding code (minimal, targeted fixes only)
- Does not modify infrastructure (CI/CD, GitHub Secrets — only reports)

---

## Prerequisites

Before using Review Loop, install:

### 1. Codex CLI (OpenAI)

```bash
npm install -g @openai/codex
codex login
```

Verify:

```bash
codex --version
```

### 2. Gemini CLI (Google)

```bash
npm install -g @anthropic-ai/gemini-cli
```

Or install via the official method from Google. Verify:

```bash
gemini --version
```

### 3. jq (JSON parsing)

On macOS:

```bash
brew install jq
```

On Ubuntu/Debian:

```bash
sudo apt install jq
```

### 4. Claude Code

Review Loop runs inside Claude Code as a **skill** (slash command). You need Claude Code installed and running.

---

## How to set up

### Way 1: Automatic (recommended)

Tell Claude Code:

> "Set up the Review Loop skill. Here's the prompt: [paste the content of prompt-eng.md]"

Claude Code will create the skill file at `~/.claude/skills/review-loop/SKILL.md`.

### Way 2: Manual

1. Create the skill directory:

```bash
mkdir -p ~/.claude/skills/review-loop
```

2. Copy the prompt file (`prompt-eng.md` from this repo) to `~/.claude/skills/review-loop/SKILL.md`

3. Restart Claude Code

4. Now you can invoke it with: `/review-loop`

---

## How it works

```
┌─────────────────────────────────────────────────┐
│                  REVIEW LOOP                     │
│                                                  │
│  ┌─────────┐ ┌─────────┐ ┌──────────┐          │
│  │ Claude  │ │ Claude  │ │ Claude   │          │
│  │ General │ │ General │ │ Breaking │          │
│  │ Rev #1  │ │ Rev #2  │ │ Changes  │          │
│  └────┬────┘ └────┬────┘ └─────┬────┘          │
│       │           │            │                │
│  ┌────┴────┐ ┌────┴────┐ ┌────┴─────┐          │
│  │ Claude  │ │ Codex   │ │ Gemini   │          │
│  │Security │ │ General │ │ Archit.  │          │
│  │ Review  │ │ Review  │ │ Review   │          │
│  └────┬────┘ └────┬────┘ └─────┬────┘          │
│       │           │            │                │
│       └───────────┼────────────┘                │
│                   ▼                              │
│          ┌────────────────┐                      │
│          │   AGGREGATE    │                      │
│          │  Deduplicate   │                      │
│          │  Validate      │                      │
│          │  Score (0-100) │                      │
│          └───────┬────────┘                      │
│                  │                               │
│          Score < 95%?                            │
│           YES → Fix → RESTART LOOP              │
│           NO  → Final report → DONE             │
│                                                  │
└─────────────────────────────────────────────────┘
```

### Execution flow:

1. **Check for changes** — `git diff HEAD`. No changes? Stop.
2. **Launch 6 agents in parallel** — all at once, not sequentially
3. **Collect results** — wait for all agents to finish
4. **Aggregate & deduplicate** — merge findings, note which agents agree
5. **Score** — calculate quality score based on severity weights
6. **Auto-fix** — apply safe fixes (Critical/High/Medium severity)
7. **Loop or stop**:
   - Score >= 95% → Done, ready to commit
   - Score < 95% and fixes applied → Re-run the loop
   - Score < 95% and no safe fixes → Stop, report remaining issues
   - 5 iterations max → Stop regardless

### Scoring system:

| Criterion | Weight | Deduction |
|-----------|--------|-----------|
| Critical issues | 30% | -30 per issue |
| High issues | 25% | -10 per issue |
| Medium issues | 20% | -3 per issue |
| Security vulnerabilities | 15% | -20 per critical, -10 per high |
| Architecture/cleanliness | 10% | 0-10 based on agent feedback |

**Score = max(0, 100 - total_deductions)**

### What gets auto-fixed:

- Bugs (logic errors, race conditions, off-by-one, null/undefined)
- Security issues (input validation, auth checks, injection prevention)
- Error handling (null checks, try-catch, proper error messages)
- Code quality (unused imports, dead code, typos)
- Type safety (missing types, incorrect types)
- Swagger annotations (missing @Api decorators)

### What does NOT get auto-fixed:

- Stylistic preferences without a concrete bug
- Vague suggestions like "consider refactoring"
- Infrastructure changes (GitHub Secrets, CI/CD)

---

## Review log

Every iteration is logged to a markdown file at:

```
docs/review-logs/YYYY-MM-DD-HH-MM-review-loop.md
```

The log contains:
- **Full raw output** from every agent (not summarized)
- **Every applied fix** with before/after code snippets
- **Scores and statistics** per iteration
- **Final summary** with cumulative changes

This is your audit trail — you can always go back and see exactly what each agent found and what was changed.

---

## Usage

Start Claude Code in a git repository with uncommitted changes, then:

```
/review-loop
```

That's it. The skill handles everything else automatically.

### Example output:

```
═══════════════════════════════════════════════════
  REVIEW LOOP — Iteration #1
═══════════════════════════════════════════════════

... (6 agents run in parallel) ...

───────────────────────────────────────────────────
  Iteration #1 Results — Score: 72%
───────────────────────────────────────────────────

| # | Severity | Category | File | Issue | Agents |
|---|----------|----------|------|-------|--------|
| 1 | Critical | Bug | src/order.ts:42 | Null dereference | Agent 1, 2 |
| 2 | High | Security | src/auth.ts:15 | Missing JWT validation | Agent 4 |
| 3 | Medium | Quality | src/utils.ts:88 | Unused import | Agent 5, 6 |

🔄 Applied 3 fixes. Restarting review loop...

═══════════════════════════════════════════════════
  REVIEW LOOP — Iteration #2
═══════════════════════════════════════════════════

... (6 agents run again on fixed code) ...

✅ Review Loop complete. Score: 97%. Ready to commit.
```

---

## FAQ

**Q: Do I need all 3 AI tools (Claude, Codex, Gemini)?**
A: No. If Codex CLI or Gemini CLI is not installed, the review continues with the remaining agents. Minimum 4 agents must respond for a valid iteration.

**Q: How long does one iteration take?**
A: Typically 1-3 minutes, since all 6 agents run in parallel.

**Q: Can it break my code?**
A: The loop only makes targeted, minimal fixes. It never refactors surrounding code or changes business logic. And it never commits — you review the changes before committing.

**Q: What if it loops forever?**
A: Hard limit of 5 iterations. After that, it stops and reports remaining issues.

**Q: Does it work with non-TypeScript projects?**
A: Yes. The agents review any code in the git diff. The prompts are language-agnostic — they analyze whatever changes you have.

**Q: Can I customize which agents run?**
A: Yes, edit the skill prompt in `~/.claude/skills/review-loop/SKILL.md`. You can remove, modify, or add agents.

**Q: Where are the logs?**
A: `docs/review-logs/YYYY-MM-DD-HH-MM-review-loop.md` in your project root.

## Compatible agents

| Agent | How to use | Status |
|-------|-----------|--------|
| Claude Code | `/review-loop` slash command | Full support (skill) |
| Cursor | Paste prompt into `.cursorrules` | Needs adaptation |
| Codex CLI | Paste prompt into `AGENTS.md` | Needs adaptation |
