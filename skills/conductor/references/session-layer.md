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

The Conductor interacts with sessions via `scripts/session-commands.sh`, which exposes five functions: `create_session`, `inject_session`, `kill_claude_in_session`, `destroy_session`, and `get_terminal_cmd`. These route to the configured backend.

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
ATTACH_CMD=$(get_terminal_cmd "SESSION_NAME")
WINDOW_PID=$(TERMINAL_CMD=$TERMINAL_CMD scripts/launch-terminal.sh \
    --title "NAME" --dir "$PROJECT_DIR" --cmd "$ATTACH_CMD")
echo "$WINDOW_PID" > temp/window-NAME.pid
```
</core>
</section>

</skill>
