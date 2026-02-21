# Conductor Skill Overhaul — Design Document

**Date:** 2026-02-19
**Status:** Design Complete
**Type:** Skill Redesign
**Scope:** Full Conductor skill update for pipeline integration, autonomous operation, and protocol-dispatching architecture

---

## 1. Problem Statement

The Conductor skill was designed for a simpler pipeline: read a plain markdown implementation plan, create task instructions via Copyist subagent, launch Musicians, monitor via database, and interact with the user throughout. Three foundational changes invalidate this model:

1. **New pipeline skills.** The Arranger produces structured implementation plans with sentinel markers, line-range indexes, and dual-audience sections. The Repetiteur provides autonomous mid-implementation re-planning when blockers exceed the Conductor's authority. The Conductor must consume these new formats and integrate with these new skills.

2. **Autonomous operation.** The Conductor becomes fully autonomous after bootstrap user approval. The user drops out of the error-handling loop entirely — the escalation chain is Conductor → Repetiteur → User (only for vision-level deviations).

3. **Skill file scale.** The Conductor's SKILL.md is 454 lines and growing. With new responsibilities (Repetiteur integration, Musician lifecycle management, sentinel monitoring, Arranger plan consumption), a monolithic SKILL.md causes context overload — rules placed far from execution points get forgotten.

---

## 2. Protocol-Dispatching Architecture

### Core Concept

SKILL.md becomes a **protocol dispatcher** (~200-300 lines). Reference files become **protocol implementations**. Each reference file owns one workflow and contains all templates, SQL, and commands needed for that workflow. SQL lives where it's used, not in a centralized query file.

This architecture was validated through two rounds of Gemini analysis. The key insight: SKILL.md provides the "what and when" (routing, constraints, context), reference files provide the "how" (procedures, templates). The Conductor loads SKILL.md fully at startup, then loads reference files on-demand as it enters each protocol.

### The Routing Constraint

**Reference files NEVER point directly to other reference files.** At boundaries (error, checkpoint, completion, escalation), a reference file names the next protocol — it does NOT include a reference tag pointing to the implementation file.

The Conductor returns to SKILL.md, finds the named protocol section, re-reads the protocol's context/purpose/constraints, then follows the reference pointer to the implementation file.

```
SKILL.md: "Follow Phase Execution Protocol"
  → reference: phase-execution.md (loaded, executed)
    → hits error boundary
    → "Proceed to Error Recovery Protocol" (name only)

Conductor returns to SKILL.md
  → finds "Error Recovery Protocol" section
  → reads SKILL.md context: authority scope, correction limits, constraints
  → follows reference to error-recovery.md
  → executes error recovery procedure
```

This forced pass-through creates a deliberate pause and realignment at every protocol transition — the Conductor re-exposes itself to the protocol's mandatory rules before diving into the procedure.

### Key Constraints

1. **State lives in the database.** When trampolining between protocols, the Conductor reads current state from comms-link. No context carried in-head across transitions.
2. **Strict protocol naming.** Reference files use exact protocol names from SKILL.md's registry. Name mismatch causes the Conductor to guess instead of looking up.
3. **Yo-yo prevention.** SKILL.md routing checks retry_count before entering Error Recovery for the same task/error. Threshold exceeded → route to Repetiteur Protocol.
4. **Hollow instructions.** SKILL.md protocol sections are deliberately un-executable without the reference file. Context/purpose/constraints only, no procedures.
5. **Reference scoping.** Reference files describe ONLY their protocol's work. At boundaries, they name the next protocol — they don't implement it.
6. **SQL co-location.** SQL lives in the protocol file where it's used. Duplication across protocols is acceptable — locality of behavior > DRY for LLM-consumed docs.

### SKILL.md Structure

```
SKILL.md (~200-300 lines):
  ├─ YAML frontmatter (skill registration)
  ├─ <metadata> (Tier 3)
  ├─ <sections> index (protocol registry)
  ├─ <section id="mandatory-rules"> — collected critical constraints
  ├─ <section id="purpose"> — skill identity, pipeline position
  ├─ <section id="initialization-protocol"> — hollow, points to initialization.md
  ├─ <section id="phase-execution-protocol"> — hollow, points to phase-execution.md
  ├─ <section id="review-protocol"> — hollow, points to review-protocol.md
  ├─ <section id="error-recovery-protocol"> — hollow, points to error-recovery.md
  ├─ <section id="repetiteur-protocol"> — hollow, points to repetiteur-invocation.md
  ├─ <section id="completion-protocol"> — hollow, points to completion.md
  ├─ <section id="musician-lifecycle"> — hollow, points to musician-lifecycle.md
  └─ <section id="sentinel-monitoring"> — hollow, points to sentinel-monitoring.md
```

### Reference File Organization (by protocol)

| File | Protocol | Contents |
|------|----------|----------|
| `initialization.md` | Initialization | Bootstrap steps, database DDL, plan loading, MEMORY.md tracking, git branch verification |
| `phase-execution.md` | Phase Execution | Plan consumption, task decomposition, Copyist launch, Musician launch, monitoring cycle |
| `review-protocol.md` | Review | Review checklists, smoothness scoring, approval/rejection SQL, context-aware reading |
| `error-recovery.md` | Error Recovery | Error classification, fix proposals, retry SQL, 5-correction threshold, escalation routing |
| `repetiteur-invocation.md` | Repetiteur | Spawn prompt template, blocker report format, handoff reception, plan changeover, passthrough comms |
| `completion.md` | Completion | Final verification, proposal integration, PR preparation, cleanup |
| `musician-lifecycle.md` | Musician Lifecycle | PID tracking, window cleanup rules, session resume for post-completion fixes, handoff automation |
| `sentinel-monitoring.md` | Sentinel Monitoring | Temp log watcher teammate prompt, anomaly criteria, lifecycle |

Additional protocols may emerge during SKILL.md drafting (Tier 1 of the buildout).

### Selective Self-Reading

The Conductor uses its own Tier 3 reference structure for context-efficient reading. When a protocol reference file is loaded, the Conductor reads the `<sections>` index first, then reads only the specific section needed — never loads a full reference file. Each `<reference>` tag in SKILL.md is an inline reminder to read selectively.

### 3-Tier Buildout Approach

1. **Draft SKILL.md** — define protocol registry, routing logic, hollow sections with stub references. This establishes the protocol vocabulary.
2. **Build reference files** — each implementing one protocol, strictly scoped, with hand-off points naming other protocols by their registry name.
3. **Rebuild SKILL.md** — refine wording, add precise `path#section` reference pointers, add inline `<mandatory>` reinforcement at every violation-prone point.

---

## 3. Autonomous Operation

### Operational Model

The Conductor is fully autonomous after bootstrap user approval. The user observes via terminal output and can interrupt, but the Conductor doesn't wait for input.

**Bootstrap (interactive):**
- Execute initialization steps
- Present plan overview (from Arranger's Overview + Phase Summary)
- User approves execution approach
- This is the last interactive gate

**Post-bootstrap (autonomous):**
- Phase planning, Copyist launching, Musician launching, monitoring, review handling — all without user prompts
- User-visible progress output at checkpoints (verbose during Repetiteur workflow)
- User can interrupt/provide input; Conductor doesn't wait for it

### Escalation Chain

1. Conductor attempts fix (up to 5 corrections per blocker)
2. If still stuck → spawn Repetiteur as teammate (opus, 1m context)
3. User only involved if Repetiteur escalates (vision deviation, 3rd consultation, significant scope change)

### Authority Scope

- **Can modify:** Intra-phase directions without breaking existing choices/architecture
- **Cannot modify:** Cross-phase dependencies, architectural decisions, protocol choices, items tagged `<mandatory>` in Arranger phase sections
- **Escalates to Repetiteur:** When out-of-scope changes are required, or after 5 correction attempts fail

### Delegation Model

- **Teammates (>40k estimated tokens):** Task decomposition, complex error analysis, review deep-dives, Copyist launches, any judgment-heavy or iterative work. Resumable with preserved context.
- **Regular Task subagents (<40k):** Monitoring watchers, simple polling, quick one-shot checks.

---

## 4. Arranger Plan Consumption

### Consumption Model

The Conductor reads Arranger-produced plans selectively, one phase at a time:

1. **Bootstrap:** Read plan-index (line ranges) + Overview + Phase Summary. This is the map — small context cost.
2. **Per-phase start:** Read `phase:N` section + `conductor-review-N` section via plan-index line ranges. One phase at a time.
3. **Pass to Copyist:** Same line range + task ID assignments + Overrides & Learnings.
4. **During reviews/errors:** Phase context already loaded from step 2.
5. **Phase complete:** Verify against conductor-review-N checklist items, then move to next phase.

Context scales with phase count, not plan size. The Conductor never loads the full document or future phases upfront.

### Lock Indicator

The plan-index (`<!-- plan-index:start -->`) at the top of the file is the lock indicator. Its presence confirms the Arranger's finalization checklist passed. The Conductor's first step is to check for this — if absent, the plan is unverified and the Conductor stops.

### Correction to Arranger Design

The Arranger design assumed the Conductor would never read phase sections. The Conductor DOES need phase context for reviews, fixes, and task decomposition. The dual-audience model is still valid — phase sections serve both Copyist and Conductor, while conductor-review sections serve Conductor only. This needs correction in the Arranger skill when it's built.

---

## 5. Repetiteur Integration

### Launch Protocol

The Conductor spawns the Repetiteur as a teammate (opus, 1m context) when blockers exceed its 5-correction authority limit. Before spawning, the Conductor:

1. Pauses all running Musicians
2. Writes the structured blocker report to `decisions/{feature-name}/` (crash recovery insurance)
3. Checks plan revision number — refuses to spawn if revision would be `r4` (max 3 consultations). Escalates to user instead.
4. Spawns Repetiteur with lean prompt: task IDs, states, instruction file PATHS (not content), artifact references, git state summary. The Repetiteur reads files itself.

### Passthrough Communication

During consultation, user input typed in the Conductor terminal is relayed to the Repetiteur via SendMessage verbatim — no interpretation or filtering. Reverse direction works naturally (Repetiteur's SendMessage appears in Conductor output). When Repetiteur is active, all user input goes to Repetiteur unless clearly a Conductor command (e.g., "stop", "abort").

### Handoff Reception

The Repetiteur annotates tasks inline in the remaining plan: no annotation = unchanged, `(REVISED)` / `(NEW)` / `(REMOVED)` next to task numbers.

**Changeover flow:**
1. Receive handoff message via SendMessage
2. Read remaining plan, note task annotations
3. Update MEMORY.md with new plan path
4. Unmarked tasks → resume paused Musicians
5. REVISED tasks → close old kitty window, delete old instruction files, launch Copyist for new instructions, launch fresh Musician
6. REMOVED tasks → close window, clean up
7. NEW tasks → launch Copyist for new instructions, launch fresh Musician

This is NOT a full phase restart. Completed work stays. Unchanged paused Musicians resume. Only changed/failed tasks get fresh launches.

---

## 6. Musician Lifecycle Management

### PID Tracking

The Conductor manages the full Musician lifecycle autonomously:
- **Launch:** `kitty ... & echo $! > temp/musician-task-03.pid`
- **Cleanup:** Read PID from file, `kill $PID` (SIGTERM), remove PID file
- **Detection:** Handled by existing comms-link monitoring (state changes)

### Cleanup Rules

- **Parallel tasks:** Close all windows when ALL parallel siblings reach `complete`/`exited`
- **Sequential tasks:** Close immediately on `complete`/`exited`
- **Re-launch (handoff):** Close old session IMMEDIATELY before launching replacement. Never two windows for same task simultaneously.

### Post-Completion Error Correction

When a later task discovers an integration error with completed work, the Conductor can resume the original Musician session:

1. Session ID already stored in `orchestration_tasks.session_id` from claim step
2. Session data persists after kitty window is killed
3. Conductor creates a new task row (e.g., `task-01-fix`) with its own lifecycle — `complete` stays terminal
4. Conductor launches: `kitty ... -- claude --resume "$SESSION_ID" "Fix: [details]"`
5. Resumed Musician claims the fix task row via comms-link, maintaining orchestration coverage

This preserves the original session's full context while keeping the state machine intact.

### Context Exhaustion

Simple automation: Conductor detects exit (state = `exited`), reads HANDOFF document, closes kitty window, launches fresh Musician session with HANDOFF context in the prompt. No `--resume` for exhaustion — session is already at limit.

---

## 7. Sentinel Teammate

### Concept

A lightweight teammate that watches all active Musicians' temp/ logs and sends fire-and-forget reports to the Conductor when it spots anomalies. Purely additive to the existing background message-watcher.

### Anomaly Criteria (mechanical, no judgment)

- Any `self-correction` entry in status log
- Any `High:` severity deviation
- Context usage jump >15% between consecutive entries
- No new entries for >5 minutes (stuck/looping)

### Behavior

- Polls temp/ files on ~10 second interval
- Reports anomalies via SendMessage, immediately resumes watching
- Does NOT wait for or expect responses from Conductor
- Conductor decides independently whether to act (emergency broadcast) or note (informational)

### Lifecycle

- Launched when Musicians launch for a phase
- Runs alongside the background message-watcher subagent
- Shut down when Conductor messages it that the phase is complete

---

## 8. Eliminated Features

### STATUS.md

STATUS.md is eliminated. Its roles are absorbed by other mechanisms:
- **Task state tracking** → comms-link database
- **Recovery/handoff** → unnecessary with 1m context
- **Current plan reference** → single line in MEMORY.md
- **Task Planning Notes** → Conductor holds in-session with 1m context
- **Proposals Pending** → tracked in database or in-session

The `references/status-md-reading-strategy.md` and `references/recovery-instructions-template.md` files are no longer needed.

### Foreground Monitoring

The foreground blocker agent idea was evaluated and scratched. The background watcher reliably notifies the Conductor on exit — the problem was never the notification mechanism. The fix is structural: extensive `<mandatory>` reinforcement at every watcher failure point throughout the skill, per the Tier 3 reinforcement principle.

### Session ID Environment Variable

The CLAUDECODE env var does not expose the session ID natively. The SessionStart hook injection stays as-is.

---

## 9. Monitoring & Watcher Reinforcement

The background watcher model stays. What changes is the reinforcement discipline. Per the Tier 3 reinforcement principle, `<mandatory>` flags are placed at every failure point:

- Watcher launch (must verify running before any work)
- Watcher re-launch after every event handling cycle
- Heartbeat refresh (task-00 must stay alive)
- Watcher exit behavior (must exit on state change, not loop)
- Watcher re-launch after review/error handling completes
- Watcher polling interval adherence
- Message deduplication (don't re-process old messages)

Collected `<mandatory>` block at top of SKILL.md states all rules. Inline `<mandatory>` tags repeat each rule at the exact execution point where violation historically occurs.

---

## 10. Edge Cases

### Musician Fails to Claim (Obsidian #14b)

Already handled by guard clause → fallback row → claim_blocked message. In autonomous mode: Conductor detects claim_blocked, closes failed kitty window, resets task row, re-launches. Straightforward automation.

### Musician Fails to Update Heartbeat (Obsidian #14c)

Staleness detection (>9 min). Conductor checks if PID is still alive. If PID alive but heartbeat stale → watcher died, session stuck → close window, re-launch. If PID dead → crash → follow crash handoff procedure.

### Unable to Determine Phase Steps (Obsidian #14e)

Launch a teammate for focused discussion with Explorer access for codebase context. Gemini as fallback for guidance. This is part of the generalized teammate delegation model.

### Copyist Output Errors (Obsidian #14f)

Small errors: Conductor edits inline. Larger issues: re-launch Copyist teammate to correct/rewrite. The Copyist teammate is resumable if the first attempt doesn't fully resolve.

---

## 11. Naming & Reference Cleanup

- **I1:** Old name references (Orchestrator → Conductor, Task-Writer → Copyist, Executor → Musician) must be updated FIRST before other content changes
- **I2:** Canonical path for task instructions: `docs/tasks/`
- **I3:** STATUS.md eliminated (see Section 8)
- **I4:** Update any 200k context budget references → 1m

---

## 12. Reference File Restructuring

### Current → Target Mapping

The 15 existing reference files (organized by type) must be restructured into ~8 protocol files (organized by workflow). Content from a single existing file may split across multiple protocol files. SQL co-location means some templates are intentionally duplicated.

| Existing File | Target Protocol File(s) | Notes |
|---------------|------------------------|-------|
| `database-queries.md` | Split across `initialization.md`, `phase-execution.md`, `error-recovery.md`, `review-protocol.md`, `completion.md` | DDL → initialization, task queries → phase-execution, error SQL → error-recovery, etc. |
| `musician-launch-prompt-template.md` | `phase-execution.md` | Launch template is part of phase execution workflow |
| `parallel-coordination.md` | `phase-execution.md` | Parallel launch protocol is part of phase execution |
| `sequential-coordination.md` | `phase-execution.md` | Sequential execution is part of phase execution |
| `review-checklists.md` | `review-protocol.md` | Direct move, single target |
| `state-machine.md` | Split: summary in `initialization.md`, relevant transitions co-located in each protocol file | Each protocol gets the state transitions it uses |
| `session-handoff.md` | `musician-lifecycle.md` | Handoff procedures are lifecycle management |
| `subagent-prompt-template.md` | `phase-execution.md` | Copyist/monitoring subagent prompts used during phase execution |
| `subagent-failure-handling.md` | `error-recovery.md` | Failure handling is error recovery |
| `danger-files-governance.md` | `phase-execution.md` | Danger file assessment happens during phase planning |
| `orchestration-principles.md` | Absorbed into SKILL.md `<context>` sections | High-level principles belong in the dispatcher, not a protocol |
| `rag-coordination-workflow.md` | `review-protocol.md` or new `rag-processing.md` | RAG processing triggers after reviews |
| `rag-query-guide.md` | Absorbed into relevant protocol files as inline guidance | Query patterns co-located where they're used |
| `status-md-reading-strategy.md` | **DELETED** | STATUS.md eliminated |
| `recovery-instructions-template.md` | **DELETED** | Recovery docs unnecessary with 1m context |

### Example Files

The 7 existing example files need assessment — some may map to new protocol files as embedded examples, others may remain as standalone example files if they demonstrate cross-protocol workflows. This mapping will be finalized during the implementation plan.

### Restructuring Approach

**Method:** Teammates per protocol + staging directory + cross-reference review.

1. **Staging directory:** New protocol files are created in `references/protocols/` (staging). Original files in `references/` are preserved throughout.

2. **Step 3a — Extraction proposals (exploration phase).** One teammate per protocol file. Each teammate:
   - Reads ALL existing reference files (large context, exploration-optimized)
   - Identifies content relevant to its assigned protocol
   - Produces a proposal document listing exact source locations (file + line ranges) for each piece of content
   - Does NOT create the protocol file yet — output is proposals only
   - Duplication across proposals is expected and correct (SQL co-location design intent)

3. **Proposal review.** Proposals are reviewed to confirm:
   - Every paragraph in every original file appears in at least one proposal (nothing dropped)
   - Protocol scoping is correct (no proposal includes content outside its protocol's scope)
   - Authority classification is preserved (content that was `<mandatory>` stays `<mandatory>`)

4. **Step 3b — Content creation (implementation phase).** After proposals are approved, teammates create the new protocol files. They work from:
   - The approved proposals (checklist of what to include — every item gets migrated)
   - The design document (what to add/change — new content layered on top of migrated content)
   - Focused context, not exploration context — work off the defined proposal list

5. **Review pass.** After all protocol files are created, a review agent cross-references original files against new protocol files to confirm content preservation, authority tag correctness, and protocol scoping.

6. **Cutover.** After review passes, old `references/` files are archived, `references/protocols/` contents move to `references/`, and SKILL.md is updated with final reference pointers.

---

## 13. Tier 3 Migration Status

The Tier 3 migration of all Conductor skill files is **complete and verified**:
- 23 files migrated (SKILL.md + 15 references + 7 examples)
- All files pass structural compliance, strict content rule, authority tag rules, template tags, and content preservation checks
- Migration was performed by a dedicated teammate and verified by an independent Opus review agent
- Zero issues found

The migrated files provide the structural base for all content changes described in this design. The protocol reorganization (Section 2) will restructure these files by protocol rather than by type.

---

## 13. Design Decisions Log

| Decision | Rationale |
|----------|-----------|
| **Protocol-dispatching SKILL.md** | Prevents context overload from monolithic skill file. Validated by Gemini. Hollow instructions prevent "lazy student" hallucination. |
| **Reference → name → SKILL.md → reference routing** | Forces deliberate realignment at protocol boundaries. Prevents instruction drift during long reference chains. |
| **SQL co-location in protocol files** | Locality of behavior > DRY for LLM-consumed docs. Each protocol is self-contained. |
| **Fully autonomous after bootstrap** | User drops out of error loop. Escalation chain: Conductor (5 corrections) → Repetiteur → User (vision only). |
| **`<mandatory>` constrains intra-phase authority** | Arranger's `<mandatory>` tags in phase sections are not modifiable by Conductor even within intra-phase scope. |
| **Teammates for >40k token work** | Resumable, full capabilities, direct communication. Better than one-shot subagents for judgment-heavy work. |
| **Background watcher stays (reinforced)** | Notification mechanism works. Fix is structural reinforcement at failure points, not architectural change. |
| **Sentinel teammate for temp log monitoring** | Proactive anomaly detection. Fire-and-forget reports. Minimal context cost. |
| **STATUS.md eliminated** | 1m context eliminates need for recovery docs. Plan tracking via MEMORY.md single line. |
| **PID tracking for Musician lifecycle** | Autonomous cleanup requires tracking which process to kill. Sentinel file per Musician. |
| **Post-completion resume via `--resume`** | Fix integration errors by resuming original session with full context. New task row preserves terminal state contract. |
| **Repetiteur inline task annotations** | Cleaner than separate mapping list. No annotation = unchanged. Conductor reads plan and knows immediately what changed. |
| **Passthrough comms — relay verbatim** | Simple, sufficient. When Repetiteur active, all user input goes to Repetiteur unless clearly a Conductor command. |
| **Blocker report persisted before spawning** | Crash recovery insurance. If session dies during consultation, context of why help was summoned is preserved. |
| **Consultation count from plan revision number** | Derivable from `r1`/`r2`/`r3` in plan filename/metadata. No separate counter needed. Conductor refuses `r4`. |
| **Arranger plan: Conductor reads phase sections** | Corrects Arranger design assumption. Conductor needs phase context for reviews, fixes, and task decomposition. Selective per-phase reading preserves context benefits. |
| **3-tier buildout sequence** | Skeleton → References → Refined Skeleton. Can't write precise pointers until reference sections exist. |
