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
- **Eager (Review Workflow step 8):** Immediately after approving a completion review, if no other reviews or errors are pending
- **Fallback (Monitoring cycle):** During quiet monitoring cycles when pending RAG entries exist and no other events need handling

Both paths use the same workflow below. The workflow involves three distinct phases: overlap-check (subagent), decision (Conductor), and ingestion (subagent).

### Step 1: Launch Overlap-Check Subagent

<template follow="format">
Task("Review RAG proposals for overlap", prompt="""
Your role: Review RAG addition proposals for overlap with existing knowledge-base content.

## Knowledge-Base Philosophy
- One concept per file — granular, atomic, independently queryable
- Files are permanent — never deleted, marked outdated instead
- Optimized for machine retrieval via RAG queries
- Cross-references connect related concepts instead of merging
- Each file: 50-300 lines typical, ~500 max, single focused concept
- YAML frontmatter required (id, created, category, parent_topic, tags)

## Your Task
For each proposal:
1. Read the proposal file. Note the musician's reasoning and the verbatim RAG content.
2. Query `query_documents` with the proposal's primary topic at 0.5 threshold.
3. Evaluate using these thresholds:
   - No overlap (> 0.5): Recommend "ready to ingest"
   - Weak overlap (0.4-0.5): Recommend "approve as new file"
   - Moderate overlap (0.3-0.4): Recommend "review needed — consider merge"
   - Strong overlap (< 0.3): Recommend "review needed — likely duplicate"

## Output Format
Write results to `temp/rag-review-{task-id}.md`:

# RAG Proposal Review — {task-id}

## Ready to Ingest
| Proposal | Target Location | Recommendation |

## Review Needed
### proposals/rag-{name}.md
- Overlap type: [duplicate / merge candidate / tangentially related]
- Relevant existing files: [list with scores]
- Subagent recommendation: [approve as-is / merge into X / skip]

---
Proposals to review: {LIST_OF_PROPOSAL_PATHS}
Task ID: {task-id}
""", model="opus", run_in_background=False)
</template>

### Step 2: Read Subagent Results

Read `temp/rag-review-{task-id}.md`. Identify:
- Which proposals are "ready to ingest" (no further review needed)
- Which proposals need Conductor review (merge candidates, potential duplicates)

### Step 3: Make Decisions

<mandatory>The Conductor makes RAG decisions autonomously. If uncertain about a merge decision, defer to ingestion as a separate entry — deduplication is cheaper than lost knowledge.</mandatory>

For each "review needed" proposal, decide:
- **Approve as-is:** Accept as new KB file
- **Merge:** Edit existing KB file to integrate the proposal content (update YAML frontmatter, add cross-references, avoid duplication within the file)
- **Skip/Reject:** Don't add to KB

### Step 4: Perform Merges (if any)

For each merge decision, edit the target knowledge-base file in place:
- Read the proposal's verbatim RAG content
- Read the existing KB file
- Integrate content thoughtfully (preserve original file structure and philosophy)

### Step 5: Write Ingestion Manifest

<template follow="format">
# RAG Ingestion Manifest — {task-id}

## New Files to Extract
| Proposal Path | Target KB Path | Source Task |
|---------------|----------------|-------------|
| docs/implementation/proposals/rag-X.md | docs/knowledge-base/category/name.md | {task-id} |

## Modified Files to Re-ingest
| KB Path | Modified By | Notes |
|---------|------------|-------|
| docs/knowledge-base/category/existing.md | Conductor merge ({task-id}) | Integrated proposal content |
</template>

### Step 6: Write Decision Log

Write to `temp/rag-decisions-{task-id}.md` for resumption context:

<template follow="format">
# RAG Processing Decisions — {task-id}

## Approved Proposals (Ready to Ingest)
- proposals/rag-X.md → docs/knowledge-base/category/X.md (NEW)

## Merged Proposals
- proposals/rag-Y.md → merged into docs/knowledge-base/category/existing.md

## Rejected Proposals
- proposals/rag-Z.md (Reason: duplicate of existing-file.md)
</template>

### Step 7: Launch Ingestion Subagent

<template follow="format">
Task("Ingest RAG files", prompt="""
Your role: Extract approved RAG files from proposals and ingest them into the local-rag server.

## Input
Ingestion manifest: docs/implementation/reports/rag-ingest-manifest-{task-id}.md

## Steps
1. For new files: Read each proposal's verbatim RAG content section. Write to target KB path exactly as written.
2. For modified files: These exist at their KB path (conductor edited them). Just ingest.
3. Ingest all files: Call `ingest_file` for each entry. Use the KB path as source name.
4. Verify each ingestion: Query `query_documents` with the file's primary topic. Verify score < 0.3 (strong match confirms success).
5. Clean up: Delete processed proposal files. Delete `temp/rag-decisions-{task-id}.md`.
6. Report results: Files extracted, ingested, verified, any failures.
""", model="opus", run_in_background=False)
</template>

### Step 8: Return to Monitoring

After RAG processing completes, return to SKILL.md and locate the Phase Execution Protocol for monitoring cycle re-entry.

### Interruption Handling

<mandatory>The background message-watcher runs continuously during all RAG phases. If it detects a state change (review, error, completion) during RAG processing, pause RAG work and handle the event first. RAG processing must NEVER block review or error handling.</mandatory>

If interrupted during the decision phase (step 3):
- Record decisions-so-far in `temp/rag-decisions-{task-id}.md`
- Handle the interrupting event via the appropriate protocol (through SKILL.md)
- After handling, resume RAG decisions from where you left off (read the decision log)

If interrupted during the ingestion phase (step 7):
- The ingestion subagent handles its own completion independently
- After handling the interrupting event, check the subagent's results
- If subagent completed: verify and clean up
- If subagent was interrupted: re-launch with remaining items

### Resumption After Session Exit

If the Conductor session exits during RAG processing (context management):
1. Check `temp/rag-decisions-{task-id}.md` — identifies which phase was interrupted
2. If before overlap-check: re-launch overlap-check subagent from scratch
3. If after overlap-check but before ingestion: resume at decision phase (read `temp/rag-review-*`)
4. If after ingestion started: check ingestion results, re-launch if needed
</core>
</section>

</skill>
