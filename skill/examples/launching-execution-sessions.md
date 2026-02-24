<skill name="conductor-example-launching-execution-sessions" version="4.0">

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- scenario
- verify-database
- insert-instruction-messages
- launch-verification-watcher
- launch-kitty-windows
- wait-for-events
- phase-complete
</sections>

<section id="scenario">
<context>
# Example: Launching Execution Sessions

This example shows how to launch parallel execution sessions for Phase 2 (4 parallel tasks).

## Scenario

Phase 2 tasks are ready:
- task-03: Extract Testing Docs (parallel)
- task-04: Extract API Docs (parallel)
- task-05: Extract Database Docs (parallel)
- task-06: Extract Architecture Docs (parallel)

Task instructions created and validated. Database rows inserted.
</context>
</section>

<section id="verify-database">
<core>
## Step 1: Verify Database State

```sql
SELECT task_id, state, instruction_path
FROM orchestration_tasks
WHERE task_id IN ('task-03', 'task-04', 'task-05', 'task-06');
```

Expected:
```
task-03 | watching | docs/tasks/task-03.md
task-04 | watching | docs/tasks/task-04.md
task-05 | watching | docs/tasks/task-05.md
task-06 | watching | docs/tasks/task-06.md
```
</core>
</section>

<section id="insert-instruction-messages">
<core>
## Step 2: Insert Instruction Messages

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES
    ('task-03', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-03.md
Type: parallel
Phase: 2
Dependencies: none
Danger files:
  - knowledge-base/testing/README.md (shared with task-04)', 'instruction'),
    ('task-04', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-04.md
Type: parallel
Phase: 2
Dependencies: none
Danger files:
  - knowledge-base/testing/README.md (cross-refs from task-03)', 'instruction'),
    ('task-05', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-05.md
Type: parallel
Phase: 2
Dependencies: none
Danger files: none', 'instruction'),
    ('task-06', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-06.md
Type: parallel
Phase: 2
Dependencies: none
Danger files: none', 'instruction');
```
</core>
</section>

<section id="launch-verification-watcher">
<core>
## Step 3: Launch Verification Watcher

Launch before kitty windows so monitoring is active when sessions start:

```python
Task("Verify execution sessions launched successfully", prompt="""
Verify that all execution sessions launched and claimed their tasks.

**Tasks to verify:** task-03, task-04, task-05, task-06

Poll every 15 seconds for up to 5 minutes:
SELECT task_id, state, last_heartbeat
FROM orchestration_tasks
WHERE task_id IN ('task-03', 'task-04', 'task-05', 'task-06')
ORDER BY task_id;

Success: All tasks reach 'working' within 5 minutes → exit and report.
Failure: Any remain 'watching' after 5 minutes → report which failed.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</core>
</section>

<section id="launch-kitty-windows">
<core>
## Step 4: Launch Kitty Windows

Launch one kitty window per task via the Bash tool. Use parallel Bash calls so all sessions start simultaneously:
</core>

<mandatory>Use the musician skill launch prompt template for each session.</mandatory>

<template follow="exact">
```bash
# Bash call 1:
kitty --directory /home/kyle/claude/remindly --title "Musician: task-03" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = 'task-03' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: task-03
- Phase: 2 — Extraction Tasks

Do not proceed without reading the full instruction message. All steps are there." &
echo $! > temp/musician-task-03.pid
```
</template>

<core>
```bash
# Bash call 2 (parallel):
kitty --directory /home/kyle/claude/remindly --title "Musician: task-04" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = 'task-04' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: task-04
- Phase: 2 — Extraction Tasks

Do not proceed without reading the full instruction message. All steps are there." &
echo $! > temp/musician-task-04.pid
```

```bash
# Bash calls 3 & 4 (parallel): Same pattern with task-05 and task-06, each with PID capture
```

All sessions coordinate autonomously via comms-link database.
</core>

<context>
**Launch notes:**
- Each `kitty --directory /home/kyle/claude/remindly --title "..." -- env -u CLAUDECODE claude --permission-mode acceptEdits "..."` opens a new OS window running claude with the musician prompt
- The `&` suffix detaches kitty so the Bash call returns immediately
- Use parallel Bash tool calls (one per kitty window) for simultaneous launch
- The verification watcher (step 3) is already running and will confirm all sessions claimed their tasks
</context>
</section>

<section id="wait-for-events">
<core>
## Step 5: Wait for Events

The monitoring subagent runs in the background. When it reports, handle the event:
- `needs_review` → See `review-approval-workflow.md`
- `error` → See `error-recovery-workflow.md`
- `complete` → Read completion report
- After handling, relaunch monitoring subagent for remaining tasks
</core>
</section>

<section id="phase-complete">
<core>
## Phase Complete

When all 4 tasks reach `complete` or `exited`:
1. Check for proposals in `docs/implementation/proposals/`
2. Verify no proposals in `temp/`
3. Proceed to Phase 3
</core>
</section>

</skill>
