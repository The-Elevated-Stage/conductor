# Review Protocol — Extraction Proposal

**Target file:** `references/protocols/review-protocol.md`
**Date:** 2026-02-20
**Scope:** Everything from "Musician submits needs_review" to "Conductor sends verdict," plus smoothness scoring, review loop tracking, RAG proposal processing workflow, and review-related SQL/state transitions.

---

## 1. Review Workflow Core (from SKILL-v2-monolithic.md)
**Source:** SKILL-v2-monolithic.md, section `review-workflow`, lines 317-365
**Authority:** mandatory (lines 318-322), core (lines 324-364), guidance (lines 345-347)
**Proposed section ID:** `review-workflow`
**Duplication note:** None — this is the primary home
**Modification needed:**
- DELETED — STATUS.md references eliminated per design (line 358: "add entry to STATUS.md 'Pending RAG Processing' section" → replace with in-session tracking via 1m context or simple temp/ file list)
- UPDATE — line 537 references "200k-token budget" → change to "1m" per design (I4)
- The routing constraint (design Section 2) says at boundaries, reference files name the next protocol but do NOT include reference tags. So the current "See `references/review-checklists.md`" and "See `references/state-machine.md`" pointers become protocol names only (e.g., "Proceed to Error Recovery Protocol" or "consult Smoothness Scale section below" since checklists are now co-located).
- Authority-aware reading strategy currently says "see references/review-checklists.md" — this content is now co-located in the same file, so the reference becomes internal section pointers.
- UPDATE — Autonomous operation: ALL "escalate to user" becomes "Conductor decides autonomously or routes to Repetiteur Protocol." Review is fully autonomous post-bootstrap. This affects: review cycle 5 escalation (goes to Repetiteur, not user), RAG decision phase (Conductor decides merges autonomously), and uncertain fix proposals (Conductor attempts, routes to Repetiteur if stuck, user only if Repetiteur escalates).

**Content summary:**
- Mandatory authority statement ("You are the authority")
- 9-step review workflow: identify task, read review request message, self-correction flag awareness, read proposal/report, review loop tracking (cap at 5 cycles), evaluate using smoothness scale, decision thresholds (0-4 approve, 5 investigate, 6-7 revise, 8-9 reject), send message via orchestration_messages, eager RAG processing
- Context-aware reading strategy (guidance)
- Post-review routing to monitoring step 5.5

---

## 2. Smoothness Scale (from review-checklists.md)
**Source:** references/review-checklists.md, section `execution-task-completion-review`, lines 95-134
**Authority:** core
**Proposed section ID:** `smoothness-scale`
**Duplication note:** Also partially in state-machine.md lines 160-181 (summary version). The review-checklists.md version is the authoritative detailed version. The state-machine.md summary should be co-located in review-protocol.md as well.
**Modification needed:** None — pure migration. The smoothness scale table and score interpretation are unchanged.

**Content summary:**
- Smoothness Scale table (0-9 with meanings and typical indicators)
- Score interpretation notes (self-reported scores as starting points, score inflation, score context)
- Score Aggregation Across Tasks (phase-level tracking template)

---

## 3. Decision Thresholds (from review-checklists.md)
**Source:** references/review-checklists.md, section `execution-task-completion-review`, lines 106-113
**Authority:** core
**Proposed section ID:** `decision-thresholds`
**Duplication note:** Also stated in SKILL-v2-monolithic.md review-workflow section (lines 350-354). Both versions should be consolidated into the authoritative version here.
**Modification needed:** None — pure migration.

**Content summary:**
- Score Range → Action → State Transition → Message Content table
- 0-4: Approve (review_approved)
- 5: Investigate then approve (fix_proposed if errors, then review_approved)
- 6-7: Request revision (review_failed)
- 8-9: Reject (review_failed)

---

## 4. Context Situation Checklist (from review-checklists.md)
**Source:** references/review-checklists.md, section `execution-task-completion-review`, lines 84-93
**Authority:** core
**Proposed section ID:** `context-situation-checklist`
**Duplication note:** Also referenced in session-handoff.md section `context-situation-checklist` (lines 291-306), and in SKILL-v2-monolithic.md error-handling section (lines 428-434). The review-checklists.md is the detailed version. Session-handoff.md has a duplicate that may also go into musician-lifecycle.md.
**Modification needed:** None — pure migration.

**Content summary:**
- Self-correction flag check (6x bloat)
- Context usage vs task estimates
- Deviations count and severity
- Distance to next checkpoint
- Agents remaining and estimated cost
- Prior context warnings on this task

---

## 5. Score Aggregation Guidance (from review-checklists.md)
**Source:** references/review-checklists.md, section `execution-task-completion-review`, lines 121-144
**Authority:** core (lines 121-134), guidance (lines 136-144)
**Proposed section ID:** `score-aggregation`
**Duplication note:** None — unique to this file
**Modification needed:** None — pure migration.

**Content summary:**
- Phase smoothness summary format (task-by-task with average/worst)
- Interpretation guidelines (average 0-3 = high quality, 3-5 = adequate, 5+ = systemic, single outlier 7+ = task-specific)
- Include aggregated scores in final completion report

---

## 6. Subagent Self-Review Checklist (from review-checklists.md)
**Source:** references/review-checklists.md, section `subagent-self-review`, lines 33-51
**Authority:** core
**Proposed section ID:** `subagent-self-review-checklist`
**Duplication note:** None — stays in review-protocol.md per team lead resolution. Used during review evaluation.
**Modification needed:** None — pure migration.

**Content summary:**
- 8-item checklist (FACTS focus): sections present, SQL correct, file paths match, hook config, dependencies, verification steps, state transitions, completion report format
- Usage instructions

---

## 7. Conductor Review Checklist — STRATEGY (from review-checklists.md)
**Source:** references/review-checklists.md, section `conductor-review`, lines 54-73
**Authority:** core (lines 55-69), guidance (lines 71-73)
**Proposed section ID:** `conductor-strategy-checklist`
**Duplication note:** None — stays in review-protocol.md per team lead resolution. Used during review evaluation.
**Modification needed:** None — pure migration.

**Content summary:**
- 7-item checklist (STRATEGY focus): plan alignment, pattern choice, dependency logic, checkpoint placement, template compliance, verification adequacy, integration consideration
- Usage priority guidance (items 1-3 first, 4-7 refinements)

---

## 8. Review Approval SQL (from database-queries.md)
**Source:** references/database-queries.md, section `common-sql-patterns`, Pattern 4 (lines 199-214)
**Authority:** core (lines 199-200), template follow="format" (lines 202-214)
**Proposed section ID:** `review-approval-sql`
**Duplication note:** This SQL will be co-located here per SQL co-location principle. May also appear in phase-execution.md if needed there.
**Modification needed:** None — pure migration with co-location.

**Content summary:**
```sql
UPDATE orchestration_tasks
SET state = 'review_approved', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'REVIEW APPROVED: Good work. Proceed with remaining steps.',
    'approval'
);
```

---

## 9. Review Rejection SQL (from database-queries.md)
**Source:** references/database-queries.md, section `common-sql-patterns`, Pattern 5 (lines 216-235)
**Authority:** core (lines 216-217), template follow="format" (lines 219-235)
**Proposed section ID:** `review-rejection-sql`
**Duplication note:** Same co-location principle as #8.
**Modification needed:** None — pure migration with co-location.

**Content summary:**
```sql
UPDATE orchestration_tasks
SET state = 'review_failed', last_heartbeat = datetime('now')
WHERE task_id = 'task-03';

INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'REVIEW FAILED (Smoothness: 7/9):
     Issue: Missing cross-references in knowledge-base files
     Required: Add cross-references to related files in each document header
     Retry: Fix cross-references, then re-submit for review',
    'rejection'
);
```

---

## 10. Review Request SQL (from database-queries.md)
**Source:** references/database-queries.md, section `common-sql-patterns`, Pattern 3 (lines 167-196)
**Authority:** core (lines 167-168), template follow="format" (lines 170-196)
**Proposed section ID:** `review-request-sql`
**Duplication note:** This is the musician-side SQL for submitting a review. Including for completeness and reference — the conductor needs to understand the message format it's reading. May also appear in musician-lifecycle.md.
**Modification needed:** None — pure migration with co-location.

**Content summary:**
- UPDATE to `needs_review` with heartbeat
- INSERT review_request message with full structure (smoothness, checkpoint, context, self-correction, deviations, agents remaining, proposal path, summary, files modified, tests, key outputs)

---

## 11. Review Count Query (from database-queries.md)
**Source:** references/database-queries.md, section `common-sql-patterns`, Pattern 12 (lines 349-360)
**Authority:** core (lines 349-350), template follow="exact" (lines 352-360)
**Proposed section ID:** `pending-reviews-query`
**Duplication note:** General-purpose query, likely also in phase-execution.md or monitoring sections.
**Modification needed:** None — but this is the "check for pending reviews/messages" query, not a "count reviews for loop tracking" query. The review loop tracking query referenced in SKILL-v2 step 5 (`SELECT COUNT(*) FROM orchestration_messages WHERE task_id = ? AND message_type = 'review_request'`) is not explicitly in database-queries.md — it's inline in SKILL-v2. Should be formalized as a template in this protocol.

**Content summary:**
```sql
SELECT task_id, from_session, message, timestamp
FROM orchestration_messages
WHERE task_id LIKE 'task-%'
ORDER BY timestamp DESC
LIMIT 10;
```

---

## 12. State Transitions: needs_review/review_approved/review_failed (from state-machine.md)
**Source:** references/state-machine.md, section `execution-states` (lines 53-69), section `state-ownership` (lines 74-80), section `state-transition-flows` (lines 82-106), section `smoothness-scale` (lines 160-181)
**Authority:** core
**Proposed section ID:** `review-state-transitions`
**Duplication note:** State machine content is split across all protocol files per design. Each protocol gets the transitions it uses.
**Modification needed:** None — extract only the review-relevant transitions.

**Content summary:**
- `needs_review` — set by Execution, awaiting conductor
- `review_approved` — set by Conductor, execution resumes
- `review_failed` — set by Conductor, execution revises
- Transition flow: `working → needs_review → [conductor: review_approved] → working → complete`
- Transition flow: `working → needs_review → [conductor: review_failed] → working → needs_review → ...`
- Smoothness scale summary (compact version from state-machine.md)
- Conductor review thresholds (0-4 approve, 5 investigate, 6-7 revise, 8-9 reject)

---

## 13. Heartbeat Rule (from state-machine.md)
**Source:** references/state-machine.md, section `heartbeat-rule`, lines 122-136
**Authority:** mandatory
**Proposed section ID:** `heartbeat-rule` (inline within review-state-transitions or as standalone)
**Duplication note:** This mandatory rule must appear in EVERY protocol file that does state transitions (all of them). Co-location per design.
**Modification needed:** None — mandatory content preserved.

**Content summary:**
- Update `last_heartbeat` on EVERY state transition
- SQL example showing heartbeat in UPDATE
- All SQL in conductor workflows MUST include heartbeat

---

## 14. RAG Coordination Workflow (from rag-coordination-workflow.md)
**Source:** references/rag-coordination-workflow.md, ALL sections (lines 1-317)
**Authority:** context (overview, lines 19-36), mandatory (interruption handling, lines 40-53), core (full workflow steps 1-10, lines 56-263; interruptions during processing, lines 266-288; resumption, lines 290-304), guidance (design principles, lines 306-315), templates (multiple)
**Proposed section ID:** `rag-processing-workflow`
**Duplication note:** None — stays as a section within review-protocol.md per team lead resolution. RAG processing triggers after reviews, not a separate protocol.
**Modification needed:**
- DELETED — STATUS.md references throughout (lines 52, 178, 258-259, 297-298). Replace with in-session tracking (1m context) or simple temp/ file list per team lead resolution.
- The interruption handling (lines 40-53) references "STATUS.md 'Pending RAG Processing' section" — replace with in-session tracking or temp/ file list.
- UPDATE — The "resumption after exit" section (lines 290-304) references STATUS.md for resumption — unnecessary with 1m context per design. Simplify or remove.
- UPDATE — RAG decision phase currently presents to user for merge decisions. In autonomous mode, Conductor makes these decisions autonomously or routes to Repetiteur Protocol if uncertain.

**Content summary:**
- Overview: Two trigger paths (review workflow step 9 eager, monitoring step 6.5 fallback)
- Three phases: overlap-check (subagent), decision (conductor + user), ingestion (subagent)
- Interruption handling (mandatory): watcher detects event → conductor decides handle-now vs continue-RAG
- Full 10-step workflow: launch overlap-check, read results, present to user, perform merges, write manifest, write decision log, set review_approved, launch ingestion, update tracking, return to monitoring
- Subagent prompt templates (overlap-check and ingestion)
- SQL for approval after RAG decisions
- Interruption handling during decision phase
- Resumption after conductor exit
- Design principles

---

## 15. Checklist Overview Table (from review-checklists.md)
**Source:** references/review-checklists.md, section `checklist-overview`, lines 17-30
**Authority:** core
**Proposed section ID:** `checklist-overview`
**Duplication note:** None
**Modification needed:** None — pure migration. Provides routing context for which checklist to apply when.

**Content summary:**
- Table mapping: Subagent Self-Review (FACTS) → task instruction subagent → before returning instructions; Conductor Review (STRATEGY) → conductor → after receiving instructions; Execution Task Completion → conductor → when execution submits needs_review/complete

---

## 16. STATUS.md Template (from review-checklists.md)
**Source:** references/review-checklists.md, section `status-md-template`, lines 147-207
**Authority:** core (lines 148-152), template (lines 154-202), guidance (lines 204-206)
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** **DELETED — STATUS.md eliminated per design (Section 8).** This entire section should NOT be migrated to review-protocol.md. Its functions are absorbed by comms-link database and 1m context.

---

## 17. STATUS.md Reading Strategy (from status-md-reading-strategy.md)
**Source:** references/status-md-reading-strategy.md, ALL content (lines 1-151)
**Authority:** core, context
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** **DELETED — STATUS.md eliminated per design (Section 8).** This entire file is marked for deletion in the design document (Section 12 mapping table). Do not migrate.

---

## 18. Recovery Instructions Template (from recovery-instructions-template.md)
**Source:** references/recovery-instructions-template.md, ALL content (lines 1-94)
**Authority:** core, guidance
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** **DELETED — Recovery docs unnecessary with 1m context per design (Section 8, Section 12 mapping table).** Do not migrate.

---

## 19. Context Headroom "200k" Reference (from orchestration-principles.md)
**Source:** references/orchestration-principles.md, section `context-headroom`, line 22
**Authority:** core
**Proposed section ID:** N/A (this content is absorbed into SKILL.md per design)
**Duplication note:** Also in SKILL-v2-monolithic.md line 537
**Modification needed:** **UPDATE — change "200k-token context window" to "1m-token context window" per design I4.** However, per design Section 12, orchestration-principles.md is "Absorbed into SKILL.md `<context>` sections" — so this content does NOT go into review-protocol.md. Noting here only because the 200k reference might appear in migrated content.

---

## 20. Review Workflow from Parallel Coordination (from parallel-coordination.md)
**Source:** references/parallel-coordination.md, section `conductor-workflow` step 8 (lines 158-168)
**Authority:** core
**Proposed section ID:** No separate section — this is routing context
**Duplication note:** The parallel-coordination.md event handling (step 8) routes `needs_review` to "read message, review proposal, approve or reject." This is the entry point that routes to the review protocol. The actual review procedure is in SKILL-v2 and review-checklists.md (already captured above).
**Modification needed:** In the new protocol architecture, parallel-coordination.md becomes phase-execution.md. Step 8 event handling should name "Review Protocol" as the destination. No content from this belongs IN review-protocol.md — it's the caller, not the callee. Noting for completeness.

---

## 21. Sequential Review Handling (from sequential-coordination.md)
**Source:** references/sequential-coordination.md, section `conductor-workflow` step 6 (lines 122-128)
**Authority:** core
**Proposed section ID:** No separate section — routing context
**Duplication note:** Same pattern as #20 — sequential coordination routes to review but the actual review procedure is elsewhere. The step says "If state becomes `needs_review`: Read message, Review proposal, Approve or reject (see state-machine.md), Continue monitoring."
**Modification needed:** In new architecture, this routing happens from phase-execution.md. No content for review-protocol.md. Noting for completeness.

---

## 22. Review Loop Tracking Query (from SKILL-v2-monolithic.md, inline)
**Source:** SKILL-v2-monolithic.md, section `review-workflow`, line 332
**Authority:** core
**Proposed section ID:** `review-loop-tracking`
**Duplication note:** Not in database-queries.md — only inline in SKILL-v2
**Modification needed:** Formalize as a template. Currently just inline SQL: `SELECT COUNT(*) FROM orchestration_messages WHERE task_id = ? AND message_type = 'review_request'`. Should be a proper template with the 5-cycle cap rule.

**Content summary:**
```sql
SELECT COUNT(*) FROM orchestration_messages
WHERE task_id = 'task-XX' AND message_type = 'review_request';
```
- Cap at 5 cycles per checkpoint
- At cycle 5, route to Repetiteur Protocol (autonomous — no user escalation). User involved only if Repetiteur also escalates.

---

## 23. Eager RAG Processing Trigger (from SKILL-v2-monolithic.md)
**Source:** SKILL-v2-monolithic.md, section `review-workflow`, lines 358-361
**Authority:** core
**Proposed section ID:** `eager-rag-trigger` (or inline in review-workflow section)
**Duplication note:** This is the entry point to RAG processing from review context. Links to the full RAG workflow (proposal #14).
**Modification needed:**
- DELETED — "add entry to STATUS.md 'Pending RAG Processing' section" → replace with in-session tracking (1m context) or simple temp/ file list per team lead resolution
- Per routing constraint: at the boundary where review hands off to RAG processing, name the RAG Processing section (co-located in this file) but the review-workflow section itself doesn't implement the RAG procedure inline

**Content summary:**
- After approving a completion review, check for RAG proposals (type: rag-addition in proposals/)
- Check orchestration_tasks for other tasks in needs_review or error state
- If none pending: launch RAG processing immediately
- If other reviews pending: handle those first, RAG deferred to monitoring fallback

---

## 24. Review-Related Content from Monitoring Section (from SKILL-v2-monolithic.md)
**Source:** SKILL-v2-monolithic.md, section `monitoring`, lines 299-307 (steps 5, 5.5, 6.5)
**Authority:** core, mandatory
**Proposed section ID:** Not a separate section — this is routing/integration context
**Duplication note:** The monitoring section (which becomes part of phase-execution.md) routes to review-protocol.md at step 5 ("Handle event — Route to Review Workflow"). Steps 5.5 and 6.5 are post-review re-entry points in monitoring.
**Modification needed:** In review-protocol.md, the final step should say "After review completes, proceed to Phase Execution Protocol (monitoring re-entry at step 5.5)" — naming the protocol per routing constraint. Not implementing the monitoring procedure.

---

## 25. Self-Correction Flag Handling (from SKILL-v2-monolithic.md + review-checklists.md)
**Source:** SKILL-v2-monolithic.md lines 330-331, review-checklists.md lines 87-88
**Authority:** core
**Proposed section ID:** Part of `review-workflow` section (step 3)
**Duplication note:** Referenced in both sources, plus session-handoff.md context-situation-checklist
**Modification needed:** Consolidate both descriptions into authoritative version. Key rule: if Self-Correction: YES, context estimates are ~6x bloated. If actual inline with estimate → tell musician to reset flag. If actual > 2x estimated → warn about needing additional session.

---

---

# Summary

## Content migrating INTO review-protocol.md:

| # | Description | Source File(s) | Authority |
|---|-------------|---------------|-----------|
| 1 | Review Workflow Core (9 steps) | SKILL-v2-monolithic.md | mandatory + core + guidance |
| 2 | Smoothness Scale (detailed) | review-checklists.md, state-machine.md | core |
| 3 | Decision Thresholds | review-checklists.md, SKILL-v2-monolithic.md | core |
| 4 | Context Situation Checklist | review-checklists.md, session-handoff.md | core |
| 5 | Score Aggregation | review-checklists.md | core + guidance |
| 6 | Subagent Self-Review (FACTS) | review-checklists.md | core |
| 7 | Conductor Strategy Checklist | review-checklists.md | core + guidance |
| 8 | Review Approval SQL | database-queries.md Pattern 4 | core + template |
| 9 | Review Rejection SQL | database-queries.md Pattern 5 | core + template |
| 10 | Review Request SQL (reference) | database-queries.md Pattern 3 | core + template |
| 11 | Pending Reviews Query | database-queries.md Pattern 12 | core + template |
| 12 | Review State Transitions | state-machine.md | core |
| 13 | Heartbeat Rule | state-machine.md | mandatory |
| 14 | RAG Processing Workflow | rag-coordination-workflow.md (full) | mandatory + core + guidance + templates |
| 15 | Checklist Overview Table | review-checklists.md | core |
| 22 | Review Loop Tracking Query | SKILL-v2-monolithic.md (inline) | core |
| 23 | Eager RAG Trigger | SKILL-v2-monolithic.md | core |
| 25 | Self-Correction Flag Handling | SKILL-v2-monolithic.md + review-checklists.md | core |

## Content NOT migrating (DELETED per design):

| # | Description | Reason |
|---|-------------|--------|
| 16 | STATUS.md Template | DELETED — STATUS.md eliminated per design Section 8 |
| 17 | STATUS.md Reading Strategy | DELETED — entire file deleted per design Section 12 |
| 18 | Recovery Instructions Template | DELETED — entire file deleted per design Section 12 |
| 19 | 200k context references | UPDATE — change to 1m wherever they appear |

## Content that routes TO review-protocol.md but lives elsewhere:

| # | Description | Lives In |
|---|-------------|----------|
| 20 | Parallel coordination step 8 | phase-execution.md |
| 21 | Sequential coordination step 6 | phase-execution.md |
| 24 | Monitoring steps 5/5.5/6.5 | phase-execution.md |

## Resolved Decisions

1. **FACTS/Strategy checklists (#6, #7):** Stay in review-protocol.md. They are used during review evaluation — this protocol's job.
2. **RAG Processing Workflow (#14):** Stays as a section within review-protocol.md, not a separate protocol file. It triggers after reviews.
3. **Autonomous operation:** All "escalate to user" becomes "Conductor decides or routes to Repetiteur Protocol." Review is fully autonomous post-bootstrap. Applied throughout proposals #1, #14, #22, #23.
4. **Pending RAG tracking:** Track in-session (1m context) or simple temp/ file list. No STATUS.md replacement needed. Applied throughout proposals #1, #14, #23.
