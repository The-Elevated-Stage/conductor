# Conductor-Musician Integration Review Findings

*Source: Musician skill review session, 2026-02-24*
*Reviewer: Musician-Conductor integration reviewer*

**Note:** Multiple findings have been resolved on the Musician side across two commits:
- Commit `0cd23fa`: Context warning state (`state = 'error'` + `message_type`), review_failed handoff guard
- Commit `e2e43b0`: `error → exited` trigger condition, field count 10 → 11, retry naming, typo fixes, deduplication

Resolved items are marked below. Remaining open items are Conductor-side only.

## Major (3)

### CM-M1: Self-Correction `true/false` in Conductor example vs `YES/NO` everywhere else
- **File:** review-approval-workflow.md lines 51, 100-104
- **Issue:** The Conductor's review-approval-workflow example uses `Self-Correction: false` and `Self-Correction: true` (lowercase booleans). The Conductor's own review-protocol.md (lines 54, 57, 87, 227) and the Musician both specify `YES/NO`. The routing logic checks for `Self-Correction: YES` which wouldn't match `true`.
- **Fix:** Update the example to use `YES/NO` consistently.

### CM-M2: Context warning — `review_failed` as "stop now" semantic mismatch (RESOLVED on Musician side)
- **File:** error-recovery.md line 135 (context-warning-protocol)
- **Issue:** Conductor's context-warning-protocol lists `review_failed` as meaning "Stop now, prepare handoff immediately." The Musician's `review_failed` handler was designed for review rejections (resume work, apply feedback, resubmit). This created a semantic mismatch where the Conductor meant "stop" but the Musician would resume.
- **Resolution:** Musician's `review_failed` handler now reads feedback first — if it directs handoff (context exhaustion, stop work), the Musician prepares HANDOFF and exits cleanly instead of resuming. No Conductor changes needed, but the Conductor should ensure its `review_failed` message for context warnings clearly indicates handoff intent.

### CM-M3: Context exhaustion at 65% — Musician didn't set `state = 'error'` (RESOLVED on Musician side)
- **File:** error-recovery.md lines 503-508 (context-warning-detection-sql)
- **Issue:** Conductor detects context warnings via `WHERE state = 'error' AND last_error = 'context_exhaustion_warning'`. Musician's normative spec only said to set `last_error` but never explicitly mentioned `state = 'error'`. Without the state change, the detection query would miss the warning.
- **Resolution:** Musician now explicitly sets `state = 'error'`, `last_error = 'context_exhaustion_warning'`, and `message_type = 'context_warning'` at 65%. No Conductor changes needed.

## Minor (9)

### CM-m1: `exit_requested` documented in Musician but never triggered by Conductor for Musician tasks
- **Files:** Musician state-machine.md line 43, SKILL.md line 304; all Conductor references
- **Issue:** The Musician has a fully documented handler for `exit_requested` (prepare HANDOFF, set `exited`, exit cleanly). The Conductor's guard clause includes `exit_requested` as a claimable state (musician-lifecycle.md line 314). But the Conductor never documents WHEN or HOW to set `exit_requested` on a Musician task — no SQL template, no protocol section, no example.
- **Impact:** The state exists as dead code in the protocol. The Conductor uses `fix_proposed` with handoff instructions or sets tasks to `exited` directly instead.
- **Fix:** Either document the Conductor workflow for setting `exit_requested` on Musician tasks (e.g., during Repetiteur consultation, user-requested stop, emergency broadcasts), or note it as reserved/future.

### CM-m2: `error -> exited` transition lacks documented trigger condition (RESOLVED on Musician side)
- **File:** Musician state-machine.md line 66
- **Issue:** Showed `error -> exited (TERMINAL: unrecoverable failure)` without specifying the trigger condition.
- **Resolution:** Updated to `error -> exited (TERMINAL: retry exhaustion after 5 failed retries)` in commit `e2e43b0`.

### CM-m3: Agents Remaining format: "count (description)" vs "count and %"
- **Files:** Musician SKILL.md line 320 vs Conductor review-protocol.md line 54
- **Issue:** Musician describes the format as "count (description)" while the Conductor expects "count and %" with per-agent and total percentage estimates. Conductor's template (review-protocol.md line 229) shows: `Agents Remaining: {N} (~{X}% each, ~{Y}% total)`.
- **Impact:** Musician examples do include percentage data in practice, so actual behavior aligns. But the normative specs don't match.
- **Fix:** Update Musician's field description to "count (~X% each, ~Y% total)" or update Conductor to accept either format.
- **Owner:** Either skill — align one to the other.

### CM-m4: Review request template field count mismatch (PARTIALLY RESOLVED)
- **Files:** Musician database-queries.md vs Conductor review-protocol.md lines 224-236
- **Issue:** Musician and Conductor had different field counts and field lists.
- **Musician-side resolution:** Updated to 11 fields (Key Outputs promoted from addendum to numbered field 11) in commit `e2e43b0`.
- **Remaining Conductor-side:** Conductor's template includes `Checkpoint: {N} of {M}` but lacks `Reason (why review needed)`. Musician has `Reason` but not `Checkpoint`. Reconcile by adding both to the Conductor's template.
- **Owner:** Conductor.

### CM-m5: Context warning `message_type` not surfaced in Musician spec (RESOLVED)
- **Issue:** Musician didn't specify what `message_type` value to use for context warnings, despite mandatory rule about no NULL message types.
- **Resolution:** Musician now specifies `message_type = 'context_warning'` explicitly.

### CM-m6: Review loop tracking counts ALL review_requests, not per-checkpoint
- **File:** Conductor review-protocol.md lines 160-162
- **Issue:** The review loop count query counts all `review_request` messages for the entire task, not per checkpoint. Tasks with multiple checkpoints could hit the 5-cycle escalation cap prematurely.
- **Impact:** Conservative (escalates early) rather than dangerous.
- **Fix:** Consider adding a checkpoint number to review request messages, or document that the 5-cycle cap is task-wide intentionally.
- **Owner:** Conductor.

### CM-m7: "Conductor-level retries" naming inconsistency (RESOLVED on Musician side)
- **File:** Musician database-queries.md line 80
- **Issue:** Musician said "out of 5 conductor-level retries" implying the Conductor manages them.
- **Resolution:** Updated to "out of 5 total retries (musician increments, conductor monitors the count)" in commit `e2e43b0`.

### CM-m8: `review_approved` for context warning relies on implicit semantics
- **Files:** Conductor error-recovery.md line 133; Musician SKILL.md line 301
- **Issue:** When Conductor responds to a context warning with `review_approved` (meaning "proceed with Musician's proposed scope reduction"), the Musician's handler just says "proceed with next steps." The protocol relies on the Musician remembering its own proposal rather than receiving explicit instructions.
- **Impact:** Low in practice — the Musician proposed a plan and the Conductor approved it, so the Musician resumes with its own plan.
- **Fix:** No action needed unless problems arise in practice.

### CM-m9: Compact Protocol invisible to Musician (intentional asymmetry)
- **Files:** Musician SKILL.md lines 414-421; Conductor SKILL.md lines 274-287
- **Issue:** Musician describes a traditional handoff model (new session reads HANDOFF). Conductor may instead use Compact Protocol (kill -> compact -> resume). Musician doesn't know which approach will be used.
- **Impact:** None. This is intentionally asymmetric — the Conductor decides the recovery approach and the Musician's HANDOFF document works for both paths. The `worked_by` session counter increments correctly under both approaches.
- **Fix:** No action needed.
