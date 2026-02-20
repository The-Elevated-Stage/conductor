# Error Recovery Protocol — Extraction Proposal

**Target file:** `references/protocols/error-recovery.md`
**Date:** 2026-02-19
**Protocol scope:** Everything from "Musician reports error" to "fix proposed and Musician resumes" or "escalated to Repetiteur."

---

## 1. Error handling section from monolithic SKILL.md
**Source:** docs/archive/SKILL-v2-monolithic.md, lines 412-441 (section id="error-handling")
**Authority:** core (outer), mandatory (context warning sub-protocol)
**Proposed section ID:** `error-classification-and-triage`
**Duplication note:** Context warning protocol also touches review-protocol.md (context situation checklist)
**Modification needed:**
- UPDATE: "retry_count >= 5" escalation currently routes to user. Per design doc Section 3, escalation chain is now Conductor (5 corrections) -> Repetiteur -> User. Change to: "retry_count >= 5 -> escalate to Repetiteur Protocol" instead of directly to user.
- UPDATE: "Uncertain" category currently says "Flag uncertainty for user review." Per design doc Section 3 (autonomous operation), Conductor is autonomous post-bootstrap. Change to: spawn teammate for investigation (>40k estimated tokens per design Section 3 delegation model), or escalate to Repetiteur if the investigation fails.
- DELETED: Reference to STATUS.md ("STATUS.md") — STATUS.md eliminated per design Section 8.
- UPDATE: "200k-token context" references — change to 1m per design Section 11 (I4).

---

## 2. Error Report SQL (Pattern 6 — Execution reports error)
**Source:** references/database-queries.md, lines 238-261 (Pattern 6: Report Error)
**Authority:** template follow="format"
**Proposed section ID:** `error-reporting-sql`
**Duplication note:** Also belongs in phase-execution.md (musician-side error reporting). Co-location per design is correct — duplicate here.
**Modification needed:** None — SQL is stable.

---

## 3. Fix Proposal SQL (Pattern 7 — Conductor proposes fix)
**Source:** references/database-queries.md, lines 263-282 (Pattern 7: Propose Fix)
**Authority:** template follow="format"
**Proposed section ID:** `fix-proposal-sql`
**Duplication note:** None — this is primary home for fix proposal SQL.
**Modification needed:** None — SQL is stable.

---

## 4. Context Warning Detection SQL (Pattern 15)
**Source:** references/database-queries.md, lines 394-407 (Pattern 15: Detect Context Warning)
**Authority:** template follow="exact" + context
**Proposed section ID:** `context-warning-detection`
**Duplication note:** None — primary home.
**Modification needed:**
- DELETED: Context block references STATUS.md ("responds with review_approved... or review_failed (stop now, prepare handoff)"). The handoff mechanism changes — no STATUS.md recovery instructions. Per design Section 8, recovery/handoff is unnecessary with 1m context.

---

## 5. Staleness Detection SQL (Pattern 13)
**Source:** references/database-queries.md, lines 362-374 (Pattern 13: Staleness Detection)
**Authority:** template follow="exact"
**Proposed section ID:** `staleness-detection-sql`
**Duplication note:** Also belongs in musician-lifecycle.md or sentinel-monitoring.md. Co-locate here for error-recovery context (stale = potential crash = error recovery trigger).
**Modification needed:** None — SQL is stable.

---

## 6. State machine — error/fix_proposed transitions
**Source:** references/state-machine.md, lines 86-104 (section id="state-transition-flows")
**Authority:** core
**Proposed section ID:** `error-state-transitions`
**Duplication note:** Summary belongs in initialization.md, full transitions co-located in each protocol. Error-relevant flows:
- `working -> error -> [conductor: fix_proposed] -> working -> ...`
- `working -> error -> [conductor: fix_proposed] -> working -> error -> ... (x5) -> exited`
**Modification needed:**
- UPDATE: Terminal path (x5 -> exited) now routes to Repetiteur Protocol before user, per design Section 3 escalation chain.

---

## 7. State machine — retry limits
**Source:** references/state-machine.md, lines 183-191 (section id="retry-limits")
**Authority:** core
**Proposed section ID:** `retry-limits`
**Duplication note:** None — primary home for retry limit rules.
**Modification needed:**
- UPDATE: "At retry 5, execution self-sets exited" — still true, but what happens next changes. Conductor now escalates to Repetiteur, not user directly.
- "Conductor subagent retries: 3 maximum. After 3, escalate to user." — Per design Section 3, subagent failures also route through Repetiteur before user.

---

## 8. State machine — `exited` state details
**Source:** references/state-machine.md, lines 108-120 (section id="exited-state-details")
**Authority:** core
**Proposed section ID:** `exited-state-triggers`
**Duplication note:** Also relevant to musician-lifecycle.md. Co-locate error-triggered exit reasons here.
**Modification needed:** None — content is accurate. The downstream handling of `exited` changes (Repetiteur escalation) but the trigger conditions themselves don't.

---

## 9. Subagent failure handling — full file
**Source:** references/subagent-failure-handling.md, lines 1-259 (entire file)
**Authority:** Mixed — context (scope), core (retry-policy, failure-categories, retry-decision-flowchart, escalation-to-user, integration-with-workflow), guidance (tracking retries)
**Proposed section ID:** `subagent-failure-handling` (sub-sections: `subagent-retry-policy`, `subagent-failure-categories`, `subagent-retry-flowchart`, `subagent-escalation`, `subagent-integration`)
**Duplication note:** Per design Section 12 file mapping table: "subagent-failure-handling.md -> error-recovery.md" — this is the primary and only target.
**Modification needed:**
- UPDATE: Escalation messages (lines 148-210) currently escalate to user. Per design Section 3, escalation chain is Conductor -> Repetiteur -> User. Options should include "Escalate to Repetiteur for re-planning" as a first-class option before user escalation.
- DELETED: References to STATUS.md in tracking retries (lines 247-255). Per design Section 8, STATUS.md eliminated. Task Planning Notes are held in-session with 1m context.
- UPDATE: "conductor's 200k-token context" in examples — change to 1m per design Section 11 (I4).
- Note: The scope disclaimer at line 22-23 ("NOT execution session errors") remains correct — this section covers conductor subagent failures specifically.

---

## 10. Context warning protocol from SKILL.md error-handling
**Source:** docs/archive/SKILL-v2-monolithic.md, lines 428-439 (within section id="error-handling")
**Authority:** core
**Proposed section ID:** `context-warning-protocol`
**Duplication note:** Context situation checklist also referenced in review-checklists.md. The checklist items should be co-located here as the authoritative copy for error-recovery context.
**Modification needed:**
- DELETED: "see references/review-checklists.md" pointer — in the new protocol architecture, the checklist should be inline in this protocol file (co-location principle).
- UPDATE: Response options should note that `review_failed` (stop now, prepare handoff) no longer involves STATUS.md recovery instructions. With 1m context, handoff is simpler.

---

## 11. Context situation checklist (from review-checklists.md)
**Source:** references/review-checklists.md, lines 82-93 (within section id="execution-task-completion-review", subsection "Context Situation Checklist")
**Authority:** core
**Proposed section ID:** `context-situation-checklist`
**Duplication note:** PRIMARY home is review-protocol.md. Co-locate here because error recovery's context warning protocol needs this checklist. SQL co-location principle applies to checklists too.
**Modification needed:** None — checklist items are stable.

---

## 12. Context situation checklist (from session-handoff.md)
**Source:** references/session-handoff.md, lines 291-306 (section id="context-situation-checklist")
**Authority:** core
**Proposed section ID:** `context-situation-checklist` (same section as #11 — merge these two versions)
**Duplication note:** This is a slightly different formulation of the same checklist. The session-handoff version uses checkbox format and includes "Proposed action specificity" item not in review-checklists version. Merge both into a single authoritative checklist.
**Modification needed:** Merge the two checklist versions into one canonical version in this protocol file.

---

## 13. Error prioritization during monitoring
**Source:** references/parallel-coordination.md, lines 210-222 (section id="error-prioritization")
**Authority:** core
**Proposed section ID:** `error-prioritization`
**Duplication note:** Also relevant to phase-execution.md (monitoring event handling). Co-locate here because error prioritization is fundamentally about error recovery ordering.
**Modification needed:** None — priority order (errors first, reviews second, completions last) is stable.

---

## 14. Error-related event handling from parallel-coordination.md
**Source:** references/parallel-coordination.md, lines 158-168 (within section id="conductor-workflow", subsection "8. Handle Events")
**Authority:** core
**Proposed section ID:** `error-event-routing`
**Duplication note:** Also relevant to phase-execution.md. The error-specific routing (`error` state handling, `last_error = 'context_exhaustion_warning'` check) belongs here. The full event routing (reviews, completions, exited) belongs in phase-execution.md.
**Modification needed:**
- DELETED: "Context Warning Protocol (see SKILL.md Context Warning Protocol)" — in the new architecture, the context warning protocol is inline in this file.
- DELETED: "Follow session handoff procedure in references/session-handoff.md" for `exited` state — that routing belongs in musician-lifecycle.md, not here.

---

## 15. Session handoff — retry exhaustion procedure
**Source:** references/session-handoff.md, lines 122-153 (section id="retry-exhaustion")
**Authority:** core + template follow="format"
**Proposed section ID:** `retry-exhaustion-procedure`
**Duplication note:** Also relevant to musician-lifecycle.md (session exit handling). The retry exhaustion SQL and message format belong here as the error-recovery-side view. The lifecycle cleanup (closing windows, launching replacements) belongs in musician-lifecycle.md.
**Modification needed:**
- UPDATE: "CONDUCTOR ERROR" classification and escalation to user — per design Section 3, escalation chain is Conductor -> Repetiteur -> User. Add Repetiteur as first escalation target.
- UPDATE: Options list should include "Escalate to Repetiteur for re-planning" before user options.

---

## 16. Claim collision recovery (from monolithic SKILL.md session-handoff section)
**Source:** docs/archive/SKILL-v2-monolithic.md, lines 378 (within section id="session-handoff")
**Authority:** core
**Proposed section ID:** `claim-collision-recovery`
**Duplication note:** The claim collision is described in session-handoff.md guard-clause-reclaiming (lines 179-218) and in SKILL.md best-practices. The error-recovery aspect (what Conductor does when claim_blocked is detected) belongs here. The mechanism (fallback rows, guard clauses) belongs in musician-lifecycle.md or initialization.md.
**Modification needed:**
- Per design Section 10 (Musician Fails to Claim): "Conductor detects claim_blocked, closes failed kitty window, resets task row, re-launches. Straightforward automation." This is new automation that should be documented here.

---

## 17. Example: Error Recovery Workflow (full file)
**Source:** examples/error-recovery-workflow.md, lines 1-275 (entire file)
**Authority:** Mixed — context (scenario), core (all step sections and alternatives)
**Proposed section ID:** `error-recovery-examples` (embedded examples section at end of protocol file)
**Duplication note:** None — this is the primary and only target per design file mapping.
**Modification needed:**
- UPDATE: Alternative: Complex Error (lines 137-165) — currently escalates to user ("Prompt user"). Per design Section 3, first escalation should be to Repetiteur.
- UPDATE: Alternative: Terminal Error (lines 243-274) — currently escalates to user. Per design Section 3, first escalation is Repetiteur.
- DELETED: Any STATUS.md references in examples — STATUS.md eliminated per design Section 8.
- UPDATE: Context exhaustion alternative (lines 167-241) — the handoff mechanism simplifies with 1m context per design Section 8.

---

## 18. Orchestration principles — error triage delegation
**Source:** references/orchestration-principles.md, lines 27-29 (within section id="context-headroom")
**Authority:** core
**Proposed section ID:** EXCLUDED — not this protocol
**Resolution:** Per team lead review: this content belongs in SKILL.md absorption (per design Section 12), NOT in error-recovery.md. The error triage delegation principle will be part of SKILL.md's `<context>` sections.

---

## 19. Orchestration principles — overload signs (error-related)
**Source:** references/orchestration-principles.md, lines 159-185 (section id="overload-signs")
**Authority:** core
**Proposed section ID:** UNCERTAIN — the "Many simultaneous state changes" guidance (handle errors first, then reviews, then completions) is relevant but overlaps with #13 (error-prioritization). The "Subagent failures accumulating" recovery action is directly relevant.
**Duplication note:** Error prioritization (#13) covers the same priority ordering. The subagent failure fallback ("Fall back to manual monitoring with validate-coordination.sh") is unique content.
**Modification needed:**
- DELETED: "Write Recovery Instructions, exit, resume in new session" — per design Section 8, STATUS.md eliminated. With 1m context, recovery instructions are unnecessary.
- UPDATE: "Write summaries to Task Planning Notes" — Task Planning Notes are in-session only now, not in STATUS.md.

---

## 20. Copyist output error handling (from design document)
**Source:** design doc Section 10 (Edge Cases — "Copyist Output Errors", Obsidian #14f)
**Authority:** NEW content — not in existing reference files
**Proposed section ID:** `copyist-output-errors`
**Duplication note:** None — this is new content from the design document.
**Modification needed:** This is new content to be written:
- "Small errors: Conductor edits inline."
- "Larger issues: re-launch Copyist teammate to correct/rewrite."
- "The Copyist teammate is resumable if the first attempt doesn't fully resolve."
- Per design Section 3 delegation model: "Teammates (>40k estimated tokens)" — Copyist is launched as teammate, not regular subagent.

---

## 21. Teammate investigation for complex errors (from design document)
**Source:** design doc Section 3 (Delegation Model)
**Authority:** NEW content — not in existing reference files
**Proposed section ID:** `complex-error-investigation`
**Duplication note:** None — this is new content from the design document.
**Modification needed:** This is new content to be written:
- "Teammates (>40k estimated tokens): Task decomposition, complex error analysis, review deep-dives..."
- Complex errors that exceed simple fix proposals should be delegated to a teammate for investigation before proposing a fix.
- The teammate has full context and can use Explorer subagent_type for codebase investigation.

---

## 22. 5-correction threshold and Repetiteur escalation routing
**Source:** design doc Section 3 (Escalation Chain + Authority Scope)
**Authority:** NEW content (mandatory — this is a core escalation rule)
**Proposed section ID:** `escalation-to-repetiteur`
**Duplication note:** Also belongs in repetiteur-invocation.md (the receiving side). Error-recovery.md documents the sending side — when and why to escalate.
**Modification needed:** This is new content to be written:
- "Conductor attempts fix (up to 5 corrections per blocker)"
- "If still stuck -> spawn Repetiteur as teammate (opus, 1m context)"
- "User only involved if Repetiteur escalates (vision deviation, 3rd consultation, significant scope change)"
- Authority scope: "Cannot modify: Cross-phase dependencies, architectural decisions, protocol choices, items tagged <mandatory> in Arranger phase sections"
- "Escalates to Repetiteur: When out-of-scope changes are required, or after 5 correction attempts fail"

---

## 23. Unable to determine phase steps (from design document)
**Source:** design doc Section 10 (Edge Cases — Obsidian #14e)
**Authority:** NEW content
**Proposed section ID:** EXCLUDED — not this protocol
**Resolution:** Per team lead review: this content belongs in phase-execution.md (planning failure case), NOT in error-recovery.md.

---

## 24. Musician fails to update heartbeat (from design document)
**Source:** design doc Section 10 (Edge Cases — Obsidian #14c)
**Authority:** NEW content
**Proposed section ID:** `stale-heartbeat-recovery`
**Duplication note:** Also relevant to musician-lifecycle.md and sentinel-monitoring.md. The detection belongs in monitoring; the recovery action belongs here.
**Modification needed:** This is new content to be written:
- "Conductor checks if PID is still alive."
- "If PID alive but heartbeat stale -> watcher died, session stuck -> close window, re-launch."
- "If PID dead -> crash -> follow crash handoff procedure."
- Cross-references musician-lifecycle.md for the actual window close and re-launch procedure.

---

## 25. Musician fails to claim (from design document)
**Source:** design doc Section 10 (Edge Cases — Obsidian #14b)
**Authority:** NEW content
**Proposed section ID:** `claim-failure-recovery`
**Duplication note:** Overlaps with #16 (claim collision recovery). Merge into single section.
**Modification needed:** New automation per design:
- "In autonomous mode: Conductor detects claim_blocked, closes failed kitty window, resets task row, re-launches. Straightforward automation."

---

## Summary

### Content from existing reference files:
- **subagent-failure-handling.md** — entire file migrates here (entries #9)
- **database-queries.md** — Patterns 6, 7, 13, 15 (entries #2, #3, #4, #5)
- **state-machine.md** — error/fix_proposed transitions, retry limits, exited state details (entries #6, #7, #8)
- **parallel-coordination.md** — error prioritization, error event routing (entries #13, #14)
- **session-handoff.md** — retry exhaustion procedure, context situation checklist (entries #15, #12)
- **review-checklists.md** — context situation checklist (entry #11)
- **orchestration-principles.md** — error triage delegation, overload signs (entries #18, #19)
- **SKILL.md monolithic** — error-handling section, context warning protocol, claim collision (entries #1, #10, #16)
- **examples/error-recovery-workflow.md** — full example file (entry #17)

### New content from design document:
- Repetiteur escalation chain (entry #22) — Section 3
- Copyist output error handling (entry #20) — Section 10
- Teammate investigation for complex errors (entry #21) — Section 3
- Stale heartbeat recovery with PID check (entry #24) — Section 10
- Claim failure automation (entry #25) — Section 10

### Deletions/updates applied across all entries:
- **STATUS.md eliminated** — all references flagged for removal (design Section 8)
- **200k -> 1m context** — all context budget references flagged for update (design Section 11, I4)
- **User escalation -> Repetiteur escalation** — all direct-to-user escalation points updated to go through Repetiteur first (design Section 3)
- **Autonomous operation** — "uncertain" errors no longer flag for user review; instead delegate to teammate or escalate to Repetiteur (design Section 3)
