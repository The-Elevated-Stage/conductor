<skill name="conductor-session-handoff" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- handoff-types
- clean-handoff
- dirty-handoff
- crash-handoff
- retry-exhaustion
- worked-by-succession
- guard-clause-reclaiming
- high-context-verification
- replacement-session-launch
- context-situation-checklist
</sections>

<section id="handoff-types">
<core>
# Session Handoff Reference

## Handoff Types

When an musician session exits, the conductor determines the handoff type and responds accordingly.

### Handoff Type Table

| Type | Condition | Key Difference | Conductor Action |
|------|-----------|---------------|---------------------|
| **Clean** | HANDOFF present, context <80% | Standard path | Read HANDOFF, set `fix_proposed`, send handoff msg, launch replacement kitty window |
| **Dirty** | HANDOFF present, context >80% | Hallucination risk | Same as clean BUT include test verification instructions in msg |
| **Crash** | No HANDOFF doc | Emergency state | Send msg with verification instructions for last completed steps |
| **Retry Exhaustion** | 5th retry failure | Conductor error | Escalate to user with retry options |
</core>
</section>

<section id="clean-handoff">
<core>
## Clean Handoff Procedure

When musician exits cleanly with HANDOFF doc and context <80%:
</core>

<template follow="format">
```sql
-- Conductor flow:
-- 1. Detect exit: query orchestration_tasks WHERE state = 'exited' AND task_id = 'task-NN'
-- 2. Check HANDOFF: read temp/task-NN-HANDOFF (musician wrote this)
-- 3. Update state and notify
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'HANDOFF RECEIVED: Musician session exited cleanly due to context exhaustion.
     Previous session: musician-task-03
     HANDOFF: temp/task-03-HANDOFF
     Context usage: 87%
     Next musician: musician-task-03-S2
     Action: Replacement kitty window launched automatically.',
    'handoff'
);
```
</template>
</section>

<section id="dirty-handoff">
<core>
## Dirty Handoff Procedure

When HANDOFF is present BUT context >80% (hallucination risk from context-exhausted session):

**Same as clean handoff, BUT:** Include test verification instructions in the handoff message.

In the message to the next session:
```
Previous session context was 87% (potential hallucination risk).
Before proceeding: Re-run ALL verification tests from last completed checkpoint.
If any fail, do NOT trust the test results in the HANDOFF — use your own judgment.
```
</core>
</section>

<section id="crash-handoff">
<core>
## Crash Handoff Procedure

When no HANDOFF doc exists (musician crashed without graceful exit):
</core>

<template follow="format">
```sql
-- Read last known state from temp/task-NN-status
-- Extract: last completed step, context at crash, deviations tracked
-- Send verification instructions for re-running from that point

UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'CRASH DETECTED: No HANDOFF doc. Previous session lost context or crashed.
     Last known state: temp/task-03-status
     Last completed: step 3 (framework setup)
     Context at crash: 75%
     Deviations logged: 2 (file skip, parsing strategy change)
     Action: Replacement kitty window launched. Verify step 3 results before resuming step 4.
     Re-run: framework initialization tests + integration tests from step 3.
     Do NOT trust results from step 4 (may be partial/broken).',
    'handoff'
);
```
</template>
</section>

<section id="retry-exhaustion">
<core>
## Retry Exhaustion Procedure

When musician self-exits after 5 failed retries (retry_count = 5):
</core>

<template follow="format">
```sql
-- This is an CONDUCTOR ERROR, not musician error
-- Musician wrote HANDOFF explaining the repeated failure pattern

UPDATE orchestration_tasks
SET state = 'exited', last_heartbeat = datetime('now'),
    last_error = 'retry_exhaustion_unresolved'
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'RETRY EXHAUSTION: Musician failed after 5 attempts.
     Root cause: [from HANDOFF]
     Last error: [details]
     Options:
      1. Retry with new instructions (scope reduction, different approach)
      2. Skip task (impacts plan, user decision)
      3. Investigate root cause (escalate to user for deep analysis)
     Action: Inform user, wait for guidance.',
    'handoff'
);
```
</template>
</section>

<section id="worked-by-succession">
<core>
## Worked_By Succession Pattern

When re-claiming a task for a new musician session, increment the suffix:

**Construction algorithm:**

1. Read current `worked_by` value from orchestration_tasks
2. Parse the value:
   - If `musician-task-NN` (no suffix): append `-S2` → `musician-task-NN-S2`
   - If `musician-task-NN-SN`: increment N → `musician-task-NN-S{N+1}`
3. When new session claims, update `worked_by` atomically with state change

**Example:**
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

When conductor sets `fix_proposed`, the next session can claim:
</core>

<template follow="exact">
```sql
-- Guard clause allows claiming from only 3 states
UPDATE orchestration_tasks
SET state = 'working',
    session_id = '$CLAUDE_SESSION_ID',
    worked_by = 'musician-task-03-S2',  -- incremented
    started_at = datetime('now'),
    last_heartbeat = datetime('now'),
    retry_count = 0  -- reset for new session
WHERE task_id = 'task-03'
  AND state IN ('watching', 'fix_proposed', 'exit_requested');  -- 3 claimable states
```
</template>

<core>
If guard blocks (state not claimable), session creates fallback row:
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
Conductor detects fallback row via monitoring and adjusts plan.
</context>
</section>

<section id="high-context-verification">
<mandatory>
## High-Context Verification Rule

When resuming a task with context >80% usage in previous session:

**Mandatory verification steps before proceeding:**

1. Re-run ALL verification tests from the last completed checkpoint
2. Compare test results to what's in HANDOFF or status file
3. If any discrepancies: do NOT trust previous session's assertions
4. If tests fail: diagnose whether previous session's code is broken or tests are environmental
5. Only resume if tests pass with your own execution

**Rationale:** High-context exhaustion (>80%) means the previous session was operating near capacity — likely hallucinating. Tests are your ground truth, not session claims.
</mandatory>
</section>

<section id="replacement-session-launch">
<core>
## Replacement Session Launch

When an musician session exits and needs replacement, the conductor launches a replacement kitty window directly and notifies the user:

**Notification to user:**
```
Task-XX musician exited.

Previous session: {worked_by}
Exit type: {clean/dirty/crash/retry_exhaustion}
Context usage: XX%
Last completed step: {description}
Handoff status: {present/missing/stale}

Launching replacement session in new kitty window...
```

**Launch replacement via Bash tool:**
</core>

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: task-XX (S2)" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = 'task-XX' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

Previous session: {worked_by}
New session will be: {worked_by-S2}
Read HANDOFF from temp/ for context.

**Context:**
- Task ID: task-XX
- Phase: {N} — {PHASE_NAME}

Do not proceed without reading the full instruction message. All steps are there." &
```
</template>

<reference path="skills_staged/conductor/references/musician-launch-prompt-template.md" load="recommended">
Full launch prompt template (Launching Replacement Sessions section).
</reference>
</section>

<section id="context-situation-checklist">
<core>
## Context Situation Checklist

When evaluating context-exhausted musician's proposal, assess:

- [ ] Self-correction flag active? (YES = context estimates ~6x bloat)
- [ ] How many deviations and severity? (high severity + high context = risky)
- [ ] How many steps to next checkpoint? (far = higher risk)
- [ ] Remaining agents and cost per agent? (many + high cost = likely to exceed budget)
- [ ] Prior context warnings on this task? (multiple = pattern of scope creep)
- [ ] Proposed action specificity? (vague = less confidence)

Use results to choose response: `review_approved` (low risk), `fix_proposed` (override scope), or `review_failed` (stop now).
</core>
</section>

</skill>
