# Completion Protocol — Extraction Proposal

This proposal identifies all content from the 15 reference files, the monolithic SKILL-v2 archive, and the completion-coordination example that belongs in the **Completion Protocol** (`completion.md`).

---

## 1. Completion Section from Monolithic SKILL.md
**Source:** `docs/archive/SKILL-v2-monolithic.md`, lines 467-483 (section id="completion")
**Authority:** core
**Proposed section ID:** `completion-workflow`
**Duplication note:** None — unique to this protocol
**Modification needed:** Per design doc Section 3 (autonomous operation), remove step 4 "Ask user about generating human-readable docs from knowledge base" — Conductor is fully autonomous post-bootstrap. Step 6 "Report to user with deliverables list and recommendations. Wait for feedback" should be changed to report and continue autonomously (user observes but Conductor doesn't wait). Also per design doc Section 8, step references to STATUS.md should be DELETED — STATUS.md eliminated. Per design doc Section 11 I4, update 200k context references to 1m.

**Content (verbatim from source):**
```
When all tasks in all phases reach `complete`:

1. Verify all completion reports filed and all expected files created.
2. Run final verification: tests passing, git clean, RAG files ingested, directory structure correct.
3. Integrate proposals: CLAUDE.md additions, memory snippets, RAG pattern documentation.
4. Ask user about generating human-readable docs from knowledge base.
5. Prepare PR: review commits, check for sensitive data, suggest title and description.
6. Report to user with deliverables list and recommendations. Wait for feedback.
7. Set conductor state to `complete`.
```

---

## 2. Completion Coordination Example (Full File)
**Source:** `examples/completion-coordination.md`, lines 1-251 (entire file)
**Authority:** core (most sections), context (scenario section), template (PR and report sections)
**Proposed section ID:** Multiple — content maps to individual completion steps below
**Duplication note:** None — unique to this protocol
**Modification needed:** Per design doc Section 8 (STATUS.md eliminated), remove any STATUS.md references. Per design doc Section 3 (autonomous operation), step 7 "Ask About Human-Readable Docs" should be DELETED or converted to autonomous output — Conductor doesn't wait for user input post-bootstrap. The file mapping table confirms this example maps to `completion.md`.

### 2a. Verify All Tasks Complete (SQL)
**Source:** `examples/completion-coordination.md`, lines 35-61 (section id="verify-all-tasks")
**Authority:** core
**Proposed section ID:** `verify-all-tasks`
**Duplication note:** SQL pattern also in database-queries.md Pattern 11 (Monitor All Tasks) — co-locate here
**Modification needed:** None — direct migration

### 2b. Read Completion Reports
**Source:** `examples/completion-coordination.md`, lines 63-69 (section id="read-completion-reports")
**Authority:** core
**Proposed section ID:** `read-completion-reports`
**Duplication note:** None
**Modification needed:** None — direct migration

### 2c. Verify Deliverables
**Source:** `examples/completion-coordination.md`, lines 71-103 (section id="verify-deliverables")
**Authority:** core
**Proposed section ID:** `verify-deliverables`
**Duplication note:** None
**Modification needed:** None — direct migration, but examples are scenario-specific. The protocol file should generalize the pattern (check expected files exist, git status clean, no uncommitted changes, check temp/ for stranded files).

### 2d. Check for Proposals
**Source:** `examples/completion-coordination.md`, lines 105-126 (section id="check-proposals")
**Authority:** core
**Proposed section ID:** `check-proposals`
**Duplication note:** None
**Modification needed:** Per design doc, proposals tracking may be in-session (1m context) or database. Remove any STATUS.md "Proposals Pending" references.

### 2e. Integrate Proposals
**Source:** `examples/completion-coordination.md`, lines 128-144 (section id="integrate-proposals")
**Authority:** core
**Proposed section ID:** `integrate-proposals`
**Duplication note:** None
**Modification needed:** None — direct migration

### 2f. Ask About Human-Readable Docs
**Source:** `examples/completion-coordination.md`, lines 146-162 (section id="ask-about-docs")
**Authority:** core
**Proposed section ID:** N/A — **DELETED per design doc Section 3**
**Duplication note:** None
**Modification needed:** DELETED — Conductor is autonomous post-bootstrap, does not prompt user for optional doc generation decisions. If this capability is kept, it should be an autonomous decision or removed entirely.

### 2g. Prepare PR
**Source:** `examples/completion-coordination.md`, lines 164-201 (section id="prepare-pr")
**Authority:** core + template (follow="format")
**Proposed section ID:** `prepare-pr`
**Duplication note:** None
**Modification needed:** None — direct migration. PR template is scenario-specific but the structure is generalizable.

### 2h. Report to User
**Source:** `examples/completion-coordination.md`, lines 203-233 (section id="report-to-user")
**Authority:** core + template (follow="format")
**Proposed section ID:** `report-to-user`
**Duplication note:** None
**Modification needed:** Per design doc Section 3, this is a report (user observes), not a gate (user approves). Change "Waiting for your feedback" to a non-blocking report. Conductor proceeds to set `complete` state without waiting.

### 2i. Set Conductor Complete (SQL)
**Source:** `examples/completion-coordination.md`, lines 235-248 (section id="set-conductor-complete")
**Authority:** core
**Proposed section ID:** `set-conductor-complete`
**Duplication note:** SQL duplicated from database-queries.md Pattern 10
**Modification needed:** None — direct migration, SQL co-location is correct per design

---

## 3. Database Query — Pattern 10: Mark Conductor Complete
**Source:** `references/database-queries.md`, lines 321-332 (Pattern 10)
**Authority:** template (follow="exact")
**Proposed section ID:** `set-conductor-complete` (co-located in completion step)
**Duplication note:** Duplicated in completion-coordination example (2i above) — intentional SQL co-location
**Modification needed:** None — direct migration

**Content:**
```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now')
WHERE task_id = 'task-00';
```

---

## 4. Database Query — Pattern 11: Monitor All Tasks
**Source:** `references/database-queries.md`, lines 334-346 (Pattern 11)
**Authority:** template (follow="exact")
**Proposed section ID:** `verify-all-tasks` (co-located in completion verification step)
**Duplication note:** Also relevant to phase-execution.md for monitoring — co-locate in both
**Modification needed:** None — direct migration

**Content:**
```sql
SELECT task_id, state, last_heartbeat,
       retry_count, last_error
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```

---

## 5. Database Query — Pattern 8: Mark Complete (Execution)
**Source:** `references/database-queries.md`, lines 285-307 (Pattern 8)
**Authority:** template (follow="format")
**Proposed section ID:** UNCERTAIN — This is the execution session's completion SQL, not the conductor's. May belong in musician-lifecycle.md or phase-execution.md instead.
**Duplication note:** Primarily belongs in musician/execution protocol. Include here only as reference for what the Conductor expects to see when verifying completion.
**Modification needed:** If included, mark as "expected state from execution session" rather than "Conductor executes this"

---

## 6. State Machine — `complete` Terminal State Rules
**Source:** `references/state-machine.md`, lines 37-49 (conductor-states) and lines 52-70 (execution-states)
**Authority:** core
**Proposed section ID:** `terminal-state-rules`
**Duplication note:** Also belongs in initialization.md (state machine summary) and phase-execution.md — co-locate here for completion-specific rules
**Modification needed:** Extract only the `complete` state entries and hook exit criteria relevant to completion

**Relevant content from conductor states:**
```
| `complete` | Conductor | All tasks done | Yes (hook allows exit) |
Hook exit criteria: Conductor session can only exit when state is `exit_requested` or `complete`.
```

**Relevant content from execution states:**
```
| `complete` | Execution | Task finished successfully | Yes (hook allows exit) |
Hook exit criteria: Execution session can only exit when state is `complete` or `exited`.
```

---

## 7. State Machine — `exited` State Details (for completion report)
**Source:** `references/state-machine.md`, lines 108-120 (section id="exited-state-details")
**Authority:** core
**Proposed section ID:** UNCERTAIN — Relevant during completion reporting when some tasks `exited` rather than `complete`. May belong more in error-recovery.md or musician-lifecycle.md.
**Duplication note:** Primary home is error-recovery or musician-lifecycle. Completion protocol needs awareness but not full detail.
**Modification needed:** Include a brief note in completion: "If any task is `exited`, note it in the completion report but continue with integration" (already present in example step 1)

---

## 8. Smoothness Score Aggregation for Completion Report
**Source:** `references/review-checklists.md`, lines 121-144 (Score Aggregation Across Tasks, in section id="execution-task-completion-review")
**Authority:** core (aggregation format) + guidance (interpretation)
**Proposed section ID:** `smoothness-aggregation`
**Duplication note:** Primary home is review-protocol.md. Completion protocol needs the aggregation format for the final report.
**Modification needed:** Extract only the aggregation/reporting portion, not the per-review scoring mechanics

**Content:**
```
### Score Aggregation Across Tasks

Track smoothness scores across all tasks in a phase to assess plan quality:

Phase 2 Smoothness Summary:
  task-03: 2/9 (testing extraction)
  task-04: 3/9 (API extraction)
  task-05: 1/9 (database extraction)
  task-06: 4/9 (architecture extraction)
  Average: 2.5/9
  Worst: 4/9

Interpretation guidelines:
- Average 0-3: Plan and instructions are high quality. Proceed confidently.
- Average 3-5: Plan is adequate but instructions could be more precise.
- Average 5+: Systemic issue. Investigate.
- Single outlier 7+: Task-specific issue.

Include aggregated scores in the final completion report to the user.
```

---

## 9. STATUS.md Template (Completion Sections)
**Source:** `references/review-checklists.md`, lines 147-207 (section id="status-md-template")
**Authority:** core + template (follow="format") + guidance
**Proposed section ID:** N/A — **DELETED — STATUS.md eliminated per design doc Section 8**
**Duplication note:** N/A
**Modification needed:** DELETED — STATUS.md is eliminated. The STATUS.md template, STATUS.md reading strategy, and recovery instructions template are all removed per design doc.

---

## 10. STATUS.md Reading Strategy
**Source:** `references/status-md-reading-strategy.md`, entire file (lines 1-151)
**Authority:** core + template + context
**Proposed section ID:** N/A — **DELETED — STATUS.md eliminated per design doc Section 8**
**Duplication note:** N/A
**Modification needed:** DELETED — entire file is eliminated per design doc

---

## 11. Recovery Instructions Template
**Source:** `references/recovery-instructions-template.md`, entire file (lines 1-94)
**Authority:** core + template + guidance
**Proposed section ID:** N/A — **DELETED — STATUS.md eliminated per design doc Section 8**
**Duplication note:** N/A
**Modification needed:** DELETED — entire file is eliminated per design doc. Recovery instructions are unnecessary with 1m context.

---

## 12. Parallel Coordination — Phase Completion
**Source:** `references/parallel-coordination.md`, lines 224-238 (section id="phase-completion")
**Authority:** core
**Proposed section ID:** UNCERTAIN — Phase completion (checking proposals after a phase) is distinct from final completion (all phases done). May belong in phase-execution.md instead.
**Duplication note:** Relevant to both phase-execution.md (per-phase completion) and completion.md (final completion)
**Modification needed:** If included in completion.md, clarify that this is about per-phase wrap-up, distinct from final orchestration completion. The proposal checking logic applies to both.

**Content:**
```
### 9. Phase Completion

When all tasks in the phase reach `complete` or `exited`:

1. Check for proposals in both locations:
   - `docs/implementation/proposals/` (general proposals)
   - `docs/proposals/claude-md/` (learnings proposals)
2. Verify no proposals stuck in `temp/`
3. Integrate critical proposals, defer non-critical
4. Update STATUS.md phase status
5. Proceed to next phase
```

**Note:** Step 4 "Update STATUS.md phase status" must be DELETED — STATUS.md eliminated per design.

---

## 13. RAG Coordination Workflow (Completion-Related Portions)
**Source:** `references/rag-coordination-workflow.md`, lines 1-317 (entire file)
**Authority:** mandatory (interruption handling), core (workflow), template (SQL and subagent prompts)
**Proposed section ID:** UNCERTAIN — RAG processing is triggered from review workflow (step 9, eager) or monitoring (step 6.5, fallback). It's not specifically a completion activity. The design doc maps it to `review-protocol.md` or a new `rag-processing.md`.
**Duplication note:** Primary home is review-protocol.md per design doc file mapping table. Only include in completion.md if RAG processing during final completion is a distinct workflow.
**Modification needed:** Per design doc file mapping table, this maps to `review-protocol.md` or new `rag-processing.md`. Should NOT be primary home in completion.md. At most, completion.md should reference: "Verify all RAG proposals have been processed before final completion."

---

## 14. Context Management (Completion-Adjacent)
**Source:** `docs/archive/SKILL-v2-monolithic.md`, lines 444-465 (section id="context-management")
**Authority:** core + guidance
**Proposed section ID:** N/A — Does not belong in completion protocol
**Duplication note:** Belongs in SKILL.md dispatcher or initialization protocol
**Modification needed:** Per design doc Section 8, STATUS.md references are eliminated. Per Section 11 I4, 200k references updated to 1m. Context management is about mid-orchestration exits, not completion. EXCLUDED from completion protocol.

---

## 15. Orchestration Principles — Context Budget
**Source:** `references/orchestration-principles.md`, lines 46-56 (context budget table)
**Authority:** core
**Proposed section ID:** N/A — Does not belong in completion protocol
**Duplication note:** Per design doc file mapping table, absorbed into SKILL.md context sections
**Modification needed:** EXCLUDED from completion protocol. Per design doc Section 11 I4, context budget references should update 200k to 1m wherever they land.

---

## 16. Database Query — Pattern 9: Request Exit (Conductor)
**Source:** `references/database-queries.md`, lines 309-319 (Pattern 9)
**Authority:** template (follow="exact")
**Proposed section ID:** UNCERTAIN — `exit_requested` is for context-management exits, not completion. Does not belong in completion protocol.
**Duplication note:** Belongs in SKILL.md dispatcher or initialization protocol (context management)
**Modification needed:** EXCLUDED from completion protocol. Exit requested is NOT completion — it's an emergency context exit.

---

## Summary

### Content that BELONGS in Completion Protocol:

| # | Description | Source | Authority | Modification |
|---|-------------|--------|-----------|-------------|
| 1 | Completion workflow steps | SKILL-v2-monolithic.md, lines 467-483 | core | Remove interactive steps per autonomous model |
| 2a | Verify all tasks SQL | completion-coordination.md, lines 35-61 | core | None |
| 2b | Read completion reports | completion-coordination.md, lines 63-69 | core | None |
| 2c | Verify deliverables | completion-coordination.md, lines 71-103 | core | Generalize from example |
| 2d | Check proposals | completion-coordination.md, lines 105-126 | core | Remove STATUS.md refs |
| 2e | Integrate proposals | completion-coordination.md, lines 128-144 | core | None |
| 2g | Prepare PR | completion-coordination.md, lines 164-201 | core+template | None |
| 2h | Report to user | completion-coordination.md, lines 203-233 | core+template | Non-blocking report |
| 2i | Set conductor complete SQL | completion-coordination.md, lines 235-248 | core | None |
| 3 | Mark conductor complete SQL | database-queries.md, lines 321-332 | template(exact) | SQL co-location |
| 4 | Monitor all tasks SQL | database-queries.md, lines 334-346 | template(exact) | SQL co-location |
| 6 | Complete terminal state rules | state-machine.md, lines 37-49, 52-70 | core | Extract complete-specific |
| 8 | Smoothness score aggregation | review-checklists.md, lines 121-144 | core+guidance | Extract reporting portion |
| 12 | Phase completion proposals check | parallel-coordination.md, lines 224-238 | core | Remove STATUS.md step |

### Content DELETED (STATUS.md eliminated per design):

| # | Description | Source | Reason |
|---|-------------|--------|--------|
| 9 | STATUS.md template | review-checklists.md, lines 147-207 | STATUS.md eliminated |
| 10 | STATUS.md reading strategy | status-md-reading-strategy.md, entire file | STATUS.md eliminated |
| 11 | Recovery instructions template | recovery-instructions-template.md, entire file | Recovery unnecessary with 1m |
| 2f | Ask about human-readable docs | completion-coordination.md, lines 146-162 | Autonomous model, no user prompts |

### Content EXCLUDED (belongs in other protocols):

| # | Description | Target Protocol |
|---|-------------|----------------|
| 5 | Execution mark-complete SQL | musician-lifecycle.md or phase-execution.md |
| 7 | Exited state details | error-recovery.md or musician-lifecycle.md |
| 13 | RAG coordination workflow | review-protocol.md or rag-processing.md |
| 14 | Context management | SKILL.md dispatcher |
| 15 | Context budget | SKILL.md context sections |
| 16 | Exit requested SQL | SKILL.md dispatcher |

### New Content Required (per design doc, not in existing files):

1. **Autonomous completion flow** — Per design doc Section 3, the Conductor reports completion without waiting for user input. This is a behavior change from existing content.
2. **Decisions directory cleanup** — Design doc file mapping mentions this in completion protocol scope. Not present in existing reference files. Needs new content: clean up `decisions/{feature-name}/` directory used for Repetiteur blocker reports.
3. **1m context budget references** — Per design doc Section 11 I4, any context budget references migrated to this file should use 1m, not 200k.
4. **Musician window cleanup at completion** — Per design doc Section 6, all kitty windows should be cleaned up at orchestration completion. PID tracking and cleanup rules from musician-lifecycle.md are relevant here, but the trigger belongs in completion protocol.
