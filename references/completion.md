<skill name="conductor-completion" version="3.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Completion Protocol
</metadata>

<sections>
- completion-workflow
- verify-all-tasks
- read-completion-reports
- verify-deliverables
- check-proposals
- integrate-proposals
- decisions-cleanup
- prepare-pr
- report-to-user
- close-musician-windows
- set-conductor-complete
- terminal-state-rules
- smoothness-aggregation
</sections>

<section id="completion-workflow">
<core>
# Completion Protocol

When all tasks in all phases reach terminal state (`complete` or `exited`), execute these steps in order:

1. Verify all tasks have reached terminal state
2. Read completion reports from each task
3. Verify all expected deliverables are present
4. Check for unprocessed proposals
5. Integrate proposals (CLAUDE.md additions, memory entities, RAG entries)
6. Clean up the decisions directory
7. Prepare PR (review commits, check for sensitive data)
8. Report to user with deliverables and recommendations
9. Close all remaining Musician kitty windows — return to SKILL.md and locate the Musician Lifecycle Protocol for cleanup
10. Set conductor state to `complete`

<mandatory>Step 8 is the one point where the Conductor pauses for user input. The orchestration is complete — the user decides whether to merge, create PR, or adjust. All prior steps are autonomous.</mandatory>
</core>
</section>

<section id="verify-all-tasks">
<core>
## Step 1: Verify All Tasks Complete

<template follow="exact">
```sql
SELECT task_id, state, completed_at, report_path
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```
</template>

All tasks must be in terminal state (`complete` or `exited`). If any task is `exited` rather than `complete`, note it for the completion report but continue with integration — `exited` tasks had clean handoffs or were intentionally terminated.

If any task is still in a non-terminal state, do not proceed. Investigate via the Error Recovery Protocol (via SKILL.md).
</core>
</section>

<section id="read-completion-reports">
<core>
## Step 2: Read Completion Reports

Read each task's completion report (path from `report_path` column). Compile:
- Deliverables list across all tasks
- Smoothness scores across all tasks (see smoothness-aggregation section)
- Any issues or warnings flagged in reports
- Files created and modified across all tasks
</core>
</section>

<section id="verify-deliverables">
<core>
## Step 3: Verify Deliverables

```bash
# Git status is clean (no uncommitted changes)
git status
git diff --stat

# Check for files stranded in temp/ that should be elsewhere
ls -la temp/

# Verify expected output files exist (paths from completion reports)
```

Run the project's test suite:

```bash
# Backend tests
npm test

# Frontend tests (if applicable)
# dart test
```

All tests must pass. If tests fail, investigate before proceeding — do not create a PR with failing tests. Route to Error Recovery Protocol if needed.
</core>
</section>

<section id="check-proposals">
<core>
## Step 4: Check for Unprocessed Proposals

```bash
# General proposals
ls -la docs/implementation/proposals/

# Verify nothing stuck in temp/
ls -la temp/*.md 2>/dev/null
```

Identify any proposals that were created by Musicians but not yet processed during review cycles. All proposals should be triaged before completion.
</core>
</section>

<section id="integrate-proposals">
<core>
## Step 5: Integrate Proposals

Process each proposal by type:
- **CLAUDE.md additions** — integrate immediately, verify no conflicts with existing rules
- **Memory entities** — add to memory graph via create_entities/add_observations
- **RAG entries** — verify ingested via local-rag tools
- **Non-critical proposals** — note for user in the completion report, defer decision

<mandatory>The Conductor integrates proposals autonomously. It does not ask the user to approve each proposal individually — it uses its judgment based on the plan's goals and existing project conventions.</mandatory>
</core>
</section>

<section id="decisions-cleanup">
<core>
## Step 6: Decisions Directory Cleanup

After the user confirms completion (merge or PR created), clean up the decisions directory used during planning:

```bash
# Remove the feature's decisions directory
rm -rf docs/plans/designs/decisions/{feature-name}/
```

This directory contained:
- Dramaturg journal
- Arranger journal
- Any Repetiteur consultation journals
- Blocker reports

These are planning artifacts that served their purpose. The implementation plan and its git history are the durable record.

<guidance>
If Repetiteur consultations occurred (journals exist in `decisions/{feature-name}/`), preserve the decision journals directory as reference. Otherwise, clean up the entire `decisions/{feature-name}/` directory to prevent accumulation across features.
</guidance>
</core>
</section>

<section id="prepare-pr">
<core>
## Step 7: Prepare PR

```bash
# Review all commits on the feature branch
git log --oneline main..HEAD

# Check for sensitive data in the diff
git diff main --stat
```

<template follow="format">
**Title:** [type]([scope]): [concise description]

**Description:**
## Summary
- [Key accomplishment 1]
- [Key accomplishment 2]
- [Key accomplishment 3]

## Tasks Completed
- [Task list with brief descriptions]

## Test Plan
- [ ] [Verification item 1]
- [ ] [Verification item 2]
- [ ] [Verification item 3]
</template>
</core>
</section>

<section id="report-to-user">
<core>
## Step 8: Report to User

<mandatory>This is the one interactive gate in the completion flow. Present the report and wait for the user's decision on how to proceed (merge, PR, adjust).</mandatory>

<template follow="format">
Implementation complete.

**Deliverables:**
- [Count] files created/modified across [count] sections
- [Count] completion reports in docs/implementation/reports/
- [Count] proposals integrated
- Feature branch: [branch-name]

**Statistics:**
- [Count] tasks completed ([count] exited)
- Average smoothness: [score]/9
- Review cycles: [count]
- Repetiteur consultations: [count or "none"]

**Recommendations:**
- [Recommendation 1]
- [Recommendation 2]
</template>
</core>
</section>

<section id="close-musician-windows">
<core>
## Step 9: Close Musician Windows

Close all remaining Musician kitty windows. For each task, read the PID file and terminate:

```bash
kill $(cat temp/musician-{task-id}.pid) 2>/dev/null
rm -f temp/musician-{task-id}.pid
```

Return to SKILL.md and locate the Musician Lifecycle Protocol for the full cleanup mechanics if any windows require special handling (crash recovery, stale PIDs).
</core>
</section>

<section id="set-conductor-complete">
<core>
## Step 10: Set Conductor Complete

After user confirms PR or merge decision:

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET state = 'complete',
    last_heartbeat = datetime('now'),
    completed_at = datetime('now')
WHERE task_id = 'task-00';
```
</template>

The stop hook detects `complete` state and allows the Conductor session to exit normally.
</core>
</section>

<section id="terminal-state-rules">
<context>
## Terminal State Rules

`complete` and `exited` are terminal states for both Conductor and Musician tasks.

**Conductor (task-00):**
- Hook exit criteria: session can only exit when state is `exit_requested` or `complete`

**Musicians (task-01+):**
- Hook exit criteria: session can only exit when state is `complete` or `exited`

No further state transitions should occur after reaching a terminal state. The post-completion resume pattern (Musician Lifecycle Protocol) creates a NEW task row rather than modifying a completed one.
</context>
</section>

<section id="smoothness-aggregation">
<core>
## Smoothness Score Aggregation

Track smoothness scores across all tasks for the completion report:

<template follow="format">
Phase [N] Smoothness Summary:
  task-[NN]: [score]/9 ([description])
  task-[NN]: [score]/9 ([description])
  Average: [score]/9
  Worst: [score]/9
</template>

<guidance>
Interpretation:
- Average 0-3: Plan and instructions are high quality
- Average 3-5: Plan is adequate but instructions could be more precise
- Average 5+: Systemic issue worth investigating
- Single outlier 7+: Task-specific issue, not a plan problem

Include aggregated scores in the completion report to give the user visibility into execution quality.
</guidance>
</core>
</section>

</skill>
