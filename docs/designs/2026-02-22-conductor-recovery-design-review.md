# Conductor Recovery & Compaction Design — Comprehensive Review

**Design reviewed:** `2026-02-22-conductor-recovery-design.md`
**Review date:** 2026-02-22
**Review methodology:** 8 parallel review agents with distinct lenses

## Review Panel

| # | Focus | Model | Agent Type |
|---|-------|-------|------------|
| 1 | Broad skill-review — design as Conductor update | Haiku | skill-reviewer |
| 2 | Broad skill-review — design as Conductor update | Opus | skill-reviewer |
| 3 | Compact Protocol integration tracing | Opus | code-reviewer |
| 4 | Recovery Bootstrap Protocol integration tracing | Opus | code-reviewer |
| 5 | Incorrect assumptions — verify claims against source files | Opus | code-reviewer |
| 6 | Skill-as-skill quality — new protocols as LLM instructions | Haiku | skill-reviewer |
| 7 | Skill-as-skill quality — new protocols as LLM instructions | Opus | skill-reviewer |
| 8 | Self-contained completeness — design read in isolation | Opus | code-reviewer |

---

## Factual Accuracy Summary (Agent 5)

41 factual claims verified against source files. **39 accurate, 2 issues found.** The design demonstrates thorough familiarity with the existing skill — section IDs, column names, state values, SQL patterns, file paths, and Souffleur integration points all match reality.

---

## Consensus Positive Findings

The following strengths were identified by 3+ reviewers:

1. **Kill → baseline → watcher → compact → detect → kill → resume sequence** is empirically validated and correctly ordered (Agents 3, 5, 7)
2. **Souffleur integration is bidirectionally consistent** — flag, states, launch prompt, export path all match Souffleur skill files (Agents 2, 3, 4, 5)
3. **"What Doesn't Change" / "What This Protocol Does NOT Do" sections** prevent scope creep during implementation (Agents 1, 2, 6, 7, 8)
4. **Musician Triage table** is crisp, exhaustive, and actionable (Agents 4, 6, 7)
5. **Staged Context Tests** are an innovative pattern not present in existing protocols (Agents 4, 6, 7)
6. **Database schema changes are minimal and additive** — 2 new states, 1 new table (Agents 1, 2, 7)
7. **Learnings file is appropriately lightweight** — append-only, freeform, temp/-scoped (Agents 2, 3, 7)
8. **`context-exhaustion-trigger` ordering** (handoff → MEMORY.md → close Musicians → THEN set `context_recovery`) prevents Souffleur race (Agents 3, 4)
9. **Progressive disclosure** correctly places protocols in reference files, not SKILL.md (Agents 6, 7)
10. **File inventory** is thorough and makes implementation scope clear (Agents 2, 7)

---

## CRITICAL Findings

### C1. Stop hook not listed as modified file — deadlock risk

**Found by:** Agents 2, 3, 4
**Location:** Design file inventory (lines 492-498), error-recovery.md changes (line 378)

The design says `context_recovery` is a terminal state that allows session exit (line 378), but the stop hook at `tools/implementation-hook/stop-hook.sh` is not listed in the modified files. The existing hook only allows exit on `exit_requested` or `complete` (initialization.md lines 276-277, 403).

**Impact:** Without updating the stop hook, the Conductor cannot exit when in `context_recovery` state. The Souffleur waits for the Conductor to die, but the hook blocks session exit. **Result: deadlock** — Conductor wants to die but can't, Souffleur waits forever.

**Resolution needed:** Add `tools/implementation-hook/stop-hook.sh` to the file inventory. Specify the exact change: add `context_recovery` to the set of terminal states for task-00. Consider whether `confirmed` (Souffleur state) also needs to be in the allowlist.

---

### C2. Monitoring queries will include `souffleur` row

**Found by:** Agents 2, 3, 4
**Location:** Design lines 307-315 (souffleur row insertion), phase-execution.md lines 565, 721-724, 767-771, completion.md line 55

The design adds a `souffleur` row to `orchestration_tasks`. Existing monitoring queries use `WHERE task_id != 'task-00'`, which will return the `souffleur` row. Specific affected queries:

- **phase-execution.md "Monitor All Tasks"** (line 721-724): `WHERE task_id != 'task-00'` — returns `souffleur` row
- **phase-execution.md staleness detection** (line 767-771): filters by state, so `souffleur` in `watching` state wouldn't match, but `souffleur` in `error` or `complete` WOULD match
- **phase-execution.md monitoring-cycle step 5.5**: `WHERE task_id != 'task-00' AND state IN ('needs_review', 'error', 'complete', 'exited')` — would return `souffleur` row if it enters `error` or `complete`
- **completion.md verify-all-tasks**: `WHERE task_id != 'task-00'` — returns `souffleur` row

The monitoring watcher could incorrectly detect a state change on the `souffleur` row and exit prematurely, or the Completion Protocol could fail verification because the `souffleur` row is included.

**Resolution needed:** All existing monitoring queries need updating to `WHERE task_id NOT IN ('task-00', 'souffleur')` or `WHERE task_id LIKE 'task-%'`. Add `phase-execution.md` and `completion.md` to the modified files list.

---

### C3. No launch templates for subagents (compact watcher, heartbeat agent)

**Found by:** Agents 1, 6, 7, 8
**Location:** Design lines 87-95 (compact watcher), lines 166-173 (heartbeat agent)

Every existing subagent/teammate in the Conductor skill has a `<template follow="format">` block with an exact Task() invocation and detailed prompt. Examples: monitoring-subagent-template in phase-execution.md (lines 614-637), investigation teammate in error-recovery.md, Copyist teammate in phase-execution.md.

The compact watcher (line 87-95) is described narratively: "Polls JSONL every ~1 second, parsing new lines as JSON from the baseline forward." No launch template, polling logic, JSON parsing details, exit behavior, or timeout handling is provided. The RAG reference (`compact-detection-jsonl-signals.md`) provides signal format but not a subagent prompt.

The heartbeat agent (lines 166-173) is similarly narrative: "Launch a background subagent immediately" with no SQL template, no launch mechanism, no loop timing, and no kill protocol.

**Impact:** An LLM will improvise subagent prompts. This has historically led to failures in the Conductor skill. The existing skill's precision with templates is deliberate — it prevents exactly this kind of improvisation.

**Resolution needed:** Provide `<template follow="format">` blocks for both:
- Compact watcher: launch mechanism (Task tool background?), poll interval, JSON match logic, timeout behavior, exit signaling
- Heartbeat agent: SQL template (`UPDATE orchestration_tasks SET session_id = '...', last_heartbeat = datetime('now') WHERE task_id = 'task-00'`), loop timing (30s), launch mechanism, kill protocol (message-based? PID?)

---

### C4. SKILL.md `repetiteur-protocol` section not in modification list

**Found by:** Agent 2
**Location:** SKILL.md lines 228-247, design file inventory (line 494)

SKILL.md's Repetiteur Protocol section contains multiple statements that directly contradict the proposed externalization:

- Line 232-233: "The Repetiteur operates as a teammate in the same session -- a peer the Conductor can dialogue with, not a fire-and-forget subagent."
- Line 235: "Repetiteur MUST be launched as a teammate with opus 1m context"
- Line 239: "the Conductor relays user input verbatim via SendMessage"

The design proposes making the Repetiteur an external Kitty session communicating via `repetiteur_conversation` table — NOT a teammate, NOT using SendMessage, NOT using Task tool.

The design's file inventory (line 494) lists SKILL.md changes as: "Protocol registry (+2), preamble (`--recovery-bootstrap` bypass), `context_recovery` state docs." It does NOT list updating the `repetiteur-protocol` section's framing text. SKILL.md is the Conductor's first-read document — if it still says "teammate" and "SendMessage," the reference file changes create a first-read contradiction.

**Resolution needed:** Add SKILL.md `repetiteur-protocol` section to the modifications list. Specify which lines need rewriting to reflect external Kitty session + comms-link communication model.

---

### C5. Musician states not set to `exited` before SIGTERM in `context-exhaustion-trigger`

**Found by:** Agent 4
**Location:** Design lines 408-414 (context-exhaustion-trigger)

The `context-exhaustion-trigger` Step 3 says: "Close all external Musician sessions -- SIGTERM via temp/ PID files, remove PID files." But it does NOT first set the Musician task states to a terminal value (`exited`).

The existing stop hook checks whether a task's state is terminal (`complete`, `exited`, or `exit_requested`) before allowing session exit. If a Musician is in `working` or `needs_review` state when SIGTERM arrives, the stop hook will **block exit**. The SIGTERM kills the kitty process, but the Claude Code process inside may not exit cleanly because its hook blocks.

Additionally, a Musician in `needs_review` state is paused waiting for a review that will never come (the Conductor is dying). Its stop hook blocks exit, creating an orphaned process.

**Resolution needed:** The `context-exhaustion-trigger` Step 3 should set all active task states to `exited` BEFORE sending SIGTERM:

```
For each active task:
  1. SET state = 'exited', last_heartbeat = datetime('now') WHERE task_id = '{task_id}'
  2. THEN kill via PID file
  3. THEN rm PID file
```

---

### C6. `context_recovery` vs `exit_requested` relationship undefined

**Found by:** Agent 2
**Location:** Design lines 305, 378; initialization.md lines 273-277

The existing Conductor skill already has a terminal exit state: `exit_requested`, described as "Needs to exit (context full, user consultation)." The design proposes a new `context_recovery` state that serves a nearly identical purpose (Conductor is context-exhausted and preparing to exit).

The design does not explain how `context_recovery` relates to `exit_requested`:
- Is `exit_requested` being replaced by `context_recovery`?
- Do both coexist? If so, what scenario uses `exit_requested` vs `context_recovery`?
- The hook exit criteria are "updated" to include `context_recovery`, but `exit_requested` is not mentioned as removed or modified.

**Resolution needed:** Explicitly document the relationship. Likely answer: `exit_requested` is for user-initiated or non-recovery exits (user consultation needed), while `context_recovery` is specifically for Souffleur-managed recovery. Both coexist with different semantics and different downstream behaviors (exit_requested → session simply exits; context_recovery → Souffleur kills and relaunches).

---

## IMPORTANT Findings

### I1. Compact Protocol Step 7: "same SQL as current clean-handoff" — exact reference needed

**Found by:** Agents 6, 7
**Location:** Design line 131

The design says: "Set `fix_proposed` and send handoff message (same SQL as current clean-handoff procedure)." The existing skill never cross-references SQL by prose description alone — it either provides SQL inline or gives the exact section ID. The phrase "same SQL as current clean-handoff procedure" requires the LLM to know which section that is and reconstruct the SQL.

Should be: "See `musician-lifecycle.md` → `clean-handoff` section (lines 88-119) for exact SQL template" or inline the SQL.

---

### I2. Message-watcher down during compaction violates mandatory rule

**Found by:** Agent 3
**Location:** Design lines 86-113 (Compact Protocol Steps 3-5), SKILL.md line 85

SKILL.md mandatory rule: "Background message-watcher MUST be running at all times during execution." During Compact Protocol Steps 3-5, only the compact watcher runs — the message-watcher is NOT running. Events from other Musicians (state changes to `error`, `needs_review`, `complete`, `exited`) will be missed.

The compact operation takes 90-97 seconds (per RAG entry) to ~5 minutes (design timeout). During this window, other Musicians' events are invisible to the Conductor.

**Options:**
1. Acknowledge the message-watcher is temporarily down and justify (MEMORY.md event queue handles missed events)
2. Launch message-watcher in parallel with compact watcher (cleanest — no reason both can't coexist)
3. Add a step to refresh Conductor heartbeat during the compact wait period

Agent 3 recommends Option 2.

---

### I3. Repetiteur communication protocol unspecified

**Found by:** Agents 1, 6, 7, 8
**Location:** Design lines 319-325 (repetiteur_conversation table), lines 419-438 (externalization changes)

The `repetiteur_conversation` table schema is given (sender, message, timestamp), but the actual communication protocol is missing:

- What values does `sender` field contain? (`"conductor"`, `"repetiteur"`, `"user"`?)
- How does either side know a message is "for them" vs already processed? No `read`/`acknowledged` column.
- How does the Conductor know the Repetiteur has finished its response? Sentinel message? State transition?
- What is the message format? Free text? JSON? Structured?
- Polling interval and timeout?
- How does the Conductor relay user input? (Currently via SendMessage passthrough)

Compare the existing `consultation-communication` section (musician-lifecycle.md lines 209-235) which fully documents the SendMessage interaction pattern. The replacement needs equal specificity.

The design says the Repetiteur skill itself needs separate updates (line 442), but the Conductor side of the protocol still needs to be specified.

---

### I4. Recovery Bootstrap Steps 4/5 ordering tension

**Found by:** Agents 4, 7
**Location:** Design lines 198-227

Stage 2 of the Staged Context Tests (Step 4) asks: "Can you state the current phase number?" and "Can you identify which tasks are active, completed, and pending?" But the database query that provides this information is in Step 5 (`SELECT * FROM orchestration_tasks WHERE task_id != 'souffleur'`).

The design resolves this by having the Conductor use export file + handoff (Steps 1-2) to answer Stage 2, with database as fallback. But if the export is truncated and no handoff exists (crash), the Conductor can't answer Stage 2 until Step 5.

**Options:**
1. Reorder Steps 4 and 5 (state reconstruction before context tests)
2. Explicitly note that Stage 2 may trigger an early database query and that's acceptable
3. Split Step 4 — Stage 1 before Step 5, Stages 2-3 after Step 5

---

### I5. Handoff document format and filename unspecified

**Found by:** Agents 4, 8
**Location:** Design lines 181-185 (read), 407-411 (write)

The design references `temp/HANDOFFS/Conductor/` as both a write target and read source but never specifies:

- **Filename convention:** Single file overwritten each time? Session-ID-based? Timestamped?
- **Document format:** Markdown? YAML? Plain text? Structured sections?
- **Content structure:** The design lists "current phase, active tasks, pending events, notes" but no parsing specification
- **Discovery:** If multiple files exist, which does the Recovery Bootstrap read?

The existing Musician handoff pattern uses `temp/task-NN-HANDOFF` (flat file, deterministic name). The Conductor handoff pattern should follow a similar convention.

**Suggestion from Agent 4:** Use `temp/HANDOFFS/Conductor/handoff.md` (single file, overwritten) for simplicity, or document why the subdirectory approach was chosen.

---

### I6. Compact watcher timeout — no failure recovery

**Found by:** Agents 3, 6, 7
**Location:** Design line 93 (timeout ~5 minutes)

Step 3 mentions "Timeout: ~5 minutes" but Step 5 assumes the watcher reports completion. No specification for what happens when:

- The compact command fails or hangs
- The `compact_boundary` signal never appears
- The compact session crashes mid-operation
- The JSONL file is malformed

The existing skill handles every failure path explicitly. The `subagent-failure-handling` in error-recovery.md (lines 233-365) has a complete retry and escalation flow.

**Resolution needed:** Add timeout handling: "If watcher times out without detecting `compact_boundary`: check PID status. If alive: force kill. If dead: check JSONL for signal (may have been missed). If no signal found: treat as compact failure, fall back to fresh session launch."

---

### I7. High-context verification after compaction ambiguity

**Found by:** Agent 3
**Location:** Design line 145 ("What Doesn't Change")

The existing `high-context-verification` rule (musician-lifecycle.md lines 422-436) mandates re-running all verification tests when context exceeds 80%. The design lists this rule as unchanged (line 145).

But after compaction and resume, the session has LOW context (post-compact). The work done at HIGH context still happened — code written during the high-context period persists in the codebase. The compacted session retains a context summary but NOT its full reasoning chain. Hallucinated code from the high-context period persists even though the session's context was trimmed.

**Question:** Should the resumed session re-verify pre-compact work? Should the Conductor instruct the resumed session to re-run tests in its continuation prompt (analogous to dirty handoff test instructions)?

---

### I8. Adversarial validation teammates underspecified

**Found by:** Agents 1, 4, 6, 7, 8
**Location:** Design lines 248-259

This is the most frequently flagged issue across all reviewers. The design describes launching "2 read-only validation teammates" but provides:

- No prompt templates (existing skill has detailed templates for every teammate/subagent)
- No specific files each teammate should read
- No expected output format (JSON? prose? structured findings?)
- No synthesis logic (how does the Conductor combine findings from both?)
- No time budget or context budget
- No timeout handling
- No "read-only" enforcement mechanism
- No specification for what happens if one finds issues but the other doesn't
- No launch mechanism (Task tool as teammates? Subagents?)

Compare the monitoring-subagent-template in phase-execution.md (lines 614-637), which provides a complete, copy-pasteable template.

**Additional concern from Agent 4:** Two teammates reading all task instructions and work output for the current phase will consume substantial context in the new Conductor's session — the session that was launched precisely because its predecessor ran out of context.

---

### I9. `phase-execution.md` and `completion.md` not listed as modified files

**Found by:** Agents 2, 3
**Location:** Design file inventory (lines 492-498)

Beyond the `souffleur` row exclusion (C2), these files are affected by:

- **phase-execution.md:** Learnings file touchpoint guidance ("consider recording" at phase transitions), monitoring query updates for `souffleur` exclusion, potential Sentinel interaction during compaction
- **completion.md:** Must handle the Souffleur row (close Souffleur session? Exclude from verification?), learnings file archival decision
- **review-protocol.md:** Learnings file touchpoint (design's touchpoint table line 474 lists it as a write point)

The design's "Learnings File Touchpoints" table (lines 469-477) mentions adding guidance to the Review Protocol and Phase Execution Protocol, but the file inventory doesn't list these as modified files.

---

### I10. Export file parsing expectations underspecified for Recovery Bootstrap Step 1

**Found by:** Agents 7, 8
**Location:** Design lines 176-177

The design says: "Read the export file at the path provided in the Souffleur's launch prompt. This is a trimmed conversation transcript from the predecessor."

Missing:
- Where is the path in the launch prompt? Parameter name/position?
- What format is the export? (The Souffleur's conductor-relaunch.md says "clean markdown with 'Files Modified' summary at the top")
- What should the Conductor extract from the export?
- What if the export is truncated (>800k chars per Souffleur Step 3)?
- What if the path is invalid or the file is empty?
- Handling: if the export is truncated, project goals and docs structure discussion from early in the session are gone, but Stage 1 tests ask about these

**Resolution needed:** At minimum, specify: the path is provided via `{EXPORT_PATH}` substitution in the launch prompt, the format is markdown, and if truncated, supplement with the same fallback files used in the crash path.

---

## SUGGESTION Findings

### S1. Sentinel false positive during compaction

**Found by:** Agent 3
**Location:** sentinel-monitoring.md anomaly criterion 4

The Sentinel's "stalled progress" anomaly fires when `temp/task-{NN}-status` has no new entries for >5 minutes. During compaction (90s to ~5min), the Musician session is dead/compacting — no status file updates. If compaction approaches or exceeds 5 minutes, the Sentinel reports a false positive.

**Suggestion:** Add guidance for the Conductor to suppress or ignore Sentinel stall reports for tasks currently undergoing compaction, or inform the Sentinel via SendMessage that task-XX is being compacted.

---

### S2. Compact Protocol trigger list is indirect, not direct

**Found by:** Agent 3
**Location:** Design lines 55-57

The trigger list says `error-recovery.md context-warning-protocol` is a trigger for the Compact Protocol. But the actual routing is indirect: `context-warning-protocol` → Musician gets `review_failed` → Musician writes HANDOFF and sets `exited` → monitoring watcher detects `exited` → event-routing → Musician Lifecycle Protocol → `context-exhaustion-flow` → Compact Protocol.

Only `musician-lifecycle.md context-exhaustion-flow` is a direct trigger. Listing the indirect path could cause implementers to add a direct jump from error-recovery to Compact Protocol, bypassing the Musician's exit sequence.

**Suggestion:** Distinguish direct routing (lifecycle protocol) from indirect routing (error recovery eventually leads there via Musician exit flow).

---

### S3. Defensive `kill -0` before `kill` in Compact Protocol steps

**Found by:** Agent 3
**Location:** Design lines 73-76, 109-112

The compact protocol uses raw `kill $PID` in Steps 1 and 5 without checking `kill -0 $PID` first. The existing `stale-heartbeat-recovery` in error-recovery.md (lines 146-151) defensively checks PID status before killing.

If the compact session already exited on its own (Step 5), the PID might have been reused by another process. Using `kill -0 $PID 2>/dev/null && kill $PID` prevents killing the wrong process.

---

### S4. Learnings file creation/rotation policy unspecified

**Found by:** Agents 1, 8
**Location:** Design lines 456-477

Missing:
- When is the file created? (Lazy on first write? During initialization?)
- What if it doesn't exist during Recovery Bootstrap Step 3? (First Conductor generation)
- Does it rotate or truncate? (Could grow large during long orchestrations)
- Is there an archival step during Completion Protocol? (Design says "permanent knowledge goes to RAG/memory graph via proposals" but no Completion Protocol touchpoint exists)

The file is in `temp/` so it's session-scoped and cleared on reboot. But what if an orchestration spans days without reboot?

**Suggestion:** Lazy creation (append creates if not exists), no rotation (temp/ handles cleanup), no archival (learnings that matter get proposed to RAG manually). But document this explicitly.

---

### S5. Recovery Bootstrap context cost of adversarial validation

**Found by:** Agent 4
**Location:** Design lines 248-259

The Recovery Bootstrap launches 2 teammates that read all task instructions and work output for the current phase, then report findings. This consumes substantial context in the new Conductor's session — the session that was launched precisely because its predecessor ran out of context.

For small remaining phases, the adversarial validation could potentially be simplified or skipped to conserve context.

**Suggestion:** Add context-budget awareness: "If remaining phase has <3 tasks, simplify to a single teammate reviewing recent work only."

---

### S6. `worked_by` increment justification for resumed (same) sessions

**Found by:** Agents 2, 8
**Location:** Design line 117

The design says `worked_by` succession "increments normally (S2, S3, etc.)" after compact + resume. But the Compact Protocol resumes the same session via `--resume`. The `worked_by` succession pattern (musician-lifecycle.md lines 284-302) is designed for new sessions taking over.

The design should explicitly justify: increment even on resume to track compaction events — each compaction represents a meaningful context boundary even though the session ID is preserved.

---

### S7. Heartbeat cadence change from 30s to 60s at Step 10

**Found by:** Agent 4
**Location:** Design lines 166-173 (heartbeat agent at 30s), phase-execution.md line 588-591 (monitoring watcher at 60s)

When the heartbeat agent is killed (Step 10) and the message watcher takes over, the heartbeat cadence changes from 30s to 60s. The Souffleur watcher's staleness threshold is 240s.

Both cadences are well within tolerance. The 30s cadence during bootstrap provides extra safety margin during the vulnerable recovery period.

**Suggestion:** Add a brief note documenting this intentional cadence change and confirming both are within the 240s threshold.

---

### S8. `/compact` is a built-in CLI command — note this for clarity

**Found by:** Agents 6, 8
**Location:** Design line 102

The Compact Protocol Step 4 uses `--resume $SESSION_ID "/compact"`. The `/compact` is a built-in Claude Code command that triggers context compaction. The protocol assumes readers know this. For a skill reference file, this should be explicitly noted as a built-in command (not a skill invocation, not a custom protocol).

---

### S9. Compact Protocol: `fix_proposed` + guard clause interaction for resumed sessions

**Found by:** Agent 2
**Location:** Design line 131

The Compact Protocol uses `fix_proposed` state (via clean-handoff procedure) and says "the resumed session claims the task via the existing guard clause." But the resumed session has the same session ID (via `--resume`). The guard clause in `guard-clause-reclaiming` (musician-lifecycle.md lines 310-324) requires writing a new `session_id`.

If `--resume` preserves the same session ID, the `session_id = '$CLAUDE_SESSION_ID'` assignment in the guard clause is a no-op. The WHERE clause still matches (`state IN ('watching', 'fix_proposed', 'exit_requested')`), so the claim succeeds. But the design should clarify whether `session_id` changes on `--resume`.

---

### S10. Recovery Bootstrap Step 5 query excludes `souffleur` but not `task-00`

**Found by:** Agent 5
**Location:** Design line 225

The query `SELECT * FROM orchestration_tasks WHERE task_id != 'souffleur'` will return the Conductor's own `task-00` row mixed in with Musician task rows. All existing monitoring queries use `WHERE task_id != 'task-00'`. The correct filter should be `WHERE task_id NOT IN ('task-00', 'souffleur')`.

---

### S11. `confirmed` and `context_recovery` states are not truly "new"

**Found by:** Agent 5
**Location:** Design lines 294-305

The Souffleur skill (v1.1) already uses both states:
- `confirmed`: bootstrap-validation.md line 77, database-queries.md line 38
- `context_recovery`: monitoring-architecture.md line 77, subagent-prompts.md line 53

The design presents them as new additions to the CHECK constraint, which is correct for the DDL, but does not acknowledge that the Souffleur already depends on these states. The current CHECK constraint would **violate at runtime** if the Souffleur were actually deployed. This is a retroactive DDL alignment, not just a forward-looking addition.

---

### S12. PID file naming inconsistency for Repetiteur

**Found by:** Agent 2
**Location:** Design line 430

The design introduces `temp/repetiteur.pid`. Existing patterns: `temp/musician-task-XX.pid`, `temp/souffleur-conductor.pid`. Three different naming conventions. Not wrong, but the design should acknowledge the divergence or propose a unified convention.

---

### S13. Compact Protocol assumes HANDOFF already exists

**Found by:** Agent 2
**Location:** Design line 63

The prerequisites say "A HANDOFF document written by the session." But if a Musician hits context exhaustion mid-work before writing a HANDOFF, the prerequisite is not met. The existing skill handles this via the crash-handoff procedure.

The design should specify what happens if compaction is triggered but no HANDOFF exists — likely: proceed with compaction anyway (the session context is preserved via `--resume`, so HANDOFF is less critical than in the fresh-session approach).

---

### S14. Compact Protocol applicability to Repetiteur needs generalization

**Found by:** Agent 3
**Location:** Design line 441

The design says the Repetiteur "can be compacted via Compact Protocol when it hits context exhaustion." But the Compact Protocol references `temp/musician-task-XX.pid` and `orchestration_tasks.session_id` throughout — neither of which exist for the externalized Repetiteur.

The Repetiteur's PID is at `temp/repetiteur.pid`, and it has no row in `orchestration_tasks` (no database tracking). The Compact Protocol would need Repetiteur-specific handling for PID file path and session ID source.

---

### S15. Souffleur row state lifecycle — `confirmed` → `watching` transition undefined

**Found by:** Agent 2
**Location:** Design lines 373-376

The design shows: `watching -> confirmed -> watching -> ... -> complete`. But neither the design nor the Souffleur skill implements a `confirmed -> watching` transition. The Souffleur's watcher updates heartbeat but not state after `confirmed`. The row appears to stay `confirmed` permanently unless something sets it back.

The design should clarify whether this is intentional (row stays `confirmed`, heartbeat is the only changing field) or whether the Souffleur should transition back to `watching`.

---

### S16. `temp/` ephemerality risk for handoff documents

**Found by:** Agent 4
**Location:** Design lines 407-411

Handoff documents live in `temp/` which is symlinked to `/tmp/remindly/` and cleared on reboot. If the system reboots between the old Conductor dying and the new one bootstrapping (unlikely but possible during a crash), the handoff is lost. The crash path already handles missing handoffs, so this degrades gracefully. But for planned context recovery, losing the handoff degrades recovery to crash-quality.

**Suggestion:** Document as a known limitation.

---

### S17. Recovery Bootstrap orphaned Repetiteur not handled

**Found by:** Agent 4
**Location:** Design lines 228-239

Step 6 (Musician Triage) triages Musicians but does not check for an active Repetiteur session. If the Repetiteur was active when the old Conductor died, the externalized Repetiteur session may be orphaned. The Recovery Bootstrap should check `temp/repetiteur.pid` and the `repetiteur_conversation` table as part of Step 5 or Step 6.

---

### S18. Context-warning-protocol "minor guidance update" characterization

**Found by:** Agent 5
**Location:** Design line 415

The design says the update to `context-warning-protocol` is "minor guidance." But it adds Conductor self-monitoring to a section that currently only handles Musician context warnings. This is an addition of a new concern, not a modification of existing handling. Calling it "minor" may cause implementers to underestimate scope.

---

### S19. Souffleur "In development" status misleading

**Found by:** Agent 5
**Location:** Design line 513

The Souffleur has a complete SKILL.md (v1.1) and 6 reference files. It is in `skills_staged/` (not deployed). "In development" should be clarified to mean "staged but not deployed."

---

### S20. Recovery Bootstrap Step 2 crash fallback creates MEMORY.md dependency before Step 5

**Found by:** Agent 7
**Location:** Design lines 183-193

The crash fallback path reads the implementation plan "via MEMORY.md plan path." But MEMORY.md is formally loaded in Step 5. If the Conductor reads MEMORY.md in Step 2 to find the plan path, then Step 5's MEMORY.md read is redundant. Either acknowledge the early read or restructure.

---

### S21. Staged Context Tests are self-assessed with no enforcement

**Found by:** Agents 6, 7
**Location:** Design lines 200-215

The tests ask "Can you state the project's goal(s)?" — these are purely self-assessed. The existing skill uses concrete verification (PRAGMA table_info, script outputs, database queries). Self-assessment is valuable but Stage 3 has no "if fails" clause at all. What does the Conductor do if it cannot pass Stage 3? Exit? Escalate? Proceed anyway?

---

### S22. Recovery Bootstrap Step 9 corrective action is vague

**Found by:** Agents 1, 6, 8
**Location:** Design lines 261-268

"If work is unusable: git rollback of affected commits, re-queue tasks" — extremely high-level for a destructive operation. No specification for:
- Which git command? (`git revert`? `git reset --hard`?)
- How to determine which commits are "affected"?
- How does "re-queue tasks" work as a database state transition?
- What's the threshold between "Conductor fixes directly" (small) vs "delegates to teammate" (large)?

Compare error-recovery.md's error classification (lines 55-68) which has explicit categories with clear indicators.

---

### S23. SKILL.md preamble bypass mechanism needs exact wording

**Found by:** Agents 2, 4
**Location:** Design line 161

The conditional branch for `--recovery-bootstrap` is described but not specified precisely. The current preamble (SKILL.md line 52) says unconditionally: "After loading this skill, proceed immediately to the Initialization Protocol." Since the Conductor is an LLM interpreting these instructions, the phrasing of the conditional matters. The design should provide exact replacement text.

---

### S24. Compact Protocol: SESSION_ID variable source needs explicit SQL

**Found by:** Agents 7, 8
**Location:** Design line 80-81

`SENTINEL=~/.claude/projects/-home-kyle-claude-remindly/${SESSION_ID}.jsonl` — where does `SESSION_ID` come from? The prerequisite says "from `orchestration_tasks.session_id`" but no SQL query is provided. An LLM might use `$CLAUDE_SESSION_ID` (the Conductor's own session ID, which is wrong — this is the child session's ID).

The existing skill shows exact SELECT queries for data retrieval. Include:
```sql
SELECT session_id FROM orchestration_tasks WHERE task_id = '{task-id}';
```

---

### S25. No mention of Conductor self-detection mechanism for context exhaustion

**Found by:** Agents 2, 7
**Location:** Design lines 404-416

The design specifies the Conductor's pre-death sequence (context-exhaustion-trigger) but never specifies HOW the Conductor detects its own context exhaustion. The Musician skill has context monitoring with percentage tracking. The Conductor currently has no equivalent mechanism.

---

## Self-Contained Completeness Gaps (Agent 8)

Agent 8 read ONLY the design document (no other files) and reported what couldn't be produced from the design alone. These are organized by severity with the understanding that many are expected false positives (clear with context but unclear in isolation).

### Gaps that are genuine (confirmed by other agents)

These overlap with findings above and validate them:
- Compact watcher implementation absent (= C3)
- Adversarial validation teammate mechanics (= I8)
- Git rollback mechanics in Step 9 (= S22)
- Repetiteur communication protocol (= I3)
- Souffleur hard gate error recovery loop (= partially in C1/C6)
- Handoff document format (= I5)

### Gaps that are acceptable external references

These are things the design intentionally delegates to existing files:
- `worked_by` succession pattern — defined in musician-lifecycle.md
- Message watcher launch/exit protocol — defined in SKILL.md and phase-execution.md
- Clean-handoff SQL — defined in musician-lifecycle.md (though I1 says it should be referenced more precisely)
- Hook verification specifics — defined in initialization.md
- `scripts/check-git-branch.sh` behavior — existing script
- `env -u CLAUDECODE` purpose — established convention

### Gaps worth noting

- `$SESSION_ID` vs `$CLAUDE_SESSION_ID` distinction not explicitly called out (S24)
- `--permission-mode acceptEdits` asymmetry between compact launch and resume launch — intentional but unexplained
- Learnings file "when to write" guidance text not provided — touchpoints table says "consider recording" but actual wording is absent
- `temp/HANDOFFS/Conductor/` — directory vs file ambiguity (I5)
- Recovery Bootstrap Step 2 plan reading: "plan-index, Overview, Phase Summary" — paths and structure are external knowledge

---

## Implementation Readiness Assessment

| Component | Readiness | Blocking Issues |
|-----------|-----------|-----------------|
| Compact Protocol | 70% | C3 (templates), I1 (SQL ref), I2 (watcher down), I6 (timeout) |
| Recovery Bootstrap Protocol | 55% | C3 (templates), C5 (SIGTERM ordering), I4 (step order), I5 (handoff format), I8 (teammates) |
| Initialization Changes | 80% | C1 (stop hook), C2 (souffleur row queries) |
| musician-lifecycle.md Changes | 90% | I1 (SQL ref), I7 (high-context verification) |
| error-recovery.md Changes | 70% | C6 (state relationship), S25 (self-detection) |
| repetiteur-invocation.md Changes | 40% | C4 (SKILL.md section), I3 (communication protocol) |
| Learnings File | 85% | S4 (creation policy) |
| Cross-skill Dependencies | 75% | C2 (query updates), I9 (file inventory) |

---

## Appendix: Finding Cross-Reference Matrix

Shows which agents found each issue (confirms findings are independently validated):

| Finding | Agent 1 | Agent 2 | Agent 3 | Agent 4 | Agent 5 | Agent 6 | Agent 7 | Agent 8 |
|---------|---------|---------|---------|---------|---------|---------|---------|---------|
| C1. Stop hook deadlock | | X | X | X | | | | |
| C2. Souffleur row in queries | | X | X | X | | | | |
| C3. Missing launch templates | X | | | | | X | X | X |
| C4. SKILL.md repetiteur section | | X | | | | | | |
| C5. SIGTERM without state change | | | | X | | | | |
| C6. context_recovery vs exit_requested | | X | | | | | | |
| I1. SQL ref for clean-handoff | | | | | | X | X | |
| I2. Message-watcher down | | | X | | | | | |
| I3. Repetiteur communication | X | | | | | X | X | X |
| I4. Steps 4/5 ordering | | | | X | | | X | |
| I5. Handoff format/filename | | | | X | | | | X |
| I6. Watcher timeout handling | | | X | | | X | X | |
| I7. High-context after compact | | | X | | | | | |
| I8. Adversarial teammates | X | | | X | | X | X | X |
| I9. Unlisted modified files | | X | X | | | | | |
| I10. Export file expectations | | | | | | | X | X |
| S10. Step 5 query filter | | | | | X | | | |
| S11. States are retroactive DDL | | | | | X | | | |

---

## Resolutions

Decisions made during review discussion. These inform the design revision.

### Simple Edits (no context change — apply directly)

- **C1:** Add `tools/implementation-hook/stop-hook.sh` to file inventory. Add `context_recovery` to terminal states.
- **C2:** Update all monitoring queries to `WHERE task_id NOT IN ('task-00', 'souffleur')` or `WHERE task_id LIKE 'task-%'`. Add `phase-execution.md` and `completion.md` to modified files.
- **C4:** Add SKILL.md `repetiteur-protocol` section to modification list.
- **C6:** Add scope distinction: `exit_requested` = Conductor→Musician signal, `context_recovery` = Conductor→Souffleur signal. Both coexist.
- **I1:** Replace "same SQL as current clean-handoff procedure" with exact section reference: `musician-lifecycle.md` → `clean-handoff` section.
- **I9:** Add `phase-execution.md`, `completion.md`, `review-protocol.md` to modified files list.
- **S10:** Fix Recovery Bootstrap Step 5 query to `WHERE task_id NOT IN ('task-00', 'souffleur')`.
- **S11:** Add note that `confirmed`/`context_recovery` are retroactive DDL alignment — Souffleur already depends on these states.
- **S12:** Acknowledge PID naming divergence (`musician-task-XX.pid`, `souffleur-conductor.pid`, `repetiteur.pid`).
- **S18:** Reword "minor guidance update" to "addition of Conductor self-monitoring concern."
- **S19:** Clarify Souffleur status: "staged but not deployed" instead of "In development."
- **S24:** Add explicit SQL: `SELECT session_id FROM orchestration_tasks WHERE task_id = '{task-id}';`

### Context Changes — Resolved

**C3: Missing launch templates (compact watcher, heartbeat agent)**

The design should specify mechanism and key parameters. Full `<template>` blocks are deferred to the reference files during implementation.

**Compact watcher parameters:**
- Type: Background Task subagent
- Inputs: JSONL path, baseline line count
- Behavior: Poll every 1s, read lines > baseline, parse as JSON, match `{"type": "system", "subtype": "compact_boundary"}` field-by-field
- Timeout: 5 minutes from launch → treat as compact failure, fall back to fresh session launch
- Malformed JSON: skip line, continue
- On detection: INSERT completion message into `orchestration_messages` (task_id, message='compact_complete', type='system'), then exit
- Conductor polls comms-link for that message

**Heartbeat agent parameters:**
- Type: Background Task subagent
- Immediate action: UPDATE task-00 `session_id` and `last_heartbeat`
- SQL: `UPDATE orchestration_tasks SET session_id = '{SESSION_ID}', last_heartbeat = datetime('now') WHERE task_id = 'task-00';`
- Loop: refresh `last_heartbeat` every 30s
- Kill protocol: Conductor INSERTs `heartbeat_agent_shutdown` message into `orchestration_messages`. Agent polls for this message each loop iteration and exits when found.
- Error handling: UPDATE failure → log, continue looping (transient)

---

**C5: Musician states not set to `exited` before SIGTERM**

The `context-exhaustion-trigger` Step 3 must set all active task states to `exited` BEFORE sending SIGTERM:

```
For each active Musician task:
  1. UPDATE state = 'exited' WHERE task_id = '{task_id}'
  2. kill $(cat temp/musician-{task_id}.pid)
  3. rm temp/musician-{task_id}.pid
```

---

**I2: Message-watcher stays running during compaction**

Message-watcher continues running during Compact Protocol. Compact watcher runs alongside it as a second background subagent. If the message-watcher exits during compaction (detects state change from another Musician), handle via normal Message-Watcher Exit Protocol, relaunch watcher, continue waiting for compact watcher completion.

---

**I3: Repetiteur communication protocol**

- `sender` values: `'conductor'`, `'repetiteur'`, `'user'` (user input relayed by Conductor)
- New message detection: each side tracks its last-read `id`. Poll with `WHERE id > $LAST_READ_ID AND sender != $SELF ORDER BY id`
- Polling interval: ~3 seconds during active consultation
- Conversation end signal: Repetiteur inserts a message with `[HANDOFF]` prefix, same as current SendMessage handoff pattern
- Message format: free text, same as current SendMessage content

---

**I4: Steps 4/5 ordering tension**

No reorder. Add note to Step 4: "Stage 2 may require querying comms-link before Step 5's formal state reconstruction. This is expected — Stage 2 tests whether you can orient from the export and handoff alone, with database queries as the fallback that confirms you need Step 5's full reconstruction."

---

**I5: Handoff document format/filename**

`temp/HANDOFFS/Conductor/handoff.md` — single file, overwritten each time. Freeform markdown, not structured for parsing. Content is whatever the dying Conductor considers useful: current phase, active tasks, pending events, in-progress decisions, notes.

---

**I6: Compact watcher timeout failure recovery**

Full failure path:
1. Watcher times out (5 min) without detecting `compact_boundary`
2. Conductor checks compact session PID — alive or dead?
3. If alive: kill it (compact hung)
4. If dead: scan JSONL from baseline forward one final time (signal may have been written just before timeout)
5. If signal found in final scan: proceed normally (resume session)
6. If no signal: compact failed — fall back to existing fresh-session-with-HANDOFF launch. Log to learnings file.

---

**I7: High-context verification after compaction — FALSE POSITIVE**

Not a real issue. The existing review pipeline already catches bad work from high-context sessions. The Conductor reviews Musician output regardless of whether the session was compacted. For the Conductor's own compaction, the Recovery Bootstrap has adversarial validation (Step 8) baked in.

---

**I8: Adversarial validation teammates**

- Launch: Task tool, 2 parallel teammates, Opus
- Teammate A: Recent task work — read task instruction file + work output (report, git diff, test results) for most recently completed/active task(s). Prose summary of deviations, errors, incomplete steps.
- Teammate B: Phase coherence — read all task instructions for current phase + completion states from DB. Prose summary of integration issues, conflicts, sequencing problems.
- Timeout: 5 minutes each
- Output: Both report prose findings to Conductor. All findings feed Step 9.
- Context cost mitigation: If current phase has ≤2 tasks, collapse to single teammate covering both scopes.

---

**I10: Export file parsing expectations**

- Path source: `{EXPORT_PATH}` substitution in the Souffleur's launch prompt
- Format: Markdown (clean markdown with "Files Modified" summary at top, per Souffleur conductor-relaunch.md)
- Truncation behavior: Souffleur preserves "Files Modified" summary at top PLUS most recent ~800k chars. Middle of conversation is cut, not the head or tail. Conductor always gets file inventory + recent work.
- What to extract: read as context — don't parse, just absorb
- If truncated and Stage 1 fails: supplement with crash-path fallback files (plan overview, docs READMEs)
- If path invalid or file empty: treat as crash scenario, proceed to Step 2 fallback reads

---

**S1: Sentinel false positive during compaction**

If the Sentinel reports a stall for a task currently undergoing compaction: relaunch the message-watcher per the Message-Watcher Exit Protocol (the watcher exited to deliver the Sentinel report), then discard the Sentinel finding — the session is intentionally down.

---

**S2: Compact Protocol trigger list (direct vs indirect)**

Reword trigger list. Direct trigger: `musician-lifecycle.md context-exhaustion-flow`. Indirect path: `error-recovery.md context-warning-protocol` eventually leads there via the Musician's exit flow. Prevents implementers from adding a shortcut jump.

---

**S4: Learnings file creation/rotation policy**

Lazy creation — append creates the file if it doesn't exist. No rotation — `temp/` handles cleanup on reboot. If file doesn't exist during Recovery Bootstrap Step 3, note "first generation" and continue. No archival step.

---

**S5: Context cost of adversarial validation**

Not an additional issue. The teammates bear the context cost in their own windows — the Conductor only receives prose finding summaries. Already mitigated by the I8 collapse rule (≤2 tasks → single teammate).

---

**S6: `worked_by` increment justification**

Add note: "`worked_by` increments on compact resume to track compaction boundaries. Each compaction is a new generation even though the session ID is preserved via `--resume`."

---

**S8: `/compact` is a built-in CLI command**

Add note: "`/compact` is a built-in Claude Code command that triggers context compaction within the session. It is not a skill invocation."

---

**S9: `fix_proposed` + guard clause for resumed sessions**

`--resume` preserves the same session ID. The guard clause claim transitions the state from `fix_proposed` to `working` — the `session_id` assignment is a no-op. `worked_by` increments to track the compaction boundary. No ambiguity to document.

---

**S13: Compact Protocol when no HANDOFF exists**

Soften the prerequisite: "A HANDOFF document written by the session (if one exists). The Compact Protocol preserves session context via `--resume`, so a missing HANDOFF is not blocking — the resumed session retains its own context of the work in progress."

---

**S14: Compact Protocol applicability to Repetiteur**

Add note: "The Compact Protocol as specified targets Musicians. Repetiteur compaction follows the same sequence but uses `temp/repetiteur.pid` for PID and tracks session ID via Conductor state (no database row). Detailed Repetiteur variant is scoped to the Repetiteur externalization workstream."

---

**S15: Souffleur `confirmed` → `watching` transition**

Fix the lifecycle diagram. Remove the `confirmed -> watching` transition. Actual lifecycle: `watching -> confirmed -> complete` (or `watching -> error -> [retry] -> confirmed -> complete`, or `watching -> error x3 -> exited`). The row stays `confirmed` for the duration of normal operations.

---

**S16: `temp/` ephemerality risk for handoffs — DROPPED**

No edit needed. The crash path handles missing handoffs by design.

---

**S17: Orphaned Repetiteur during recovery**

Add to Recovery Bootstrap Step 6 triage: "Check `temp/repetiteur.pid`. If exists: check PID liveness. If alive: kill it (Repetiteur cannot continue without a Conductor to communicate with). Remove PID file. Re-invoke later if needed."

---

**S20: Step 2 crash fallback MEMORY.md dependency**

Add note to Step 2: "Read MEMORY.md now for the plan path. Step 5 revisits MEMORY.md for broader state reconstruction."

---

**S21: Staged Context Tests Stage 3 failure**

Add Stage 3 failure clause: "If fails: re-read SKILL.md Protocol Registry and Phase Execution Protocol reference. If still unable to articulate the loop: halt and report to user — recovery session may be corrupted."

---

**S22: Corrective action specifics (Step 9)**

- Git rollback: `git revert` (not `git reset --hard`) — reversible, preserves history
- Re-queue: SET state back to `watching`, clear `session_id` and `worked_by`
- Small vs large threshold: single file with obvious correction → Conductor fixes directly. Multiple files or design decisions → delegate to teammate.
- If work is sound: proceed to Step 10, no action needed.

---

**S23: SKILL.md preamble exact wording**

Proposed replacement: "After loading this skill: if your invocation includes `--recovery-bootstrap`, proceed directly to the Recovery Bootstrap Protocol (skip Initialization Protocol entirely). Otherwise, proceed to the Initialization Protocol."

---

**S25: Conductor self-detection mechanism for context exhaustion**

The Conductor detects its own context exhaustion via the same platform-level context warnings that Musicians receive. No custom monitoring infrastructure is needed — Claude Code surfaces context usage warnings naturally. When the Conductor observes it is approaching context limits, it enters the `context-exhaustion-trigger` sequence.

### All Findings Resolved
