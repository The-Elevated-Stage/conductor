<skill name="conductor-example-rag-processing-subagent-prompts" version="2.0">

<metadata>
type: example
parent-skill: conductor
tier: 3
</metadata>

<sections>
- workflow-overview
- overlap-check-subagent
- ingestion-subagent
</sections>

<section id="workflow-overview">
<context>
# RAG Processing Subagent Prompts

Two subagents are launched during RAG proposal processing (Monitoring step 6.5 or Review Workflow step 9).

## Full RAG Processing Workflow

This workflow runs during the monitoring cycle when RAG proposals are pending and no other events require attention. The background watcher is active throughout — if a new event arrives, pause RAG processing to handle it.

1. Launch overlap-check subagent (below)
2. Read subagent results from `temp/rag-review-{task-id}.md`
3. For "ready to ingest" items: no user action needed
4. For "review needed" items: present to user in bulk with subagent recommendations and relevant existing RAG files. User decides per proposal: approve as new file, merge into existing, or reject.
5. Perform merges — conductor edits existing knowledge-base files in place (complex editorial work)
6. Write ingestion manifest to `docs/implementation/reports/rag-ingest-manifest-{task-id}.md` — list of files to ingest (new files from proposals + any modified existing files from merges)
7. Write decision log to `temp/rag-decisions-{task-id}.md` — rejected proposals, approved proposals with target locations, merge details
8. Set `review_approved` — send approval message via `orchestration_messages`. Musician can now release and idle. RAG ingestion continues independently.
9. Launch ingestion subagent (below)
10. Resume normal monitoring cycle
</context>
</section>

<section id="overlap-check-subagent">
<core>
## 1. Overlap-Check Subagent

**When:** Monitoring step 6.5, first action after confirming pending RAG work.
**Model:** opus
**Output:** `temp/rag-review-{task-id}.md`

### Task Tool Prompt
</core>

<template follow="format">
```
Read the RAG proposal files listed below, then read examples/rag-processing-subagent-prompts.md
in the conductor skill for your detailed instructions.

Proposals to review: {LIST_OF_PROPOSAL_PATHS}
Task ID: {TASK_ID}
```
</template>

<core>
### Detailed Instructions (read by subagent from this file)

**Your role:** Review RAG addition proposals for overlap with existing knowledge-base content.

**Knowledge-base philosophy (critical context):**
- One concept per file — granular, atomic, independently queryable
- Files are permanent — never deleted, marked outdated instead
- Optimized for machine retrieval via RAG queries, not human reading
- Cross-references connect related concepts instead of merging them
- Each file: 50-300 lines typical, ~500 max, single focused concept
- YAML frontmatter required (id, created, category, parent_topic, tags)
- Categories: conductor, implementation, reference, testing, api, database, plans, templates

**What belongs in knowledge-base:** Validated patterns from completed work, architectural decisions with rationale, reusable technical patterns, reference material for future sessions.

**What does NOT belong:** Untested ideas, task-specific implementation details, temporary workarounds, comprehensive multi-concept guides.

**For each proposal:**

1. Read the proposal file. Note:
   - The musician's reasoning section (why they think this belongs in KB)
   - The verbatim RAG file content (the actual proposed KB entry)
   - The musician's pre-compiled RAG match list (entries matching at 0.4 threshold)

2. Use the musician's match list as a starting point. For each match listed, assess relevance to the proposed content.

3. Query `query_documents` with the proposal's primary topic at 0.5 threshold to catch additional overlap the musician may have missed (the 0.4-0.5 band).

4. Evaluate each proposal:
   - **No overlap (> 0.5 on all queries):** Recommend "ready to ingest"
   - **Weak overlap (0.4-0.5):** Recommend "approve as new file" with note about tangentially related entries
   - **Moderate overlap (0.3-0.4):** Recommend "review needed — consider merge" and identify the specific existing file(s)
   - **Strong overlap (< 0.3):** Recommend "review needed — likely duplicate" and identify the matching file(s)

5. Write results to `temp/rag-review-{task-id}.md`:
</core>

<template follow="format">
```markdown
# RAG Proposal Review — {task-id}

## Ready to Ingest
| Proposal | Target Location | Recommendation |
|----------|----------------|----------------|
| proposals/rag-{name}.md | knowledge-base/{category}/{filename}.md | New file, no overlap |

## Review Needed
### proposals/rag-{name}.md
- **Overlap type:** [duplicate / merge candidate / tangentially related]
- **Relevant existing files:** [list with scores]
- **Musician reasoning:** [from proposal]
- **Subagent recommendation:** [approve as-is / merge into {existing-file} / skip — with brief justification]
```
</template>
</section>

<section id="ingestion-subagent">
<core>
## 2. Ingestion Subagent

**When:** After conductor completes RAG decisions and sets `review_approved` (workflow step 9 above).
**Model:** opus
**Input:** Ingestion manifest at `docs/implementation/reports/rag-ingest-manifest-{task-id}.md`

### Task Tool Prompt
</core>

<template follow="format">
```
Process the RAG ingestion manifest, then read examples/rag-processing-subagent-prompts.md
in the conductor skill for your detailed instructions.

Manifest: docs/implementation/reports/rag-ingest-manifest-{task-id}.md
Task ID: {TASK_ID}
```
</template>

<core>
### Detailed Instructions (read by subagent from this file)

**Your role:** Extract approved RAG files from proposals and ingest them into the local-rag server.

**Steps:**

1. Read the ingestion manifest. It contains:
   - List of new files to extract (proposal path → target knowledge-base path)
   - List of modified existing files to re-ingest (knowledge-base paths edited by conductor during merge)

2. **For new files:** Read each proposal's verbatim RAG content section. Write it to the target knowledge-base path exactly as written (the conductor and user have already approved this content).

3. **For modified files:** These already exist at their knowledge-base path (conductor edited them during merge). No extraction needed — just ingest.

4. **Ingest all files:** Call `ingest_file` for each entry in the manifest. Use the file's knowledge-base path as the source name.

5. **Verify each ingestion:** After ingesting, query `query_documents` with the file's primary topic. Verify score < 0.3 (strong match confirms successful ingestion). Log any verification failures.

6. **Archive manifest:** Move the manifest from `docs/implementation/reports/rag-ingest-manifest-{task-id}.md` to `docs/implementation/reports/archive/rag-ingest-manifest-{task-id}.md` (create archive/ directory if needed).

7. **Clean up:** Delete `temp/rag-decisions-{task-id}.md`.

8. **Report results:**
   - Files extracted: count
   - Files ingested: count
   - Verification passed: count
   - Verification failed: count + details
   - Manifest archived: yes/no
</core>
</section>

</skill>
