# Sentinel Monitoring Protocol — Extraction Proposal

**Target protocol file:** `references/protocols/sentinel-monitoring.md`
**Date:** 2026-02-20

## Summary

The Sentinel Monitoring Protocol is almost entirely NEW content from the design document (Section 7). The existing reference files contain no "sentinel" concept — the Sentinel is a new teammate type introduced in the overhaul. However, several existing reference files contain content about temp/ file formats and monitoring patterns that should be co-located here for context.

---

## 1. Sentinel Concept and Purpose
**Source:** Design document, Section 7 ("Sentinel Teammate"), lines 231-256
**Authority:** core
**Proposed section ID:** concept
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. Verbatim from Section 7 "Concept" paragraph: "A lightweight teammate that watches all active Musicians' temp/ logs and sends fire-and-forget reports to the Conductor when it spots anomalies. Purely additive to the existing background message-watcher."

---

## 2. Anomaly Detection Criteria
**Source:** Design document, Section 7 ("Anomaly Criteria"), lines 237-243
**Authority:** mandatory
**Proposed section ID:** anomaly-criteria
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design. Four mechanical criteria:
- Any `self-correction` entry in status log
- Any `High:` severity deviation
- Context usage jump >15% between consecutive entries
- No new entries for >5 minutes (stuck/looping)

Should be marked `<mandatory>` since these are the exact, non-negotiable detection rules.

---

## 3. Sentinel Behavior (Polling and Reporting)
**Source:** Design document, Section 7 ("Behavior"), lines 245-249
**Authority:** core
**Proposed section ID:** behavior
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design:
- Polls temp/ files on ~10 second interval
- Reports anomalies via SendMessage, immediately resumes watching
- Does NOT wait for or expect responses from Conductor
- Conductor decides independently whether to act (emergency broadcast) or note (informational)

---

## 4. Sentinel Lifecycle Management
**Source:** Design document, Section 7 ("Lifecycle"), lines 251-256
**Authority:** core
**Proposed section ID:** lifecycle
**Duplication note:** None — unique to this protocol
**Modification needed:** New content from design:
- Launched when Musicians launch for a phase
- Runs alongside the background message-watcher subagent
- Shut down when Conductor messages it that the phase is complete

---

## 5. Sentinel Prompt Template
**Source:** Design document, Section 7 (entire section — must be synthesized into a template)
**Authority:** core (template follow="format")
**Proposed section ID:** prompt-template
**Duplication note:** None — unique to this protocol
**Modification needed:** Entirely new. Needs to be created from the design document's specifications. Should be a `<template>` block containing the prompt the Conductor uses to launch the Sentinel teammate. Must include:
- List of temp/ file paths to monitor (parameterized by active task IDs)
- The four anomaly criteria (duplicated from anomaly-criteria section for self-containment)
- SendMessage reporting format
- Instructions to NOT wait for responses
- ~10 second polling interval
- Exit behavior (only when Conductor sends shutdown message)

---

## 6. Conductor Integration — Launching the Sentinel
**Source:** Design document, Section 7, lines 251-252 + Section 9 (Monitoring & Watcher Reinforcement)
**Authority:** core
**Proposed section ID:** conductor-integration
**Duplication note:** Partially duplicates phase-execution protocol (which will reference "launch Sentinel" as a step)
**Modification needed:** New content. Describes when and how the Conductor launches the Sentinel:
- Launch timing: after Musicians launch for a phase (same as message-watcher)
- Launch method: Task tool with SendMessage capability (teammate, not regular subagent)
- Relationship to background message-watcher: runs alongside, independent
- Phase completion: Conductor sends shutdown message

---

## 7. Temp File Format Reference (Dependency on Musician Skill)
**Source:** references/session-handoff.md, lines 98-99, 109; references/parallel-coordination.md, lines 197, 201
**Authority:** context
**Proposed section ID:** temp-file-formats
**Duplication note:** Also belongs in musician-lifecycle protocol (handoff procedures reference temp/ files).
**Modification needed:** This section should NOT define the temp file format — the Musician skill owns the format (it writes the files). Instead, this section should:
- Note the dependency: "The Sentinel reads temp/ files whose format is defined by the Musician skill"
- Reference the Musician skill's temp file format specification
- List which files the Sentinel monitors (`temp/task-{NN}-status`) and which it ignores (`temp/task-{NN}-HANDOFF`, `temp/musician-task-{NN}.pid`)
- Note that the Sentinel's anomaly criteria (self-correction entries, severity levels, context usage %) depend on the Musician writing these fields in the expected format

---

## 8. Temp File Path Patterns
**Source:** references/session-handoff.md, lines 52, 62, 98, 109; references/parallel-coordination.md, lines 197, 201
**Authority:** core
**Proposed section ID:** temp-file-formats (subsection)
**Duplication note:** Also in musician-lifecycle protocol
**Modification needed:** Consolidation of existing scattered references into a clear table:
- `temp/task-{NN}-status` — Musician status log (written by Musician, read by Sentinel and Conductor)
- `temp/task-{NN}-HANDOFF` — Handoff document (written by Musician on clean exit)
- `temp/musician-task-{NN}.pid` — PID file (from design document Section 6, line 203)

---

## 9. Anomaly Report Message Format
**Source:** Design document, Section 7 (synthesized from behavior description)
**Authority:** core (template follow="format")
**Proposed section ID:** report-format
**Duplication note:** None — unique to this protocol
**Modification needed:** Entirely new. Must create a template for the SendMessage format the Sentinel uses to report anomalies to the Conductor. Should include:
- Task ID affected
- Anomaly type (one of the four criteria)
- Relevant data (e.g., context jump from X% to Y%, or "no entries for N minutes")
- Timestamp of detection

---

## 10. Relationship to Background Message-Watcher
**Source:** Design document, Section 7 line 235 + Section 9 (Monitoring & Watcher Reinforcement), lines 283-294
**Authority:** context
**Proposed section ID:** relationship-to-watcher
**Duplication note:** Phase-execution protocol will also describe the watcher
**Modification needed:** New content clarifying the distinction:
- Background message-watcher: polls comms-link database for state changes, exits on detection, Conductor relaunches
- Sentinel: polls temp/ files for anomalies, does NOT exit on detection (fire-and-forget), runs continuously until phase complete
- They serve different purposes: watcher is the primary event loop, Sentinel is early warning
- Sentinel is "purely additive" — the system works without it, Sentinel adds proactive detection

---

## 11. Design Decision: Sentinel as Teammate (not Subagent)
**Source:** Design document, Section 3 ("Delegation Model"), lines 137-138
**Authority:** context
**Proposed section ID:** design-rationale
**Duplication note:** None
**Modification needed:** New content explaining why the Sentinel is a teammate rather than a regular Task subagent:
- Design doc Section 3: "Teammates (>40k estimated tokens): ... Resumable with preserved context"
- Design doc Section 3: "Regular Task subagents (<40k): Monitoring watchers, simple polling, quick one-shot checks"
- The Sentinel is long-running (entire phase) and needs SendMessage capability
- Launched via standard Task tool with `team_name` parameter (same as other teammates)
- As a teammate, it can send messages independently without exiting
- Contrast with background message-watcher which IS a regular Task subagent (exits on detection)

---

## Content NOT Included (Assessed and Excluded)

The following existing reference file content was assessed and determined NOT to belong in this protocol:

- **Database monitoring queries** (database-queries.md, patterns 11-19) — These belong in phase-execution and other protocols. The Sentinel monitors temp/ files, not the database.
- **Monitoring subagent prompts** (examples/monitoring-subagent-prompts.md) — These are for the background message-watcher, not the Sentinel. Different mechanism entirely.
- **Staleness detection SQL** (state-machine.md, staleness-detection section) — Database-based staleness. Sentinel's "no entries >5 minutes" criterion is file-based, not SQL.
- **Context warning protocol** (SKILL-v2-monolithic.md, error-handling section) — Conductor handles context warnings from database state changes. Sentinel may detect the SAME issue via temp/ files earlier, but the handling protocol belongs in error-recovery, not here.

---

## Cross-Protocol References

When building this protocol file, it should contain:
1. **Outbound references (name only, per routing constraint):**
   - "Proceed to Phase Execution Protocol" — for launch timing context
   - "Proceed to Error Recovery Protocol" — if anomaly warrants Conductor intervention

2. **Inbound references (other protocols will point here):**
   - Phase Execution Protocol will reference "Launch Sentinel Monitoring" as a step
   - SKILL.md `<section id="sentinel-monitoring">` will contain the hollow routing section pointing to this file

---

## Open Questions (RESOLVED)

1. **Temp file status log format:** RESOLVED — The Musician skill defines the temp file format (it writes the files). The Sentinel only reads them. This protocol should reference the Musician skill's temp file format specification rather than defining the format itself. Entry #7 (Temp File Format Reference) should be reframed as a dependency note pointing to the Musician skill, not an inline format definition.

2. **Teammate launch mechanism:** RESOLVED — Standard Task tool with `team_name` parameter, same as other teammates in the orchestration. Not a kitty window launch.

3. **Multiple phases:** RESOLVED — One Sentinel per phase lifecycle. Launch when Musicians launch for a phase, shut down by sending the Sentinel a message when the phase completes. New Sentinel launched for the next phase.
