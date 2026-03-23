---
name: review-loop
description: Iterative code review loop — 6 parallel agents (4 Claude + 1 Codex + 1 Gemini), fixes issues, restarts review until quality >= 95%.
---

# Review Loop

An iterative code review system that launches 6 parallel agents, aggregates findings, applies safe fixes, and repeats the cycle until the score reaches 95% or higher.

**NEVER commits.** Only reviews and fixes code. The user decides when to commit.

## Prerequisites

- `codex` CLI installed and authorized (`codex login`)
- `gemini` CLI installed and authorized
- We are in a git repository with uncommitted changes (staged + unstaged)
- `jq` available for JSON parsing

## Core Concept

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

## Review Log File

**MANDATORY:** Every iteration MUST be logged to a markdown file. This is NOT optional.

### Log file location

```
docs/review-logs/YYYY-MM-DD-HH-MM-review-loop.md
```

Create the directory `docs/review-logs/` if it doesn't exist.

### Log file structure

The log is created at Step 1 and appended throughout the entire cycle. It captures:
- Full raw output from each agent (no truncation)
- Every applied fix with before/after code
- Scores and statistics per iteration
- Final summary

### Log file template

```markdown
# Review Loop Log — YYYY-MM-DD HH:MM

**Start:** YYYY-MM-DD HH:MM:SS
**Repository:** <repo name>
**Branch:** <current branch>
**Initial changes:** <git diff --stat summary>

---

## Iteration #1

**Start:** HH:MM:SS

### Agent 1 — General Review #1 (Claude)
<full raw agent 1 output — DO NOT truncate or summarize>

### Agent 2 — General Review #2 (Claude)
<full raw agent 2 output>

### Agent 3 — Breaking Changes Detector (Claude)
<full raw agent 3 output>

### Agent 4 — Security Review (Claude)
<full raw agent 4 output>

### Agent 5 — General Review (Codex)
<full raw codex agent output>

### Agent 6 — Architecture & Code Quality (Gemini)
<full raw gemini agent output>

### Non-responsive agents (if any)
- Agent X: <error message / timeout>

### Aggregated findings
| # | Severity | Category | File | Issue | Agents | Safe to fix? |
|---|----------|----------|------|-------|--------|--------------|
| 1 | Critical | Bug | path:line | description | Agent 1, 2 | Yes |
| ... | ... | ... | ... | ... | ... | ... |

### Score: XX%
- Critical: X | High: X | Medium: X | Low: X
- Safe to auto-fix: X | Needs manual review: X

### Applied changes

#### Fix #1 — [Severity] Description
**File:** `path/to/file.ts:42`
**Issue:** <what was wrong>
**Before:**
\```typescript
<original code>
\```
**After:**
\```typescript
<fixed code>
\```
**Reason:** <why this fix is safe>

#### Fix #2 — ...
(repeat for each fix)

### No changes applied (if none)
Reason: <all findings Low/Medium or need manual review>

---

## Iteration #2
(same structure, shows NEW state after previous fixes)

---

## Final Summary

**Completed:** YYYY-MM-DD HH:MM:SS
**Total iterations:** N
**Final score:** XX%
**Total findings across all iterations:** X
**Auto-fixed:** X
**Remaining (manual review):** X

### All changes made (cumulative)
1. `path/to/file.ts:42` — fix description
2. `path/to/file.ts:88` — fix description
...

### Unresolved issues
1. `path/to/file.ts:15` — description (why not auto-fixed)
...
```

### Logging rules

1. **Log FULL output from each agent** — don't summarize or truncate. The log is the source of truth.
2. **Log EVERY code change** with before/after snippets — so you can trace exactly what the cycle changed.
3. **Log even failed agents** — record what went wrong (timeout, CLI error, etc.).
4. **Log timestamps** — for each iteration start.
5. **Append, never overwrite** — each iteration is added to the same file.
6. **Use Write** to create the file at Step 1, then **Edit** to add new iterations.
7. **Log file persists after the cycle ends** — it's a permanent record in the repository.

## Review Agents

All 6 agents are launched **in parallel** on each iteration.

### Claude Agent 1 — General Review #1

**Type:** `Agent` tool, `subagent_type: "general-purpose"`

**Prompt:**
```
You are an experienced code reviewer. Analyze ALL uncommitted changes (both staged and unstaged) in this repository.

Run these commands to get the changes:
1. `git diff` (unstaged changes)
2. `git diff --cached` (staged changes)
3. `git diff HEAD` (all uncommitted vs HEAD)
4. `git status --short`

Provide a structured code review with severity levels:
- **Critical** — will cause bugs, crashes, or data loss in production
- **High** — significant logic errors, race conditions, missing error handling
- **Medium** — code quality issues, performance problems, unclear logic
- **Low** — stylistic issues, minor improvements, naming suggestions

For each finding:
1. File path and line number(s)
2. What the issue is
3. Why it matters
4. Suggested fix (specific code)

Focus: bugs, logic errors, edge cases, error handling, performance.
Be specific and practical. Do NOT suggest changes that alter business logic unless it's clearly broken.
All output must be in English (code, comments, variable names).

DO NOT make any changes. Only report findings.
```

### Claude Agent 2 — General Review #2 (Second Opinion)

**Type:** `Agent` tool, `subagent_type: "general-purpose"`

**Prompt:**
```
You are an independent code reviewer providing a second opinion. Analyze ALL uncommitted changes in this repository.

Run these commands to get the changes:
1. `git diff HEAD` (all uncommitted changes)
2. `git status --short`
3. Read each changed file in full to understand the surrounding context

Provide a fresh, independent review — DO NOT anticipate what other reviewers might find. Look at things from a different angle.

Focus:
- Things that are easy to miss: off-by-one errors, null/undefined cases, async/await issues
- API contract violations: does the code match expected interfaces?
- Data flow: are transformations correct end-to-end?
- Error propagation: are errors caught, logged, and handled properly?
- Naming and readability: will someone else understand this in 6 months?

Rate each finding: Critical / High / Medium / Low.
Include file path, line numbers, and specific fix suggestions.
All output must be in English.

DO NOT make any changes. Only report findings.
```

### Claude Agent 3 — Breaking Changes Detector

**Type:** `Agent` tool, `subagent_type: "general-purpose"`

**Prompt:**
```
You are a regression analyst. Your SOLE job is to determine whether uncommitted changes could break any EXISTING functionality.

Run these commands:
1. `git diff HEAD` (all uncommitted changes)
2. `git status --short`
3. For each changed file, read the FULL file (not just the diff) to understand context
4. Find all callers/consumers of changed functions, classes, or APIs

Check for:
- **API contract changes**: renamed fields, changed types, removed endpoints, changed response shapes
- **Database schema changes**: will existing data break? Are migrations needed?
- **Import/export changes**: removed exports that other modules depend on
- **Behavioral changes**: functions that now return different values, throw different errors, or have different side effects
- **Configuration changes**: renamed/removed env variables, changed defaults
- **Type changes**: TypeScript interface modifications that break consumers

For each potentially breaking change:
1. What changed (file:line)
2. What could break (list specific files/modules/consumers)
3. Risk level: Critical / High / Medium / Low
4. How to verify: specific test command or manual check

If NO breaking changes are found, explicitly state: "No breaking changes detected."
All output must be in English.

DO NOT make any changes. Only report findings.
```

### Claude Agent 4 — Security Review

**Type:** `Agent` tool, `subagent_type: "general-purpose"`

**Prompt:**
```
You are a security auditor. Review ALL uncommitted changes for security vulnerabilities.

Run these commands:
1. `git diff HEAD` (all uncommitted changes)
2. `git status --short`
3. Read full files where security-related changes are detected

Focus EXCLUSIVELY on:
- **Injections**: SQL injection, command injection, XSS, template injection
- **Authentication/Authorization**: JWT handling, session management, role checks, missing guards
- **Data leakage**: sensitive data in logs, responses, or error messages; .env secrets, API keys
- **Input validation**: missing validation, type coercion issues, buffer overflow
- **OWASP Top 10**: all categories
- **Cryptographic issues**: weak algorithms, hardcoded keys, insecure randomness
- **Dependency risks**: known vulnerable packages, unsafe imports
- **Race conditions**: TOCTOU, double-spending, concurrent access without locks

For each vulnerability:
1. File path and line number(s)
2. Vulnerability type (CWE number if possible)
3. Severity: Critical / High / Medium / Low
4. Exploitation scenario (how this could be attacked)
5. Specific fix

If NO security vulnerabilities are found, explicitly state: "No security vulnerabilities detected."
All output must be in English.

DO NOT make any changes. Only report findings.
```

### Codex Agent — General Review

**Type:** `Bash` tool with `run_in_background: true`

Uses the same approach as the `codex-review-all` skill.

**CRITICAL: `--uncommitted` and `[PROMPT]` are MUTUALLY EXCLUSIVE in Codex CLI.**

```bash
codex exec review --uncommitted --ephemeral --json 2>/dev/null | jq -rs '[.[] | select(.type == "item.completed" and .item.type == "agent_message") | .item.text] | join("\n")'
```

### Gemini Agent — Architecture & Code Quality

**Type:** `Bash` tool with `run_in_background: true`

Uses Gemini CLI with `@` file references for full context.

**Step 1:** Get changed file references:
```bash
git diff --name-only HEAD
```

**Step 2:** Run review:
```bash
gemini -p "You are a software architect and code quality expert. Review uncommitted changes: <@FILE_REFERENCES>

Here is the git diff:

$(git diff HEAD | head -5000)

Focus your review EXCLUSIVELY on:
1. **Architecture**: Are the changes in the right place? Do they follow existing patterns? Separation of concerns?
2. **Code cleanliness**: Dead code, unused imports, duplicated logic, overly complex functions
3. **Comments**: Are complex parts documented? Are comments accurate and in English?
4. **Swagger/OpenAPI**: Are new endpoints documented with @ApiOperation, @ApiResponse, @ApiProperty? Are DTOs properly annotated?
5. **Naming**: Are variable/function/class names clear, consistent, and in English?
6. **DRY violations**: Is there copied code that should be extracted?

Rate each finding: Critical / High / Medium / Low.
Be specific — include exact file paths and line numbers.
All output must be in English." -m gemini-2.5-pro --output-format text 2>&1
```

## Execution Flow

### Step 1: Check for changes and initialize log

```bash
git status --short
```

If no output → tell the user "No uncommitted changes found" and stop.

Also run to understand scope:
```bash
git diff --stat HEAD
```

**Create log file:**
```bash
mkdir -p docs/review-logs
```

Use `Write` tool to create `docs/review-logs/YYYY-MM-DD-HH-MM-review-loop.md` with the header section (Start, Repository, Branch, Initial changes). Use the actual current date/time.

### Step 2: Show iteration header

For iteration N, show:

```
═══════════════════════════════════════════════════
  REVIEW LOOP — Iteration #N
═══════════════════════════════════════════════════
```

### Step 3: Launch all 6 agents in parallel

Launch ALL agents simultaneously:
- 4 Claude agents via `Agent` tool with `run_in_background: true`
- 1 Codex agent via `Bash` tool with `run_in_background: true`
- 1 Gemini agent via `Bash` tool with `run_in_background: true`

**CRITICAL:** All 6 must be launched in ONE message with multiple tool calls. Never sequentially.

### Step 4: Wait for all results and log raw output

Use `TaskOutput` to collect results from all 6 agents as they complete.

**IMMEDIATELY after each agent completes**, append its raw output to the log file via `Edit` tool. Do NOT wait for all agents — log each as it arrives. This ensures data isn't lost even if the process is interrupted.

If any agent fails (timeout, crash, CLI error):
- Log the failure (agent name + error message) in the log file
- Continue with results from remaining agents
- Note the failure in the report

### Step 5: Aggregate and deduplicate

When all results are collected:

1. **Parse all findings** into a single list with structure:
   ```
   - Source: <which agent found it>
   - Severity: Critical / High / Medium / Low
   - Category: Bug / Security / Architecture / Breaking / Quality
   - File: <path:line>
   - Issue: <description>
   - Fix: <suggested fix>
   ```

2. **Deduplicate**: If multiple agents flagged the same issue (same file + same topic), merge them into one finding. Note which agents agreed.

3. **Cross-validation**: If Agent 3 (Breaking Changes) flagged something as risky, but a suggested fix from Agent 1/2 would cause that breakage, mark the fix as UNSAFE.

### Step 6: Score changes

Calculate a quality score (0-100) based on:

| Criterion | Weight | Calculation |
|-----------|--------|-------------|
| Critical issues | 30% | -30 per critical, 0 if none |
| High issues | 25% | -10 per high, 0 if none |
| Medium issues | 20% | -3 per medium, 0 if none |
| Security vulnerabilities | 15% | -20 per critical sec, -10 per high sec |
| Architecture/cleanliness | 10% | 0-10 based on agent feedback |

**Score = max(0, 100 - total_deductions)**

### Step 7: Log aggregated findings and show iteration report

**Append to log file:** aggregated findings table, score, and statistics for this iteration (see Log File Template → "Aggregated findings" and "Score" sections).

Then show the user:

```
───────────────────────────────────────────────────
  Iteration #N Results — Score: XX%
───────────────────────────────────────────────────

## Findings Summary
| # | Severity | Category | File | Issue | Agents |
|---|----------|----------|------|-------|--------|
| 1 | Critical | Bug | path:line | description | Agent 1, 2 |
| 2 | High | Security | path:line | description | Agent 4 |
| ... | ... | ... | ... | ... | ... |

## Detailed Findings
### Finding #1 — [Critical] Bug in path/to/file.ts:42
**Found by:** Agent 1 (General Review), Agent 2 (Second Opinion)
**Issue:** <detailed description>
**Suggested fix:**
\```typescript
// specific code fix
\```
**Safe to apply:** Yes / No (if No, explain why)

... (repeat for each finding)

## Statistics
- Total findings: X
- Critical: X | High: X | Medium: X | Low: X
- Safe to auto-fix: X
- Need manual review: X
- Agents that responded: X/6
```

### Step 8: Apply safe fixes

**APPLY ALL fixes that match any of these criteria:**
1. Severity Critical, High, or Medium — fix automatically without asking the user
2. Low severity — fix if the fix is simple and unambiguous (doesn't require design decisions)
3. Fix is specific and unambiguous (not "consider refactoring")
4. At least 1 agent found the issue (multi-agent agreement not required)

**Allowed fix types (any severity):**
   - Bugs (logic errors, race conditions, off-by-one, null/undefined cases)
   - Security (input validation, authorization checks, injection prevention)
   - Error handling (null checks, try-catch, proper error messages)
   - Code quality (unused imports, dead code, typos)
   - Type safety (missing types, incorrect types)
   - Swagger annotations (missing @Api decorators)
   - Architectural issues (if the fix is clear and specific)
   - Business logic changes ARE ALLOWED if the current logic is clearly broken (confirmed by agents)

**Do NOT fix:**
   - Stylistic preferences without a concrete bug
   - Remarks like "consider refactoring" without specific code
   - Infrastructure changes (GitHub Secrets, CI/CD) — only report

**When applying fixes:**
- Use `Edit` tool for each fix
- Make minimal, targeted changes
- Do NOT refactor surrounding code
- Do NOT add features
- Do NOT change formatting of untouched code
- **Log EVERY fix in the log file** with before/after code snippets (see Log File Template → "Applied changes" section)

**If NO safe fixes exist** (all findings Low/Medium or need manual review):
- Proceed to Step 9 and report findings
- Set the current score and suggest what the user should review manually

### Step 9: Loop decision

```
If score >= 95%:
    → Show "✅ Review Loop complete. Score: XX%. Ready to commit."
    → Show final summary of all iterations
    → STOP

If score < 95% AND safe fixes were applied:
    → Show "🔄 Applied X fixes. Restarting review loop..."
    → Go to Step 2 with iteration N+1

If score < 95% AND no safe fixes can be applied:
    → Show "⚠️ Score: XX%. Remaining issues need manual review."
    → Show list of issues needing human attention
    → STOP

If iteration count > 5:
    → Show "⚠️ Maximum iterations (5) reached. Score: XX%."
    → Show remaining issues
    → STOP
```

### Step 10: Final summary (on completion)

**Append final summary to the log file** (see Log File Template → "Final Summary" section).

Then show the user:

```
══════════════════════════════════════════════════
  REVIEW LOOP — Final Summary
══════════════════════════════════════════════════

Iterations: N
Final score: XX%
Total findings across all iterations: X
Auto-fixed: X
Remaining (manual review): X

## Changes Made
1. [file:line] — description of applied fix
2. [file:line] — description of applied fix
...

## Unresolved Issues (if any)
1. [file:line] — issue description (why not auto-fixed)
...
══════════════════════════════════════════════════
```

## Important Rules

1. **NEVER commit.** Only review and fix. The user decides when to commit.
2. **NEVER change business logic.** Only fix bugs, security issues, and code quality.
3. **All review output must be in English.** Comments, swagger, variable names — everything.
4. **Staged + unstaged = one whole.** Always use `git diff HEAD` to see all uncommitted changes as a unified whole.
5. **Maximum 5 iterations** to prevent infinite loops.
6. **If Codex CLI is unavailable** — skip that agent and continue with 5 agents.
7. **If Gemini CLI is unavailable** — skip that agent and continue with 5 agents.
8. **Minimum 4 agents must respond** for a valid iteration. If fewer than 4 responded, retry failed agents once before continuing.
9. **Be conservative with auto-fixes.** When in doubt — report instead of fix.
10. **Each iteration sees the CURRENT state** — after previous fixes. Agents always review the latest code.
11. **MANDATORY log file** — every iteration, every agent, every change must be recorded.
