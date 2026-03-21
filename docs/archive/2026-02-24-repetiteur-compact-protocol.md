# Conductor Update Required: Repetiteur Compact Protocol

**Date:** 2026-02-24
**Source:** Repetiteur skill review (I10)
**Status:** Pending implementation

---

## Summary

The Repetiteur skill defines a `[COMPACT_READY]` signal for context exhaustion recovery. The Conductor needs to recognize and act on this signal. This document describes what the Conductor needs to know about the protocol and what the Repetiteur expects.

---

## The Signal

The Repetiteur monitors its own context usage throughout a consultation. The compaction flow is:

1. **At 65% context:** Writes a lightweight checkpoint, stops starting new stages, continues finishing the current stage only
2. **When current stage completes (post-65%):** Writes a full checkpoint to its consultation journal (all 9 required fields — current stage, blocker summary, constraint map, impact map, resolution decisions so far, remaining work assessment, Conductor dialogue state with LAST_READ_ID, files modified, and next action), then sends a `[COMPACT_READY]` message to the `repetiteur_conversation` table
3. **At 75% (safety net):** If the current stage is still running at 75%, the Repetiteur writes the full checkpoint immediately and sends `[COMPACT_READY]` regardless of stage completion

The signal typically fires between 65-75%, after the current stage finishes. 75% is the hard stop.

### Message Format

```sql
INSERT INTO repetiteur_conversation (sender, message)
VALUES ('repetiteur', '[COMPACT_READY] Checkpoint written: {journal_path}. Current stage: {stage_name}.');
```

**Fields:**
- `{journal_path}` — Absolute path to the consultation journal containing the checkpoint (e.g., `docs/plans/designs/decisions/feature-name/consultation-1-journal.md`)
- `{stage_name}` — One of: `ingestion`, `impact-assessment`, `resolution`, `verification`, `handoff-prep`

### Example

```sql
INSERT INTO repetiteur_conversation (sender, message)
VALUES ('repetiteur', '[COMPACT_READY] Checkpoint written: docs/plans/designs/decisions/background-sync/consultation-1-journal.md. Current stage: resolution.');
```

---

## Expected Conductor Action

1. **Detect** the `[COMPACT_READY]` prefix in a new `repetiteur_conversation` row where `sender = 'repetiteur'`
2. **Kill** the Repetiteur's Kitty session
3. **Relaunch** a new Kitty session with the same `/repetiteur` skill invocation
4. **Include in the spawn prompt:**
   - The original blocker report (same as initial invocation)
   - The checkpoint journal path from the `[COMPACT_READY]` message
   - The current stage from the `[COMPACT_READY]` message
   - An instruction that this is a resumed consultation, not a new one

The restarted Repetiteur reads its own checkpoint from the journal and resumes from the indicated stage.

---

## Key Properties

- **One-way signal:** Like `[HANDOFF]`, this requires no reply in the conversation table. The Conductor acts on it directly.
- **No response expected:** The Repetiteur session is about to be killed — it does not poll for a response after sending this.
- **Timing:** Can occur at any point during the consultation — mid-resolution, mid-verification, etc. The checkpoint captures whatever state exists at that moment.
- **Frequency:** Typically once per consultation, but could theoretically occur multiple times if a consultation is unusually large. Each `[COMPACT_READY]` follows the same protocol.
- **Journal is the recovery mechanism:** The checkpoint in the journal is what allows the new session to resume. The `[COMPACT_READY]` message is just the trigger for the Conductor to act.

---

## Detection Pattern

The Conductor should watch for `[COMPACT_READY]` with the same polling mechanism it uses for `[HANDOFF]` detection in the `repetiteur_conversation` table. Both are prefix-based signals from `sender = 'repetiteur'`.

```sql
SELECT id, message FROM repetiteur_conversation
WHERE sender = 'repetiteur'
AND message LIKE '[COMPACT_READY]%'
ORDER BY id DESC LIMIT 1;
```
