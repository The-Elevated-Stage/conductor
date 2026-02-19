# Example: Conductor Initialization

This example shows the complete initialization workflow for a documentation reorganization plan.

## Scenario

Implementation plan: `docs/plans/2026-02-04-docs-reorganization.md`
- Phase 1: Foundation task (sequential)
- Phase 2: Extraction tasks 3-6 (parallel)
- Phase 3: Migration tasks 7-10 (mixed)

## Step 1: Read Implementation Plan

```
Read docs/plans/2026-02-04-docs-reorganization.md
```

Identify:
- 3 phases
- Phase 1: task-01 (sequential, foundation)
- Phase 2: task-03 through task-06 (parallel-safe, independent extraction)
- Phase 3: task-07 through task-10 (mixed — some parallel, some sequential)
- Danger files: `knowledge-base/testing/README.md` shared by task-03 and task-04

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

## Step 3: Verify temp/ Directory

```bash
ls -la temp/ || mkdir -p temp/
```

## Step 4: Load docs/ READMEs

Read these 5 files (full reads, ~1-2k tokens total):
- `docs/README.md`
- `docs/knowledge-base/README.md`
- `docs/implementation/README.md`
- `docs/implementation/proposals/README.md`
- `docs/scratchpad/README.md`

## Step 5: Load Memory Graph

Read the full knowledge graph via memory MCP `read_graph`. Review for project-wide decisions, rules, and RAG pointers relevant to this orchestration run.

## Step 6: Initialize STATUS.md

```markdown
# STATUS.md — Documentation Reorganization

## Conductor Info
- **Session ID:** $CLAUDE_SESSION_ID (set by SessionStart hook)
- **Branch:** feat/docs-reorganization
- **Database:** comms.db (orchestration_tasks, orchestration_messages)
- **Plan:** docs/plans/2026-02-04-docs-reorganization.md (LOCKED)

## Phase Overview
- Phase 1 (Foundation): task-01 — PENDING
- Phase 2 (Extraction): task-03, task-04, task-05, task-06 — PENDING
- Phase 3 (Migration): task-07, task-08, task-09, task-10 — PENDING

### Task 1: Create Documentation Structure
State: Pending | Type: Sequential | Phase: 1

### Task 3: Extract Testing Docs
State: Pending | Type: Parallel | Phase: 2
⚠️ Danger Files: knowledge-base/testing/README.md (shared with Task 4)

### Task 4: Extract API Docs
State: Pending | Type: Parallel | Phase: 2
⚠️ Danger Files: knowledge-base/testing/README.md (cross-references from Task 3)

### Task 5: Extract Database Docs
State: Pending | Type: Parallel | Phase: 2

### Task 6: Extract Architecture Docs
State: Pending | Type: Parallel | Phase: 2

## Task Planning Notes
(Empty — populated during execution)

## Proposals Pending
(None yet)

## Recovery Instructions
(Written before context exit)

## Project Decisions Log
- 2026-02-04 09:15: Plan locked. Branch created.
```

## Step 7: Initialize Database

Via comms-link execute:

```sql
DROP TABLE IF EXISTS orchestration_tasks;
DROP TABLE IF EXISTS orchestration_messages;

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

INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));
```

Verify:
```sql
SELECT * FROM orchestration_tasks;
-- Expected: 1 row, task-00, state=watching
```

## Step 8: Verify Hooks and Database

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

**Expected behavior:** When conductor session starts, SessionStart hook automatically injects `$CLAUDE_SESSION_ID` into the system prompt (available as a value, not a bash env var). Stop hook (via preset) monitors session state and blocks exit until task is in terminal state.

## Step 9: Lock Plan

Plan is now frozen. Record in STATUS.md:
```markdown
## Project Decisions Log
- 2026-02-04 09:15: Plan locked. Branch created.
- 2026-02-04 09:16: Initialization complete. Database ready. Hook active.
```

**Next:** Begin Phase 1 — create task instruction for task-01.
