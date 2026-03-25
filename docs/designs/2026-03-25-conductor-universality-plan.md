# Conductor Universality & Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Conductor skill universally project-agnostic and add resilience features for autonomous orchestration.

**Architecture:** Two-wave approach — Wave 1 decouples from hardcoded project assumptions (config system, terminal/session layer, VCS optional, hook removal), Wave 2 adds resilience (heartbeat teammate, infrastructure degradation protocol). All changes are to skill markdown files and shell scripts within `conductor/skills/conductor/`.

**Tech Stack:** Python 3 (config resolver), Bash (terminal/session scripts), Markdown with XML authority tags (skill files)

**Design Spec:** `conductor/docs/designs/2026-03-25-conductor-universality-design.md`

---

## Wave 1: Decouple

### Task 1: Configuration Resolver Script

**Files:**
- Create: `skills/conductor/scripts/conductor-config.py`

- [ ] **Step 1: Create the resolver script**

Model on `souffleur/skills/souffleur/scripts/souffleur-config.py`. Same structure: argparse, `--project-dir` flag, search `.orchestra_configs/conductor` in project dir then parent, parse key=value, validate, output JSON.

```python
#!/usr/bin/env python3
"""
Conductor: Configuration Resolver

Resolves orchestration settings from .orchestra_configs/conductor files.

Search order (first hit wins):
1. <project-dir>/.orchestra_configs/conductor
2. <project-dir>/../.orchestra_configs/conductor

Output is always valid JSON. Invalid or missing values emit warnings and
fallback to safe defaults.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# --- Defaults ---
DEFAULTS = {
    "PROJECT_DIR": None,  # resolved to cwd at runtime
    "TERMINAL_CMD": "kitty",
    "SESSION_LAYER": "tmux",
    "VCS_ENABLED": "true",
    "SOUFFLEUR_PERMISSIONS": "acceptEdits",
    "MUSICIAN_PERMISSIONS": "acceptEdits",
    "MAX_PARALLEL_MUSICIANS": 4,
    "DEGRADATION_FIX_ATTEMPTS": 5,
    "DEGRADATION_RELAUNCH_LIMIT": 2,
    "HEARTBEAT_POKE_THRESHOLD": 240,
}

ALLOWED_PERMISSIONS = {"acceptEdits", "bypassPermissions"}
ALLOWED_SESSION_LAYERS = {"tmux", "fifo"}
ALLOWED_BOOLEANS = {"true", "false"}

POSITIVE_INT_KEYS = {
    "MAX_PARALLEL_MUSICIANS",
    "DEGRADATION_FIX_ATTEMPTS",
    "DEGRADATION_RELAUNCH_LIMIT",
    "HEARTBEAT_POKE_THRESHOLD",
}


def _find_config_file(project_dir: Path) -> Path | None:
    candidates = [
        project_dir / ".orchestra_configs" / "conductor",
        project_dir.parent / ".orchestra_configs" / "conductor",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def _parse_config(path: Path) -> tuple[dict[str, str], list[str]]:
    values: dict[str, str] = {}
    warnings: list[str] = []

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        warnings.append(f"Unable to read config file {path}: {exc}")
        return values, warnings

    for line_no, raw_line in enumerate(lines, start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            warnings.append(
                f"Ignoring malformed config line {line_no} in {path} (missing '=')"
            )
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()

        if key in values:
            warnings.append(
                f"Duplicate key '{key}' on line {line_no} in {path}; last value wins"
            )

        values[key] = value

    return values, warnings


def _resolve(project_dir: Path) -> dict:
    warnings: list[str] = []
    config_path = _find_config_file(project_dir)

    source = None
    raw: dict[str, str] = {}
    if config_path is not None:
        source = str(config_path)
        raw, parse_warnings = _parse_config(config_path)
        warnings.extend(parse_warnings)

    # PROJECT_DIR
    raw_project_dir = raw.get("PROJECT_DIR")
    if raw_project_dir is not None:
        resolved_project_dir = str(Path(raw_project_dir).resolve())
    else:
        resolved_project_dir = str(project_dir)

    # TERMINAL_CMD
    terminal_cmd = raw.get("TERMINAL_CMD", DEFAULTS["TERMINAL_CMD"])

    # SESSION_LAYER
    session_layer = DEFAULTS["SESSION_LAYER"]
    raw_sl = raw.get("SESSION_LAYER")
    if raw_sl is not None:
        if raw_sl in ALLOWED_SESSION_LAYERS:
            session_layer = raw_sl
        else:
            warnings.append(
                f"Invalid SESSION_LAYER='{raw_sl}' "
                f"(allowed: {', '.join(sorted(ALLOWED_SESSION_LAYERS))}); "
                f"using default {DEFAULTS['SESSION_LAYER']}"
            )

    # VCS_ENABLED
    vcs_enabled = DEFAULTS["VCS_ENABLED"]
    raw_vcs = raw.get("VCS_ENABLED")
    if raw_vcs is not None:
        if raw_vcs.lower() in ALLOWED_BOOLEANS:
            vcs_enabled = raw_vcs.lower()
        else:
            warnings.append(
                f"Invalid VCS_ENABLED='{raw_vcs}' (allowed: true, false); "
                f"using default {DEFAULTS['VCS_ENABLED']}"
            )

    # Permission fields
    souffleur_permissions = DEFAULTS["SOUFFLEUR_PERMISSIONS"]
    raw_sp = raw.get("SOUFFLEUR_PERMISSIONS")
    if raw_sp is not None:
        if raw_sp in ALLOWED_PERMISSIONS:
            souffleur_permissions = raw_sp
        else:
            warnings.append(
                f"Invalid SOUFFLEUR_PERMISSIONS='{raw_sp}' "
                f"(allowed: {', '.join(sorted(ALLOWED_PERMISSIONS))}); "
                f"using default {DEFAULTS['SOUFFLEUR_PERMISSIONS']}"
            )

    musician_permissions = DEFAULTS["MUSICIAN_PERMISSIONS"]
    raw_mp = raw.get("MUSICIAN_PERMISSIONS")
    if raw_mp is not None:
        if raw_mp in ALLOWED_PERMISSIONS:
            musician_permissions = raw_mp
        else:
            warnings.append(
                f"Invalid MUSICIAN_PERMISSIONS='{raw_mp}' "
                f"(allowed: {', '.join(sorted(ALLOWED_PERMISSIONS))}); "
                f"using default {DEFAULTS['MUSICIAN_PERMISSIONS']}"
            )

    # Positive integer fields
    int_values = {}
    for key in POSITIVE_INT_KEYS:
        default = DEFAULTS[key]
        raw_val = raw.get(key)
        if raw_val is not None:
            try:
                parsed = int(raw_val)
                if parsed > 0:
                    int_values[key] = parsed
                else:
                    warnings.append(
                        f"Invalid {key}='{raw_val}' (must be positive integer); "
                        f"using default {default}"
                    )
                    int_values[key] = default
            except ValueError:
                warnings.append(
                    f"Invalid {key}='{raw_val}' (must be positive integer); "
                    f"using default {default}"
                )
                int_values[key] = default
        else:
            int_values[key] = default

    # Warn on unknown keys
    known = set(DEFAULTS.keys())
    for key in raw:
        if key not in known:
            warnings.append(f"Ignoring unknown config key '{key}'")

    return {
        "project_dir": resolved_project_dir,
        "project_name": Path(resolved_project_dir).name,
        "terminal_cmd": terminal_cmd,
        "session_layer": session_layer,
        "vcs_enabled": vcs_enabled == "true",
        "souffleur_permissions": souffleur_permissions,
        "musician_permissions": musician_permissions,
        "max_parallel_musicians": int_values["MAX_PARALLEL_MUSICIANS"],
        "degradation_fix_attempts": int_values["DEGRADATION_FIX_ATTEMPTS"],
        "degradation_relaunch_limit": int_values["DEGRADATION_RELAUNCH_LIMIT"],
        "heartbeat_poke_threshold": int_values["HEARTBEAT_POKE_THRESHOLD"],
        "source": source,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Conductor config resolver")
    parser.add_argument(
        "--project-dir",
        default=".",
        help="Project directory for .orchestra_configs lookup (default: cwd)",
    )
    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    result = _resolve(project_dir)

    for warning in result["warnings"]:
        print(f"Warning: {warning}", file=sys.stderr)

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Make script executable**

Run: `chmod +x skills/conductor/scripts/conductor-config.py`

- [ ] **Step 3: Test with no config file (defaults only)**

Run: `python3 skills/conductor/scripts/conductor-config.py --project-dir /tmp`
Expected: JSON output with all defaults, `"source": null`, empty warnings array.

- [ ] **Step 4: Test with a sample config file**

Create `temp/test-config/.orchestra_configs/conductor`:
```
# Test config
TERMINAL_CMD=alacritty
SESSION_LAYER=fifo
VCS_ENABLED=false
SOUFFLEUR_PERMISSIONS=bypassPermissions
BOGUS_KEY=whatever
```

Run: `python3 skills/conductor/scripts/conductor-config.py --project-dir temp/test-config`
Expected: JSON with overridden values, warning about unknown key `BOGUS_KEY`, `"source"` pointing to the config file.

- [ ] **Step 5: Test validation (invalid values)**

Create `temp/test-invalid/.orchestra_configs/conductor`:
```
SESSION_LAYER=screen
VCS_ENABLED=maybe
MAX_PARALLEL_MUSICIANS=-3
HEARTBEAT_POKE_THRESHOLD=abc
```

Run: `python3 skills/conductor/scripts/conductor-config.py --project-dir temp/test-invalid`
Expected: All defaults applied, 4 warnings on stderr about invalid values.

- [ ] **Step 6: Clean up test files and commit**

```bash
rm -rf temp/test-config temp/test-invalid
cd conductor && git add skills/conductor/scripts/conductor-config.py
git commit -m "feat: add conductor configuration resolver script"
```

---

### Task 2: Terminal Launch Script

**Files:**
- Create: `skills/conductor/scripts/launch-terminal.sh`

- [ ] **Step 1: Create the launch script**

```bash
#!/usr/bin/env bash
# launch-terminal.sh — Terminal-agnostic window launcher
# Usage: launch-terminal.sh --title "NAME" --dir "PATH" --cmd "COMMAND" [--close-on-exit]
#
# Reads TERMINAL_CMD from the environment (set by Conductor from config).
# Falls back to 'kitty' if unset.

set -euo pipefail

TERMINAL="${TERMINAL_CMD:-kitty}"
TITLE=""
DIR=""
CMD=""
CLOSE_ON_EXIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)  TITLE="$2";  shift 2 ;;
        --dir)    DIR="$2";    shift 2 ;;
        --cmd)    CMD="$2";    shift 2 ;;
        --close-on-exit) CLOSE_ON_EXIT=true; shift ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$CMD" ]]; then
    echo "Error: --cmd is required" >&2
    exit 1
fi

# Resolve terminal-specific flags
case "$TERMINAL" in
    kitty)
        ARGS=()
        [[ -n "$DIR" ]]   && ARGS+=(--directory "$DIR")
        [[ -n "$TITLE" ]] && ARGS+=(--title "$TITLE")
        kitty "${ARGS[@]}" -- bash -c "$CMD" &
        ;;
    alacritty)
        ARGS=()
        [[ -n "$DIR" ]]   && ARGS+=(--working-directory "$DIR")
        [[ -n "$TITLE" ]] && ARGS+=(--title "$TITLE")
        alacritty "${ARGS[@]}" -e bash -c "$CMD" &
        ;;
    foot)
        ARGS=()
        [[ -n "$DIR" ]]   && ARGS+=(--working-directory="$DIR")
        [[ -n "$TITLE" ]] && ARGS+=(--title="$TITLE")
        foot "${ARGS[@]}" bash -c "$CMD" &
        ;;
    *)
        # Generic fallback — attempt POSIX-ish invocation
        ARGS=()
        [[ -n "$DIR" ]] && ARGS+=(--working-directory "$DIR")
        [[ -n "$TITLE" ]] && ARGS+=(--title "$TITLE")
        "$TERMINAL" "${ARGS[@]}" bash -c "$CMD" &
        ;;
esac

# Print PID of the backgrounded terminal process
echo $!
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x skills/conductor/scripts/launch-terminal.sh
cd conductor && git add skills/conductor/scripts/launch-terminal.sh
git commit -m "feat: add terminal-agnostic launch script"
```

---

### Task 3: Session Layer Scripts

**Files:**
- Create: `skills/conductor/scripts/session-commands.sh`
- Create: `skills/conductor/scripts/session-fifo-loop.sh`

- [ ] **Step 1: Create session-commands.sh**

Shell functions for session lifecycle. Sourced by the Conductor via Bash tool.

```bash
#!/usr/bin/env bash
# session-commands.sh — Session layer abstraction (tmux/FIFO routing)
# Source this file, then call functions. Requires SESSION_LAYER and PROJECT_NAME in env.
#
# Functions:
#   create_session  SESSION_NAME [DIR]   — Create a new session (tmux or FIFO)
#   inject_session  SESSION_NAME CMD     — Inject a command into a running session
#   kill_claude_in_session SESSION_NAME  — Kill the Claude process inside a session
#   destroy_session SESSION_NAME         — Fully destroy a session and its window

set -euo pipefail

SESSION_LAYER="${SESSION_LAYER:-tmux}"
PROJECT_NAME="${PROJECT_NAME:-project}"
TEMP_DIR="${TEMP_DIR:-temp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_qualified_name() {
    echo "${PROJECT_NAME}-${1}"
}

# --- tmux backend ---

_tmux_create() {
    local name="$(_qualified_name "$1")"
    local dir="${2:-.}"
    tmux new-session -d -s "$name" -c "$dir"
}

_tmux_inject() {
    local name="$(_qualified_name "$1")"
    local cmd="$2"
    tmux send-keys -t "$name" "$cmd" Enter
}

_tmux_kill_claude() {
    local name="$(_qualified_name "$1")"
    local pane_pid
    pane_pid=$(tmux list-panes -t "$name" -F '#{pane_pid}' 2>/dev/null | head -1)
    if [[ -z "$pane_pid" ]]; then
        echo "Warning: Could not find pane PID for session $name" >&2
        return 1
    fi
    # Walk children to find claude process
    local claude_pid
    claude_pid=$(pgrep -P "$pane_pid" -f "claude" 2>/dev/null | head -1)
    if [[ -z "$claude_pid" ]]; then
        # Try one level deeper (bash -> claude)
        for child in $(pgrep -P "$pane_pid" 2>/dev/null); do
            claude_pid=$(pgrep -P "$child" -f "claude" 2>/dev/null | head -1)
            [[ -n "$claude_pid" ]] && break
        done
    fi
    if [[ -n "$claude_pid" ]]; then
        kill "$claude_pid" 2>/dev/null || true
    else
        echo "Warning: No claude process found in session $name" >&2
        return 1
    fi
}

_tmux_destroy() {
    local name="$(_qualified_name "$1")"
    tmux kill-session -t "$name" 2>/dev/null || true
}

# --- FIFO backend ---

_fifo_create() {
    local session_name="$1"
    local dir="${2:-.}"
    local fifo_path="${TEMP_DIR}/musician-${session_name}.fifo"
    # Store session metadata
    echo "$fifo_path" > "${TEMP_DIR}/session-${session_name}.name"
    # The FIFO loop script creates the FIFO itself on startup.
    # Launch it inside a terminal window via launch-terminal.sh.
    # The Conductor handles the terminal launch separately.
}

_fifo_inject() {
    local session_name="$1"
    local cmd="$2"
    local fifo_path="${TEMP_DIR}/musician-${session_name}.fifo"
    # Wait for FIFO to exist (loop script creates it on startup)
    local attempts=0
    while [[ ! -p "$fifo_path" ]] && [[ $attempts -lt 20 ]]; do
        sleep 0.5
        attempts=$((attempts + 1))
    done
    if [[ ! -p "$fifo_path" ]]; then
        echo "Error: FIFO $fifo_path not created within 10 seconds" >&2
        return 1
    fi
    echo "$cmd" > "$fifo_path"
}

_fifo_kill_claude() {
    local session_name="$1"
    local loop_pid_file="${TEMP_DIR}/fifo-loop-${session_name}.pid"
    if [[ ! -f "$loop_pid_file" ]]; then
        echo "Warning: No FIFO loop PID file for session $session_name" >&2
        return 1
    fi
    local loop_pid
    loop_pid=$(cat "$loop_pid_file")
    # Walk children to find claude process
    local claude_pid
    claude_pid=$(pgrep -P "$loop_pid" -f "claude" 2>/dev/null | head -1)
    if [[ -z "$claude_pid" ]]; then
        for child in $(pgrep -P "$loop_pid" 2>/dev/null); do
            claude_pid=$(pgrep -P "$child" -f "claude" 2>/dev/null | head -1)
            [[ -n "$claude_pid" ]] && break
        done
    fi
    if [[ -n "$claude_pid" ]]; then
        kill "$claude_pid" 2>/dev/null || true
    else
        echo "Warning: No claude process found for session $session_name" >&2
        return 1
    fi
}

_fifo_destroy() {
    local session_name="$1"
    local fifo_path="${TEMP_DIR}/musician-${session_name}.fifo"
    local loop_pid_file="${TEMP_DIR}/fifo-loop-${session_name}.pid"
    # Kill loop script if running
    if [[ -f "$loop_pid_file" ]]; then
        local loop_pid
        loop_pid=$(cat "$loop_pid_file")
        kill "$loop_pid" 2>/dev/null || true
        rm -f "$loop_pid_file"
    fi
    rm -f "$fifo_path"
    rm -f "${TEMP_DIR}/session-${session_name}.name"
}

# --- Public API (routes to backend) ---

create_session() {
    case "$SESSION_LAYER" in
        tmux) _tmux_create "$@" ;;
        fifo) _fifo_create "$@" ;;
        *)    echo "Error: Unknown SESSION_LAYER=$SESSION_LAYER" >&2; return 1 ;;
    esac
}

inject_session() {
    case "$SESSION_LAYER" in
        tmux) _tmux_inject "$@" ;;
        fifo) _fifo_inject "$@" ;;
        *)    echo "Error: Unknown SESSION_LAYER=$SESSION_LAYER" >&2; return 1 ;;
    esac
}

kill_claude_in_session() {
    case "$SESSION_LAYER" in
        tmux) _tmux_kill_claude "$@" ;;
        fifo) _fifo_kill_claude "$@" ;;
        *)    echo "Error: Unknown SESSION_LAYER=$SESSION_LAYER" >&2; return 1 ;;
    esac
}

destroy_session() {
    case "$SESSION_LAYER" in
        tmux) _tmux_destroy "$@" ;;
        fifo) _fifo_destroy "$@" ;;
        *)    echo "Error: Unknown SESSION_LAYER=$SESSION_LAYER" >&2; return 1 ;;
    esac
}

# Returns the command string to pass to launch-terminal.sh --cmd
# This is the bridge between the session layer and the terminal launcher.
get_terminal_cmd() {
    local session_name="$1"
    local qualified="$(_qualified_name "$session_name")"
    case "$SESSION_LAYER" in
        tmux)
            echo "tmux attach -t ${qualified}"
            ;;
        fifo)
            echo "bash ${SCRIPT_DIR}/session-fifo-loop.sh ${session_name} ${TEMP_DIR}"
            ;;
        *)
            echo "Error: Unknown SESSION_LAYER=$SESSION_LAYER" >&2
            return 1
            ;;
    esac
}
```

- [ ] **Step 2: Create session-fifo-loop.sh**

```bash
#!/usr/bin/env bash
# session-fifo-loop.sh — FIFO backend loop script
# Runs inside a terminal window. Creates a named FIFO, reads commands from it
# in a loop, executes each command, waits for exit, then reads next.
#
# Usage: session-fifo-loop.sh SESSION_NAME TEMP_DIR

set -uo pipefail

SESSION_NAME="${1:?Usage: session-fifo-loop.sh SESSION_NAME TEMP_DIR}"
TEMP_DIR="${2:-.}"
FIFO_PATH="${TEMP_DIR}/musician-${SESSION_NAME}.fifo"
PID_FILE="${TEMP_DIR}/fifo-loop-${SESSION_NAME}.pid"

# Write own PID for Conductor to discover
echo $$ > "$PID_FILE"

# Create FIFO (this script owns it)
mkfifo "$FIFO_PATH" 2>/dev/null || true

cleanup() {
    rm -f "$FIFO_PATH" "$PID_FILE"
    exit 0
}
trap cleanup EXIT INT TERM

echo "FIFO loop ready: $FIFO_PATH (PID $$)"

# Read loop — blocks on FIFO read until a command arrives
while true; do
    if read -r cmd < "$FIFO_PATH"; then
        if [[ -n "$cmd" ]]; then
            echo "--- Executing command ---"
            eval "$cmd"
            echo "--- Command exited with code $? ---"
        fi
    else
        # FIFO removed or broken pipe — exit
        break
    fi
done
```

- [ ] **Step 3: Make both executable and commit**

```bash
chmod +x skills/conductor/scripts/session-commands.sh
chmod +x skills/conductor/scripts/session-fifo-loop.sh
cd conductor && git add skills/conductor/scripts/session-commands.sh skills/conductor/scripts/session-fifo-loop.sh
git commit -m "feat: add session layer scripts (tmux + FIFO backends)"
```

---

### Task 4: Session Layer Reference File

**Files:**
- Create: `skills/conductor/references/session-layer.md`

- [ ] **Step 1: Create the reference file**

This file is loaded on demand only — pointed to from launch templates but not read during normal flow. It documents the mechanics for both backends.

```markdown
<skill name="conductor-session-layer" version="5.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Session Layer
</metadata>

<sections>
- purpose
- tmux-backend
- fifo-backend
- window-lifecycle
- pid-tracking
- terminal-launch-patterns
</sections>

<section id="purpose">
<core>
# Session Layer Reference

## Purpose

The session layer abstracts how the Conductor creates terminal windows, injects commands into them, kills Claude processes, and destroys sessions. Two backends are supported: tmux (default) and FIFO (fallback).

The Conductor interacts with sessions via `scripts/session-commands.sh`, which exposes four functions: `create_session`, `inject_session`, `kill_claude_in_session`, `destroy_session`. These route to the configured backend.

All launch templates in `phase-execution.md`, `musician-lifecycle.md`, and other reference files use the session layer instead of direct terminal commands. This file documents the backend-specific mechanics for troubleshooting and edge cases.

**Scripts:**
- `scripts/launch-terminal.sh` — Opens a terminal window (terminal-emulator-agnostic)
- `scripts/session-commands.sh` — Session lifecycle functions (source and call)
- `scripts/session-fifo-loop.sh` — FIFO backend loop (runs inside terminal windows)
</core>
</section>

<section id="tmux-backend">
<core>
## tmux Backend (SESSION_LAYER=tmux)

tmux is the default and recommended backend. Terminal windows attach to named tmux sessions — tmux owns the session, the terminal is a display layer.

### Session Naming

All tmux session names are namespaced with the project name (derived from `PROJECT_DIR` basename) to prevent collisions:
- Long-term primary: `${PROJECT_NAME}-musician-primary`
- Parallel temporaries: `${PROJECT_NAME}-musician-task-XX`
- Souffleur: `${PROJECT_NAME}-souffleur`
- Repetiteur: `${PROJECT_NAME}-repetiteur`

### Create Session + Terminal Window

```bash
# 1. Create session (tmux or FIFO depending on config)
source scripts/session-commands.sh
create_session "musician-primary" "$PROJECT_DIR"

# 2. Open terminal window with appropriate attach/loop command
ATTACH_CMD=$(get_terminal_cmd "musician-primary")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Musician: primary" \
    --dir "$PROJECT_DIR" \
    --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-musician-primary.pid
```

### Inject Command

```bash
inject_session "musician-primary" \
    "env -u CLAUDECODE claude --permission-mode $MUSICIAN_PERMISSIONS -p \"\$(cat temp/task-XX-prompt.txt)\""
```

Note: `env -u CLAUDECODE` unsets the CLAUDECODE environment variable to prevent nested Claude Code detection issues.

### Kill Claude (Preserve Session)

```bash
kill_claude_in_session "musician-primary"
# Shell returns to prompt (tmux) or FIFO read (fifo), ready for next injection
```

PID discovery: For tmux, `tmux list-panes -t SESSION -F '#{pane_pid}'` gives the shell PID. For FIFO, the loop script PID is read from `temp/fifo-loop-SESSION.pid`. In both cases, walk children via `pgrep -P` to find the `claude` process. Kill Claude only — the session persists.

### Destroy Session

```bash
destroy_session "musician-primary"
# Also kill the terminal window
PID=$(cat temp/window-musician-primary.pid)
kill "$PID" 2>/dev/null || true
rm -f temp/window-musician-primary.pid
```

### Resilience

If the terminal window is closed accidentally, the tmux session persists detached. The Conductor can still inject commands and kill Claude via tmux. To restore visibility, open a new terminal window attached to the session.
</core>
</section>

<section id="fifo-backend">
<core>
## FIFO Backend (SESSION_LAYER=fifo)

Fallback when tmux is not installed. Uses named pipes for command injection.

### Create Session + Terminal Window

```bash
# 1. Register session (FIFO is created by the loop script on startup)
source scripts/session-commands.sh
create_session "musician-primary" "$PROJECT_DIR"

# 2. Open terminal window — get_terminal_cmd returns the FIFO loop command
ATTACH_CMD=$(get_terminal_cmd "musician-primary")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Musician: primary" \
    --dir "$PROJECT_DIR" \
    --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-musician-primary.pid
```

### FIFO Ownership

The loop script (`session-fifo-loop.sh`) creates the FIFO on startup: `mkfifo temp/musician-SESSION.fifo`. The Conductor waits for the FIFO to exist (up to 10 seconds) before injecting. One owner, one consumer — no creation race.

### Loop Script PID Tracking

The loop script writes its own PID to `temp/fifo-loop-SESSION.pid` on startup. This gives the Conductor a reliable process tree root for Claude PID discovery, independent of terminal emulator process tree structure.

### Inject Command

```bash
inject_session "musician-primary" \
    "env -u CLAUDECODE claude --permission-mode $MUSICIAN_PERMISSIONS -p \"\$(cat temp/task-XX-prompt.txt)\""
```

Writes to the FIFO. The loop script reads the command, executes it, waits for exit, then blocks on next read.

### Write Sequencing

The loop script reads one command per iteration. It blocks until the previous command exits. The Conductor must kill the running Claude process before injecting the next command — writing while Claude is running blocks the write until Claude exits. This is the intended behavior for task rotation.

### Kill Claude (Preserve Session)

```bash
kill_claude_in_session "musician-primary"
# Loop script returns to FIFO read, ready for next command
```

### Destroy Session

```bash
destroy_session "musician-primary"
# Also kill the terminal window
PID=$(cat temp/window-musician-primary.pid)
kill "$PID" 2>/dev/null || true
rm -f temp/window-musician-primary.pid
```

Removing the FIFO file causes the loop script's next read to fail, exiting the loop.
</core>
</section>

<section id="window-lifecycle">
<core>
## Window Lifecycle

### Musician Windows

| Event | Long-term window | Parallel temp windows |
|-------|-----------------|----------------------|
| Phase start (sequential) | Create if doesn't exist | N/A |
| Phase start (parallel) | Reuse for task 1 | Create for tasks 2-N |
| Task rotation (sequential) | Kill Claude, inject next | N/A |
| Task complete (parallel) | Kill Claude, idle | Destroy window + session |
| Phase complete | Idle (awaits next phase) | Already destroyed |
| Project complete | Destroy | Already destroyed |

### Souffleur and Repetiteur

Single window each, created at launch, destroyed at completion or kill. No reuse pattern.
</core>
</section>

<section id="pid-tracking">
<core>
## PID Tracking Model

| File | Contents | Lifetime |
|------|----------|----------|
| `temp/window-musician-primary.pid` | Terminal window PID | Long-lived (project duration) |
| `temp/window-musician-task-XX.pid` | Terminal window PID | Temporary (parallel task duration) |
| `temp/window-souffleur.pid` | Terminal window PID | Souffleur lifetime |
| `temp/window-repetiteur.pid` | Terminal window PID | Repetiteur lifetime |
| `temp/session-SESSION.name` | Session identifier (tmux name or FIFO path) | Session lifetime |
| `temp/fifo-loop-SESSION.pid` | FIFO loop script PID (FIFO backend only) | Session lifetime |

Claude PIDs are discovered dynamically via process tree walking — not stored in files.
</core>
</section>

<section id="terminal-launch-patterns">
<core>
## Terminal Launch Patterns

`scripts/launch-terminal.sh` wraps terminal-specific invocation. It reads `TERMINAL_CMD` from the environment and translates standard flags.

Supported terminals: kitty, alacritty, foot. Others use a generic fallback.

The script outputs the terminal's PID to stdout. The Conductor captures it:

```bash
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "NAME" --dir "$PROJECT_DIR" --cmd "COMMAND")
echo "$WINDOW_PID" > temp/window-NAME.pid
```
</core>
</section>

</skill>
```

- [ ] **Step 2: Commit**

```bash
cd conductor && git add skills/conductor/references/session-layer.md
git commit -m "feat: add session layer reference file"
```

---

### Task 5: SKILL.md Updates

**Files:**
- Modify: `skills/conductor/SKILL.md`

- [ ] **Step 1: Add config and heartbeat mandatory rules**

In the `mandatory-rules` section, add after the existing rules:

```markdown
- Configuration resolver MUST run as Step 0 before all other initialization steps — resolved values are used by every subsequent protocol
- Messages from the heartbeat teammate are CRITICAL interrupts — drop current work immediately and address the heartbeat issue before returning to the interrupted task. A stale heartbeat means the Conductor is invisible to Musicians and approaching Souffleur kill threshold.
```

- [ ] **Step 2: Update the sections list**

Add to the `<sections>` block:
```
- infrastructure-degradation-protocol
```

- [ ] **Step 3: Add Infrastructure Degradation Protocol to protocol registry**

In the `protocol-registry` section's table, add:

```markdown
| **Infrastructure Degradation Protocol** | Self-healing and escalation for Conductor tool failures |
```

- [ ] **Step 4: Add the infrastructure-degradation-protocol section**

Add new section before `</skill>`:

```xml
<section id="infrastructure-degradation-protocol">
<core>
## Infrastructure Degradation Protocol

When the Conductor's own tools degrade during a long-running session — bash failures, MCP timeouts, comms-link unresponsiveness — this protocol provides a structured escalation from self-healing through Souffleur relaunch to critical failure. This is not about Musician errors (handled by Error Recovery Protocol) — it is about the Conductor's own infrastructure becoming unreliable.

Detection is heuristic: the same tool failing 3+ times in a row, multiple unrelated tools failing in a short window, or comms-link becoming unresponsive. When the Conductor recognizes a pattern of tool degradation, it enters this protocol.

The reference file defines a four-step escalation ladder. Step 1 (self-heal) is the most critical — the Conductor should exhaust available workarounds before escalating, because a Souffleur relaunch pauses the entire orchestration.

<mandatory>The self-heal step (Step 1) should attempt at least DEGRADATION_FIX_ATTEMPTS (default 5) different approaches before escalating. This is a minimum recommendation — more attempts are better. Escalate sooner only if self-healing is provably impossible (e.g., comms-link entirely unreachable).</mandatory>
</core>

<reference path="references/infrastructure-degradation.md" load="required">
Complete escalation ladder: self-heal strategies, Souffleur relaunch sequence (with critical ordering), post-relaunch fallback, critical failure procedure.
</reference>
</section>
```

- [ ] **Step 5: Update preamble — Three-Tier model context**

In the `preamble` section's `<context>` block under "Tier 2 — Subagents and Teammates:", add mention of the heartbeat teammate:

```markdown
Used for task instruction creation (Copyist teammate), monitoring (watcher subagent), heartbeat monitoring (heartbeat teammate), investigation (Explorer teammate), and focused work.
```

- [ ] **Step 6: Commit**

```bash
cd conductor && git add skills/conductor/SKILL.md
git commit -m "feat: add infrastructure degradation protocol and config/heartbeat mandatory rules"
```

---

### Task 6: Initialization Protocol Updates

**Files:**
- Modify: `skills/conductor/references/initialization.md`

This is the most heavily edited file. Changes: Step 0 config, hook removal, Step 2 VCS conditional, Step 4 rewrite, Souffleur launch with config, Step 9 renumber, heartbeat teammate section.

- [ ] **Step 1: Add config step to bootstrap-steps**

In the `bootstrap-steps` section, update the intro text:

```markdown
Execute these steps in order. Step 0 is config resolution (always first). Steps 1-5 are reads (parallelizable). Steps 6-9 are writes (sequential). Step 10 is the user gate.

### Step 0: Resolve Configuration

Run the config resolver to load all orchestration settings:

\`\`\`bash
python3 skills/conductor/scripts/conductor-config.py --project-dir "$(pwd)"
\`\`\`

Store the JSON output in-session. All subsequent steps reference config values by name. If no `.orchestra_configs/conductor` file exists, all defaults apply.
```

- [ ] **Step 2: Make Step 2 conditional on VCS_ENABLED**

Replace current Step 2 content with:

```markdown
### Step 2: VCS Check (Conditional)

**If `VCS_ENABLED` is true (default):** Verify not on main. Create feature branch if needed.

\`\`\`bash
bash scripts/check-git-branch.sh
\`\`\`

<mandatory>Never execute orchestration on the main branch when VCS is enabled.</mandatory>

**If `VCS_ENABLED` is false:** Skip. Log to terminal: "VCS checks disabled via config — skipping branch verification."
```

- [ ] **Step 3: Rewrite Step 3 (temp/ directory)**

Replace the `<mandatory>` about temp symlink:

```markdown
### Step 3: Verify temp/ Directory

Create `temp/` in the project root if missing.

<mandatory>ALL temporary and scratch files created by the Conductor MUST go in temp/ during execution — never /tmp/ or any other location.</mandatory>
```

- [ ] **Step 4: Rewrite Step 4 (Load Project Context)**

Replace the hardcoded README list:

```markdown
### Step 4: Load Project Context

Discover and read project documentation indexes:
1. Check for `docs/README.md` — read if present
2. Scan for other top-level READMEs in the project root — read if present
3. Skip gracefully if no documentation indexes exist

No hardcoded list — different projects have different structures. The goal is to gain enough project context for informed orchestration.
```

- [ ] **Step 5: Update Step 7 (Souffleur launch) to use config**

In the `souffleur-launch` section, replace the hardcoded launch command:

```markdown
### Launch Souffleur

\`\`\`bash
# Write Souffleur prompt to file
cat > temp/souffleur-prompt.txt << 'PROMPT'
/souffleur PID:$KITTY_PID SESSION_ID:$CLAUDE_SESSION_ID
PROMPT

# Launch via session layer
source scripts/session-commands.sh
create_session "souffleur" "$PROJECT_DIR"
ATTACH_CMD=$(get_terminal_cmd "souffleur")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Souffleur" \
    --dir "$PROJECT_DIR" \
    --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-souffleur.pid

inject_session "souffleur" \
    "env -u CLAUDECODE claude --permission-mode $SOUFFLEUR_PERMISSIONS -p \"\$(cat temp/souffleur-prompt.txt)\""
\`\`\`
```

Also replace the `$CLAUDE_SESSION_ID` explanation:

From: "`$CLAUDE_SESSION_ID` is a system prompt value injected by the SessionStart hook"
To: "`$CLAUDE_SESSION_ID` is available in the system prompt"

Also update the "Discover Own Kitty PID" subsection:
- Rename heading from "Discover Own Kitty PID" to "Discover Own Terminal PID"
- Replace "Walk the process tree to find the kitty PID" with "Walk the process tree to find the terminal window PID that owns this session"
- Replace `$KITTY_PID` with `$TERMINAL_PID` in the Souffleur prompt and launch commands
- Remove the "See RAG: kitty PID discovery" reference (replace with terminal-agnostic PID discovery using `$PPID` walk)

- [ ] **Step 6: Delete hook-verification section**

Remove the entire `<section id="hook-verification">` block (lines 527-542 approximately). Remove `hook-verification` from the `<sections>` list at the top of the file. Remove the old Step 9 (Verify Hooks) from the `bootstrap-steps` section.

- [ ] **Step 7: Update column-reference section**

In `session_id` row, change:
From: "Actual Claude Code session ID (set by SessionStart hook, injected into system prompt as $CLAUDE_SESSION_ID)"
To: "Actual Claude Code session ID (available in system prompt as $CLAUDE_SESSION_ID)"

- [ ] **Step 8: Update database-location section**

Replace the hardcoded path and description:

```markdown
## Database Location

Database is accessed exclusively via comms-link MCP. The Conductor does not need to know the database file path — comms-link abstracts the location.

<mandatory>All database operations MUST use comms-link MCP (query for SELECT, execute for writes). Direct sqlite3 CLI access creates WAL isolation issues — comms-link cannot see changes made by sqlite3 and vice versa.</mandatory>
```

- [ ] **Step 9: Add heartbeat-teammate-launch section**

Add new section after `message-watcher-launch`:

```xml
<section id="heartbeat-teammate-launch">
<mandatory>
## Step 9: Launch Heartbeat Teammate

After the message watcher is launched, create a permanent heartbeat teammate. This teammate monitors the Conductor's own heartbeat and sends CRITICAL interrupts via SendMessage if the heartbeat goes stale.

**Launch as a Team teammate** (not a regular subagent) with `model="opus"`:

Prompt:
\`\`\`
You are the Conductor's heartbeat watchdog. Your ONLY job is to monitor the Conductor's heartbeat and alert when it goes stale.

**Behavior:**
1. Poll task-00 heartbeat via comms-link every 60 seconds:
   SELECT last_heartbeat, (julianday('now') - julianday(last_heartbeat)) * 86400 AS seconds_stale
   FROM orchestration_tasks WHERE task_id = 'task-00';
2. If seconds_stale > {HEARTBEAT_POKE_THRESHOLD}: SendMessage to Conductor immediately
3. Message: "HEARTBEAT STALE: task-00 heartbeat is {N} seconds old. Message-watcher may be dead. Relaunch immediately."
4. If heartbeat is still stale after 2 more poll cycles: poke again with escalated urgency
5. Check for shutdown signal each cycle:
   SELECT id FROM orchestration_messages
   WHERE task_id = 'task-00' AND message = 'heartbeat_teammate_shutdown' AND message_type = 'system'
   ORDER BY id DESC LIMIT 1;
   If found: exit cleanly.

**CRITICAL: You are a SILENT watchdog. Send messages ONLY when the heartbeat is stale. Never send status updates, confirmations, or progress reports. Every message you send triggers a critical interrupt in the Conductor. Do not send unnecessary messages.**
\`\`\`

The heartbeat teammate runs for the entire Conductor session. Shutdown: Conductor inserts `heartbeat_teammate_shutdown` message during Completion Protocol.
</mandatory>
</section>
```

- [ ] **Step 10: Commit**

```bash
cd conductor && git add skills/conductor/references/initialization.md
git commit -m "feat: update initialization — config step, hook removal, VCS conditional, session layer, heartbeat teammate"
```

---

### Task 7: Phase Execution Protocol Updates

**Files:**
- Modify: `skills/conductor/references/phase-execution.md`

- [ ] **Step 1: Update musician-launch section**

Replace the hardcoded kitty launch template with the session layer pattern. The new template:

```markdown
### Launch Command

**Step 1: Write prompt to file**

\`\`\`bash
cat > temp/task-XX-prompt.txt << 'PROMPT'
/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
SELECT message FROM orchestration_messages WHERE task_id = '{task-id}' AND message_type = 'instruction';

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: {task-id}
- Phase: {PHASE_NUMBER} — {PHASE_NAME}

Do not proceed without reading the full instruction message. All steps are there.
PROMPT
\`\`\`

**Step 2: Launch via session layer**

For the long-term primary window (first task or sequential):
\`\`\`bash
source scripts/session-commands.sh
# Create session if it doesn't exist
create_session "musician-primary" "$PROJECT_DIR"
# Open terminal window if not already open
if [[ ! -f temp/window-musician-primary.pid ]] || ! kill -0 "$(cat temp/window-musician-primary.pid)" 2>/dev/null; then
    ATTACH_CMD=$(get_terminal_cmd "musician-primary")
    WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
        --title "Musician: primary" \
        --dir "$PROJECT_DIR" \
        --cmd "$ATTACH_CMD")
    echo "$WINDOW_PID" > temp/window-musician-primary.pid
fi
# Inject the claude command
inject_session "musician-primary" \
    "env -u CLAUDECODE claude --permission-mode $MUSICIAN_PERMISSIONS -p \"\$(cat temp/task-XX-prompt.txt)\""
\`\`\`

For parallel temporary windows (tasks 2-N):
\`\`\`bash
source scripts/session-commands.sh
create_session "musician-task-XX" "$PROJECT_DIR"
ATTACH_CMD=$(get_terminal_cmd "musician-task-XX")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Musician: task-XX" \
    --dir "$PROJECT_DIR" \
    --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-musician-task-XX.pid
inject_session "musician-task-XX" \
    "env -u CLAUDECODE claude --permission-mode $MUSICIAN_PERMISSIONS -p \"\$(cat temp/task-XX-prompt.txt)\""
\`\`\`

<reference path="references/session-layer.md" load="on-demand">
Session layer mechanics, backend-specific details, troubleshooting.
</reference>
```

- [ ] **Step 2: Update sequential-execution section**

Replace the hardcoded kitty launch in Step 3 with the same session layer pattern (primary window reuse). Update Step 6 cleanup to use `kill_claude_in_session` instead of direct PID kill.

- [ ] **Step 3: Update parallel-execution section**

Replace Step 6 (Launch Kitty Windows) with session layer launches. Add `MAX_PARALLEL_MUSICIANS` enforcement:

```markdown
**Step 6: Launch Sessions**

<mandatory>Check active session count before launching. If the phase has more tasks than MAX_PARALLEL_MUSICIANS, queue excess tasks and launch them as earlier tasks complete.</mandatory>

Launch one session per task via the session layer. Task 1 uses the long-term primary window; tasks 2-N get temporary windows.
```

- [ ] **Step 4: Update all remaining hardcoded launch templates**

Search for any remaining `kitty --directory` patterns in the file and replace with session layer calls.

- [ ] **Step 5: Commit**

```bash
cd conductor && git add skills/conductor/references/phase-execution.md
git commit -m "feat: update phase execution — session layer, prompt files, MAX_PARALLEL_MUSICIANS"
```

---

### Task 8: Musician Lifecycle Protocol Updates

**Files:**
- Modify: `skills/conductor/references/musician-lifecycle.md`

- [ ] **Step 1: Update pid-tracking section**

Replace the kitty PID tracking with the new model:

```markdown
## PID Tracking

**Window PIDs** (terminal process — managed via session layer):
- `temp/window-musician-primary.pid` — long-term primary window
- `temp/window-musician-task-XX.pid` — temporary parallel windows

**Session identifiers** (tmux name or FIFO path):
- `temp/session-musician-primary.name`
- `temp/session-musician-task-XX.name`

**Claude PIDs:** Discovered dynamically via `kill_claude_in_session` from `scripts/session-commands.sh`. Not stored in files.
```

- [ ] **Step 2: Update cleanup-rules section**

Replace direct `kill $PID` / `rm PID` commands with session layer calls:

```markdown
1. **Parallel tasks:** Destroy all temporary windows when ALL parallel siblings complete. The primary window's Claude process is killed but the window stays.
2. **Sequential tasks:** Kill Claude in the primary window immediately. The window stays for the next task.
3. **Re-launch (handoff):** Kill Claude in the session, then inject replacement command. Never have two Claude processes in the same session.
```

- [ ] **Step 3: Update all handoff procedures**

In `clean-handoff`, `dirty-handoff`, `crash-handoff` sections: replace `kill $PID` / `rm temp/musician-task-XX.pid` with `kill_claude_in_session SESSION_NAME`. For replacement launches, use `inject_session` instead of launching new kitty windows.

- [ ] **Step 4: Update replacement-session-launch section**

Replace the hardcoded kitty launch template with the session layer pattern. For primary window: `kill_claude_in_session` + `inject_session`. For temporary windows: `destroy_session` + full re-create.

- [ ] **Step 5: Update orphan cleanup references in guard-clause-reclaiming and claim-collision-recovery**

Replace `kill $PID` / `rm temp/musician-task-XX.pid` with `destroy_session` calls where appropriate.

- [ ] **Step 6: Commit**

```bash
cd conductor && git add skills/conductor/references/musician-lifecycle.md
git commit -m "feat: update musician lifecycle — session layer, window reuse model"
```

---

### Task 9: Compact Protocol Updates

**Files:**
- Modify: `skills/conductor/references/compact-protocol.md`

- [ ] **Step 1: Update JSONL sentinel path discovery**

In the `sequence` section Step 2 (Record Baseline), replace the hardcoded path:

```markdown
Discover the JSONL path dynamically:

\`\`\`bash
SENTINEL=$(ls ~/.claude/projects/*/${SESSION_ID}.jsonl 2>/dev/null | head -1)
if [[ -z "$SENTINEL" ]]; then
    # Retry with short delay (JSONL may not be created yet)
    for i in $(seq 1 6); do
        sleep 5
        SENTINEL=$(ls ~/.claude/projects/*/${SESSION_ID}.jsonl 2>/dev/null | head -1)
        [[ -n "$SENTINEL" ]] && break
    done
fi
if [[ -z "$SENTINEL" ]]; then
    # Compact failure — fall back to fresh-session launch
    echo "JSONL not found for session $SESSION_ID — compact cannot proceed"
    # Route to failure-handling section
fi
BASELINE_LINES=$(wc -l < "$SENTINEL")
```

Cache the resolved path for reuse within the same compact cycle.

- [ ] **Step 2: Update launch commands to use session layer**

Replace kitty launch commands in Steps 4 and 6 with session layer calls. Use `inject_session` for the compact command and for the resume command.

- [ ] **Step 3: Update PID tracking references**

Replace `temp/musician-task-XX.pid` references with session layer PID model.

- [ ] **Step 4: Commit**

```bash
cd conductor && git add skills/conductor/references/compact-protocol.md
git commit -m "feat: update compact protocol — JSONL glob discovery, session layer"
```

---

### Task 10: Repetiteur Invocation Updates

**Files:**
- Modify: `skills/conductor/references/repetiteur-invocation.md`

- [ ] **Step 1: Update spawn-prompt-template section**

Replace the hardcoded kitty launch command:

```markdown
### Launch Command

\`\`\`bash
# Write repetiteur prompt to file
cat > temp/repetiteur-prompt.txt << 'PROMPT'
/repetiteur
{structured blocker report content}
PROMPT

# Launch via session layer
source scripts/session-commands.sh
create_session "repetiteur" "$PROJECT_DIR"
ATTACH_CMD=$(get_terminal_cmd "repetiteur")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "Repetiteur" \
    --dir "$PROJECT_DIR" \
    --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-repetiteur.pid

inject_session "repetiteur" \
    "env -u CLAUDECODE claude --permission-mode acceptEdits -p \"\$(cat temp/repetiteur-prompt.txt)\""
\`\`\`
```

- [ ] **Step 2: Update PID references**

Replace `temp/repetiteur.pid` with `temp/window-repetiteur.pid` throughout.

- [ ] **Step 3: Commit**

```bash
cd conductor && git add skills/conductor/references/repetiteur-invocation.md
git commit -m "feat: update repetiteur invocation — session layer, prompt file"
```

---

### Task 11: Recovery Bootstrap Updates

**Files:**
- Modify: `skills/conductor/references/recovery-bootstrap.md`

- [ ] **Step 1: Remove hook verification from state-reconstruction**

In the `state-reconstruction` section, Parallel group 2, remove:
```
- Hook verification: confirm `hooks.json`, `session-start-hook.sh`, `stop-hook.sh` exist; verify `comms.db` accessible via comms-link
```

Replace with:
```
- Database verification: verify `comms.db` accessible via comms-link (simple SELECT)
```

- [ ] **Step 2: Update crash-scenario fallback READMEs in handoff-reading**

In the `handoff-reading` section, replace the hardcoded README list (items 5-9):

From:
```
5. `docs/README.md`
6. `docs/knowledge-base/README.md`
7. `docs/implementation/README.md`
8. `docs/implementation/proposals/README.md`
9. `docs/scratchpad/README.md`
```

To:
```
5. `docs/README.md` (if present)
6. Scan for other top-level READMEs in the project root (if present)
```

- [ ] **Step 3: Update orphan session cleanup PID references**

In the `musician-triage` section, update the orphan cleanup to use the new PID file naming:

From: `temp/musician-task-XX.pid`
To: `temp/window-musician-task-XX.pid` for parallel tasks, `temp/window-musician-primary.pid` for the primary window.

Also update to use session layer cleanup: `source scripts/session-commands.sh; destroy_session "musician-task-XX"` instead of direct `kill $PID`.

- [ ] **Step 4: Commit**

```bash
cd conductor && git add skills/conductor/references/recovery-bootstrap.md
git commit -m "feat: update recovery bootstrap — remove hooks, dynamic project discovery, session layer PIDs"
```

---

### Task 12: Error Recovery + Validation Script Updates

**Files:**
- Modify: `skills/conductor/references/error-recovery.md`
- Modify: `skills/conductor/scripts/validate-coordination.sh`

- [ ] **Step 1: Add infrastructure degradation pointer to error-recovery.md**

In an appropriate location (near the `entry-points` or `error-classification` section), add a note:

```markdown
**Tool-level failures (Conductor's own infrastructure):** If the Conductor itself encounters repeated tool failures (bash, MCP, comms-link), this is NOT a Musician error. Route to the Infrastructure Degradation Protocol via SKILL.md — do not attempt to handle Conductor tool degradation through this protocol's Musician-focused recovery flows.
```

- [ ] **Step 2: Update validate-coordination.sh**

Replace the hardcoded database path default:

From: `DB="${1:-/home/kyle/claude/remindly/comms.db}"`
To: `DB="${1:-comms.db}"`

Note: This script uses direct sqlite3 which has WAL isolation issues with comms-link. Add a comment noting this limitation:

```bash
# NOTE: This script uses sqlite3 directly as a diagnostic fallback.
# For production orchestration, always use comms-link MCP.
# Direct sqlite3 may not see recent comms-link writes (WAL isolation).
DB="${1:-comms.db}"
```

- [ ] **Step 3: Commit**

```bash
cd conductor && git add skills/conductor/references/error-recovery.md skills/conductor/scripts/validate-coordination.sh
git commit -m "feat: add infrastructure degradation pointer, update validation script paths"
```

---

## Wave 2: Extend

### Task 13: Infrastructure Degradation Protocol Reference

**Files:**
- Create: `skills/conductor/references/infrastructure-degradation.md`

- [ ] **Step 1: Create the reference file**

```markdown
<skill name="conductor-infrastructure-degradation" version="5.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Infrastructure Degradation Protocol
</metadata>

<sections>
- detection
- escalation-ladder
- step-1-self-heal
- step-2-souffleur-relaunch
- step-3-post-relaunch
- step-4-critical-failure
- integration
</sections>

<section id="detection">
<core>
# Infrastructure Degradation Protocol

## Detection Criteria

The Conductor enters this protocol when it recognizes a pattern of tool degradation — not a single failure (that is a retry), but a systemic pattern.

**Triggers:**
- Same tool fails 3+ times in a row with non-task-related errors (e.g., bash returning "command not found" for a previously working command, MCP timeout on a tool that was working minutes ago)
- Multiple unrelated tools fail within a short window (systemic degradation — the session environment is breaking down)
- comms-link becomes unresponsive (most critical — this is the orchestration backbone; without it, the Conductor cannot monitor Musicians, send messages, or update state)

**Not triggers:**
- A single tool failure (retry normally)
- Musician-reported errors (route to Error Recovery Protocol)
- Expected failures (e.g., a file not found when checking if something exists)
</core>
</section>

<section id="escalation-ladder">
<core>
## Escalation Ladder

```
Step 1: Self-heal ──→ resolved? ──→ return to previous work
         │ no
         ▼
Step 2: Souffleur relaunch ──→ resolved? ──→ continue orchestration
         │ no (limit reached)
         ▼
Step 3: Post-relaunch workarounds ──→ resolved? ──→ continue
         │ no
         ▼
Step 4: Critical failure ──→ pause Musicians, report to user
```

Each step is described in its own section below.
</core>
</section>

<section id="step-1-self-heal">
<core>
## Step 1: Self-Heal

<mandatory>
The self-heal step is the most important step in this ladder. A Souffleur relaunch is disruptive — it pauses the entire orchestration, kills the Conductor session, and requires a full recovery bootstrap. The Conductor should treat escalation to Step 2 as a last resort, not a convenience.

Attempt at least DEGRADATION_FIX_ATTEMPTS (default 5) different approaches before escalating. This is a minimum recommendation, not a ceiling — more attempts are better. The Conductor may escalate sooner only if self-healing is provably impossible (e.g., comms-link is entirely unreachable after multiple connection attempts).
</mandatory>

**The Conductor determines approach.** No prescribed fixes — the right workaround depends on what is actually broken. Examples of self-heal strategies:

- **MCP timeout:** Retry with backoff. Try a simpler query first. Check if the MCP server process is alive.
- **Bash failures:** Try alternative commands. Check if PATH is correct. Try absolute paths.
- **comms-link unresponsive:** Retry connection. Check if the database file is accessible. Try a simple SELECT 1 query.
- **Multiple tools failing:** Consider whether the session environment is corrupted. Try resetting tool state.

**If resolved:** Return to the work that was in progress when degradation was detected.

**If still failing after thorough attempts:** Proceed to Step 2.
</core>
</section>

<section id="step-2-souffleur-relaunch">
<mandatory>
## Step 2: Request Souffleur Relaunch

ORDERING IS CRITICAL — follow the same sequence as the existing context-exhaustion-trigger in error-recovery.md. The state change is the Souffleur's kill trigger — once set, the Conductor may be killed at any moment. All persistent writes must complete first.

1. **Write learnings:** Append degradation details to `temp/conductor-learnings.log`:
   ```
   [{timestamp}] INFRASTRUCTURE DEGRADATION: {tool} failed {N} times. Attempted fixes: {list}. Requesting Souffleur relaunch.
   ```

2. **Insert message:** Record the degradation in orchestration_messages:
   ```sql
   INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
       'task-00', '$CLAUDE_SESSION_ID',
       'INFRASTRUCTURE DEGRADATION: Conductor tools degraded. Tool: {tool}. Failures: {N}. Self-heal attempts: {N}. Requesting relaunch.',
       'system'
   );
   ```

3. **Set state:** Trigger the Souffleur kill:
   ```sql
   UPDATE orchestration_tasks
   SET state = 'context_recovery', last_heartbeat = datetime('now')
   WHERE task_id = 'task-00';
   ```

The Souffleur detects the state change, kills the session, and relaunches via recovery bootstrap. The degradation context in the learnings file is preserved and read by the new Conductor during recovery Step 3.
</mandatory>
</section>

<section id="step-3-post-relaunch">
<core>
## Step 3: Post-Relaunch Fallback

If the same tool failures recur after a Souffleur relaunch, the problem may be environmental rather than session-specific. After DEGRADATION_RELAUNCH_LIMIT (default 2) failed relaunches, try any remaining workarounds not yet attempted.

The recovery bootstrap's learnings file reading (Step 3 in recovery-bootstrap.md) provides the history of what was tried. The new Conductor session should:

1. Read the degradation entries from `temp/conductor-learnings.log`
2. Try different approaches than what was already attempted
3. If resolved: continue orchestration normally

If no new approaches are available: proceed to Step 4.
</core>
</section>

<section id="step-4-critical-failure">
<mandatory>
## Step 4: Critical Failure

All self-heal options and Souffleur relaunches exhausted. The orchestration cannot continue autonomously.

1. **Pause all Musicians:** Send emergency broadcast to all active tasks:
   ```sql
   INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
   VALUES ('{task-id}', 'task-00',
       'EMERGENCY: Conductor infrastructure critically degraded. All work paused. Awaiting user intervention.',
       'emergency');
   ```
   (One INSERT per active task_id.)

2. **Terminal output:** Print a clear summary for the user:
   ```
   === CRITICAL: Infrastructure Degradation ===
   Tool(s) failing: {list}
   Self-heal attempts: {N}
   Souffleur relaunches: {N}
   What was tried: {summary}

   The orchestration cannot continue automatically.
   Please investigate the tool failures and restart the Conductor.
   =============================================
   ```

3. **Set state:**
   ```sql
   UPDATE orchestration_tasks
   SET state = 'exit_requested', last_heartbeat = datetime('now')
   WHERE task_id = 'task-00';
   ```
</mandatory>
</section>

<section id="integration">
<core>
## Integration with Other Protocols

**Error Recovery Protocol:** Infrastructure degradation is distinct from Musician errors. If the Conductor encounters tool failures while handling a Musician error, it enters this protocol, resolves the tool issue, then returns to error recovery. The two protocols do not overlap — one handles Musician problems, the other handles Conductor problems.

**Recovery Bootstrap Protocol:** No changes needed. The recovery bootstrap already reads `temp/conductor-learnings.log` (Step 3) and reconstructs state from the database. Degradation context flows naturally through the existing recovery pipeline.

**Completion Protocol:** If the Conductor detects degradation during the completion phase, it should still attempt self-healing. Escalating to Souffleur relaunch during completion is wasteful — the work is done, only final verification remains. Prefer reporting the degradation to the user and letting them decide.
</core>
</section>

</skill>
```

- [ ] **Step 2: Commit**

```bash
cd conductor && git add skills/conductor/references/infrastructure-degradation.md
git commit -m "feat: add infrastructure degradation protocol reference"
```

---

### Task 14: Completion Protocol Updates

**Files:**
- Modify: `skills/conductor/references/completion.md`

- [ ] **Step 1: Read completion.md**

Read the current file to understand its structure before editing.

- [ ] **Step 2: Add heartbeat teammate shutdown**

In the completion procedure (before or alongside existing cleanup steps), add:

```markdown
### Shutdown Heartbeat Teammate

Insert the shutdown signal for the heartbeat teammate:

\`\`\`sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-00', 'task-00',
    'heartbeat_teammate_shutdown',
    'system'
);
\`\`\`

The heartbeat teammate detects this message on its next poll cycle and exits cleanly.
```

- [ ] **Step 3: Update close-musician-windows section**

Replace all "kitty windows" references with "Musician windows/sessions". Replace the cleanup commands:

From:
```bash
kill $(cat temp/musician-{task-id}.pid)
rm -f temp/musician-{task-id}.pid
```

To:
```bash
source scripts/session-commands.sh
# Destroy the long-term primary window
destroy_session "musician-primary"
PID=$(cat temp/window-musician-primary.pid 2>/dev/null)
[[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true
rm -f temp/window-musician-primary.pid
```

Replace "Close all remaining Musician kitty windows" with "Close all remaining Musician sessions and windows."

- [ ] **Step 4: Commit**

```bash
cd conductor && git add skills/conductor/references/completion.md
git commit -m "feat: update completion protocol — heartbeat shutdown, session layer cleanup"
```

---

### Task 15: Remaining Reference File Cleanup

Catch-all task for reference files that need path/PID/hook updates not covered by earlier tasks.

**Files:**
- Modify: `skills/conductor/references/error-recovery.md`
- Modify: `skills/conductor/references/sentinel-monitoring.md`
- Modify: `skills/conductor/examples/conductor-initialization.md`
- Modify: `skills/conductor/examples/launching-execution-sessions.md`
- Modify: `skills/conductor/examples/monitoring-subagent-prompts.md` (if applicable)

- [ ] **Step 1: Update error-recovery.md — PID patterns and kitty references**

Search for `temp/musician-task-XX.pid` and `kitty` in the file. Update:
- `stale-heartbeat-recovery` section: replace `PID=$(cat temp/musician-task-XX.pid 2>/dev/null)` with session layer cleanup (`source scripts/session-commands.sh; kill_claude_in_session "musician-task-XX"`)
- `claim-failure-recovery` section: replace "Close the failed Musician's kitty window (read PID file, SIGTERM, remove PID file)" with "Close the failed Musician's session via `destroy_session`"
- `context-exhaustion-trigger` section: replace `kill -0 $(cat temp/musician-{task_id}.pid)` / `rm temp/musician-{task_id}.pid` with session layer calls
- Remove or revise any "stop hook blocks session exit" references (these are obsolete after hook removal)

- [ ] **Step 2: Update sentinel-monitoring.md — PID pattern**

Replace `temp/musician-task-{NN}.pid` reference with `temp/window-musician-task-XX.pid` or session layer references as appropriate.

- [ ] **Step 3: Update example files**

Example files are illustrative — they show patterns, not exact templates. Update them to use session layer patterns:
- `examples/conductor-initialization.md`: Replace hardcoded `kitty --directory /home/kyle/claude/remindly` with session layer patterns. Replace hook verification walkthrough with a note that hooks are no longer verified.
- `examples/launching-execution-sessions.md`: Replace hardcoded kitty commands with session layer patterns. Update PID file references.
- Check other example files for hardcoded paths and update similarly.

- [ ] **Step 4: Update SKILL.md initialization-protocol reference pointer text**

In SKILL.md, the `initialization-protocol` section's reference pointer says:
```
Complete bootstrap sequence: database DDL, plan loading, plan-index verification, git branch setup, MEMORY.md tracking, hook verification, environment checks.
```

Remove "hook verification" from this description.

- [ ] **Step 5: Commit**

```bash
cd conductor && git add skills/conductor/references/error-recovery.md \
    skills/conductor/references/sentinel-monitoring.md \
    skills/conductor/examples/ \
    skills/conductor/SKILL.md
git commit -m "fix: update remaining files — session layer, PID patterns, hook removal"
```

---

### Task 16: Final Validation Pass

**Files:**
- All modified files (read-only verification)

- [ ] **Step 1: Grep for remaining hardcoded paths**

```bash
cd conductor && grep -rn "/home/kyle/claude/remindly" skills/conductor/
```

Expected: Zero results. If any remain, fix them.

- [ ] **Step 2: Grep for remaining hook references**

```bash
grep -rn "hooks.json\|session-start-hook\|stop-hook" skills/conductor/
```

Expected: Zero results (or only the old-table-names section if it was preserved as a historical note).

- [ ] **Step 3: Grep for remaining bare kitty commands**

```bash
grep -rn "^kitty \|kitty --directory" skills/conductor/
```

Expected: Zero results. All kitty references should be inside `launch-terminal.sh` or in the session-layer reference as documentation.

- [ ] **Step 4: Grep for old PID file pattern**

```bash
grep -rn "temp/musician-task-.*\.pid" skills/conductor/ | grep -v "window-musician"
```

Expected: Zero results. All should use the new `temp/window-musician-*` pattern.

- [ ] **Step 5: Verify section lists match actual sections**

For each reference file, check that the `<sections>` list at the top matches the actual `<section id="">` tags in the file. Any mismatch means a section was added or removed without updating the list.

- [ ] **Step 6: Run validate-coordination.sh**

```bash
bash skills/conductor/scripts/validate-coordination.sh
```

Verify it runs without referencing hardcoded paths (should use `comms.db` default or accept argument).

- [ ] **Step 7: Final commit if any fixes were needed**

```bash
cd conductor && git add -A
git commit -m "fix: address remaining hardcoded references found in validation pass"
```
