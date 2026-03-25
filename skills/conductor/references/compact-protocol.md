<skill name="conductor-compact-protocol" version="4.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Compact Protocol
</metadata>

<sections>
- purpose
- prerequisites
- sequence
- failure-handling
- sentinel-handling
- repetiteur-variant
- unchanged
</sections>

<section id="purpose">
<core>
# Compact Protocol

## Purpose

Handles compacting external child sessions (Musicians, Copyist, Repetiteur) when they hit context exhaustion. The Conductor manages the entire lifecycle. The session keeps its accumulated context rather than starting fresh.

**Direct trigger:** `musician-lifecycle.md` -> `context-exhaustion-flow` (replacing fresh-session-with-HANDOFF).

**Indirect path:** `error-recovery.md` -> `context-warning-protocol` -> Musician receives `review_failed` -> Musician writes HANDOFF and sets `exited` -> monitoring watcher detects `exited` -> event-routing -> Musician Lifecycle Protocol -> `context-exhaustion-flow` -> Compact Protocol. This path arrives via the Musician's exit flow.

<mandatory>Implementers must NOT add a direct jump from error-recovery to Compact Protocol. That would bypass the Musician's exit sequence. The only entry point is through `musician-lifecycle.md` -> `context-exhaustion-flow`.</mandatory>

**Repetiteur context exhaustion** (after externalization) follows the same protocol with minor differences — see repetiteur-variant section.
</core>
</section>

<section id="prerequisites">
<core>
## Prerequisites

Before entering this protocol, the Conductor has:

- The session's window and session identifiers (via session layer PID files)
- The session's session ID (from `orchestration_tasks.session_id`)
- A HANDOFF document written by the session (if one exists — the Compact Protocol preserves session context via `--resume`, so a missing HANDOFF is not blocking; the resumed session retains its own context of the work in progress)
- The task ID and current `worked_by` value

<mandatory>`$SESSION_ID` throughout this protocol refers to the CHILD session's ID retrieved from `orchestration_tasks.session_id` — NOT the Conductor's own `$CLAUDE_SESSION_ID`.</mandatory>

The Musician skill's existing exit flow (HANDOFF writing, `exited` state) is unchanged — only the Conductor's response changes.
</core>
</section>

<section id="sequence">
<core>
## Sequence

### Step 1: Close Old Session

```bash
source scripts/session-commands.sh
kill_claude_in_session "musician-primary"  # or "musician-task-XX" for parallel
```

### Step 2: Record Baseline

Retrieve the child session's ID (NOT the Conductor's own `$CLAUDE_SESSION_ID`):

```sql
SELECT session_id FROM orchestration_tasks WHERE task_id = '{task-id}';
```

Discover the JSONL path dynamically and count lines BEFORE launching compact:

```bash
SENTINEL=$(ls ~/.claude/projects/*/${SESSION_ID}.jsonl 2>/dev/null | head -1)
if [[ -z "$SENTINEL" ]]; then
    # Retry with short delay (JSONL may not be created yet)
    for i in $(seq 1 6); do
        sleep 5
        SENTINEL=$(ls ~/.claude/projects/*/${SESSION_ID}.jsonl 2>/dev/null | head -1)
        [[ -n "$SENTINEL" ]] && break
    done
fi
if [[ -z "$SENTINEL" ]]; then
    # Compact failure — fall back to fresh-session launch
    echo "JSONL not found for session $SESSION_ID — compact cannot proceed"
    # Route to failure-handling section
fi
BASELINE_LINES=$(wc -l < "$SENTINEL")
```

Cache the resolved SENTINEL path for reuse within the same compact cycle. The watcher reads all lines from baseline forward, preventing race conditions.

### Step 3: Launch Compact Watcher (Background Subagent)

The message-watcher continues running during compaction. The compact watcher runs alongside it as a second background subagent.

**Compact watcher parameters:**
- **Type:** Background Task subagent
- **Inputs:** JSONL path, baseline line count
- **Behavior:** Poll every ~1 second, read lines > baseline, parse as JSON, match `{"type": "system", "subtype": "compact_boundary"}` field-by-field
- **Malformed JSON:** Skip line, continue
- **Timeout:** 5 minutes from launch -> treat as compact failure (see failure-handling section)
- **On detection:** INSERT completion message into `orchestration_messages` (task_id, message='compact_complete', type='system'), then exit
- **Conductor polls** comms-link for that message

<template follow="format">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'compact-watcher',
    'compact_complete',
    'system'
);
```
</template>

<mandatory>The compact watcher's INSERT must include `message_type` — all INSERTs into `orchestration_messages` must specify type (no NULLs).</mandatory>

If the message-watcher exits during compaction (detects state change from another Musician): handle via normal Message-Watcher Exit Protocol, relaunch watcher, continue waiting for compact watcher completion.

See RAG: `compact-detection-jsonl-signals.md` for JSONL signal details and detection implementation patterns.

### Step 4: Launch Compact Session

<mandatory>Watcher launches BEFORE compact session — this prevents race conditions where the compact completes before the watcher begins monitoring.</mandatory>

```bash
source scripts/session-commands.sh
create_session "compact-task-XX" "$PROJECT_DIR"
ATTACH_CMD=$(get_terminal_cmd "compact-task-XX")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Compact: task-XX" \
    --dir "$PROJECT_DIR" \
    --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-compact-task-XX.pid
inject_session "compact-task-XX" \
    "env -u CLAUDECODE claude --resume $SESSION_ID /compact"
```

> `/compact` is a built-in Claude Code command that triggers context compaction within the session. It is not a skill invocation.

### Step 5: Watcher Reports Completion -> Kill Compacted Session

*Success path (compact_complete message detected):*

```bash
source scripts/session-commands.sh
destroy_session "compact-task-XX"
PID=$(cat temp/window-compact-task-XX.pid 2>/dev/null)
[[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
rm -f temp/window-compact-task-XX.pid
```

> The Step 4 session never auto-closes — after `/compact` finishes, the session sits idle waiting for input.

For failure path details, see failure-handling section.

### Step 6: Resume with Continuation Prompt

Uses the existing replacement-session-launch template from `musician-lifecycle.md`, with `--resume $SESSION_ID` added. The session wakes up with compacted context intact.

`worked_by` increments on compact resume to track compaction boundaries. Each compaction is a new generation even though the session ID is preserved via `--resume`.

Write the continuation prompt to `temp/task-XX-prompt.txt` (include previous session, worked_by-SN, HANDOFF reference). Then launch via session layer:

```bash
source scripts/session-commands.sh
# Reuse primary window for sequential, or create new for parallel
inject_session "musician-primary" \
    "env -u CLAUDECODE claude --resume $SESSION_ID --permission-mode $MUSICIAN_PERMISSIONS -p \"\$(cat temp/task-XX-prompt.txt)\""
```

`--resume` preserves the same session ID. The guard clause's `session_id` assignment is a no-op on resumed sessions — the WHERE clause still matches (`state IN ('watching', 'fix_proposed', 'exit_requested')`), so the claim succeeds. `worked_by` increments to track the compaction boundary.

### Step 7: Update Database State

Set `fix_proposed` and send handoff message. See `musician-lifecycle.md` -> `clean-handoff` section for exact SQL template. The resumed session claims the task via the existing guard clause.

<template follow="format">
```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'HANDOFF RECEIVED: Musician session compacted (context exhaustion).
     Previous session: {worked_by}
     HANDOFF: temp/{task-id}-HANDOFF
     Context usage: {XX}%
     Next musician: {worked_by-SN}
     Action: Compacted session resumed automatically via --resume.',
    'handoff'
);
```
</template>

### Step 8: Return to Monitoring

Proceed to SKILL.md -> Message-Watcher Exit Protocol to ensure the watcher is running.
</core>
</section>

<section id="failure-handling">
<core>
## Failure Handling

When the compact watcher times out (5 minutes) without detecting `compact_boundary`:

### Step 1: Watcher Times Out

The compact watcher reaches its 5-minute timeout without detecting the `compact_boundary` signal in the JSONL.

### Step 2: Check Compact Session PID

```bash
PID=$(cat temp/window-compact-task-XX.pid 2>/dev/null)
if [ -n "$PID" ] && kill -0 $PID 2>/dev/null; then
    echo "Compact session alive — compact hung"
else
    echo "Compact session dead — check for late signal"
fi
```

### Step 3: If Alive — Kill It (Compact Hung)

```bash
source scripts/session-commands.sh
destroy_session "compact-task-XX"
PID=$(cat temp/window-compact-task-XX.pid 2>/dev/null)
[[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
rm -f temp/window-compact-task-XX.pid
```

The compact session is still running but did not produce a completion signal within 5 minutes. It is hung — kill it.

### Step 4: If Dead — Final JSONL Scan

Scan JSONL from baseline forward one final time. The signal may have been written just before the timeout check.

```bash
# Use the cached SENTINEL path from Step 2
# Read lines from BASELINE_LINES forward, check for compact_boundary
```

Parse each line from baseline as JSON. Match `{"type": "system", "subtype": "compact_boundary"}` field-by-field. Skip malformed JSON lines.

### Step 5: Route Based on Final Scan Result

**Signal found in final scan:** Proceed normally — go to Step 6 (Resume with Continuation Prompt) in the sequence section.

**No signal found:** Compact failed. Fall back to existing fresh-session-with-HANDOFF launch from `musician-lifecycle.md` -> `replacement-session-launch`. Log the failure to the learnings file for post-mortem analysis.
</core>
</section>

<section id="sentinel-handling">
<core>
## Sentinel Handling During Compaction

If the Sentinel (from `sentinel-monitoring.md`) reports a stall for a task currently undergoing compaction:

1. Relaunch the message-watcher per the Message-Watcher Exit Protocol (the watcher exited to deliver the Sentinel report)
2. Discard the Sentinel finding — the session is intentionally down during compaction

The compact session does not write to temp/ status files, so the Sentinel's stall detection will trigger. This is expected and not actionable.
</core>
</section>

<section id="repetiteur-variant">
<context>
## Repetiteur Variant

The Compact Protocol as specified targets Musicians. Repetiteur compaction follows the same sequence but with these differences:

- **PID file:** `temp/window-repetiteur.pid` (instead of `temp/window-musician-*.pid`)
- **Session ID tracking:** Via Conductor state (no database row) — the Repetiteur does not have an `orchestration_tasks` entry
- **No `worked_by` succession:** The Repetiteur is a single-instance role, not a succession chain
- **No guard clause:** Repetiteur does not claim tasks via SQL guard clauses

Detailed Repetiteur compact variant is scoped to the Repetiteur externalization workstream.
</context>
</section>

<section id="unchanged">
<core>
## What Doesn't Change

The Compact Protocol reuses existing infrastructure without modification:

- **Musician's HANDOFF writing flow** — the Musician writes HANDOFF and sets `exited` as before
- **Musician's context warning reporting** — the error-recovery -> context-warning-protocol path is unchanged
- **Replacement-session-launch prompt template** — reused from `musician-lifecycle.md`, just adds `--resume`
- **`worked_by` succession pattern** — now explicitly increments on compact resume (consistent with existing behavior)
- **Database state transitions** — `exited` -> `fix_proposed` -> `working` follows the same path
- **High-context verification rule** — >80% context = re-run tests before trusting previous session's claims
</core>
</section>

</skill>
