<skill name="conductor-sequential-coordination" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- when-to-use
- key-characteristics
- conductor-workflow
- execution-session-workflow
- comparison
</sections>

<section id="when-to-use">
<core>
# Sequential Coordination Pattern

## When to Use

- Single task that must complete before next phase
- Tasks with strict ordering dependencies
- Foundation tasks (Phase 1 of most plans)
- Tasks that modify shared resources that other tasks depend on
</core>
</section>

<section id="key-characteristics">
<core>
## Key Characteristics

- **Hooks always active** — Hooks are self-configuring via `hooks.json` and SessionStart. Sequential tasks don't require background monitoring, but hooks still monitor state transitions and stop hook tracks session lifecycle.
- **No background subagent** monitoring — conductor checks database manually
- **Manual message checks** between steps
- **Single execution session** at a time
</core>
</section>

<section id="conductor-workflow">
<core>
## Conductor Workflow

### 1. Create Task Instruction

Launch subagent with `copyist` skill, specifying `sequential` task type.

### 2. Insert Database Row
</core>

<template follow="exact">
```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-01', 'watching', 'docs/tasks/task-01.md', datetime('now'));
```
</template>

<core>
### 3. Insert Instruction Message
</core>

<template follow="format">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-01', 'task-00',
    'TASK INSTRUCTION: docs/tasks/task-01.md
     Type: sequential
     Phase: 1
     Dependencies: none',
    'instruction'
);
```
</template>

<core>
### 4. Launch Execution Session

Launch a kitty window via the Bash tool:
</core>

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: task-01" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = 'task-01' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: task-01
- Phase: 1 — Foundation

Do not proceed without reading the full instruction message. All steps are there." &
```
</template>

<core>
### 5. Monitor (Polling)

Periodically check task state:
</core>

<template follow="exact">
```sql
SELECT task_id, state, last_heartbeat, retry_count
FROM orchestration_tasks
WHERE task_id = 'task-01';
```
</template>

<context>
For sequential tasks, the conductor can poll manually rather than using a background subagent. Check every few minutes or when the conductor has context to spare.
</context>

<core>
### 6. Handle Review (if needed)

If state becomes `needs_review`:
1. Read message from `orchestration_messages`
2. Review proposal
3. Approve or reject (see state-machine.md)
4. Continue monitoring

### 7. Wait for Completion

When state becomes `complete`:
1. Read completion report from `report_path`
2. Verify deliverables
3. Update STATUS.md
4. Proceed to next phase
</core>
</section>

<section id="execution-session-workflow">
<core>
## Execution Session Workflow (Sequential)

The execution session follows the sequential task template:

1. **Claim task** — Atomic UPDATE with guard clause
2. **Execute steps** — Work through instruction sequentially
3. **Check messages** — Manual SQL check between major steps
4. **Complete** — Set state to `complete`, write completion report
</core>

<context>
Hooks are always registered (SessionStart hook injects `$CLAUDE_SESSION_ID`, stop hook monitors state). Sequential tasks don't require background monitoring subagent — only polling by conductor and manual message checks by musician are needed. No review checkpoints unless instruction specifies one.
</context>
</section>

<section id="comparison">
<core>
## Comparison with Parallel Pattern

| Aspect | Sequential | Parallel |
|--------|-----------|----------|
| Hook | Self-configuring (always present) | Required (orchestration preset) |
| Background subagent | Not required | Required (monitoring) |
| Review checkpoints | Optional | Mandatory at logical points |
| Error recovery | Simple retry | Full retry cycle with fix proposals |
| Conductor effort | Low (polling) | High (active monitoring) |
| Context cost | Low | Higher (subagent overhead) |
</core>
</section>

</skill>
