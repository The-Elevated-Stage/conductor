# Conductor Update Required: Souffleur v1.2 Provider Split Integration

**Date:** 2026-02-26
**Source Skill:** Souffleur (`a524f45`)
**Status:** Pending Conductor updates

---

## Summary

Souffleur moved from a single relaunch path (`kill -> claude_export -> relaunch`) to a provider-routed recovery model:

1. **Lethe provider (preferred)** for `context_recovery`
2. **claude_export provider (fallback)** when Lethe preflight fails or Lethe launch fails twice before relaunch starts
3. **shared wrap-up** for retry tracking + monitoring re-entry

The Conductor must update its context-exhaustion trigger and related references so this new Souffleur behavior is used safely and consistently.

---

## Routing Clarification (Critical)

Not all recovery events route through Lethe.

- `CONTEXT_RECOVERY` event: uses provider router (Lethe preferred, claude_export fallback pre-relaunch only)
- `CONDUCTOR_DEAD:pid` or `CONDUCTOR_DEAD:heartbeat` events: route directly to **claude_export provider**

This means the Lethe split changes Conductor behavior primarily for planned context exhaustion recovery, not crash/heartbeat-death handling.

---

## What Changed in Souffleur (Conductor-Relevant)

### 1) `context_recovery` trigger is unchanged, but payload is now supported

Souffleur still triggers on:

```sql
UPDATE orchestration_tasks
SET state = 'context_recovery', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

But for provider-routed recovery it now also consumes a structured instruction payload written to `task_id='souffleur'`.

### 2) Payload contract is tagged plaintext

Souffleur reads latest `orchestration_messages` row where:
- `task_id='souffleur'`
- `message_type='instruction'`
- `message LIKE 'CONTEXT_RECOVERY_PAYLOAD_V1%'`

Format:

```text
CONTEXT_RECOVERY_PAYLOAD_V1
permission_mode: <optional>
resume_prompt: <optional>
```

### 3) Souffleur owns PID/session lifecycle

Conductor should **not** pass PID/session_id in the payload.
Souffleur already maintains:
- initial PID/session from `/souffleur PID:... SESSION_ID:...`
- relaunch PID capture (`$!`) on claude_export path
- Lethe completion contract + one-time PID discovery when needed
- session ID rediscovery (`SESSION_ID_FOUND:{id}`) when required

### 4) New degraded mode exists

If Lethe relaunches successfully but Souffleur cannot resolve a PID after one discovery attempt, Souffleur switches watcher to **heartbeat-only** mode and emits warning text.

### 5) No double-relaunch rule

If Lethe has already started a new Conductor generation, Souffleur must not then run claude_export for that same cycle.

### 6) Lethe retry/fallback rule is now explicit

- Lethe launch failure with `relaunch_started=false`: retry Lethe once
- If second pre-relaunch failure: fallback to claude_export provider
- If `relaunch_started=true`: never fallback to claude_export in the same cycle

---

## Defaults and Overrides (Conductor Input Contract)

Souffleur now supports optional Conductor-provided inputs for context recovery:
- `permission_mode`
- `resume_prompt`

If omitted, Souffleur applies defaults:
- `permission_mode`: `acceptEdits`
- `resume_prompt`:

```text
/conductor --recovery-bootstrap

The session history was cleaned, review handoff documents and resume plan implementation.
```

The first line must remain `/conductor --recovery-bootstrap` so Conductor routes directly into Recovery Bootstrap Protocol.

---

## Hard Requirements for Conductor

### Requirement A: Write context-recovery payload before setting `context_recovery`

In Conductor `context-exhaustion-trigger`, add a payload insert step immediately before the final state update.

Recommended SQL template:

```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES (
    'souffleur',
    'task-00',
    'CONTEXT_RECOVERY_PAYLOAD_V1
permission_mode: acceptEdits
resume_prompt: /conductor --recovery-bootstrap

The session history was cleaned, review handoff documents and resume plan implementation.',
    'instruction'
);
```

Then (last step, unchanged kill trigger):

```sql
UPDATE orchestration_tasks
SET state = 'context_recovery', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

### Requirement B: Update orchestration message enum to include `warning`

Souffleur now documents a `warning` insert for degraded heartbeat-only mode.

Current Conductor DDL in `references/initialization.md` excludes `warning` from:

```sql
message_type TEXT CHECK (message_type IN (...))
```

**Must add:** `'warning'`

Otherwise Souffleur warning inserts will violate CHECK constraints in initialized databases.

### Requirement C: Recovery Bootstrap must not assume export path always exists

Conductor recovery bootstrap currently assumes relaunch context always includes an export file path from Souffleur’s old monolithic relaunch contract.

With Lethe provider:
- session may resume from compacted context
- export path may be absent

Recovery bootstrap should support both:
1. **export-present** (claude_export provider path)
2. **export-absent** (Lethe resumed path)

It must not fail or over-assume old Souffleur export semantics.

### Requirement D: Recovery bootstrap framing in `SKILL.md` needs provider-aware wording

`conductor/skill/SKILL.md` currently frames recovery as a "completely new Conductor" with no resumed context.

With Lethe provider, Conductor may enter recovery bootstrap with resumed compacted context. Update wording so protocol entry conditions remain valid for both:
- fresh relaunch from export
- resumed compacted session path

---

## File-by-File Conductor Update Targets

### 1) `conductor/skill/references/error-recovery.md`

Section: `context-exhaustion-trigger`

Required changes:
- Insert new payload-write step before `context_recovery` update
- Keep `context_recovery` update as the terminal kill trigger
- Preserve strict ordering: handoff + MEMORY + close musicians + payload + `context_recovery`

### 2) `conductor/skill/references/initialization.md`

Sections:
- database DDL (`orchestration_messages.message_type` CHECK list)
- any message-type docs/tables

Required changes:
- Add `'warning'` enum value
- Note that Souffleur may emit warnings during degraded monitoring

### 3) `conductor/skill/examples/conductor-initialization.md`

If this example mirrors DDL enum list, keep it in sync with `'warning'`.

### 4) `conductor/skill/references/recovery-bootstrap.md`

Sections likely impacted:
- `purpose`
- `entry-conditions`
- `session-summary`

Required changes:
- Make export file input optional
- Define behavior when no export path exists (Lethe path)
- Remove/replace dependence on old monolithic export-only assumptions

### 5) `conductor/skill/SKILL.md` (recovery bootstrap framing)

Check for statements that assume recovery is always a completely fresh, context-empty session.

With Lethe provider, Conductor may resume from compacted context and still invoke `/conductor --recovery-bootstrap` via prompt. The framing should not contradict that operational mode.

---

## Suggested Conductor Wording Updates

### For context-exhaustion trigger docs

Use this explicit sequence:

1. Write handoff
2. Update MEMORY
3. Close external musicians
4. Insert `CONTEXT_RECOVERY_PAYLOAD_V1` instruction to `task_id='souffleur'`
5. Set `task-00.state='context_recovery'` (terminal step)

### For recovery-bootstrap docs

Add a branch note:
- If export path exists in launch context: read export summary + tail as before
- If no export path: proceed using handoff/MEMORY/comms/learnings and existing context

---

## Validation Checklist for Your Conductor Pass

1. `error-recovery.md` includes payload insert step before `context_recovery` update.
2. Initialization DDL CHECK list includes `warning` message type.
3. Examples that mirror DDL are updated to include `warning`.
4. Recovery bootstrap docs no longer require export path as always-present.
5. Recovery bootstrap references to Souffleur relaunch semantics are provider-aware (not export-only).
6. `SKILL.md` recovery framing no longer assumes always-blank session context.
7. No Conductor docs instruct sending PID/session_id to Souffleur in context-recovery payload.

---

## Optional Enhancements (Not Required for Basic Compatibility)

- Allow Conductor to omit payload fields and rely on Souffleur defaults when appropriate.
- Add a Conductor example snippet for payload insertion in context-exhaustion flow.
- Document that Souffleur `warning` messages are informational and should not trigger Conductor-side recovery loops by themselves.

---

## Minimal Compatibility SQL Snippet (Copy/Paste)

```sql
-- Step before final context_recovery transition
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES (
    'souffleur',
    'task-00',
    'CONTEXT_RECOVERY_PAYLOAD_V1
permission_mode: acceptEdits
resume_prompt: /conductor --recovery-bootstrap

The session history was cleaned, review handoff documents and resume plan implementation.',
    'instruction'
);

-- Existing kill trigger (must remain last)
UPDATE orchestration_tasks
SET state = 'context_recovery', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```
