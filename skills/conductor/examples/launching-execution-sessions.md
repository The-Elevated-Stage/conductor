<skill name="conductor-example-launching-execution-sessions" version="4.0">

<context>
**Note (v5.0):** This example predates the universality update. It shows hardcoded kitty/remindly paths and inline prompt arguments — these are replaced by the session layer (references/session-layer.md), prompt files (temp/task-XX-prompt.txt), and configuration system. The workflow concepts remain valid; the specific commands should use the session layer from references/phase-execution.md.
</context>

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- scenario
- verify-database
- insert-instruction-messages
- launch-verification-watcher
- launch-sessions
- wait-for-events
- phase-complete
</sections>

<section id="scenario">
<context>
# Example: Launching Execution Sessions

This example shows how to launch parallel execution sessions for Phase 2 (4 parallel tasks).

## Scenario

Phase 2 tasks are ready:
- task-03: Extract Testing Docs (parallel)
- task-04: Extract API Docs (parallel)
- task-05: Extract Database Docs (parallel)
- task-06: Extract Architecture Docs (parallel)

Task instructions created and validated. Database rows inserted.
</context>
</section>

<section id="verify-database">
<core>
## Step 1: Verify Database State

```sql
SELECT task_id, state, instruction_path
FROM orchestration_tasks
WHERE task_id IN ('task-03', 'task-04', 'task-05', 'task-06');
```

Expected:
```
task-03 | watching | docs/tasks/task-03.md
task-04 | watching | docs/tasks/task-04.md
task-05 | watching | docs/tasks/task-05.md
task-06 | watching | docs/tasks/task-06.md
```
</core>
</section>

<section id="insert-instruction-messages">
<core>
## Step 2: Insert Instruction Messages

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES
    ('task-03', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-03.md
Type: parallel
Phase: 2
Dependencies: none
Danger files:
  - knowledge-base/testing/README.md (shared with task-04)', 'instruction'),
    ('task-04', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-04.md
Type: parallel
Phase: 2
Dependencies: none
Danger files:
  - knowledge-base/testing/README.md (cross-refs from task-03)', 'instruction'),
    ('task-05', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-05.md
Type: parallel
Phase: 2
Dependencies: none
Danger files: none', 'instruction'),
    ('task-06', 'task-00', 'TASK INSTRUCTION: docs/tasks/task-06.md
Type: parallel
Phase: 2
Dependencies: none
Danger files: none', 'instruction');
```
</core>
</section>

<section id="launch-verification-watcher">
<core>
## Step 3: Launch Verification Watcher

Launch before kitty windows so monitoring is active when sessions start:

```python
Task("Verify execution sessions launched successfully", prompt="""
Verify that all execution sessions launched and claimed their tasks.

**Tasks to verify:** task-03, task-04, task-05, task-06

Poll every 15 seconds for up to 5 minutes:
SELECT task_id, state, last_heartbeat
FROM orchestration_tasks
WHERE task_id IN ('task-03', 'task-04', 'task-05', 'task-06')
ORDER BY task_id;

Success: All tasks reach 'working' within 5 minutes → exit and report.
Failure: Any remain 'watching' after 5 minutes → report which failed.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```
</core>
</section>

<section id="launch-sessions">
<core>
## Step 4: Launch Sessions

Write prompts to files and launch via session layer. Task 1 uses the long-term primary window; tasks 2-N get temporary windows.
</core>

<mandatory>Use the musician skill launch prompt template for each session. See references/phase-execution.md → musician-launch for the canonical template.</mandatory>

<core>
```bash
# Write prompt files
cat > temp/task-03-prompt.txt << 'PROMPT'
/musician

Load the musician skill first, then proceed.

**Your task:**
Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = 'task-03' AND message_type = 'instruction';
Read the returned message. Follow every step exactly.

**Context:**
- Task ID: task-03
- Phase: 2 — Extraction Tasks
PROMPT

# Same pattern for task-04, task-05, task-06 prompt files

# Launch via session layer
source scripts/session-commands.sh

# Task-03: primary window (long-term, reused across phases)
create_session "musician-primary" "$PROJECT_DIR"
ATTACH_CMD=$(get_terminal_cmd "musician-primary")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Musician: primary" --dir "$PROJECT_DIR" --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-musician-primary.pid
inject_session "musician-primary" \
    "env -u CLAUDECODE claude --permission-mode $MUSICIAN_PERMISSIONS -p \"\$(cat temp/task-03-prompt.txt)\""

# Task-04: temporary parallel window
create_session "musician-task-04" "$PROJECT_DIR"
ATTACH_CMD=$(get_terminal_cmd "musician-task-04")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Musician: task-04" --dir "$PROJECT_DIR" --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-musician-task-04.pid
inject_session "musician-task-04" \
    "env -u CLAUDECODE claude --permission-mode $MUSICIAN_PERMISSIONS -p \"\$(cat temp/task-04-prompt.txt)\""

# Same pattern for task-05 and task-06 as temporary windows
```

All sessions coordinate autonomously via comms-link database.
</core>

<context>
**Launch notes:**
- `get_terminal_cmd` returns the appropriate attach/loop command for the configured session layer (tmux or FIFO)
- `launch-terminal.sh` opens a terminal window using the configured `TERMINAL_CMD` (kitty, alacritty, foot, etc.)
- `inject_session` sends the claude command into the session — for tmux this uses `send-keys`, for FIFO it writes to the named pipe
- The verification watcher (step 3) is already running and will confirm all sessions claimed their tasks
</context>
</section>

<section id="wait-for-events">
<core>
## Step 5: Wait for Events

The monitoring subagent runs in the background. When it reports, handle the event:
- `needs_review` → See `review-approval-workflow.md`
- `error` → See `error-recovery-workflow.md`
- `complete` → Read completion report
- After handling, relaunch monitoring subagent for remaining tasks
</core>
</section>

<section id="phase-complete">
<core>
## Phase Complete

When all 4 tasks reach `complete` or `exited`:
1. Check for proposals in `docs/implementation/proposals/`
2. Verify no proposals in `temp/`
3. Proceed to Phase 3
</core>
</section>

</skill>
