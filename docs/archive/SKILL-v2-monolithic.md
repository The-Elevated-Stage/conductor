---
name: Conductor
description: Coordinates autonomous execution of multi-task implementation plans. Always invoke manually via /conductor.
---

<skill name="conductor" version="2.0">

<metadata>
type: skill
tier: 3
</metadata>

<sections>
- mandatory-rules
- purpose
- orchestration-model
- initialization
- phase-planning
- launching-execution-sessions
- monitoring
- review-workflow
- session-handoff
- emergency-broadcasts
- error-handling
- context-management
- completion
- resumption
- best-practices
- resources
</sections>

<section id="mandatory-rules">
<core>
# Conductor

## When You Invoke This Skill

You are the Conductor. Begin by assessing the project state:

1. **Identify available work** — Query for:
   - Active implementation plans (in progress)
   - Not-started IMPLEMENTATION plans (ready to orchestrate)
   - Stalled execution sessions (need handoff/resume)

2. **Report findings to user** — Present options and ask which to prioritize
3. **If single path:** Deep dive into 9-step Initialization, execute phases, pause with status review
4. **If multiple paths:** Wait for user to select which to begin

Then proceed through the full orchestration workflow (Initialization, Phase Planning, Execution, Monitoring, Completion).
</core>

<mandatory>
**Critical Rules:**

- **File Path Governance** (ALL files in these locations):
  - Ephemeral scratch: `temp/` (e.g., `temp/rag-review-task-03.md`)
  - Task instructions: `docs/tasks/` (e.g., `docs/tasks/task-01.md`)
  - Reports: `docs/implementation/reports/`
  - Proposals: `docs/implementation/proposals/`
  - Status: `docs/implementation/STATUS.md`
  - Database: `comms.db`
  - **NEVER /tmp/ — use `temp/` instead**

- **Subagent model:** ALL subagent launches via the Task tool MUST specify `model="opus"`. Sonnet is the default and is insufficient for orchestration subagents. This applies to: task instruction creation, monitoring watchers, RAG overlap-check, RAG ingestion, staleness watchers, and any other subagent the conductor spawns. **No exceptions.**

- **Task instruction creation:** When you need to create task instructions, **ALWAYS** launch a Task subagent with the `copyist` skill, pointing it at the implementation plan with an Overrides & Learnings section (this is mandatory — do not skip). See the Phase Planning section for details.

- **File creation:** All file creation MUST use the Write tool and specify the full path relative to the workspace root
</mandatory>
</section>

<section id="purpose">
<core>
## Purpose

Coordinate autonomous execution of multi-task implementation plans through database-driven state management, parallel execution sessions, and phased task delivery. Transform plans into self-contained task instructions, launch external execution sessions, monitor via database, and handle reviews, errors, and completion.
</core>
</section>

<section id="orchestration-model">
<core>
## 3-Tier Orchestration Model

```
Tier 0: This session — conductor
  ├─ Read and lock implementation plan
  ├─ Create phases, launch task instruction subagents
  ├─ Monitor all tasks via database
  └─ Handle reviews, errors, phase transitions

Tier 1: Execution sessions (EXTERNAL Claude sessions)
  ├─ Read task instruction file
  ├─ Do direct integration work (refactoring, assembly, holistic testing)
  ├─ Delegate smaller isolated pieces (<500 LOC, single module) to Tier 2 subagents
  └─ Review subagent results at checkpoints

Tier 2: Subagents (launched by Tier 1)
  ├─ Receive relevant instruction sections from Tier 1
  ├─ Do actual implementation (code, tests, docs)
  └─ Report results back to Tier 1
```

The conductor does NOT do implementation work. Delegate to subagents (task instruction creation, monitoring) and coordinate external sessions (task execution).
</core>
</section>

<section id="initialization">
<core>
## Initialization

Execute these steps in order. **Steps 1-5 are reads (parallelizable). Steps 6-8 are writes (sequential). Step 9 is a gate (launch initiation).**

1. **Read implementation plan** — Identify phases, task dependencies, parallel-safe groups, danger file annotations (inline `⚠️ Danger Files:` markers).
2. **Git branch** — Verify not on main. Create feature branch if needed. Run `scripts/check-git-branch.sh` to verify.
3. **Verify temp/ directory** — Create `temp/` if missing.
</core>

<mandatory>ALL temporary and scratch files created by the conductor MUST go in `temp/` during execution — never /tmp/ or any other location. This includes RAG review files, decision logs, intermediate reports, etc.</mandatory>

<context>The `temp/` directory is symlinked to `/tmp/remindly` and is automatically cleaned on system reboot, making it safe for ephemeral files.</context>

<core>
4. **Load docs/ READMEs** — Full reads of `docs/README.md`, `knowledge-base/README.md`, `implementation/README.md`, `implementation/proposals/README.md`, `scratchpad/README.md`. Skip all other READMEs (read on demand).
5. **Load memory graph** — Read the full knowledge graph via `read_graph` from memory MCP. This provides project-wide decisions, rules, and RAG pointers accumulated from prior sessions for broad decision-making and project mapping.
6. **Initialize STATUS.md** — Create with: conductor session ID, task list from plan, coordination database info, git branch, Task Planning Notes section, Proposals Pending section, Recovery Instructions section.
7. **Initialize database** — Drop and recreate tables via `comms-link execute`. Insert conductor row. See `references/database-queries.md` for full DDL and initialization SQL.
8. **Verify hooks** — Hooks are self-configuring via `hooks.json` and SessionStart hook. Verify: `hooks.json` exists in `tools/implementation-hook/`, `session-start-hook.sh` and `stop-hook.sh` exist in same directory, `comms.db` is accessible via comms-link.
9. **Lock implementation plan** — Plan is now frozen. Conductor deviations go to STATUS.md Task Planning Notes. External user changes go to `{plan-name}-revisions.md` (standardized naming: append `-revisions` to plan filename, e.g., `2026-02-04-docs-reorganization-revisions.md`). See `references/danger-files-governance.md` for full external change management workflow.
</core>
</section>

<section id="phase-planning">
<core>
## Phase Planning & Task Instruction Creation

For each phase in the implementation plan:

1. **Analyze phase** — Identify task type (sequential or parallel), danger files, inter-task dependencies.
2. **Review danger files** — Extract inline annotations from plan. Assess severity and timeline overlap. Decide: keep parallel or move to sequential. See `references/danger-files-governance.md`.
3. **Prepare overrides & learnings** — Review the implementation plan for this phase. Note any conductor corrections, task planning notes, or learnings from prior phases that should override or supplement what's in the plan. These will be passed directly in the subagent prompt.
</core>

<mandatory>
4. **Launch Task subagent for this phase** — Use the Task tool to launch a subagent with the `copyist` skill. The subagent will:
   - Read the implementation plan directly
   - Load the `copyist` skill
   - Create ALL instruction files for the phase in `docs/tasks/task-{ID}.md`
   - Apply any overrides from the conductor
   - Validate each file and report results

   **DO NOT skip this step.** If you skip launching the subagent, the task instruction files will not be created and orchestration will fail.
</mandatory>

<template follow="format">
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
""", model="opus", run_in_background=False)
```
</template>

<core>
5. **Review returned instructions** — Check validation script results, spot-check alignment with plan goals, verify appropriate task type chosen. Verify all template sections are present (inapplicable sections marked N/A with reason). Compare created instructions against the `copyist` skill templates (sequential and parallel) to ensure structure and completeness. Look for: clear objective, success criteria, prerequisites, context, and all required steps.
6. **Insert database rows** — For each task: `INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat) VALUES ('task-XX', 'watching', 'docs/tasks/task-XX.md', datetime('now'));`
7. **Insert instruction messages** — After completing step 6, insert one message per task into `orchestration_messages` with message_type='instruction'. Format the message as:
   ```
   TASK INSTRUCTION: docs/tasks/task-XX.md
   Type: [sequential|parallel]
   Phase: N
   Dependencies: [task IDs or "none"]
   Danger files:
     - [path] ([notes if shared])
   ```
</core>

<mandatory>Musician claims task only after BOTH the task row (step 6) AND instruction message exist.</mandatory>

<context>
**Subagent retry policy:** The Task subagent (step 4) has 3 retries maximum with same prompt. After 3 failures, escalate to user with all error messages and options (skip phase, abort, retry manually). See `references/subagent-failure-handling.md` for failure categories, retry decision flowchart, and escalation message format.
</context>
</section>

<section id="launching-execution-sessions">
<mandatory>
## Launching Execution Sessions (MANDATORY Musician Skill Protocol)

All external execution sessions MUST use the musician skill launch prompt template. See `references/musician-launch-prompt-template.md` for the template and fill-in instructions.
</mandatory>

<core>
**Sequential tasks:** Use the same musician skill launch template, but launch one task at a time. Wait for the task to reach `complete` state before launching the next task. No danger files coordination needed for sequential tasks. See `references/sequential-coordination.md` for details.
</core>

<mandatory>Background message-watcher is REQUIRED for all execution sessions.</mandatory>

<core>
**Parallel tasks:** Launch one kitty window per task using the Bash tool. All musician prompts must start with `/musician` to load the skill first.

The conductor launches execution sessions directly via the Bash tool by spawning kitty windows. Each task gets its own kitty OS window running `claude` with the filled-in musician template as the prompt. See `references/musician-launch-prompt-template.md` for the complete template and `references/parallel-coordination.md` for the full launch protocol.

**Launch command pattern (one per task):**
</core>

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: {{TASK_ID}}" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = '{{TASK_ID}}' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: {{TASK_ID}}
- Phase: {{PHASE_NUMBER}} — {{PHASE_NAME}}

Do not proceed without reading the full instruction message. All steps are there." &
```
</template>

<core>
Use the Bash tool with `run_in_background=true` or append `&` to each command so the conductor is not blocked. Launch all tasks for the phase in parallel (one Bash call per kitty window).

**Launch sequence:**

1. **Launch background verification watcher first** — Before launching kitty windows, launch a watcher subagent to poll for tasks reaching `working` state. See `examples/monitoring-subagent-prompts.md` (Launch Verification Watcher section) for the specific prompt. This ensures monitoring is active before execution sessions start.
2. **Launch kitty windows** — Use the Bash tool to launch one kitty window per task. The watcher is already running.
3. **Watcher behavior:**
   - If all tasks reach `working` within 5 minutes: watcher exits and notifies conductor
   - If any remain `watching` after 5 minutes: watcher notifies conductor to re-launch failed kitty windows
4. **After verification complete:** Start the main background monitoring subagent. See `examples/monitoring-subagent-prompts.md` (Main Monitoring Watcher section).
</core>
</section>

<section id="monitoring">
<core>
## Monitoring

Use a tiered STATUS.md reading strategy (see `references/status-md-reading-strategy.md`):

- **Frequent:** Query `orchestration_tasks` for state and heartbeat. Fast and cheap.
- **Selective:** Read individual task sections from STATUS.md when reviewing specific task context.
- **Rare:** Full STATUS.md reads only at initialization, final completion, or resumption.
</core>

<mandatory>
**Background Watcher Exit Behavior**

The background monitoring subagent operates on a specific contract:

1. **Launch:** Conductor launches subagent with `model="opus", run_in_background=True`
2. **Poll:** Subagent continuously polls `orchestration_tasks` table
3. **Heartbeats:** Subagent updates task heartbeats and conductor heartbeat (`task-00`)
4. **Exit trigger:** When subagent detects state change to `needs_review`, `error`, or `complete`:
   - Send optional exit message (for logging only — do NOT rely on message delivery)
   - **IMMEDIATELY EXIT the background task** (do not loop, do not wait, do not send more messages)
5. **Notification:** Claude notifies conductor of subagent exit
</mandatory>

<reference path="skills_staged/conductor/examples/monitoring-subagent-prompts.md" load="recommended">
Complete prompt template with explicit exit instructions.
</reference>

<core>
**Conductor Monitoring Cycle:**

1. **Launch background watcher** — Invoke Task with `model="opus", run_in_background=True`, prompt from template above
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
6.5. **Process pending RAG work** — Check STATUS.md "Pending RAG Processing" section. If entries exist and no other events are pending, process them now. This catches RAG proposals deferred during busy review cycles. The background message-watcher remains active throughout — if a new event arrives during RAG processing, pause RAG work and handle the event first (see reference for full interruption protocol). See `references/rag-coordination-workflow.md` for the complete RAG processing flow, subagent prompts, and interruption handling details.
7. **Repeat** — Return to step 2
</core>

<context>
**Conductor heartbeat management:** During each monitoring cycle, the watcher updates `task-00` heartbeat. Musicians check this heartbeat with 540-second (9-minute) threshold — stale conductor heartbeat triggers timeout escalation.

Run `scripts/validate-coordination.sh` to manually check database state at any time (useful for debugging).
</context>
</section>

<section id="review-workflow">
<mandatory>
## Review Workflow

**You are the authority.** When you identify an error — in task instructions, musician output, verification results, or review submissions — you MUST correct it. Do not approve work that contains known errors. Do not defer corrections to the musician hoping they'll self-correct. Use `fix_proposed` to send corrections, even mid-review.
</mandatory>

<core>
When background watcher exits due to detection of `needs_review` state:

1. **Identify task** — Query which task(s) have `needs_review` state. Usually one, but check for multiples. If multiple tasks are in `needs_review` simultaneously, handle them in order: pick one at random to start, complete its review, then check the table again before handling the next one. Follow the full review workflow below for each task.
2. **Read review request message** — From `orchestration_messages` for the task.
   - **Message structure:** Context Usage (%), Self-Correction (YES/NO), Deviations (count + severity), Agents Remaining (count and %), Proposal (path to file), Summary (accomplishments), Files Modified (count), Tests (status and count), Key Outputs (list of project-root-relative paths with action: created/modified/rag-addition).
3. **Self-correction flag awareness:** If `Self-Correction: YES`, context estimates are unreliable (~6x bloat). Treat with caution. Compare actual context usage to task instruction estimates. If actual > 2x estimated → warn user they may need an additional session. If actual inline with estimate → tell musician to reset flag to false.
4. **Read the proposal or report** — Referenced in the message.
5. **Review loop tracking** — Count prior reviews: `SELECT COUNT(*) FROM orchestration_messages WHERE task_id = ? AND message_type = 'review_request'`. Cap at 5 cycles per checkpoint. At cycle 5, escalate to user with entire review history.
6. **Evaluate using smoothness scale (0-9):**

| Score | Meaning |
|-------|---------|
| 0 | Perfect execution, no deviations |
| 1-2 | Minor clarifications, self-resolved |
| 3-4 | Some deviations, documented |
| 5-6 | Significant issues, conductor input needed |
| 7-8 | Major blockers, multiple review cycles |
| 9 | Failed or incomplete, needs redesign |
</core>

<guidance>
**Context-aware reading strategy:** Skim message structure first (Context Usage, Self-Correction, Deviations fields). Deep-read proposal file only if smoothness >5 or self-correction flag is set. This preserves conductor context for strategic decisions.
</guidance>

<core>
7. **Decision thresholds:**
   - **0-4:** Approve. Set state to `review_approved`, send approval message. If `Self-Correction: YES`, include: "Set self-correction flag to false — this was minor."
   - **5:** Investigate before approving. Score 5 means significant issues occurred — do not rubber-stamp. Read the full proposal/report (override the context-aware skim strategy). If you identify errors the musician missed or perpetuated, correct them via `fix_proposed` before approving. Only set `review_approved` after confirming no actionable errors remain.
   - **6-7:** Request revision. Set state to `review_failed`, send specific feedback.
   - **8-9:** Reject. Set state to `review_failed`, send detailed rejection with required changes.

For detailed review checklists, score interpretation, context situation checklist, and aggregation guidance, see `references/review-checklists.md`.

8. **Send message via `orchestration_messages`** — Update task state and send approval/feedback/rejection message to musician. If approving a task for completion and it has RAG proposals (`type: rag-addition` in `docs/implementation/proposals/`), add entry to STATUS.md "Pending RAG Processing" section.
9. **Eager RAG processing (completion reviews only)** — Before returning to idle state, check `orchestration_tasks` for any other tasks in `needs_review` or `error` state. If none are pending, launch the RAG processing subagent immediately. If other reviews are pending, handle those first — RAG processing must never block review handling. Deferred RAG will be caught by the monitoring cycle fallback (step 6.5).

**After review completes:** Proceed to step 5.5 (Check Table for Additional Changes) in Monitoring section above.

See `references/state-machine.md` for all state transitions and ownership rules.
</core>
</section>

<section id="session-handoff">
<core>
## Session Handoff

When an musician session exits and needs replacement (clean context exit, crash, or retry exhaustion), follow the handoff procedure in `references/session-handoff.md`. This covers:

- **Clean Handoff:** Musician wrote HANDOFF doc, context <80%. Set `fix_proposed`, read HANDOFF, send handoff message, launch replacement kitty window.
- **Dirty Handoff:** Musician wrote HANDOFF doc, context >80% (hallucination risk). Same as clean BUT verify produced tests in handoff message. Do not verify code directly — high context = likely hallucinations.
- **Crash:** No HANDOFF doc. Send message with verification instructions for most recently completed/worked steps.
- **Retry Exhaustion:** Musician self-exited after 5th retry failure. This is an conductor error — escalate to user with options.
- **Context Exit:** Clean session exit due to context management. Not an error — session handled context warning and chose to handoff. Update STATUS.md with recovery instructions.
- **Claim Collision Recovery:** If a new musician session fails to claim a task (detected via `claim_blocked` message), attempt 1 retry: reset the task row (update state back to `watching`, clear session_id) and re-insert the instruction message. Re-launch the musician kitty window. If claim fails again, report to user that the task may need manual investigation.

See `references/session-handoff.md` for full procedures, worked_by succession pattern, and guard clause re-claiming logic.
</core>
</section>

<section id="emergency-broadcasts">
<core>
## Emergency Broadcasts

When critical cross-cutting issues require all execution sessions to see a message (shared file conflict, user-requested pause, etc.), use emergency broadcast:
</core>

<template follow="exact">
```sql
-- One INSERT per task_id. Each musician watcher detects via its own task's message log.
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'BROADCAST: [critical message]',
    'emergency'
);
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-04', 'task-00',
    'BROADCAST: [same message]',
    'emergency'
);
```
</template>

<context>
No body parsing needed — each session only monitors its own task_id column. Conductor has full control over triggers.
</context>
</section>

<section id="error-handling">
<core>
## Error Handling

When an execution session sets state to `error`:

1. Check `last_error` field. If `last_error = 'context_exhaustion_warning'`, follow **Context Warning Protocol** below. Otherwise continue.
2. Read error report from path referenced in the message.
3. Analyze: error type, context, stack trace, retry count, suggested investigation.
4. Decision tree:
   - **Simple fix** (typo, config) — Propose fix immediately. Set `fix_proposed`.
   - **Complex** (logic error) — Search RAG for similar patterns, then propose.
   - **Uncertain** — **Flag uncertainty for user review** before sending to musician. Include in your fix proposal: "This fix is uncertain. Please verify before merging." Give user option to investigate further or provide guidance.
   - **retry_count >= 5** — This is an conductor error: musician exhausted retries. Escalate to user for decision: retry with new instructions, skip task, investigate root cause. See `references/session-handoff.md` for escalation message template.
5. Send fix proposal via `orchestration_messages`. Set state to `fix_proposed`.

**Context Warning Protocol:** When `last_error = 'context_exhaustion_warning'`, musician reports remaining context but can still propose a path forward. Evaluate context situation checklist (see `references/review-checklists.md`):
- Is self-correction flag active? (context estimates are ~6x unreliable)
- How many deviations and how severe?
- How far to next checkpoint?
- How many agents remain and at what cost?
- Has this task had prior context warnings?

Respond with ONE of:
- `review_approved`: Proceed with musician's proposal (reach checkpoint OR run N more agents — whatever musician suggested)
- `fix_proposed`: Override musician's proposal — "Only do X then prepare handoff" or "Adjust approach"
- `review_failed`: Stop now, prepare handoff immediately

See `examples/error-recovery-workflow.md` for the complete flow.
</core>
</section>

<section id="context-management">
<core>
## Context Management

Monitor context usage via system messages:

- **< 70%:** Safe. Continue normal operations.
- **70-80%:** Complete current review or action. Write Recovery Instructions to STATUS.md. Set conductor state to `exit_requested`.
- **> 80%:** Immediately write Recovery Instructions and exit.

**Recovery Instructions format:** Simple bulleted list with these sections:
- Timestamp (when recovery started)
- Last context usage (%)
- Last checkpoint reached
- Active sessions (task IDs and their current states)
- Next action for resuming session (clear, specific instruction)
</core>

<guidance>
Keep Recovery Instructions concise—they're meant for the resuming conductor session to quickly understand state and proceed.
</guidance>
</section>

<section id="completion">
<core>
## Completion

When all tasks in all phases reach `complete`:

1. Verify all completion reports filed and all expected files created.
2. Run final verification: tests passing, git clean, RAG files ingested, directory structure correct.
3. Integrate proposals: CLAUDE.md additions, memory snippets, RAG pattern documentation.
4. Ask user about generating human-readable docs from knowledge base.
5. Prepare PR: review commits, check for sensitive data, suggest title and description.
6. Report to user with deliverables list and recommendations. Wait for feedback.
7. Set conductor state to `complete`.

See `examples/completion-coordination.md` for the full workflow.
</core>
</section>

<section id="resumption">
<core>
## Resumption

When starting a new session to resume interrupted orchestration:

1. **Read full STATUS.md** — Not just Recovery section. Cost is ~2-5k tokens, done once.
2. **Query orchestration_tasks** — Get all rows, triage by state:
   - `complete`/`exited` — skip, note for report
   - `working` + recent heartbeat — still running, monitor
   - `working` + stale heartbeat — may need intervention
   - `watching` — not yet claimed
   - `needs_review` — handle immediately
   - `error` — needs fix proposal
3. **Check recent messages** — Read last 10 from `orchestration_messages`.
4. **Propose next steps** — Present triage results and proposed actions to user. Wait for approval.
5. **Verify hooks** — Hooks are self-configuring. Check `hooks.json`, `session-start-hook.sh`, `stop-hook.sh` exist in `tools/implementation-hook/`. SessionStart hook will set `$CLAUDE_SESSION_ID` automatically.
</core>
</section>

<section id="best-practices">
<core>
## Best Practices

**Claim Collisions and Fallback Rows**

When two execution sessions try to claim the same task simultaneously, the second claim fails due to database guard clauses. The failing session creates a fallback row with message_type='claim_blocked' to exit cleanly:

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-03', '$CLAUDE_SESSION_ID',
    'CLAIM BLOCKED: Guard prevented claim on task-03. Created fallback row to exit cleanly.',
    'claim_blocked');
```
</core>

<context>
The monitoring subagent detects fallback rows later and compares timestamps with the original task:
- If original task's heartbeat > fallback's: Delete fallback (original session worked, collision handled)
- If original task's heartbeat <= fallback's: Report to user (claim collision, task may need re-launch via kitty)

See `references/state-machine.md` for full guard clause details.
</context>

<core>
**Context Headroom is Valuable**

The conductor delegates work to preserve context for wide-scope decisions:
- Use conductor context for: strategic decisions, cross-task coordination, quality assurance, error triage
- Delegate to subagents for: task instruction creation, monitoring, RAG queries
- Delegate to external sessions for: all implementation work (code, tests, docs)

This frees the conductor's 200k-token budget for what only the conductor can do: see the full picture.
</core>

<mandatory>
**External Sessions Are Not Subagents**

This distinction is critical:
- **External execution sessions:** Full Claude Code sessions launched in separate kitty windows with their own 200k context. Execute task instructions independently. Coordinate via comms-link database. Conductor launches these via the Bash tool (`kitty --directory /home/kyle/claude/remindly --title "Musician: task-XX" -- env -u CLAUDECODE claude --permission-mode acceptEdits "prompt" &`).
- **Subagents:** Spawned by conductor using the Task tool. Run within parent session's context budget. Used for task instruction creation and monitoring. Ephemeral.

Confusing these breaks the orchestration model. Execution sessions do the work. Subagents coordinate.
</mandatory>

<core>
**When Conductor is Overloaded**

Watch for these signs:
- Context > 70%: Write Recovery Instructions, set `exit_requested`, exit and resume in new session
- Monitoring cycle takes > 5 minutes of reasoning: Reduce parallelism or simplify task structure
- Many parallel tasks reporting simultaneously: **Handle in priority order: errors first, then reviews, then completions.** Errors are blocking; completions are non-blocking.
- Re-reading same information repeatedly: Write key facts to Task Planning Notes as working memory

For detailed guidance on these topics, delegation patterns, and anti-patterns, see `references/orchestration-principles.md`.
</core>
</section>

<section id="resources">
<core>
## Resources

### Reference Files

- **`references/state-machine.md`** — All 11 states, transitions, ownership rules, heartbeat requirements, terminal states
- **`references/database-queries.md`** — Complete DDL, initialization workflow, 19 common SQL patterns with expected outputs
- **`references/sequential-coordination.md`** — Simple pattern: self-configuring hooks, manual message checks, single-task execution
- **`references/parallel-coordination.md`** — Hook-based pattern: background subagent, review checkpoints, parallel launch protocol
- **`references/subagent-prompt-template.md`** — Prompt template for launching task instruction creation subagents
- **`references/rag-query-guide.md`** — RAG query patterns organized by use case for orchestration knowledge base
- **`references/rag-coordination-workflow.md`** — Complete RAG processing workflow, overlap-check and ingestion subagent prompts, interruption handling during RAG review
- **`references/danger-files-governance.md`** — Shared file conflict detection, risk analysis, and mitigation workflow
- **`references/status-md-reading-strategy.md`** — When to query database vs read STATUS.md vs full file reads
- **`references/review-checklists.md`** — Subagent FACTS checklist, conductor STRATEGY checklist, smoothness scale, context situation checklist, score aggregation
- **`references/subagent-failure-handling.md`** — Failure categories, retry decision flowchart, escalation message format
- **`references/orchestration-principles.md`** — Context headroom strategy, external sessions vs subagents, delegation patterns, overload indicators
- **`references/session-handoff.md`** — Handoff procedures (clean/dirty/crash), worked_by succession, guard clause re-claiming, high-context verification rule
- **`references/recovery-instructions-template.md`** — Simple template for Recovery Instructions format
- **`references/musician-launch-prompt-template.md`** — Kitty launch command template for execution sessions

### Example Files

- **`examples/conductor-initialization.md`** — Complete setup workflow with all 9 steps
- **`examples/launching-execution-sessions.md`** — Parallel launch with user instructions and CLI flags
- **`examples/review-approval-workflow.md`** — Review detection, approval, and rejection flow with SQL
- **`examples/error-recovery-workflow.md`** — Error detection through fix proposal with SQL
- **`examples/monitoring-subagent-prompts.md`** — Background subagent launch prompts for monitoring
- **`examples/rag-processing-subagent-prompts.md`** — Overlap-check and ingestion subagent prompts for RAG proposal processing
- **`examples/completion-coordination.md`** — Final integration, verification, and reporting

### Scripts

- **`scripts/validate-coordination.sh`** — Check database state, verify table schema, report task statuses
- **`scripts/check-git-branch.sh`** — Verify not on main branch, report current branch name
</core>
</section>

</skill>
