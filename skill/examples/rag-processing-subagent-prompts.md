<skill name="conductor-example-rag-processing-teammate-prompt" version="3.0">

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- workflow-overview
- rag-teammate-prompt
</sections>

<section id="workflow-overview">
<context>
# RAG Processing Teammate Prompt

A single background teammate handles the entire RAG processing workflow autonomously. The Conductor launches this teammate and immediately returns to its monitoring loop — no gap in orchestration coverage.

## Trigger Paths

- **Eager (Review Workflow step 8):** Immediately after approving a completion review with RAG proposals, if no other reviews or errors are pending
- **Fallback (Monitoring cycle):** During quiet monitoring cycles when pending RAG entries exist and no other events need handling

## Conductor's Role

The Conductor launches the teammate and resumes monitoring. The teammate works independently:
- Reads proposals, checks overlap, checks for invalidated existing entries
- Makes decisions autonomously using the deduplication policy
- Messages the Conductor via SendMessage only for tough decisions
- Sends a completion message when done
- The Conductor picks up messages in the next monitoring cycle
</context>
</section>

<section id="rag-teammate-prompt">
<core>
## RAG Teammate Launch

The Conductor launches this teammate using the Task tool with `model="opus"` and `run_in_background=True`:
</core>

<template follow="format">
```python
Task("Process RAG proposals", prompt="""
Your role: Autonomously process RAG addition proposals — check for overlap, check for
invalidated existing entries, make decisions, perform merges, write files, ingest, and clean up.

## Proposals to Process
{LIST_OF_PROPOSAL_PATHS}
Source task: {task-id}

## Knowledge-Base Philosophy
- One concept per file — granular, atomic, independently queryable
- Files are permanent — never deleted, marked outdated instead
- Optimized for machine retrieval via RAG queries
- Cross-references connect related concepts instead of merging
- Each file: 50-300 lines typical, ~500 max, single focused concept
- YAML frontmatter required (id, created, category, parent_topic, tags)
- Categories: conductor, implementation, reference, testing, api, database, plans, templates

## Deduplication Policy
- Decisions/designs/rationale → keep as separate entries even if overlapping (cross-reference)
- Code examples/templates/snippets → no duplication, merge or replace
- Safe default: if uncertain, ingest separately — deduplication is cheap, lost knowledge is expensive

## Workflow

### Phase 1: Overlap Check
For each proposal:
1. Read the proposal file. Note the musician's reasoning and the verbatim RAG content.
2. Use the musician's pre-compiled RAG match list as a starting point.
3. Query `query_documents` with the proposal's primary topic at 0.5 threshold.
4. Evaluate:
   - No overlap (> 0.5): Mark "ready to ingest"
   - Weak overlap (0.4-0.5): Mark "approve as new file"
   - Moderate overlap (0.3-0.4): Mark "review needed — consider merge"
   - Strong overlap (< 0.3): Mark "review needed — likely duplicate"

### Phase 2: Check for Invalidated Existing Entries
Query `query_documents` for topics related to the new work. Check if any existing entries are:
- Stale — contain outdated information superseded by the new work
- Anti-patterns — describe approaches the new work has replaced
- Incomplete — missing information the new work now provides

For invalidated entries: mark as outdated (add `status: outdated` to YAML frontmatter
and a note explaining what supersedes them), then re-ingest.

### Phase 3: Make Decisions
For each "review needed" proposal, decide:
- Approve as-is: Accept as new KB file
- Merge: Edit existing KB file to integrate the proposal content
- Skip/Reject: Don't add to KB (log reason)

Apply the deduplication policy above. If uncertain about a tough decision,
message the Conductor via SendMessage with the specific question.
Continue processing other proposals while waiting for a response.

### Phase 4: Execute
1. New files: Extract verbatim RAG content from proposals, write to target KB paths
2. Merges: Read existing KB file, integrate proposal content, preserve file structure
3. Invalidated entries: Update YAML frontmatter with `status: outdated`
4. Ingest all files: Call `ingest_file` for each. Use KB path as source name.
5. Verify: Query `query_documents` for each file's primary topic. Score < 0.3 = success.

### Phase 5: Clean Up
1. Delete processed proposal files from `docs/implementation/proposals/`
2. Delete temp files (`temp/rag-decisions-*.md`, `temp/rag-review-*.md`)
3. Write decision log to `temp/rag-decisions-{task-id}.md` for reference

### Phase 6: Report
Message the Conductor via SendMessage with results:
- Files ingested (new): count
- Files merged: count
- Existing entries invalidated: count
- Verification passed: count
- Any failures or tough decisions deferred
""", model="opus", run_in_background=True)
```
</template>

<core>
### Example Scenario

Proposals pending after task-03 completion review:
- `docs/implementation/proposals/rag-widget-testing.md` (rag-addition)
- `docs/implementation/proposals/rag-api-testing-patterns.md` (rag-addition)

The Conductor launches the RAG teammate with these two paths as `{LIST_OF_PROPOSAL_PATHS}` and immediately returns to monitoring. The teammate:

1. Reads both proposals, queries for overlap
2. Finds `rag-widget-testing.md` has no overlap (> 0.5) — marks ready to ingest
3. Finds `rag-api-testing-patterns.md` has moderate overlap (0.35) with existing `docs/knowledge-base/testing/api-test-patterns.md`
4. Checks if existing entry is stale — finds it's still accurate but incomplete
5. Decides to merge (new content supplements existing rather than duplicating)
6. Writes new file, merges existing file, ingests both, verifies
7. Cleans up proposals, sends completion message to Conductor

The Conductor picks up the completion message during its next monitoring cycle.
</core>
</section>

</skill>
