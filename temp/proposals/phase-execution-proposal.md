# Phase Execution Protocol — Extraction Proposal

**Date:** 2026-02-19
**Protocol:** Phase Execution
**Target file:** `references/protocols/phase-execution.md`
**Scope:** The primary orchestration loop: reading Arranger plan phase sections, task decomposition, Copyist teammate launch, Musician launch commands (kitty with PID capture), monitoring cycle (background watcher setup, state change detection and routing), danger file governance, parallel and sequential coordination patterns.

---

## 1. Arranger Plan Consumption (per-phase reading)
**Source:** Design document Section 4 (Arranger Plan Consumption), lines 142-163
**Authority:** core
**Proposed section ID:** plan-consumption
**Duplication note:** Plan-index and lock indicator checking belongs in initialization protocol; per-phase reading belongs here
**Modification needed:** NEW CONTENT — this is entirely new from the design document. The old skill had no Arranger plan concept. Key content:
- Per-phase start: Read `phase:N` section + `conductor-review-N` section via plan-index line ranges
- Pass to Copyist: Same line range + task ID assignments + Overrides & Learnings
- During reviews/errors: Phase context already loaded from step 2
- Phase complete: Verify against conductor-review-N checklist items, then move to next phase
- Context scales with phase count, not plan size — never load full document or future phases upfront

---

## 2. Phase Analysis and Danger File Assessment
**Source:** references/danger-files-governance.md, lines 1-175 (entire file)
**Authority:** core (sections definition, governance-flow, mitigation-patterns, reporting-format) + context (examples)
**Proposed section ID:** danger-file-assessment
**Duplication note:** None — this is Phase Execution specific
**Modification needed:** None — content migrates as-is. The 3-Step Governance Flow (Step 1: Implementation Plan, Step 2: Conductor Review, Step 3: Conductor Handoff) and all mitigation patterns (ordering within tasks, append-only, conductor batching, sequential sub-steps) belong here. Skip conditions also belong here.

---

## 3. Phase Planning & Task Decomposition (from monolithic SKILL.md)
**Source:** SKILL-v2-monolithic.md, section id="phase-planning", lines 132-205
**Authority:** core + mandatory (the subagent launch mandate)
**Proposed section ID:** task-decomposition
**Duplication note:** The Copyist subagent prompt template (item 7 below) is a key sub-component
**Modification needed:** UPDATE per design doc:
- Plan reading now uses Arranger line ranges, not full file reads
- The Overrides & Learnings now includes Arranger conductor-review-N context
- The delegation model now specifies **Teammates (>40k estimated tokens)** for Copyist launches instead of regular Task subagents (Design Section 3, Delegation Model)
- All steps otherwise migrate as-is (analyze phase, review danger files, prepare overrides, launch copyist, review instructions, insert DB rows, insert instruction messages)

Content includes:
- Step 1: Analyze phase — task type, danger files, inter-task dependencies
- Step 2: Review danger files (pointer to danger-file-assessment section)
- Step 3: Prepare overrides & learnings
- Step 4: Launch Copyist teammate (mandatory, with template)
- Step 5: Review returned instructions
- Step 6: Insert database rows
- Step 7: Insert instruction messages
- Mandatory rule: Musician claims task only after BOTH task row AND instruction message exist

---

## 4. Copyist Subagent/Teammate Prompt Template
**Source:** references/subagent-prompt-template.md, lines 1-155 (entire file)
**Authority:** core + template (follow="format") + guidance (pre-fetching RAG)
**Proposed section ID:** copyist-launch-template
**Duplication note:** None — Phase Execution specific
**Modification needed:** UPDATE per design doc Section 3 (Delegation Model):
- Change from `Task(...)` subagent to Teammate invocation for >40k token work
- The template structure and placeholders remain the same
- Conductor usage section (filling template, after-return review) migrates as-is
- Pre-fetching RAG guidance migrates as-is
- The ENH-L validation checklist and ENH-M checkpoint design guidance migrate as-is

---

## 5. Database Row Insertion (Task Creation)
**Source:** references/database-queries.md, Pattern 1 (lines 137-145), Pattern 14 (lines 376-391)
**Authority:** template (follow="exact" for Pattern 1, follow="exact" for Pattern 14)
**Proposed section ID:** database-task-creation
**Duplication note:** DDL goes to initialization protocol; these patterns are phase-execution specific
**Modification needed:** None — SQL migrates as-is

Pattern 1 content:
```sql
INSERT INTO orchestration_tasks (task_id, state, instruction_path, last_heartbeat)
VALUES ('task-03', 'watching', 'docs/tasks/task-03.md', datetime('now'));
```

Pattern 14 content:
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', 'task-00',
    'TASK INSTRUCTION: docs/tasks/task-03.md
     Type: parallel
     Phase: 2
     Dependencies: none',
    'instruction'
);
```

---

## 6. Dynamic Row Management
**Source:** references/database-queries.md, section id="dynamic-row-management", lines 493-510
**Authority:** core
**Proposed section ID:** database-task-creation (subsection)
**Duplication note:** None
**Modification needed:** None — "Tables persist across phases. Add rows as phases launch" content migrates as-is

---

## 7. Musician Launch Prompt Template
**Source:** references/musician-launch-prompt-template.md, lines 1-196 (entire file)
**Authority:** mandatory (all sessions must use template) + template (follow="exact") + core + context
**Proposed section ID:** musician-launch
**Duplication note:** Replacement session launch template also appears in session-handoff.md (belongs in musician-lifecycle protocol)
**Modification needed:** UPDATE per design doc Section 6 (Musician Lifecycle):
- Launch command now includes PID capture: `kitty ... & echo $! > temp/musician-task-03.pid`
- Template structure otherwise unchanged
- Conductor usage table, filled-in example, launching multiple tasks, design points all migrate
- Context references to "200k-token context" should be updated: **UPDATE — change to 1m per design** (Design Section 11, I4)

Key content:
- Kitty launch command template with placeholders
- Filled-in example
- Launching multiple tasks (parallel phase)
- Launching replacement sessions (handoff) — note: also in musician-lifecycle protocol
- Design points (why /musician first, SQL query explicit, message-driven, etc.)
- Integration with Copyist skill

---

## 8. Sequential Coordination Pattern
**Source:** references/sequential-coordination.md, lines 1-172 (entire file)
**Authority:** core + template (follow="exact" for SQL, follow="exact" for launch command) + context
**Proposed section ID:** sequential-execution
**Duplication note:** The launch template (section id="conductor-workflow", step 4) duplicates musician-launch-prompt-template.md — intentional SQL co-location
**Modification needed:** UPDATE per design:
- PID capture on launch command (Design Section 6)
- STATUS.md references should be flagged: **DELETED — STATUS.md eliminated per design** (Design Section 8)
- Context references to "200k" → **UPDATE — change to 1m per design**

Content includes:
- When to use (single task, strict ordering, foundation tasks, shared resources)
- Key characteristics (self-configuring hooks, no background subagent, manual message checks, single session)
- Conductor workflow steps 1-7 (create instruction, insert row, insert message, launch session, monitor polling, handle review, wait for completion)
- Execution session workflow (claim, execute, check messages, complete)
- Comparison table with parallel pattern

---

## 9. Parallel Coordination Pattern
**Source:** references/parallel-coordination.md, lines 1-296 (entire file)
**Authority:** core + mandatory + template (follow="exact") + guidance + context
**Proposed section ID:** parallel-execution
**Duplication note:**
- Launch template duplicates musician-launch-prompt-template.md (intentional)
- Monitoring subagent design duplicates monitoring cycle below (intentional)
- Session handoff flow also in session-handoff.md (musician-lifecycle protocol)
- Error prioritization also relevant to error-recovery protocol
**Modification needed:** UPDATE per design:
- PID capture on all launch commands (Design Section 6)
- STATUS.md references → **DELETED — STATUS.md eliminated per design**
- "200k-token context" → **UPDATE — change to 1m per design**
- Phase completion step 4 "Update STATUS.md phase status" → **DELETED — STATUS.md eliminated per design**
- Watcher design: add `<mandatory>` reinforcement at every failure point per Design Section 9

Content includes:
- When to use (3+ independent tasks)
- Key characteristics (custom hook, background monitoring, review checkpoints, danger files, error recovery)
- Conductor workflow steps 1-8 (analyze danger files, create instructions batch, insert DB rows, insert instruction messages, launch verification watcher, launch kitty windows, launch main monitoring subagent, handle events)
- Session handoff flow (detect → read HANDOFF → assess type → set fix_proposed → send msg → launch replacement)
- Error prioritization (errors → reviews → completions)
- Phase completion (check proposals, verify, integrate, proceed)
- Execution session workflow (hooks, claim, launch subagent, execute, review checkpoint, process review, complete)
- Monitoring subagent design (template)
- Context budget for parallel phases
- Emergency broadcasts (guidance)

---

## 10. Monitoring Cycle
**Source:** SKILL-v2-monolithic.md, section id="monitoring", lines 263-315
**Authority:** core + mandatory (background watcher exit behavior)
**Proposed section ID:** monitoring-cycle
**Duplication note:**
- The monitoring subagent prompt template also appears in parallel-coordination.md
- RAG processing step 6.5 also in rag-coordination-workflow.md (belongs in review protocol)
**Modification needed:** UPDATE per design:
- STATUS.md tiered reading strategy reference → **DELETED — STATUS.md eliminated per design**
- Monitoring cycle steps remain but STATUS.md references removed
- Add `<mandatory>` reinforcement at every watcher failure point per Design Section 9:
  - Watcher launch (must verify running before any work)
  - Watcher re-launch after every event handling cycle
  - Heartbeat refresh (task-00 must stay alive)
  - Watcher exit behavior (must exit on state change, not loop)
  - Watcher re-launch after review/error handling completes
  - Watcher polling interval adherence
  - Message deduplication (don't re-process old messages)
- Step 6.5 RAG processing reference should point to review protocol (not inline)
- "200k" references → **UPDATE — change to 1m per design**

Content includes:
- Background watcher exit behavior contract (mandatory)
- 7-step conductor monitoring cycle
- Step 5.5 check table for additional changes
- Heartbeat management context
- validate-coordination.sh reference

---

## 11. Monitoring Subagent Prompt Template
**Source:** references/parallel-coordination.md, section id="monitoring-subagent-design", lines 256-280
**Authority:** core + template (follow="format")
**Proposed section ID:** monitoring-subagent-template
**Duplication note:** Also relevant to parallel-execution section; co-locate here for completeness
**Modification needed:** None — template migrates as-is. The Task(...) format stays for monitoring (< 40k tokens, per Design Section 3 delegation model).

Content:
```
Task("Monitor Phase 2 tasks", prompt="""
Poll orchestration_tasks every 30 seconds using comms-link query.
Check staleness: if any task state is 'working'/'review_approved'/'review_failed'/'fix_proposed' and last_heartbeat >540 seconds old, report as stale.
Check for state changes in: task-03, task-04, task-05, task-06.
Detect fallback rows (task_id LIKE 'fallback-%').
Also refresh conductor heartbeat.
Report back immediately when any task reaches: needs_review, error, complete, exited.
""", subagent_type="general-purpose", model="opus", run_in_background=True)
```

---

## 12. Launch Verification Watcher
**Source:** SKILL-v2-monolithic.md, section id="launching-execution-sessions", lines 253-259
**Authority:** core
**Proposed section ID:** launch-verification
**Duplication note:** Also in parallel-coordination.md step 5
**Modification needed:** None — the concept of launching a verification watcher before kitty windows migrates as-is. Points to monitoring-subagent-prompts example file for the specific prompt.

---

## 13. State Machine — Working/Needs_Review/Error Transitions (Monitoring-Relevant)
**Source:** references/state-machine.md, sections: execution-states (lines 52-69), state-transition-flows (lines 82-106), heartbeat-rule (lines 122-136), staleness-detection (lines 138-158)
**Authority:** core + mandatory (heartbeat rule) + template (staleness SQL)
**Proposed section ID:** state-transitions-monitoring
**Duplication note:** Full state machine summary belongs in initialization protocol; these specific transitions are co-located here for monitoring context
**Modification needed:** None — transitions and heartbeat rules migrate as-is

Content includes:
- Execution states table (working, needs_review, review_approved, review_failed, error, fix_proposed, complete, exited)
- State transition flows (happy path, review rejection, error path, retry exhaustion)
- Heartbeat rule (mandatory: update last_heartbeat on EVERY state transition)
- Staleness detection SQL (540-second threshold)

---

## 14. Emergency Broadcasts
**Source:** SKILL-v2-monolithic.md, section id="emergency-broadcasts", lines 384-410
**Authority:** core + template (follow="exact")
**Proposed section ID:** emergency-broadcasts
**Duplication note:** Also referenced in parallel-coordination.md as guidance
**Modification needed:** None — migrates as-is

Content: One INSERT per task_id with message_type = 'emergency'. Each musician watcher detects via its own task's message log.

---

## 15. Database Queries — Monitoring Patterns
**Source:** references/database-queries.md:
- Pattern 11: Monitor All Tasks (lines 334-346)
- Pattern 12: Check for Pending Reviews/Messages (lines 348-361)
- Pattern 13: Staleness Detection (lines 363-374)
- Pattern 17: Refresh Conductor Heartbeat (lines 428-440)
- Pattern 19: Detect and Cleanup Fallback Rows (lines 468-491)
**Authority:** template (follow="exact" for all)
**Proposed section ID:** monitoring-queries
**Duplication note:** These SQL patterns are co-located in phase-execution per SQL co-location design principle
**Modification needed:** None — SQL migrates as-is

---

## 16. Database Queries — Phase Launch Patterns
**Source:** references/database-queries.md:
- Pattern 2: Atomic Task Claim (lines 148-165) — execution-side but relevant context for conductor
- Pattern 16: Emergency Broadcast (lines 410-426)
**Authority:** template (follow="exact") + mandatory (verify rows_affected = 1)
**Proposed section ID:** launch-queries
**Duplication note:** Pattern 2 (atomic claim) also belongs in musician skill; co-located here for conductor awareness
**Modification needed:** None

---

## 17. Event Routing (from Monitoring to Other Protocols)
**Source:** SKILL-v2-monolithic.md, section id="monitoring", lines 298-307 (step 5 handle event routing) + references/parallel-coordination.md, section id="conductor-workflow" step 8 Handle Events, lines 158-169
**Authority:** core
**Proposed section ID:** event-routing
**Duplication note:** This is a boundary section — routes to review protocol, error-recovery protocol, completion protocol, musician-lifecycle protocol. Per the routing constraint (Design Section 2), this section names next protocols but does NOT include reference tags to those protocol files.
**Modification needed:** UPDATE per design:
- Routing must follow the protocol-dispatching architecture: name the protocol, conductor returns to SKILL.md
- Event types and routing:
  - `needs_review` → "Proceed to Review Protocol"
  - `error` → "Proceed to Error Recovery Protocol"
  - `complete` → "Proceed to Completion Protocol" (if all tasks done) or update tracking
  - `exited` → "Proceed to Musician Lifecycle Protocol"
- After handling, return to monitoring cycle step 5.5 (check table for additional changes)

---

## 18. PID Tracking (NEW from design)
**Source:** Design document Section 6, lines 199-205
**Authority:** core
**Proposed section ID:** pid-tracking
**Duplication note:** Also belongs in musician-lifecycle protocol for cleanup
**Modification needed:** NEW CONTENT from design:
- Launch: `kitty ... & echo $! > temp/musician-task-03.pid`
- Detection: Handled by existing comms-link monitoring (state changes)
- Cleanup rules: parallel tasks close all windows when ALL siblings complete/exited; sequential close immediately; re-launch closes old IMMEDIATELY before replacement

---

## 19. Sentinel Teammate Launch (NEW from design)
**Source:** Design document Section 7, lines 232-257
**Authority:** core
**Proposed section ID:** sentinel-launch
**Duplication note:** Full sentinel monitoring protocol is a separate protocol file (sentinel-monitoring.md); this section covers only the launch during phase execution
**Modification needed:** NEW CONTENT from design:
- Launched when Musicians launch for a phase
- Runs alongside the background message-watcher subagent
- Shut down when Conductor messages it that the phase is complete
- Reference to sentinel-monitoring protocol for anomaly criteria and behavior details

---

## 20. Subagent Failure Handling (Phase Planning Context)
**Source:** references/subagent-failure-handling.md, section id="integration-with-workflow" → "During Phase Planning", lines 215-229
**Authority:** core
**Proposed section ID:** copyist-failure-handling
**Duplication note:** Full failure handling (all categories, retry flowchart, escalation) belongs in error-recovery protocol. Only the phase-planning integration context belongs here.
**Modification needed:** None — the "During Phase Planning" integration workflow migrates as-is. Points to error-recovery protocol for full failure categories and retry logic.

---

## 21. Phase Completion Gate
**Source:** references/parallel-coordination.md, section id="phase-completion", lines 224-238
**Authority:** core
**Proposed section ID:** phase-completion
**Duplication note:** Final orchestration completion (all phases done) belongs in completion protocol; this is per-phase completion
**Modification needed:** UPDATE per design:
- Step 4 "Update STATUS.md phase status" → **DELETED — STATUS.md eliminated per design**
- Step 2 "Verify no proposals stuck in temp/" stays
- Step 1 check proposals stays
- Step 3 integrate critical proposals stays
- Step 5 "Proceed to next phase" stays
- Add: verify against Arranger's conductor-review-N checklist items (Design Section 4)

---

## 22. Autonomous Operation Model (NEW from design)
**Source:** Design document Section 3, lines 106-138
**Authority:** core + mandatory (authority scope)
**Proposed section ID:** autonomous-operation
**Duplication note:** Bootstrap (interactive) part belongs in initialization protocol; post-bootstrap autonomous model belongs here
**Modification needed:** NEW CONTENT from design:
- Post-bootstrap: Phase planning, Copyist launching, Musician launching, monitoring, review handling — all without user prompts
- User-visible progress output at checkpoints
- User can interrupt but Conductor doesn't wait
- Escalation chain: Conductor (5 corrections) → Repetiteur → User (vision only)
- Authority scope: can modify intra-phase directions; cannot modify cross-phase dependencies, architectural decisions, `<mandatory>` items
- Delegation model: Teammates (>40k) vs regular Task subagents (<40k)

---

## 23. Orchestration Principles — Delegation Patterns (Context)
**Source:** references/orchestration-principles.md, section id="delegation-patterns", lines 115-157
**Authority:** core + guidance (anti-patterns)
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**NOT THIS PROTOCOL — SKILL.md preamble/context absorption.** High-level principles, not protocol procedures. The design file mapping confirms: orchestration-principles.md is "Absorbed into SKILL.md `<context>` sections."

---

## 24. Orchestration Principles — Context Headroom (Context)
**Source:** references/orchestration-principles.md, section id="context-headroom", lines 16-60
**Authority:** core + context
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**NOT THIS PROTOCOL — SKILL.md preamble/context absorption.** High-level principles, not protocol procedures. The design file mapping confirms: orchestration-principles.md is "Absorbed into SKILL.md `<context>` sections."

---

## 25. Orchestration Principles — External Sessions vs Subagents
**Source:** references/orchestration-principles.md, section id="external-sessions-vs-subagents", lines 63-112
**Authority:** mandatory + core
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**NOT THIS PROTOCOL — SKILL.md preamble/context absorption.** High-level principles, not protocol procedures. The design file mapping confirms: orchestration-principles.md is "Absorbed into SKILL.md `<context>` sections."

---

## 26. Orchestration Principles — Overload Signs
**Source:** references/orchestration-principles.md, section id="overload-signs", lines 159-186
**Authority:** core
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**NOT THIS PROTOCOL — SKILL.md preamble/context absorption.** High-level principles, not protocol procedures. The design file mapping confirms: orchestration-principles.md is "Absorbed into SKILL.md `<context>` sections."

---

## 27. Launching Execution Sessions Section (Monolithic SKILL.md)
**Source:** SKILL-v2-monolithic.md, section id="launching-execution-sessions", lines 207-261
**Authority:** mandatory + core + template (follow="exact")
**Proposed section ID:** musician-launch (merges with item 7)
**Duplication note:** Overlaps heavily with musician-launch-prompt-template.md — this is the SKILL.md version that references the template
**Modification needed:** UPDATE per design:
- PID capture on launch commands (Design Section 6)
- Launch sequence steps migrate as-is (launch verification watcher, launch kitty windows, watcher behavior, after verification start main monitoring)
- "Background message-watcher is REQUIRED" mandatory rule stays

---

## 28. Database Queries — Review-Related (Conductor Actions During Monitoring)
**Source:** references/database-queries.md:
- Pattern 4: Approve Review (lines 198-214)
- Pattern 5: Reject Review (lines 216-235)
- Pattern 7: Propose Fix (lines 264-282)
- Pattern 9: Request Exit (lines 309-319)
**Authority:** template (follow="format" for 4,5,7; follow="exact" for 9)
**Proposed section ID:** conductor-action-queries
**Duplication note:** Patterns 4, 5, 7 also belong in review protocol and error-recovery protocol respectively. Co-located here per SQL co-location principle for completeness. Pattern 9 also in initialization/completion.
**Modification needed:** None — SQL migrates as-is

---

## 29. RAG Query Guide — Conductor Queries (Phase Planning Context)
**Source:** references/rag-query-guide.md, section id="conductor-queries", lines 34-51
**Authority:** core
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**NOT THIS PROTOCOL — SKILL.md preamble/context absorption.** RAG query patterns are inline guidance, not protocol procedures. The design file mapping confirms: rag-query-guide.md is "Absorbed into relevant protocol files as inline guidance." Individual queries may be added as `<guidance>` tags during content creation phase if needed, but are not structural protocol content.

---

## 30. STATUS.md References Throughout
**Multiple sources across all files above**
**Authority:** N/A
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** **DELETED — STATUS.md eliminated per design** (Design Section 8). All references to:
- "Update STATUS.md" → remove
- "Read STATUS.md" → use database queries instead
- STATUS.md reading strategy → eliminated
- Recovery Instructions in STATUS.md → unnecessary with 1m context
- Task Planning Notes in STATUS.md → Conductor holds in-session with 1m context
- Proposals Pending in STATUS.md → tracked in database or in-session

Specific references to flag and remove:
- Monitoring section: tiered STATUS.md reading strategy
- Phase completion: "Update STATUS.md phase status"
- Parallel coordination phase completion step 4
- Overload signs: "Write key facts to Task Planning Notes"
- Context management: "Write Recovery Instructions to STATUS.md"
- Review workflow step 8: "add entry to STATUS.md 'Pending RAG Processing' section"
- RAG coordination: STATUS.md "Pending RAG Processing" section references

---

## 31. Context References (200k → 1m)
**Multiple sources across all files**
**Authority:** N/A
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** **UPDATE — change to 1m per design** (Design Section 11, I4). Specific instances:
- orchestration-principles.md line 22: "200k-token context window"
- orchestration-principles.md line 59: "120-160k tokens of headroom"
- orchestration-principles.md line 74: "own 200k-token context"
- orchestration-principles.md line 104: "Own 200k"
- parallel-coordination.md line 292: context budget figures need recalculation
- SKILL-v2-monolithic.md line 537: "200k-token budget"
- SKILL-v2-monolithic.md line 544: "200k context"
- Multiple launch command references: "own 200k context"

---

## Summary

### Content by Authority Level

**Mandatory:**
- Musician skill launch template adherence (item 7)
- Background message-watcher required for all sessions (item 10)
- Background watcher exit behavior contract (item 10)
- Heartbeat rule — update on EVERY state transition (item 13)
- Copyist subagent launch — do not skip (item 3)
- Musician claims only after BOTH task row AND instruction message (item 3)
- Watcher reinforcement at every failure point (item 10, Design Section 9)

**Core:**
- Plan consumption model (item 1 — NEW)
- Danger file assessment (item 2)
- Task decomposition workflow (item 3)
- Copyist launch template (item 4)
- Database task creation (items 5-6)
- Musician launch template (item 7)
- Sequential coordination (item 8)
- Parallel coordination (item 9)
- Monitoring cycle (item 10)
- Monitoring subagent template (item 11)
- State transitions for monitoring (item 13)
- Emergency broadcasts (item 14)
- Monitoring queries (item 15)
- Event routing (item 17)
- PID tracking (item 18 — NEW)
- Sentinel teammate launch (item 19 — NEW)
- Phase completion gate (item 21)
- Autonomous operation model (item 22 — NEW)

**NOT THIS PROTOCOL (SKILL.md preamble/context absorption):**
- Delegation patterns (item 23)
- Context headroom (item 24)
- External sessions vs subagents (item 25)
- Overload signs (item 26)
- RAG query patterns (item 29)

### Deletions
- All STATUS.md references (item 30) — **DELETED per design**
- Recovery instructions template content — **DELETED per design**
- STATUS.md reading strategy content — **DELETED per design**

### Updates Required
- All "200k" context references → "1m" (item 31)
- All launch commands need PID capture (items 7, 8, 9, 27)
- Copyist launch changes from Task subagent to Teammate for >40k work (items 3, 4)
- Watcher `<mandatory>` reinforcement at all failure points (item 10)
- Plan consumption now uses Arranger line ranges (item 1)
- Autonomous operation model (no user interaction post-bootstrap) (item 22)
- Sentinel teammate launch added to phase execution (item 19)

### New Content (from design document)
- Arranger plan consumption per-phase reading model (item 1)
- PID tracking for musician lifecycle (item 18)
- Sentinel teammate launch during phase execution (item 19)
- Autonomous operation post-bootstrap model (item 22)
- Watcher reinforcement mandatory rules (item 10)
