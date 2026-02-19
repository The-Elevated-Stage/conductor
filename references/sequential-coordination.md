# Sequential Coordination Pattern

## When to Use

- Single task that must complete before next phase
- Tasks with strict ordering dependencies
- Foundation tasks (Phase 1 of most plans)
- Tasks that modify shared resources that other tasks depend on

## Key Characteristics

- **Hooks always active** — Hooks are self-configuring via `hooks.json` and SessionStart. Sequential tasks don't require background monitoring, but hooks still monitor state transitions and stop hook tracks session lifecycle.
- **No background subagent** monitoring — conductor checks database manually
- **Manual message checks** between steps
- **Single execution session** at a time

## Conductor Workflow

### 1. Create Task Instruction

Launch subagent with `copyist` skill, specifying `sequential` task type.

### 2. Insert Database Row

```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-01', 'watching', 'docs/tasks/task-01.md', datetime('now'));
```

### 3. Insert Instruction Message

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

### 4. Launch Execution Session

Launch a kitty window via the Bash tool:

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

### 5. Monitor (Polling)

Periodically check task state:

```sql
SELECT task_id, state, last_heartbeat, retry_count
FROM orchestration_tasks
WHERE task_id = 'task-01';
```

For sequential tasks, the conductor can poll manually rather than using a background subagent. Check every few minutes or when the conductor has context to spare.

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

## Execution Session Workflow (Sequential)

The execution session follows the sequential task template:

1. **Claim task** — Atomic UPDATE with guard clause
2. **Execute steps** — Work through instruction sequentially
3. **Check messages** — Manual SQL check between major steps
4. **Complete** — Set state to `complete`, write completion report

Hooks are always registered (SessionStart hook injects `$CLAUDE_SESSION_ID`, stop hook monitors state). Sequential tasks don't require background monitoring subagent — only polling by conductor and manual message checks by musician are needed. No review checkpoints unless instruction specifies one.

## Comparison with Parallel Pattern

| Aspect | Sequential | Parallel |
|--------|-----------|----------|
| Hook | Self-configuring (always present) | Required (orchestration preset) |
| Background subagent | Not required | Required (monitoring) |
| Review checkpoints | Optional | Mandatory at logical points |
| Error recovery | Simple retry | Full retry cycle with fix proposals |
| Conductor effort | Low (polling) | High (active monitoring) |
| Context cost | Low | Higher (subagent overhead) |
