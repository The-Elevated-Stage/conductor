<skill name="conductor-parallel-coordination" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- when-to-use
- key-characteristics
- conductor-workflow
- session-handoff-flow
- error-prioritization
- phase-completion
- execution-session-workflow
- monitoring-subagent-design
- context-budget
</sections>

<section id="when-to-use">
<core>
# Parallel Coordination Pattern

## When to Use

- 3+ independent tasks with no shared file conflicts
- Tasks that can safely run simultaneously
- Phase contains parallel-safe tasks (verified during planning)
</core>
</section>

<section id="key-characteristics">
<core>
## Key Characteristics

- **Custom hook required** on both conductor and execution sessions
- **Background monitoring subagent** watches for state changes
- **Review checkpoints** mandatory at logical points in each task
- **Danger files governance** for any shared resources
- **Full error recovery cycle** with fix proposals and retry tracking
</core>
</section>

<section id="conductor-workflow">
<core>
## Conductor Workflow

### 1. Analyze Phase for Danger Files

Extract inline danger file annotations from the implementation plan:

```markdown
Task 3: Extract Testing Docs
...
⚠️ Danger Files: docs/knowledge-base/testing/ (shared with Task 4)
```

Decide: keep parallel (with mitigation) or move to sequential. See `danger-files-governance.md`.

### 2. Create Task Instructions (Batch)

Launch ONE subagent to create ALL task instructions for the phase using `references/subagent-prompt-template.md`. Include danger file decisions in the Overrides & Learnings section.

### 3. Insert Database Rows

For each task in the phase:
</core>

<template follow="exact">
```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-03', 'watching', 'docs/tasks/task-03.md', datetime('now'));
```
</template>

<core>
### 4. Insert Instruction Messages

For each task:
</core>

<template follow="format">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'TASK INSTRUCTION: docs/tasks/task-03.md
Type: parallel
Phase: 2
Dependencies: none
Danger files:
  - docs/knowledge-base/testing/ (shared with task-04)',
    'instruction'
);
```
</template>

<core>
### 5. Launch Verification Watcher

**Before launching kitty windows**, start a background verification watcher subagent to confirm all sessions claim their tasks. See `examples/monitoring-subagent-prompts.md` (Launch Verification Watcher section) for the prompt template. This ensures monitoring is active before execution sessions start.

### 6. Launch Kitty Windows
</core>

<mandatory>Use the musician skill launch prompt template for each session. See `references/musician-launch-prompt-template.md` for the complete template and fill-in instructions.</mandatory>

<core>
Launch one kitty window per task via the Bash tool. Use parallel Bash calls so all sessions start simultaneously:
</core>

<template follow="exact">
```bash
# Task 03
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
```
</template>

<context>
```bash
# Task 04 (launched in parallel via separate Bash call)
kitty --directory /home/kyle/claude/remindly --title "Musician: task-04" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician
...same template with task-04..." &
```

```bash
# Task 05 and task-06 follow the same pattern
```

**Launch notes:**
- Each `kitty --directory /home/kyle/claude/remindly --title "..." -- env -u CLAUDECODE claude --permission-mode acceptEdits "..."` opens a new OS window running claude with the musician prompt
- The `&` suffix detaches kitty so the Bash call returns immediately
- Use parallel Bash tool calls (one per kitty window) for simultaneous launch
- `--continue` resumes the most recent conversation in cwd
- `--resume [session-id]` resumes a specific session (or opens picker)
</context>

<core>
### 7. Launch Main Monitoring Subagent

After verification watcher confirms all tasks reached `working`, start the main background monitoring subagent that polls `orchestration_tasks` for state changes. See `examples/monitoring-subagent-prompts.md`.

### 8. Handle Events

When monitoring subagent reports back, handle in this order: errors first, then reviews, then completions.

- **`error`** — Read error report, analyze, propose fix or escalate. Check if `last_error = 'context_exhaustion_warning'` — if so, follow context warning protocol (see SKILL.md Context Warning Protocol).
- **`needs_review`** — Read message, review proposal, approve or reject
- **`complete`** — Read completion report, verify deliverables, update STATUS.md
- **`exited`** — Musician session terminated. Follow session handoff procedure in `references/session-handoff.md`. May be clean exit (HANDOFF present), crash (no HANDOFF), or retry exhaustion (conductor error).
- **All tasks complete** — Phase is done, proceed to next phase

After handling each event, relaunch the monitoring subagent to continue watching.
</core>

<guidance>
**Emergency broadcasts:** If you need to send a critical message to all parallel tasks (shared file conflict, user-requested pause), issue ONE INSERT per task_id with `message_type = 'emergency'`. Each musician's watcher detects via its own task's message log:

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-03', 'task-00', 'EMERGENCY: [critical message]', 'emergency');

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-04', 'task-00', 'EMERGENCY: [critical message]', 'emergency');

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-05', 'task-00', 'EMERGENCY: [critical message]', 'emergency');

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-06', 'task-00', 'EMERGENCY: [critical message]', 'emergency');
```
</guidance>
</section>

<section id="session-handoff-flow">
<core>
### 8a. Session Handoff Flow

When an musician session exits (clean, dirty, or crash):

1. **Detect via monitoring** — Check task state = `exited` or heartbeat stale (>540 seconds)
2. **Read HANDOFF file** — Parse `temp/task-{NN}-HANDOFF` (if present; indicates clean exit)
3. **Assess handoff type**:
   - **Clean:** HANDOFF present, context <80% — standard recovery
   - **Dirty:** HANDOFF present, context >80% — include test verification instructions
   - **Crash:** No HANDOFF — construct recovery from `temp/task-{NN}-status` and most recent conductor messages
4. **Set state to `fix_proposed`** — Mark task ready for replacement session to claim
5. **Send handoff message** — Include recovery instructions in `orchestration_messages` with `message_type = 'handoff'`
6. **Launch replacement** — Launch a new kitty window for the replacement session via Bash tool. See `references/musician-launch-prompt-template.md` (Launching Replacement Sessions) for the handoff template. Notify user that a replacement session was launched.

**Worked_by succession:** Each retry increments: `musician-task-{NN}` → `musician-task-{NN}-S2` → `musician-task-{NN}-S3`
</core>
</section>

<section id="error-prioritization">
<core>
### 8b. Error Prioritization During Monitoring

When monitoring subagent detects multiple pending events, process in this order:

1. **Errors first** — Task in `error` state (blocking musician, requires immediate fix)
2. **Reviews second** — Task in `needs_review` state (blocking musician, may approve or reject)
3. **Completions last** — Task reporting `complete` (non-blocking, can be processed after errors/reviews)

This priority prevents cascading delays when errors accumulate across parallel tasks.
</core>
</section>

<section id="phase-completion">
<core>
### 9. Phase Completion

When all tasks in the phase reach `complete` or `exited`:

1. Check for proposals in both locations:
   - `docs/implementation/proposals/` (general proposals)
   - `docs/proposals/claude-md/` (learnings proposals)
2. Verify no proposals stuck in `temp/`
3. Integrate critical proposals, defer non-critical
4. Update STATUS.md phase status
5. Proceed to next phase
</core>
</section>

<section id="execution-session-workflow">
<core>
## Execution Session Workflow (Parallel)

The execution session follows the parallel task template:

1. **Hooks self-configure** — SessionStart hook injects `$CLAUDE_SESSION_ID` into system prompt. Stop hook (via `hooks.json` preset configuration) monitors for state changes. No manual setup needed.
2. **Claim task** — Atomic UPDATE with guard clause
3. **Launch background subagent** — Monitor for conductor messages
4. **Execute steps** — Work through instruction
5. **Review checkpoint** — Set `needs_review`, launch blocking subagent to wait for response
6. **Process review** — Apply feedback from `review_approved` or `review_failed`
7. **Complete** — Set `complete`, write completion report, terminate subagent
</core>
</section>

<section id="monitoring-subagent-design">
<core>
## Monitoring Subagent Design

The monitoring subagent is a **non-blocking** background agent launched by the conductor:
</core>

<template follow="format">
```
Task("Monitor Phase 2 tasks", prompt="""
Poll orchestration_tasks every 30 seconds using comms-link query.
Check staleness: if any task state is 'working' or 'review_approved'/'review_failed'/'fix_proposed' and last_heartbeat >540 seconds old, report as stale.
Check for state changes in: task-03, task-04, task-05, task-06.
Detect fallback rows (task_id LIKE 'fallback-%'). If found, compare timestamps: if fallback.last_heartbeat >= original_task.last_heartbeat, report collision (task not worked since).
Also refresh conductor heartbeat: UPDATE orchestration_tasks SET last_heartbeat = datetime('now') WHERE task_id = 'task-00';
Report back immediately when any task reaches: needs_review, error, complete, exited, or when stale/fallback detected.
Include the task_id, new state, and any recent messages.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</template>

<context>
When the subagent reports, the conductor handles the event and relaunches monitoring.
</context>
</section>

<section id="context-budget">
<context>
## Context Budget for Parallel Phases

Typical context costs per phase:
- Task instruction creation subagent: one-time, not retained
- Monitoring subagent: minimal (small prompts, background)
- Review processing: ~2-5k tokens per review (read message + proposal)
- Error handling: ~3-8k tokens per error (read report + analysis)

Budget for a 4-task phase: ~20-40k tokens of conductor context.
</context>
</section>

</skill>
