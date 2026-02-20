# Initialization Protocol — Extraction Proposal

**Protocol:** Initialization
**Target file:** `references/protocols/initialization.md`
**Date:** 2026-02-19

---

## 1. Bootstrap Steps from SKILL.md Initialization Section

**Source:** `docs/archive/SKILL-v2-monolithic.md`, lines 107-129 (section id="initialization")
**Authority:** core (with inline mandatory tags)
**Proposed section ID:** `bootstrap-steps`
**Duplication note:** None — unique to initialization
**Modification needed:**
- Step 6 (Initialize STATUS.md) — DELETED — STATUS.md eliminated per design (Section 8)
- Step 9 (Lock implementation plan) — UPDATE: plan lock mechanism changes to Arranger plan-index sentinel check per design Section 4
- Steps must integrate Arranger plan consumption model: read plan-index + Overview + Phase Summary at bootstrap (design Section 4)
- UPDATE: "Read implementation plan" (step 1) changes to selective Arranger plan reading: plan-index (line ranges) + Overview + Phase Summary only
- Step 5 (Load memory graph) — no change, stays as-is
- Step 4 (Load docs/ READMEs) — no change, stays as-is
- Step 2 (Git branch) — no change
- Step 3 (Verify temp/) — no change
- Step 7 (Initialize database) — stays, but DDL content comes from database-queries.md (see proposal #2 below)
- Step 8 (Verify hooks) — no change

**Content (from lines 109-129):**
```
Execute these steps in order. Steps 1-5 are reads (parallelizable). Steps 6-8 are writes (sequential). Step 9 is a gate (launch initiation).

1. Read implementation plan
2. Git branch — Verify not on main. Create feature branch if needed.
3. Verify temp/ directory
4. Load docs/ READMEs
5. Load memory graph
6. Initialize STATUS.md [DELETED per design]
7. Initialize database — Drop and recreate tables via comms-link execute. Insert conductor row.
8. Verify hooks — hooks.json, session-start-hook.sh, stop-hook.sh exist. comms.db accessible.
9. Lock implementation plan
```

Also includes the inline `<mandatory>` about temp/ files (line 118) and `<context>` about temp/ symlink (line 120).

---

## 2. Schema DDL and Initialization SQL

**Source:** `references/database-queries.md`, lines 29-84 (section id="schema-ddl")
**Authority:** core + mandatory + template (follow="exact")
**Proposed section ID:** `database-initialization`
**Duplication note:** DDL SQL will also appear partially in `error-recovery.md` (for table rebuild after corruption) — but full DDL is primarily initialization
**Modification needed:** None for core DDL content. The `<mandatory>` about using comms-link execute (line 34) must be preserved.

**Content includes:**
- DROP TABLE IF EXISTS statements
- CREATE TABLE orchestration_tasks (11-state CHECK constraint)
- CREATE TABLE orchestration_messages (12 message_type CHECK constraint)
- INSERT conductor row (task-00)
- CREATE INDEX statements (3 indexes)

---

## 3. Schema Verification SQL

**Source:** `references/database-queries.md`, lines 87-98 (section id="schema-verification")
**Authority:** core
**Proposed section ID:** `schema-verification`
**Duplication note:** None — unique to initialization
**Modification needed:** None

**Content:**
```sql
PRAGMA table_info(orchestration_tasks);
PRAGMA table_info(orchestration_messages);
```
Plus the rule: "If columns are missing or tables don't exist: drop and recreate."

---

## 4. Database Location

**Source:** `references/database-queries.md`, lines 19-27 (section id="database-location")
**Authority:** core
**Proposed section ID:** `database-location`
**Duplication note:** This is foundational context — may also appear in SKILL.md purpose section
**Modification needed:** None

**Content:**
```
/home/kyle/claude/remindly/comms.db — shared by comms-link MCP server and stop hook (via sqlite3).
```

---

## 5. Column Reference

**Source:** `references/database-queries.md`, lines 100-131 (section id="column-reference")
**Authority:** core
**Proposed section ID:** `column-reference`
**Duplication note:** Useful reference in initialization; could also be co-located in other protocols but primary home is initialization (where tables are created)
**Modification needed:** None

**Content:** Full column reference tables for both `orchestration_tasks` and `orchestration_messages`.

---

## 6. Old Table Names (NEVER USE)

**Source:** `references/database-queries.md`, lines 512-524 (section id="old-table-names")
**Authority:** mandatory
**Proposed section ID:** `old-table-names`
**Duplication note:** Could be in SKILL.md mandatory-rules collected block instead — UNCERTAIN
**Modification needed:** None

**Content:** Mapping of old names to new names (coordination_status → orchestration_tasks, etc.)

---

## 7. State Machine Summary/Overview

**Source:** `references/state-machine.md`, lines 25-35 (section id="database-table")
**Authority:** core
**Proposed section ID:** `state-machine-overview`
**Duplication note:** Individual state transitions go to each protocol file per design. Summary/overview belongs in initialization per file mapping table.
**Modification needed:** None

**Content:**
```
All state is stored in orchestration_tasks in /home/kyle/claude/remindly/comms.db.
Single state column with CHECK constraint enforcing exactly 11 valid values.
```

---

## 8. Conductor States Table

**Source:** `references/state-machine.md`, lines 37-50 (section id="conductor-states")
**Authority:** core
**Proposed section ID:** `conductor-states`
**Duplication note:** Overview of conductor-specific states belongs in initialization; individual transitions co-located in relevant protocols
**Modification needed:** None

**Content:** Table with 4 conductor states (watching, reviewing, exit_requested, complete) plus hook exit criteria.

---

## 9. Execution States Table

**Source:** `references/state-machine.md`, lines 52-70 (section id="execution-states")
**Authority:** core
**Proposed section ID:** `execution-states`
**Duplication note:** Overview belongs in initialization; individual transitions co-located in relevant protocols
**Modification needed:** None

**Content:** Table with 9 execution states plus hook exit criteria.

---

## 10. State Ownership Summary

**Source:** `references/state-machine.md`, lines 72-80 (section id="state-ownership")
**Authority:** core
**Proposed section ID:** `state-ownership`
**Duplication note:** Belongs in initialization as summary; relevant protocols will repeat their subset
**Modification needed:** None

**Content:**
```
Conductor sets: watching, reviewing, exit_requested, complete, review_approved, review_failed, fix_proposed, exited
Execution sets: working, needs_review, error, complete, exited
```

---

## 11. State Transition Flows (Overview)

**Source:** `references/state-machine.md`, lines 82-107 (section id="state-transition-flows")
**Authority:** core
**Proposed section ID:** `state-transition-flows`
**Duplication note:** ASCII flow diagrams belong in initialization as overview; individual flows co-located in each protocol
**Modification needed:** None

**Content:** ASCII state transition flow diagrams (happy path, review rejection, error path, retry exhaustion, conductor paths).

---

## 12. Heartbeat Rule

**Source:** `references/state-machine.md`, lines 122-136 (section id="heartbeat-rule")
**Authority:** mandatory
**Proposed section ID:** `heartbeat-rule`
**Duplication note:** This is a universal rule — should appear in initialization AND be reinforced inline in every protocol that does state transitions
**Modification needed:** None

**Content:** "Update last_heartbeat on EVERY state transition" with example SQL.

---

## 13. Dynamic Row Management

**Source:** `references/database-queries.md`, lines 493-510 (section id="dynamic-row-management")
**Authority:** core
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**Resolution: NOT THIS PROTOCOL — phase-execution.** Dynamic row management describes adding rows as phases launch, which is a phase-execution concern, not initialization.

---

## 14. Plan-Index Verification (NEW — from design document)

**Source:** Design document, Section 4 (Arranger Plan Consumption), lines 156-158
**Authority:** mandatory (new)
**Proposed section ID:** `plan-index-verification`
**Duplication note:** None — unique to initialization
**Modification needed:** This is NEW content not in any existing reference file

**Content (from design):**
```
The plan-index (<!-- plan-index:start -->) at the top of the file is the lock indicator. Its presence confirms the Arranger's finalization checklist passed. The Conductor's first step is to check for this — if absent, the plan is unverified and the Conductor stops.
```

---

## 15. Arranger Plan Bootstrap Reading (NEW — from design document)

**Source:** Design document, Section 4 (Arranger Plan Consumption), lines 146-154
**Authority:** core (new)
**Proposed section ID:** `plan-bootstrap-reading`
**Duplication note:** Phase-execution.md will reference per-phase reading; initialization owns the bootstrap read
**Modification needed:** This is NEW content not in any existing reference file

**Content (from design):**
```
1. Bootstrap: Read plan-index (line ranges) + Overview + Phase Summary. This is the map — small context cost.
2. Per-phase start: Read phase:N section + conductor-review-N section via plan-index line ranges. (belongs in phase-execution)

Context scales with phase count, not plan size. The Conductor never loads the full document or future phases upfront.
```

---

## 16. User Approval Gate (NEW — from design document)

**Source:** Design document, Section 3 (Autonomous Operation), lines 112-117
**Authority:** mandatory (new)
**Proposed section ID:** `user-approval-gate`
**Duplication note:** None — unique to initialization
**Modification needed:** This is NEW content not in any existing reference file

**Content (from design):**
```
Bootstrap (interactive):
- Execute initialization steps
- Present plan overview (from Arranger's Overview + Phase Summary)
- User approves execution approach
- This is the last interactive gate
```

---

## 17. Conductor Heartbeat Refresh (Pattern 17)

**Source:** `references/database-queries.md`, lines 428-440 (Pattern 17)
**Authority:** template (follow="exact") + context
**Proposed section ID:** `conductor-heartbeat`
**Duplication note:** Also belongs in phase-execution.md (monitoring cycle) — intentional SQL co-location
**Modification needed:** None

**Content:**
```sql
UPDATE orchestration_tasks SET last_heartbeat = datetime('now') WHERE task_id = 'task-00';
```
Plus context about monitoring subagent refreshing this during poll cycle.

---

## 18. Insert Conductor Row (Pattern from DDL)

**Source:** `references/database-queries.md`, lines 76-77 (within schema-ddl)
**Authority:** template (follow="exact")
**Proposed section ID:** Already covered in `database-initialization` (proposal #2)
**Duplication note:** None
**Modification needed:** None

**Content:**
```sql
INSERT INTO orchestration_tasks (task_id, state, last_heartbeat)
VALUES ('task-00', 'watching', datetime('now'));
```

---

## 19. MEMORY.md Plan Tracking (from design document)

**Source:** Design document, Section 8 (Eliminated Features), line 268
**Authority:** core (new)
**Proposed section ID:** `memory-plan-tracking`
**Duplication note:** None — unique to initialization
**Modification needed:** This is NEW content. STATUS.md is eliminated; plan tracking moves to MEMORY.md single line

**Content (from design):**
```
Current plan reference → single line in MEMORY.md
```

---

## 20. Hook Verification Details

**Source:** `docs/archive/SKILL-v2-monolithic.md`, lines 127-128 (step 8 within initialization)
**Authority:** core
**Proposed section ID:** `hook-verification`
**Duplication note:** None — unique to initialization
**Modification needed:** None

**Content:**
```
Verify hooks — Hooks are self-configuring via hooks.json and SessionStart hook. Verify:
- hooks.json exists in tools/implementation-hook/
- session-start-hook.sh and stop-hook.sh exist in same directory
- comms.db is accessible via comms-link
```

---

## 21. Context Headroom Reference

**Source:** `references/orchestration-principles.md`, lines 16-56 (section id="context-headroom")
**Authority:** core + context
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**Resolution: NOT THIS PROTOCOL — SKILL.md absorption.** Design doc maps orchestration-principles.md to "Absorbed into SKILL.md context sections". Context headroom belongs in the SKILL.md preamble, not a protocol file. The 200k→1m update (design I4) applies when absorbed into SKILL.md.

---

## 22. STATUS.md Template and Reading Strategy

**Source:** `references/review-checklists.md`, lines 147-207 (section id="status-md-template")
**Source:** `references/status-md-reading-strategy.md`, entire file
**Authority:** core + template + guidance
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**Flag: DELETED — STATUS.md eliminated per design (Section 8).** Both the STATUS.md template in review-checklists.md and the entire status-md-reading-strategy.md file are eliminated. Recovery instructions template is also eliminated.

---

## 23. Recovery Instructions Template

**Source:** `references/recovery-instructions-template.md`, entire file
**Authority:** core + template + guidance
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**Flag: DELETED — Recovery docs unnecessary with 1m context per design (Section 8).**

---

## 24. Context Budget Guidelines (200k references)

**Source:** `references/orchestration-principles.md`, lines 42-56 (Context Budget Guidelines table)
**Authority:** core + context
**Proposed section ID:** N/A
**Duplication note:** Part of proposal #21
**Modification needed:** N/A

**Resolution: NOT THIS PROTOCOL — SKILL.md absorption.** Same as proposal #21. Context budget guidelines are part of orchestration-principles.md which is absorbed into SKILL.md preamble per design. The 200k→1m update (design I4) applies when absorbed into SKILL.md.

---

## 25. Authority Scope (NEW — from design document)

**Source:** Design document, Section 3 (Autonomous Operation), lines 129-133
**Authority:** mandatory (new)
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** N/A

**Resolution: NOT THIS PROTOCOL — SKILL.md + phase-execution.** Authority scope belongs in SKILL.md mandatory-rules (top-level constraint) and is referenced from phase-execution (where scope decisions are made during error handling). Not an initialization concern.

---

## Summary

### Definitely belongs in initialization.md:
1. Bootstrap steps (proposal #1) — with STATUS.md step deleted, plan-index check added
2. Schema DDL and initialization SQL (proposal #2)
3. Schema verification (proposal #3)
4. Database location (proposal #4)
5. Column reference (proposal #5)
6. Old table names (proposal #6)
7. State machine overview (proposal #7)
8. Conductor states table (proposal #8)
9. Execution states table (proposal #9)
10. State ownership summary (proposal #10)
11. State transition flows overview (proposal #11)
12. Heartbeat rule (proposal #12)
13. Plan-index verification — NEW (proposal #14)
14. Arranger plan bootstrap reading — NEW (proposal #15)
15. User approval gate — NEW (proposal #16)
16. Conductor heartbeat refresh SQL (proposal #17)
17. MEMORY.md plan tracking — NEW (proposal #19)
18. Hook verification (proposal #20)

### NOT THIS PROTOCOL (resolved):
- Dynamic row management (proposal #13) → phase-execution
- Context headroom (proposal #21) → SKILL.md preamble absorption
- Context budget guidelines (proposal #24) → SKILL.md preamble absorption
- Authority scope (proposal #25) → SKILL.md mandatory-rules + phase-execution

### DELETED:
- STATUS.md template and reading strategy (proposal #22) — STATUS.md eliminated
- Recovery instructions template (proposal #23) — unnecessary with 1m context

### UPDATE needed (within initialization content):
- Plan lock mechanism → Arranger plan-index sentinel (proposal #1, step 9)
- Initialize STATUS.md step → DELETED (proposal #1, step 6)
- Any 200k references within initialization-scoped content → 1m
