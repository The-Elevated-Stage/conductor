# Musician Lifecycle Protocol — Extraction Proposal

**Protocol file:** `references/protocols/musician-lifecycle.md`
**Date:** 2026-02-20
**Scope:** PID tracking, cleanup rules, session handoff procedures, context exhaustion handling, post-completion error correction, claim collision recovery, worked_by succession, guard clause re-claiming

---

## 1. PID Tracking (Launch & Capture)
**Source:** Design document Section 6 (Musician Lifecycle Management), lines 200-206
**Authority:** core
**Proposed section ID:** pid-tracking
**Duplication note:** Launch command also appears in phase-execution.md (launch template) — lifecycle file owns the PID capture/cleanup aspect
**Modification needed:** NEW content from design. Current references have no PID tracking. Design specifies:
- Launch: `kitty ... & echo $! > temp/musician-task-03.pid`
- Cleanup: Read PID from file, `kill $PID` (SIGTERM), remove PID file
- Detection: Handled by existing comms-link monitoring (state changes)

---

## 2. Cleanup Rules
**Source:** Design document Section 6, lines 207-211
**Authority:** mandatory
**Proposed section ID:** cleanup-rules
**Duplication note:** None — unique to lifecycle protocol
**Modification needed:** NEW content from design. Three rules:
- Parallel tasks: Close all windows when ALL parallel siblings reach `complete`/`exited`
- Sequential tasks: Close immediately on `complete`/`exited`
- Re-launch (handoff): Close old session IMMEDIATELY before launching replacement. Never two windows for same task simultaneously.

---

## 3. Handoff Types Overview
**Source:** references/session-handoff.md, lines 23-38 (section: handoff-types)
**Authority:** core
**Proposed section ID:** handoff-types
**Duplication note:** None
**Modification needed:** None — direct migration of handoff type table

---

## 4. Clean Handoff Procedure
**Source:** references/session-handoff.md, lines 40-69 (section: clean-handoff)
**Authority:** core + template
**Proposed section ID:** clean-handoff
**Duplication note:** SQL also relevant to database-queries protocol (SQL co-location acceptable per design)
**Modification needed:** None — direct migration. Template SQL for detect/update/message flow.

---

## 5. Dirty Handoff Procedure
**Source:** references/session-handoff.md, lines 71-87 (section: dirty-handoff)
**Authority:** core
**Proposed section ID:** dirty-handoff
**Duplication note:** None
**Modification needed:** None — direct migration. Same as clean but with test verification instructions.

---

## 6. Crash Handoff Procedure
**Source:** references/session-handoff.md, lines 89-119 (section: crash-handoff)
**Authority:** core + template
**Proposed section ID:** crash-handoff
**Duplication note:** SQL also relevant to database-queries protocol
**Modification needed:** Integrate PID tracking awareness. Design Section 10, lines 304-306: "Conductor checks if PID is still alive. If PID alive but heartbeat stale -> watcher died, session stuck -> close window, re-launch. If PID dead -> crash -> follow crash handoff procedure." Add PID alive/dead check as first step before existing crash recovery flow.

---

## 7. Retry Exhaustion Procedure
**Source:** references/session-handoff.md, lines 121-153 (section: retry-exhaustion)
**Authority:** core + template
**Proposed section ID:** retry-exhaustion
**Duplication note:** Retry limit rules also in state-machine.md and error-recovery protocol
**Modification needed:** None — direct migration. Includes escalation message template.

---

## 8. Worked_By Succession Pattern
**Source:** references/session-handoff.md, lines 155-176 (section: worked-by-succession)
**Authority:** core
**Proposed section ID:** worked-by-succession
**Duplication note:** Also referenced in state-machine.md lines 217-231 (section: worked-by-succession). Both files describe the same pattern. Lifecycle file should be the canonical owner; state-machine.md can have a brief cross-reference.
**Modification needed:** None — direct migration from session-handoff.md (more detailed version).

Also from SKILL-v2-monolithic.md best-practices section — the worked_by succession is mentioned in the session-handoff section context. No additional content beyond what's in the reference file.

---

## 9. Guard Clause Re-Claiming
**Source:** references/session-handoff.md, lines 178-218 (section: guard-clause-reclaiming)
**Authority:** core + template (exact)
**Proposed section ID:** guard-clause-reclaiming
**Duplication note:** Guard clause SQL also in state-machine.md lines 193-214 (section: atomic-claim-pattern). The lifecycle file owns the re-claiming use case specifically (handoff context), while state-machine.md owns the initial claim pattern. Both include the same SQL template — SQL co-location is acceptable per design.
**Modification needed:** None — direct migration. Includes both the successful re-claim SQL and the fallback row creation SQL.

---

## 10. Fallback Row Pattern (Claim Collision Recovery)
**Source:** references/state-machine.md, lines 234-257 (section: fallback-row-pattern)
**Authority:** core + template (exact)
**Proposed section ID:** claim-collision-recovery
**Duplication note:** Also in database-queries.md lines 468-491 (Pattern 19: Detect and Cleanup Fallback Rows). The monitoring/detection SQL belongs in phase-execution or monitoring; the fallback creation SQL belongs here in lifecycle.
**Modification needed:** Integrate design Section 10, lines 300-302: "In autonomous mode: Conductor detects claim_blocked, closes failed kitty window, resets task row, re-launches. Straightforward automation." Current content describes the pattern but not the autonomous response. Add the autonomous recovery flow.

Also from SKILL-v2-monolithic.md best-practices section lines 509-527: Claim collision description and monitoring subagent response. This content maps here.

---

## 11. High-Context Verification Rule
**Source:** references/session-handoff.md, lines 221-236 (section: high-context-verification)
**Authority:** mandatory
**Proposed section ID:** high-context-verification
**Duplication note:** None — unique to lifecycle (handoff context)
**Modification needed:** None — direct migration. Mandatory verification steps when resuming task with context >80%.

---

## 12. Replacement Session Launch
**Source:** references/session-handoff.md, lines 238-288 (section: replacement-session-launch)
**Authority:** core + template (exact)
**Proposed section ID:** replacement-session-launch
**Duplication note:** Launch template also in musician-launch-prompt-template.md lines 128-155 (section: launching-replacement-sessions). The lifecycle file owns when/why to launch replacements; the launch template file owns the prompt format. However, per the design file mapping table, `musician-launch-prompt-template.md` maps to `phase-execution.md`. The replacement launch template should live here in lifecycle since it's triggered by the handoff workflow. The general launch template stays in phase-execution.
**Modification needed:** Integrate PID tracking. Design Section 6: Conductor must `kill $PID` of old session and remove PID file BEFORE launching replacement (per cleanup rules: "Close old session IMMEDIATELY before launching replacement").

---

## 13. Context Situation Checklist
**Source:** references/session-handoff.md, lines 290-306 (section: context-situation-checklist)
**Authority:** core
**Proposed section ID:** context-situation-checklist
**Duplication note:** Also referenced in review-checklists.md lines 82-93 (section: execution-task-completion-review, context situation checklist). The review protocol's version is about evaluating musician proposals at review time; this version is about evaluating context-exhausted musician state for handoff decisions. Similar content, different trigger point. Both should keep their copies.
**Modification needed:** None — direct migration.

---

## 14. Session Handoff SQL (Database Pattern 18)
**Source:** references/database-queries.md, lines 442-467 (Pattern 18: Session Handoff - Context Exit)
**Authority:** core + template (format)
**Proposed section ID:** Embed within clean-handoff section
**Duplication note:** SQL co-location — this pattern lives in database-queries.md currently and should be co-located in the lifecycle protocol per design principle
**Modification needed:** None — direct migration. The SQL template and reference to session-handoff.md for full procedure.

---

## 15. Atomic Task Claim (Database Pattern 2)
**Source:** references/database-queries.md, lines 147-165 (Pattern 2: Atomic Task Claim)
**Authority:** mandatory + template (exact)
**Proposed section ID:** atomic-claim (or embed in guard-clause-reclaiming)
**Duplication note:** Also in state-machine.md lines 193-214. Primary home is state-machine.md / initialization protocol for initial claims. The lifecycle protocol needs it for RE-claims after handoff. SQL co-location means both keep it.
**Modification needed:** None for the SQL itself. The mandatory "Verify rows_affected = 1" rule migrates with it.

---

## 16. Post-Completion Error Correction (Resume)
**Source:** Design document Section 6, lines 214-228
**Authority:** core
**Proposed section ID:** post-completion-resume
**Duplication note:** None — entirely new concept
**Modification needed:** NEW content from design. Full new section:
- Session ID already stored in `orchestration_tasks.session_id` from claim step
- Session data persists after kitty window is killed
- Conductor creates a new task row (e.g., `task-01-fix`) with its own lifecycle — `complete` stays terminal
- Conductor launches: `kitty ... -- claude --resume "$SESSION_ID" "Fix: [details]"`
- Resumed Musician claims the fix task row via comms-link, maintaining orchestration coverage

---

## 17. Context Exhaustion Handling
**Source:** Design document Section 6, lines 226-228
**Authority:** core
**Proposed section ID:** context-exhaustion-flow
**Duplication note:** Overlaps with clean/dirty handoff procedures but described separately in design as a simplified automation flow
**Modification needed:** NEW content from design. "Simple automation: Conductor detects exit (state = `exited`), reads HANDOFF document, closes kitty window, launches fresh Musician session with HANDOFF context in the prompt. No `--resume` for exhaustion — session is already at limit."

---

## 18. Session Handoff Flow (from parallel-coordination.md)
**Source:** references/parallel-coordination.md, lines 190-207 (section: session-handoff-flow)
**Authority:** core
**Proposed section ID:** Merge into handoff-types overview or create summary-handoff-flow
**Duplication note:** This is a summary of the session-handoff.md procedures, embedded in parallel-coordination. It belongs in lifecycle as a quick-reference flow.
**Modification needed:** None — direct migration. Provides the condensed 6-step flow (detect -> read HANDOFF -> assess type -> set fix_proposed -> send msg -> launch replacement). Update "User launches replacement musician" to "Conductor launches replacement musician" per autonomous operation design.

---

## 19. Heartbeat Staleness as Exit Trigger
**Source:** references/state-machine.md, lines 108-119 (section: exited-state-details)
**Authority:** core
**Proposed section ID:** Embed within crash-handoff or create separate staleness-response section
**Duplication note:** Staleness detection SQL is in state-machine.md lines 139-158 and database-queries.md Pattern 13 (lines 362-374). The detection mechanism belongs in monitoring/sentinel protocol; the RESPONSE to staleness (what the conductor does when a session is stale) belongs here in lifecycle.
**Modification needed:** Integrate design Section 10 lines 304-306: PID alive check before declaring crash. If PID alive but heartbeat stale -> watcher died, session stuck -> close window, re-launch. If PID dead -> crash -> follow crash handoff.

---

## 20. Exited State Details
**Source:** references/state-machine.md, lines 108-119 (section: exited-state-details)
**Authority:** core
**Proposed section ID:** exited-state-triggers
**Duplication note:** Also belongs in state-machine protocol. Lifecycle file should own the "what to do" response; state-machine owns the "what it means" definition.
**Modification needed:** None — migrate the "When execution session sets it" and "When conductor sets it" triggers list. Response procedures are handled by other sections above (crash handoff, retry exhaustion, etc.).

---

## 21. Parallel Phase Completion Event Handling (exited detection)
**Source:** references/parallel-coordination.md, lines 158-168 (section: conductor-workflow, step 8 Handle Events)
**Authority:** core
**Proposed section ID:** EXCLUDED — event routing belongs in phase-execution protocol (monitoring cycle routes events to appropriate protocols). The `exited` case routes TO this lifecycle protocol, but the routing dispatch itself lives in phase-execution.
**Duplication note:** The routing logic ("exited -> follow session handoff procedure") belongs in phase-execution; the actual handoff procedures belong in lifecycle
**Modification needed:** N/A — not included in this protocol file. Phase-execution will contain the routing dispatch that points to musician-lifecycle for `exited` events.

---

## 22. Complete/Exited State Transitions
**Source:** references/state-machine.md, lines 55-69 (execution states table — complete and exited rows)
**Authority:** core
**Proposed section ID:** terminal-states
**Duplication note:** Also in state-machine protocol (primary home). Lifecycle needs the terminal state definitions for handoff decision logic.
**Modification needed:** None — reference or co-locate the terminal state definitions.

---

## 23. SKILL-v2 Session Handoff Section
**Source:** SKILL-v2-monolithic.md, lines 367-381 (section: session-handoff)
**Authority:** core
**Proposed section ID:** N/A — merge into handoff-types overview
**Duplication note:** This is a summary/dispatcher that points to session-handoff.md reference. The content is already covered by proposals #3-#7 above. Contains one additional item: "Claim Collision Recovery" with specific autonomous response (reset task row, re-insert instruction message, re-launch kitty window, report to user if second fail). This maps to proposal #10.
**Modification needed:** None beyond what's covered in other proposals. The claim collision recovery details should be integrated into proposal #10.

---

## 24. SKILL-v2 Best Practices — External Sessions vs Subagents
**Source:** SKILL-v2-monolithic.md, lines 540-548 (section: best-practices, mandatory block)
**Authority:** mandatory
**Proposed section ID:** EXCLUDED — this is a cross-cutting principle absorbed into SKILL.md mandatory-rules section, not a lifecycle protocol concern.
**Duplication note:** Also in orchestration-principles.md lines 63-112. Will be absorbed into SKILL.md per design Section 12 mapping table (orchestration-principles.md → "Absorbed into SKILL.md `<context>` sections").
**Modification needed:** N/A — not included in this protocol file. SKILL.md owns this principle.

---

## 25. STATUS.md References
**Source:** Multiple files reference STATUS.md for tracking handoff state
**Authority:** N/A
**Proposed section ID:** N/A
**Duplication note:** N/A
**Modification needed:** DELETED — STATUS.md eliminated per design Section 8. All references to:
- "Update STATUS.md with recovery instructions" → remove
- "Read STATUS.md for handoff context" → replace with "Read state from comms-link database"
- "Write Recovery Instructions to STATUS.md" → remove (1m context eliminates need)
- session-handoff.md line 204: "...notifies user" → update to autonomous launch
- parallel-coordination.md lines 232-237 (phase-completion): STATUS.md updates → remove

Affected source files:
- references/session-handoff.md (replacement-session-launch): notification format references STATUS
- references/review-checklists.md (status-md-template): entire section is STATUS.md template — DELETED
- references/status-md-reading-strategy.md: entire file — DELETED per design
- references/recovery-instructions-template.md: entire file — DELETED per design
- references/orchestration-principles.md lines 167-168: "Write Recovery Instructions to STATUS.md" → remove
- SKILL-v2-monolithic.md various: STATUS.md references throughout → remove

---

## 26. Musician Fails to Update Heartbeat (Edge Case)
**Source:** Design document Section 10, lines 304-306
**Authority:** core
**Proposed section ID:** heartbeat-staleness-response (merge with proposal #19)
**Duplication note:** Staleness detection SQL in state-machine and database-queries protocols
**Modification needed:** NEW edge case logic from design: Conductor checks if PID is still alive.
- If PID alive but heartbeat stale → watcher died, session stuck → close window, re-launch
- If PID dead → crash → follow crash handoff procedure
This is a refinement of the existing staleness response that leverages PID tracking.

---

## 27. Musician Fails to Claim (Edge Case)
**Source:** Design document Section 10, lines 300-302
**Authority:** core
**Proposed section ID:** Merge into claim-collision-recovery (proposal #10)
**Duplication note:** Overlaps with fallback row pattern
**Modification needed:** NEW autonomous response from design: "Conductor detects claim_blocked, closes failed kitty window, resets task row, re-launches. Straightforward automation."

---

## 28. Context Budget (200k → 1m Update)
**Source:** Design document Section 11 (I4), line 324
**Authority:** N/A (naming cleanup)
**Proposed section ID:** N/A — applies across all sections
**Duplication note:** N/A
**Modification needed:** All references to "200k context" in lifecycle-related content must be updated to "1m context". Specifically:
- orchestration-principles.md line 22: "200k-token context window" → "1m-token context window"
- orchestration-principles.md line 104: "200k" in table → "1m"
- SKILL-v2-monolithic.md line 537: "200k-token budget" → "1m-token budget"
- SKILL-v2-monolithic.md line 544: "200k context" → "1m context"

---

## Summary

| Category | Count |
|----------|-------|
| Direct migrations (no changes) | 13 |
| Migrations with modifications | 6 |
| NEW content from design | 4 |
| DELETED content (STATUS.md elimination) | 1 (affects many references) |
| EXCLUDED (belongs in other protocols) | 2 |
| Cross-cutting (naming/context updates) | 2 |

### Key New Content from Design
1. **PID tracking** — entirely new (proposal #1)
2. **Cleanup rules** — entirely new (proposal #2)
3. **Post-completion resume** via `--resume` — entirely new (proposal #16)
4. **Context exhaustion simplified flow** — new simplified description (proposal #17)

### Key Modifications to Existing Content
1. **Crash handoff** — add PID alive/dead check (proposal #6)
2. **Replacement session launch** — add PID cleanup before launch (proposal #12)
3. **Claim collision recovery** — add autonomous response (proposal #10, #27)
4. **Heartbeat staleness** — add PID-aware response (proposal #19, #26)
5. **All STATUS.md references** — remove or replace (proposal #25)
6. **200k → 1m context** — update all references (proposal #28)

### Section Order for Protocol File
Proposed section ordering in `musician-lifecycle.md`:
1. `pid-tracking` — launch and capture
2. `cleanup-rules` — when to close windows
3. `handoff-types` — overview table
4. `clean-handoff` — procedure + SQL
5. `dirty-handoff` — procedure (extends clean)
6. `crash-handoff` — procedure + SQL (with PID check)
7. `retry-exhaustion` — procedure + SQL
8. `context-exhaustion-flow` — simplified automation
9. `post-completion-resume` — new `--resume` workflow
10. `worked-by-succession` — naming pattern
11. `guard-clause-reclaiming` — re-claim SQL
12. `claim-collision-recovery` — fallback rows + autonomous response
13. `replacement-session-launch` — template + PID cleanup
14. `high-context-verification` — mandatory verification rule
15. `context-situation-checklist` — evaluation criteria
16. `terminal-states` — complete/exited definitions
