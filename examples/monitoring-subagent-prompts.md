<skill name="conductor-example-monitoring-subagent-prompts" version="2.0">

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- launch-verification-watcher
- main-monitoring-parallel
- sequential-task-monitoring
- staleness-only-monitoring
- post-review-re-monitoring
- monitoring-cycle-extras
- design-decisions
</sections>

<section id="launch-verification-watcher">
<core>
# Example: Monitoring Subagent Prompts

## Launch Verification Watcher (Immediate Post-Launch)

Launch before presenting musician prompts to the user, so monitoring is active when sessions start:
</core>

<template follow="format">
```python
Task("Verify execution sessions launched successfully", prompt="""
Verify that all execution sessions launched and claimed their tasks.

**Tasks to verify:** {{TASK_LIST}} (e.g., task-03, task-04, task-05, task-06)

**Behavior:**

Poll every 15 seconds for up to 5 minutes:

SELECT task_id, state, last_heartbeat
FROM orchestration_tasks
WHERE task_id IN ({{TASK_LIST}})
ORDER BY task_id;

**Success condition:** All tasks reach state='working' within 5 minutes
- When ALL tasks show 'working': Exit immediately and report "All tasks verified working"

**Failure condition:** Any task remains 'watching' after 5 minutes
- Report "Launch verification timeout: {{TASK_LIST}} still watching after 5 minutes"
- Include which tasks reached 'working' and which remain 'watching'
- Conductor will re-launch failed kitty windows

**Do not loop beyond 5 minutes.** Either verify success or report timeout.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</template>
</section>

<section id="main-monitoring-parallel">
<core>
## Main Monitoring: Parallel Phase (Primary Use Case)

Launch after Launch Verification Watcher confirms all tasks are `working`:
</core>

<template follow="format">
```python
Task("Monitor Phase 2 execution tasks", prompt="""
Monitor orchestration_tasks for state changes using comms-link query tool.

**Tasks to watch:** task-03, task-04, task-05, task-06

**Poll every 30 seconds with this query:**

SELECT task_id, state, last_heartbeat,
       retry_count,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE task_id IN ('task-03', 'task-04', 'task-05', 'task-06')
ORDER BY task_id;

**Report back IMMEDIATELY when ANY task reaches:**
- needs_review — execution wants conductor review
- error — execution hit a problem
- complete — execution finished successfully
- exited — execution terminated

**Also report if:**
- Any task has seconds_stale > 540 while in state: review_approved, review_failed, fix_proposed, or working
  (indicates session may have crashed)

**When reporting, include:**
1. Which task changed state
2. The new state
3. seconds_stale value
4. The most recent message for that task:
   SELECT message FROM orchestration_messages
   WHERE task_id = '[changed_task]'
   ORDER BY timestamp DESC LIMIT 1;

**EXIT IMMEDIATELY after reporting.** Do not continue monitoring. Do not loop. Do not send additional messages. The conductor will handle the event and relaunch a new monitoring subagent afterward.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</template>
</section>

<section id="sequential-task-monitoring">
<core>
## Sequential Task Monitoring (Simpler)

For sequential tasks, monitoring is simpler since only one task runs at a time:

```python
Task("Monitor task-01 execution", prompt="""
Monitor orchestration_tasks for task-01 state changes using comms-link query tool.

Poll every 60 seconds:
SELECT state, last_heartbeat, retry_count
FROM orchestration_tasks
WHERE task_id = 'task-01';

Report back when state changes from 'working' to anything else.
Include the new state and most recent message.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</core>
</section>

<section id="staleness-only-monitoring">
<core>
## Staleness-Only Monitoring

When all tasks are in stable states but need staleness detection:

```python
Task("Watch for stale sessions", prompt="""
Check for stale sessions using comms-link query tool.

Poll every 60 seconds:
SELECT task_id, state,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE state NOT IN ('watching', 'complete', 'exited')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;

Report back if any rows returned. Include task_id, state, and seconds_stale.
If no stale sessions after 10 checks, report "All sessions healthy" and stop.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</core>
</section>

<section id="post-review-re-monitoring">
<core>
## Post-Review Re-Monitoring

After handling a review or error, relaunch monitoring for remaining active tasks:

```python
# After handling task-03 review, relaunch for remaining tasks
remaining_tasks = ['task-04', 'task-05', 'task-06']  # task-03 still working but handled

Task("Continue monitoring Phase 2", prompt=f"""
Resume monitoring orchestration_tasks for: {', '.join(remaining_tasks)}
Same criteria as before — report on needs_review, error, complete, exited, or staleness.
Also include task-03 in monitoring (it resumed after review).
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</core>
</section>

<section id="monitoring-cycle-extras">
<core>
## Monitoring Cycle: Conductor Heartbeat & Fallback Cleanup

Each monitoring cycle should include two additional steps:

### Heartbeat Refresh

After detecting task states, refresh the conductor's own heartbeat:

```sql
UPDATE orchestration_tasks
SET last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</core>

<mandatory>This prevents musician sessions from timing out while waiting for conductor responses. Must be done every monitoring cycle (not just on events).</mandatory>

<core>
### Fallback Row Cleanup

Check for fallback rows (created when musician guard clause blocked a claim) and clean them up:

```sql
-- Find fallback rows
SELECT task_id, last_heartbeat FROM orchestration_tasks
WHERE task_id LIKE 'fallback-%';

-- For each fallback found, compare timestamps with original task:
-- SELECT task_id, last_heartbeat FROM orchestration_tasks
-- WHERE task_id = 'task-{NN}';

-- If fallback.last_heartbeat >= original_task.last_heartbeat:
--   Task was NOT worked since fallback collision → report to conductor
-- If fallback.last_heartbeat < original_task.last_heartbeat:
--   Task was worked after collision → DELETE fallback row
DELETE FROM orchestration_tasks WHERE task_id = 'fallback-{session_id}';
```

Report any fallback collisions immediately to the conductor (rare case, indicates claim race condition).
</core>
</section>

<section id="design-decisions">
<mandatory>
## Key Design Decisions

- **Model:** Always `model="opus"` — sonnet is the default and is insufficient for orchestration subagents
- **Background:** Always `run_in_background=True` so conductor can continue
- **Poll interval:** 30s for parallel phases, 60s for sequential or staleness-only
- **Staleness threshold:** 540 seconds (9 minutes) for transitional states
- **Heartbeat refresh:** Every cycle, in-band, to keep conductor alive
- **Fallback cleanup:** Every cycle, delete if original task has newer timestamp
- **Relaunch pattern:** After each event handling, launch a new monitoring subagent
</mandatory>
</section>

</skill>
