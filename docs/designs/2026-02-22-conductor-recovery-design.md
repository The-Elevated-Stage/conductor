# Conductor Recovery & Compaction Design

**Date:** 2026-02-22
**Scope:** Conductor skill v3.0 → v4.0 (skills_staged/conductor/skill/)
**Dependencies:** Souffleur skill (skills_staged/souffleur/skill/)

## Overview

Three categories of changes to the Conductor skill:

1. **Compact Protocol** — Compacting external child sessions (Musicians, Copyist, Repetiteur) when they hit context exhaustion. Replaces the current fresh-session-with-HANDOFF pattern with kill → compact → resume, preserving accumulated session context.

2. **Recovery Bootstrap Protocol** — Unified recovery flow for the Conductor itself after either a planned context handoff or an unplanned crash. Launched by the Souffleur as a completely new session that ingests a trimmed conversation export. Single protocol, single flow, one branch point (handoff existence).

3. **Repetiteur Externalization** — Moving the Repetiteur from a teammate (Task tool + SendMessage) to an external Kitty session (comms-link communication). Driven by the constraint that teammates cannot be compacted. Includes a new conversation table for back-and-forth dialogue.

Supporting changes: Initialization Protocol updates (Souffleur integration, schema changes), learnings file (cross-session knowledge persistence), existing reference file modifications.

## Architecture

### New Protocols in SKILL.md

| Protocol | Role | Reference File |
|----------|------|---------------|
| **Compact Protocol** | Compacting external child sessions | `references/compact-protocol.md` |
| **Recovery Bootstrap Protocol** | Unified Conductor recovery after crash or context exhaustion | `references/recovery-bootstrap.md` |

### New Artifacts (Runtime)

| Artifact | Purpose |
|----------|---------|
| `temp/HANDOFFS/Conductor/` | Conductor handoff documents for planned context recovery |
| `temp/conductor-learnings.log` | Append-only freeform learnings file, persists across Conductor generations |

### New Database Objects

| Object | Purpose |
|--------|---------|
| `repetiteur_conversation` table | Back-and-forth dialogue between Conductor and externalized Repetiteur |
| `souffleur` row in `orchestration_tasks` | Souffleur lifecycle state tracking |
| `context_recovery` state | Signal for Souffleur to kill and relaunch Conductor |
| `confirmed` state | Souffleur bootstrap validation passed |

---

## Compact Protocol

### Purpose

Handles compacting external child sessions (Musicians, Copyist, Repetiteur) when they hit context exhaustion. The Conductor manages the entire lifecycle. The session keeps its accumulated context rather than starting fresh.

### Trigger

Routed from:
- `musician-lifecycle.md` → `context-exhaustion-flow` (replacing fresh-session-with-HANDOFF)
- `error-recovery.md` → `context-warning-protocol` (when Conductor decides compaction is appropriate)
- Repetiteur context exhaustion (after externalization)

### Prerequisites

Before entering this protocol, the Conductor has:
- The session's PID (from `temp/musician-task-XX.pid`)
- The session's session ID (from `orchestration_tasks.session_id`)
- A HANDOFF document written by the session
- The task ID and current `worked_by` value

The Musician skill's existing exit flow (HANDOFF writing, `exited` state) is unchanged — only the Conductor's response changes.

### Sequence

**Step 1: Close old session**
```bash
PID=$(cat temp/musician-task-XX.pid)
kill $PID
rm temp/musician-task-XX.pid
```

**Step 2: Record baseline**
```bash
SENTINEL=~/.claude/projects/-home-kyle-claude-remindly/${SESSION_ID}.jsonl
BASELINE_LINES=$(wc -l < "$SENTINEL")
```

Count lines BEFORE launching compact. The watcher reads all lines from baseline forward, preventing race conditions.

**Step 3: Launch compact watcher (background subagent)**

Polls JSONL every ~1 second, parsing new lines as JSON from the baseline forward. Looks for exactly:
```json
{"type": "system", "subtype": "compact_boundary"}
```

Inputs: JSONL path, baseline line count. Timeout: ~5 minutes. Exits immediately on detection.

See RAG: `compact-detection-jsonl-signals.md` for signal details.

**Step 4: Launch compact session**
```bash
kitty --directory /home/kyle/claude/remindly \
  --title "Compact: task-XX" \
  -- env -u CLAUDECODE claude \
  --resume $SESSION_ID "/compact" &
echo $! > temp/musician-task-XX.pid
```

Watcher launches BEFORE compact session — prevents race condition.

**Step 5: Watcher reports completion → Kill compacted session**
```bash
PID=$(cat temp/musician-task-XX.pid)
kill $PID
rm temp/musician-task-XX.pid
```

**Step 6: Resume with continuation prompt**

Uses the existing replacement-session-launch template from `musician-lifecycle.md`, with `--resume $SESSION_ID` added. The session wakes up with compacted context intact. `worked_by` succession increments normally (S2, S3, etc.).

```bash
kitty --directory /home/kyle/claude/remindly \
  --title "Musician: task-XX (S{N})" \
  -- env -u CLAUDECODE claude \
  --resume $SESSION_ID \
  --permission-mode acceptEdits "/musician
  ...existing replacement-session-launch prompt template..." &
echo $! > temp/musician-task-XX.pid
```

**Step 7: Update database state**

Set `fix_proposed` and send handoff message (same SQL as current clean-handoff procedure). The resumed session claims the task via the existing guard clause.

**Step 8: Return to monitoring**

Proceed to SKILL.md → Message-Watcher Exit Protocol to ensure the watcher is running.

### What Doesn't Change

- Musician's HANDOFF writing flow
- Musician's context warning reporting
- Replacement-session-launch prompt template (reused, just adds `--resume`)
- `worked_by` succession pattern
- Database state transitions
- High-context verification rule (>80% = re-run tests)

---

## Recovery Bootstrap Protocol

### Purpose

Unified recovery flow for the Conductor after crash or planned context handoff. This is a completely new session — no resumed context, no old teammates/agents accessible. Reconstructs full situational awareness from: Souffleur's export file, handoff document (if exists), MEMORY.md, comms-link database, and learnings file.

### Trigger

Invoked via Souffleur's launch prompt with a single flag:
- `/conductor --recovery-bootstrap`

The Souffleur provides relaunch context as plain text via `{RECOVERY_REASON}` substitution. The Conductor determines recovery behavior from handoff existence (step 2), not from the flag or prompt text.

SKILL.md preamble: when `--recovery-bootstrap` is present, bypass Initialization Protocol and enter Recovery Bootstrap Protocol directly.

### Sequence

**Step 0: Heartbeat Agent**

Launch a background subagent immediately:
1. Updates `task-00.session_id` to `$CLAUDE_SESSION_ID`
2. Updates `task-00.last_heartbeat = datetime('now')`
3. Loops: refreshes heartbeat every ~30 seconds
4. Runs until explicitly killed (step 10)

Serves two purposes: Souffleur discovers the new session ID via `SESSION_ID_FOUND`, and heartbeat stays fresh during the lengthy recovery process.

**Step 1: Read Session Summary**

Read the export file at the path provided in the Souffleur's launch prompt. This is a trimmed conversation transcript from the predecessor — the most recent portion of its history.

**Step 2: Read Handoff**

Read handoff from `temp/HANDOFFS/Conductor/` if it exists. Extract current phase, step, active task state, and any notes.

If handoff does not exist (crash scenario), read fallback files to reconstruct large-scope context:
- Implementation plan: plan-index, Overview, Phase Summary (via MEMORY.md plan path)
- Current phase section (determined from DB in step 5)
- `docs/README.md`
- `docs/knowledge-base/README.md`
- `docs/implementation/README.md`
- `docs/implementation/proposals/README.md`
- `docs/scratchpad/README.md`

This mirrors what Initialization Protocol loads at bootstrap.

**Step 3: Read Learnings File**

Read `temp/conductor-learnings.log`. Absorb cross-session learnings — decisions, patterns, gotchas discovered during execution. Append-only, accumulates across Conductor generations.

**Step 4: Staged Context Tests**

Structured self-assessment before proceeding. Each stage validates sufficient understanding to orchestrate.

*Stage 1 — After session history + handoff/fallbacks:*
- Can you state the project's goal(s)?
- Can you identify the docs/ directory structure and expectations per subdirectory?
- If fails: re-read any large-scope documents not yet loaded.

*Stage 2 — State awareness:*
- Can you state the current phase number and what it covers?
- Can you identify which tasks are active, completed, and pending?
- If fails: query comms-link more thoroughly. Read current phase section from plan.

*Stage 3 — Protocol fluency:*
- Can you name each step of the Phase Execution Protocol's implementation loop?
- Action: read the full Phase Execution Protocol section from SKILL.md before jumping in mid-flow.

**Step 5: State Reconstruction**

Parallel reads where possible:
- Read MEMORY.md (plan path, pending event notes)
- Load memory graph (`read_graph` from memory MCP)
- Schema verification (`PRAGMA table_info` — confirm, do NOT recreate)
- Hook verification (hooks.json, session-start-hook.sh, stop-hook.sh, comms.db accessible)
- Git branch verification (`scripts/check-git-branch.sh`)
- Verify `temp/` exists
- Query full task state: `SELECT * FROM orchestration_tasks WHERE task_id != 'souffleur'`
- Determine current phase from latest claimed tasks; check if parallel or sequential

**Step 6: Musician Triage**

| DB State | Heartbeat | Action |
|----------|-----------|--------|
| `working` | Fresh (<540s) | Leave alone — assume operating correctly |
| `working` | Stale (>540s) | Flag as dead — handle in step 9 |
| `needs_review` | Any | Handle review normally (non-destructive assessment) |
| `error` | Any | Do NOT attempt fixes. Flag for step 9 corrective actions |
| `complete` | N/A | Note as completed |
| `exited` | N/A | Note — may need replacement |

Kill orphaned sessions via `temp/musician-task-XX.pid` files only. If no PID file exists for a suspected orphan, let it survive for user to close manually.

**Step 7: Settle & Review Completions**

Let in-flight Musicians finish current work. Review completion reports of most recently completed task(s) via `orchestration_tasks.report_path`.

**Step 8: Adversarial Phase Validation**

Launch 2 read-only validation teammates:

**Teammate A — Recent Task Review:**
- Read task instruction files for most recently completed/active task(s)
- Read actual work output (code changes, test results, reports)
- Assess: does work match instructions? Any errors in instructions that led to faulty work?

**Teammate B — Phase Coherence Review:**
- Read ALL task instruction files for current phase
- Read all completed work across the phase
- Assess: is the phase internally coherent? Integration issues between tasks?

Both are read-only at this stage. Output feeds step 9.

**Step 9: Corrective Action**

Based on teammate findings:
1. `git status` — assess working tree state
2. If work is unusable: git rollback of affected commits, re-queue tasks
3. If work has fixable flaws: Conductor fixes directly (small) or delegates to teammate (large)
4. If work is sound: proceed
5. Errors flagged from step 6: re-assess with full context, redo affected steps or re-queue as needed

**Step 10: Launch Message Watcher**

Kill heartbeat agent from step 0. Launch message watcher (takes over heartbeat refreshing). Full operational monitoring now active.

**Step 11: Resume Phase Execution**

Return to SKILL.md → Phase Execution Protocol at current phase. Proceed with plan.

### What This Protocol Does NOT Do

- Does not re-run Initialization Protocol (bypassed by launch flag)
- Does not recreate DB tables (schema verification only)
- Does not wait for user approval (already granted during original init)
- Does not re-launch the Souffleur (already running — it launched this Conductor)
- Does not have access to old teammates or subagents (completely new session)

---

## Initialization Protocol Changes

### Schema Changes

**CHECK constraint — two new states:**

```sql
state TEXT NOT NULL CHECK (state IN (
    'watching', 'reviewing', 'exit_requested', 'complete',
    'working', 'needs_review', 'review_approved', 'review_failed',
    'error', 'fix_proposed', 'exited',
    'context_recovery',
    'confirmed'
))
```

- `context_recovery`: set by Conductor when context-exhausted and ready for Souffleur to kill
- `confirmed`: set by Souffleur after bootstrap validation passes

**New row — Souffleur (inserted BEFORE task-00):**

```sql
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('souffleur', 'watching', datetime('now'));

INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));
```

**New table — Repetiteur conversation:**

```sql
CREATE TABLE repetiteur_conversation (
    id INTEGER PRIMARY KEY,
    sender TEXT NOT NULL,
    message TEXT NOT NULL,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### Bootstrap Sequence Changes

**Step 6 (Initialize Database) — modified:**
- Souffleur row inserted before task-00
- `context_recovery` and `confirmed` added to CHECK constraint
- `repetiteur_conversation` table created

**New step between 6 and 7 — Launch Souffleur:**

1. Discover own kitty PID (trivial ps walk — RAG: "kitty PID discovery")
2. Launch Souffleur:
   ```bash
   kitty --directory /home/kyle/claude/remindly \
     --title "Souffleur" \
     -- env -u CLAUDECODE claude \
     --permission-mode acceptEdits \
     "/souffleur PID:$KITTY_PID SESSION_ID:$CLAUDE_SESSION_ID" &
   ```
3. **Hard gate:** Poll comms-link until Souffleur row `state = 'confirmed'`. If `error`, read diagnostic message and respond with corrected args. If `exited` (3 failures), report to user — cannot proceed without live Souffleur.

**New step after Souffleur confirmation — Launch Message Watcher:**

Message watcher launches immediately after Souffleur is confirmed, before any Musicians.

### State Documentation Updates

**Conductor states table gains:**

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `context_recovery` | Conductor | Context exhausted, handoff prepared, Souffleur kills | Yes (triggers relaunch) |

**Infrastructure states (new or added to existing section):**

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `confirmed` | Souffleur | Bootstrap validation passed | No |

**State transition flows gain:**

```
Conductor context exit:
  watching → context_recovery → [Souffleur kills, relaunches new Conductor]

Souffleur lifecycle:
  watching → confirmed → watching → ... → complete
  watching → error → [retry] → confirmed → ...
  watching → error → ... (x3) → exited
```

**Hook exit criteria updated:** `context_recovery` is a terminal state that allows session exit.

### SKILL.md Preamble Update

When invoked with `--recovery-bootstrap`, bypass the Initialization Protocol entirely. Proceed directly to the Recovery Bootstrap Protocol.

---

## Existing Reference File Modifications

### musician-lifecycle.md

**`context-exhaustion-flow` section — replaced with redirect:**

When a Musician exits due to context exhaustion (state = `exited`, HANDOFF present), proceed to SKILL.md → Compact Protocol. The Compact Protocol handles the full cycle.

Current section content (fresh session rationale, "No `--resume` for exhaustion") is removed.

**`handoff-types` table — updated:**

Context Exit row changes from "Simplified automation (see context-exhaustion-flow section)" to "Compact and resume (see Compact Protocol via SKILL.md)."

**All other sections unchanged.**

### error-recovery.md

**New section: `context-exhaustion-trigger`**

The Conductor's pre-death sequence when it detects its own context exhaustion. Strict ordering — `context_recovery` is the kill trigger:

1. Write handoff to `temp/HANDOFFS/Conductor/` — current phase, active tasks, pending events, notes
2. Update MEMORY.md — plan path, handoff location, active task PIDs
3. Close all external Musician sessions — SIGTERM via temp/ PID files, remove PID files
4. **(Last step, `<mandatory>`):** Set `task-00` state to `context_recovery`

**`context-warning-protocol` section — minor guidance update:**

When the Conductor itself is running low on context (not the Musician), route to `context-exhaustion-trigger` instead of continuing to orchestrate.

### repetiteur-invocation.md

**Substantial rework — externalization:**

| Aspect | Current | New |
|--------|---------|-----|
| Launch | Task tool as teammate | Kitty window via Bash |
| Communication | SendMessage | `repetiteur_conversation` table via comms-link |
| Context model | Shares Conductor's context | Independent session |
| Compactable | No | Yes (via Compact Protocol) |
| Session management | Task tool | Conductor manages PID |

**Sections reworked:**
- `spawn-prompt-template` — Kitty launch, PID capture to `temp/repetiteur.pid`
- `consultation-communication` — comms-link polling instead of SendMessage
- `passthrough-communication` — user input relayed via INSERT into conversation table
- `handoff-reception` — handoff delivered via conversation table INSERT

**Sections unchanged (content-wise):**
- `pre-spawn-checklist`, `consultation-count-check`, `pause-musicians`, `blocker-report-format`, `blocker-report-persistence`, `blocker-report-preparation`, `escalation-context`, `task-annotation-matching`, `plan-changeover`, `superseded-plan-handling`

**`error-scenarios` — updated:** Repetiteur crash is now a kitty window/PID death, detected via PID check or conversation table silence.

**New capability:** Repetiteur can be compacted via Compact Protocol when it hits context exhaustion during consultation.

**Note:** The Repetiteur skill itself needs separate updates to use comms-link. Not part of this design.

---

## Learnings File

### Path & Format

`temp/conductor-learnings.log` — append-only, freeform, minimal structure.

```
[2026-02-22T14:32:00] Musician context estimates ~6x unreliable when self-correction active
[2026-02-22T15:10:00] RAG query "orchestration patterns" returns better results than "conductor patterns"
[2026-02-22T16:45:00] Task-05 musician needed explicit import paths — relative imports broke in test runner
```

Timestamps for ordering. One line per learning. No categories, no severity, no required fields. The Conductor decides what to write and when.

### Lifecycle

- Created during first orchestration session when Conductor has something worth recording
- Appended throughout execution — during reviews, error recovery, phase transitions
- Read by Recovery Bootstrap Protocol (step 3) on every Conductor generation
- Lives in `temp/` — cleared on reboot. Scoped to a single orchestration run. Permanent knowledge goes to RAG/memory graph via proposals

### Touchpoints

Light guidance woven into multiple protocol locations:

| Location | Guidance |
|----------|----------|
| SKILL.md preamble `<context>` | Mention learnings file as part of context strategy |
| Phase Execution Protocol reference | After phase transitions: consider recording cross-cutting learnings |
| Review Protocol reference | After reviews with notable findings: consider appending patterns |
| Error Recovery Protocol reference | After error resolution: consider appending reusable insights |
| Recovery Bootstrap Protocol reference | Step 3: read the learnings file |

---

## File Inventory

### New Files

| File | Type |
|------|------|
| `references/compact-protocol.md` | Reference — external session compaction mechanics |
| `references/recovery-bootstrap.md` | Reference — unified Conductor recovery sequence |

### Modified Files

| File | Change Summary |
|------|---------------|
| `SKILL.md` | Protocol registry (+2), preamble (`--recovery-bootstrap` bypass), `context_recovery` state docs |
| `references/initialization.md` | Schema (CHECK, Souffleur row, conversation table), Souffleur launch, hard gate, message watcher |
| `references/musician-lifecycle.md` | `context-exhaustion-flow` → Compact Protocol redirect, `handoff-types` table |
| `references/error-recovery.md` | New `context-exhaustion-trigger` section, `context-warning-protocol` guidance |
| `references/repetiteur-invocation.md` | Externalization — Kitty launch, conversation table, PID management |

### Runtime Artifacts (Created During Execution)

| Artifact | Purpose |
|----------|---------|
| `temp/HANDOFFS/Conductor/` | Conductor handoff documents |
| `temp/conductor-learnings.log` | Cross-session learnings |

---

## Cross-Skill Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| **Souffleur skill** | In development | Must be complete before Recovery Bootstrap can be tested |
| **Repetiteur skill** | Needs update | Must update to use comms-link conversation table. Separate workstream. |
| **Musician skill** | No changes | Existing HANDOFF/exit flows unchanged. Compact Protocol is Conductor-side. |
| **Copyist skill** | No changes | Can be compacted via Compact Protocol but skill itself unchanged. |

## RAG References

| Entry | Used By |
|-------|---------|
| `compact-detection-jsonl-signals.md` | Compact Protocol — `compact_boundary` signal detection |
| `external-session-management.md` | Compact Protocol, Recovery Bootstrap — session launch patterns |
| Kitty PID discovery entry | Initialization — Souffleur launch |
