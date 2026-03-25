# Conductor Universality & Resilience Update

**Date:** 2026-03-25
**Type:** Design Spec
**Skill:** Conductor v4.0 → v5.0
**Scope:** Two-wave update — Wave 1 (decouple) and Wave 2 (extend)

## Overview

The Conductor skill is currently hardcoded to the `remindly` project — paths, hooks, terminal emulator, VCS, and session management are all baked in. This update makes the Conductor universally project-agnostic and adds resilience features for long-running autonomous orchestration.

**Wave 1 (Decouple):** Configuration system, hook removal, project-agnostic paths, optional VCS, terminal decoupling, session layer with window reuse.

**Wave 2 (Extend):** Heartbeat teammate, infrastructure degradation protocol.

### Sources

- `conductor/docs/working/conductor-issues.md` — 7 field-tested issues from the hockey simulation project
- Obsidian notes at `Custom Skills/Conductor` — 4 enhancement ideas (1 deferred: Lethe compact protocol)
- Souffleur config pattern — `.orchestra_configs/` with Python resolver

### Deferred

- **Lethe compact protocol** — Replacing `/compact` with Lethe for Musician compaction. Deferred pending Lethe skill work.

---

## Wave 1: Decouple

### 1. Configuration System

**Pattern:** Follows Souffleur's established `.orchestra_configs/` convention.

**Config file location** (search order, first found wins):
1. `<project-dir>/.orchestra_configs/conductor`
2. `<project-dir>/../.orchestra_configs/conductor`

**Format:** Plain text key=value pairs. `#` comments, blank lines ignored, duplicate keys last-value-wins with warning.

**Resolver:** `skills/conductor/scripts/conductor-config.py`
- Validates all values against allowed sets/types
- Applies defaults for missing keys
- Outputs JSON to stdout with resolved values, source path, and warnings array
- Invalid values emit warning and fall back to default

**Configuration variables:**

| Key | Default | Allowed Values | Purpose |
|-----|---------|----------------|---------|
| `PROJECT_DIR` | (cwd) | absolute path | Root directory for orchestration |
| `TERMINAL_CMD` | `kitty` | any terminal command | Terminal emulator for launching windows |
| `SESSION_LAYER` | `tmux` | `tmux`, `fifo` | Session injection backend |
| `VCS_ENABLED` | `true` | `true`, `false` | Whether to run VCS checks |
| `SOUFFLEUR_PERMISSIONS` | `acceptEdits` | `acceptEdits`, `bypassPermissions` | Permission mode for Souffleur launch |
| `MUSICIAN_PERMISSIONS` | `acceptEdits` | `acceptEdits`, `bypassPermissions` | Permission mode for Musician launches |
| `MAX_PARALLEL_MUSICIANS` | `4` | positive integer | Maximum concurrent Musician sessions. Enforced in phase-execution parallel Step 6 — Conductor counts active sessions before launching and queues excess tasks |
| `DEGRADATION_FIX_ATTEMPTS` | `5` | positive integer | Self-heal attempts before Souffleur relaunch. Recommendation: try at least this many. May escalate sooner only if self-healing is provably impossible (e.g., comms-link entirely unreachable) |
| `DEGRADATION_RELAUNCH_LIMIT` | `2` | positive integer | Max Souffleur relaunches before critical failure |
| `HEARTBEAT_POKE_THRESHOLD` | `240` | positive integer (seconds) | Seconds before heartbeat teammate pokes Conductor |

**Consumption:** Conductor runs resolver as Step 0 (pre-step before the existing Step 1), stores JSON in-session. Existing step numbers remain unchanged until the hook removal renumbering (Step 9 deleted, Step 10 → Step 9). All protocols reference config values by name — no hardcoded literals anywhere in skill files.

**Note:** Wave 2 variables (`HEARTBEAT_POKE_THRESHOLD`, `DEGRADATION_FIX_ATTEMPTS`, `DEGRADATION_RELAUNCH_LIMIT`) are defined in the resolver with defaults but have no effect until Wave 2 is implemented. This is intentional — Wave 1 creates the config infrastructure, Wave 2 consumes it.

**Missing config file:** All defaults apply silently. Config is optional.

### 2. Hook Removal

**Remove entirely:**
- `initialization.md` → `hook-verification` section — deleted
- Step 9 (Verify Hooks) — deleted from bootstrap sequence
- Step 10 (User Approval Gate) renumbered to Step 9
- All references to `hooks.json`, `session-start-hook.sh`, `stop-hook.sh` — removed

**Update:**
- `column-reference` section: `session_id` description changes from "set by SessionStart hook, injected into system prompt as $CLAUDE_SESSION_ID" to "available in system prompt as $CLAUDE_SESSION_ID"
- `souffleur-launch` section: remove "$CLAUDE_SESSION_ID is a system prompt value injected by the SessionStart hook" — replace with "available in system prompt"
- Bootstrap sequence description: "Steps 1-5 are reads (parallelizable). Steps 6-8 are writes (sequential). Step 9 is the user gate."

**Note:** The stop hook concept (sessions only exit in terminal states) may be reimplemented separately. Removing it from the Conductor means the Conductor no longer gates on hook infrastructure existing. The hooks themselves are outside Conductor's scope.

### 3. Project-Agnostic Paths

**All hardcoded `/home/kyle/claude/remindly` paths → `$PROJECT_DIR` from config.**

Affected locations across reference files:
- All launch templates (Souffleur, Musician, Copyist, compact sessions) — `kitty --directory /home/kyle/claude/remindly` becomes `$TERMINAL_CMD` via launch script with `$PROJECT_DIR`
- `database-location` section — remove hardcoded path, replace with: "Database is accessed exclusively via comms-link MCP. The Conductor does not need to know the database file path."
- `temp/` description — remove symlink assumption (`symlinked to /tmp/remindly`), replace with: "temp/ directory in project root. Must exist before execution; created in Step 3 if missing."
- JSONL sentinel path in `compact-protocol.md` — currently hardcodes `~/.claude/projects/-home-kyle-claude-remindly/`. Discover dynamically via glob `~/.claude/projects/*/${SESSION_ID}.jsonl` (session ID is unique). Edge cases: if glob returns zero matches (JSONL not yet created), retry with short delay up to 30 seconds. If `~/.claude/projects/` does not exist, treat as compact failure and fall back to fresh-session launch. Cache the resolved path after first successful glob to avoid repeated directory scans.

**Step 4 (Load Project Context) — rewritten:**

Current version loads a hardcoded list of remindly-specific READMEs (`docs/README.md`, `knowledge-base/README.md`, `implementation/README.md`, `implementation/proposals/README.md`, `scratchpad/README.md`).

New version: Discover and read project documentation indexes. Check for `docs/README.md` and scan for other top-level READMEs. Skip gracefully if none exist. No hardcoded list — different projects have different structures.

**Relative paths stay relative:** `docs/tasks/`, proposal directories, etc. are relative to `PROJECT_DIR` (the cwd). No changes needed.

### 4. VCS Optional

**Config:** `VCS_ENABLED=true` (default)

**When `true`:** Step 2 runs as today — `scripts/check-git-branch.sh`, verify not on main, create feature branch if needed. Mandatory rule "Never execute orchestration on the main branch" is active.

**When `false`:** Step 2 is skipped entirely. Conductor logs to terminal: "VCS checks disabled via config — skipping branch verification." No branch checks, no branch creation. The mandatory rule about main branch is inert.

**Changes:**
- `initialization.md` → `bootstrap-steps` → Step 2: Conditional on `VCS_ENABLED`
- `check-git-branch.sh`: Unchanged — only called when VCS is enabled
- Git worktree references elsewhere (`isolation: "worktree"` in Agent tool): These are Claude Code platform features, not Conductor-managed. No changes.

### 5. Terminal & Session Layer

The largest architectural change. Decouples the Conductor from kitty and introduces a session injection mechanism for window reuse.

#### Part A: Terminal Decoupling

**Config:** `TERMINAL_CMD=kitty` (default)

**New script:** `scripts/launch-terminal.sh` — wraps terminal-specific invocation behind a standard interface:

```
Usage: launch-terminal.sh --title "NAME" --dir "PATH" --session "SESSION_NAME" [--close-on-exit]
```

Translates to terminal-specific flags:
- `kitty`: `kitty --directory $DIR --title $TITLE ...`
- `alacritty`: `alacritty --working-directory $DIR --title $TITLE ...`
- Others: extensible case statement, falls back to `$TERMINAL_CMD` with POSIX-ish flags

Terminal-specific knowledge lives in this one script rather than scattered across every launch template.

#### Part B: Session Layer

**Config:** `SESSION_LAYER=tmux` (default), fallback `fifo`

**New reference file:** `references/session-layer.md` — loaded on demand only. Launch templates in `phase-execution.md` and `musician-lifecycle.md` point to this file but do not inline session mechanics. This reduces reading burden in the common case.

**New scripts:**
- `scripts/session-commands.sh` — shell functions for `create-session`, `inject-session`, `kill-claude-in-session`, `destroy-session`. Routes to tmux or FIFO backend based on config.

**tmux backend:**
- **Session naming:** All tmux session names are namespaced with a project identifier derived from `PROJECT_DIR` basename to prevent collisions when multiple Conductors run on different projects: `${PROJECT_NAME}-musician-primary`, `${PROJECT_NAME}-musician-task-XX`.
- Create long-term session: `tmux new-session -d -s ${PROJECT_NAME}-musician-primary`
- Inject command: `tmux send-keys -t ${PROJECT_NAME}-musician-primary "claude ..." Enter`
- Kill Claude (not window): discover Claude PID via `tmux list-panes -t SESSION -F '#{pane_pid}'`, walk child processes to find `claude`, kill it. Shell returns to prompt inside tmux.
- Temporary parallel sessions: `tmux new-session -d -s ${PROJECT_NAME}-musician-task-XX` — fully destroyed on cleanup.
- **Terminal/tmux relationship:** `launch-terminal.sh` opens a terminal window that runs `tmux attach -t SESSION_NAME` as its command. The terminal is a display layer; tmux owns the session. This means the user sees output in the terminal window, and the Conductor interacts via `tmux send-keys` to the named session. If the terminal window is closed accidentally, the tmux session persists detached and can be reattached.

**FIFO backend (fallback when tmux unavailable):**
- New script: `scripts/session-fifo-loop.sh` — runs inside the terminal window, reads commands from a named FIFO in a loop
- **FIFO ownership:** The loop script creates the FIFO (`mkfifo temp/musician-SESSION.fifo`) on startup, before entering the read loop. The Conductor waits for the FIFO to exist (poll with short delay, max 10 seconds) before injecting commands. This eliminates the creation race — one owner, one consumer.
- **Loop script PID tracking:** On startup, the loop script writes its own PID to `temp/fifo-loop-SESSION.pid`. This gives the Conductor a reliable process tree root for Claude PID discovery (walk children of the loop script PID to find `claude`), independent of terminal emulator process tree structure.
- **Write sequencing:** The loop script reads one command per iteration (`read cmd < fifo; eval "$cmd"; [wait for exit]; read cmd < ...`). It blocks on the FIFO read until the previous command (Claude session) exits. The Conductor must kill the running Claude process before writing the next command — injecting while Claude is running blocks until Claude exits. This is the correct behavior for task rotation (kill Claude, then inject next).
- Inject command: `echo "claude ..." > temp/musician-SESSION.fifo`
- Kill Claude: read loop script PID from `temp/fifo-loop-SESSION.pid`, walk child processes to find `claude`, kill it. Shell returns to FIFO read loop.
- Cleanup: remove FIFO file and PID file, loop exits naturally on broken pipe.

#### Prompt File Pattern

All launch templates change from inline prompts to file-based prompts. This fixes the silent shell escaping failures documented in the working issues (issue 7).

1. Conductor writes prompt to `temp/task-XX-prompt.txt`
2. Session injection references the file: `claude --permission-mode $MUSICIAN_PERMISSIONS -p "$(cat temp/task-XX-prompt.txt)"`

#### Window Lifecycle

**Musician windows:**

| Event | Long-term window | Parallel temp windows |
|-------|-----------------|----------------------|
| Phase start (sequential) | Create if doesn't exist | N/A |
| Phase start (parallel) | Reuse for task 1 | Create for tasks 2-N |
| Task rotation (sequential) | Kill Claude, inject next | N/A |
| Task complete (parallel) | Kill Claude, idle | Destroy window entirely |
| Phase complete | Idle (awaits next phase) | Already destroyed |
| Project complete | Destroy | Already destroyed |

**Souffleur and Repetiteur windows:** Simpler lifecycle — single window each, created at launch, destroyed at completion or kill. No reuse pattern. These follow the same terminal/session-layer abstraction but without the long-term window concept.

#### PID Tracking Changes

Current model tracks one kitty PID per task. New model:

- **Window PID:** `temp/window-musician-primary.pid` (the terminal process — long-lived for the primary window)
- **Session name:** `temp/session-musician-primary.name` (tmux session name or FIFO path — used by session-commands.sh)
- **Claude PID:** Discovered dynamically when needed (child of tmux pane or FIFO loop shell)
- **Parallel window PIDs:** `temp/window-musician-task-XX.pid` (temporary, destroyed with the window)

The per-task `temp/musician-task-XX.pid` pattern is replaced by the above. Lifecycle management in `musician-lifecycle.md` updates accordingly — cleanup commands use `session-commands.sh` functions instead of direct `kill $PID`.

---

## Wave 2: Extend

### 6. Heartbeat Teammate

A permanent teammate launched during initialization that monitors the Conductor's heartbeat and sends critical interrupts when the heartbeat goes stale. Fills the gap between a dead message-watcher and Souffleur's kill threshold.

**Config:** `HEARTBEAT_POKE_THRESHOLD=240` seconds (4 minutes). Must be well below the Souffleur's 9-minute staleness threshold.

**Launch:** Initialization Step 8, after Souffleur confirmation, alongside message-watcher launch. Permanent — runs for the entire Conductor session.

**Implementation:** Team teammate (not regular subagent). Uses `SendMessage` to communicate with Conductor — this channel works even without a database watcher.

**Teammate behavior:**
- Poll task-00 heartbeat via comms-link every 60 seconds
- If `(now - last_heartbeat) > HEARTBEAT_POKE_THRESHOLD`: `SendMessage` to Conductor
- Message: "HEARTBEAT STALE: task-00 heartbeat is {N} seconds old. Message-watcher may be dead. Relaunch immediately."
- If poke fails to produce heartbeat refresh within 2 more poll cycles (2 minutes): poke again with escalated urgency
- **Silent watchdog:** Sends messages ONLY when heartbeat is stale. No status updates, no confirmations, no periodic reports. Every message is a critical alert.

**Mandatory rule (added to SKILL.md `mandatory-rules`):**

> Messages from the heartbeat teammate are CRITICAL interrupts. Drop current work immediately — mid-review, mid-error-handling, mid-anything — and address the heartbeat issue before returning to the interrupted task. A stale heartbeat means the Conductor is invisible to Musicians and approaching Souffleur kill threshold. Nothing else matters until the heartbeat is live.

**Conductor's response to poke:**
1. Check if message-watcher is running (active background task)
2. If watcher is dead: relaunch immediately via monitoring-subagent-template
3. If watcher is alive but heartbeat still stale: kill and relaunch watcher (it may be stuck)
4. Refresh heartbeat after resolution
5. Return to interrupted work

**Shutdown:** On normal completion (Completion Protocol), the Conductor sends a shutdown message to the heartbeat teammate. On context recovery or Souffleur kill, the teammate dies automatically when the Conductor session is terminated.

**Skill file locations:**
- Launch template: `initialization.md` → new section `heartbeat-teammate-launch` (after `message-watcher-launch`)
- Mandatory rule: SKILL.md → `mandatory-rules` section
- Response handling: Conductor's main event processing (new event type)
- Brief mention in SKILL.md preamble under Three-Tier model (Tier 2 addition)

### 7. Infrastructure Degradation Protocol

A new protocol for when the Conductor's own tools degrade during long-running sessions — bash failures, MCP timeouts, comms-link unresponsiveness. Provides a structured escalation ladder from self-healing through Souffleur relaunch to critical failure.

**New protocol entry in SKILL.md protocol registry:**

| Protocol | Role |
|----------|------|
| **Infrastructure Degradation Protocol** | Self-healing and escalation for Conductor tool failures |

**New section in SKILL.md:** `<section id="infrastructure-degradation-protocol">` with core framing and reference pointer.

**New reference file:** `references/infrastructure-degradation.md`

**Detection criteria (heuristic, assessed by Conductor):**
- Same tool fails 3+ times in a row with non-task-related errors
- Multiple unrelated tools fail within a short window (systemic degradation)
- comms-link becomes unresponsive (most critical — orchestration backbone)

**Escalation ladder:**

```
Step 1: Self-heal (minimum 5 attempts — recommendation, not ceiling)
  The Conductor determines approach: reconnect MCP, retry with different flags,
  use alternative tools, etc. No prescribed fixes — Conductor uses judgment.
  The number 5 is a minimum recommendation to stress the importance of this step.
  A Souffleur relaunch is disruptive — it pauses the entire orchestration.
  The Conductor should treat escalation as a last resort, not a convenience.
  Try different tools, different approaches, different workarounds. Exhaust options.
  If resolved: return to previous work.
  If still failing after thorough attempts: Step 2.

Step 2: Request Souffleur relaunch
  ORDERING IS CRITICAL — follow the same sequence as the existing
  context-exhaustion-trigger in error-recovery.md:
  1. Write learnings + degradation details to temp/conductor-learnings.log
  2. Insert message to orchestration_messages explaining the degradation
  3. Set state to context_recovery (this is the Souffleur kill trigger —
     once set, the Conductor may be killed at any moment)
  Souffleur detects state change, kills and relaunches via recovery bootstrap.

Step 3: Post-relaunch — same failures recur
  After DEGRADATION_RELAUNCH_LIMIT (default 2) failed relaunches:
  try any remaining workarounds not yet attempted.
  If resolved: continue.

Step 4: Critical failure
  All options exhausted.
  Pause all Musicians (emergency broadcast).
  Output clear terminal message: what failed, what was tried, what the user needs to do.
  Set state to exit_requested.
```

**Conductor latitude:** Steps 1 and 3 deliberately leave fix strategy to the Conductor's judgment. The protocol defines the escalation structure, not the specific fixes — those depend on what's actually broken.

**Integration with existing protocols:**
- `recovery-bootstrap.md`: No changes needed — already handles being relaunched. Degradation context captured in `temp/conductor-learnings.log` which recovery bootstrap already reads.
- `error-recovery.md`: Infrastructure degradation is distinct from Musician errors. If the Conductor encounters tool failures while handling a Musician error, it enters this protocol, resolves the tool issue, then returns to error recovery.

---

## Files Changed Summary

### New files
| File | Purpose |
|------|---------|
| `skills/conductor/scripts/conductor-config.py` | Configuration resolver |
| `skills/conductor/scripts/launch-terminal.sh` | Terminal-agnostic window launcher |
| `skills/conductor/scripts/session-commands.sh` | Session layer abstraction (tmux/FIFO routing) |
| `skills/conductor/scripts/session-fifo-loop.sh` | FIFO backend loop script |
| `skills/conductor/references/session-layer.md` | Session injection mechanics (on-demand reference) |
| `skills/conductor/references/infrastructure-degradation.md` | Degradation protocol full specification |

### Modified files
| File | Changes |
|------|---------|
| `skills/conductor/SKILL.md` | New mandatory rules (heartbeat interrupt, config-first), new protocol registry entries (Infrastructure Degradation), new sections (infrastructure-degradation-protocol, heartbeat handling) |
| `skills/conductor/references/initialization.md` | Config resolution as Step 1, hook-verification section removed, Step 4 rewritten (project context discovery), Step 9 renumbered, new heartbeat-teammate-launch section, Souffleur launch uses config variables |
| `skills/conductor/references/phase-execution.md` | All launch templates → session layer + prompt files, PID tracking updated, `$MUSICIAN_PERMISSIONS` from config |
| `skills/conductor/references/musician-lifecycle.md` | Cleanup commands → session-commands.sh, PID tracking model updated, window lifecycle for long-term/temporary windows |
| `skills/conductor/references/compact-protocol.md` | JSONL path discovery via glob, launch commands → session layer, PID tracking updated |
| `skills/conductor/references/repetiteur-invocation.md` | Launch template → session layer + config variables |
| `skills/conductor/references/error-recovery.md` | Reference to Infrastructure Degradation Protocol for tool-level failures |
| `skills/conductor/references/recovery-bootstrap.md` | Remove hook verification from Step 5 parallel group, replace crash-scenario fallback README loading with dynamic project discovery (same pattern as Step 4), remove hardcoded remindly-specific paths |
| `skills/conductor/scripts/validate-coordination.sh` | Review for hardcoded paths and PID file naming changes |

### Cross-Skill Dependencies

The Souffleur skill's recovery provider references contain hardcoded `kitty --directory /home/kyle/claude/remindly` Conductor launch templates. When the Conductor moves to the session layer and config system, the Souffleur's relaunch commands must match. This is a separate work item tracked outside this spec — the Souffleur's launch templates should use `launch-terminal.sh` and read from `.orchestra_configs/conductor` for `PROJECT_DIR` and `TERMINAL_CMD`.

### Removed content
| Location | What |
|----------|------|
| `initialization.md` → `hook-verification` | Entire section |
| `initialization.md` → `database-location` | Hardcoded path (replaced with comms-link-only statement) |
| All launch templates | Hardcoded `/home/kyle/claude/remindly` paths |
| All launch templates | Inline prompt arguments (replaced with prompt files) |
| Step 4 | Hardcoded README list including `knowledge-base/README.md` |
