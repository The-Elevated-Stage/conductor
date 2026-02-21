<skill name="conductor-state-machine" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- database-table
- conductor-states
- execution-states
- state-ownership
- state-transition-flows
- exited-state-details
- heartbeat-rule
- staleness-detection
- smoothness-scale
- retry-limits
- atomic-claim-pattern
- worked-by-succession
- fallback-row-pattern
</sections>

<section id="database-table">
<core>
# State Machine Reference

## Database Table

All state is stored in `orchestration_tasks` in `/home/kyle/claude/remindly/comms.db`.

Single `state` column with CHECK constraint enforcing exactly 11 valid values. No separate `status` column.
</core>
</section>

<section id="conductor-states">
<core>
## Conductor States (task-00)

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `watching` | Conductor | Monitoring execution tasks | No |
| `reviewing` | Conductor | Actively reviewing a submission | No |
| `exit_requested` | Conductor | Needs to exit (context full, user consultation) | Yes (hook allows exit) |
| `complete` | Conductor | All tasks done | Yes (hook allows exit) |

**Hook exit criteria:** Conductor session can only exit when state is `exit_requested` or `complete`.
</core>
</section>

<section id="execution-states">
<core>
## Execution States (task-01+)

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `watching` | Conductor | Inserted but no session has claimed it yet | No |
| `working` | Execution | Actively executing task steps (musician watcher monitors heartbeat) | No |
| `needs_review` | Execution | Review submitted, awaiting conductor | No |
| `review_approved` | **Conductor** | Approved, execution resumes | No |
| `review_failed` | **Conductor** | Rejected, execution revises | No |
| `error` | Execution | Hit an error, awaiting conductor fix | No |
| `fix_proposed` | **Conductor** | Fix sent, execution applies it | No |
| `complete` | Execution | Task finished successfully | Yes (hook allows exit) |
| `exited` | Execution OR Conductor | Terminated without completion | Yes (hook allows exit) |

**Hook exit criteria:** Execution session can only exit when state is `complete` or `exited`.
</core>
</section>

<section id="state-ownership">
<core>
## State Ownership Summary

**Conductor sets:** `watching`, `reviewing`, `exit_requested`, `complete`, `review_approved`, `review_failed`, `fix_proposed`, `exited` (heartbeat staleness only)

**Execution sets:** `working`, `needs_review`, `error`, `complete`, `exited` (5th retry failure)
</core>
</section>

<section id="state-transition-flows">
<core>
## State Transition Flows

```
Execution happy path:
  watching → [execution claims] → working → needs_review → [conductor: review_approved] → working → complete

Execution review rejection:
  working → needs_review → [conductor: review_failed] → working → needs_review → ...

Execution error path:
  working → error → [conductor: fix_proposed] → working → ...

Execution terminal (retry exhaustion):
  working → error → [conductor: fix_proposed] → working → error → ... (x5) → exited

Conductor happy path:
  watching → reviewing → watching → ... → complete

Conductor context exit:
  watching → exit_requested
```
</core>
</section>

<section id="exited-state-details">
<core>
## `exited` State Details

**When execution session sets it:**
- 5th error retry exhaustion (retry_count reaches 5, self-terminates with HANDOFF)
- Clean context exhaustion exit (context limit reached, writes HANDOFF, self-terminates)

**When conductor sets it:**
- Staleness detection (session disappeared, no heartbeat for >540s in transitional or working state)
- Explicitly abandoning an unrecoverable task
</core>
</section>

<section id="heartbeat-rule">
<mandatory>
## Heartbeat Rule

Update `last_heartbeat` on EVERY state transition:

```sql
UPDATE orchestration_tasks
SET state = 'needs_review', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';
```

All SQL in task instructions and conductor workflows MUST include `last_heartbeat = datetime('now')` alongside any `state` change. This enables staleness detection.
</mandatory>
</section>

<section id="staleness-detection">
<core>
## Staleness Detection

Monitoring subagent checks for stale transitional states:
</core>

<template follow="exact">
```sql
SELECT task_id, state,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE state IN ('review_approved', 'review_failed', 'fix_proposed', 'working')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
```
</template>

<context>
If detected: conductor sets `exited` with `last_error` explaining the staleness, then escalates to user.
</context>
</section>

<section id="smoothness-scale">
<core>
## Smoothness Scale (Review Quality)

Execution sessions self-report smoothness in review requests and completion messages:

| Score | Meaning |
|-------|---------|
| 0 | Perfect execution, no deviations |
| 1-2 | Minor clarifications needed, self-resolved |
| 3-4 | Some deviations from plan, documented |
| 5-6 | Significant issues, required conductor input |
| 7-8 | Major blockers, multiple review cycles |
| 9 | Failed or incomplete, needs redesign |

**Conductor review thresholds:**
- 0-4: Approve (`review_approved`)
- 5: Investigate before approving — correct errors via `fix_proposed` if found, then `review_approved`
- 6-7: Request revision (`review_failed` with specific feedback)
- 8-9: Reject (`review_failed` with detailed rejection and required changes)
</core>
</section>

<section id="retry-limits">
<core>
## Retry Limits

- **Execution retry_count:** 0-5. At retry 5, execution self-sets `exited`.
- **Conductor subagent retries:** 3 maximum. After 3, escalate to user.
- **retry_count** tracks error retries, not review cycles.
</core>
</section>

<section id="atomic-claim-pattern">
<core>
## Atomic Claim Pattern

Execution sessions claim tasks with a guarded UPDATE:
</core>

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET state = 'working',
    session_id = '$CLAUDE_SESSION_ID',
    worked_by = 'musician-task-03',
    started_at = datetime('now'),
    last_heartbeat = datetime('now'),
    retry_count = 0
WHERE task_id = 'task-03'
  AND state IN ('watching', 'fix_proposed', 'exit_requested');
```
</template>

<mandatory>Guard clause: Only 3 states are claimable (watching, fix_proposed, exit_requested). This prevents race conditions. Verify `rows_affected = 1` after execution. The `session_id` value comes from the SessionStart hook, which injects `$CLAUDE_SESSION_ID` into the system prompt automatically.</mandatory>
</section>

<section id="worked-by-succession">
<core>
## Worked_By Succession Pattern

When an musician session takes over (re-claiming) after a previous session exited:

```
First musician session:     worked_by = 'musician-task-03'
Second musician session:    worked_by = 'musician-task-03-S2'
Third musician session:     worked_by = 'musician-task-03-S3'
```

Suffix `-S2`, `-S3` indicates successive sessions. Conductor updates this field when re-claiming is approved via guard clause (state guard returns 0, fix_proposed allows re-claim).
</core>
</section>

<section id="fallback-row-pattern">
<core>
## Fallback Row Pattern

When a claim guard fails (state is not claimable), the session creates a fallback row to exit cleanly:
</core>

<template follow="exact">
```sql
INSERT INTO orchestration_tasks (task_id, state, session_id, last_heartbeat)
VALUES ('fallback-$CLAUDE_SESSION_ID', 'exited', '$CLAUDE_SESSION_ID', datetime('now'));

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-03', '$CLAUDE_SESSION_ID',
    'CLAIM BLOCKED: Guard prevented claim on task-03. Created fallback row to exit cleanly.',
    'claim_blocked');
```
</template>

<context>
The fallback row always succeeds (unique task_id, no guard). Hook reads it, allows session exit, and notifies conductor. Monitoring subagent detects fallback rows later, compares timestamps with original task:
- If original task's heartbeat > fallback's heartbeat: DELETE fallback (original task worked after collision, handled)
- If original task's heartbeat <= fallback's heartbeat: Report to user (claim collision, no session ever took over)
</context>
</section>

</skill>
