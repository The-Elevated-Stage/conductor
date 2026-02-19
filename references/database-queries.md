# Database Queries Reference

## Database Location

`/home/kyle/claude/remindly/comms.db` — shared by comms-link MCP server and stop hook (via sqlite3).

## Schema DDL

**IMPORTANT:** Use `comms-link execute` (raw SQL) for CREATE TABLE with CHECK constraints. The `create-table` tool does not support CHECK.

```sql
-- Drop existing tables (clean start for new implementation)
DROP TABLE IF EXISTS orchestration_tasks;
DROP TABLE IF EXISTS orchestration_messages;

-- Table 1: State machine + lifecycle
CREATE TABLE orchestration_tasks (
    task_id TEXT PRIMARY KEY,
    state TEXT NOT NULL CHECK (state IN (
        'watching', 'reviewing', 'exit_requested', 'complete',
        'working', 'needs_review', 'review_approved', 'review_failed',
        'error', 'fix_proposed', 'exited'
    )),
    instruction_path TEXT,
    session_id TEXT,
    worked_by TEXT,
    started_at TEXT,
    completed_at TEXT,
    report_path TEXT,
    retry_count INTEGER DEFAULT 0,
    last_heartbeat TEXT,
    last_error TEXT
);

-- Table 2: Append-only message log
CREATE TABLE orchestration_messages (
    id INTEGER PRIMARY KEY,
    task_id TEXT,
    from_session TEXT,
    message TEXT,
    message_type TEXT CHECK (message_type IN (
        'review_request', 'error', 'context_warning', 'completion',
        'emergency', 'handoff', 'approval', 'fix_proposal',
        'rejection', 'instruction', 'claim_blocked', 'resumption'
    )),
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Insert conductor row
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));

-- Create indexes for query performance
CREATE INDEX idx_messages_task_time ON orchestration_messages(task_id, timestamp);
CREATE INDEX idx_messages_type ON orchestration_messages(message_type);
CREATE INDEX idx_tasks_state_heartbeat ON orchestration_tasks(state, last_heartbeat);
```

## Schema Verification

```sql
PRAGMA table_info(orchestration_tasks);
PRAGMA table_info(orchestration_messages);
```

If columns are missing or tables don't exist: drop and recreate.

## Column Reference

### orchestration_tasks

| Column | Type | Purpose |
|--------|------|---------|
| `task_id` | TEXT PK | task-00 (conductor), task-01+ (execution) |
| `state` | TEXT NOT NULL | State machine value (11 valid states via CHECK) |
| `instruction_path` | TEXT | Path to task instruction file |
| `session_id` | TEXT | Actual Claude Code session ID (set by SessionStart hook, injected into system prompt as $CLAUDE_SESSION_ID) |
| `worked_by` | TEXT | Worker identifier with succession: musician-task-{NN}, musician-task-{NN}-S2, musician-task-{NN}-S3, etc. (each new session increments suffix) |
| `started_at` | TEXT | When task was claimed |
| `completed_at` | TEXT | When task completed |
| `report_path` | TEXT | Path to completion report |
| `retry_count` | INTEGER | Error retry tracking (0-5) |
| `last_heartbeat` | TEXT | Staleness detection (updated on every state transition) |
| `last_error` | TEXT | Most recent error message |

### orchestration_messages

| Column | Type | Purpose |
|--------|------|---------|
| `id` | INTEGER PK | Auto-increment |
| `task_id` | TEXT | Which task this message relates to |
| `from_session` | TEXT | Who sent the message |
| `message` | TEXT | Free-text message content |
| `message_type` | TEXT | Enum for filtering messages without parsing body |
| `timestamp` | TEXT | Auto-set to CURRENT_TIMESTAMP |

## Common SQL Patterns

### Pattern 1: Insert Task Row (Conductor — Phase Launch)

```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-03', 'watching', 'docs/tasks/task-03.md', datetime('now'));
```

### Pattern 2: Atomic Task Claim (Execution — Initialization)

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

Verify `rows_affected = 1`. If 0, guard blocked (create fallback row, notify conductor, exit cleanly).

### Pattern 3: Request Review (Execution)

```sql
UPDATE orchestration_tasks
SET state = 'needs_review', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', '$CLAUDE_SESSION_ID',
    'REVIEW REQUEST (Smoothness: 2/9):
     Checkpoint: 5 of 12
     Context Usage: 45%
     Self-Correction: YES (minor rewrites during parsing)
     Deviations: 2 (file skip decisions)
     Agents Remaining: 3 (~15% each, ~45% total)
     Proposal: docs/implementation/proposals/task-03-testing-patterns.md
     Summary: Extracted testing documentation, created 3 knowledge-base files
     Files Modified: 12
     Tests: All passing (8 total, 2 new)
     Key Outputs:
       - docs/implementation/proposals/task-03-testing-patterns.md (created)
       - docs/implementation/proposals/rag-testing-tdd.md (rag-addition)
       - docs/implementation/reports/task-03-checkpoint-5.md (created)',
    'review_request'
);
```

### Pattern 4: Approve Review (Conductor)

```sql
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'REVIEW APPROVED: Good work. Proceed with remaining steps.',
    'approval'
);
```

### Pattern 5: Reject Review (Conductor)

```sql
UPDATE orchestration_tasks
SET state = 'review_failed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'REVIEW FAILED (Smoothness: 7/9):
     Issue: Missing cross-references in knowledge-base files
     Required: Add cross-references to related files in each document header
     Retry: Fix cross-references, then re-submit for review',
    'rejection'
);
```

### Pattern 6: Report Error (Execution)

```sql
UPDATE orchestration_tasks
SET state = 'error', last_heartbeat = datetime('now'),
    retry_count = retry_count + 1,
    last_error = 'test_auth_integration timeout'
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', '$CLAUDE_SESSION_ID',
    'ERROR (Retry 1/5): Test failed after implementation
     Error: test_auth_integration timeout
     Report: docs/implementation/reports/task-03-error-retry-1.md
     Key Outputs:
       - backend/auth.ts (modified)
       - docs/implementation/reports/task-03-error-retry-1.md (created)
     Awaiting conductor fix proposal',
    'error'
);
```

### Pattern 7: Propose Fix (Conductor)

```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'FIX PROPOSAL (Retry 1/5):
     Root cause: Auth service timeout set to 5s, test expects 3s
     Fix: Update auth.ts:45 timeout to 3000ms
     Retry: Re-run tests after fix',
    'fix_proposal'
);
```

### Pattern 8: Mark Complete (Execution)

```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now'),
    report_path = 'docs/implementation/reports/task-03-completion.md'
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', '$CLAUDE_SESSION_ID',
    'TASK COMPLETE (Smoothness: 1/9):
     Report: docs/implementation/reports/task-03-completion.md
     Summary: All deliverables created, tests passing, ready for integration
     Key Outputs:
       - docs/implementation/reports/task-03-completion.md (created)
       - docs/implementation/proposals/rag-testing-tdd.md (rag-addition)',
    'completion'
);
```

### Pattern 9: Request Exit (Conductor)

```sql
UPDATE orchestration_tasks
SET state = 'exit_requested', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

### Pattern 10: Mark Conductor Complete

```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now')
WHERE task_id = 'task-00';
```

### Pattern 11: Monitor All Tasks

```sql
SELECT task_id, state, last_heartbeat,
       retry_count, last_error
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```

### Pattern 12: Check for Pending Reviews/Messages

```sql
SELECT task_id, from_session, message, timestamp
FROM orchestration_messages
WHERE task_id LIKE 'task-%'
ORDER BY timestamp DESC
LIMIT 10;
```

### Pattern 13: Staleness Detection

```sql
SELECT task_id, state,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE state IN ('working', 'review_approved', 'review_failed', 'fix_proposed')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
```

### Pattern 14: Insert Instruction Message

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'TASK INSTRUCTION: docs/tasks/task-03.md
     Type: parallel
     Phase: 2
     Dependencies: none',
    'instruction'
);
```

### Pattern 15: Detect Context Warning

```sql
SELECT task_id, state, last_error
FROM orchestration_tasks
WHERE state = 'error' AND last_error = 'context_exhaustion_warning';
```

When matched: Conductor evaluates context situation checklist (self-correction flag, deviations, checkpoint distance, agent estimates, prior warnings) and responds with `review_approved` (proceed with musician's proposal), `fix_proposed` (override scope), or `review_failed` (stop now, prepare handoff).

### Pattern 16: Emergency Broadcast

```sql
-- One message per task_id. Each musician's watcher monitors only its own task_id.
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'EMERGENCY: File merge conflict detected in shared file X. Pause work, await instructions.',
    'emergency'
);
```

Conductor uses this for critical cross-cutting events (shared file conflicts, user-requested pause, etc.). One INSERT per task_id ensures each musician detects the message via its own task's message log.

### Pattern 17: Refresh Conductor Heartbeat

```sql
UPDATE orchestration_tasks SET last_heartbeat = datetime('now') WHERE task_id = 'task-00';
```

Monitoring subagent refreshes this during its poll cycle. Conductor actions (review, error handling, phase transitions) also refresh it. Musicians check this heartbeat at 9-minute threshold — stale conductor heartbeat triggers timeout escalation.

### Pattern 18: Session Handoff (Context Exit)

```sql
-- When musician exits for context exhaustion (clean exit, has HANDOFF doc)
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'SESSION HANDOFF: Musician session exited due to context exhaustion.
     Handoff doc: <musician-tmp>/handoff-{$CLAUDE_SESSION_ID}.md
     Context usage: 87%
     Next step: Launch replacement musician with `claude ...`',
    'handoff'
);
```

See `references/session-handoff.md` for full handoff procedure (clean/dirty/crash types, high-context verification rule, worked_by succession, guard clause re-claiming).

### Pattern 19: Detect and Cleanup Fallback Rows

```sql
-- Monitoring subagent periodically checks for fallback rows
SELECT task_id, last_heartbeat, message
FROM orchestration_tasks
WHERE task_id LIKE 'fallback-%';

-- For each fallback found, extract original task_id and compare timestamps
-- If task's last_heartbeat > fallback's last_heartbeat: DELETE fallback (task worked after collision)
-- If task's last_heartbeat <= fallback's last_heartbeat: Report to user (claim collision, no session claimed it)
DELETE FROM orchestration_tasks
WHERE task_id LIKE 'fallback-%'
  AND task_id NOT IN (
    SELECT 'fallback-' || f.task_id FROM orchestration_tasks f
    INNER JOIN orchestration_tasks t ON t.task_id = SUBSTR(f.task_id, 10)  -- fallback-{original-id}
    WHERE t.last_heartbeat > f.last_heartbeat
  );
```

## Dynamic Row Management

Tables persist across phases. Add rows as phases launch:

```
Plan starts:      orchestration_tasks has [task-00]
Phase 1 launches: + [task-01]
Phase 1 completes: task-01 state='complete'
Phase 2 launches: + [task-03, task-04, task-05, task-06]
Phase 2 completes: all state='complete'
Phase 3 launches: + [task-07, task-08, ...]
```

No table rebuild between phases — just INSERT new rows.

## Old Table Names (NEVER USE)

| Old Name | New Name |
|----------|----------|
| `coordination_status` | `orchestration_tasks` |
| `migration_tasks` | merged into `orchestration_tasks` |
| `task_messages` | `orchestration_messages` |
| `status` column | `state` column |
| `coordination.db` | `comms.db` |
