<skill name="conductor-example-review-approval-workflow" version="2.0">

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- scenario
- read-review-message
- update-conductor-state
- read-proposal
- check-self-correction
- approve
- reject-revision
- reject-major
- resume-monitoring
</sections>

<section id="scenario">
<context>
# Example: Review Approval Workflow

This example shows the conductor handling a review request from an execution session.

## Scenario

Monitoring subagent reports: "task-03 state changed to needs_review"
</context>
</section>

<section id="read-review-message">
<core>
## Step 1: Read the Review Message

```sql
SELECT task_id, from_session, message, timestamp
FROM orchestration_messages
WHERE task_id = 'task-03'
ORDER BY timestamp DESC
LIMIT 1;
```

Result:
```
task-03 | b358b967-0cbd-483b-90e0-6aa78c9d1baa | REVIEW REQUEST (Smoothness: 2/9):
Context Usage: 28% (safe to proceed, no self-correction active)
Self-Correction: false
Deviations: None
Agents Remaining: 3 (task-04, task-05, task-06)
Proposal: docs/implementation/proposals/task-03-testing-extraction.md
Summary: Extracted 8 testing docs to knowledge-base/testing/,
         created README with file index, added cross-references.
Files Modified: 9
Tests: All grep verifications passing
Danger File Status: knowledge-base/testing/README.md created with 12 entries.
                    Task-04 can safely add cross-references.
Key Outputs:
  - docs/implementation/proposals/task-03-testing-extraction.md (created)
  - docs/implementation/proposals/rag-widget-testing.md (rag-addition)
  - docs/implementation/reports/task-03-checkpoint-2.md (created)
```
</core>
</section>

<section id="update-conductor-state">
<core>
## Step 2: Update Conductor State

```sql
UPDATE orchestration_tasks
SET state = 'reviewing', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</core>
</section>

<section id="read-proposal">
<core>
## Step 3: Read the Proposal

Read `docs/implementation/proposals/task-03-testing-extraction.md` and evaluate:

- Does the work align with plan goals?
- Is the task type appropriate?
- Are deliverables complete?
- Is quality acceptable (smoothness 2/9 = minor issues, self-resolved)?
</core>
</section>

<section id="check-self-correction">
<core>
## Step 3b: Check Self-Correction Flag

Before deciding on approval or rejection, check if musician reported self-correction:

**From the review message:** `Self-Correction: false`

**Decision logic:**
- **If Self-Correction: false** → Context estimates are reliable. Make approval/rejection decision normally.
- **If Self-Correction: true** → Context estimates are unreliable (~6x bloat). Additional steps:
  1. Compare actual context % to task instruction's estimated cost for this checkpoint
  2. If actual >> estimated: Musician may be thrashing. Ask if they want to exit early or continue.
  3. If actual ≈ estimated: Tell musician to reset flag to false, estimates are back in sync.
  4. If remaining work + actual context > 80%: Recommend setting task to `fix_proposed` for early handoff.
</core>

<context>
Note: Task-03 shows "Self-Correction: false" and "Context Usage: 28% (safe to proceed)" so no additional context handling needed.
</context>
</section>

<section id="approve">
<core>
## Step 4a: Approve (Smoothness 0-5)

```sql
-- Approve the review
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

-- Send approval message
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'REVIEW APPROVED: Extraction looks good. Proceed with remaining steps.
     Note: Danger file README.md created successfully, task-04 can proceed.',
    'approval'
);

-- Return conductor to watching
UPDATE orchestration_tasks
SET state = 'watching', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</core>
</section>

<section id="reject-revision">
<core>
## Step 4b: Reject (Smoothness 6-7 — Revision Needed)

```sql
-- Reject the review
UPDATE orchestration_tasks
SET state = 'review_failed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

-- Send rejection with specific feedback
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'REVIEW FAILED (Smoothness: 6/9):
     Issue: Missing metadata headers in 3 knowledge-base files
     Required: Each .md file needs YAML frontmatter with title, date, tags
     Files affected: kb-testing-unit.md, kb-testing-integration.md, kb-testing-e2e.md
     Retry: Add frontmatter headers matching knowledge-base/README.md format,
            then re-submit for review',
    'rejection'
);

-- Return conductor to watching
UPDATE orchestration_tasks
SET state = 'watching', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</core>
</section>

<section id="reject-major">
<core>
## Step 4c: Reject (Smoothness 8-9 — Major Issues)

```sql
-- Reject with detailed explanation
UPDATE orchestration_tasks
SET state = 'review_failed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'REVIEW FAILED (Smoothness: 8/9):
     Critical issues found:
     1. Wrong source directory used (docs/old-testing/ instead of docs/testing/)
     2. File naming doesn''t match knowledge-base convention
     3. Cross-references point to non-existent files
     Required: Re-extract from correct source, follow naming in knowledge-base/README.md
     Note: This may require starting the extraction over',
    'rejection'
);

UPDATE orchestration_tasks
SET state = 'watching', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
</core>
</section>

<section id="resume-monitoring">
<core>
## Step 5: Resume Monitoring

After handling the review, relaunch monitoring subagent for remaining active tasks.
</core>
</section>


</skill>
