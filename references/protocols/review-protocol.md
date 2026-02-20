<skill name="conductor-review-protocol" version="3.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Review Protocol
</metadata>

<sections>
- review-workflow
- self-correction-handling
- smoothness-scale
- decision-thresholds
- context-situation-checklist
- review-loop-tracking
- review-approval-sql
- review-rejection-sql
- review-request-format
- checklist-overview
- subagent-self-review-checklist
- conductor-strategy-checklist
- score-aggregation
- review-state-transitions
- eager-rag-trigger
- rag-processing-workflow
</sections>

<section id="review-workflow">
<mandatory>
# Review Protocol

## Review Workflow

You are the authority. When you identify an error — in task instructions, Musician output, verification results, or review submissions — you MUST correct it. Do not approve work that contains known errors. Do not defer corrections hoping they'll self-correct.
</mandatory>

<core>
When the background watcher detects `needs_review` state and exits:

### Step 1: Identify Task
Query which task(s) have `needs_review` state. Usually one, but check for multiples. If multiple tasks are in `needs_review` simultaneously, handle them in order: pick one at random to start, complete its full review, then check the table again before handling the next.

### Step 2: Read Review Request Message

<template follow="exact">
```sql
SELECT message FROM orchestration_messages
WHERE task_id = '{task-id}' AND message_type = 'review_request'
ORDER BY timestamp DESC LIMIT 1;
```
</template>

The message structure contains: Context Usage (%), Self-Correction (YES/NO), Deviations (count + severity), Agents Remaining (count and %), Proposal (path to file), Summary (accomplishments), Files Modified (count), Tests (status and count), Smoothness (0-9), Reason (why review needed).

### Step 3: Self-Correction Flag Check
See self-correction-handling section. If `Self-Correction: YES`, context estimates are unreliable.

### Step 4: Read Proposal or Report
Read the proposal or report file referenced in the message. Apply context-aware reading strategy: skim message structure first (Context Usage, Self-Correction, Deviations fields). Deep-read proposal only if smoothness >5 or self-correction flag is set.

### Step 5: Review Loop Tracking
See review-loop-tracking section. Cap at 5 cycles per checkpoint.

### Step 6: Evaluate Using Smoothness Scale
See smoothness-scale and decision-thresholds sections.

### Step 7: Send Verdict
Apply the decision threshold. Use the appropriate SQL (review-approval-sql or review-rejection-sql section).

### Step 8: Check for RAG Proposals
If approving a completion review that has RAG proposals (type: `rag-addition` in `docs/implementation/proposals/`), check whether to trigger eager RAG processing. See eager-rag-trigger section.

### Step 9: Return to Phase Execution Protocol
After review completes, return to SKILL.md and locate the Phase Execution Protocol. The monitoring cycle re-entry handles checking for additional state changes and relaunching the watcher.

<mandatory>Background message-watcher must be relaunched after review handling completes. No work proceeds without an active watcher.</mandatory>
</core>
</section>

<section id="self-correction-handling">
<core>
## Self-Correction Flag Handling

When a Musician reports `Self-Correction: YES`:

- Context estimates are unreliable (~6x bloat from self-correction overhead)
- Compare actual context usage to task instruction estimates
- If actual > 2x estimated → the Musician may need an additional session. Factor this into approval decision.
- If actual is inline with estimate → tell Musician to reset flag to false in the approval message: "Set self-correction flag to false — this was minor."

Self-correction is critical planning information. A Musician that self-corrected has consumed significant context on rework — the remaining budget for that session is less than the numbers suggest.
</core>
</section>

<section id="smoothness-scale">
<core>
## Smoothness Scale (0 = smoothest, 9 = roughest)

| Score | Meaning | Typical Indicators |
|-------|---------|-------------------|
| 0 | Perfect execution | Zero deviations, all tests pass first try, no self-corrections |
| 1 | Near-perfect | One minor clarification, self-resolved instantly |
| 2 | Minor bumps | 1-2 small deviations, documented, no impact on deliverables |
| 3 | Some friction | Minor issues required small adjustments |
| 4 | Noticeable deviations | Multiple deviations documented, all resolved |
| 5 | Significant issues | Conductor input was/would be needed for decisions |
| 6 | Multiple problems | Several issues, some required creative solutions |
| 7 | Major blockers | Blocked on something, required multiple attempts |
| 8 | Near-failure | Major blockers, fundamental issues with approach |
| 9 | Failed/incomplete | Cannot complete as specified, needs redesign |

<guidance>
Self-reported scores are starting points — the Conductor verifies by reading the review content. Musicians tend toward slight score inflation (reporting smoother than reality). The deviation count and self-correction flag are more reliable indicators than the self-reported smoothness score.
</guidance>
</core>
</section>

<section id="decision-thresholds">
<core>
## Decision Thresholds

| Score Range | Action | State Transition | Key Rule |
|-------------|--------|-----------------|----------|
| **0-4** | Approve | `review_approved` | Standard approval. If Self-Correction: YES, include "Set self-correction flag to false." |
| **5** | Investigate then approve | Deep-read proposal first | Score 5 means significant issues occurred — do not rubber-stamp. Override the context-aware skim strategy. If you identify errors the Musician missed, correct via the Error Recovery Protocol before approving. |
| **6-7** | Request revision | `review_failed` | Send specific feedback on what needs to change. |
| **8-9** | Reject | `review_failed` | Send detailed rejection with required changes. |

<mandatory>Score 5 always gets a deep read. Do not approve a smoothness-5 submission without reading the full proposal and verifying no actionable errors remain.</mandatory>
</core>
</section>

<section id="context-situation-checklist">
<core>
## Context Situation Checklist

When evaluating a Musician's submission, especially with context warnings or self-correction:

- [ ] Self-correction flag active? (YES = context estimates ~6x bloat)
- [ ] How many deviations and severity? (high severity + high context = risky)
- [ ] How far to next checkpoint? (far = higher risk of more issues)
- [ ] How many agents remain and at what cost? (many + high cost = likely to exceed budget)
- [ ] Prior context warnings on this task? (multiple = pattern of scope creep)
- [ ] Proposed action specificity? (vague = less confidence in the plan)

Use results to inform the approval decision. This checklist applies to both review approvals and context warning responses.
</core>
</section>

<section id="review-loop-tracking">
<core>
## Review Loop Tracking

Track how many review cycles have occurred for this checkpoint:

<template follow="exact">
```sql
SELECT COUNT(*) FROM orchestration_messages
WHERE task_id = '{task-id}' AND message_type = 'review_request';
```
</template>

Cap at 5 review cycles per checkpoint. At cycle 5, the issue is beyond review-level fixes — proceed to SKILL.md and locate the Error Recovery Protocol for deeper investigation. If Error Recovery also exhausts its attempts, the escalation chain continues to the Repetiteur Protocol.

<mandatory>Do not exceed 5 review cycles for a single checkpoint. Repeated rejections indicate a fundamental issue, not a cosmetic one.</mandatory>
</core>
</section>

<section id="review-approval-sql">
<core>
## Review Approval SQL

<template follow="format">
```sql
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'REVIEW APPROVED: {feedback}
     {Optional: Set self-correction flag to false — this was minor.}
     Proceed with remaining steps.',
    'approval'
);
```
</template>
</core>
</section>

<section id="review-rejection-sql">
<core>
## Review Rejection SQL

<template follow="format">
```sql
UPDATE orchestration_tasks
SET state = 'review_failed', last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'REVIEW FAILED (Smoothness: {X}/9):
     Issue: {what is wrong}
     Required: {specific changes needed}
     Retry: {instructions for re-submission}',
    'rejection'
);
```
</template>
</core>
</section>

<section id="review-request-format">
<core>
## Review Request Format (Reference)

This is the format Musicians use to submit reviews. The Conductor reads these — not writes them. Included for reference so the Conductor knows what to expect in each field.

<template follow="format">
REVIEW REQUEST (Smoothness: {X}/9):
  Checkpoint: {N} of {M}
  Context Usage: {XX}%
  Self-Correction: {YES/NO} ({details if YES})
  Deviations: {N} ({severity — description})
  Agents Remaining: {N} (~{X}% each, ~{Y}% total)
  Proposal: {path/to/proposal.md}
  Summary: {what was accomplished}
  Files Modified: {N}
  Tests: {status} ({M} total, {N} new)
  Key Outputs:
    - {path/to/file.md} ({created/modified/rag-addition})
</template>

<mandatory>All 10 fields are required in every review request. If any are missing, note it as a deviation in the review.</mandatory>
</core>
</section>

<section id="checklist-overview">
<core>
## Checklist Overview

| Checklist | Used By | When | Focus |
|-----------|---------|------|-------|
| Subagent Self-Review (FACTS) | Task instruction subagent | Before returning instructions to Conductor | Factual correctness, template compliance |
| Conductor Review (STRATEGY) | Conductor | After receiving task instructions from Copyist | Strategic alignment, plan coherence |
| Execution Task Completion | Conductor | When Musician submits `needs_review` or `complete` | Quality, testing, deliverables |
</core>
</section>

<section id="subagent-self-review-checklist">
<core>
## Subagent Self-Review Checklist (FACTS)

Used by the Copyist subagent to verify task instruction quality before returning to the Conductor:

1. [ ] All template sections present (inapplicable sections marked N/A with reason)
2. [ ] All SQL uses `orchestration_tasks` and `orchestration_messages` (not old table names)
3. [ ] All INSERTs include `message_type` column with valid value
4. [ ] Every state transition includes `last_heartbeat = datetime('now')`
5. [ ] All file paths are explicit and complete
6. [ ] Hook configuration matches task type (sequential vs parallel)
7. [ ] Dependencies listed match prerequisite checks
8. [ ] Verification steps have specific expected outputs
</core>
</section>

<section id="conductor-strategy-checklist">
<core>
## Conductor Strategy Checklist (STRATEGY)

Used by the Conductor to evaluate task instructions received from the Copyist:

1. [ ] Task aligns with implementation plan phase goals
2. [ ] Task type (sequential/parallel) matches phase coordination pattern
3. [ ] Inter-task dependencies are correctly identified and ordered
4. [ ] Checkpoint placement is appropriate (not too early, not too late)
5. [ ] Template compliance (all required sections present)
6. [ ] Verification steps are adequate for the task's scope
7. [ ] Integration considerations addressed (cross-task file conflicts, shared resources)

<guidance>
Items 1-3 are strategic — check these first. Items 4-7 are refinements. If items 1-3 have issues, the task may need redesign rather than correction.
</guidance>
</core>
</section>

<section id="score-aggregation">
<core>
## Score Aggregation

Track smoothness scores across all tasks in a phase:

<template follow="format">
Phase {N} Smoothness Summary:
  task-{NN}: {score}/9 ({description})
  task-{NN}: {score}/9 ({description})
  Average: {score}/9
  Worst: {score}/9
</template>

<guidance>
Interpretation:
- Average 0-3: Plan and instructions are high quality. Proceed confidently.
- Average 3-5: Plan is adequate but instructions could be more precise.
- Average 5+: Systemic issue — investigate plan quality, not just individual tasks.
- Single outlier 7+: Task-specific issue, not a plan problem.

Include aggregated scores in the completion report (see Completion Protocol via SKILL.md).
</guidance>
</core>
</section>

<section id="review-state-transitions">
<core>
## Review State Transitions

Three states are directly involved in the review cycle:

- **`needs_review`** — Set by Musician. Awaiting Conductor review. Musician is paused.
- **`review_approved`** — Set by Conductor. Musician resumes work.
- **`review_failed`** — Set by Conductor. Musician applies feedback and re-submits.

```
working → needs_review → [Conductor: review_approved] → working → ...
working → needs_review → [Conductor: review_failed] → working → needs_review → ...
```

<mandatory>Every state transition MUST include `last_heartbeat = datetime('now')`. Omitting the heartbeat from a state update is a bug.</mandatory>
</core>
</section>

<section id="eager-rag-trigger">
<core>
## Eager RAG Processing Trigger

After approving a completion review that has RAG proposals (`rag-addition` type in `docs/implementation/proposals/`):

1. Check `orchestration_tasks` for other tasks in `needs_review` or `error` state
2. If none pending: launch RAG processing immediately (see rag-processing-workflow section)
3. If other reviews or errors are pending: handle those first — RAG processing must never block review handling
4. Deferred RAG processing will be caught during the next monitoring cycle when no other events are pending

Track pending RAG work in-session (1m context provides ample room) or in a simple `temp/pending-rag.txt` list.
</core>
</section>

<section id="rag-processing-workflow">
<core>
## RAG Processing Workflow

RAG processing has two trigger paths:
- **Eager:** Immediately after a completion review approval when no other events are pending
- **Fallback:** During the monitoring cycle when no reviews or errors need handling

### Three Phases

**Phase 1: Overlap Check (Subagent)**

Launch a teammate to check the RAG proposal against existing knowledge base entries:
- Read the proposal file
- Query local-rag for similar existing content
- Report: duplicate (skip), partial overlap (merge candidate), or unique (ingest)

**Phase 2: Decision (Conductor)**

The Conductor reviews the overlap check results and decides:
- **Unique content:** Approve for ingestion
- **Partial overlap:** Determine whether to merge with existing entry or keep as separate
- **Duplicate:** Skip ingestion, delete proposal file

<mandatory>The Conductor makes RAG decisions autonomously. If uncertain about a merge decision, defer to ingestion as a separate entry — deduplication is cheaper than lost knowledge.</mandatory>

**Phase 3: Ingestion (Subagent)**

Launch a teammate to perform the actual ingestion:
- Read the proposal file
- Execute ingestion via local-rag tools
- Confirm successful ingestion
- Delete the proposal file after successful ingestion

### Interruption Handling

<mandatory>If the background message-watcher detects a state change (review, error, completion) during RAG processing, pause RAG work and handle the event first. RAG processing must never block review or error handling. Resume RAG processing after the event is handled.</mandatory>

If interrupted mid-Phase-2 (decision): note the decision state in temp/ and resume from where you left off.
If interrupted mid-Phase-3 (ingestion): the teammate handles its own completion. Check results when resuming.
</core>
</section>

</skill>
