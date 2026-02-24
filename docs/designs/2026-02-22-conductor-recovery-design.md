# Conductor Recovery & Compaction Design

**Date:** 2026-02-22 (revised 2026-02-23)
**Scope:** Conductor skill v3.0 → v4.0 (skills_staged/conductor/skill/)
**Dependencies:** Souffleur skill (skills_staged/souffleur/skill/)
**Validation:** 8-agent parallel review (2026-02-22) — 41 factual claims verified, 49 findings resolved

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
| `temp/HANDOFFS/Conductor/handoff.md` | Conductor handoff document (single file, overwritten) |
| `temp/conductor-learnings.log` | Append-only freeform learnings file, persists across Conductor generations |

### New Database Objects

| Object | Purpose |
|--------|---------|
| `repetiteur_conversation` table | Back-and-forth dialogue between Conductor and externalized Repetiteur |
| `souffleur` row in `orchestration_tasks` | Souffleur lifecycle state tracking |
| `context_recovery` state | Signal for Souffleur to kill and relaunch Conductor |
| `confirmed` state | Souffleur bootstrap validation passed |

> **Note:** `confirmed` and `context_recovery` are retroactive DDL alignment — the Souffleur skill (v1.1) already depends on these states. The current CHECK constraint would violate at runtime if the Souffleur were deployed without these additions.

---

## Compact Protocol

### Purpose

Handles compacting external child sessions (Musicians, Copyist, Repetiteur) when they hit context exhaustion. The Conductor manages the entire lifecycle. The session keeps its accumulated context rather than starting fresh.

### Trigger

**Direct trigger:** `musician-lifecycle.md` → `context-exhaustion-flow` (replacing fresh-session-with-HANDOFF).

**Indirect path:** `error-recovery.md` → `context-warning-protocol` → Musician receives `review_failed` → Musician writes HANDOFF and sets `exited` → monitoring watcher detects `exited` → event-routing → Musician Lifecycle Protocol → `context-exhaustion-flow` → Compact Protocol. This path arrives via the Musician's exit flow — implementers must NOT add a direct jump from error-recovery to Compact Protocol, as that would bypass the Musician's exit sequence.

**Repetiteur context exhaustion** (after externalization) — see Repetiteur Variant note at end of section.

### Prerequisites

Before entering this protocol, the Conductor has:
- The session's PID (from `temp/musician-task-XX.pid`)
- The session's session ID (from `orchestration_tasks.session_id`)
- A HANDOFF document written by the session (if one exists — the Compact Protocol preserves session context via `--resume`, so a missing HANDOFF is not blocking; the resumed session retains its own context of the work in progress)
- The task ID and current `worked_by` value

The Musician skill's existing exit flow (HANDOFF writing, `exited` state) is unchanged — only the Conductor's response changes.

### Sequence

**Step 1: Close old session**
```bash
PID=$(cat temp/musician-task-XX.pid)
kill -0 $PID 2>/dev/null && kill $PID
rm temp/musician-task-XX.pid
```

**Step 2: Record baseline**

Retrieve the child session's ID (NOT the Conductor's own `$CLAUDE_SESSION_ID`):
```sql
SELECT session_id FROM orchestration_tasks WHERE task_id = '{task-id}';
```

Count JSONL lines BEFORE launching compact:
```bash
SENTINEL=~/.claude/projects/-home-kyle-claude-remindly/${SESSION_ID}.jsonl
BASELINE_LINES=$(wc -l < "$SENTINEL")
```

The watcher reads all lines from baseline forward, preventing race conditions.

**Step 3: Launch compact watcher (background subagent)**

The message-watcher continues running during compaction. The compact watcher runs alongside it as a second background subagent.

**Compact watcher parameters:**
- **Type:** Background Task subagent
- **Inputs:** JSONL path, baseline line count
- **Behavior:** Poll every ~1 second, read lines > baseline, parse as JSON, match `{"type": "system", "subtype": "compact_boundary"}` field-by-field
- **Malformed JSON:** Skip line, continue
- **Timeout:** 5 minutes from launch → treat as compact failure (see Step 5 failure path)
- **On detection:** INSERT completion message into `orchestration_messages` (task_id, message='compact_complete', type='system'), then exit
- **Conductor polls** comms-link for that message

See RAG: `compact-detection-jsonl-signals.md` for signal details.

If the message-watcher exits during compaction (detects state change from another Musician), handle via normal Message-Watcher Exit Protocol, relaunch watcher, continue waiting for compact watcher completion.

**Step 4: Launch compact session**
```bash
kitty --directory /home/kyle/claude/remindly \
  --title "Compact: task-XX" \
  -- env -u CLAUDECODE claude \
  --resume $SESSION_ID "/compact" &
echo $! > temp/musician-task-XX.pid
```

> **Note:** `/compact` is a built-in Claude Code command that triggers context compaction within the session. It is not a skill invocation.

Watcher launches BEFORE compact session — prevents race condition.

**Step 5: Watcher reports completion → Kill compacted session**

*Success path (compact_complete message detected):*
```bash
PID=$(cat temp/musician-task-XX.pid)
kill -0 $PID 2>/dev/null && kill $PID
rm temp/musician-task-XX.pid
```

> **Note:** The Step 5 session never auto-closes — after `/compact` finishes, the session sits idle waiting for input. PID reuse is not a realistic risk, but the defensive `kill -0` check is responsible practice and maintains consistency with patterns in `error-recovery.md`.

*Failure path (watcher times out without detecting `compact_boundary`):*
1. Watcher times out (5 min) without detecting `compact_boundary`
2. Conductor checks compact session PID — alive or dead?
3. If alive: kill it (compact hung)
4. If dead: scan JSONL from baseline forward one final time (signal may have been written just before timeout)
5. If signal found in final scan: proceed normally (resume session)
6. If no signal: compact failed — fall back to existing fresh-session-with-HANDOFF launch. Log to learnings file.

**Step 6: Resume with continuation prompt**

Uses the existing replacement-session-launch template from `musician-lifecycle.md`, with `--resume $SESSION_ID` added. The session wakes up with compacted context intact.

`worked_by` increments on compact resume to track compaction boundaries. Each compaction is a new generation even though the session ID is preserved via `--resume`.

```bash
kitty --directory /home/kyle/claude/remindly \
  --title "Musician: task-XX (S{N})" \
  -- env -u CLAUDECODE claude \
  --resume $SESSION_ID \
  --permission-mode acceptEdits "/musician
  ...existing replacement-session-launch prompt template..." &
echo $! > temp/musician-task-XX.pid
```

`--resume` preserves the same session ID. The guard clause's `session_id` assignment is a no-op on resumed sessions — the WHERE clause still matches (`state IN ('watching', 'fix_proposed', 'exit_requested')`), so the claim succeeds. `worked_by` increments to track the compaction boundary.

**Step 7: Update database state**

Set `fix_proposed` and send handoff message. See `musician-lifecycle.md` → `clean-handoff` section for exact SQL template. The resumed session claims the task via the existing guard clause.

**Step 8: Return to monitoring**

Proceed to SKILL.md → Message-Watcher Exit Protocol to ensure the watcher is running.

### Sentinel Handling During Compaction

If the Sentinel reports a stall for a task currently undergoing compaction: relaunch the message-watcher per the Message-Watcher Exit Protocol (the watcher exited to deliver the Sentinel report), then discard the Sentinel finding — the session is intentionally down.

### Repetiteur Variant

The Compact Protocol as specified targets Musicians. Repetiteur compaction follows the same sequence but uses `temp/repetiteur.pid` for PID and tracks session ID via Conductor state (no database row). Detailed Repetiteur variant is scoped to the Repetiteur externalization workstream.

### What Doesn't Change

- Musician's HANDOFF writing flow
- Musician's context warning reporting
- Replacement-session-launch prompt template (reused, just adds `--resume`)
- `worked_by` succession pattern (now explicitly increments on compact resume)
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

SKILL.md preamble: when `--recovery-bootstrap` is present, bypass Initialization Protocol and enter Recovery Bootstrap Protocol directly. Exact wording: "After loading this skill: if your invocation includes `--recovery-bootstrap`, proceed directly to the Recovery Bootstrap Protocol (skip Initialization Protocol entirely). Otherwise, proceed to the Initialization Protocol."

### Sequence

**Step 0: Heartbeat Agent**

Launch a background subagent immediately:

**Heartbeat agent parameters:**
- **Type:** Background Task subagent
- **Immediate action:** UPDATE task-00 `session_id` and `last_heartbeat`
- **SQL:** `UPDATE orchestration_tasks SET session_id = '{SESSION_ID}', last_heartbeat = datetime('now') WHERE task_id = 'task-00';`
- **Loop:** Refresh `last_heartbeat` every 60s (matches message-watcher cadence; both well within Souffleur's 240s staleness threshold)
- **Kill protocol:** Conductor INSERTs into `orchestration_messages` (task_id='task-00', message='heartbeat_agent_shutdown', type='system'). Agent polls for this message each loop iteration and exits when found.
- **Error handling:** UPDATE failure → log, continue looping (transient)

Serves two purposes: Souffleur discovers the new session ID by polling `orchestration_tasks` for a changed `session_id` on `task-00`, and heartbeat stays fresh during the lengthy recovery process.

**Step 1: Read Session Summary**

Read the export file at the path provided via `{EXPORT_PATH}` substitution in the Souffleur's launch prompt. Format is clean markdown with "Files Modified" summary at the top (per Souffleur `conductor-relaunch.md`).

Truncation behavior: Souffleur preserves the "Files Modified" summary at the top PLUS the most recent ~800k chars. The middle of the conversation is cut, not the head or tail. The Conductor always gets file inventory + recent work.

What to extract: read as context — don't parse, just absorb.

If the path is invalid or the file is empty: treat as crash scenario, proceed to Step 2 fallback reads.

**Step 2: Read Handoff**

Read handoff from `temp/HANDOFFS/Conductor/handoff.md` — single file, overwritten each time. Freeform markdown, not structured for parsing. Content is whatever the dying Conductor considered useful: current phase, active tasks, pending events, in-progress decisions, notes.

Read MEMORY.md now for the plan path. Step 5 revisits MEMORY.md for broader state reconstruction.

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

If the file does not exist (first Conductor generation), note "first generation" and continue.

**Step 4: Staged Context Tests**

Structured self-assessment before proceeding. Each stage validates sufficient understanding to orchestrate.

*Stage 1 — After session history + handoff/fallbacks:*
- Can you state the project's goal(s)?
- Can you identify the docs/ directory structure and expectations per subdirectory?
- If fails: re-read any large-scope documents not yet loaded. If truncated export caused failure, supplement with crash-path fallback files (plan overview, docs READMEs).

*Stage 2 — State awareness:*
- Can you state the current phase number and what it covers?
- Can you identify which tasks are active, completed, and pending?
- If fails: query comms-link more thoroughly. Read current phase section from plan.

Stage 2 may require querying comms-link before Step 5's formal state reconstruction. This is expected — Stage 2 tests whether you can orient from the export and handoff alone, with database queries as the fallback that confirms you need Step 5's full reconstruction.

*Stage 3 — Protocol fluency:*
- Can you name each step of the Phase Execution Protocol's implementation loop?
- Action: read the full Phase Execution Protocol section from SKILL.md before jumping in mid-flow.
- If fails: re-read SKILL.md Protocol Registry and Phase Execution Protocol reference. If still unable to articulate the loop: halt and report to user — recovery session may be corrupted.

**Step 5: State Reconstruction**

Parallel reads where possible:
- Read MEMORY.md (plan path, pending event notes)
- Load memory graph (`read_graph` from memory MCP)
- Schema verification (`PRAGMA table_info` — confirm, do NOT recreate)
- Hook verification (hooks.json, session-start-hook.sh, stop-hook.sh, comms.db accessible)
- Git branch verification (`scripts/check-git-branch.sh`)
- Verify `temp/` exists
- Query full task state: `SELECT * FROM orchestration_tasks WHERE task_id NOT IN ('task-00', 'souffleur')`
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

**Repetiteur triage:** Check `temp/repetiteur.pid`. If exists: check PID liveness. If alive: kill it (Repetiteur cannot continue without a Conductor to communicate with). Remove PID file. Re-invoke later if needed.

**Step 7: Settle & Review Completions**

Let in-flight Musicians finish current work. Review completion reports of most recently completed task(s) via `orchestration_tasks.report_path`.

**Step 8: Adversarial Phase Validation**

Launch read-only validation teammates:

- **Launch:** Task tool, 2 parallel teammates, Opus
- **Timeout:** 5 minutes each
- **Context cost mitigation:** If current phase has ≤2 tasks, collapse to a single teammate covering both scopes.

**Teammate A — Recent Task Review:**
- Read task instruction files + work output (report, git diff, test results) for most recently completed/active task(s)
- Prose summary of deviations, errors, incomplete steps

**Teammate B — Phase Coherence Review:**
- Read ALL task instruction files for current phase + completion states from DB
- Prose summary of integration issues, conflicts, sequencing problems

Both are read-only at this stage. Both report prose findings to Conductor. All findings feed step 9.

> **Note:** The teammates bear the context cost in their own windows — the Conductor only receives prose finding summaries.

**Step 9: Corrective Action**

Based on teammate findings:
1. `git status` — assess working tree state
2. If work is unusable: `git revert` (not `git reset --hard` — reversible, preserves history) of affected commits, re-queue tasks (SET state back to `watching`, clear `session_id` and `worked_by`)
3. If work has fixable flaws: single file with obvious correction → Conductor fixes directly. Multiple files or design decisions → delegate to teammate.
4. If work is sound: proceed — no action needed
5. Errors flagged from step 6: re-assess with full context, redo affected steps or re-queue as needed

**Step 10: Launch Message Watcher**

Kill heartbeat agent from step 0 (INSERT into `orchestration_messages`: task_id='task-00', message='heartbeat_agent_shutdown', type='system'). Launch message watcher (takes over heartbeat refreshing). Full operational monitoring now active.

**Step 11: Resume Phase Execution**

Return to SKILL.md → Phase Execution Protocol at current phase. Proceed with plan.

### What This Protocol Does NOT Do

- Does not re-run Initialization Protocol (bypassed by launch flag)
- Does not recreate DB tables (schema verification only)
- Does not wait for user approval (already granted during original init)
- Does not re-launch the Souffleur (already running — it launched this Conductor)
- Does not have access to old teammates or subagents (completely new session)

### Conductor Context Self-Detection

The Conductor detects its own context exhaustion via the same platform-level context warnings that Musicians receive. No custom monitoring infrastructure is needed — Claude Code surfaces context usage warnings naturally. When the Conductor observes it is approaching context limits, it enters the `context-exhaustion-trigger` sequence (see error-recovery.md changes below).

---

## Initialization Protocol Changes

### Schema Changes

**CHECK constraint — two new states (retroactive DDL alignment):**

These states are retroactive DDL alignment — the Souffleur skill (v1.1) already depends on them. Without these additions, the current CHECK constraint would violate at runtime if the Souffleur were deployed.

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

> **Scope distinction:** `exit_requested` = Conductor→Musician signal (existing, used for session exits, user consultation). `context_recovery` = Conductor→Souffleur signal (new, specifically for Souffleur-managed recovery after context exhaustion). Both coexist with different semantics and different downstream behaviors: `exit_requested` → session simply exits; `context_recovery` → Souffleur kills and relaunches.

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
  watching → confirmed → complete
  watching → error → [retry] → confirmed → complete
  watching → error → ... (x3) → exited
```

> **Note:** The Souffleur row stays `confirmed` for the duration of normal operations. There is no `confirmed → watching` transition.

**Hook exit criteria updated:** `context_recovery` is a terminal state that allows session exit.

### SKILL.md Preamble Update

Exact replacement for the current unconditional instruction:

> "After loading this skill: if your invocation includes `--recovery-bootstrap`, proceed directly to the Recovery Bootstrap Protocol (skip Initialization Protocol entirely). Otherwise, proceed to the Initialization Protocol."

---

## Existing Reference File Modifications

### musician-lifecycle.md

**`context-exhaustion-flow` section — replaced with redirect:**

When a Musician exits due to context exhaustion (state = `exited`, HANDOFF present), proceed to SKILL.md → Compact Protocol. The Compact Protocol handles the full cycle. This is the direct trigger for the Compact Protocol.

Current section content (fresh session rationale, "No `--resume` for exhaustion") is removed.

**`handoff-types` table — updated:**

Context Exit row changes from "Simplified automation (see context-exhaustion-flow section)" to "Compact and resume (see Compact Protocol via SKILL.md)."

**All other sections unchanged.**

### error-recovery.md

**New section: `context-exhaustion-trigger`**

The Conductor's pre-death sequence when it detects its own context exhaustion. Strict ordering — `context_recovery` is the kill trigger:

1. Write handoff to `temp/HANDOFFS/Conductor/handoff.md` — current phase, active tasks, pending events, notes. Single file, overwritten.
2. Update MEMORY.md — plan path, handoff location, active task PIDs
3. Close all external Musician sessions:
   ```
   For each active Musician task:
     1. UPDATE state = 'exited' WHERE task_id = '{task_id}'
     2. kill -0 $(cat temp/musician-{task_id}.pid) 2>/dev/null && kill $(cat temp/musician-{task_id}.pid)
     3. rm temp/musician-{task_id}.pid
   ```
   States must be set to `exited` BEFORE sending SIGTERM. Otherwise the stop hook blocks session exit for Musicians in non-terminal states like `working` or `needs_review`.
4. **(Last step, `<mandatory>`):** Set `task-00` state to `context_recovery`

**`context-warning-protocol` section — addition of Conductor self-monitoring concern:**

When the Conductor itself is running low on context (not the Musician), route to `context-exhaustion-trigger` instead of continuing to orchestrate. The Conductor detects its own context exhaustion via the same platform-level context warnings that Musicians receive — no custom monitoring infrastructure needed.

### repetiteur-invocation.md

**Substantial rework — externalization:**

| Aspect | Current | New |
|--------|---------|-----|
| Launch | Task tool as teammate | Kitty window via Bash |
| Communication | SendMessage | `repetiteur_conversation` table via comms-link |
| Context model | Shares Conductor's context | Independent session |
| Compactable | No | Yes (via Compact Protocol) |
| Session management | Task tool | Conductor manages PID |

**Communication protocol (Conductor side):**
- `sender` values: `'conductor'`, `'repetiteur'`, `'user'` (user input relayed by Conductor)
- New message detection: each side tracks its last-read `id`. Poll with `WHERE id > $LAST_READ_ID AND sender != $SELF ORDER BY id`
- Polling interval: ~3 seconds during active consultation
- Conversation end signal: Repetiteur inserts a message with `[HANDOFF]` prefix, same as current SendMessage handoff pattern
- Message format: free text, same as current SendMessage content

**Sections reworked:**
- `spawn-prompt-template` — Kitty launch, PID capture to `temp/repetiteur.pid`
- `consultation-communication` — comms-link polling instead of SendMessage
- `passthrough-communication` — user input relayed via INSERT into conversation table
- `handoff-reception` — handoff delivered via conversation table INSERT

**Sections unchanged (content-wise):**
- `pre-spawn-checklist`, `consultation-count-check`, `pause-musicians`, `blocker-report-format`, `blocker-report-persistence`, `blocker-report-preparation`, `escalation-context`, `task-annotation-matching`, `plan-changeover`, `superseded-plan-handling`

**`error-scenarios` — updated:** Repetiteur crash is now a kitty window/PID death, detected via PID check or conversation table silence.

**New capability:** Repetiteur can be compacted via Compact Protocol when it hits context exhaustion during consultation.

> **PID naming:** The Repetiteur uses `temp/repetiteur.pid`, diverging from `temp/musician-task-XX.pid`. The Souffleur skill manages its own PID file (`temp/souffleur-conductor.pid`) — that convention is defined in the Souffleur skill, not this design. The Repetiteur is a singleton so task-ID-based naming is unnecessary.

> **Note:** SKILL.md's `repetiteur-protocol` section (lines 228-247) must also be rewritten to reflect the external Kitty session + comms-link model. The current text references "teammate," "SendMessage," and "Task tool" — all of which change.

**Note:** The Repetiteur skill itself needs separate updates to use comms-link. Not part of this design. However, the Conductor-side changes to `repetiteur-invocation.md` must be implemented fully so the Repetiteur skill has a complete template to work from.

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

- **Creation:** Lazy — append creates the file if it doesn't exist. No explicit creation step during initialization.
- Appended throughout execution — during reviews, error recovery, phase transitions
- Read by Recovery Bootstrap Protocol (step 3) on every Conductor generation. If the file does not exist (first Conductor generation), note "first generation" and continue.
- **Rotation:** None — `temp/` handles cleanup on reboot.
- **Archival:** None — learnings that matter get proposed to RAG/memory graph via the existing proposal mechanism.
- Lives in `temp/` — cleared on reboot. Scoped to a single orchestration run.

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
| `SKILL.md` | Protocol registry (+2), preamble (`--recovery-bootstrap` bypass), `context_recovery` state docs, `repetiteur-protocol` section rewrite for externalization |
| `references/initialization.md` | Schema (CHECK +2 states, Souffleur row, `repetiteur_conversation` table), Souffleur launch, hard gate, message watcher |
| `references/musician-lifecycle.md` | `context-exhaustion-flow` → Compact Protocol redirect, `handoff-types` table |
| `references/error-recovery.md` | New `context-exhaustion-trigger` section, `context-warning-protocol` Conductor self-monitoring addition |
| `references/repetiteur-invocation.md` | Externalization — Kitty launch, conversation table, PID management, communication protocol |
| `references/phase-execution.md` | Souffleur row exclusion in monitoring queries (`task_id NOT IN ('task-00', 'souffleur')` or `task_id LIKE 'task-%'`), learnings file touchpoint |
| `references/completion.md` | Souffleur row exclusion in verification queries |
| `references/review-protocol.md` | Learnings file touchpoint |
| `tools/implementation-hook/stop-hook.sh` | Add `context_recovery` to terminal states for task-00 |

### Runtime Artifacts (Created During Execution)

| Artifact | Purpose |
|----------|---------|
| `temp/HANDOFFS/Conductor/handoff.md` | Conductor handoff document (single file, overwritten) |
| `temp/conductor-learnings.log` | Cross-session learnings (lazy-created) |

---

## Cross-Skill Dependencies

| Dependency | Status | Notes |
|------------|--------|-------|
| **Souffleur skill** | Staged, not deployed | Must be deployed before Recovery Bootstrap can be tested. Complete SKILL.md (v1.1) and 6 reference files in `skills_staged/souffleur/` |
| **Repetiteur skill** | Needs update | Must update to use comms-link conversation table. Conductor side must be fully implemented first as template. Separate workstream. |
| **Musician skill** | No changes | Existing HANDOFF/exit flows unchanged. Compact Protocol is Conductor-side. |
| **Copyist skill** | No changes | Can be compacted via Compact Protocol but skill itself unchanged. |

## RAG References

| Entry | Used By |
|-------|---------|
| `compact-detection-jsonl-signals.md` | Compact Protocol — `compact_boundary` signal detection |
| `external-session-management.md` | Compact Protocol, Recovery Bootstrap — session launch patterns |
| Kitty PID discovery entry | Initialization — Souffleur launch |

---

## Implementation Context

Context from the design brainstorming and review sessions, preserved for implementation.

### Key Technical Facts

- **`/compact` is a built-in Claude Code command** — not a skill. It triggers context compaction within a session.
- **`--resume` preserves the same session ID** — the guard clause's `session_id` assignment is a no-op on resumed sessions. `worked_by` still increments to track compaction boundaries.
- **Souffleur export truncation** preserves the "Files Modified" summary at the top PLUS the most recent ~800k chars. The middle of the conversation is cut, not the head or tail. The Conductor always gets file inventory + recent work.
- **The Compact Protocol Step 5 session never auto-closes** — after `/compact` finishes, the session sits idle waiting for input. The Conductor kills it. PID reuse is not a realistic risk but defensive `kill -0` is used for consistency.
- **`$CLAUDE_SESSION_ID` is injected by the SessionStart hook** — it is a system prompt value, NOT a bash environment variable. The Conductor references it in its own context.
- **`$SESSION_ID` in Compact Protocol refers to the child session's ID** (retrieved via SQL from `orchestration_tasks.session_id`), NOT the Conductor's own `$CLAUDE_SESSION_ID`.

### Architecture Evolution

The design went through significant evolution during brainstorming:

1. **Originally three protocols** — Compact Protocol, Context-Recovery Protocol, and Crash Recovery Protocol as separate flows.
2. **Merged to two** — Context-Recovery and Crash Recovery merged into a unified Recovery Bootstrap Protocol when analysis showed the flows genuinely converge. The only branch point is handoff existence (Step 2).
3. **Compact Protocol scope narrowed** — Originally had two entry points (`<external-session>` and `<conductor-session>`). The `<conductor-session>` entry point was eliminated when the Souffleur was discovered to handle Conductor recovery. The Conductor no longer manages its own compaction — it signals `context_recovery` and the Souffleur handles kill/export/relaunch.
4. **Single flag** — Originally two flags (`--crash-recovery-protocol`, `--context-recovery-protocol`). Merged to single `--recovery-bootstrap` flag. The Souffleur's launch prompt text provides crash vs planned context via `{RECOVERY_REASON}` substitution.

### Repetiteur Externalization Scope

The Repetiteur skill is unbuilt. The Conductor-side changes to `repetiteur-invocation.md` must be implemented fully so the Repetiteur skill has a complete template to work from. Key Conductor-side specs:

- Kitty launch with PID capture to `temp/repetiteur.pid`
- `repetiteur_conversation` table DDL (in initialization.md)
- Polling protocol: sender values (`conductor`, `repetiteur`, `user`), `WHERE id > $LAST_READ_ID AND sender != $SELF ORDER BY id`, ~3s polling
- Conversation end signal: `[HANDOFF]` prefix on Repetiteur's final message
- Compaction via Compact Protocol using `temp/repetiteur.pid` and session ID tracked in Conductor state (no DB row)
- Recovery Bootstrap Step 6 triage: kill orphaned Repetiteur via PID file

### Stale Artifacts Removed

- `docs/plans/2026-02-21-context-recovery-implementation.md` — deleted. This was the old Souffleur-side plan with dual-flag pattern (`--crash-recovery-protocol`/`--context-recovery-protocol`). Caused review agent confusion.

---

## Appendix: Review Provenance

This design was validated by an 8-agent parallel review (2026-02-22):

| # | Focus | Model |
|---|-------|-------|
| 1 | Broad skill-review — design as Conductor update | Haiku |
| 2 | Broad skill-review — design as Conductor update | Opus |
| 3 | Compact Protocol integration tracing | Opus |
| 4 | Recovery Bootstrap Protocol integration tracing | Opus |
| 5 | Incorrect assumptions — verify claims against source files | Opus |
| 6 | Skill-as-skill quality — new protocols as LLM instructions | Haiku |
| 7 | Skill-as-skill quality — new protocols as LLM instructions | Opus |
| 8 | Self-contained completeness — design read in isolation | Opus |

**Results:** 41 factual claims verified (39 accurate, 2 corrected). 49 findings total: 6 critical, 10 important, 25 suggestions. All findings resolved and incorporated into this document.

**Consensus strengths confirmed by 3+ agents:**
1. Kill → baseline → watcher → compact → detect → kill → resume sequence correctly ordered
2. Souffleur integration is bidirectionally consistent
3. "What Doesn't Change" sections prevent scope creep
4. Musician Triage table is exhaustive and actionable
5. Staged Context Tests are an innovative pattern
6. Database schema changes are minimal and additive
7. Learnings file is appropriately lightweight
8. `context-exhaustion-trigger` ordering prevents Souffleur race
9. Progressive disclosure correctly places protocols in reference files
10. File inventory makes implementation scope clear

The full review with individual finding details, agent attributions, and cross-reference matrix is preserved in `2026-02-22-conductor-recovery-design-review.md`.
