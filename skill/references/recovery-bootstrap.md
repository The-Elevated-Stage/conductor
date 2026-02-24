<skill name="conductor-recovery-bootstrap" version="4.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Recovery Bootstrap Protocol
</metadata>

<sections>
- purpose
- entry-conditions
- heartbeat-agent
- session-summary
- handoff-reading
- learnings-reading
- staged-context-tests
- state-reconstruction
- musician-triage
- settle-completions
- adversarial-validation
- corrective-action
- launch-watcher
- resume-execution
- not-included
- self-detection
</sections>

<section id="purpose">
<core>
# Recovery Bootstrap Protocol

## Purpose

Unified recovery flow for the Conductor after crash or planned context handoff. This is a completely new session — no resumed context, no old teammates or agents accessible. The protocol reconstructs full situational awareness from five sources:

1. Souffleur's export file (previous session history)
2. Handoff document (if exists — written by the dying Conductor)
3. MEMORY.md (plan path, active orchestration state)
4. comms-link database (task states, message history)
5. Learnings file (cross-session decisions and gotchas)

The protocol validates recovered context through staged self-assessment before resuming orchestration, then triages in-flight Musicians and validates recent work through adversarial review.
</core>
</section>

<section id="entry-conditions">
<core>
## Entry Conditions

Invoked via Souffleur's launch prompt with a single flag:

```
/conductor --recovery-bootstrap
```

The Souffleur provides relaunch context as plain text via `{RECOVERY_REASON}` substitution in the launch prompt. The Conductor determines recovery behavior from handoff existence (Step 2), not from the flag or prompt text.
</core>

<mandatory>
When `--recovery-bootstrap` is present, bypass the Initialization Protocol entirely and enter the Recovery Bootstrap Protocol directly. The flag is the sole routing signal — SKILL.md preamble checks for it before any other protocol dispatch.
</mandatory>
</section>

<section id="heartbeat-agent">
<core>
## Step 0: Heartbeat Agent

Launch a background subagent immediately — before any reads or recovery logic.

**Heartbeat agent parameters:**
- **Type:** Background Task subagent
- **Immediate action:** UPDATE task-00 `session_id` and `last_heartbeat`
- **Loop:** Refresh `last_heartbeat` every 60s (matches message-watcher cadence; both well within Souffleur's 240s staleness threshold)
- **Kill protocol:** Conductor INSERTs shutdown message into `orchestration_messages`. Agent polls for this message each loop iteration and exits when found.
- **Error handling:** UPDATE failure -> log, continue looping (transient)

**Immediate action SQL:**

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET session_id = '{SESSION_ID}', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</template>

**Loop SQL (every 60s):**

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</template>

**Shutdown poll SQL (each loop iteration):**

<template follow="exact">
```sql
SELECT id FROM orchestration_messages
WHERE task_id = 'task-00' AND message = 'heartbeat_agent_shutdown' AND message_type = 'system'
ORDER BY id DESC LIMIT 1;
```
</template>

If the query returns a row, the agent exits cleanly.

This agent serves two purposes: the Souffleur discovers the new session ID by polling `orchestration_tasks` for a changed `session_id` on `task-00`, and the heartbeat stays fresh during the lengthy recovery process.
</core>
</section>

<section id="session-summary">
<core>
## Step 1: Read Session Summary

Read the export file at the path provided via `{EXPORT_PATH}` substitution in the Souffleur's launch prompt. Format is clean markdown with a "Files Modified" summary at the top (per Souffleur `conductor-relaunch.md`).

**Truncation behavior:** Souffleur preserves the "Files Modified" summary at the top PLUS the most recent ~800k chars. The middle of the conversation is cut, not the head or tail. The Conductor always gets the file inventory plus recent work.

**What to extract:** Read as context — do not parse, just absorb. The export provides broad situational awareness of what the previous Conductor session was doing.

**If the path is invalid or the file is empty:** Treat as crash scenario. Proceed to Step 2 — the fallback reads in the crash path will reconstruct the necessary large-scope context.
</core>
</section>

<section id="handoff-reading">
<core>
## Step 2: Read Handoff

Read the handoff document from `temp/HANDOFFS/Conductor/handoff.md` — single file, overwritten each time. Content is freeform markdown, not structured for parsing. The dying Conductor writes whatever it considers useful: current phase, active tasks, pending events, in-progress decisions, notes.

Read MEMORY.md now for the plan path. Step 5 revisits MEMORY.md for broader state reconstruction.

### Crash Scenario (Handoff Does Not Exist)

If the handoff file does not exist, the previous Conductor crashed without writing one. Read the following fallback files to reconstruct large-scope context:

1. **Implementation plan: plan-index** (via MEMORY.md plan path)
2. **Implementation plan: Overview section** (via plan-index line range)
3. **Implementation plan: Phase Summary section** (via plan-index line range)
4. **Current phase section** (determined from DB in Step 5 — defer this read)
5. `docs/README.md`
6. `docs/knowledge-base/README.md`
7. `docs/implementation/README.md`
8. `docs/implementation/proposals/README.md`
9. `docs/scratchpad/README.md`

This mirrors what the Initialization Protocol loads at bootstrap. The goal is to reach the same baseline understanding that a fresh Conductor would have after initialization.
</core>

<guidance>
If the export file from Step 1 was also missing or empty, this fallback set becomes the primary source of project context. Ensure all items are read before proceeding to the staged context tests.
</guidance>
</section>

<section id="learnings-reading">
<core>
## Step 3: Read Learnings File

Read `temp/conductor-learnings.log`. This file contains cross-session learnings — decisions, patterns, and gotchas discovered during execution. It is append-only and accumulates across Conductor generations.

**Format:** One line per learning, timestamped for ordering. No categories, no severity, no required fields.

```
[2026-02-22T14:32:00] Musician context estimates ~6x unreliable when self-correction active
[2026-02-22T15:10:00] RAG query "orchestration patterns" returns better results than "conductor patterns"
```

**Lifecycle:**
- **Creation:** Lazy — append creates the file if it does not exist
- **Appended** throughout execution during reviews, error recovery, and phase transitions
- **Read** by Recovery Bootstrap Protocol (this step) on every Conductor generation
- **Rotation:** None — `temp/` handles cleanup on reboot
- Lives in `temp/` — scoped to a single orchestration run, cleared on reboot

**If the file does not exist:** This is the first Conductor generation. Note "first generation" and continue — no error.
</core>
</section>

<section id="staged-context-tests">
<core>
## Step 4: Staged Context Tests

Structured self-assessment before proceeding. Each stage validates sufficient understanding to orchestrate. All three stages must pass.

### Stage 1 — Project Orientation (After Session History + Handoff/Fallbacks)

**Questions:**
- Can you state the project's goal(s)?
- Can you identify the `docs/` directory structure and expectations per subdirectory?

**If fails:** Re-read any large-scope documents not yet loaded. If a truncated export caused the failure, supplement with crash-path fallback files (plan overview, docs READMEs) even if the handoff existed.

### Stage 2 — State Awareness

**Questions:**
- Can you state the current phase number and what it covers?
- Can you identify which tasks are active, completed, and pending?

**If fails:** Query comms-link more thoroughly. Read current phase section from the implementation plan.

Stage 2 may require querying comms-link before Step 5's formal state reconstruction. This is expected — Stage 2 tests whether you can orient from the export and handoff alone, with database queries as the fallback that confirms you need Step 5's full reconstruction.

### Stage 3 — Protocol Fluency

**Questions:**
- Can you name each step of the Phase Execution Protocol's implementation loop?

**Action:** Read the full Phase Execution Protocol section from SKILL.md before jumping in mid-flow.
</core>

<mandatory>
Stage 3 failure is critical. If re-reading SKILL.md's Protocol Registry and Phase Execution Protocol reference still does not allow you to articulate the implementation loop: HALT and report to user. The recovery session may be corrupted — do not proceed with orchestration.
</mandatory>
</section>

<section id="state-reconstruction">
<core>
## Step 5: State Reconstruction

Parallel reads where possible. This step builds the complete operational picture.

**Parallel group 1 — File reads:**
- Read MEMORY.md (plan path, pending event notes)
- Load memory graph (`read_graph` from memory MCP)
- Git branch verification (`scripts/check-git-branch.sh`)
- Verify `temp/` exists

**Parallel group 2 — Database verification:**
- Schema verification: `PRAGMA table_info(orchestration_tasks)` and `PRAGMA table_info(orchestration_messages)` — confirm tables and columns exist. Do NOT recreate tables.
- Hook verification: confirm `hooks.json`, `session-start-hook.sh`, `stop-hook.sh` exist; verify `comms.db` accessible via comms-link

**Full task state query:**

<template follow="exact">
```sql
SELECT * FROM orchestration_tasks
WHERE task_id NOT IN ('task-00', 'souffleur');
```
</template>

**Phase determination:** Determine the current phase from the latest claimed tasks. Check whether the phase is parallel or sequential by examining task states and instruction paths.
</core>

<mandatory>
Schema verification is read-only. Do NOT recreate database tables during recovery — the existing data is the source of truth. If columns are missing, report to user rather than dropping and recreating.
</mandatory>
</section>

<section id="musician-triage">
<core>
## Step 6: Musician Triage

Assess every Musician based on database state and heartbeat freshness:

| DB State | Heartbeat | Action |
|----------|-----------|--------|
| `working` | Fresh (<540s) | Leave alone — assume operating correctly |
| `working` | Stale (>540s) | Flag as dead — handle in Step 9 corrective actions |
| `needs_review` | Any | Handle review normally (non-destructive assessment) |
| `error` | Any | Do NOT attempt fixes yet. Flag for Step 9 corrective actions |
| `complete` | N/A | Note as completed |
| `exited` | N/A | Note — may need replacement |

**Staleness detection SQL:**

<template follow="exact">
```sql
SELECT task_id, state, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE task_id NOT IN ('task-00', 'souffleur')
  AND state = 'working'
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
```
</template>

### Orphan Session Cleanup

Kill orphaned sessions via `temp/musician-task-XX.pid` files only:

```bash
PID=$(cat temp/musician-task-XX.pid 2>/dev/null)
if [ -n "$PID" ] && kill -0 $PID 2>/dev/null; then
    kill $PID
    rm temp/musician-task-XX.pid
fi
```

If no PID file exists for a suspected orphan, let it survive for the user to close manually. Do not guess PIDs.

### Repetiteur Triage

Check `temp/repetiteur.pid`:
1. If file exists: check PID liveness (`kill -0`)
2. If alive: kill it — the Repetiteur cannot continue without a Conductor to communicate with
3. Remove PID file
4. Re-invoke the Repetiteur later if needed
</core>

<mandatory>
Do NOT attempt error fixes during triage. Triage is assessment only — all corrective actions are deferred to Step 9, which has full context from adversarial validation.
</mandatory>
</section>

<section id="settle-completions">
<core>
## Step 7: Settle and Review Completions

Let in-flight Musicians finish their current work. Do not interrupt Musicians that have fresh heartbeats and are in `working` state.

Review completion reports of the most recently completed task(s) via `orchestration_tasks.report_path`:

<template follow="exact">
```sql
SELECT task_id, report_path, completed_at
FROM orchestration_tasks
WHERE state = 'complete' AND report_path IS NOT NULL
ORDER BY completed_at DESC;
```
</template>

Read each report to understand what was accomplished. This context feeds the adversarial validation in Step 8.
</core>
</section>

<section id="adversarial-validation">
<core>
## Step 8: Adversarial Phase Validation

Launch read-only validation teammates to assess recent work quality.

**Launch parameters:**
- **Type:** Task tool, 2 parallel teammates
- **Model:** Opus
- **Timeout:** 5 minutes each

### Context Cost Mitigation

If the current phase has 2 or fewer tasks, collapse to a single teammate covering both scopes. The context cost of two separate teammates is not justified for a small phase.

### Teammate A — Recent Task Review

**Scope:** Read task instruction files + work output (report, git diff, test results) for the most recently completed or active task(s).

**Deliverable:** Prose summary of deviations, errors, and incomplete steps.

### Teammate B — Phase Coherence Review

**Scope:** Read ALL task instruction files for the current phase plus completion states from DB.

**Deliverable:** Prose summary of integration issues, conflicts, and sequencing problems.

Both teammates are read-only at this stage. Both report prose findings to the Conductor. All findings feed Step 9.
</core>

<guidance>
The teammates bear the context cost in their own windows — the Conductor only receives prose finding summaries. This keeps the Conductor's context lean while still performing thorough validation.
</guidance>
</section>

<section id="corrective-action">
<core>
## Step 9: Corrective Action

Based on teammate findings from Step 8 and flags from Step 6:

### Assessment

1. Run `git status` to assess the working tree state.

### Decision Tree

**If work is unusable:** Use `git revert` of affected commits, then re-queue tasks:

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET state = 'watching',
    session_id = NULL,
    worked_by = NULL,
    last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';
```
</template>

**If work has fixable flaws:** Single file with an obvious correction — Conductor fixes directly. Multiple files or design decisions — delegate to a teammate.

**If work is sound:** Proceed — no action needed.

**Errors flagged from Step 6:** Re-assess with full context from adversarial validation. Redo affected steps or re-queue as needed.
</core>

<mandatory>
Use `git revert` for rollbacks — NOT `git reset --hard`. Revert is reversible and preserves history. Hard reset destroys history and is not recoverable.
</mandatory>
</section>

<section id="launch-watcher">
<core>
## Step 10: Launch Message Watcher

### Kill Heartbeat Agent

The heartbeat agent from Step 0 is no longer needed — the message watcher takes over heartbeat refreshing.

<template follow="exact">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-00', 'task-00',
    'heartbeat_agent_shutdown',
    'system'
);
```
</template>

The heartbeat agent polls for this message each loop iteration and exits when it finds it.

### Launch Message Watcher

Launch the full operational message watcher. This takes over both heartbeat refreshing and event monitoring. Full operational monitoring is now active.

Proceed to SKILL.md -> Message-Watcher Exit Protocol for the watcher launch procedure.
</core>

<mandatory>
The heartbeat agent shutdown INSERT must include all fields explicitly: `task_id='task-00'`, `message='heartbeat_agent_shutdown'`, `message_type='system'`. No NULL fields.
</mandatory>
</section>

<section id="resume-execution">
<core>
## Step 11: Resume Phase Execution

Return to SKILL.md -> Phase Execution Protocol at the current phase. Proceed with the implementation plan from wherever the previous Conductor left off.

The state reconstruction from Step 5 and adversarial validation from Step 8 provide the Conductor with sufficient context to resume mid-phase. The Phase Execution Protocol handles the remaining work normally — no special recovery logic is needed after this point.
</core>
</section>

<section id="not-included">
<mandatory>
## What This Protocol Does NOT Do

Five explicit exclusions:

1. **Does not re-run Initialization Protocol** — bypassed by the `--recovery-bootstrap` launch flag
2. **Does not recreate DB tables** — schema verification only; existing data is the source of truth
3. **Does not wait for user approval** — already granted during original initialization
4. **Does not re-launch the Souffleur** — it is already running; it launched this Conductor
5. **Does not have access to old teammates or subagents** — this is a completely new session; all previous teammates and subagents are gone
</mandatory>
</section>

<section id="self-detection">
<core>
## Conductor Context Self-Detection

The Conductor detects its own context exhaustion via the same platform-level context warnings that Musicians receive. No custom monitoring infrastructure is needed — Claude Code surfaces context usage warnings naturally.

When the Conductor observes it is approaching context limits, it enters the `context-exhaustion-trigger` sequence (see `error-recovery.md`). This triggers the handoff writing and Souffleur relaunch cycle that eventually brings a new Conductor through this Recovery Bootstrap Protocol.
</core>
</section>

</skill>
