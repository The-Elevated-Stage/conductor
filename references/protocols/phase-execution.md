<skill name="conductor-phase-execution" version="3.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Phase Execution Protocol
</metadata>

<sections>
- plan-consumption
- danger-file-assessment
- task-decomposition
- copyist-launch-template
- database-task-creation
- musician-launch
- sequential-execution
- parallel-execution
- sentinel-launch
- monitoring-cycle
- monitoring-subagent-template
- launch-verification
- event-routing
- emergency-broadcasts
- phase-completion
- monitoring-queries
- heartbeat-rule
</sections>

<section id="plan-consumption">
<core>
# Phase Execution Protocol

## Per-Phase Plan Reading

When entering a new phase, read the phase's content selectively via the plan-index line ranges:

1. Read `phase:N` section — the implementation detail for this phase
2. Read `conductor-review-N` section — the verification checklist and guidance for this phase

Both are read using the line ranges from the plan-index parsed during initialization. This keeps context cost proportional to one phase, not the full plan.

The phase section provides the implementation content needed for task decomposition and review context. The conductor-review section provides verification items the Conductor must check after the phase completes.

<mandatory>Do not read future phase sections. Only the current phase is loaded. When the phase completes and the conductor-review checklist passes, move to the next phase and read its sections fresh.</mandatory>
</core>
</section>

<section id="danger-file-assessment">
<core>
## Danger File Assessment

Before decomposing a phase into tasks, assess danger files — files that multiple tasks may modify simultaneously.

### 3-Step Governance Flow

**Step 1: Extract from Plan**
Identify inline danger file annotations in the phase section (marked with warning indicators or explicit mentions of shared files).

**Step 2: Assess Risk**
For each shared file:
- Which tasks touch it?
- Are the modifications independent (different sections/functions) or overlapping?
- Can the tasks be ordered to avoid conflicts?

**Step 3: Decide Mitigation**
- **Ordering within tasks:** If modifications are independent, order tasks so the more fundamental change goes first
- **Append-only pattern:** If tasks add to a file (not modifying existing content), parallel is safe
- **Sequential sub-steps:** Convert parallel tasks to sequential for the specific file operations
- **Conductor batching:** Conductor collects modifications from multiple tasks and applies them in a single batch

### Skip Conditions

Danger file assessment is not needed when:
- All tasks work on entirely separate files (common in decomposed phases)
- The phase is already sequential
- The Arranger's plan explicitly marks the phase as parallel-safe with no shared resources
</core>
</section>

<section id="task-decomposition">
<core>
## Task Decomposition

For each phase, the Conductor determines how to split the work into tasks. The Arranger provides boundary/goal guidance — the Conductor decides the actual task boundaries.

### Decomposition Steps

1. **Read the phase section** (already loaded from plan-consumption)
2. **Identify natural task boundaries** — separate files, separate components, separate concerns
3. **Assess parallelism** — which tasks can run simultaneously? Check for shared file conflicts (danger-file-assessment section)
4. **Assign task IDs** — sequential numbering continuing from prior phases (task-01, task-02, etc.)
5. **Prepare Overrides & Learnings** — review conductor-review-N from the plan for any guidance. Add any corrections, scope adjustments, or learnings from prior phases.
6. **Launch Copyist teammate** — see copyist-launch-template section
7. **Review returned instructions** — spot-check alignment with phase goals. See Review Protocol via SKILL.md for the strategy checklist.

<mandatory>If unable to determine how to split a phase into tasks, launch a teammate for focused discussion with Explorer access for codebase context. Gemini as fallback for guidance. Do not guess at task boundaries — a bad decomposition wastes more context than the investigation costs.</mandatory>

After receiving and reviewing Copyist instructions:
- Insert database rows for each task (database-task-creation section)
- Insert instruction messages for each task
- Proceed to Musician launch

<mandatory>Musician claims a task only after BOTH the task row AND the instruction message exist in the database. Do not launch Musicians before both are inserted.</mandatory>
</core>
</section>

<section id="copyist-launch-template">
<core>
## Copyist Launch Template

<mandatory>Copyist MUST be launched as a teammate (not a regular subagent) — task instruction generation is >40k estimated tokens. Use the Task tool with model="opus" and team_name.</mandatory>

<template follow="format">
Load the copyist skill, then create task instruction files for this phase.

## Phase Info
**Phase:** {N} — {NAME}
**Task type:** {TYPE} (sequential/parallel)
**Tasks to create:** {TASK_LIST with IDs}
**Implementation plan:** {PLAN_PATH}
**Line range:** {LINE_START}-{LINE_END} (read only these lines)
**Output directory:** docs/tasks/

## Overrides & Learnings
{CONDUCTOR_NOTES — hard-coded corrections, scope adjustments,
danger file decisions, or lessons from prior phases that override
the implementation plan for these tasks}

## Instructions
1. Read the implementation plan at `{PLAN_PATH}`, lines {LINE_START} to {LINE_END} only
2. Invoke the `copyist` skill
3. Read the appropriate template (sequential or parallel)
4. Extract the tasks listed above from the plan
5. Apply any Overrides & Learnings — these take precedence over the plan
6. Write instruction files to `docs/tasks/`
7. Validate each file and fix errors until all pass

Report validation results for each file when done.
</template>

<mandatory>Copyist receives the line range, not the full plan path. Task decomposition is the Conductor's responsibility — the Copyist creates instructions for the tasks the Conductor specifies.</mandatory>

### Copyist Failure

If the Copyist returns faulty instructions, proceed to SKILL.md and locate the Error Recovery Protocol (Copyist output errors section). Small errors can be fixed inline; larger issues require re-launching the Copyist teammate.
</core>
</section>

<section id="database-task-creation">
<core>
## Database Task Creation

For each task in the phase, insert a task row and an instruction message:

### Task Row

<template follow="exact">
```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('{task-id}', 'watching', 'docs/tasks/{task-id}.md', datetime('now'));
```
</template>

### Instruction Message

<template follow="exact">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'TASK INSTRUCTION: docs/tasks/{task-id}.md
     Type: {sequential|parallel}
     Phase: {N}
     Dependencies: {task IDs or "none"}
     Danger files:
       - {path} ({notes if shared})',
    'instruction'
);
```
</template>

Tables persist across phases. Add rows as new phases launch — do not recreate tables between phases.
</core>
</section>

<section id="musician-launch">
<mandatory>
## Musician Launch

All external execution sessions MUST use the musician skill launch prompt template.
</mandatory>

<core>
### Launch Command

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: {task-id}" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = '{task-id}' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: {task-id}
- Phase: {PHASE_NUMBER} — {PHASE_NAME}

Do not proceed without reading the full instruction message. All steps are there." &
echo $! > temp/musician-{task-id}.pid
```
</template>

The `&` runs the kitty process in the background. The `echo $!` captures the PID to a sentinel file for lifecycle management (see Musician Lifecycle Protocol via SKILL.md).

### Sequential Tasks

Launch one task at a time. Wait for the task to reach `complete` state before launching the next. No danger file coordination needed.

### Parallel Tasks

Launch one kitty window per task. All tasks for the phase launch simultaneously. Use one Bash call per kitty window.

### Launch Sequence (Parallel)

1. Launch verification watcher (see launch-verification section) — ensures monitoring is active before sessions start
2. Launch kitty windows — one per task with PID capture
3. Launch Sentinel teammate (see sentinel-launch section)
4. Verification watcher confirms all tasks reach `working` state within 5 minutes
5. After verification: start the main monitoring subagent (see monitoring-subagent-template section)
</core>
</section>

<section id="sequential-execution">
<core>
## Sequential Execution Pattern

Use when: single task per phase, strict ordering required, foundation work, shared resource constraints.

### Conductor Workflow

1. Create task instruction (via Copyist teammate)
2. Insert database row and instruction message
3. Launch single Musician kitty window with PID capture
4. Launch background monitoring watcher
5. Monitor via watcher — handle events as they arise (reviews, errors, completion)
6. When task completes: close kitty window, verify against conductor-review checklist
7. Proceed to next task or next phase

No danger file coordination needed. Manual message checks between steps if needed.
</core>
</section>

<section id="parallel-execution">
<core>
## Parallel Execution Pattern

Use when: 3+ independent tasks, no shared resource conflicts (or mitigated via danger file assessment).

### Conductor Workflow

1. Analyze danger files (danger-file-assessment section)
2. Create all task instructions for the phase (single Copyist teammate call)
3. Insert database rows for all tasks
4. Insert instruction messages for all tasks
5. Launch verification watcher
6. Launch kitty windows (one per task, all simultaneously, each with PID capture)
7. Launch Sentinel teammate
8. Verification watcher confirms tasks reach `working` — re-launch failed ones
9. After verification: launch main monitoring subagent
10. Handle events via monitoring cycle (event-routing section)
11. Phase completion: all tasks reach terminal state → verify against conductor-review checklist

<mandatory>Background message-watcher must be running at all times during parallel execution. If any Musician enters `needs_review` or `error`, the watcher detects and exits — handle the event, then relaunch the watcher before continuing.</mandatory>
</core>
</section>

<section id="sentinel-launch">
<core>
## Sentinel Teammate Launch

After launching Musicians for a phase, launch the Sentinel monitoring teammate. The Sentinel watches Musicians' temp/ logs for anomalies and sends fire-and-forget reports.

Launch timing: immediately after Musicians are launched, alongside the monitoring subagent.

For the Sentinel's prompt, anomaly criteria, and behavior, read the sentinel-monitoring section in the Sentinel Monitoring Protocol file (via SKILL.md).

Shutdown: message the Sentinel when the phase completes. If entering the Repetiteur Protocol (all Musicians paused), also shut down the Sentinel.
</core>
</section>

<section id="monitoring-cycle">
<core>
## Monitoring Cycle

The Conductor's monitoring loop during phase execution:

### Cycle Steps

1. **Launch background watcher** — Task subagent with `model="opus"`, `run_in_background=True`. See monitoring-subagent-template section.
2. **Output progress** — Report to terminal: "Monitoring started for Phase {N}. Watching for state changes."
3. **Wait for watcher exit** — Conductor pauses. User can ask questions or provide context.
4. **Watcher detects event** — Exits background task. Conductor is notified.
5. **Handle event** — Route via event-routing section to the appropriate protocol.
5.5. **Check table for additional changes** — Before relaunching watcher, query `orchestration_tasks`:
   - Check for new state changes on any task
   - Read any new messages from `orchestration_messages` that arrived during step 5
   - If additional events found: handle them sequentially (loop back to step 5 for each)
6. **Relaunch watcher** — Launch new background watcher.
7. **Repeat** — Return to step 2.

<mandatory>Background message-watcher must be running before and after every event handling cycle. Relaunch immediately after handling any event — no work proceeds without an active watcher.</mandatory>

<mandatory>After handling ANY event (review, error, completion), ALWAYS execute step 5.5 before relaunching the watcher. Multiple tasks may have changed state while you were handling the first event.</mandatory>
</core>
</section>

<section id="monitoring-subagent-template">
<core>
## Monitoring Subagent Template

The background monitoring watcher is a regular Task subagent (< 40k tokens, polling loop):

<template follow="format">
```python
Task(
    description="Monitor Phase {N} tasks",
    prompt="""Poll orchestration_tasks every 30 seconds using comms-link query.

Tasks to monitor: {TASK_ID_LIST}

Each poll cycle:
1. Query all task states and heartbeats
2. Refresh conductor heartbeat (task-00): UPDATE orchestration_tasks SET last_heartbeat = datetime('now') WHERE task_id = 'task-00'
3. Check for state changes: needs_review, error, complete, exited
4. Check for stale heartbeats (>540 seconds)
5. Check for fallback rows (task_id LIKE 'fallback-%')

EXIT IMMEDIATELY when you detect:
- Any task state changes to needs_review, error, complete, or exited
- Any stale heartbeat detected
- Any fallback row detected

Do NOT loop after detecting a change. Do NOT send additional messages. EXIT the task immediately so the Conductor is notified.""",
    subagent_type="general-purpose",
    model="opus",
    run_in_background=True
)
```
</template>

<mandatory>The watcher must EXIT on state change detection, not continue polling. The Conductor relies on the watcher's exit notification to know an event occurred.</mandatory>
</core>
</section>

<section id="launch-verification">
<core>
## Launch Verification

Before the main monitoring watcher starts, a verification watcher confirms all Musicians successfully claimed their tasks:

1. Launch verification watcher: polls for all tasks reaching `working` state
2. If all tasks reach `working` within 5 minutes: watcher exits, verification passed
3. If any remain `watching` after 5 minutes: watcher notifies Conductor to re-launch failed kitty windows (check PID, re-launch)
4. After verification: start the main monitoring subagent
</core>
</section>

<section id="event-routing">
<core>
## Event Routing

When the monitoring watcher exits with a detected event, route based on state:

| Detected State | Action |
|---------------|--------|
| `needs_review` | Return to SKILL.md, locate Review Protocol |
| `error` | Return to SKILL.md, locate Error Recovery Protocol |
| `complete` | If all tasks in phase are terminal → proceed to phase-completion section. If not all → note and continue monitoring. |
| `exited` | Return to SKILL.md, locate Musician Lifecycle Protocol |
| Stale heartbeat | Return to SKILL.md, locate Error Recovery Protocol (stale-heartbeat-recovery section) |
| Fallback row (`claim_blocked`) | Return to SKILL.md, locate Error Recovery Protocol (claim-failure-recovery section) |

After handling ANY event through the appropriate protocol, return here and execute monitoring cycle step 5.5 (check for additional changes) before relaunching the watcher.
</core>
</section>

<section id="emergency-broadcasts">
<core>
## Emergency Broadcasts

For critical cross-cutting issues requiring all execution sessions to see a message (shared file conflict, consultation pause, user-requested stop):

<template follow="exact">
```sql
-- One INSERT per active task_id
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('{task-id}', 'task-00', 'EMERGENCY: {critical message}', 'emergency');
```
</template>

Each Musician's background watcher monitors only its own task_id — it will detect the emergency message on its next poll cycle. No body parsing needed. The Conductor has full control over when and why to broadcast.
</core>
</section>

<section id="phase-completion">
<core>
## Phase Completion

When all tasks in the current phase reach terminal state (`complete` or `exited`):

1. Check for unprocessed proposals in `docs/implementation/proposals/` and `temp/`
2. Integrate critical proposals, defer non-critical
3. Shut down the Sentinel teammate (message it to stop)
4. **Verify against conductor-review-N checklist** — read the conductor-review section for this phase from the plan. All checklist items must pass before proceeding.
5. Close all Musician kitty windows for the phase (see Musician Lifecycle Protocol via SKILL.md for cleanup mechanics)
6. Proceed to next phase — return to plan-consumption section to read the next phase's content

If this was the LAST phase: return to SKILL.md and locate the Completion Protocol.
</core>
</section>

<section id="monitoring-queries">
<core>
## Monitoring SQL Patterns

### Monitor All Tasks

<template follow="exact">
```sql
SELECT task_id, state, last_heartbeat, retry_count, last_error
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```
</template>

### Check for Pending Messages

<template follow="exact">
```sql
SELECT task_id, from_session, message, timestamp
FROM orchestration_messages
WHERE task_id LIKE 'task-%'
ORDER BY timestamp DESC
LIMIT 10;
```
</template>

### Detect Fallback Rows

<template follow="exact">
```sql
SELECT task_id, session_id, last_heartbeat
FROM orchestration_tasks
WHERE task_id LIKE 'fallback-%';
```
</template>

### Fallback Row Cleanup

Compare timestamps to determine if the original task was worked since the collision:

<template follow="exact">
```sql
-- If original task's heartbeat > fallback's: delete fallback (collision resolved)
DELETE FROM orchestration_tasks WHERE task_id = 'fallback-{session-id}';

-- If original task's heartbeat <= fallback's: report to user (task may need re-launch)
```
</template>
</core>
</section>

<section id="heartbeat-rule">
<mandatory>
## Heartbeat Rule

Update `last_heartbeat` on EVERY state transition:

```sql
UPDATE orchestration_tasks
SET state = '{new_state}', last_heartbeat = datetime('now')
WHERE task_id = '{task_id}';
```

All SQL in conductor workflows MUST include `last_heartbeat = datetime('now')` alongside any `state` change. Omitting the heartbeat from a state update is a bug.

The Conductor's own heartbeat (task-00) is refreshed by the monitoring subagent during its poll cycle. Musicians check the Conductor's heartbeat to detect if the Conductor has crashed (>9 minutes stale = Conductor may be down).
</mandatory>
</section>

</skill>
