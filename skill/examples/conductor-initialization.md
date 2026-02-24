<skill name="conductor-example-initialization" version="4.0">

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- scenario
- read-plan
- git-branch
- verify-temp
- load-readmes
- load-memory
- initialize-database
- souffleur-launch
- message-watcher-launch
- verify-hooks
- user-approval-gate
</sections>

<section id="scenario">
<context>
# Example: Conductor Initialization

This example shows the complete initialization workflow for a documentation reorganization plan.

## Scenario

Implementation plan: `docs/plans/2026-02-04-docs-reorganization.md`
- Phase 1: Foundation task (sequential)
- Phase 2: Extraction tasks 3-6 (parallel)
- Phase 3: Migration tasks 7-10 (mixed)
</context>
</section>

<section id="read-plan">
<core>
## Step 1: Read Implementation Plan (Selective)

Read the plan-index block first, then use its line ranges to read only the Overview and Phase Summary sections:

```
Read docs/plans/2026-02-04-docs-reorganization.md (lines 1-15 for plan-index)
Read docs/plans/2026-02-04-docs-reorganization.md (lines per plan-index for Overview)
Read docs/plans/2026-02-04-docs-reorganization.md (lines per plan-index for Phase Summary)
```

Identify:
- 3 phases
- Phase 1: task-01 (sequential, foundation)
- Phase 2: task-03 through task-06 (parallel-safe, independent extraction)
- Phase 3: task-07 through task-10 (mixed — some parallel, some sequential)
- Danger files: `knowledge-base/testing/README.md` shared by task-03 and task-04
</core>
</section>

<section id="git-branch">
<core>
## Step 2: Git Branch

```bash
# Check current branch
git branch --show-current
# Output: main

# Create feature branch
git checkout -b feat/docs-reorganization

# Verify
git branch --show-current
# Output: feat/docs-reorganization
```
</core>
</section>

<section id="verify-temp">
<core>
## Step 3: Verify temp/ Directory

```bash
ls -la temp/ || mkdir -p temp/
```
</core>
</section>

<section id="load-readmes">
<core>
## Step 4: Load docs/ READMEs

Read these 5 files (full reads, ~1-2k tokens total):
- `docs/README.md`
- `docs/knowledge-base/README.md`
- `docs/implementation/README.md`
- `docs/implementation/proposals/README.md`
- `docs/scratchpad/README.md`
</core>
</section>

<section id="load-memory">
<core>
## Step 5: Load Memory Graph

Read the full knowledge graph via memory MCP `read_graph`. Review for project-wide decisions, rules, and RAG pointers relevant to this orchestration run.
</core>
</section>

<section id="initialize-database">
<core>
## Step 6: Initialize Database

Via comms-link execute:
</core>

<template follow="format">
```sql
-- Core DDL shown here. Full canonical DDL is in references/initialization.md.
DROP TABLE IF EXISTS orchestration_tasks;
DROP TABLE IF EXISTS orchestration_messages;
DROP TABLE IF EXISTS repetiteur_conversation;

CREATE TABLE orchestration_tasks (
    task_id TEXT PRIMARY KEY,
    state TEXT NOT NULL CHECK (state IN (
        'watching', 'reviewing', 'exit_requested', 'complete',
        'working', 'needs_review', 'review_approved', 'review_failed',
        'error', 'fix_proposed', 'exited',
        'context_recovery',
        'confirmed'
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

CREATE TABLE orchestration_messages (
    id INTEGER PRIMARY KEY,
    task_id TEXT,
    from_session TEXT,
    message TEXT,
    message_type TEXT CHECK (message_type IN (
        'review_request', 'error', 'context_warning', 'completion',
        'emergency', 'handoff', 'approval', 'fix_proposal',
        'rejection', 'instruction', 'claim_blocked', 'resumption',
        'system'
    )),
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE repetiteur_conversation (
    id INTEGER PRIMARY KEY,
    sender TEXT NOT NULL,
    message TEXT NOT NULL,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Insert infrastructure rows (souffleur BEFORE conductor)
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('souffleur', 'watching', datetime('now'));

INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));

-- Indexes for query performance
CREATE INDEX idx_messages_task_time ON orchestration_messages(task_id, timestamp);
CREATE INDEX idx_messages_type ON orchestration_messages(message_type);
CREATE INDEX idx_tasks_state_heartbeat ON orchestration_tasks(state, last_heartbeat);
```
</template>

<core>
Verify:
```sql
SELECT * FROM orchestration_tasks;
-- Expected: 2 rows — souffleur (watching), task-00 (watching)
```
</core>
</section>

<section id="souffleur-launch">
<core>
## Step 7: Launch Souffleur

Discover own kitty PID via process tree walk (see RAG: "kitty PID discovery"), then launch:

```bash
kitty --directory /home/kyle/claude/remindly \
  --title "Souffleur" \
  -- env -u CLAUDECODE claude \
  --permission-mode acceptEdits \
  "/souffleur PID:$KITTY_PID SESSION_ID:$CLAUDE_SESSION_ID" &
```

Hard gate — poll until Souffleur confirms:
```sql
SELECT state FROM orchestration_tasks WHERE task_id = 'souffleur';
-- Wait for: state = 'confirmed'
```

Do not proceed until confirmed. If `error`, read diagnostic and retry. After 3 failures, report to user.
</core>
</section>

<section id="message-watcher-launch">
<core>
## Step 8: Launch Message Watcher

After Souffleur is confirmed, launch the background message watcher before hook verification or user approval. This provides event detection for state changes and heartbeat refreshing.
</core>
</section>

<section id="verify-hooks">
<core>
## Step 9: Verify Hooks and Database

Hooks self-configure via `hooks.json` preset detection. No manual setup.sh step needed.

Verify hook files exist:
```bash
# SessionStart hook script
test -f tools/implementation-hook/session-start-hook.sh && echo "SessionStart hook found"

# Stop hook (configured via hooks.json preset)
test -f tools/implementation-hook/stop-hook.sh && echo "Stop hook found"

# Hook configuration file
test -f tools/implementation-hook/hooks.json && echo "hooks.json found"

# Database is initialized and accessible
test -f comms.db && echo "Database ready"
```
</core>

<context>
**Expected behavior:** When conductor session starts, SessionStart hook automatically injects `$CLAUDE_SESSION_ID` into the system prompt (available as a value, not a bash env var). Stop hook (via preset) monitors session state and blocks exit until task is in terminal state.
</context>
</section>

<section id="user-approval-gate">
<core>
## Step 10: User Approval Gate

Present the plan overview to the user (from Overview and Phase Summary sections read in Step 1):

```markdown
Ready to execute: Documentation Reorganization
- 3 phases, 9 tasks
- Phase 1: Foundation (sequential, 1 task)
- Phase 2: Extraction (parallel, 4 tasks)
- Phase 3: Migration (mixed, 4 tasks)
- Danger files: knowledge-base/testing/README.md (shared by task-03 and task-04)

Approve execution?
```

After approval, set the plan tracking line in MEMORY.md:

```markdown
## Active Orchestration
Current plan: docs/plans/2026-02-04-docs-reorganization.md
```

This is the last interactive gate. After this point, the Conductor operates fully autonomously.

**Next:** Begin Phase 1 — create task instruction for task-01.
</core>
</section>

</skill>
