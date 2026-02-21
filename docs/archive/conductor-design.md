# Conductor Skill Design Document

## Frontmatter & Skill Metadata

```yaml
---
name: Conductor
description: This skill should be used when the user asks to "orchestrate this plan", "coordinate implementation", "run parallel implementation", "use the orchestration skill", "launch execution sessions", "resume orchestration", "run this plan", or wants to autonomously execute a multi-task implementation plan using database coordination, parallel execution sessions, and phased task management.
---
```

## Purpose

The Conductor is a coordination-focused session manager designed to run as the main Claude session (Tier 0). It reads implementation plans, transforms them into self-contained task instruction files via subagents, launches external Claude sessions to execute those instructions, monitors progress via database polling, handles reviews and errors, manages phase transitions, and coordinates final integration.

Unlike the Musician (Tier 1, which does direct integration work and delegates to Tier 2 subagents), the Conductor does **no implementation work**. It reads plans, creates instructions, monitors, reviews, triages errors, and coordinates. All coding, testing, and documentation creation is delegated — either to subagents (for instruction creation and monitoring) or to external execution sessions (for all implementation).

The Conductor is context-frugal, self-aware about remaining headroom, delegates aggressively to preserve context for wide-scope strategic decisions, and escalates to the user when uncertain or when execution sessions require intervention it cannot provide.

## 3-Tier Orchestration Model

```
Tier 0: This session — conductor
  ├─ Reads and locks implementation plan
  ├─ Creates phases, launches task instruction subagents
  ├─ Monitors all Tier 1 sessions via database
  ├─ Handles reviews, errors, phase transitions
  ├─ Manages danger files, emergency broadcasts, proposal integration
  └─ Coordinates final integration and PR preparation

Tier 1: Execution sessions (EXTERNAL Claude sessions) — Musician skill
  ├─ Reads task instruction file
  ├─ Launches Tier 2 subagents for small/isolated work
  ├─ Does direct integration work (refactor, assemble, holistic test)
  ├─ Manages verification checkpoints
  ├─ Coordinates review cycles with conductor
  └─ Handles context-aware pausing and resumption

Tier 2: Subagents (launched by Tier 1)
  ├─ Receive task-specific instruction sections
  ├─ Do focused implementation (code, unit tests, docs)
  └─ Return tested code ready for integration
```

**Key distinction:** Execution sessions (Tier 1) are EXTERNAL Claude Code sessions running in separate terminals with their own 200k context windows. They are NOT subagents. The conductor CANNOT launch them — it provides terminal commands to the user. Subagents are spawned by the conductor using the Task tool within its own context budget and are used only for instruction creation and monitoring.

## Execution Model & Tool Utilization

### Category 1: Conductor Tools (Direct Use)

```
comms-link — SQLite coordination database (comms.db)
  - Tables: orchestration_tasks, orchestration_messages (static names, reused across plans)
  - Query task status, send/receive messages, track progress
  - CRITICAL: Use comms-link for ALL database operations (WAL isolation with sqlite3 CLI)

local-rag — Knowledge base RAG server
  - Verify ingestion after execution sessions complete
  - Query to check for duplicate patterns before integration
  - Use for task instruction creation (search orchestration patterns)

memory — Persistent knowledge graph
  - Store orchestration patterns, anti-patterns, cross-project learnings
  - Query for historical decisions and rationale

filesystem — File operations (confined to workspace)
  - Read implementation plans
  - Write STATUS.md, task instruction files
  - Read completion reports, proposals

sequential-thinking — Structured multi-step reasoning
  - Use for complex error triage or phase planning decisions
```

### Category 2: Execution Session Tools (Recommend in Instructions)

```
filesystem — File operations (also used by conductor)
serena — Semantic code analysis (symbol-level reading/editing)
repomix — Codebase analysis (pack/analyze large codebases)
github-server — GitHub operations (PRs, issues, status checks)
postgresql — Database operations (migrations, queries)
postman — API testing/operations
flutter-inspector — Flutter app debugging
mermaid — Diagram creation
playwright — Browser automation
```

The conductor does NOT use code analysis or implementation tools directly. It recommends them in task instructions for execution sessions.

## Delegation Model

The conductor preserves its 200k-token context budget for what only it can do: see the full picture across all tasks, make strategic decisions, and coordinate.

**Conductor does directly:**
- Plan interpretation and phase identification
- Danger file risk assessment and mitigation decisions
- Sequential vs parallel decisions
- Review evaluation (smoothness scoring, approval/rejection)
- Error triage and fix proposal creation
- Cross-task coordination and emergency broadcasts
- Phase transition management
- Proposal integration decisions
- Final integration verification
- User communication and escalation

**Conductor delegates to subagents (Task tool):**
- Task instruction creation (one subagent per phase)
- Background monitoring (database polling)
- RAG queries for pattern lookup
- STATUS.md reading (when targeted reads are needed)

**Conductor delegates to external sessions (user-launched):**
- All implementation work (code, tests, documentation)
- All code review and verification
- All file creation and modification in source code
- All testing and coverage analysis

**Decision heuristic:** If it requires understanding the full plan, coordinating across tasks, or making strategic decisions → conductor does it. If it requires writing code, running tests, or focused file operations → delegate to execution session. If it requires creating instructions, monitoring, or quick lookups → delegate to subagent.

## Bootstrap & Initialization

Execute these steps in order when starting a new orchestration session. **Steps 1-5 are reads (parallelizable). Steps 6-8 are writes (sequential). Step 9 is a gate (launch initiation).**

### 1. Read Implementation Plan

Read the implementation plan file. Identify:
- Phases and their ordering
- Task dependencies (which tasks block others)
- Parallel-safe groups (tasks that can run simultaneously)
- Danger file annotations (inline `⚠️ Danger Files:` markers)
- Expected deliverables per task
- Estimated complexity per task

### 2. Git Branch Setup (MANDATORY)

Verify the working directory is not on main/master. If on main:

```
STOP - Must create feature branch before proceeding.

Ask user: "You're currently on [main/master].
Create feature branch for this implementation?

Suggested: feature/[plan-name-from-doc]
(e.g., feature/docs-reorganization)

Proceed with feature branch creation?"
```

Wait for user confirmation. On confirmation:
```bash
git checkout -b feature/[branch-name]
```

Run `scripts/check-git-branch.sh` to verify. If already on feature branch, proceed.

### 3. Verify temp/ Directory

```bash
test -d /home/kyle/claude/remindly/temp || mkdir -p /home/kyle/claude/remindly/temp
```

`temp/` is a symlink to `/tmp/remindly` (cleared on reboot). Safe for scratch files, logs, intermediate outputs. Never store important state here.

### 4. Load docs/ READMEs

Full reads of these 5 READMEs (~1-2k tokens total):
- `docs/README.md` — Documentation system overview
- `docs/knowledge-base/README.md` — File format, metadata standard
- `docs/implementation/README.md` — Reports and proposals overview
- `docs/implementation/proposals/README.md` — Proposal workflow, flat structure
- `docs/scratchpad/README.md` — Active tracking workflow

Skip all other READMEs — read on demand if needed. Full reads are more resilient than heading-based partial reads and the cost is negligible.

### 5. Load Memory Graph

Read the full knowledge graph via `read_graph` from memory MCP. This provides project-wide decisions, rules, and RAG pointers accumulated from prior sessions for broad decision-making and project mapping.

### 6. Initialize STATUS.md

Create `docs/implementation/STATUS.md` with:
- Conductor session ID (`$CLAUDE_SESSION_ID` from system prompt)
- Task list from implementation plan
- Coordination database info
- Git branch information
- Task Planning Notes section (extracted goals per task)
- Proposals Pending section
- Recovery Instructions section
- Project Decisions Log section

STATUS.md is the conductor's runtime tracking file. The implementation plan is a static input; STATUS.md is the live state that enables mid-plan recovery after context exhaustion. Design principle: section-based updates (touch ONE task section per checkpoint, not the whole file).

See [Reference: STATUS.md Template](#reference-statusmd-template) for the full template.

### 7. Initialize Database

Drop and recreate tables via `comms-link execute` (raw SQL). Insert conductor row.

```sql
-- Drop existing tables (clean start for new implementation)
DROP TABLE IF EXISTS orchestration_tasks;
DROP TABLE IF EXISTS orchestration_messages;

-- Create tables (use comms-link execute for CHECK constraint support)
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

-- Add indexes for query performance
CREATE INDEX idx_messages_task_time ON orchestration_messages(task_id, timestamp);
CREATE INDEX idx_messages_type ON orchestration_messages(message_type);
CREATE INDEX idx_tasks_state_heartbeat ON orchestration_tasks(state, last_heartbeat);

-- Insert conductor row
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));
```

**CRITICAL:** Use `comms-link execute` for all DDL statements. The `create-table` tool does not support CHECK constraints. Never use `sqlite3` CLI for operations that comms-link needs to see — WAL isolation means comms-link cannot see changes made by sqlite3 and vice versa.

### 8. Verify Hooks

Hooks are self-configuring via `hooks.json` and the SessionStart hook. Verify:
- `tools/implementation-hook/hooks.json` exists
- `tools/implementation-hook/session-start-hook.sh` exists
- `tools/implementation-hook/stop-hook.sh` exists (referenced via hooks.json)
- `comms.db` is accessible via comms-link

The SessionStart hook auto-injects `CLAUDE_SESSION_ID=<session_id>` into the system prompt as `additionalContext`. This is a system prompt value, NOT a bash environment variable. The stop hook monitors `orchestration_tasks` for the session's task state and blocks exit until a terminal state is reached.

### 9. Lock Implementation Plan

The plan is now frozen. Record in STATUS.md Project Decisions Log:

```
[YYYY-MM-DD HH:MM] - Plan Locked
Decision: Implementation plan locked at execution start
File: [path to plan]
```

- **Conductor deviations** (going sequential instead of parallel, discovering hidden dependencies) → written to STATUS.md Task Planning Notes. These are mutable working memory, not a second source of truth.
- **External user changes** → go to `{plan-name}-revisions.md` (standardized naming: append `-revisions` to plan filename). This separate file doesn't corrupt the original plan.

## Phase Planning & Task Instruction Creation

For each phase in the implementation plan:

### 1. Analyze Phase

Identify:
- Task type: sequential or parallel
- Danger files across tasks in phase
- Inter-task dependencies
- Expected deliverables and complexity

### 2. Review Danger Files

Extract inline annotations from the plan. Assess severity and timeline overlap.

| Severity | Criteria | Action |
|----------|----------|--------|
| Low | Append-only changes, no semantic conflict | Keep parallel, add ordering notes |
| Medium | Same file, different sections | Keep parallel with mitigation, or move sequential |
| High | Same functions/sections, semantic conflict | Move to sequential or split task |

See [Reference: Danger Files Governance](#reference-danger-files-governance) for the complete decision matrix and mitigation patterns.

### 3. Prepare Overrides & Learnings

Review the implementation plan for this phase. Note any conductor corrections, task planning notes, or learnings from prior phases that should override or supplement what's in the plan. These will be passed directly in the subagent prompt.

### 4. MANDATORY: Launch Task Subagent

Use the Task tool to launch a subagent with the `copyist` skill. The subagent will:
- Read the implementation plan directly
- Load the `copyist` skill
- Create ALL instruction files for the phase in `docs/tasks/task-{ID}.md`
- Apply any overrides from the conductor
- Validate each file and report results

**Use this prompt template for the Task tool call:**
```
Task("Create task instructions for Phase {N}", prompt="""

Load the copyist skill, then create task instruction files for this phase.

## Phase Info
**Phase:** {N} — {NAME}
**Task type:** {TYPE} (sequential/parallel)
**Tasks to create:** {TASK_LIST}
**Implementation plan:** {PLAN_PATH}
**Output directory:** docs/tasks/

## Overrides & Learnings
{CONDUCTOR_NOTES — hard-coded corrections, scope adjustments,
danger file decisions, or lessons from prior phases that override
the implementation plan for these tasks}

## Instructions
1. Read the implementation plan at `{PLAN_PATH}`
2. Invoke the `copyist` skill
3. Read the appropriate template (sequential or parallel) — following templates is MANDATORY
4. Extract the tasks listed above from the plan
5. Apply any Overrides & Learnings — these take precedence over the plan
6. Write instruction files to `docs/tasks/`
7. Validate each file and fix errors until all pass

Report validation results for each file when done.
""", run_in_background=False)
```

**DO NOT skip this step.** If you skip launching the subagent, the task instruction files will not be created and orchestration will fail.

See [Reference: Subagent Prompt Template](#reference-subagent-prompt-template) for the full template with quality gate, placeholder table, and post-return review guidance.

### 5. Review Returned Instructions

**Template compliance validation:**
- All sections from the selected template are present
- Inapplicable sections marked N/A with reason, not omitted
- Parallel template `[STRICT]` sections included verbatim

**Review from in-memory context** — don't re-read the implementation plan. Use Task Planning Notes from STATUS.md:

```
Task 3 notes:
- Extract testing patterns from 6 files
- Create proposal before extraction
- Checkpoint: proposal review
- Verify YAML frontmatter
```

**Review checklist (STRATEGY focus):**
- Instructions align with overall plan goals?
- Appropriate pattern chosen (sequential vs parallel)?
- Task dependencies make sense?
- Review checkpoints at logical points?
- Context budget reasonable for execution session?
- Verification steps adequate for deliverables?
- Integration with other tasks considered?

**Iteration limits:**
- Same issue recurring: 2 loops max → user intervention
- Total reviews per instruction: 5 max → user intervention
- Reviews are full document, not first-issue-only

**Review-correction loop:**
```
Conductor → Review finds issue
   ↓
Conductor → Prompt subagent: "Missing X, check plan section Y"
   ↓
Subagent → Read additional section, revise instruction
   ↓
Conductor → Review again
```

### 6. Insert Database Rows

For each task in the phase:

```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-XX', 'watching', 'docs/tasks/task-XX.md', datetime('now'));
```

### 7. Insert Instruction Messages

**INSERT task row first (step 6), then INSERT instruction message sequentially.** Musician claims only after both exist.

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'TASK INSTRUCTION: docs/tasks/task-XX.md
     Type: [sequential|parallel]
     Phase: N
     Dependencies: [list or none]
     Danger files: [list or none]',
    'instruction');
```

**Subagent retry policy:** 3 retries maximum with same prompt. After 3 failures, escalate to user with all error messages and options (skip phase, abort, retry manually). See [Reference: Subagent Failure Handling](#reference-subagent-failure-handling) for failure categories, retry decision flowchart, and escalation message format.

## Launching Execution Sessions

### Sequential Tasks

Use the same musician skill launch template (with `/musician` prefix), but launch one task at a time. Wait for the task to reach `complete` state before launching the next task. No danger files coordination needed for sequential tasks.

```
Phase N ready. Please launch execution session:

Terminal 1:
claude "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = 'task-XX' AND message_type = 'instruction';

[... full musician template ...]"
```

**Background message-watcher is REQUIRED.** See `references/sequential-coordination.md` for details.

### Parallel Tasks

Present user with terminal commands:

```
Phase N ready. Please launch N execution sessions:

Terminal 1: claude "Read task instruction from orchestration_messages for task-XX and execute it."
Terminal 2: claude "Read task instruction from orchestration_messages for task-YY and execute it."
Terminal 3: claude "Read task instruction from orchestration_messages for task-ZZ and execute it."
...

All sessions will coordinate autonomously via comms-link database.
I will monitor for completion and reviews.

CLI notes:
- `claude "prompt"` starts a new interactive session with an initial prompt
- `--continue` resumes the most recent conversation in cwd
- `--resume [session-id]` resumes a specific session (or opens picker)
- `--append-system-prompt "text"` adds conductor context without replacing defaults
```

### Launch Sequence

1. **Launch background verification watcher first** — Before presenting prompts to the user, launch a watcher subagent to poll for tasks reaching `working` state. This ensures monitoring is active before the user starts sessions.
2. **Present musician prompts to user** — Show the filled-in terminal commands. The watcher is already running.
3. **Watcher behavior:**
   - If all tasks reach `working` within 5 minutes: watcher exits and notifies conductor
   - If any remain `watching` after 5 minutes: watcher notifies conductor to re-prompt user with musician template
4. **After verification complete:** Start the main background monitoring subagent. See [Reference: Monitoring Subagent Templates](#reference-monitoring-subagent-templates).

## Monitoring

### Tiered STATUS.md Reading Strategy

Avoid re-reading the full STATUS.md on every checkpoint. Use a tiered approach:

**Tier 1 — Database Queries (frequent):**
Every monitoring cycle. Near-zero token cost.
```sql
SELECT task_id, state, last_heartbeat
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```

**Tier 2 — Partial STATUS.md Reads (selective):**
When reviewing a specific task's context. Read only that task's section (~500-1k tokens). Task section names are stable (`### Task N: [Name]`) and won't change mid-implementation, making partial reads safe.

**Tier 3 — Full STATUS.md Reads (rare):**
Only at initialization, final completion check, resumption, or phase transitions (~2-5k tokens, done once per event).

Token savings: 50-70% reduction vs full reads (21-45k vs 60-150k for a typical 3-phase orchestration).

### Background Monitoring Subagent

For parallel phases, launch a background monitoring subagent that polls for state changes. See [Reference: Monitoring Subagent Templates](#reference-monitoring-subagent-templates) for the full parameterized prompt templates (parallel, sequential, staleness-only, and post-review variants).

**Key design decisions:**
- Always `run_in_background=True` for parallel phases
- Poll interval: 30 seconds (parallel), 60 seconds (sequential)
- Staleness threshold: 540 seconds (9 minutes)
- Relaunch after each event (subagent returns, conductor handles event, relaunches)
- Refreshes conductor heartbeat every cycle (prevents musician timeout on task-00)

### Conductor Heartbeat Management

The conductor must keep its own heartbeat fresh. Musicians check `task-00` heartbeat with a 540-second (9-minute) threshold — stale conductor heartbeat triggers timeout escalation in musician pause watchers.

Two mechanisms (belt and suspenders):
1. **Monitoring subagent** refreshes conductor heartbeat every poll cycle
2. **Conductor** updates heartbeat on every action (review, error handling, phase transition)

```sql
UPDATE orchestration_tasks SET last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

### Event Priority

When multiple events are pending, handle in priority order:
1. **Errors** — task in `error` state (blocking musician, needs fix)
2. **Reviews** — task in `needs_review` state (blocking musician, needs evaluation)
3. **Completions** — task reporting `complete` (non-blocking, informational)

Errors are blocking; completions are non-blocking.

### Conductor Monitoring Cycle

1. **Launch background watcher** — Invoke Task with `run_in_background=True`, prompt from monitoring template
2. **Return to user** — Report: "Monitoring started. Watching for state changes (needs_review, error, complete). I'll handle them when detected."
3. **Wait for watcher exit** — Conductor pauses, user can ask questions or provide context
4. **Watcher detects event** — Exits background task, conductor is notified
5. **Handle event** — Route to Review Workflow, Error Handling, or Completion (see sections below)
5.5. **CHECK TABLE FOR ADDITIONAL CHANGES** — Before relaunching watcher, query `orchestration_tasks` table:
   - Check for new state changes on any task (multiple tasks may have changed while conductor was handling step 5)
   - Read any new messages from `orchestration_messages` that arrived during step 5
   - If additional events found: handle them sequentially (loop back to step 5 for each)
   - This catches both watcher message failures and concurrent updates
6. **Relaunch watcher** — After all pending events processed, invoke Task with `run_in_background=True` again
6.5. **Process pending RAG work** — Check STATUS.md "Pending RAG Processing" section. If entries exist and no other events are pending, process them now. This catches RAG proposals deferred during busy review cycles. The background message-watcher remains active throughout — if a new event arrives during RAG processing, pause RAG work and handle the event first.
7. **Repeat** — Return to step 2

## Review Workflow

When an execution session sets state to `needs_review`:

### 1. Read Review Request Message

```sql
SELECT message, timestamp FROM orchestration_messages
WHERE task_id = 'task-XX' AND message_type = 'review_request'
ORDER BY timestamp DESC LIMIT 1;
```

**Message structure:** Context Usage (%), Self-Correction (YES/NO with details), Deviations (count + severity), Agents Remaining (count and %), Proposal (path to file), Summary (accomplishments), Files Modified (count), Tests (status and count).

### 2. Set Conductor State

```sql
UPDATE orchestration_tasks
SET state = 'reviewing', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

### 3. Context-Aware Reading Strategy

Skim message structure first (Context Usage, Self-Correction, Deviations fields). Deep-read proposal file only if smoothness >5 or self-correction flag is set. This preserves conductor context for strategic decisions.

### 4. Self-Correction Flag Handling

If `Self-Correction: YES` — context estimates are unreliable (~6x bloat during self-correction phases).

Task instructions include rough context usage estimates per step. Compare actual to estimated:

- **Actual ≈ estimated** → Tell musician: "Set self-correction flag to false — this was minor"
- **Actual > 2x estimated** → Warn user they may need an additional session
- **Actual > 40% AND not at final checkpoint** → Set `fix_proposed`, have musician estimate context to next checkpoint

To compare without reading the full instruction file, grep for estimate keywords in the instruction file.

### 5. Evaluate Using Smoothness Scale

| Score | Meaning | Action |
|-------|---------|--------|
| 0 | Perfect execution, no deviations | Approve |
| 1-2 | Minor clarifications, self-resolved | Approve |
| 3-4 | Some deviations, documented | Approve |
| 5 | Borderline, conductor judgment | Approve (usually) |
| 6-7 | Significant issues, conductor input needed | Request revision (`review_failed`) |
| 8-9 | Major blockers or failure | Reject with detailed feedback |

### 6. Review Loop Tracking

Track review cycles:
```sql
SELECT COUNT(*) FROM orchestration_messages
WHERE task_id = 'task-XX' AND message_type = 'review_request';
```

Cap at 5 cycles per checkpoint. At cycle 5, escalate to user with the entire review history.

### 7. Send Response

**Approve (smoothness 0-5):**
```sql
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'REVIEW APPROVED: [feedback]
     Proceed with remaining steps.',
    'approval');
```

**Reject (smoothness 6-7):**
```sql
UPDATE orchestration_tasks
SET state = 'review_failed', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'REVIEW FAILED (Smoothness: X/9):
     Issue: [what is wrong]
     Required: [specific changes needed]
     Retry: [instructions for re-submission]',
    'rejection');
```

**Reject (smoothness 8-9):**
Same SQL as 6-7, but with more detailed explanation and explicit required changes.

### 8. Return to Monitoring

Set conductor state back to `watching`:
```sql
UPDATE orchestration_tasks
SET state = 'watching', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

Relaunch monitoring subagent for remaining active tasks.

### 9. Update STATUS.md

Update only the relevant task section with review history, smoothness score, and any notes.

### 10. Eager RAG Processing (Completion Reviews Only)

After approving a task for completion, check `orchestration_tasks` for any other tasks in `needs_review` or `error` state. If none are pending, launch the RAG processing subagent immediately. If other reviews are pending, handle those first — RAG processing must never block review handling. Deferred RAG will be caught by the monitoring cycle fallback (step 6.5).

**After review completes:** Proceed to step 5.5 (Check Table for Additional Changes) in the Conductor Monitoring Cycle above.

### Score Aggregation

Track average smoothness across a phase:
- **0-3 average:** High quality execution — plan and instructions are working well
- **3-5 average:** Adequate — some friction but manageable
- **5+ average:** Systemic issue — plan quality, instruction clarity, or task scoping needs improvement

## Deviation Interpretation

Musicians track deviations from plan in `temp/task-{NN}-deviations` and report them in all review/completion/error messages. The conductor interprets these from a strategic perspective.

### Deviation Severity Definitions

| Severity | Criteria | Conductor Action |
|----------|----------|---------------------|
| **Low** | No timeline impact, minor approach change | Note in STATUS.md, no escalation |
| **Medium** | <1 hour impact, notable approach change | Count as friction signal. 2+ Medium deviations in one task → investigate plan quality |
| **High** | >1 hour impact, significant scope or architecture change | Immediate attention. May require plan revision or task restructuring |

### Escalation Triggers (Conductor Perspective)

The conductor escalates to the user when:
- **2+ Medium deviations** in a single task (pattern suggests instruction quality issue)
- **1+ High deviation** in any task (scope change that affects other tasks or plan goals)
- **Cross-task deviation pattern** — similar deviations appearing in 2+ parallel tasks (systemic issue with plan or instructions)
- **Deviation + self-correction combo** — a deviation that triggered self-correction is especially concerning (context cost compounds)

### Reading Deviations Without Consuming Context

The conductor can passively check musician deviations without database messaging:

1. **From review messages:** The `Deviations: N (severity — description)` field gives count and severity inline
2. **From temp/ files:** Read `temp/task-{NN}-deviations` directly (read-only, no database cost)
3. **From check-context-headroom.sh:** The script reports step progress which correlates with deviation risk

**Deviation-smoothness correlation:**
- Low deviations typically map to smoothness 1-3
- Medium deviations typically map to smoothness 3-5
- High deviations typically map to smoothness 5-7
- Self-correction + deviation typically maps to smoothness 6-8

### Self-Correction Flag

A binary signal from the musician: did it correct its own code during this session?

- **Critical impact:** When active, context usage estimates are off by **~6x**
- **Why:** The model is strong at self-correction but consumes immense context during the process (backtracking, re-reading, rewriting)
- **Reported in:** ALL messages (review request, completion, error, context warning)
- **Conductor response:** Plan for early handoff. If self-correction + high context (>50%) → proactively suggest scope reduction at next review

## Error Handling & Recovery

When an execution session sets state to `error`:

### 1. Check Error Type

```sql
SELECT last_error, retry_count FROM orchestration_tasks
WHERE task_id = 'task-XX';
```

If `last_error = 'context_exhaustion_warning'`, follow **Context Warning Protocol** below. Otherwise continue.

### 2. Read Error Report

```sql
SELECT message, timestamp FROM orchestration_messages
WHERE task_id = 'task-XX' AND message_type = 'error'
ORDER BY timestamp DESC LIMIT 1;
```

Read the error report file referenced in the message (e.g., `docs/implementation/reports/task-XX-error-retry-N.md`).

### 3. Analyze Error

Evaluate: error type, context, stack trace, retry count, suggested investigation.

### 4. Decision Tree

| Condition | Action |
|-----------|--------|
| Simple fix (typo, config) | Propose fix immediately. Set `fix_proposed`. |
| Complex (logic error) | Search RAG for similar patterns, then propose fix. |
| Uncertain | **Flag uncertainty for user review** before sending to musician. Include: "This fix is uncertain. Please verify." Give user option to investigate. |
| retry_count >= 5 | Musician exhausted retries (conductor error). Escalate to user: retry with new instructions, skip task, investigate root cause. |

### 5. Send Fix Proposal

```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'FIX PROPOSAL (Retry N/5):
     Root cause: [analysis]
     Fix: [specific instructions]
     Retry: [what to do after applying fix]',
    'fix_proposal');
```

### 6. Resume Monitoring

Relaunch monitoring subagent. The execution session will apply the fix, set state to `working`, and continue.

### Context Warning Protocol

When `last_error = 'context_exhaustion_warning'`, read the context warning message:

```sql
SELECT message, timestamp FROM orchestration_messages
WHERE task_id = 'task-XX' AND message_type = 'context_warning'
ORDER BY timestamp DESC LIMIT 1;
```

The musician reports remaining context and proposes a path forward. Evaluate using the context situation checklist:

1. Is self-correction flag active? (context estimates ~6x unreliable)
2. How many deviations and how severe?
3. How far to next checkpoint?
4. How many agents remain and at what cost?
5. Has this task had prior context warnings?
6. Is musician's proposal realistic given the context math?

**Respond with ONE of:**

| Response | State Set | Meaning |
|----------|-----------|---------|
| Proceed with musician's proposal | `review_approved` | Reach checkpoint OR run N more agents |
| Override musician's proposal | `fix_proposed` | "Only do X then prepare handoff" or "Adjust approach" |
| Stop now | `review_failed` | Prepare handoff immediately |

### Retry Limits

- **Execution error retries:** 0-5. At retry 5, musician writes HANDOFF and self-exits (`exited`). This is an conductor error — escalate to user.
- **Conductor subagent retries:** 3 maximum. After 3, escalate to user.
- **`retry_count` tracks error retries only**, not review cycles.

## Session Handoff

When an musician session exits and needs replacement:

### Four Handoff Types

| Type | Condition | Key Action |
|------|-----------|------------|
| **Clean** | HANDOFF present, context <80% | Standard: read HANDOFF, set `fix_proposed`, send handoff msg, inform user |
| **Dirty** | HANDOFF present, context >80% | Same as clean BUT include test verification instructions in handoff message (hallucination risk at high context) |
| **Crash** | No HANDOFF file | Send message with verification instructions for most recently completed/worked steps |
| **Retry Exhaustion** | 5th retry failure | Conductor error — escalate to user with options (retry with new instructions, skip task, investigate root cause) |

### Clean Handoff Procedure

1. Detect exit via monitoring (state = `exited` or stale heartbeat)
2. Read `temp/task-{NN}-HANDOFF` — verify it exists and is fresh (<60 minutes)
3. Read handoff content: completed steps, pending steps, deviations, self-correction status
4. Set task state:
```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';
```
5. Send handoff message with recovery instructions:
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'Session 1 exited cleanly. Resumption instructions:
     - [Remaining work from HANDOFF]
     - Re-run checkpoint verification to confirm work is intact
     - Then complete normally',
    'fix_proposal');
```
6. Inform user: "Task-XX musician exited. Please launch replacement: `claude "Read task instruction from orchestration_messages for task-XX and execute it."`"

### Dirty Handoff Procedure

Same as clean, BUT the handoff message includes:
- "CAUTION: Previous session exited at >80% context. Hallucination risk for late-session output."
- "Verify ALL tests produced in the final step before continuing."
- "Do not trust code assertions from the last 10% of the previous session's context."

### Crash Handoff Procedure

No HANDOFF document exists. The conductor must reconstruct state:
1. Read `temp/task-{NN}-status` for last known state
2. Read `orchestration_messages` for last communication from the session
3. Determine last completed step and last attempted step
4. Send handoff message with verification instructions for the most recently completed/worked steps

### Retry Exhaustion Procedure

Musician self-exited after 5th retry failure. This is NOT a continuation — the approach doesn't work.
1. Read all error reports for this task
2. Escalate to user with full context:
   - All 5 retry error messages
   - Options: retry with different instructions, skip task, investigate root cause, abort plan
3. Wait for user decision before proceeding

### Worked_by Succession Pattern

Track session succession via the `worked_by` field:
- First session: `musician-task-03`
- Second session: `musician-task-03-S2`
- Third session: `musician-task-03-S3`

Algorithm: parse current `worked_by`, check for `-SN` suffix. If no suffix → append `-S2`. If `-SN` → append `-S{N+1}`.

### User Notification Template

```
Task-XX musician exited ([clean/dirty/crash]).
[If clean: "Clean handoff prepared."]
[If dirty: "CAUTION: High-context exit. Tests need verification."]
[If crash: "No handoff document. Verification required."]

Please launch replacement session:
  claude "Read task instruction from orchestration_messages for task-XX and execute it."

Handoff message sent to database. New session will read instructions and continue.
```

## Emergency Broadcasts

When critical cross-cutting issues require all execution sessions to see a message (shared file conflict discovered, user-requested pause, schema change, etc.):

**One INSERT per affected task_id.** Each musician's background watcher monitors only its own `task_id` column — no body parsing needed.

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-03', 'task-00',
    'EMERGENCY: [description of cross-cutting issue]
     Action Required: [what musician should do]
     Urgency: [immediate / next-checkpoint]',
    'emergency');

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-04', 'task-00',
    'EMERGENCY: [same message]',
    'emergency');
```

The conductor has full discretion over when and why to broadcast. No enumerated trigger list — use judgment based on the cross-cutting nature of the issue.

**Musician response options** (musician decides based on urgency):
- Kill current subagent immediately (urgent: "stop all work")
- Wait for current subagent to finish (informational: "heads up about future step")
- Acknowledge and continue (advisory: instructions for a step not yet in progress)

## Context Management

### Conductor Context Thresholds

Monitor context usage via system messages after tool calls:

| Usage | Action |
|-------|--------|
| < 70% | Safe. Continue normal operations. |
| 70-80% | Complete current review or action. Write Recovery Instructions to STATUS.md. Set conductor state to `exit_requested`. |
| > 80% | Immediately write Recovery Instructions and exit. |

### Recovery Instructions

Written to STATUS.md Recovery section before exiting:

```markdown
## Recovery Instructions

**Context exit at:** [timestamp]
**Last known usage:** 145k/200k (72.5%)
**Last checkpoint:** Task 3, awaiting review response
**Active sessions:** task-03 (working), task-04 (working)
**Next action:** Check orchestration_tasks, read messages, resume monitoring
```

### Token Cost Estimates (Mental Tracking)

```
Initialization:
- Read implementation plan: 15-20k tokens
- Load docs/ READMEs (optimized): 5-8k tokens
- Initialize STATUS.md: 2-3k tokens
Total initialization: ~25-30k tokens

Per-task operations:
- Review task instruction: 2-4k tokens
- Read completion report: 4-6k tokens
- Review proposal (small): 3-5k tokens
- Review proposal (large): 8-12k tokens
- Comms-link queries: <1k tokens

Context estimates tend to be ~15k too low. Add buffer.
```

### Clean Exit Procedure

```
1. Complete in-flight work (finish review, send response)
2. Update STATUS.md Recovery section
3. Set orchestration_tasks state: exit_requested
4. Notify execution sessions if needed (emergency broadcast or individual messages)
5. Alert user with clear resume instructions
6. Exit cleanly (hook allows exit on exit_requested or complete)
```

## Danger Files Governance

Danger files are files potentially modified by 2+ parallel execution sessions. The governance flow ensures conflicts are identified early and mitigated.

### 3-Step Governance Flow

**Step 1: Implementation Plan (Human Decision)**

When suggesting tasks as parallel-safe, the plan author annotates danger files inline:
```markdown
Task 3: Extract Testing Docs
...
⚠️ Danger Files: docs/knowledge-base/testing/ (shared with Task 4)
```

**Step 2: Conductor Review (Context-Based Risk Analysis)**

When planning a phase, extract danger file annotations. Analyze:

| Factor | Assessment |
|--------|------------|
| Severity | Low / Medium / High |
| Timeline overlap | Do both tasks touch the file simultaneously or sequentially? |
| Modification type | Append-only? Same section? Different sections? |
| Mitigation available? | Ordering, batching, splitting possible? |

Decision: keep parallel (with mitigation) OR move to sequential.

**Step 3: Conductor Handoff (Data to Task Instruction Subagent)**

If danger files are present, include in the subagent prompt:
- "Task X and Task Y share file A"
- "Consider these mitigations: [ordering, append-only, batching]"
- The subagent writes coordination logic into task instructions (file locking order, sequential sub-steps for shared files)

### Mitigation Patterns

1. **Ordering Within Tasks** — Temporal separation: Task A touches shared file in step 1, Task B touches it in step 5 (by then Task A is done with it)
2. **Append-Only Modifications** — Both tasks only add content (no edits/deletes). Git auto-merge handles this cleanly.
3. **Conductor Batching** — Both tasks create proposals for the shared file. Conductor combines proposals during phase completion.
4. **Sequential Sub-Steps** — The shared-file work is extracted into a sequential sub-step within otherwise parallel tasks.

### When to Skip

Skip danger file analysis when:
- All tasks in the phase are already sequential
- Tasks operate on completely independent file sets (no overlap possible)
- Phase has only one task

## Proposal System

Execution sessions and their subagents create proposals **JIT (just-in-time)** whenever they discover patterns, anti-patterns, learnings, or anything worth preserving. The conductor handles deduplication and integration.

### Proposal Locations

```
docs/implementation/proposals/     — General proposals (specs, database, API changes)
                                     Flat directory, no subdirectories.
                                     Tagged: YYYY-MM-DD-brief-description.md
```

### Proposal Types

| Type | Content |
|------|---------|
| `PATTERN` | Reusable patterns discovered during implementation |
| `ANTI_PATTERN` | Approaches that fail or cause problems (document WHY) |
| `MEMORY` | Cross-session learnings, project conventions, debugging strategies |
| `CLAUDE_MD` | Rules or conventions that should be enforced project-wide |
| `RAG` | Knowledge-base content worth preserving for future sessions |
| `MEMORY_MCP` | Entities, relations, observations for the memory graph |
| `DOCUMENTATION` | Gaps in existing documentation |

### Checking for Proposals

**After each task completes:**
1. Check `docs/implementation/proposals/` for new proposals
2. Check `temp/` for misplaced proposals (warn: may be lost on reboot)
3. If proposals found in temp/, alert execution session to move them

**After each phase completes:**
1. Review ALL proposals from that phase
2. Integrate critical proposals (CLAUDE.md additions, memory snippets, pattern documentation)
3. Defer non-critical to end-of-plan
4. Track in STATUS.md Proposals Pending section

### Integration Rules

- **CLAUDE.md additions:** Apply immediately if they affect subsequent phases
- **Memory entities:** Create via memory MCP
- **RAG content:** Ingest via `tools/bulk-ingest-rag.sh`
- **Anti-patterns:** Document immediately (prevent repetition in subsequent tasks)
- **Documentation gaps:** Defer to completion unless blocking

## Completion

When all tasks in all phases reach `complete`:

### 10-Step Final Integration

**1. Verify All Tasks Complete**
```sql
SELECT task_id, state, completed_at, report_path
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```
All tasks must be `complete`. If any are `exited`, note in final report.

**2. Read Completion Reports**
Read all `report_path` files. Collect: deliverables lists, test status, deviations, smoothness scores.

**3. Verify Deliverables**
Check all expected files exist:
```bash
ls -la [expected file paths]
git status
git diff --stat
```

**4. Run Final Verification**
- All tests passing (if applicable)
- Git clean (no uncommitted changes beyond expected)
- RAG files ingested (`query_documents` test for newly created content)
- Directory structure matches design (no files outside established directories)
- No files created outside `docs/` or `temp/`
- No unresolved TODO comments in new code/docs

**5. Check for Proposals**
```bash
ls -la docs/implementation/proposals/
```
Also check `temp/` for any misplaced proposals.

**6. Integrate Proposals**
- Review all pending proposals (STATUS.md Proposals Pending list)
- Integrate CLAUDE.md additions
- Add memory snippets via memory MCP
- Document new patterns in RAG
- Defer non-critical to user decision

**7. Ask About Human-Readable Docs**
```
Implementation complete. The following reference documentation could be
generated from RAG knowledge-base:

- reference/[topic]-guide.md (from knowledge-base/[topic]/)
- ...

Generate consolidated guides now?
```

**8. Prepare PR**
- Review all commits on feature branch
- Verify commit messages are clear
- Check for sensitive data (credentials, tokens, API keys)
- Suggest PR title and description

**9. Report to User**
```
Implementation complete.

Deliverables: [count] files created/modified
Phases: [N] completed
Average smoothness: [X/9]
Total tasks: [N] completed, [N] exited (if any)
Proposals integrated: [N]

Recommendations:
- [Any follow-up work needed]
- [Any concerns or deferred items]
```

**10. Set Conductor Complete**
```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now')
WHERE task_id = 'task-00';
```

The stop hook sees `complete` and allows the conductor session to exit.

## Resumption

When starting a new session to resume interrupted orchestration:

### 1. Read Full STATUS.md

Read the **entire** STATUS.md file — not just the Recovery section. This costs ~2-5k tokens and is done once per resumption. Partial reads risk missing context scattered across task sections.

### 2. Query orchestration_tasks (Full Table)

```sql
SELECT task_id, state, session_id, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
ORDER BY task_id;
```

Triage by state:
- `complete` / `exited` → skip (note for report)
- `working` + recent heartbeat → still running, monitor
- `working` + stale heartbeat (>540s) → may need intervention (crashed session)
- `watching` → not yet claimed (no session has picked it up)
- `needs_review` → pending review, handle immediately
- `error` → needs fix proposal
- Missing rows → tasks not yet launched (phase not started)

### 3. Check Recent Messages

```sql
SELECT task_id, message, message_type, timestamp
FROM orchestration_messages
ORDER BY timestamp DESC
LIMIT 10;
```

### 4. Propose Next Steps to User

```
Analyzed current state:
- Tasks 3, 4 still working (heartbeats recent)
- Task 3 has pending review request
- Task 5 completed
- Task 6 exited (crash — no HANDOFF)

Proposed next steps:
1. Handle task-03 review
2. Initiate crash handoff for task-06
3. Resume monitoring for task-04
4. Proceed with Phase 3 planning (task-05 complete)

Proceed with these steps?
```

### 5. Wait for User Approval

### 6. Verify Hooks

Hooks are self-configuring. Check `hooks.json`, `session-start-hook.sh`, `stop-hook.sh` exist in `tools/implementation-hook/`. SessionStart hook will set `$CLAUDE_SESSION_ID` automatically for the new session.

### 7. Resume from Last Checkpoint

Execute approved next steps. Update STATUS.md with new session information. Relaunch monitoring subagent for active tasks.

## Message Format Standards

All messages use human-readable structured text. The `message_type` column enables filtering without body parsing.

### Review Request (musician → conductor)

**message_type:** `review_request`
```
REVIEW REQUEST (Smoothness: X/9):
  Checkpoint: N of M
  Context Usage: XX%
  Self-Correction: YES/NO (details if YES)
  Deviations: N (severity — description)
  Agents Remaining: N (~X% each, ~Y% total)
  Proposal: path/to/proposal.md
  Summary: what was accomplished
  Files Modified: N
  Tests: status (M total, N new)
```

### Context Warning (musician → conductor)

**message_type:** `context_warning`
**Task state:** `error` with `last_error = 'context_exhaustion_warning'`
```
CONTEXT WARNING: XX% usage
  Self-Correction: YES/NO
  Agents Remaining: N (~X% each, ~Y% total)
  Agents That Fit in 65% Budget: N
  Deviations: N (details)
  Proposal: what musician suggests doing
  Awaiting conductor instructions
```

### Error Report (musician → conductor)

**message_type:** `error`
**Task state:** `error`
```
ERROR (Retry N/5):
  Context Usage: XX%
  Self-Correction: YES/NO
  Error: description
  Report: docs/implementation/reports/task-{NN}-error-retry-{N}.md
  Awaiting conductor fix proposal
```

### Completion Report (musician → conductor)

**message_type:** `completion`
**Task state:** `needs_review` (completion requires final approval before `complete`)
```
TASK COMPLETE (Smoothness: X/9):
  Context Usage: XX%
  Self-Correction: YES/NO
  Deviations: N
  Report: docs/implementation/reports/task-{NN}-completion.md
  Summary: All deliverables created, tests passing
  Files Modified: N
  Tests: All passing (M tests, N new)
```

### Clean Exit / Handoff (musician → conductor)

**message_type:** `handoff`
**Task state:** `exited`
```
EXITED: Context exhaustion, clean handoff prepared.
  HANDOFF: temp/task-{NN}-HANDOFF
  Context Usage: XX%
  Last Completed Step: N
  Remaining Steps: list
```

### Emergency Broadcast (conductor → all musicians)

**message_type:** `emergency`
```
EMERGENCY: description of cross-cutting issue
  Action Required: what musician should do
  Urgency: immediate / next-checkpoint
```

### Approval (conductor → musician)

**message_type:** `approval`
```
REVIEW APPROVED: feedback
  (Optional) Set self-correction flag to false — this was minor.
  Proceed with remaining steps.
```

### Rejection (conductor → musician)

**message_type:** `rejection`
```
REVIEW FAILED (Smoothness: X/9):
  Issue: what's wrong
  Required: specific changes needed
  Retry: instructions for re-submission
```

### Fix Proposal (conductor → musician)

**message_type:** `fix_proposal`
```
FIX PROPOSAL (Retry N/5):
  Root cause: analysis
  Fix: specific instructions
  Retry: what to do after applying fix
```

### Task Instruction (conductor → musician)

**message_type:** `instruction`
```
TASK INSTRUCTION: task-{NN}
  Instruction file: docs/tasks/task-{NN}.md
  Phase: N
  Dependencies: none / list
  Danger files: none / list
```

### Claim Blocked (musician → conductor)

**message_type:** `claim_blocked`
```
CLAIM BLOCKED: Guard prevented claim on task-{NN}.
  Created fallback row to exit cleanly. Conductor intervention needed.
```

### Resumption Status (new musician → conductor)

**message_type:** `resumption`
```
RESUMPTION: musician-task-{NN}-S{N} taking over
  Previous session: {session_id from HANDOFF}
  HANDOFF: present / missing / stale
  Context Usage: XX% (fresh session)
  Deviations found: N (severity breakdown)
  Status/comms mismatches: N or none
  Pending conductor messages: N
  Self-correction in previous session: YES/NO
  Assessment: clean handoff / needs verification / needs conductor guidance
  Resuming from: step N, description
```

## File Path Conventions

### Persistent Files (survive reboots)

| File | Path | Purpose |
|------|------|---------|
| STATUS.md | `docs/implementation/STATUS.md` | Conductor runtime tracking |
| Implementation plan | `docs/plans/[plan-name].md` | Static input (locked) |
| Plan revisions | `docs/plans/[plan-name]-revisions.md` | External user changes |
| Task instructions | `docs/tasks/task-{NN}.md` | Self-contained instruction files |
| Completion report | `docs/implementation/reports/task-{NN}-completion.md` | Final report for completed task |
| Error report | `docs/implementation/reports/task-{NN}-error-retry-{N}.md` | Per-retry error analysis |
| Handoff report | `docs/implementation/reports/task-{NN}-handoff-s{N}.md` | Session handoff report |
| Proposals | `docs/implementation/proposals/{date}-{topic}.md` | Structured change requests |

### Ephemeral Files (cleared on reboot)

| File | Path | Purpose |
|------|------|---------|
| Status log | `temp/task-{NN}-status` | Append-only step progress with context % |
| Deviations log | `temp/task-{NN}-deviations` | Tracked deviations from plan |
| HANDOFF | `temp/task-{NN}-HANDOFF` | Clean exit handoff document |
| Hook iterations | `temp/hook-{session_id}.iterations` | Stop hook iteration counter |

### STATUS.md Design Principles

- **Section-based updates:** Touch ONE task section per checkpoint, not the whole file
- **Stable section names:** `### Task N: [Name]` format enables reliable partial reads
- **Recovery section:** Always current — written before any exit
- **Task Planning Notes:** Conductor's working memory (mutable, not a second source of truth)
- **Proposals Pending:** Tracks integration backlog
- **Decisions Log:** Documents conductor decisions with rationale

### Temporary File Lifecycle (Conductor Perspective)

The conductor reads but does not write temp/ files (except in edge cases like crash reconstruction). Understanding the lifecycle matters for monitoring and handoff.

**What musicians write:**
- `temp/task-{NN}-status` — Append-only log of every step/agent/deviation with `[ctx: XX%]`. The conductor's primary passive monitoring channel.
- `temp/task-{NN}-deviations` — Structured deviation records with severity levels. Read during reviews to cross-check reported deviation counts.
- `temp/task-{NN}-HANDOFF` — Created only on clean exit. Primary healthiness indicator for session replacement.

**What the conductor reads and when:**
| File | When Read | Why |
|------|-----------|-----|
| `temp/task-{NN}-status` | Passive monitoring, crash reconstruction | Check step progress and context trajectory without database messaging |
| `temp/task-{NN}-deviations` | During review evaluation | Verify reported deviation count matches file records |
| `temp/task-{NN}-HANDOFF` | Session handoff | Determine handoff type (clean if present, crash if absent) and gather successor instructions |
| `temp/hook-{session_id}.iterations` | Never directly | Used by stop hook internally; conductor checks hook health via database state |

**Lifecycle across sessions:**
- Files are tagged with `task_id`, not `session_id` — multiple sessions working on the same task (original + resumption) all write to the same files
- A resuming session (S2) appends to the original session's (S1) status file, building a continuous history
- HANDOFF files are overwritten by each session's clean exit — only the most recent matters
- All temp/ files are lost on reboot (symlink to `/tmp/remindly`). Persistent state lives in the database and docs/implementation/

**When temp/ files disagree with database:**
- Database is authoritative for task state and ownership
- temp/ files are supplementary context — use to reconstruct timeline but never override database state
- If temp/status shows work beyond what the database reflects, the musician may have crashed between step completion and database update

## Hook Integration

### SessionStart Hook

**File:** `tools/implementation-hook/session-start-hook.sh`
**Fires:** Automatically when any Claude session starts
**Action:** Extracts `session_id` from hook input JSON, injects `CLAUDE_SESSION_ID={session_id}` into the system prompt via `additionalContext`

The session ID is a **system prompt value**, not a bash environment variable. Claude reads it from the system prompt and uses it in database operations.

### Stop Hook

**File:** Referenced via `tools/implementation-hook/hooks.json`
**Fires:** When Claude attempts to exit a session
**Action:**
1. Extract `session_id` from hook input JSON
2. Query `orchestration_tasks` for row matching this session_id
3. Determine preset: `task-00` → orchestration preset, else → execution preset
4. Check if task state matches preset's exit criteria
5. If exit criteria met: allow exit
6. If not: inject fallback prompt, increment iteration counter
7. If iterations exceed max: force exit

### Presets

**Orchestration preset (task-00):**
- Exit criteria: `exit_requested` or `complete`
- Max iterations: 1000

**Execution preset (all other tasks):**
- Exit criteria: `complete` or `exited`
- Max iterations: 500

### No Manual Setup Required

Hooks are self-configuring via `hooks.json`. No `setup.sh` script needed. The conductor verifies hook files exist during initialization (Step 7) but does not need to install or configure them.

## Key Principles

1. **Context headroom is valuable** — Delegate aggressively. Use conductor context for strategic decisions, cross-task coordination, quality assurance, and error triage. Everything else goes to subagents or external sessions.

2. **External sessions are not subagents** — This is the most common confusion. External sessions are full Claude Code sessions in separate terminals with their own 200k context. Subagents share the parent's context and are ephemeral. Confusing these breaks the orchestration model.

3. **The conductor does no implementation** — No coding, no testing, no file creation (beyond STATUS.md and instruction files). The conductor coordinates. Execution sessions do the work.

4. **Implementation plan is locked** — Frozen at execution start. Conductor deviations go to STATUS.md Task Planning Notes. External changes go to `{plan-name}-revisions.md`. Never modify the original plan.

5. **Database is the source of truth for state** — Not STATUS.md, not temp/ files. The database is authoritative for task states, heartbeats, and session ownership. STATUS.md is for narrative context and recovery.

6. **Heartbeat on every state transition** — Every SQL UPDATE that changes state MUST include `last_heartbeat = datetime('now')`. Omitting this is a bug that breaks staleness detection.

7. **Terminal state is the last write** — `complete` and `exited` must be the absolute last database write for any session. Nothing should happen between setting the terminal state and the session ending.

8. **Errors before reviews before completions** — When multiple events are pending, handle in priority order. Errors are blocking; completions are non-blocking.

9. **Escalate uncertainty to user** — When the conductor is uncertain about a fix, an approach, or a decision, involve the user. The cost of asking is low; the cost of a wrong autonomous decision is high.

10. **Self-correction flag means context estimates are unreliable** — When an musician reports `Self-Correction: YES`, its remaining-agent estimates may be off by ~6x. Plan for early handoff.

11. **Propose everything** — Execution sessions create proposals for all patterns, anti-patterns, and learnings. The conductor integrates. Never skip proposal review — anti-patterns are as valuable as patterns.

12. **Document decisions** — Log all strategic decisions to STATUS.md Project Decisions Log with rationale. Propose relevant decisions for memory graph and RAG.

---

## Reference: State Machine

### All States (11)

**Conductor-only states (task-00):**

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `watching` | Conductor | Monitoring execution tasks | No |
| `reviewing` | Conductor | Actively reviewing a submission | No |
| `exit_requested` | Conductor | Needs to exit (context full, user consultation) | Yes (hook allows exit) |
| `complete` | Conductor | All tasks done | Yes (hook allows exit) |

**Execution states (task-01+):**

| State | Set By | Meaning | Terminal? |
|-------|--------|---------|-----------|
| `watching` | Conductor | Task created, not yet claimed | No |
| `working` | Musician | Actively executing task steps | No |
| `needs_review` | Musician | Review submitted, awaiting conductor | No |
| `review_approved` | Conductor | Conductor approved, execution resumes | No |
| `review_failed` | Conductor | Conductor rejected, execution revises | No |
| `error` | Musician | Hit an error, awaiting conductor fix | No |
| `fix_proposed` | Conductor | Conductor sent fix, ready for claim | No |
| `complete` | Musician | Task finished successfully | Yes (hook allows exit) |
| `exited` | Musician OR Conductor | Task terminated without completion | Yes (hook allows exit) |

### State Ownership Summary

**Conductor sets:** `watching`, `reviewing`, `exit_requested`, `complete`, `review_approved`, `review_failed`, `fix_proposed`, `exited` (staleness detection only)

**Musician sets:** `working`, `needs_review`, `error`, `complete`, `exited` (5th retry or context exit)

### State Transition Flows

```
Execution happy path:
  watching → working → needs_review → [conductor: review_approved]
  → working → ... → complete

Execution review rejection:
  working → needs_review → [conductor: review_failed]
  → working → needs_review → [conductor: review_approved] → ...

Execution error path:
  working → error → [conductor: fix_proposed] → working → ...

Execution terminal (retry exhaustion):
  working → error → [conductor: fix_proposed] → working
  → error → ... (×5) → exited

Conductor happy path:
  watching → reviewing → watching → ... → complete

Conductor context exit:
  watching → exit_requested
```

### `exited` State Details

**When musician sets it:**
- 5th error retry failure (retry_count reaches 5, self-terminates)
- Context exhaustion with clean handoff
- Double conductor timeout (unrecoverable)

**When conductor sets it:**
- Staleness/heartbeat detection (session disappeared, no heartbeat >540 seconds)
- Explicitly abandoning an unrecoverable task

### Guard Clause (Atomic Claim)

Only **3 states are claimable** by a new musician session: `watching`, `fix_proposed`, `exit_requested`.

```sql
UPDATE orchestration_tasks
SET state = 'working',
    session_id = '$CLAUDE_SESSION_ID',
    worked_by = 'musician-task-{NN}',
    started_at = datetime('now'),
    last_heartbeat = datetime('now'),
    retry_count = 0
WHERE task_id = 'task-{NN}'
  AND state IN ('watching', 'fix_proposed', 'exit_requested');
```

Verify `rows_affected = 1`. If 0, the guard blocked — see Fallback Row Pattern.

**Why only 3 states?** Other states (`needs_review`, `review_approved`, `review_failed`, `error`) represent active protocol steps. If a session dies in those states, staleness detection moves the task to `fix_proposed`, which is then claimable. This prevents race conditions.

### Fallback Row Pattern

When the guard blocks a claim, the session must exit cleanly. The stop hook needs an `exited` state for this session:

```sql
-- Always succeeds (no guard — unique PK)
INSERT INTO orchestration_tasks (task_id, state, session_id, last_heartbeat)
VALUES ('fallback-$CLAUDE_SESSION_ID', 'exited', '$CLAUDE_SESSION_ID', datetime('now'));

-- Notify conductor
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-{NN}', '$CLAUDE_SESSION_ID',
    'CLAIM BLOCKED: Guard prevented claim on task-{NN}. Created fallback row to exit cleanly.',
    'claim_blocked');
```

The monitoring subagent detects fallback rows and triages:
- If original task has newer heartbeat than fallback → task was worked since collision → DELETE fallback
- If original task heartbeat <= fallback → task NOT worked since collision → report to user

### Staleness Detection

```sql
SELECT task_id, state,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE state IN ('working', 'review_approved', 'review_failed', 'fix_proposed')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
```

When stale:
1. Session is likely dead (watcher died with it, heartbeat stopped refreshing)
2. Conductor sets state to `fix_proposed` (preferred) or `exited` (if unrecoverable)
3. Informs user to launch replacement session

**Heartbeat staleness is the only case where the conductor sets `exited` on an execution task.**

---

## Reference: Database Queries

### Database Location

`/home/kyle/claude/remindly/comms.db` — accessed exclusively via comms-link MCP.

### Schema DDL

See [Bootstrap & Initialization — Step 6](#6-initialize-database) for full CREATE TABLE statements with CHECK constraints, indexes, and conductor row insertion.

### Column Reference: orchestration_tasks

| Column | Type | Purpose |
|--------|------|---------|
| `task_id` | TEXT PK | `task-00` (conductor), `task-01`..`task-NN` (musicians), `fallback-{session_id}` (guard block exits) |
| `state` | TEXT | Current state in the state machine (11 valid values) |
| `instruction_path` | TEXT | Path to task instruction file |
| `session_id` | TEXT | Actual Claude Code session ID (set by SessionStart hook) |
| `worked_by` | TEXT | Worker identifier with succession: `musician-task-03`, `musician-task-03-S2` |
| `started_at` | TEXT | ISO datetime when task was first claimed |
| `completed_at` | TEXT | ISO datetime when task reached terminal state |
| `report_path` | TEXT | Path to completion/error report file |
| `retry_count` | INTEGER | Error retry count (0-5). At 5, musician self-exits. |
| `last_heartbeat` | TEXT | Updated on every state transition and by watcher refresh |
| `last_error` | TEXT | Discriminates error subtypes (`context_exhaustion_warning`, `conductor_timeout`) |

### Column Reference: orchestration_messages

| Column | Type | Purpose |
|--------|------|---------|
| `id` | INTEGER PK | Auto-incrementing message ID (used for deduplication) |
| `task_id` | TEXT | Which task this message concerns |
| `from_session` | TEXT | `$CLAUDE_SESSION_ID` of sender, or `task-00` for conductor |
| `message` | TEXT | Human-readable message body with structured sections |
| `message_type` | TEXT | Enum for cheap filtering (12 valid values) |
| `timestamp` | TEXT | ISO datetime, defaults to `CURRENT_TIMESTAMP` |

### Common SQL Patterns

**1. Insert Task Row (phase launch):**
```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-XX', 'watching', 'docs/tasks/task-XX.md', datetime('now'));
```

**2. Insert Instruction Message:**
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'TASK INSTRUCTION: docs/tasks/task-XX.md
     Type: parallel
     Phase: 2
     Dependencies: none',
    'instruction');
```

**3. Monitor All Tasks:**
```sql
SELECT task_id, state, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
ORDER BY task_id;
```

**4. Check for Pending Reviews:**
```sql
SELECT task_id, message, timestamp
FROM orchestration_messages
WHERE message_type = 'review_request'
ORDER BY timestamp DESC
LIMIT 5;
```

**5. Approve Review:**
```sql
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'REVIEW APPROVED: [feedback]',
    'approval');
```

**6. Reject Review:**
```sql
UPDATE orchestration_tasks
SET state = 'review_failed', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'REVIEW FAILED (Smoothness: X/9): [feedback]',
    'rejection');
```

**7. Report Error Fix:**
```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'FIX PROPOSAL: [fix details]',
    'fix_proposal');
```

**8. Staleness Detection:**
```sql
SELECT task_id, state,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE state IN ('working', 'review_approved', 'review_failed', 'fix_proposed')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
```

**9. Emergency Broadcast (one per task):**
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00', 'EMERGENCY: [message]', 'emergency');
```

**10. Refresh Conductor Heartbeat:**
```sql
UPDATE orchestration_tasks SET last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

**11. Session Handoff (set fix_proposed for replacement):**
```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'Session exited. Resumption instructions: [details]',
    'fix_proposal');
```

**12. Detect Fallback Rows:**
```sql
SELECT task_id, session_id, last_heartbeat
FROM orchestration_tasks
WHERE task_id LIKE 'fallback-%';
```

**13. Cleanup Fallback Row (after triage):**
```sql
DELETE FROM orchestration_tasks
WHERE task_id = 'fallback-[session_id]';
```

**14. Mark Conductor Complete:**
```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now')
WHERE task_id = 'task-00';
```

**15. Request Exit (conductor context full):**
```sql
UPDATE orchestration_tasks
SET state = 'exit_requested', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

**16. Count Review Cycles (review loop cap):**
```sql
SELECT COUNT(*) FROM orchestration_messages
WHERE task_id = 'task-XX' AND message_type = 'review_request';
```

**17. Detect Context Warning:**
```sql
SELECT task_id, last_error, retry_count
FROM orchestration_tasks
WHERE state = 'error' AND last_error = 'context_exhaustion_warning';
```

**18. Check Conductor Health (musician-side):**
```sql
SELECT state, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE task_id = 'task-00';
```

**19. Dynamic Row Management (no rebuild between phases):**
Tables persist across phases. Insert new rows as phases launch:
```
Plan starts:     orchestration_tasks has [task-00]
Phase 1 launches: + [task-01]
Phase 1 completes: task-01 state='complete'
Phase 2 launches: + [task-03, task-04, task-05, task-06]
Phase 2 completes: all state='complete'
Phase 3 launches: + [task-07, task-08, ...]
```

### Database Access Restrictions

**Conductor (task-00):**
- READ any row in `orchestration_tasks` (monitoring)
- WRITE `task-00` state/heartbeat and task-NN states it owns (review responses, staleness cleanup)
- READ/WRITE any row in `orchestration_messages`

**Musician (task-NN):**
- READ/WRITE only its own `task-NN` row in `orchestration_tasks`
- READ `task-00` row (conductor heartbeat check)
- READ sibling task states (parallel awareness)
- WRITE to `orchestration_messages` only with own task_id
- READ from `orchestration_messages` only where own task_id

---

## Reference: Review Checklists

### Subagent Self-Review Checklist (FACTS Focus)

The task instruction subagent has fresh document context — it validates concrete details:

- [ ] All required sections present?
- [ ] SQL queries syntactically correct?
- [ ] File paths match implementation plan?
- [ ] Hook configuration matches pattern (sequential vs parallel)?
- [ ] Dependencies accurately listed?
- [ ] Verification steps included?
- [ ] State transitions correctly specified?
- [ ] Completion report format included?

### Conductor Review Checklist (STRATEGY Focus)

The conductor knows overall goals — it validates alignment:

- [ ] Instructions align with overall plan goals?
- [ ] Appropriate pattern chosen (sequential vs parallel)?
- [ ] Task dependencies make sense in project context?
- [ ] Review checkpoints at logical points?
- [ ] Context budget reasonable for execution session?
- [ ] Verification adequate for deliverables?
- [ ] Integration with other tasks considered?

### Execution Task Completion Review

**Context Situation Checklist (6 factors):**
1. Is self-correction flag active? (estimates ~6x unreliable)
2. What is current context usage vs task estimate?
3. How many deviations and how severe?
4. How far to next checkpoint?
5. How many agents remain and at what cost?
6. Has this task had prior context warnings?

**Smoothness Scale (0-9):**

| Score | Meaning | Conductor Action |
|-------|---------|---------------------|
| 0 | Perfect execution, no deviations | Approve |
| 1-2 | Minor clarifications, self-resolved | Approve |
| 3-4 | Some deviations, documented | Approve |
| 5 | Borderline, conductor judgment | Approve (usually) |
| 6-7 | Significant issues, conductor input needed | Request revision (`review_failed`) |
| 8-9 | Major blockers or failure | Reject with detailed feedback |

**Score Aggregation:**
Track average across a phase:
- 0-3 average → High quality execution (plan and instructions working well)
- 3-5 average → Adequate (some friction, manageable)
- 5+ average → Systemic issue (plan quality, instruction clarity, or task scoping needs improvement)

---

## Reference: Monitoring Subagent Templates

### Parallel Phase Monitoring (Primary)

```
Task("Monitor parallel execution", prompt="""
You are a background monitoring subagent for the conductor.

TASKS TO WATCH: [{task_list}]

POLL CYCLE (repeat until event detected or terminated):
1. Query all task states:
   SELECT task_id, state, last_heartbeat,
          (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
   FROM orchestration_tasks
   WHERE task_id IN ({task_list_sql});

2. Check for events:
   - Any state = 'needs_review' → REPORT
   - Any state = 'error' → REPORT
   - Any state = 'complete' → REPORT
   - Any state = 'exited' → REPORT
   - Any seconds_stale > 540 in non-terminal state → REPORT as STALE

3. Refresh conductor heartbeat:
   UPDATE orchestration_tasks SET last_heartbeat = datetime('now')
   WHERE task_id = 'task-00';

4. Check for fallback rows:
   SELECT task_id, last_heartbeat FROM orchestration_tasks
   WHERE task_id LIKE 'fallback-%';
   If found: include in report.

5. Wait 30 seconds, repeat from step 1.

On event: Return immediately with task_id, new state, and most recent message:
   SELECT message, timestamp FROM orchestration_messages
   WHERE task_id = '[event_task_id]'
   ORDER BY timestamp DESC LIMIT 1;

Use comms-link query for SELECTs, comms-link execute for UPDATEs.
""", subagent_type="general-purpose", run_in_background=True)
```

### Sequential Task Monitoring

```
Task("Monitor sequential task", prompt="""
Monitor task-XX for completion.
Poll every 60 seconds:
   SELECT state, last_heartbeat FROM orchestration_tasks WHERE task_id = 'task-XX';
Report when state changes from 'working'.
Refresh conductor heartbeat each cycle:
   UPDATE orchestration_tasks SET last_heartbeat = datetime('now') WHERE task_id = 'task-00';
Use comms-link query/execute.
""", subagent_type="general-purpose", run_in_background=True)
```

### Staleness-Only Monitoring

For phases where reviews are unlikely (e.g., simple tasks):

```
Task("Staleness monitor", prompt="""
Check for stale sessions every 60 seconds:
   SELECT task_id, state, (julianday('now') - julianday(last_heartbeat)) * 86400 as stale
   FROM orchestration_tasks WHERE state NOT IN ('complete', 'exited', 'watching');
Report if any stale > 540. Refresh task-00 heartbeat each cycle.
Stop after 10 consecutive healthy checks.
""", subagent_type="general-purpose", run_in_background=True)
```

### Post-Review Re-Monitoring

After handling a review or error, relaunch for remaining active tasks:

```
Task("Continue monitoring", prompt="""
Resume monitoring after review handled.
REMAINING ACTIVE TASKS: [{remaining_task_list}]
[Same poll cycle as primary monitoring template]
""", subagent_type="general-purpose", run_in_background=True)
```

---

## Reference: Subagent Prompt Template

Two-step pattern for launching the task instruction creation subagent:

### Step 1: Prepare Overrides & Learnings

Before launching the subagent, the conductor reviews the implementation plan for the current phase and compiles any corrections, scope adjustments, danger file decisions, or lessons from prior phases. These are passed directly in the subagent prompt as the `## Overrides & Learnings` section.

If there are no overrides, write "None — follow the implementation plan as written."

### Step 2: Launch Subagent

```
Task("Create task instructions for Phase {PHASE_NUMBER}", prompt="""

Load the copyist skill, then create task instruction files for this phase.

## Phase Info
**Phase:** {PHASE_NUMBER} — {PHASE_NAME}
**Task type:** {TASK_TYPE} (sequential/parallel)
**Tasks to create:** {TASK_LIST}
**Implementation plan:** {PLAN_PATH}
**Output directory:** docs/tasks/

## Overrides & Learnings
{OVERRIDES_AND_LEARNINGS}

## Instructions
1. Read the implementation plan at `{PLAN_PATH}`
2. Invoke the `copyist` skill
3. Read the appropriate template (sequential or parallel) — following templates is MANDATORY
4. Extract the tasks listed above from the plan
5. Apply any Overrides & Learnings — these take precedence over the plan
6. Write instruction files to `docs/tasks/`
7. Validate each file and fix errors until all pass

## Quality Gate

Before returning, verify every instruction file:
- Passes validation script (0 errors)
- Contains no "see plan section X" references
- Has complete SQL with correct table names and heartbeats
- Has explicit file paths for all deliverables
- Sequential: has Initialization, Completion, Error Recovery sections
- Parallel: has Hook setup, Background subagent, Review checkpoint, Error Recovery sections

### Instruction Validation Checklist (ENH-L)

Verify each instruction file before returning:
1. **Plan coverage:** Does instruction cover all objectives from implementation plan for this task? No missing steps.
2. **Step clarity:** Each step is unambiguous — execution session can proceed without judgment calls.
3. **Safety flags:** Dangerous operations (force-push, destructive db changes) are explicitly marked with ⚠️ WARNING.
4. **Template compliance:** All sections from the selected template are present. Inapplicable sections marked N/A with reason, not omitted.
5. **Checkpoint quality:** Checkpoints are after significant deliverables, not arbitrary steps. One per 3-5 substantive steps.

Report the validation results for each file when done.

### Checkpoint Design Guidance (ENH-M)

When instruction includes checkpoints (parallel tasks or mid-task reviews):
1. **Frequency:** Place one checkpoint per 3-5 major steps. Too many: overhead. Too few: musician loses track.
2. **Granularity:** Each checkpoint tests a cohesive unit (e.g., "Extract & verify API schema section", not "Extract headers and endpoints separately").
3. **Verification strategy at each:** What test or verification confirms this checkpoint is complete? Include specific grep/ls/test commands, not vague descriptions.

""", subagent_type="general-purpose", run_in_background=False)
```

### Conductor Usage

#### Before Launch — Prepare Overrides & Learnings

The conductor reviews the implementation plan for the current phase and compiles overrides:

1. **Review STATUS.md Task Planning Notes** — any corrections or scope adjustments from prior phases
2. **Check danger file decisions** — resolved conflicts, mitigation strategies
3. **Note lessons learned** — patterns from completed phases that should inform this phase's instructions

Compile these into the `## Overrides & Learnings` section of the prompt. If none, write "None — follow the implementation plan as written."

Then launch the subagent with the template above, filling in all placeholders.

#### Filling the Template

| Placeholder | Source |
|---|---|
| `{PHASE_NUMBER}` | Implementation plan phase structure |
| `{PHASE_NAME}` | Implementation plan phase name |
| `{TASK_TYPE}` | `sequential` or `parallel` — from plan analysis |
| `{TASK_LIST}` | Comma-separated task IDs for this phase |
| `{PLAN_PATH}` | Path to the implementation plan file |
| `{OVERRIDES_AND_LEARNINGS}` | Conductor-compiled corrections, scope adjustments, danger file decisions, lessons from prior phases. "None — follow the implementation plan as written." if empty |
| Output directory | Hardcoded to `docs/tasks/` unless user specifies otherwise |

#### After Return — Conductor Review

The conductor reviews returned files from in-memory context (not re-reading the plan):

1. Check validation results reported by subagent
2. Review against Task Planning Notes from STATUS.md
3. Spot-check: instructions align with plan goals, appropriate task type, reasonable checkpoints
4. If issues found: prompt subagent with specific correction ("Missing X, check plan section Y")
5. Iteration limits: 2 loops max for same issue, 5 total reviews per instruction

---

## Reference: Subagent Failure Handling

### Retry Policy

3 retries maximum. After 3 failures, escalate to user.

### Failure Categories

| Category | Examples | Action |
|----------|----------|--------|
| **Transient** | Timeout, connection reset, partial output | Retry immediately with same prompt |
| **Configuration** | Wrong skill name, missing file, invalid tool call | Fix configuration, then retry |
| **Logic** | Wrong output format, validation fails, incomplete results | Add correction context to prompt, retry |
| **Systemic** | Fundamentally wrong despite correct prompt | Escalate immediately (skip retries) |

### Retry Decision Flowchart

```
Subagent fails
  │
  ├─ Attempt < 3?
  │   ├─ Yes → Categorize failure
  │   │   ├─ Transient → Retry with same prompt
  │   │   ├─ Configuration → Fix config, retry
  │   │   ├─ Logic → Add correction context, retry
  │   │   └─ Systemic → Escalate immediately
  │   └─ No → Escalate to user
  │
  └─ Escalate
      └─ Present to user:
         - Error summary (all attempts)
         - Failure category
         - Options: retry manually, skip phase, abort, modify inputs
         - Recommendation
```

### Escalation Message Format

```
Task instruction subagent failed [N] times creating Phase [N] instructions.

Failure details:
- Attempt 1: [error message]
- Attempt 2: [error message]
- Attempt 3: [error message]

Failure category: [transient/configuration/logic/systemic]

Options:
1. Retry manually with adjusted prompt
2. Skip this phase and proceed
3. Abort implementation
4. Modify inputs and try again

Recommendation: [conductor's suggestion]
```

### Common Configuration Errors

- Wrong skill name in subagent prompt
- Wrong file path (plan moved or renamed)
- Missing `subagent_type` parameter
- Plan file too large for context budget

### Fallback for Monitoring Subagent Failure

If the monitoring subagent fails 3 times, fall back to manual monitoring via `scripts/validate-coordination.sh` (run periodically by the conductor).

---

## Reference: STATUS.md Template

```markdown
# Implementation Status: [Project/Plan Name]

**Implementation Plan:** [path to implementation plan]
**Started:** [YYYY-MM-DD HH:MM]
**Conductor Session:** [session-id]

---

## Coordination Database

**Database Path:** /home/kyle/claude/remindly/comms.db
**Tables (static names, drop/recreate at implementation start):**
- `orchestration_tasks` - Combined task tracking: state machine + lifecycle metadata
- `orchestration_messages` - Message passing between conductor and execution sessions

---

## Recovery Instructions

*If this session exits and needs to resume, follow these steps:*

**1. Check all task states:**
SELECT task_id, state, session_id, last_heartbeat
FROM orchestration_tasks ORDER BY task_id;

**2. Find last completed work:**
- Read each task section below
- Last checked checkpoint shows progress

**3. Check for pending reviews:**
SELECT task_id, message, timestamp FROM orchestration_messages
WHERE message_type IN ('review_request', 'error')
ORDER BY timestamp DESC LIMIT 5;

**4. Resume orchestration:**
- If active sessions exist, continue monitoring
- If no active sessions, check which tasks are incomplete and launch next batch

---

## Git Branch

**Branch:** feature/[branch-name]
**Base Branch:** main
**Branch Created:** [timestamp]

---

## Task Status

### Task 0: Conductor
**Status:** Running
**Last Updated:** [YYYY-MM-DD HH:MM]
**Context Usage:** [tracked when conductor checks]

---

### Task 1: [Task Name]
**Status:** Pending | In Progress | Complete | Blocked
**Dependencies:** [list] | **Parallel Safe:** Yes/No
**Session:** [session-id if started] | **Last Updated:** [YYYY-MM-DD HH:MM]

**Progress:**
- [ ] Instructions created (path: [file])
- [ ] Checkpoint 1: [description]
- [ ] Checkpoint 2: [description]
- [ ] Final review complete
- [ ] Report filed (path: [file])

**Deviations:** [If any, or "None"]

---

[Repeat for each task...]

---

## Task Planning Notes

*Reference for conductor review - not parsed during checkpoint updates*

### Task N: [Task Name]
**Goals from plan:**
- [extracted goals]

**Expected deliverables:**
- [expected outputs]

**Critical checkpoints:**
- [key verification points]

---

## Proposals Pending

*Proposals awaiting integration*

- [ ] [proposal path] — [type] — [brief description]

---

## Project Decisions Log

*Conductor decisions documented for transparency*

### [YYYY-MM-DD HH:MM] - [Decision Title]
**Decision:** [what was decided]
**Rationale:** [why]
**Impact:** [how it affects the plan]
```

---

## Reference: Resumption Decision Tree

When the conductor resumes after a context exit or crash, it follows this decision tree to determine what to do.

### Conductor Resumption Flow

```
New conductor session starts
  │
  ├─ Read full STATUS.md (~2-5k tokens, once)
  │   └─ Recovery Instructions: last context %, active sessions, next action
  │
  ├─ Query orchestration_tasks (full table)
  │   │
  │   ├─ Triage by state:
  │   │   ├─ complete / exited → Skip (note for report)
  │   │   ├─ working + fresh heartbeat → Monitor (session still alive)
  │   │   ├─ working + stale heartbeat (>540s) → Investigate (likely crash)
  │   │   ├─ watching → Not yet claimed (phase not started or session never launched)
  │   │   ├─ needs_review → Handle immediately (review pending)
  │   │   ├─ error → Handle immediately (fix proposal needed)
  │   │   ├─ review_approved / review_failed → Session should be working
  │   │   │   └─ If stale → session crashed mid-response, set fix_proposed
  │   │   └─ fix_proposed → Session should be working
  │   │       └─ If stale → fix not claimed, inform user to relaunch
  │   │
  │   └─ Check task-00 state: should be exit_requested or watching
  │       └─ Update to watching with new session_id
  │
  ├─ Read last 10 messages from orchestration_messages
  │   └─ Check for: unhandled reviews, unanswered errors, recent completions
  │
  ├─ Check for fallback rows
  │   └─ If found: triage (original task has newer heartbeat? → DELETE fallback)
  │
  └─ Present triage to user
      │
      ├─ Priority order:
      │   1. Errors (blocking)
      │   2. Reviews (blocking)
      │   3. Stale sessions (need intervention)
      │   4. Completions (informational)
      │   5. Phase transitions (next steps)
      │
      └─ Wait for user approval before acting
```

### Resumption vs Fresh Start

| Signal | Action |
|--------|--------|
| orchestration_tasks exists with rows | Resumption — follow decision tree above |
| orchestration_tasks empty or missing | Fresh start — full initialization sequence |
| STATUS.md exists | Resumption context available — read it |
| STATUS.md missing | Limited context — rely on database state and messages |

### Common Resumption Scenarios

**Scenario 1: Clean mid-phase resume**
- Previous conductor exited at 72%
- All execution sessions still working, heartbeats fresh
- Action: Update task-00, relaunch monitoring, wait for events

**Scenario 2: Stale execution session**
- One task has stale heartbeat (>540s), still in `working` state
- Action: Check temp/task-{NN}-HANDOFF. If present → clean handoff. If absent → crash handoff.

**Scenario 3: Pending review from before exit**
- Task in `needs_review` state, review message waiting
- Action: Handle review immediately (highest priority after errors)

**Scenario 4: Phase boundary**
- All tasks in current phase are complete/exited
- Action: Verify phase deliverables, check proposals, begin next phase planning

---

## Example: Conductor Initialization

This walkthrough shows a complete initialization sequence for a documentation reorganization plan with 3 phases and 10 tasks.

### Step 1: Read Implementation Plan

The conductor reads `docs/plans/2026-02-04-docs-reorganization.md` and identifies:
- Phase 1 (Foundation): Task 1 only (sequential, must complete first)
- Phase 2 (Extraction): Tasks 3, 4, 5, 6 (parallel-safe, independent content extraction)
- Phase 3 (Migration): Tasks 7, 8, 9, 10 (mixed — some parallel, some sequential)

Danger files noted: `docs/knowledge-base/testing/` shared between Tasks 3 and 4.

### Step 2: Git Branch

```bash
git branch --show-current  # Returns: main
```

Conductor asks user to create feature branch. User confirms.

```bash
git checkout -b feature/docs-reorganization
```

### Step 3: Verify temp/

```bash
ls -la /home/kyle/claude/remindly/temp/
# Exists (symlink to /tmp/remindly)
```

### Step 4: Load docs/ READMEs

Read 5 files:
- `docs/README.md`
- `docs/knowledge-base/README.md`
- `docs/implementation/README.md`
- `docs/implementation/proposals/README.md`
- `docs/scratchpad/README.md`

### Step 5: Load Memory Graph

Read the full knowledge graph via `read_graph` from memory MCP. This provides project-wide decisions, rules, and RAG pointers accumulated from prior sessions.

### Step 6: Initialize STATUS.md

Create `docs/implementation/STATUS.md` with full template including:
- Session ID from system prompt
- All 10 tasks listed with dependencies
- Phase overview
- Task Planning Notes for each task (extracted from plan)
- Empty Proposals Pending section
- Recovery Instructions section
- Git branch info

### Step 7: Initialize Database

Via comms-link execute:
```sql
DROP TABLE IF EXISTS orchestration_tasks;
DROP TABLE IF EXISTS orchestration_messages;
-- [Full DDL with CHECK constraints and indexes]
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));
```

Verify:
```sql
PRAGMA table_info(orchestration_tasks);
PRAGMA table_info(orchestration_messages);
```

### Step 8: Verify Hooks

```bash
test -f tools/implementation-hook/hooks.json && echo "PASS"
test -f tools/implementation-hook/session-start-hook.sh && echo "PASS"
```

Verify comms.db accessible via comms-link query:
```sql
SELECT COUNT(*) FROM orchestration_tasks;
-- Expected: 1 (the task-00 row)
```

### Step 9: Lock Plan

Record in STATUS.md Decisions Log:
```
[2026-02-04 14:30] - Plan Locked
Decision: Implementation plan locked at execution start
File: docs/plans/2026-02-04-docs-reorganization.md
```

**Context usage after initialization: ~25-30k tokens (~12-15%).**

Ready to begin Phase 1.

---

## Example: Launching Parallel Execution Sessions

This walkthrough shows launching Phase 2 with 4 parallel tasks after Phase 1 completes.

### Step 1: Verify Phase 1 Complete

```sql
SELECT task_id, state FROM orchestration_tasks WHERE task_id = 'task-01';
-- Expected: state = 'complete'
```

### Step 2: Create Phase 2 Task Instructions

Launch Task subagent pointing at implementation plan directly with Overrides & Learnings (danger file note for testing/ directory shared between tasks 3 and 4):

```
Task("Create task instructions for Phase 2", prompt="""
[Prompt with: phase info, plan path, Overrides & Learnings section,
 instructions, quality gate. Danger file note for testing/ directory shared
 between tasks 3 and 4]
""", subagent_type="general-purpose", run_in_background=False)
```

Review returned instructions. Template compliance validation: all 4 files have complete template sections. Strategy checklist passes. Danger file coordination addressed in instructions.

### Step 3: Insert Database Rows

```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-03', 'watching', 'docs/tasks/task-03.md', datetime('now'));
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-04', 'watching', 'docs/tasks/task-04.md', datetime('now'));
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-05', 'watching', 'docs/tasks/task-05.md', datetime('now'));
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-06', 'watching', 'docs/tasks/task-06.md', datetime('now'));
```

### Step 4: Insert Instruction Messages

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-03', 'task-00',
    'TASK INSTRUCTION: docs/tasks/task-03.md
     Type: parallel  Phase: 2  Dependencies: none
     Danger files: docs/knowledge-base/testing/ (shared with task-04)',
    'instruction');
-- [Repeat for task-04, task-05, task-06]
```

### Step 5: Present Launch Instructions to User

```
Phase 2 ready. Please launch 4 execution sessions:

Terminal 1: claude "Read task instruction from orchestration_messages for task-03 and execute it."
Terminal 2: claude "Read task instruction from orchestration_messages for task-04 and execute it."
Terminal 3: claude "Read task instruction from orchestration_messages for task-05 and execute it."
Terminal 4: claude "Read task instruction from orchestration_messages for task-06 and execute it."

All sessions will coordinate autonomously via comms-link database.
I will monitor for completion and reviews.
```

### Step 6: Verify Launch + Start Monitoring

Launch background verification watcher first, then present musician prompts to user. Watcher polls for tasks reaching `working` state.

All 4 reach `working` within 2 minutes. Start main monitoring subagent:
```
Task("Monitor Phase 2", prompt="""
[Parallel monitoring template with tasks 03-06]
""", subagent_type="general-purpose", run_in_background=True)
```

### Step 7: Handle Events

Monitoring subagent returns when any task changes state. Handle in priority order:
- Errors → Error handling workflow
- Reviews → Review workflow
- Completions → Note completion, relaunch monitoring for remaining tasks

### Phase 2 Complete

When all 4 tasks reach `complete`:
1. Check for proposals in `docs/implementation/proposals/`
2. Check `temp/` for misplaced proposals
3. Integrate critical proposals
4. Update STATUS.md
5. Proceed to Phase 3

---

## Example: Review Approval Workflow

This walkthrough shows handling a `needs_review` event from task-03 at checkpoint 1.

### Step 1: Monitoring Subagent Returns

```
Event detected: task-03 state = 'needs_review'
Message: "REVIEW REQUEST (Smoothness: 2/9):
  Checkpoint: 1 of 3
  Context Usage: 28%
  Self-Correction: NO
  Deviations: 0
  Agents Remaining: 3 (~4% each, ~12% total)
  Proposal: docs/implementation/proposals/2026-02-07-testing-patterns.md
  Summary: Steps 1-3 complete, 3 knowledge-base files extracted
  Files Modified: 8
  Tests: All passing (42 tests, 8 new)"
```

### Step 2: Set Reviewing State

```sql
UPDATE orchestration_tasks
SET state = 'reviewing', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

### Step 3: Evaluate

- Smoothness 2/9 → Minor clarifications, self-resolved → Approve range
- Self-Correction: NO → Context estimates reliable
- Deviations: 0 → Clean execution
- Context 28% → Plenty of headroom
- Tests passing → Good

Quick read of proposal file. Aligns with plan goals. Deliverables match expectations.

### Step 4: Approve

```sql
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-03', 'task-00',
    'REVIEW APPROVED: Clean execution. Proceed with Steps 4-6.',
    'approval');
```

### Step 5: Return to Watching

```sql
UPDATE orchestration_tasks
SET state = 'watching', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

### Step 6: Resume Monitoring

Relaunch monitoring subagent for remaining active tasks (task-03 still working + task-04, 05, 06).

### Step 7: Update STATUS.md

Update task-03 section:
```markdown
### Task 3: Extract Testing Documentation
**Status:** In Progress
**Progress:**
- [x] Checkpoint 1: Approved (Smoothness 2/9)
- [ ] Checkpoint 2: [pending]
- [ ] Final review
```

---

## Example: Error Recovery Workflow

This walkthrough shows handling an error from task-05 at retry 1.

### Step 1: Monitoring Subagent Returns

```
Event detected: task-05 state = 'error'
last_error: 'test_auth_integration timeout'
```

### Step 2: Read Error Details

```sql
SELECT message FROM orchestration_messages
WHERE task_id = 'task-05' AND message_type = 'error'
ORDER BY timestamp DESC LIMIT 1;
```

```
ERROR (Retry 1/5):
  Context Usage: 38%
  Self-Correction: NO
  Error: test_auth_integration timeout
  Report: docs/implementation/reports/task-05-error-retry-1.md
  Awaiting conductor fix proposal
```

Read the error report file for full analysis.

### Step 3: Analyze

Error is a test timeout — likely a configuration issue (timeout threshold too low). Simple fix.

### Step 4: Propose Fix

```sql
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-05';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-05', 'task-00',
    'FIX PROPOSAL (Retry 1/5):
     Root cause: Auth service timeout set to 5s, test expects 3s
     Fix: Update auth.ts:45 timeout to 3000ms
     Retry: Re-run tests after fix',
    'fix_proposal');
```

### Step 5: Resume Monitoring

Relaunch monitoring subagent. Execution session will apply fix, set `working`, and continue.

### Alternative: Context Exhaustion Warning

If `last_error = 'context_exhaustion_warning'`:

```
CONTEXT WARNING: 58% usage
  Self-Correction: YES (step 3, agent 1 — integration test mismatch)
  Agents Remaining: 4 (~8% each with self-correction risk = ~32% total)
  Agents That Fit in 65% Budget: 1
  Deviations: 2
  Proposal: Complete step 4, then handoff
  Awaiting conductor instructions
```

Context situation checklist:
- Self-correction active → estimates unreliable (~6x)
- 58% usage with ~32% estimated remaining → 90% projected (exceeds ceiling)
- Only 1 agent fits in 65% budget
- Musician's proposal (complete step 4 then handoff) is realistic

Response: `fix_proposed` — "Complete step 4 only, skip remaining agents, prepare handoff."

### Alternative: Retry Exhaustion (Retry 5)

Musician self-exits after 5th retry. State = `exited`.

Escalate to user:
```
Task-05 musician exhausted all 5 retries and exited.

Error history:
- Retry 1: test_auth_integration timeout
- Retry 2: same timeout after fix applied
- Retry 3: different failure — auth module not found
- Retry 4: module found but tests still failing
- Retry 5: same failure pattern

Options:
1. Retry with new task instructions (different approach)
2. Skip task-05 and proceed with remaining tasks
3. Investigate root cause before continuing
4. Abort implementation

Recommendation: Investigate root cause — the error pattern suggests a deeper issue.
```

---

## Example: Completion Coordination

This walkthrough shows the final integration after all tasks complete.

### Step 1: Verify All Complete

```sql
SELECT task_id, state, completed_at, report_path
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```

All tasks show `complete`. Task 6 shows `exited` (context exit, completed by replacement session task-06-S2).

### Step 2: Read Completion Reports

Read all report files. Collect deliverables, smoothness scores, test status.

### Step 3: Run Final Verification

```bash
# All tests passing
flutter test

# Git clean
git status

# Check for files outside expected directories
find docs/ -name "*.md" -newer docs/implementation/STATUS.md
```

### Step 4: Check and Integrate Proposals

```bash
ls -la docs/implementation/proposals/
```

Found 3 proposals:
- `2026-02-07-parser-rewrite-antipattern.md` (ANTI_PATTERN)
- `2026-02-07-testing-pattern-extraction.md` (PATTERN)
- `2026-02-07-claude-md-rag-query-rule.md` (CLAUDE_MD)

Integrate CLAUDE_MD proposal immediately. Defer others to user decision.

### Step 5: Ask About Docs Generation

```
Implementation complete. Consolidated guides available from knowledge-base:
- reference/testing-guide.md
- reference/api-guide.md

Generate now?
```

### Step 6: Prepare PR

```bash
git log --oneline main..HEAD
```

Suggest PR title: "docs: reorganize documentation with RAG knowledge base"

### Step 7: Report to User

```
Implementation complete.

Deliverables: 47 files created/modified
Phases: 3 completed
Average smoothness: 2.3/9 (high quality)
Total tasks: 9 completed, 1 exited (resumed by S2, completed)
Proposals: 3 created, 1 integrated, 2 deferred

Recommendations:
- Review deferred proposals before merging
- Run full test suite one more time
- Consider generating consolidated reference guides
```

### Step 8: Set Complete

```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now')
WHERE task_id = 'task-00';
```

---

## Example: Mid-Plan Resumption

This walkthrough shows a new conductor session resuming after the previous session exited at 72% context.

### Step 1: Read Full STATUS.md

Read the entire file. Recovery section says:
```
Context exit at: 2026-02-07 16:00
Last known usage: 72%
Last checkpoint: Task 3 review approved, Task 4 still working
Active sessions: task-04 (working)
Next action: Monitor task-04, proceed with Phase 3
```

### Step 2: Query Database

```sql
SELECT task_id, state, session_id, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
ORDER BY task_id;
```

Results:
- task-00: `exit_requested` (stale — previous conductor)
- task-01: `complete`
- task-03: `complete`
- task-04: `working`, heartbeat 45s ago (still alive)
- task-05: `complete`
- task-06: `complete`

### Step 3: Check Recent Messages

```sql
SELECT task_id, message_type, timestamp
FROM orchestration_messages
ORDER BY timestamp DESC LIMIT 10;
```

No pending reviews or errors.

### Step 4: Propose Next Steps

```
Analyzed current state:
- Phase 1: Complete (task-01)
- Phase 2: 3 of 4 complete (task-04 still working, heartbeat fresh)
- Phase 3: Not started

Proposed next steps:
1. Update task-00 to 'watching' with new session_id
2. Monitor task-04 until completion
3. After task-04 completes, proceed to Phase 3

Proceed?
```

### Step 5: User Approves

### Step 6: Resume

Update conductor row:
```sql
UPDATE orchestration_tasks
SET state = 'watching',
    session_id = '$CLAUDE_SESSION_ID',
    last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

Launch monitoring subagent for task-04. Continue orchestration.

---

## Example: Instruction Subagent Launch & Review

This walkthrough shows the conductor launching a task instruction creation subagent for Phase 2 and handling a review correction loop.

### Step 1: Prepare Overrides & Learnings

Phase 1 is complete. Phase 2 has 3 parallel tasks (tasks 03-05). The conductor reviews STATUS.md Task Planning Notes and compiles overrides:

```
Task 3 notes:
- Extract testing patterns from 6 files
- Create proposal before extraction
- Checkpoint: proposal review
- Verify YAML frontmatter

Task 4 notes:
- Extract implementation guidelines from 4 files
- Checkpoint: after first 2 extractions
- Danger file: docs/knowledge-base/testing/ (shared with Task 3)

Task 5 notes:
- Consolidate reference documentation
- Checkpoint: after consolidation
- Self-contained, no danger files
```

Overrides compiled:
- task-03 and task-04 share `docs/knowledge-base/testing/` — use temporal separation (task-03 touches it in step 1, task-04 in step 3)
- task-05 is fully independent

### Step 2: Launch Task Subagent

Launch subagent pointing at implementation plan directly with Overrides & Learnings:

```
Task("Create task instructions for Phase 2", prompt="""

Load the copyist skill, then create task instruction files for this phase.

## Phase Info
**Phase:** 2 — Content Extraction
**Task type:** parallel
**Tasks to create:** task-03, task-04, task-05
**Implementation plan:** docs/plans/2026-02-04-docs-reorganization.md
**Output directory:** docs/tasks/

## Overrides & Learnings
- task-03 and task-04 share docs/knowledge-base/testing/ (danger file)
  Use temporal separation: task-03 touches it in step 1, task-04 in step 3
- task-05 is fully independent, no danger files

## Instructions
1. Read the implementation plan at `docs/plans/2026-02-04-docs-reorganization.md`
2. Invoke the `copyist` skill
3. Read the parallel template — following templates is MANDATORY
4. Extract tasks 03, 04, 05 from the plan
5. Apply the Overrides & Learnings above — these take precedence over the plan
6. Write instruction files to `docs/tasks/`
7. Validate each file and fix errors until all pass

Report validation results for each file when done.
""", subagent_type="general-purpose", run_in_background=False)
```

### Step 3: Review Returned Instructions

Subagent returns. All 3 files written to disk. Validation script reports 0 errors.

**Template compliance check:**
- task-03.md: All template sections present ✅
- task-04.md: All template sections present ✅
- task-05.md: Missing Verification Checklist and Error Recovery sections ⚠️

### Step 4: Correction Loop (Task 05 Incomplete)

Task-05 is missing mandatory template sections. Launch correction:

```
Task("Complete task-05 template sections", prompt="""
Task-05 instruction file is missing required template sections.

Current file: docs/tasks/task-05.md
Issue: Missing Verification Checklist and Error Recovery sections.

Required additions:
- Verification Checklist with Verify/Expected/If-failed format
- Error Recovery section (STRICT — use parallel template verbatim)
- More detailed step-by-step breakdown (current has 3 steps, should have 5-6)
- Explicit verification criteria per step

Reference the implementation plan section for Task 5: [relevant section]

Rewrite and complete all template sections.
""", subagent_type="general-purpose")
```

### Step 5: Re-Review

Subagent returns with completed task-05.md. All 3 files now have complete template sections.

**STRATEGY checklist (7 items):**
- [x] Instructions align with plan goals
- [x] Parallel pattern chosen correctly
- [x] Task dependencies documented (danger file for 03/04)
- [x] Review checkpoints at logical points
- [x] Template compliance — all sections present
- [x] Verification steps adequate
- [x] Integration between tasks considered (danger file mitigation)

### Step 6: Insert Database Rows and Messages

Proceed to insert task rows and instruction messages (see [Phase Planning — Steps 6-7](#6-insert-database-rows)).

**Context usage after Phase 2 instruction creation: ~45-50k tokens (~22-25%).**

---

## Example: Conductor Clean Exit

This walkthrough shows the conductor exiting cleanly when context approaches the threshold.

**Scenario:** The conductor is monitoring Phase 2 (4 parallel tasks). Task-03 just submitted a complex review (smoothness 6/9 with self-correction flag). After evaluating the review and sending a rejection, context is at 73%.

### Step 1: Context Threshold Triggered

After sending the review rejection, the conductor checks context: **73%** — in the 70-80% zone.

### Step 2: Complete In-Flight Work

The conductor has just finished the review rejection. No other in-flight work. All other parallel tasks are in `working` state with fresh heartbeats.

### Step 3: Write Recovery Instructions

Update STATUS.md Recovery section:

```markdown
## Recovery Instructions

**Context exit at:** 2026-02-07 15:30
**Last known usage:** 73% (145k/200k)
**Last checkpoint:** Task 3 review rejected (smoothness 6/9, self-correction active)
**Active sessions:**
- task-03: review_failed (awaiting musician revision)
- task-04: working (heartbeat 30s ago)
- task-05: working (heartbeat 45s ago)
- task-06: working (heartbeat 20s ago)
**Next action:**
1. Monitor all 4 tasks
2. Task-03 will resubmit after addressing rejection feedback
3. Expect task-05 completion soon (was at checkpoint 2 of 3)
4. No pending errors or escalations
```

### Step 4: Update STATUS.md Task Sections

Quick updates to each active task section noting current status at exit.

### Step 5: Set Exit Requested

```sql
UPDATE orchestration_tasks
SET state = 'exit_requested', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

### Step 6: Notify User

```
Conductor context at 73%. Exiting to preserve remaining capacity for resumption.

Current state:
- 4 execution sessions active (tasks 03-06)
- Task 03 has pending review rejection
- No errors or escalations

To resume orchestration:
  claude "Resume orchestration. Read STATUS.md and orchestration_tasks for current state."

Execution sessions will continue autonomously. They check conductor heartbeat
with 9-minute threshold — resume within ~8 minutes to prevent timeout escalation.
```

### Step 7: Exit

The stop hook queries task-00 state, finds `exit_requested`, and allows exit.

### What Happens Next

1. Execution sessions continue working. Their watchers check task-00 heartbeat every cycle.
2. If conductor doesn't resume within ~9 minutes, musicians detect stale conductor heartbeat but continue working — they only escalate to user on timeout, not crash.
3. New conductor session starts, reads STATUS.md, queries database, proposes next steps (see [Example: Mid-Plan Resumption](#example-mid-plan-resumption)).

---

## Script: validate-coordination.sh

Validates database consistency across all orchestration tasks. Run at any time to check overall state.

**Usage:** `bash scripts/validate-coordination.sh`

**Checks performed:**
1. **All tasks exist** — Report task_id, state, session_id, last_heartbeat, retry_count for each
2. **Heartbeat freshness** — Flag stale heartbeats (>540 seconds) in non-terminal states
3. **State validity** — Verify all states are one of the 11 valid values
4. **Pending messages** — Count unread messages per task
5. **Fallback rows** — Detect and report any `fallback-*` rows
6. **Conductor health** — Check task-00 state and heartbeat

**Output format:**
```
=== Orchestration State Report ===
task-00  watching    heartbeat: 12s ago    [OK]
task-01  complete    completed: 2026-02-07  [DONE]
task-03  working     heartbeat: 45s ago    [OK]     messages: 0 pending
task-04  needs_review heartbeat: 30s ago   [REVIEW] messages: 1 pending
Fallbacks: none
=== SUMMARY: 1 task needs attention (task-04 review pending) ===
```

## Script: check-git-branch.sh

Verifies the working directory is not on main/master branch.

**Usage:** `bash scripts/check-git-branch.sh`

**Behavior:**
- If on main/master: exit code 1, print warning
- If on feature branch: exit code 0, print branch name

## Script: check-context-headroom.sh

Parses an musician's status file for context usage entries and estimates remaining budget. The conductor uses this to passively check an musician's context trajectory without interrupting it via database messages.

**Usage:** `bash scripts/check-context-headroom.sh <task_id>`

**Checks performed:**

1. **Parse context entries** — Extract all `[ctx: XX%]` entries from `temp/task-{NN}-status`
2. **Calculate trajectory** — Average context per entry, total consumed since bootstrap
3. **Estimate remaining budget** — Headroom to 80% ceiling, estimated entries remaining
4. **Agent tracking** — Count agents launched/returned, average context per agent
5. **Self-correction impact** — If self-correction entries found, flag estimates as unreliable (~6x risk)
6. **Step progress** — Count steps started/completed, current step

**Output format:**
```
=== Context Headroom: task-03 ===
Current:     52% (entry 24 of status file)
Trajectory:  +2.0% per entry avg
Headroom:    28% remaining to 80% ceiling
Agents:      6 completed, 0 in-flight (~4.3% per agent avg)
Est. Agents Left: ~6 agents fit in remaining budget
Steps:       3 of 5 completed, step 4 in progress
Self-Correction: NO
=== RESULT: HEALTHY ===
```

With self-correction:
```
=== Context Headroom: task-03 ===
Current:     58% (entry 30 of status file)
Trajectory:  +2.8% per entry avg
Headroom:    22% remaining to 80% ceiling
Agents:      8 completed, 1 in-flight (~4.8% per agent avg)
Est. Agents Left: ~4 agents fit in remaining budget
Steps:       3 of 5 completed, step 4 in progress
Self-Correction: YES — estimates unreliable (6x risk)
=== RESULT: CAUTION (self-correction detected) ===
```

**Implementation notes:**
- Read-only file parsing — no database access needed
- Uses `grep` to extract `[ctx: XX%]` patterns and `agent` / `step` entries
- Exit code 0 for healthy, 1 for caution (self-correction or >60% usage), 2 for critical (>75% usage)
- Defined in detail in the [Musician Design](musician-design.md) — this is a shared tool used by both musician (self-check) and conductor (passive monitoring)

---

## Git Operation Restrictions

**Allowed:**
- `git status`, `git diff`, `git log` (read-only inspection)
- `git add` specific files (not `git add -A` or `git add .`)
- `git commit` (with meaningful messages)
- `git checkout -b` (branch creation)
- `git stash` / `git stash pop`
- `git pull`

**Forbidden (require explicit user approval):**
- `git push --force` or `git push -f`
- `git reset --hard`
- `git clean -f`
- `git branch -D`
- `git rebase` on published branches
- `git checkout .` or `git restore .`
- Any operation that destroys uncommitted work

**Conductor-specific:** The conductor should not push to remote without user approval. Commits are local; push decisions happen during final integration.

**Musician-specific:** Musicians should not push to remote at all. Commits are local; conductor or user handles push decisions.

---

## What's Left to Design

**All sections completed in this document:** ✅

**Core workflow sections (22):**
- ~~Purpose and 3-tier model~~ ✅
- ~~Execution model and tool utilization~~ ✅
- ~~Delegation model~~ ✅
- ~~Bootstrap and initialization~~ ✅
- ~~Phase planning and task instruction creation~~ ✅
- ~~Launching execution sessions~~ ✅
- ~~Monitoring~~ ✅
- ~~Review workflow~~ ✅
- ~~Deviation interpretation~~ ✅
- ~~Error handling and recovery~~ ✅
- ~~Session handoff~~ ✅
- ~~Emergency broadcasts~~ ✅
- ~~Context management~~ ✅
- ~~Danger files governance~~ ✅
- ~~Proposal system~~ ✅
- ~~Completion~~ ✅
- ~~Resumption~~ ✅
- ~~Message format standards~~ ✅
- ~~File path conventions~~ ✅
- ~~Temporary file lifecycle~~ ✅
- ~~Hook integration~~ ✅
- ~~Key principles~~ ✅

**Reference appendices (8):**
- ~~State machine (all 11 states, transitions, ownership)~~ ✅
- ~~Database queries (19 SQL patterns)~~ ✅
- ~~Review checklists (3 checklists, smoothness scale)~~ ✅
- ~~Monitoring subagent templates (4 templates)~~ ✅
- ~~Subagent prompt template~~ ✅
- ~~Subagent failure handling (4 categories, retry flowchart)~~ ✅
- ~~STATUS.md template~~ ✅
- ~~Resumption decision tree~~ ✅

**Procedural examples (8):**
- ~~Conductor initialization~~ ✅
- ~~Launching parallel execution sessions~~ ✅
- ~~Review approval workflow~~ ✅
- ~~Error recovery workflow~~ ✅
- ~~Completion coordination~~ ✅
- ~~Mid-plan resumption~~ ✅
- ~~Instruction subagent launch and review~~ ✅
- ~~Conductor clean exit~~ ✅

**Scripts (3):**
- ~~validate-coordination.sh~~ ✅
- ~~check-git-branch.sh~~ ✅
- ~~check-context-headroom.sh~~ ✅

---

**Design Status:** Complete. All workflow sections, reference appendices, examples, and scripts documented.
**Companion documents:** [Musician Design](musician-design.md), [Orchestration Protocol](orchestration-protocol.md)
