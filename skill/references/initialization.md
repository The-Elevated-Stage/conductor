<skill name="conductor-initialization" version="4.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Initialization Protocol
</metadata>

<sections>
- bootstrap-steps
- plan-index-verification
- plan-bootstrap-reading
- user-approval-gate
- database-initialization
- souffleur-launch
- message-watcher-launch
- schema-verification
- column-reference
- database-location
- state-machine-overview
- conductor-states
- execution-states
- infrastructure-states
- state-ownership
- state-transition-flows
- heartbeat-rule
- conductor-heartbeat
- memory-plan-tracking
- hook-verification
- old-table-names
</sections>

<section id="bootstrap-steps">
<core>
# Initialization Protocol

## Bootstrap Sequence

Execute these steps in order. Steps 1-5 are reads (parallelizable). Steps 6-8 are writes (sequential). Step 9 is verification. Step 10 is the user gate.

### Step 1: Read Implementation Plan (Selective)

Read the Arranger-produced implementation plan selectively — NOT the full document:
1. Read the plan-index block at the top of the file (see plan-index-verification section)
2. Read the Overview section (via plan-index line range)
3. Read the Phase Summary section (via plan-index line range)

This gives the Conductor the map of the work without loading implementation detail. Phase sections are read on-demand when each phase begins (handled by Phase Execution Protocol).

### Step 2: Git Branch

Verify not on main. Create feature branch if needed.

```bash
bash scripts/check-git-branch.sh
```

<mandatory>Never execute orchestration on the main branch.</mandatory>

### Step 3: Verify temp/ Directory

Create `temp/` if missing.

<mandatory>ALL temporary and scratch files created by the Conductor MUST go in temp/ during execution — never /tmp/ or any other location. temp/ is symlinked to /tmp/remindly and is automatically cleaned on system reboot.</mandatory>

### Step 4: Load docs/ READMEs

Full reads of: `docs/README.md`, `knowledge-base/README.md`, `implementation/README.md`, `implementation/proposals/README.md`, `scratchpad/README.md`. Skip all other READMEs (read on demand).

### Step 5: Load Memory Graph

Read the full knowledge graph via `read_graph` from memory MCP. This provides project-wide decisions, rules, and RAG pointers accumulated from prior sessions.

### Step 6: Initialize Database

Drop and recreate tables via comms-link execute. Insert conductor row and Souffleur row. See database-initialization section for full DDL.

### Step 7: Launch Souffleur

Discover own kitty PID, then launch the Souffleur supervisor. See souffleur-launch section for the full launch sequence and hard gate.

### Step 8: Launch Message Watcher

After the Souffleur is confirmed, launch the background message watcher before hook verification or user approval. See message-watcher-launch section for details.

### Step 9: Verify Hooks

Hooks are self-configuring via `hooks.json` and SessionStart hook. See hook-verification section for details.

### Step 10: User Approval Gate

Present the plan overview to the user (from the Overview and Phase Summary sections read in Step 1). The user approves the execution approach.

<mandatory>This is the last interactive gate. After user approval, the Conductor operates fully autonomously. Do not wait for user input during execution — the user observes via terminal output.</mandatory>
</core>
</section>

<section id="plan-index-verification">
<mandatory>
## Plan-Index Verification

The Arranger's plan-index at the top of the implementation plan is both a map and a lock indicator.

**Verify presence:** The first thing to check is whether `<!-- plan-index:start -->` exists at the top of the file. If absent, the plan has not passed the Arranger's finalization checklist — execution MUST NOT proceed. Report to user.

**Parse line ranges:** The plan-index contains entries like:
```
<!-- phase:1 lines:NN-NN title:"Phase Title" -->
<!-- conductor-review:1 lines:NN-NN -->
```

These line ranges are used throughout the orchestration to selectively read plan sections without loading the full document.

**Verify timestamp:** The `<!-- verified:YYYY-MM-DDTHH:MM:SS -->` entry confirms when finalization occurred.

**Revision metadata:** If the plan is a Repetiteur remaining plan, the index includes `<!-- revision:N -->` and `<!-- supersedes:{file} -->`. The revision number is used for consultation count checks (see Repetiteur Protocol).
</mandatory>
</section>

<section id="plan-bootstrap-reading">
<core>
## Arranger Plan Bootstrap Reading

At bootstrap, only three sections are loaded:

1. **Plan-index** — the line range map (tiny, always read fully)
2. **Overview** — what we're building, why, end goals, constraints. Comprehensive enough to understand the full picture without reading phase sections.
3. **Phase Summary** — quick reference for what each phase covers, dependencies, parallelization opportunities. The Conductor's map of the work.

These are read via the line ranges from the plan-index. Context cost is small — typically 1-3k tokens total.

Individual phase sections are read on-demand when each phase begins, handled by the Phase Execution Protocol. This keeps the Conductor's bootstrap context lean.
</core>
</section>

<section id="user-approval-gate">
<mandatory>
## User Approval Gate

After reading the plan overview, present it to the user:
- What the plan covers (from Overview section)
- Phase count and structure (from Phase Summary)
- Any known risks or constraints flagged in the plan

The user approves the execution approach. This is the LAST interactive gate in the entire orchestration. After this point, the Conductor is fully autonomous — it makes all decisions without waiting for user input. The user can still interrupt or provide input, but the Conductor never pauses to wait.
</mandatory>
</section>

<section id="database-initialization">
<core>
## Database Initialization
</core>

<mandatory>Use comms-link execute (raw SQL) for CREATE TABLE with CHECK constraints. The create-table tool does not support CHECK.</mandatory>

<template follow="exact">
```sql
-- Drop existing tables (clean start for new implementation)
DROP TABLE IF EXISTS orchestration_tasks;
DROP TABLE IF EXISTS orchestration_messages;
DROP TABLE IF EXISTS repetiteur_conversation;

-- Table 1: State machine + lifecycle
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

-- Table 2: Append-only message log
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

-- Table 3: Repetiteur conversation (back-and-forth dialogue)
CREATE TABLE repetiteur_conversation (
    id INTEGER PRIMARY KEY,
    sender TEXT NOT NULL,
    message TEXT NOT NULL,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Insert infrastructure rows
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('souffleur', 'watching', datetime('now'));

-- Insert conductor row
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));

-- Create indexes for query performance
CREATE INDEX idx_messages_task_time ON orchestration_messages(task_id, timestamp);
CREATE INDEX idx_messages_type ON orchestration_messages(message_type);
CREATE INDEX idx_tasks_state_heartbeat ON orchestration_tasks(state, last_heartbeat);
```
</template>
</section>

<section id="souffleur-launch">
<core>
## Step 7: Launch Souffleur

### Discover Own Kitty PID

Walk the process tree to find the kitty PID that owns this session. This PID is passed to the Souffleur so it can monitor the Conductor's terminal window.

See RAG: "kitty PID discovery" for the discovery method.

### Launch Souffleur

```bash
kitty --directory /home/kyle/claude/remindly \
  --title "Souffleur" \
  -- env -u CLAUDECODE claude \
  --permission-mode acceptEdits \
  "/souffleur PID:$KITTY_PID SESSION_ID:$CLAUDE_SESSION_ID" &
```

`$CLAUDE_SESSION_ID` is a system prompt value injected by the SessionStart hook — it is NOT a bash environment variable. The Conductor references it from its own context when constructing the launch command.

### Hard Gate: Souffleur Confirmation

Poll comms-link until the Souffleur row reaches `state = 'confirmed'`:

```sql
SELECT state FROM orchestration_tasks WHERE task_id = 'souffleur';
```

**If `confirmed`:** Souffleur is ready. Proceed to Step 8.

**If `error`:** Read the Souffleur's diagnostic message from orchestration_messages and respond with corrected arguments.

**If `exited` after 3 failures:** Report to user — cannot proceed without a live Souffleur. The Conductor requires Souffleur supervision for recovery capability.
</core>

<mandatory>
The Souffleur launch is a hard gate — the Conductor MUST NOT proceed to any further steps (message watcher, hook verification, user approval, or phase execution) until the Souffleur row reaches `confirmed` state. A Conductor without a live Souffleur has no recovery capability.
</mandatory>
</section>

<section id="message-watcher-launch">
<core>
## Step 8: Launch Message Watcher

After the Souffleur is confirmed, launch the background message watcher immediately — before hook verification, user approval, or any Musicians.

The message watcher provides:
- Event detection for task state changes (review requests, errors, completions)
- Conductor heartbeat refreshing on every poll cycle
- Foundation for the monitoring infrastructure that all subsequent protocols depend on

Launch the message watcher using the monitoring-subagent-template from the Phase Execution Protocol reference file. The watcher must be running before the Conductor enters phase execution.
</core>
</section>

<section id="schema-verification">
<core>
## Schema Verification

After initialization, verify tables exist with correct columns:

```sql
PRAGMA table_info(orchestration_tasks);
PRAGMA table_info(orchestration_messages);
```

If columns are missing or tables don't exist: drop and recreate using the DDL above.
</core>
</section>

<section id="column-reference">
<core>
## Column Reference

### orchestration_tasks

| Column | Type | Purpose |
|--------|------|---------|
| `task_id` | TEXT PK | `task-00` (conductor), `task-01`+ (execution), `fallback-{session_id}` (guard block exits), `task-XX-fix` (post-completion corrections) |
| `state` | TEXT NOT NULL | State machine value (13 valid states via CHECK) |
| `instruction_path` | TEXT | Path to task instruction file in `docs/tasks/` |
| `session_id` | TEXT | Actual Claude Code session ID (set by SessionStart hook, injected into system prompt as $CLAUDE_SESSION_ID) |
| `worked_by` | TEXT | Worker identifier with succession: `musician-task-{NN}`, `musician-task-{NN}-S2`, etc. |
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
| `from_session` | TEXT | Who sent the message (session ID or `task-00` for conductor) |
| `message` | TEXT | Free-text message content |
| `message_type` | TEXT | Enum for filtering without parsing body |
| `timestamp` | TEXT | Auto-set to CURRENT_TIMESTAMP |
</core>
</section>

<section id="database-location">
<core>
## Database Location

`/home/kyle/claude/remindly/comms.db` — shared by comms-link MCP server and stop hook (via sqlite3).

<mandatory>All database operations MUST use comms-link MCP (query for SELECT, execute for writes). Direct sqlite3 CLI access creates WAL isolation issues — comms-link cannot see changes made by sqlite3 and vice versa.</mandatory>
</core>
</section>

<section id="state-machine-overview">
<core>
## State Machine Overview

All state is stored in `orchestration_tasks` in `comms.db`. Single `state` column with CHECK constraint enforcing exactly 13 valid values. No separate `status` column.

Individual state transitions are co-located in the protocol files where they're used. This section provides the overview — the complete picture of what states exist, who owns them, and how they flow.
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
| `context_recovery` | Conductor | Context exhausted, handoff prepared, Souffleur kills and relaunches | Yes (hook allows exit) |

Hook exit criteria: Conductor session can only exit when state is `exit_requested`, `complete`, or `context_recovery`.
</core>
</section>

<section id="execution-states">
<core>
## Execution States (task-01+)

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `watching` | Conductor | Inserted but no session has claimed it yet | No |
| `working` | Execution | Actively executing task steps | No |
| `needs_review` | Execution | Review submitted, awaiting conductor | No |
| `review_approved` | **Conductor** | Approved, execution resumes | No |
| `review_failed` | **Conductor** | Rejected, execution revises | No |
| `error` | Execution | Hit an error, awaiting conductor fix | No |
| `fix_proposed` | **Conductor** | Fix sent, execution applies it | No |
| `complete` | Execution | Task finished successfully | Yes (hook allows exit) |
| `exited` | Execution OR Conductor | Terminated without completion | Yes (hook allows exit) |

Hook exit criteria: Execution session can only exit when state is `complete` or `exited`.
</core>
</section>

<section id="infrastructure-states">
<core>
## Infrastructure States

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `confirmed` | Souffleur | Bootstrap validation passed — Souffleur is operational | No |

The `confirmed` state is used exclusively by the Souffleur row (`task_id = 'souffleur'`). It signals that the Souffleur has completed its own bootstrap and is actively supervising the Conductor. The Souffleur row stays `confirmed` for the duration of normal operations — there is no `confirmed` → `watching` transition.
</core>

<context>
Both `confirmed` and `context_recovery` are retroactive DDL alignment — the Souffleur skill (v1.1) already depends on these states. Without these additions to the CHECK constraint, the Souffleur's state transitions would violate the constraint at runtime.
</context>
</section>

<section id="state-ownership">
<core>
## State Ownership Summary

**Conductor sets:** `watching`, `reviewing`, `exit_requested`, `complete`, `review_approved`, `review_failed`, `fix_proposed`, `context_recovery`, `exited` (heartbeat staleness only)

**Execution sets:** `working`, `needs_review`, `error`, `complete`, `exited` (5th retry failure or clean context exit)
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

Conductor context exit (recovery):
  watching → context_recovery → [Souffleur kills, relaunches new Conductor]

Souffleur lifecycle:
  watching → confirmed → complete
  watching → error → [retry] → confirmed → complete
  watching → error → ... (x3) → exited
```
</core>
</section>

<section id="heartbeat-rule">
<mandatory>
## Heartbeat Rule

Update `last_heartbeat` on EVERY state transition:

```sql
UPDATE orchestration_tasks
SET state = '{new_state}', last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';
```

All SQL in task instructions and conductor workflows MUST include `last_heartbeat = datetime('now')` alongside any `state` change. This enables staleness detection. Omitting the heartbeat from a state update is a bug.
</mandatory>
</section>

<section id="conductor-heartbeat">
<core>
## Conductor Heartbeat Refresh

The Conductor's own heartbeat (task-00) must be kept alive. Musicians check the Conductor's heartbeat to detect if the Conductor has crashed. The monitoring subagent refreshes this during its poll cycle.

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</template>

If the Conductor's heartbeat goes stale (>9 minutes), Musicians consider the Conductor down and may escalate.
</core>
</section>

<section id="memory-plan-tracking">
<core>
## MEMORY.md Plan Tracking

The current plan path is tracked as a single line in MEMORY.md:

```
## Active Orchestration
Current plan: docs/plans/designs/{feature}-plan.md
```

This line is:
- **Set** during initialization after verifying the plan-index
- **Updated** when a Repetiteur remaining plan replaces the current plan (see Repetiteur Protocol)
- **The source of truth** — if any plan reference doesn't match MEMORY.md, something is wrong

<mandatory>MEMORY.md is loaded every turn. This persistent anchor survives session interruptions and ensures the Conductor always knows which plan it is working from.</mandatory>
</core>
</section>

<section id="hook-verification">
<core>
## Hook Verification

Hooks are self-configuring via `hooks.json` and the SessionStart hook. Verify:

1. `hooks.json` exists in `tools/implementation-hook/`
2. `session-start-hook.sh` exists in `tools/implementation-hook/`
3. `stop-hook.sh` exists in `tools/implementation-hook/`
4. `comms.db` is accessible via comms-link (run a simple SELECT to confirm)

The SessionStart hook injects `CLAUDE_SESSION_ID={session_id}` into the system prompt via `additionalContext`. This is how the Conductor and Musicians identify themselves in the database.

The Stop hook queries `orchestration_tasks` by session_id and only allows session exit when the task state is terminal (`complete`, `exited`, `exit_requested` for conductor, or `context_recovery` for conductor).
</core>
</section>

<section id="old-table-names">
<mandatory>
## Old Table Names (NEVER USE)

These names are from a previous design and must never appear in SQL:

| Old Name | Current Name |
|----------|-------------|
| `coordination_status` | `orchestration_tasks` |
| `migration_tasks` | `orchestration_tasks` |
| `task_messages` | `orchestration_messages` |
| `status` column | `state` column |

If you see these names in any context, they are outdated. Always use `orchestration_tasks` and `orchestration_messages`.
</mandatory>
</section>

</skill>
