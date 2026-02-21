<skill name="conductor-rag-coordination-workflow" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- overview
- interruption-handling
- full-workflow
- handling-interruptions-during-processing
- resumption-after-exit
- design-principles
</sections>

<section id="overview">
<context>
# RAG Coordination Workflow

This document describes the complete RAG processing workflow, including how the conductor coordinates two subagents (overlap-check and ingestion) and handles interruptions from incoming task events.

## Overview

RAG processing can be triggered from two paths:
- **Review Workflow step 9 (eager):** After approving a task for completion, if no other reviews are pending
- **Monitoring step 6.5 (fallback):** During quiet monitoring cycles when pending RAG entries exist

Both paths use the same workflow described below.

The workflow involves three distinct phases:
1. **Overlap-check phase:** Review proposals for existing KB overlap (subagent)
2. **Decision phase:** Conductor reviews subagent results with user, makes merge/approve/reject decisions
3. **Ingestion phase:** Write new files, perform merges, ingest into RAG (subagent)
</context>
</section>

<section id="interruption-handling">
<mandatory>
## Interruption Handling

The background message-watcher runs continuously during all RAG phases. If an event arrives (task state change):

1. **Watcher detects event** → exits background task and notifies conductor
2. **Conductor is unblocked** (was waiting for user input during review decision)
3. **Conductor immediately relaunches message-watcher** with normal prompt (no special handling needed)
4. **Conductor reports to user:** "Task [task-id] entered [state]. Handle now or continue RAG review?"
5. **User decides:**
   - **Handle task:** Conductor processes review/error/completion, returns to RAG
   - **Continue RAG:** Conductor resumes RAG where it left off
6. **If RAG was interrupted mid-decision:** Record decisions-so-far in STATUS.md "Pending RAG Processing" section so resuming session can continue later
</mandatory>
</section>

<section id="full-workflow">
<core>
## Full Workflow

### Step 1: Launch Overlap-Check Subagent

**When:** Monitoring step 6.5, after confirming pending RAG work exists.

**Conductor prepares:**
```sql
SELECT proposal_path FROM proposals_pending
WHERE task_id = 'task-XX' AND type = 'rag-addition';
```

**Launch subagent:**
</core>

<template follow="format">
```
Task("Review RAG proposals for overlap", prompt="""
Your role: Review RAG addition proposals for overlap with existing knowledge-base content.

## Knowledge-Base Philosophy
- One concept per file — granular, atomic, independently queryable
- Files are permanent — never deleted, marked outdated instead
- Optimized for machine retrieval via RAG queries, not human reading
- Cross-references connect related concepts instead of merging them
- Each file: 50-300 lines typical, ~500 max, single focused concept
- YAML frontmatter required (id, created, category, parent_topic, tags)
- Categories: conductor, implementation, reference, testing, api, database, plans, templates

## What Belongs / Doesn't Belong
**YES:** Validated patterns from completed work, architectural decisions with rationale, reusable technical patterns, reference material for future sessions.
**NO:** Untested ideas, task-specific implementation details, temporary workarounds, comprehensive multi-concept guides.

## Your Task
For each proposal:
1. Read the proposal file. Note the musician's reasoning and the verbatim RAG content.
2. Query `query_documents` with the proposal's primary topic at 0.5 threshold.
3. Evaluate each proposal using these thresholds:
   - **No overlap (> 0.5):** Recommend "ready to ingest"
   - **Weak overlap (0.4-0.5):** Recommend "approve as new file"
   - **Moderate overlap (0.3-0.4):** Recommend "review needed — consider merge"
   - **Strong overlap (< 0.3):** Recommend "review needed — likely duplicate"

## Output Format
Write results to `temp/rag-review-task-XX.md`:
```markdown
# RAG Proposal Review — task-XX

## Ready to Ingest
| Proposal | Target Location | Recommendation |
|----------|----------------|----------------|

## Review Needed
### proposals/rag-{name}.md
- **Overlap type:** [duplicate / merge candidate / tangentially related]
- **Relevant existing files:** [list with scores]
- **Subagent recommendation:** [approve as-is / merge into X / skip]
```

---

**Proposals to review:**
{LIST_OF_PROPOSAL_PATHS}

Task ID: task-XX
""", model="opus", run_in_background=False)
```
</template>

<core>
### Step 2: Read Subagent Results

Read `temp/rag-review-{task-id}.md` to understand:
- Which proposals are "ready to ingest" (no action needed)
- Which proposals need conductor review (merge candidates, potential duplicates)

### Step 3: Present to User for Decisions

For each "review needed" proposal, present to user with:
- Subagent's recommended action (approve, merge, skip)
- Relevant existing KB files and overlap scores
- Musician's reasoning from original proposal

User decides per proposal:
- **Approve as-is:** Accept as new KB file
- **Merge:** Conductor will edit existing KB file to integrate content
- **Skip/Reject:** Don't add to KB

### Step 4: Perform Merges (if any)

For each merge decision, conductor edits the target knowledge-base file in place:
- Read the proposal's verbatim RAG content
- Read the existing KB file
- Integrate content thoughtfully (update YAML frontmatter, add cross-references, avoid duplication)
- Preserve original file structure and philosophy

### Step 5: Write Ingestion Manifest

Create `docs/implementation/reports/rag-ingest-manifest-{task-id}.md`:
</core>

<template follow="format">
```markdown
# RAG Ingestion Manifest — task-XX

## New Files to Extract
| Proposal Path | Target KB Path | Source Task |
|---------------|----------------|-------------|
| docs/implementation/proposals/rag-X.md | docs/knowledge-base/category/name.md | task-XX |

## Modified Files to Re-ingest
| KB Path | Modified By | Notes |
|---------|------------|-------|
| docs/knowledge-base/category/existing.md | Conductor merge (task-XX) | Integrated proposal content |
```
</template>

<core>
### Step 6: Write Decision Log

Create `temp/rag-decisions-{task-id}.md` for resumption sessions:
</core>

<template follow="format">
```markdown
# RAG Processing Decisions — task-XX

## Approved Proposals (Ready to Ingest)
- proposals/rag-X.md → docs/knowledge-base/category/X.md (NEW)

## Merged Proposals
- proposals/rag-Y.md → merged into docs/knowledge-base/category/existing.md

## Rejected Proposals
- proposals/rag-Z.md (Reason: duplicate of existing-file.md)
```
</template>

<core>
### Step 7: Set Task to review_approved

After all decisions are made and manifest/decision-log written:
</core>

<template follow="exact">
```sql
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = 'task-XX';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('task-XX', 'task-00',
    'APPROVAL: RAG proposals reviewed and decisions made. Manifest ready at docs/implementation/reports/rag-ingest-manifest-task-XX.md. Musician can now release and idle.',
    'approval');
```
</template>

<context>
Musician can now continue or idle. RAG ingestion proceeds independently.
</context>

<core>
### Step 8: Launch Ingestion Subagent

**When:** After conductor completes decisions and sets `review_approved`.

**Launch subagent:**
</core>

<template follow="format">
```
Task("Ingest RAG files", prompt="""
Your role: Extract approved RAG files from proposals and ingest them into the local-rag server.

## Input
Ingestion manifest: docs/implementation/reports/rag-ingest-manifest-task-XX.md
This file contains:
- New files to extract (proposal path → target knowledge-base path)
- Modified existing files to re-ingest (KB paths edited by conductor during merge)

## Steps
1. **For new files:** Read each proposal's verbatim RAG content section. Write to target KB path exactly as written.
2. **For modified files:** These exist at their KB path (conductor edited them). Just ingest.
3. **Ingest all files:** Call `ingest_file` for each entry. Use the KB path as source name.
4. **Verify each ingestion:** Query `query_documents` with the file's primary topic. Verify score < 0.3 (strong match confirms success).
5. **Archive manifest:** Move from `docs/implementation/reports/rag-ingest-manifest-task-XX.md` to `docs/implementation/reports/archive/rag-ingest-manifest-task-XX.md` (create archive/ directory if needed).
6. **Clean up:** Delete `temp/rag-decisions-task-XX.md`.
7. **Report results:**
   - Files extracted: [count]
   - Files ingested: [count]
   - Verification passed: [count]
   - Verification failed: [count + details]
   - Manifest archived: yes/no
""", model="opus", run_in_background=False)
```
</template>

<core>
### Step 9: Update STATUS.md

Mark "Pending RAG Processing" entry for this task as complete.

### Step 10: Return to Monitoring

Proceed to Monitoring step 7 (repeat monitoring cycle).
</core>
</section>

<section id="handling-interruptions-during-processing">
<core>
## Handling Interruptions During RAG Processing

If a message-watcher event arrives while conductor is in decision phase (waiting for user input on merge decisions):

1. **Watcher exits, conductor is notified**
2. **Conductor immediately relaunches message-watcher**
3. **Conductor presents to user:**
   ```
   Task event detected: task-03 entered needs_review

   Current RAG processing for task-XX is in decision phase (merge decisions pending).

   Option A: Handle task-03 review now, then resume RAG decisions
   Option B: Continue with RAG decisions, task-03 can wait in queue
   ```
4. **User chooses:**
   - **Option A:** Conductor handles task-03 review/error/completion, then returns to RAG (resume merge decisions)
   - **Option B:** Conductor continues RAG, task-03 waits (watcher will detect it again next cycle)
5. **If resuming after Option A:** STATUS.md "Pending RAG Processing" section should have recorded which proposals have been decided and which remain. Resuming session continues from that point.
</core>
</section>

<section id="resumption-after-exit">
<core>
## Resumption After Conductor Exit

If conductor exits during RAG processing (context exhaustion, user request):

1. **Resuming session reads STATUS.md "Pending RAG Processing" section**
2. **Identifies which phase was interrupted:**
   - Before overlap-check: Re-launch overlap-check subagent
   - After overlap-check, before ingestion: Resume at decision phase (read `temp/rag-review-*`, continue making decisions)
   - After ingestion started: Re-launch ingestion subagent
3. **References `temp/rag-decisions-*` if it exists** (conductor's decisions-so-far during previous session)
4. **Continues workflow from interruption point**
</core>
</section>

<section id="design-principles">
<guidance>
## Key Design Principles

- **Always launch fresh:** Each subagent call is independent; no state carried in subagent context
- **Conductor makes editorial decisions:** Merge/approve/reject calls are conductor's responsibility, not subagent's
- **Background watcher is always active:** RAG work is high-level action, watcher runs independently
- **Record decisions-so-far:** STATUS.md and temp/ files allow clean resumption without re-doing work
</guidance>
</section>

</skill>
