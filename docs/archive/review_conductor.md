# Conductor Skill — Review Findings

*Source: 9-reviewer parallel review session, 2026-02-20*
*Reviewers: SKILL.md structure, example files, inter-file references, broad skill, Musician integration, Copyist integration, Repetiteur integration, Arranger integration, message-watcher gap analysis*

---

## Critical (3)

### F1: RAG processing monitoring contradiction — REDESIGN
- **Source:** Message-watcher gap analysis
- **Files:** `references/review-protocol.md:483`, `references/phase-execution.md:554-558`
- **Issue:** `review-protocol.md:483` claims "background message-watcher runs continuously during all RAG phases" — but the watcher already exited to trigger the review that led to RAG processing. No instruction exists to relaunch the watcher before RAG processing begins. The next watcher launch occurs only when RAG completes and the Conductor returns to the monitoring cycle.
- **Impact:** 15-45 minute blind window during RAG processing. All Musician state changes (completions, errors, review requests) are missed until RAG finishes.
- **Also:** Conductor heartbeat goes stale during this window (see F11).
- **Decision:** Redesign RAG pipeline as a **teammate model**. One RAG teammate handles the entire pipeline (overlap check, ambiguity identification, merges, ingestion). Conductor stays in monitoring loop — its only involvement is reading a message from the teammate and responding with decisions (approve/merge/reject). This resolves F1 (no monitoring gap), F8 (no user involvement — autonomous two-mind model), and the "over-engineered" concern from the broad review (one teammate replaces two foreground subagents + manifest + decision log). The `rag-processing-workflow` section in `review-protocol.md` shrinks significantly. The `rag-processing-subagent-prompts.md` example gets rewritten for the teammate model.

### F2: Danger file annotation source undefined
- **Source:** Arranger integration review
- **Files:** `references/phase-execution.md:60-73`
- **Issue:** The Conductor expects task-level danger file annotations with `[warning] Danger Files:` format from the Arranger's plan. The Arranger has no concept of "danger files" and does not produce task-level annotations (it explicitly does not do task decomposition). The Conductor's 3-step danger file governance workflow will find nothing to extract, silently skipping file-conflict mitigation.
- **Design decision needed:** (a) Arranger annotates file-conflict risks at phase level, Conductor maps to tasks during decomposition. (b) Conductor discovers file conflicts independently during task decomposition. Option (a) = front-load research. Option (b) = task decomposition is Conductor's concern.

### F3: Missing PID capture in launch example
- **Source:** Example files review, Musician integration review
- **Files:** `examples/launching-execution-sessions.md:124-142`
- **Issue:** Template marked `<template follow="exact">` omits `echo $! > temp/musician-{task-id}.pid` after the `&`. The reference template at `references/phase-execution.md:299` correctly includes it. Without PID capture, lifecycle management (kill, cleanup) in `examples/completion-coordination.md` step 9 would fail.
- **Fix:** Add PID capture line to the example template.

---

## Major (7)

### F4: Only 2 of 12 event handlers have explicit watcher relaunch instructions
- **Source:** Message-watcher gap analysis
- **Files:** Multiple references
- **Issue:** Only Review Protocol (`review-protocol.md:77`) and Musician Error Workflow (`error-recovery.md:106`) have explicit mandatory-tagged "relaunch the watcher" instructions. All other handlers rely on implicit routing ("return to Phase Execution Protocol") or have NO relaunch instruction:
  - Error Recovery — Context Warning: implicit routing
  - Error Recovery — Stale Heartbeat: routes to Musician Lifecycle, no relaunch
  - Error Recovery — Claim Failure: routes to Musician Lifecycle, no relaunch
  - Musician Lifecycle — all handoff types: ends with "launch replacement session," no watcher relaunch
  - Musician Lifecycle — Post-Completion Resume: launches resumed session, no relaunch
  - Repetiteur — Plan Changeover: implicit routing
  - RAG Processing: implicit routing
  - Phase Completion: implicit routing
- **Impact:** Systemic risk — the Conductor must "remember" to return to monitoring after every handler. The skill does not consistently remind it.

### F5: No Conductor context exhaustion / session handoff protocol
- **Source:** SKILL.md review, Broad review
- **Files:** `SKILL.md:55` (mentions 1m context), no protocol anywhere
- **Issue:** No guidance for:
  1. How the Conductor detects its own context pressure
  2. When to set `exit_requested`
  3. What state to persist for a successor Conductor session
  4. How to resume orchestration in a new session
- **Impact:** A Conductor that runs out of context mid-orchestration leaves Musicians orphaned with no recovery path.

### F6: Incomplete Repetiteur consultation scenario missing
- **Source:** Repetiteur integration review
- **Files:** `references/repetiteur-invocation.md:363-380` (error-scenarios section)
- **Issue:** The Repetiteur design defines mandatory exit at 75% context where it sends an "incomplete consultation" message and expects the Conductor to spawn a fresh Repetiteur session. The Conductor's error-scenarios section covers vision deviation, verification loop failure, handoff parse failure, and crash — but NOT "incomplete, spawn fresh session."
- **Fix:** Add a new error scenario for receiving an incomplete-consultation message. Fresh Repetiteur should continue from the partial journal. Count as same consultation number (continuation, not new invocation).

### F7: Error recovery example contradicts autonomous model
- **Source:** Example files review, Broad review
- **Files:** `examples/error-recovery-workflow.md:152-165`
- **Issue:** "Alternative: Complex Error (Retry 3+)" section shows: `Prompt user: "Task-05 has failed 3 times..."` with 3 user-facing options. SKILL.md line 29: "Fully autonomous after bootstrap user approval — do not wait for user input during execution." The reference error-recovery protocol does not include user prompting — it classifies, investigates (via teammate), and proposes fixes autonomously.
- **Fix:** Replace user prompt with autonomous investigation decision (launch teammate, classify, fix).

### F8: RAG processing example contradicts autonomous model — RESOLVED BY F1
- **Source:** Broad review
- **Files:** `examples/rag-processing-subagent-prompts.md:28-29`
- **Issue:** Workflow overview says: "For review needed items: present to user in bulk... User decides per proposal: approve as new file, merge into existing, or reject." The reference file (`review-protocol.md:409-411`) says: "The Conductor makes RAG decisions autonomously."
- **Resolution:** Subsumed by F1 redesign. The RAG teammate model eliminates user involvement entirely. Teammate proposes, Conductor decides, teammate executes. Example will be rewritten as part of F1 implementation.

### F9: Instructions boilerplate diverges from Copyist canonical version
- **Source:** Copyist integration review
- **Files:** `references/phase-execution.md:216-224`
- **Issue:** Conductor has 7-step Instructions block; Copyist's canonical template has 8 steps with different content (Copyist has explicit "Read schema reference" step; Conductor omits it). Copyist's `launch-prompt-template.md:51` says "The Instructions section is fixed boilerplate. The conductor does not modify it."
- **Fix:** Adopt Copyist's canonical version verbatim. Remove the Conductor's independent copy.

### F10: No Conductor-side validation of Copyist output
- **Source:** Copyist integration review
- **Files:** `references/phase-execution.md:184`
- **Issue:** Only guidance is "spot-check alignment with phase goals" — no checklist, no script, no minimum criteria. The Copyist has robust self-validation (25+ point checklist + 335-line shell script), but if self-validation misses something, the Conductor has no safety net. External sessions are expensive.
- **Fix:** Add explicit validation step after Copyist returns: run validate-instruction.sh on each file. If any fail, invoke Copyist Output Errors handling.

---

## Moderate (5)

### F11: Stale Conductor heartbeat during long handlers
- **Source:** Message-watcher gap analysis
- **Files:** `references/phase-execution.md:593-598`
- **Issue:** The monitoring watcher refreshes `task-00` heartbeat every poll cycle. When no watcher is running (during event handling), the heartbeat goes stale. After 9 minutes (540 seconds), Musicians consider the Conductor down and may escalate unnecessarily.
- **Impact:** Affects any handler >9 minutes: complex error investigation, RAG processing, deep reviews. Creates false alarms.

### F12: Missing DDL indexes in initialization example
- **Source:** Example files review
- **Files:** `examples/conductor-initialization.md:111-148`
- **Issue:** Template marked `<template follow="exact">` omits 3 `CREATE INDEX` statements present in the reference (`references/initialization.md:146-194`). A Conductor following the example would create tables without indexes, affecting query performance during monitoring.
- **Fix:** Add indexes to example, or change template from `follow="exact"` to `follow="format"` with a brevity note.

### F13: No guidance for total phase failure
- **Source:** Broad review
- **Files:** `references/phase-execution.md:701-714` (phase-completion section)
- **Issue:** Phase completion proceeds when all tasks reach terminal state, even if ALL are `exited` (zero `complete`). Proceeding to the next phase with zero deliverables from the current phase is likely wrong.
- **Fix:** Add check: if all tasks in a phase are `exited` (none `complete`), treat as systemic failure. Do not proceed to next phase. Route to Repetiteur Protocol.

### F14: "Sections index" reference ambiguous in mandatory rules
- **Source:** SKILL.md review
- **Files:** `SKILL.md:37`
- **Issue:** "Reference files are read selectively — read the sections index first" does not clarify it means the reference file's `<sections>` tag. Could be misinterpreted as SKILL.md's own sections index.
- **Fix:** Change to "read the reference file's `<sections>` tag first, then only the `<section id="...">` needed."

### F15: No explicit entry point directive in preamble
- **Source:** SKILL.md review
- **Files:** `SKILL.md:49-51`
- **Issue:** The preamble describes the Conductor's role and entry conceptually but never says "your first action is to proceed to the Initialization Protocol." A Conductor loading the skill for the first time has to infer the entry point.
- **Fix:** Add one sentence at end of preamble `<core>`: "After loading this skill, proceed immediately to the Initialization Protocol."

---

## Minor (14)

### F16: Example file versions are 2.0, references/SKILL.md are 3.0
- **Source:** Inter-file references review, Broad review
- **Files:** All 7 files in `examples/`
- **Issue:** Version metadata mismatch suggests examples weren't updated with the v3.0 overhaul.
- **Fix:** Update all example `version` metadata to `3.0`.

### F17: RAG example step number references wrong
- **Source:** Example files review, Inter-file references review
- **Files:** `examples/rag-processing-subagent-prompts.md:19`
- **Issue:** Says "Monitoring step 6.5 or Review Workflow step 9." Reference has RAG at "Step 8" (not 9), and "step 6.5" doesn't exist in the monitoring cycle.
- **Fix:** Change to "Review Workflow step 8 (eager trigger) or during quiet monitoring cycles (fallback trigger)."

### F18: Review example step numbering diverges from protocol
- **Source:** Example files review
- **Files:** `examples/review-approval-workflow.md`
- **Issue:** Example has 5 steps (Read Message, Update State, Read Proposal, Check Self-Correction, Approve/Reject, Resume). Protocol has 9 steps. Example inserts "Update Conductor State" not in protocol, omits Review Loop Tracking (step 5), RAG check (step 8). The example also includes a `rag-addition` proposal in the scenario but never shows handling it.
- **Fix:** Add note that example steps are illustrative, not 1:1 with protocol. Add RAG handling note.

### F19: git log command wrong syntax in completion example
- **Source:** Example files review
- **Files:** `examples/completion-coordination.md:166`
- **Issue:** `git log --oneline feat/docs-reorganization..HEAD` shows zero commits (same ref). Should be `git log --oneline main..HEAD` per the reference.
- **Fix:** Change to `main..HEAD`.

### F20: Staleness state list inconsistency between references
- **Source:** Example files review
- **Files:** `references/phase-execution.md:775-776` vs `references/error-recovery.md:514-517`
- **Issue:** Phase-execution uses `NOT IN ('complete', 'exited')` (includes watching, needs_review, etc.). Error-recovery uses `IN ('working', 'review_approved', 'review_failed', 'fix_proposed')` (conservative). Monitoring example matches error-recovery. The conservative list is more practical.
- **Fix:** Align phase-execution to use the conservative list.

### F21: No example coverage for Repetiteur, Sentinel, or Musician Lifecycle
- **Source:** Example files review
- **Issue:** These three protocols have no dedicated examples. Repetiteur is the most complex protocol and would benefit most from an example.

### F22: Two protocol routing statements missing "via SKILL.md" qualifier
- **Source:** Inter-file references review
- **Files:** `references/review-protocol.md:126`, `references/completion.md:62`
- **Issue:** "correct via the Error Recovery Protocol" and "Investigate via the Error Recovery Protocol" omit "via SKILL.md" unlike dozens of other instances.
- **Fix:** Add "(via SKILL.md)" for consistency.

### F23: Monitoring example missing conductor heartbeat refresh
- **Source:** Musician integration review
- **Files:** `examples/monitoring-subagent-prompts.md:67-101`
- **Issue:** Main monitoring prompt does not include the `task-00` heartbeat refresh step. Reference template at `phase-execution.md:619-643` includes it. Without it, Conductor heartbeat goes stale.
- **Fix:** Add heartbeat refresh to example prompt.

### F24: "Arranger phase sections" wording opaque
- **Source:** SKILL.md review
- **Files:** `SKILL.md:39`
- **Issue:** "Items with mandatory authority tags in Arranger phase sections" — term "Arranger phase sections" may be unclear at first encounter.
- **Fix:** Change to "the implementation plan's phase sections."

### F25: Context warning message type used incorrectly in example
- **Source:** Example files review
- **Files:** `examples/error-recovery-workflow.md:196-207`
- **Issue:** Conductor response uses `message_type = 'context_warning'` for its reply. `context_warning` is what the Musician sends to report the problem, not the Conductor's response type. Should be `fix_proposal` (state is `fix_proposed`) or `approval`.
- **Fix:** Change message_type to `fix_proposal`.

### F26: All 7 example files are orphaned from SKILL.md
- **Source:** Inter-file references review
- **Issue:** No path from SKILL.md to any example file. Examples are discoverable only by browsing the directory. They serve no function in the skill's operational flow (by design — examples are for offline reference).
- **Recommendation:** Consider adding optional `<reference>` tags in protocol sections pointing to relevant examples, or document the convention that examples are offline-only.

### F27: Initialization example missing "Selective" qualifier
- **Source:** Example files review
- **Files:** `examples/conductor-initialization.md` Step 1
- **Issue:** Header says "Read Implementation Plan" without "(Selective)". Body shows a bare `Read` command, not the selective plan-index-first pattern the reference mandates.
- **Fix:** Add "(Selective)" to heading and show plan-index reading pattern.

### F28: "Old Table Names" section may be stale
- **Source:** Broad review
- **Files:** `references/initialization.md:407-422`
- **Issue:** 16 lines of "never use these old names" for a migration that has already happened. If no legacy references exist anywhere, this section is dead weight.
- **Fix:** Search codebase for old names (`coordination_status`, `migration_tasks`, `task_messages`). If zero hits, remove section.

### F29: Initialization example uses old plan path format
- **Source:** Broad review
- **Files:** `examples/conductor-initialization.md:29`
- **Issue:** References `docs/plans/2026-02-04-docs-reorganization.md`. Repetiteur protocol uses `docs/plans/designs/{feature}-plan.md`. Inconsistent convention.
- **Note:** Examples are illustrative scenarios, not live paths. May not need fixing if path format is understood as scenario-specific.
