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

### 2. Daily Report — MANDATORY

File: `docs/reports/YYYY-MM-DD-daily-report.md` in the project directory.

**Format:**

```markdown
# Report for DD.MM.YYYY

### 1. Task name (short)
Description of what was done in business language, 2-3 sentences. Focus on the problem solved and the result. Like a standup update — so a PM understands without technical details.

### 2. Another task name
Same approach — what the situation was, what was done, what the result is.
```

**Daily report rules:**
- One file per day, appended throughout the day
- Each task is a separate `###` block with a sequential number and title
- Write informally, in business language
- **New task** → new `###` block with the next number
- **Follow-up on existing task** → update the text in the existing `###` block (don't create a new one)

**Example:**

```markdown
# Report for 18.03.2026

### 1. Float/Fixed split for providers
Admin can now separately enable/disable a provider for floating (float) and fixed rate. Previously there was one toggle — now two independent ones. For providers that don't support fixed-rate, the toggle is automatically locked.

### 2. 2FA security
Improved 2FA functionality: the test code for two-factor auth (`000000`) could previously work on staging by accident. Now it only works with explicit permission and never in production.

### 3. Markup (commission) configuration via API
Investigated which providers allow passing our commission via API on each request, and which ones only through their partner dashboard. Quickex — via API. BitcoinVN and Changee — only through the dashboard.
```
