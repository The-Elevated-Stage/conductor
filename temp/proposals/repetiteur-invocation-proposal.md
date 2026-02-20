# Repetiteur Invocation Protocol — Extraction Proposal

**Protocol file:** `references/protocols/repetiteur-invocation.md`
**Date:** 2026-02-20

---

## Summary

The Repetiteur Invocation Protocol is **almost entirely NEW content** from the design documents. The Repetiteur is a new skill, so the existing monolithic SKILL.md has no Repetiteur section. Some ancillary content exists in session-handoff.md (handoff message patterns) and database-queries.md (state transition SQL), but the core protocol content comes from:

- **Primary:** Conductor Overhaul Design, Section 5 (Repetiteur Integration)
- **Secondary:** Repetiteur Design, Section 2 (Invocation & Input Context), Section 4 Stage 1 (Ingestion — what Conductor provides), Section 7 (Conductor Communication & Plan Transition)
- **Tertiary:** Conductor Overhaul Design, Section 3 (Autonomous Operation — escalation chain, authority scope)

---

## 1. Repetiteur Spawn Prompt Template (Teammate with Opus 1m)
**Source:** [Conductor Overhaul Design, Section 5 — Launch Protocol]; [Repetiteur Design, Section 2 — Invocation Mechanism + Structured Blocker Report]
**Authority:** mandatory
**Proposed section ID:** spawn-prompt-template
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. Must be synthesized from both design documents. The conductor overhaul describes the spawn mechanics (teammate, opus, 1m context); the repetiteur design describes the exact structured blocker report format the spawn prompt must contain. Template needs to be created from these specifications — neither design has a ready-made template.

Content to include:
- Teammate spawn via Task tool (or SendMessage-based teammate creation) with `model="opus"` and team_name matching conductor's active team
- The spawn prompt structure: `/repetiteur` skill invocation + structured blocker report
- All mandatory blocker report fields (from repetiteur design Section 2):
  - Blocker Description (what failed, what was tried, why it exceeds authority, which tasks)
  - Plan State (plan path, revision number, task completion state, phase number)
  - Current Phase Task State (instruction file paths, per-task status, blocking task's instruction + error report)
  - Artifact References (design doc path, decision journal directory path, list of journals)
  - Git State (branch, commit summary since plan execution began, uncommitted changes)

---

## 2. Structured Blocker Report Format
**Source:** [Repetiteur Design, Section 2 — Structured Blocker Report subsection, full specification]
**Authority:** mandatory
**Proposed section ID:** blocker-report-format
**Duplication note:** None — unique to this protocol. The Repetiteur skill's own references will have this format from the receiving end.
**Modification needed:** New content from design. Verbatim from repetiteur design — all fields are mandatory, the Conductor must provide them completely.

Content to include:
- Complete field specification with all 5 categories (Blocker Description, Plan State, Current Phase Task State, Artifact References, Git State)
- Per-field documentation of what to include
- Note that Current Phase Task State requires a subagent to read task instruction files and return summaries
- Note that prior completed phases do NOT get task-level breakdown

---

## 3. Blocker Report Persistence to decisions/{feature-name}/
**Source:** [Conductor Overhaul Design, Section 5 — Launch Protocol, item 2: "Writes the structured blocker report to `decisions/{feature-name}/` (crash recovery insurance)"]
**Authority:** mandatory
**Proposed section ID:** blocker-report-persistence
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. The design specifies that before spawning, the Conductor persists the blocker report as crash recovery insurance. Need to define the file naming convention (e.g., `blocker-report-rN.md` in the decisions directory) and the persistence step in the pre-spawn checklist.

Content to include:
- File path: `docs/plans/designs/decisions/{feature-name}/blocker-report-rN.md` (where N matches the plan revision that will be produced)
- Write the structured blocker report to this path BEFORE spawning the Repetiteur
- Rationale: crash recovery insurance — if session dies during consultation, the context of why help was summoned is preserved
- This file persists alongside journals; the Repetiteur may also read it if the spawn message is lost

---

## 4. Consultation Count Check (Refuse r4)
**Source:** [Conductor Overhaul Design, Section 5 — Launch Protocol, item 3: "Checks plan revision number — refuses to spawn if revision would be r4"]; [Repetiteur Design, Section 1 — Consultation Limits]
**Authority:** mandatory
**Proposed section ID:** consultation-count-check
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. The conductor overhaul says the Conductor checks the plan revision number and refuses to spawn if it would produce r4. The repetiteur design explains the rationale (3 failed approaches means vision-level problem). Must synthesize into a concrete pre-spawn check.

Content to include:
- Before spawning: read current plan's revision metadata (from `<!-- revision:N -->` in the plan-index)
- If current revision is `r3` (meaning next would be `r4`): refuse to spawn
- Instead, escalate to user with message: "Three consultations exhausted. The problem likely requires design-level revision. [Details of what was tried in r1, r2, r3]."
- Derivation: revision number comes from plan filename or plan-index metadata — no separate counter needed

---

## 5. Pause All Musicians Before Spawning
**Source:** [Conductor Overhaul Design, Section 5 — Launch Protocol, item 1: "Pauses all running Musicians"]; [Repetiteur Design, Section 2 — Invocation Mechanism, item 2: "Conductor pauses all running musicians (no parallel work during consultation)"]
**Authority:** mandatory
**Proposed section ID:** pause-musicians
**Duplication note:** SQL for emergency broadcast may duplicate from phase-execution.md (emergency broadcast pattern). This is expected per SQL co-location design.
**Modification needed:** New content from design. Need to define HOW to pause musicians. Design says "pauses all running Musicians" but doesn't specify mechanism explicitly. Inferred from existing patterns:

Content to include:
- Send emergency broadcast to ALL active tasks with message explaining consultation pause
- SQL: one INSERT per active task_id with `message_type = 'emergency'` and message: "CONSULTATION PAUSE: Repetiteur consultation in progress. Pause all work. Do not proceed with any new steps. Await further instructions."
- Query `orchestration_tasks WHERE state IN ('working', 'needs_review', 'review_approved', 'review_failed', 'fix_proposed')` to find active tasks
- Musicians' watcher subagents will detect the emergency message and pause
- Rationale (from repetiteur design decisions): "Simplifies state management. The Repetiteur's impact assessment might reveal that 'unaffected' work is actually affected. Pausing everything prevents compounding changes during re-planning."

---

## 6. Communication Patterns During Consultation (Conductor as Ground-Truth Provider)
**Source:** [Repetiteur Design, Section 7 — Communication Patterns During Consultation]; [Repetiteur Design, Section 4 Stage 1 — Ingestion, "After parallel tracks complete" — Conductor dialogue]; [Repetiteur Design, Section 4 Stage 3 — Adaptive Resolution, "Conductor dialogue during resolution"]
**Authority:** core
**Proposed section ID:** consultation-communication
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. The repetiteur design describes three communication phases from the Repetiteur's perspective. This protocol describes them from the Conductor's perspective (what to expect, how to respond).

Content to include:
- **Ingestion clarifications (Stage 1):** Brief, targeted questions to fill gaps in the blocker report. Conductor answers from execution context. Not extended discussion. Examples from design: "Which specific API call returned the error?", "Did the musician attempt [alternative] before failing?", "What state is [component] in currently?"
- **Ground-truth validation (Stage 3):** Key decision points during resolution. Conductor provides execution perspective — what actually happened during implementation vs what the plan prescribed. Examples from design: "I'm proposing to change [approach A] to [approach B]. From your execution perspective, does this conflict with anything already implemented?"
- **Conductor disagreement:** If Conductor explicitly disagrees with proposed approach, the Repetiteur must resolve the concern before proceeding. If persistent disagreement, escalates to user. Conductor should provide specific, factual objections (not general concerns).
- **Conductor's role is perspective, not approval.** The Repetiteur makes the final decision. Conductor provides ground-truth information.

---

## 7. Passthrough User-to-Repetiteur Communication
**Source:** [Conductor Overhaul Design, Section 5 — Passthrough Communication]
**Authority:** mandatory
**Proposed section ID:** passthrough-communication
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. Verbatim from the overhaul design.

Content to include:
- During consultation, user input typed in the Conductor terminal is relayed to the Repetiteur via SendMessage verbatim — no interpretation or filtering
- Reverse direction works naturally (Repetiteur's SendMessage appears in Conductor output)
- When Repetiteur is active, ALL user input goes to Repetiteur unless clearly a Conductor command (e.g., "stop", "abort")
- Detection heuristic: if user message contains plan/approach/blocker-related content → relay to Repetiteur. If user message is a conductor-level command ("stop", "abort", "status") → handle locally.

---

## 8. Handoff Message Reception
**Source:** [Repetiteur Design, Section 7 — Communication Channel, Handoff subsection]; [Conductor Overhaul Design, Section 5 — Handoff Reception]
**Authority:** mandatory
**Proposed section ID:** handoff-reception
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. Both designs describe the handoff from different perspectives. Must synthesize into the Conductor's reception procedure.

Content to include:
- The Repetiteur sends a SendMessage containing:
  - Path to the new remaining plan (Implementation Plan rX)
  - Revision number
  - Summary of what changed: approach revisions, rollbacks ordered, new phases added, phases preserved
  - Whether rollback tasks exist and what they revert
  - Which phase to begin execution from (first phase in the remaining plan)
  - Path to the consultation journal for reference
- The Conductor receives this message AFTER the Repetiteur has:
  - Committed the remaining plan to git
  - Moved the superseded plan to `docs/plans/designs/superseded/`
  - Committed the consultation journal
- Directory state is already clean when Conductor receives the message
- If handoff message not received (Repetiteur crash): Conductor's timeout detects stall, reports to user. Previous plan remains active. State is recoverable.

---

## 9. Task Annotation Matching (REVISED/NEW/REMOVED)
**Source:** [Conductor Overhaul Design, Section 5 — Handoff Reception]
**Authority:** mandatory
**Proposed section ID:** task-annotation-matching
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. The overhaul design describes the annotation convention and the Conductor's response per annotation type.

Content to include:
- The Repetiteur annotates tasks inline in the remaining plan: no annotation = unchanged, `(REVISED)` / `(NEW)` / `(REMOVED)` next to task numbers
- This is NOT a full phase restart. Completed work stays.
- Conductor reads the remaining plan and maps annotations to actions:
  - **No annotation (unmarked tasks):** Resume paused Musicians — these tasks are confirmed unaffected by the Repetiteur's impact assessment
  - **REVISED tasks:** Close old kitty window, delete old instruction files, launch Copyist for new instructions, launch fresh Musician
  - **REMOVED tasks:** Close kitty window, clean up task row (set state to `exited`), remove instruction files
  - **NEW tasks:** Launch Copyist for new instructions, insert new task row, launch fresh Musician

---

## 10. Plan Changeover Procedure
**Source:** [Conductor Overhaul Design, Section 5 — Handoff Reception]; [Repetiteur Design, Section 7 — Conductor Resume Behavior + Plan Transition Protocol]
**Authority:** mandatory
**Proposed section ID:** plan-changeover
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. Must synthesize the full changeover flow from both documents.

Content to include:
- **Step 1:** Receive handoff message via SendMessage
- **Step 2:** Read remaining plan's verification index — confirm it exists (lock indicator, same check as with Arranger output). If missing/malformed → treat as unverified, report to user.
- **Step 3:** Read Overview, Consultation Context, and Phase Summary sections
- **Step 4:** Read conductor checkpoint sections for each remaining phase
- **Step 5:** Update MEMORY.md with new plan path (replace old plan reference)
- **Step 6:** Map task annotations per section 9 (task-annotation-matching):
  - Unmarked → resume paused Musicians
  - REVISED → close old window, delete old instructions, Copyist + fresh Musician
  - REMOVED → close window, cleanup
  - NEW → Copyist + insert row + fresh Musician
- **Step 7:** Resume normal execution: task decomposition via Copyist, Musician launches, checkpoint verification
- **Step 8:** Do NOT re-verify completed work marked as unaffected — the Repetiteur's impact assessment already verified isolation
- **Step 9:** The Conductor does NOT read the superseded plan. The Consultation Context section within the remaining plan provides all historical context needed.

---

## 11. Superseded Plan Handling
**Source:** [Repetiteur Design, Section 5 — File Location + Naming Convention]; [Repetiteur Design, Section 7 — Plan Transition Protocol + Multiple Consultation Transitions]
**Authority:** core
**Proposed section ID:** superseded-plan-handling
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. Conductor needs to know the directory structure but doesn't manage it (Repetiteur handles file moves).

Content to include:
- Superseded plans live in `docs/plans/designs/superseded/`
- The Repetiteur handles moving the old plan to `superseded/` BEFORE sending the handoff message
- The Conductor never looks in `superseded/` — only the Repetiteur reads these (for context in future consultations)
- Directory evolution example (from repetiteur design Section 7):
  ```
  After original: docs/plans/designs/{feature}-plan.md
  After r1: docs/plans/designs/{feature}-plan-r1.md + superseded/{feature}-plan.md
  After r2: docs/plans/designs/{feature}-plan-r2.md + superseded/{feature}-plan.md + {feature}-plan-r1.md
  ```

---

## 12. Pre-Spawn Checklist (Composite)
**Source:** [Conductor Overhaul Design, Section 5 — Launch Protocol, all 4 items]; [Conductor Overhaul Design, Section 3 — Escalation Chain]
**Authority:** mandatory
**Proposed section ID:** pre-spawn-checklist
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. This is a synthesized checklist combining all pre-spawn requirements from the design.

Content to include:
1. **Pause all Musicians** — Emergency broadcast to all active tasks (see section 5 above)
2. **Write blocker report to decisions/ directory** — Crash recovery insurance (see section 3 above)
3. **Check consultation count** — Read plan revision metadata. If would produce r4, refuse and escalate to user (see section 4 above)
4. **Spawn Repetiteur** — Teammate with opus, 1m context. Lean prompt with task IDs, states, instruction file PATHS (not content), artifact references, git state summary. The Repetiteur reads files itself.

---

## 13. Escalation Chain Context
**Source:** [Conductor Overhaul Design, Section 3 — Autonomous Operation, Escalation Chain + Authority Scope]
**Authority:** core
**Proposed section ID:** escalation-context
**Duplication note:** May overlap with error-recovery.md (the 5-correction threshold that triggers Repetiteur invocation). This is expected — error-recovery describes WHEN to escalate, this protocol describes HOW.
**Modification needed:** New content from design.

Content to include:
- Escalation chain: Conductor attempts fix (up to 5 corrections per blocker) → spawn Repetiteur → user only if Repetiteur escalates
- Conductor authority scope:
  - **Can modify:** Intra-phase directions without breaking existing choices/architecture
  - **Cannot modify:** Cross-phase dependencies, architectural decisions, protocol choices, items tagged `<mandatory>` in Arranger phase sections
  - **Escalates to Repetiteur:** When out-of-scope changes are required, or after 5 correction attempts fail
- User is involved ONLY if Repetiteur escalates (vision deviation, 3rd consultation, significant scope change)

---

## 14. Error Scenarios During Consultation
**Source:** [Repetiteur Design, Section 7 — Error Scenarios]
**Authority:** core
**Proposed section ID:** error-scenarios
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design.

Content to include:
- **Repetiteur fails to produce a remaining plan (vision deviation):** Receives escalation notice instead of handoff. Relay to user. No partial or speculative plan.
- **Repetiteur's verification loop fails repeatedly:** Receives message that consultation unable to produce verified plan. Relay to user. Signal that blocker may be more fundamental.
- **Conductor cannot parse handoff:** Remaining plan's verification index is missing or malformed → treat as unverified, report to user. Do NOT attempt to execute unverified plan.
- **Partial failure recovery (Repetiteur crash before handoff):** Conductor never receives handoff, remains in waiting state. Previous plan may still be active (not yet moved to superseded/). Timeout detects stall. Report to user. State is recoverable — user can inspect directory and complete transition manually or restart consultation.
- **In all error scenarios where handoff was never sent:** Previous plan remains active from Conductor's perspective.

---

## 15. Delegation Model for Blocker Report Preparation
**Source:** [Conductor Overhaul Design, Section 3 — Delegation Model]; [Repetiteur Design, Section 2 — Current Phase Task State]
**Authority:** guidance
**Proposed section ID:** blocker-report-preparation
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. The repetiteur design specifies that a subagent reads current phase task instruction files and returns summaries. The conductor overhaul specifies teammates for >40k token work.

Content to include:
- Before spawning the Repetiteur, Conductor may need to prepare the blocker report's "Current Phase Task State" section
- A subagent reads the current phase's task instruction files and returns a summary of what each completed and paused task implemented
- This distilled task-level context covers the in-progress phase only — prior completed phases do NOT get task-level breakdown
- If preparation is complex (>40k estimated tokens): use a teammate. Otherwise: regular Task subagent.

---

## RESOLVED — Not This Protocol

### U1. Musician PID Tracking During Pause
**Resolved:** NOT THIS PROTOCOL — belongs in `musician-lifecycle.md`. PID management is lifecycle's job. The repetiteur-invocation protocol triggers the pause via emergency broadcast; musician-lifecycle handles the PID-level mechanics.

### U2. Sentinel Teammate Shutdown During Consultation
**Resolved:** NOT THIS PROTOCOL — belongs in `sentinel-monitoring.md`. Sentinel shuts down when Conductor pauses all Musicians, same trigger as phase completion. The sentinel-monitoring protocol owns its own lifecycle rules.

---

## DELETED Entries

### D1. STATUS.md References
**Source:** [Conductor Overhaul Design, Section 8 — Eliminated Features]
**Status:** DELETED — STATUS.md eliminated per design
**Note:** The monolithic SKILL.md has STATUS.md update steps in many sections. None of these carry into the repetiteur-invocation protocol. The design says: "STATUS.md is eliminated. Its roles are absorbed by other mechanisms." Recovery/handoff tracking is unnecessary with 1m context. Current plan reference goes to MEMORY.md single line.

### D2. Recovery Instructions Template
**Source:** [Conductor Overhaul Design, Section 8 — Eliminated Features]
**Status:** DELETED — Recovery docs unnecessary with 1m context
**Note:** `references/recovery-instructions-template.md` is no longer needed. No recovery-related content should appear in this protocol.

### D3. status-md-reading-strategy.md
**Source:** [Conductor Overhaul Design, Section 8 — Eliminated Features; Section 12 — Reference File Restructuring table]
**Status:** DELETED — STATUS.md eliminated
**Note:** `references/status-md-reading-strategy.md` is no longer needed.

---

## Content from Existing Reference Files

### From session-handoff.md (lines 1-308)
- **Handoff types table (lines 26-38):** NOT relevant — this covers Musician session handoff, not Repetiteur handoff. Lives in musician-lifecycle.md.
- **Replacement session launch (lines 239-288):** NOT relevant — this covers launching replacement Musicians after context exhaustion. Lives in musician-lifecycle.md.
- No content from session-handoff.md belongs in the repetiteur-invocation protocol.

### From database-queries.md (lines 1-527)
- **Pattern 9: Request Exit (lines 310-319):** POTENTIALLY relevant — Conductor may set `exit_requested` if something goes wrong during Repetiteur consultation. But this is a general state transition, not specific to this protocol.
- **Pattern 16: Emergency Broadcast (lines 410-427):** Relevant to section 5 (Pause All Musicians) — the emergency broadcast SQL pattern. **Include duplicate SQL in this protocol per co-location design.**
- **Pattern 17: Refresh Conductor Heartbeat (lines 429-439):** POTENTIALLY relevant — Conductor should continue heartbeat during consultation. But this is general monitoring, not protocol-specific.

### From state-machine.md (lines 1-260)
- **Conductor states (lines 38-50):** Relevant context — the Conductor stays in `watching` or possibly a new consultation-related state during Repetiteur consultation. No new state defined in design documents, so Conductor remains in `watching`.
- No direct content to migrate, but state context should inform the protocol.

### From monolithic SKILL.md (lines 1-603)
- The monolithic SKILL.md has NO Repetiteur-related content. It was written before the Repetiteur was designed.
- Error handling section (lines 413-442) mentions escalation to user at retry_count >= 5 but does NOT mention Repetiteur as an intermediate step. This is the gap the new protocol fills.

---

## Section Structure Summary

The proposed protocol file should have these sections:

1. `pre-spawn-checklist` (mandatory) — Composite checklist: pause, persist, check count, spawn
2. `consultation-count-check` (mandatory) — r4 refusal logic
3. `pause-musicians` (mandatory) — Emergency broadcast to all active tasks
4. `blocker-report-format` (mandatory) — Full field specification
5. `blocker-report-persistence` (mandatory) — Write to decisions/ directory
6. `blocker-report-preparation` (guidance) — Subagent for task-level summaries
7. `spawn-prompt-template` (mandatory) — Teammate spawn with structured report
8. `consultation-communication` (core) — Three communication phases
9. `passthrough-communication` (mandatory) — User input relay
10. `escalation-context` (core) — Authority scope and escalation chain
11. `handoff-reception` (mandatory) — What the Conductor receives
12. `task-annotation-matching` (mandatory) — REVISED/NEW/REMOVED handling
13. `plan-changeover` (mandatory) — Full changeover procedure
14. `superseded-plan-handling` (core) — Directory structure awareness
15. `error-scenarios` (core) — All failure modes during consultation
