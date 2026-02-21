<skill name="conductor-review-checklists" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- checklist-overview
- subagent-self-review
- conductor-review
- execution-task-completion-review
- status-md-template
</sections>

<section id="checklist-overview">
<core>
# Review Checklists

Three review checklists serve different purposes at different points in the orchestration lifecycle. Apply the correct checklist for the context.

## When to Apply Each Checklist

| Checklist | Who Runs It | When | Purpose |
|-----------|------------|------|---------|
| Subagent Self-Review (FACTS) | Task instruction subagent | Before returning instructions to conductor | Catch factual errors in generated instructions |
| Conductor Review (STRATEGY) | Conductor | After receiving task instructions from subagent | Catch strategic misalignments with plan goals |
| Execution Task Completion | Conductor | When execution session submits `needs_review` or `complete` | Evaluate quality and decide approve/reject |
</core>
</section>

<section id="subagent-self-review">
<core>
## Subagent Self-Review Checklist (FACTS Focus)

The task instruction creation subagent runs this checklist before returning results. Focus is on **factual correctness** — does the instruction file contain everything needed for autonomous execution?

1. **All required sections present?** — Verify template sections exist (Initialization, Steps, Completion, Error Recovery). Sequential tasks need Completion section. Parallel tasks need Hook setup, Background subagent, Review checkpoint.
2. **SQL queries syntactically correct?** — Every SQL statement uses correct table names (`orchestration_tasks`, `orchestration_messages`), includes `last_heartbeat = datetime('now')` on state changes, uses single quotes for strings.
3. **File paths match implementation plan?** — Source paths, target paths, and deliverable paths match what the plan specifies. No invented directories.
4. **Hook self-configuration noted?** — Hooks self-configure via `hooks.json` (stop hook preset detection) and SessionStart hook (session ID injection). No manual setup.sh step. Instruction should note that SessionStart hook injects `$CLAUDE_SESSION_ID` into the system prompt automatically.
5. **Dependencies accurately listed?** — Task dependencies from the plan are reflected in the instruction. Danger file annotations carried through.
6. **Verification steps included?** — Each major step has a verification command (ls, grep, git diff, test run). No step produces output without verification.
7. **State transitions correctly specified?** — Atomic claim in Initialization. `needs_review` at checkpoints. `complete` in Completion. `error` in Error Recovery. All with heartbeat.
8. **Completion report format included?** — Completion section writes a report with: deliverables list, files created/modified, smoothness score, issues encountered.

### How to Use

Run through all 8 items sequentially. If any item fails, fix the instruction file before returning to conductor. The validation script (`validate-instruction.sh`) catches some of these automatically, but not strategic issues like dependency accuracy or path correctness.
</core>
</section>

<section id="conductor-review">
<core>
## Conductor Review Checklist (STRATEGY Focus)

The conductor runs this checklist after receiving task instructions from the subagent. Focus is on **strategic alignment** — do these instructions achieve what the plan intends?

1. **Instructions align with overall plan goals?** — Read the plan's stated objectives for this phase. Verify the task instructions actually produce those outcomes, not a close approximation.
2. **Appropriate pattern chosen (sequential vs parallel)?** — If the plan says parallel but danger files are severe, the subagent should have flagged this. If sequential was chosen for independent tasks, question the choice.
3. **Task dependencies make sense in project context?** — Cross-check: does task-04 actually depend on task-03's output? Are the dependencies real or assumed?
4. **Review checkpoints at logical points?** — Checkpoints should be after significant deliverables, not after trivial steps. One checkpoint per 3-5 substantive steps is typical.
5. **Template compliance?** — All sections from the selected template are present. Inapplicable sections are marked N/A with a reason, not omitted.
6. **Verification adequate for deliverables?** — Each deliverable has a corresponding verification. Verification is specific (grep for exact content, ls for exact path), not vague ("check that it works").
7. **Integration with other tasks considered?** — For parallel tasks: danger file mitigations present. For sequential tasks: output from previous task used as input where needed. Cross-references to other tasks are accurate.

### How to Use
</core>

<guidance>
Review items 1, 2, and 3 first — these catch the highest-impact issues. Items 4-7 are refinements. If items 1-3 pass but 4-7 have minor issues, approve with notes rather than rejecting.
</guidance>
</section>

<section id="execution-task-completion-review">
<core>
## Execution Task Completion Review

When an execution session sets state to `needs_review` or `complete`, the conductor evaluates using the **smoothness scale (0-9)**.

### Context Situation Checklist

Before approving or rejecting, check these context situation factors:

- **Self-correction flag active?** If YES, context estimates are unreliable (~6x bloat). Compare actual context usage to task instruction estimates. If actual >> estimated, musician may lose track of progress.
- **Context usage vs. task estimates?** Report actual context % used vs. estimated in instruction. Warn if actual >2x estimated — musician may be thrashing or subagents may be inefficient.
- **Deviations present and severity?** Count: how many steps deviated, how critical were they to the deliverable?
- **Distance to next checkpoint?** How many steps remain to next logical review point?
- **Agents remaining and estimated cost?** How many subagents are left in the queue, and what's the estimated context cost per agent?
- **Prior context warnings on this task?** If this is the 2nd or 3rd context warning, escalate sooner.

Use this checklist alongside the Smoothness Scale to make informed decisions.

### Smoothness Scale

| Score | Meaning | Typical Indicators |
|-------|---------|-------------------|
| 0 | Perfect execution, no deviations | All steps completed as written, all verifications pass, no conductor interaction needed |
| 1-2 | Minor clarifications, self-resolved | Small ambiguity in instructions resolved by execution session, minor path adjustment, trivial fix applied |
| 3-4 | Some deviations from plan, documented | Execution session adapted approach for unforeseen circumstance, documented reasoning, deliverables still match expectations |
| 5-6 | Significant issues, required conductor input | One or more review cycles with feedback, error recovery needed, some deliverables modified from original spec |
| 7-8 | Major blockers, multiple review cycles | Repeated review failures, fundamental approach issues, significant deliverable changes, multiple error retries |
| 9 | Failed or incomplete, needs redesign | Task cannot be completed as specified, instruction quality insufficient, requires re-planning |

### Decision Thresholds

| Score Range | Action | State Transition | Message Content |
|-------------|--------|-----------------|-----------------|
| **0-4** | Approve | `review_approved` | Brief acknowledgment, note any minor observations |
| **5** | Investigate, then approve | `fix_proposed` if errors found, then `review_approved` | Read full proposal/report, correct errors before approving |
| **6-7** | Request revision | `review_failed` | Specific issues to address, expected corrections, reference to relevant standards |
| **8-9** | Reject | `review_failed` | Detailed rejection explaining what went wrong, required changes, whether task needs redesign |

### Interpreting Scores in Context

- **Self-reported scores** from execution sessions are starting points. Conductor validates by reading the proposal or completion report.
- **Score inflation** is common — execution sessions may report 2 when issues suggest 4. Adjust based on evidence in the report.
- **Score context matters** — A smoothness of 4 on a complex refactoring task is good. A smoothness of 4 on a simple file copy task indicates instruction quality issues.

### Score Aggregation Across Tasks

Track smoothness scores across all tasks in a phase to assess plan quality:

```
Phase 2 Smoothness Summary:
  task-03: 2/9 (testing extraction)
  task-04: 3/9 (API extraction)
  task-05: 1/9 (database extraction)
  task-06: 4/9 (architecture extraction)
  Average: 2.5/9
  Worst: 4/9
```
</core>

<guidance>
**Interpretation guidelines:**
- **Average 0-3:** Plan and instructions are high quality. Proceed confidently.
- **Average 3-5:** Plan is adequate but instructions could be more precise. Note patterns for future improvement.
- **Average 5+:** Systemic issue. Investigate whether the plan was underspecified, instructions were unclear, or task scope was too large.
- **Single outlier 7+:** Task-specific issue, not systemic. Investigate that task independently.

Include aggregated scores in the final completion report to the user. This helps assess orchestration quality over time.
</guidance>
</section>

<section id="status-md-template">
<core>
## STATUS.md Template (Conductor Session Log)

Create a persistent STATUS.md at the project root to track orchestration progress:
</core>

<template follow="format">
```markdown
# Orchestration Status — [YYYY-MM-DD HH:MM]

**Conductor Session:** $CLAUDE_SESSION_ID
**Database:** comms.db
**Hook Configuration:** hooks.json (stop hook preset detection enabled)

## Task Status Summary

| Task | State | Worked By | Smoothness | Checkpoints | Context % | Notes |
|------|-------|-----------|-----------|-------------|-----------|-------|
| task-00 | watching | conductor | — | — | — | Conductor monitoring |
| task-03 | working | musician-task-03 | N/A | 2/5 | 34% | In progress: step 3 agent 1 |
| task-04 | needs_review | musician-task-04 | 2/9 | 3/4 | 41% | Awaiting approval |
| task-05 | complete | musician-task-05 | 1/9 | 4/4 | 28% | Completed checkpoint N |

## Phases

### Phase 1 (Sequential): Foundation
- Status: Complete
- Tasks: task-01, task-02
- Completion: 2026-02-04 10:30 UTC

### Phase 2 (Parallel): Knowledge Extraction
- Status: In Progress (ETA: 2026-02-05 14:00)
- Tasks: task-03, task-04, task-05, task-06
- Started: 2026-02-04 14:15 UTC

## Recent Events

- 14:32 — task-04 submitted for review (smoothness 2/9, context 41%)
- 14:25 — task-03 hit self-correction flag, estimated context to checkpoint: +12%
- 14:15 — All phase 2 musicians launched

## Recovery Instructions

**If conductor exits:**
1. Query comms.db: `SELECT task_id, state, worked_by, last_heartbeat FROM orchestration_tasks`
2. For any task in non-terminal state: create handoff message in orchestration_messages (message_type = 'handoff')
3. Notify user to launch replacement conductor session with `--resume [session-id]` flag

**If musician exits unexpectedly:**
1. Conductor detects stale heartbeat (>540 seconds) via monitoring subagent
2. Conductor reads temp/task-{NN}-HANDOFF (if present)
3. Conductor sets task state to `fix_proposed`
4. User launches replacement musician: `claude "Resume task-{NN}..."`
```
</template>

<guidance>
Keep STATUS.md updated during monitoring cycles. Include session ID (`$CLAUDE_SESSION_ID` from system prompt) for resumption tracking.
</guidance>
</section>

</skill>
