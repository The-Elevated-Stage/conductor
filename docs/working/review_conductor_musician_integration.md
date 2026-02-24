# Conductor-Musician Integration Review Findings

*Source: Musician skill review session, 2026-02-24*
*Reviewer: Musician-Conductor integration reviewer*

**Status: ALL RESOLVED**

Musician-side fixes across two commits:
- Commit `0cd23fa`: Context warning state (`state = 'error'` + `message_type`), review_failed handoff guard
- Commit `e2e43b0`: `error → exited` trigger condition, field count 10 → 11, retry naming, typo fixes, deduplication

Conductor-side fixes:
- Self-Correction `YES/NO` in review-approval-workflow.md example
- `exit_requested` documented as context warning "stop" response (error-recovery.md, musician-lifecycle.md)
- Agents Remaining format aligned to `count (~X% each, ~Y% total)` (Musician-side update)
- Key Outputs added to inline field summary (review-protocol.md)
- Review loop query now filters by checkpoint number (review-protocol.md)

## Major (3) — ALL RESOLVED

### CM-M1: Self-Correction `true/false` in Conductor example vs `YES/NO` everywhere else (RESOLVED)
- **Resolution:** Updated review-approval-workflow.md to use `YES/NO` consistently.

### CM-M2: Context warning — `review_failed` as "stop now" semantic mismatch (RESOLVED)
- **Resolution (Musician):** `review_failed` handler now reads feedback first — if it directs handoff, Musician prepares HANDOFF and exits cleanly.
- **Resolution (Conductor):** Context warning protocol now uses `exit_requested` (not `review_failed`) for "stop and handoff" — semantically correct as a lifecycle decision, not a quality judgment.

### CM-M3: Context exhaustion at 65% — Musician didn't set `state = 'error'` (RESOLVED on Musician side)
- **Resolution:** Musician now explicitly sets `state = 'error'`, `last_error = 'context_exhaustion_warning'`, and `message_type = 'context_warning'` at 65%.

## Minor (9) — ALL RESOLVED

### CM-m1: `exit_requested` documented in Musician but never triggered by Conductor (RESOLVED)
- **Resolution:** Conductor's context-warning-protocol and context-situation-checklists now include `exit_requested` as the "stop and handoff" response. Updated error-recovery.md and musician-lifecycle.md.

### CM-m2: `error -> exited` transition lacks documented trigger condition (RESOLVED on Musician side)
- **Resolution:** Updated to `error -> exited (TERMINAL: retry exhaustion after 5 failed retries)`.

### CM-m3: Agents Remaining format mismatch (RESOLVED on Musician side)
- **Resolution:** Musician updated to `count (~X% each, ~Y% total)` in SKILL.md and database-queries.md, aligning with Conductor's expectations and existing example usage.

### CM-m4: Review request template field count mismatch (RESOLVED)
- **Musician-side:** Updated to 11 fields (Key Outputs promoted to numbered field 11).
- **Conductor-side:** Added Key Outputs to inline field summary in review-protocol.md. Template already had Reason and Key Outputs fields; inline description now matches.

### CM-m5: Context warning `message_type` not surfaced in Musician spec (RESOLVED on Musician side)
- **Resolution:** Musician now specifies `message_type = 'context_warning'` explicitly.

### CM-m6: Review loop tracking counts ALL review_requests, not per-checkpoint (RESOLVED)
- **Resolution:** Updated review-protocol.md query to filter by checkpoint number via `LIKE 'CHECKPOINT {N}:%'`. Cap is per-checkpoint as intended.

### CM-m7: "Conductor-level retries" naming inconsistency (RESOLVED on Musician side)
- **Resolution:** Updated to "5 total retries (musician increments, conductor monitors the count)".

### CM-m8: `review_approved` for context warning relies on implicit semantics (NO ACTION NEEDED)
- **Assessment:** Low impact — Musician proposed a plan, Conductor approved it, Musician resumes with its own plan. Works as designed.

### CM-m9: Compact Protocol invisible to Musician (NO ACTION NEEDED)
- **Assessment:** Intentionally asymmetric. Conductor decides recovery approach; Musician's HANDOFF works for both paths.
