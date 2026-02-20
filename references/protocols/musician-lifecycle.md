<skill name="conductor-musician-lifecycle" version="3.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Musician Lifecycle Protocol
</metadata>

<sections>
- pid-tracking
- cleanup-rules
- handoff-types
- clean-handoff
- dirty-handoff
- crash-handoff
- retry-exhaustion
- context-exhaustion-flow
- post-completion-resume
- worked-by-succession
- guard-clause-reclaiming
- claim-collision-recovery
- replacement-session-launch
- high-context-verification
- context-situation-checklist
- terminal-states
</sections>

<section id="pid-tracking">
<core>
# Musician Lifecycle Protocol

## PID Tracking

Every Musician kitty window launch captures its process ID for lifecycle management.

**On launch:**
<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: task-XX" -- env -u CLAUDECODE claude --permission-mode acceptEdits "prompt" &
echo $! > temp/musician-task-XX.pid
```
</template>

**On cleanup:**
```bash
PID=$(cat temp/musician-task-XX.pid)
kill $PID  # SIGTERM for clean termination
rm temp/musician-task-XX.pid
```

The PID file is the Conductor's handle for managing that specific session. Without it, the Conductor cannot target a specific window for cleanup.
</core>
</section>

<section id="cleanup-rules">
<mandatory>
## Cleanup Rules

Three rules govern when Musician kitty windows are closed:

1. **Parallel tasks:** Close all windows when ALL parallel siblings reach `complete`/`exited`. Do not close one-by-one as they finish — wait for the full set.

2. **Sequential tasks:** Close immediately when the task reaches `complete`/`exited`. No waiting.

3. **Re-launch (handoff):** Close old session IMMEDIATELY before launching the replacement. Never have two kitty windows for the same task simultaneously. Kill PID first, then launch new window.
</mandatory>
</section>

<section id="handoff-types">
<core>
## Handoff Types

When a Musician session exits, the Conductor determines the handoff type and responds accordingly.

| Type | Condition | Key Difference | Conductor Action |
|------|-----------|---------------|---------------------|
| **Clean** | HANDOFF present, context <80% | Standard path | Read HANDOFF, set `fix_proposed`, send handoff msg, close window, launch replacement |
| **Dirty** | HANDOFF present, context >80% | Hallucination risk | Same as clean BUT include test verification instructions in msg |
| **Crash** | No HANDOFF doc | Emergency state | PID check first, then send msg with verification instructions for last completed steps |
| **Retry Exhaustion** | 5th retry failure | Conductor error | Escalate — route to Error Recovery Protocol, then potentially Repetiteur Protocol |
| **Context Exit** | Clean exit due to context management | Not an error | Simplified automation (see context-exhaustion-flow section) |

<mandatory>For all handoff types: close the old kitty window (kill PID) BEFORE launching any replacement. Read the PID file, SIGTERM the process, remove the PID file, then proceed.</mandatory>
</core>
</section>

<section id="clean-handoff">
<core>
## Clean Handoff Procedure

When Musician exits cleanly with HANDOFF doc and context <80%:

1. Detect exit: state = `exited` in orchestration_tasks
2. Close kitty window (kill PID, remove PID file)
3. Read `temp/task-NN-HANDOFF`
4. Set state to `fix_proposed` and send handoff message

<template follow="format">
```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'HANDOFF RECEIVED: Musician session exited cleanly due to context exhaustion.
     Previous session: {worked_by}
     HANDOFF: temp/{task-id}-HANDOFF
     Context usage: {XX}%
     Next musician: {worked_by-SN}
     Action: Replacement session launched automatically.',
    'handoff'
);
```
</template>

5. Launch replacement session (see replacement-session-launch section)
</core>
</section>

<section id="dirty-handoff">
<core>
## Dirty Handoff Procedure

When HANDOFF is present BUT context >80% (hallucination risk from context-exhausted session):

Same as clean handoff, BUT the handoff message includes test verification instructions:

```
Previous session context was {XX}% (potential hallucination risk).
Before proceeding: Re-run ALL verification tests from last completed checkpoint.
If any fail, do NOT trust the test results in the HANDOFF — use your own judgment.
```

High-context sessions may have produced code that looks correct but contains subtle logic errors from attention degradation. Tests are ground truth, not session claims.
</core>
</section>

<section id="crash-handoff">
<core>
## Crash Handoff Procedure

When no HANDOFF doc exists (Musician crashed without graceful exit):

<mandatory>Check PID status FIRST before declaring crash type.</mandatory>

1. **PID alive but heartbeat stale:** Watcher died but session is stuck (looping, frozen). Kill PID — the session isn't making progress.
2. **PID dead:** Session genuinely crashed. Proceed with crash recovery.

After determining crash type:

3. Close kitty window (kill PID if alive, remove PID file)
4. Read `temp/task-NN-status` for last known state (this file survives crashes)
5. Set state to `fix_proposed` and send crash recovery message

<template follow="format">
```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'CRASH DETECTED: No HANDOFF doc. Previous session lost context or crashed.
     Last known state: temp/{task-id}-status
     Last completed: {step N} ({description})
     Context at crash: {XX}%
     Deviations logged: {N} ({details})
     Action: Replacement session launched. Verify step {N} results before resuming step {N+1}.
     Re-run: {specific tests} from step {N}.
     Do NOT trust results from step {N+1} (may be partial/broken).',
    'handoff'
);
```
</template>

6. Launch replacement session (see replacement-session-launch section)
</core>
</section>

<section id="retry-exhaustion">
<core>
## Retry Exhaustion Procedure

When Musician self-exits after 5 failed retries (retry_count = 5):

This is a signal that the error is beyond simple fixes. The Musician exhausted its retry budget without resolution.

<template follow="format">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'RETRY EXHAUSTION: Musician failed after 5 attempts.
     Root cause: {from HANDOFF}
     Last error: {details}
     Correction attempts: {summary of 5 fixes tried}',
    'handoff'
);
```
</template>

Close the kitty window (kill PID, remove PID file). Route to Error Recovery Protocol — the Conductor may attempt its own corrections or escalate to Repetiteur Protocol if the issue exceeds intra-phase authority.
</core>
</section>

<section id="context-exhaustion-flow">
<core>
## Context Exhaustion — Simplified Flow

When a Musician exits due to context management (the most common handoff scenario):

1. Detect exit: state = `exited` in orchestration_tasks
2. Close kitty window (kill PID, remove PID file)
3. Read `temp/task-NN-HANDOFF` for completed/pending steps
4. Set state to `fix_proposed` and send handoff message
5. Launch fresh replacement session with HANDOFF context in the prompt

No `--resume` for exhaustion — the session is already at its context limit. A fresh session with HANDOFF context is the correct approach. The HANDOFF doc tells the replacement session exactly where to pick up.
</core>
</section>

<section id="post-completion-resume">
<core>
## Post-Completion Error Correction

When a later task discovers an integration error with previously completed work, the Conductor can resume the original Musician's session to fix it. This leverages the original session's full context — it already knows what it built.

**Prerequisites:**
- Session ID is already stored in `orchestration_tasks.session_id` from the original claim
- Session data persists after kitty window closure
- `complete` remains terminal — a NEW task row is created for the fix

**Procedure:**

1. Create a fix task row:
<template follow="exact">
```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('{original-task-id}-fix', 'watching', NULL, datetime('now'));

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{original-task-id}-fix', 'task-00',
    'FIX TASK: Integration error found by {discovering-task-id}.
     Error: {description of the integration issue}
     Fix required: {specific correction needed}
     Original task: {original-task-id}
     Original session: {session-id from orchestration_tasks}',
    'instruction'
);
```
</template>

2. Retrieve the original session ID:
```sql
SELECT session_id FROM orchestration_tasks WHERE task_id = '{original-task-id}';
```

3. Launch resumed session:
<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: {original-task-id}-fix" -- env -u CLAUDECODE claude --resume "{SESSION_ID}" "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = '{original-task-id}-fix' AND message_type = 'instruction';

Read the returned message. It contains your fix instructions.

You are being resumed to correct an integration error discovered by a later task.
Your original context is intact — you already know what you built.
Claim the fix task row, apply the correction, verify, and report." &
echo $! > temp/musician-{original-task-id}-fix.pid
```
</template>

The resumed session claims the fix task row via comms-link and follows the normal orchestration flow (watcher, heartbeat, review). If it exhausts context during the fix, it exits cleanly with a HANDOFF — the fix task row keeps it covered.
</core>
</section>

<section id="worked-by-succession">
<core>
## Worked_By Succession Pattern

When re-claiming a task for a new Musician session, increment the suffix:

1. Read current `worked_by` value from orchestration_tasks
2. Parse:
   - If `musician-task-NN` (no suffix): append `-S2` → `musician-task-NN-S2`
   - If `musician-task-NN-SN`: increment N → `musician-task-NN-S{N+1}`
3. Update `worked_by` atomically with the state change during claim

```
First session:  worked_by = 'musician-task-03'
Second session: worked_by = 'musician-task-03-S2'
Third session:  worked_by = 'musician-task-03-S3'
```
</core>
</section>

<section id="guard-clause-reclaiming">
<core>
## Guard Clause Re-Claiming

When Conductor sets `fix_proposed`, the next session can claim:

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET state = 'working',
    session_id = '$CLAUDE_SESSION_ID',
    worked_by = 'musician-task-03-S2',
    started_at = datetime('now'),
    last_heartbeat = datetime('now'),
    retry_count = 0
WHERE task_id = 'task-03'
  AND state IN ('watching', 'fix_proposed', 'exit_requested');
```
</template>

Only 3 states are claimable: `watching`, `fix_proposed`, `exit_requested`. Verify `rows_affected = 1`. If 0, the guard blocked — create a fallback row (see claim-collision-recovery section).
</core>
</section>

<section id="claim-collision-recovery">
<core>
## Claim Collision Recovery

When a Musician session fails to claim a task (guard clause blocks because another session already claimed it):

**Fallback row creation (by the blocked Musician):**

<template follow="exact">
```sql
INSERT INTO orchestration_tasks (task_id, state, session_id, last_heartbeat)
VALUES ('fallback-$CLAUDE_SESSION_ID', 'exited', '$CLAUDE_SESSION_ID', datetime('now'));

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('{task-id}', '$CLAUDE_SESSION_ID',
    'CLAIM BLOCKED: Guard prevented claim on {task-id}. Created fallback row to exit cleanly.',
    'claim_blocked');
```
</template>

**Conductor's autonomous response (upon detecting claim_blocked):**

1. Close the failed Musician's kitty window (kill PID, remove PID file)
2. Check the original task's state — was it successfully claimed by another session?
3. If yes: the collision is resolved, clean up the fallback row
4. If no (task still in claimable state): reset the task row, re-insert instruction message, re-launch a new Musician
5. If second claim also fails: report to user for manual investigation

<template follow="exact">
```sql
-- Clean up fallback row after resolution
DELETE FROM orchestration_tasks WHERE task_id = 'fallback-{session-id}';
```
</template>
</core>
</section>

<section id="replacement-session-launch">
<core>
## Replacement Session Launch

When launching a replacement Musician after any handoff type:

<mandatory>Close the old kitty window BEFORE launching the replacement. Kill PID, remove PID file, THEN launch.</mandatory>

**Step 1: Close old session**
```bash
PID=$(cat temp/musician-task-XX.pid)
kill $PID
rm temp/musician-task-XX.pid
```

**Step 2: Output progress to terminal**
```
Task-XX musician exited.
Previous session: {worked_by}
Exit type: {clean/dirty/crash}
Context usage: XX%
Last completed step: {description}
Launching replacement session...
```

**Step 3: Launch replacement**

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: task-XX (S{N})" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = 'task-XX' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

Previous session: {worked_by}
New session will be: {worked_by-SN}
Read HANDOFF from temp/ for context.

**Context:**
- Task ID: task-XX
- Phase: {N} — {PHASE_NAME}

Do not proceed without reading the full instruction message. All steps are there." &
echo $! > temp/musician-task-XX.pid
```
</template>
</core>
</section>

<section id="high-context-verification">
<mandatory>
## High-Context Verification Rule

When resuming a task where the previous session had context >80%:

1. Re-run ALL verification tests from the last completed checkpoint
2. Compare test results to what's in HANDOFF or status file
3. If any discrepancies: do NOT trust previous session's assertions
4. If tests fail: diagnose whether previous session's code is broken or tests are environmental
5. Only resume work if tests pass with your own execution

High-context exhaustion (>80%) means the previous session was operating near capacity — likely hallucinating. Tests are ground truth, not session claims.
</mandatory>
</section>

<section id="context-situation-checklist">
<core>
## Context Situation Checklist

When evaluating a context-exhausted Musician's proposal, assess:

- [ ] Self-correction flag active? (YES = context estimates ~6x bloat)
- [ ] How many deviations and severity? (high severity + high context = risky)
- [ ] How many steps to next checkpoint? (far = higher risk)
- [ ] Remaining agents and cost per agent? (many + high cost = likely to exceed budget)
- [ ] Prior context warnings on this task? (multiple = pattern of scope creep)
- [ ] Proposed action specificity? (vague = less confidence)

Use results to choose response: `review_approved` (low risk, proceed with Musician's proposal), `fix_proposed` (override scope — "Only do X then prepare handoff"), or `review_failed` (stop now, prepare handoff immediately).
</core>
</section>

<section id="terminal-states">
<core>
## Terminal States

`complete` and `exited` are terminal. No further state transitions after reaching either.

**`complete`:**
- Set by Musician after final approval and cleanup
- Hook allows session exit
- Session ID persists in database for potential post-completion resume

**`exited`:**
- Set by Musician for clean context exit, crash recovery, or retry exhaustion
- Set by Conductor for staleness cleanup (abandoned sessions)
- Hook allows session exit
- Triggers handoff procedure (Conductor determines type and responds)

The post-completion resume pattern (see post-completion-resume section) creates a NEW task row (`task-XX-fix`) rather than modifying a completed row. Terminal means terminal.
</core>
</section>

</skill>
