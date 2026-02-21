<skill name="conductor-example-error-recovery-workflow" version="3.0">

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- scenario
- read-error-message
- read-error-report
- analyze-and-decide
- propose-fix
- execution-processes-fix
- resume-monitoring
- alternative-complex-error
- alternative-context-exhaustion
- alternative-terminal-error
</sections>

<section id="scenario">
<context>
# Example: Error Recovery Workflow

This example shows the conductor handling an error from an execution session.

## Scenario

Monitoring subagent reports: "task-05 state changed to error, retry_count = 1"
</context>
</section>

<section id="read-error-message">
<core>
## Step 1: Read Error Message

```sql
SELECT task_id, from_session, message, timestamp
FROM orchestration_messages
WHERE task_id = 'task-05'
ORDER BY timestamp DESC
LIMIT 1;
```

Result:
```
task-05 | c1d2e3f4-5a6b-7c8d-9e0f-1a2b3c4d5e6f | ERROR (Retry 1/5): Test failed after implementation
 Error: grep verification failed for kb-database-migration.md
 Expected: Contains "## Migration Patterns" heading
 Actual: File exists but heading is "## Database Migration Patterns"
 Report: docs/implementation/reports/task-05-error-retry-1.md
 Key Outputs:
   - docs/implementation/reports/task-05-error-retry-1.md (created)
 Awaiting conductor fix proposal
```
</core>
</section>

<section id="read-error-report">
<core>
## Step 2: Read Error Report

Read `docs/implementation/reports/task-05-error-retry-1.md` for detailed context:

- Error type: Verification failure
- Step: Step 4 (verification)
- Context: File was created correctly but heading doesn't match expected format
- Stack trace: N/A (grep mismatch)
- Retry count: 1 of 5
- Suggested fix: Update verification pattern or fix heading
</core>
</section>

<section id="analyze-and-decide">
<core>
## Step 3: Analyze and Decide

Decision tree:
- **Simple fix?** Yes — heading mismatch is a naming convention issue
- **Action:** Propose fix with correct heading
</core>
</section>

<section id="propose-fix">
<core>
## Step 4: Propose Fix

```sql
-- Set fix_proposed state
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-05';

-- Send fix proposal
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-05', 'task-00',
    'FIX PROPOSAL (Retry 1/5):
     Root cause: Heading format mismatch. Convention is "## Migration Patterns"
                 (category name only), not "## Database Migration Patterns" (full name).
     Fix: Update kb-database-migration.md heading from
          "## Database Migration Patterns" to "## Migration Patterns"
     Verification: Re-run grep check after fix
     Reference: See knowledge-base/README.md for heading convention',
    'fix_proposal'
);
```
</core>
</section>

<section id="execution-processes-fix">
<core>
## Step 5: Execution Session Processes Fix

The execution session:
1. Reads the fix proposal message
2. Applies the fix (changes heading)
3. Re-runs verification
4. Sets state back to `working`:

```sql
UPDATE orchestration_tasks
SET state = 'working', last_heartbeat = datetime('now')
WHERE task_id = 'task-05';
```
</core>
</section>

<section id="resume-monitoring">
<core>
## Step 6: Resume Monitoring

Relaunch monitoring subagent. Execution session continues with remaining steps.
</core>
</section>

<section id="alternative-complex-error">
<core>
## Alternative: Complex Error (Retry 3+)

If the error is more complex or recurring:

### Read Error Report (Retry 3)

```
ERROR (Retry 3/5): Same verification failure after 2 fix attempts
 Previous fixes: heading change (retry 1), full file regeneration (retry 2)
 Error persists: grep pattern may be wrong
```

### Autonomous Investigation

After 3 failed retries, the Conductor launches an investigation teammate rather than prompting the user:

```
Launch teammate to investigate: "Task-05 has failed verification 3 times.
 Previous fixes: heading change (retry 1), full file regeneration (retry 2).
 Error persists — grep pattern may be wrong.

 Investigate:
 1. Read the task instruction file for the expected verification pattern
 2. Read the actual generated file
 3. Determine if the verification pattern is wrong or the file content is wrong
 4. Propose a specific fix with evidence"
```

Based on teammate findings, classify and respond:
- If verification pattern is wrong → propose fix to update the pattern
- If file content is persistently wrong → escalate to Repetiteur Protocol (via SKILL.md)
- If root cause is ambiguous after investigation → escalate to Repetiteur Protocol (via SKILL.md)
</core>
</section>

<section id="alternative-context-exhaustion">
<core>
## Alternative: Context Exhaustion Warning

### Execution Session Reports Context Warning

Musician reports context usage >65% with remaining work. Task state = `error` with `last_error = 'context_exhaustion_warning'`.

Musician message includes:
```
CONTEXT WARNING: 72% usage
  Self-Correction: YES
  Agents Remaining: 2 (~18% each, ~36% total)
  Agents That Fit in 65% Budget: 1
  Deviations: 1 (switched parsing strategy)
  Proposal: Prepare clean handoff at step 3.5, can resume in new session
  Awaiting conductor instructions
```

### Conductor Response to Context Warning

When monitoring detects `last_error = 'context_exhaustion_warning'`:

```sql
-- Assess handoff need from musician's message above (context_usage, self_correction, deviations)
-- If no sufficient budget for remaining work:
UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = 'task-05';

-- Send context handoff message
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-05', 'task-00',
    'CONTEXT EXIT APPROVED:
     Current usage: 72%, insufficient for 2 remaining agents (~36%)
     Conductor decision: Prepare clean handoff and exit
     Handoff location: temp/task-05-HANDOFF
     Next session: musician-task-05-S2 will resume from step 3.5
     Re-verify step 3 completion before resuming agents',
    'fix_proposal'
);
```

### New Session Resumes from Handoff

The continuation session (S2):

```sql
-- Send clean handoff message
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-05', 'task-00',
    'CONTEXT HANDOFF (Retry 2/5):
     Status: Error recovery in progress
     Current action: Processing fix proposal from Retry 1
     Worked_By: Continuing with musician-task-05-S2
     Next steps: Apply fix, re-run verification, resume monitoring
     Session ID: [New musician session will use $CLAUDE_SESSION_ID]',
    'handoff'
);

-- Musician uses worked_by succession pattern
UPDATE orchestration_tasks
SET worked_by = 'musician-task-05-S2'
WHERE task_id = 'task-05';
```

### New Session (S2) Resumes

The continuation session:
1. Reads the CONTEXT HANDOFF message
2. Checks current `state` and `last_error`
3. Applies the fix proposal (if state = fix_proposed)
4. Continues error recovery from where S1 left off
</core>
</section>

<section id="alternative-terminal-error">
<core>
## Alternative: Terminal Error (Retry 5)

Execution session self-exits after 5th retry:

```sql
-- Execution session sets this automatically
UPDATE orchestration_tasks
SET state = 'exited', last_heartbeat = datetime('now'),
    last_error = 'Retry limit exhausted (5/5): Verification mismatch persists'
WHERE task_id = 'task-05';
```

Conductor detects via monitoring:

```
Task-05 has exited after exhausting 5 retries.
Last error: Verification mismatch persists

Options:
1. Retry manually (create new task instruction)
2. Skip this task (proceed without these deliverables)
3. Investigate root cause before deciding

Recommend: Option 3 — read the task instruction and error reports
to understand if the verification pattern is wrong.
```
</core>
</section>

</skill>
