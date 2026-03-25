#!/usr/bin/env bash
# session-commands.sh — Session layer abstraction (tmux/FIFO routing)
# Source this file, then call functions. Requires SESSION_LAYER and PROJECT_NAME in env.
#
# Functions:
#   create_session  SESSION_NAME [DIR]   — Create a new session (tmux or FIFO)
#   inject_session  SESSION_NAME CMD     — Inject a command into a running session
#   kill_claude_in_session SESSION_NAME  — Kill the Claude process inside a session
#   destroy_session SESSION_NAME         — Fully destroy a session and its window
#   get_terminal_cmd SESSION_NAME        — Return the --cmd string for launch-terminal.sh

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

_tmux_terminal_cmd() {
    local name="$(_qualified_name "$1")"
    echo "tmux attach -t ${name}"
}

# --- FIFO backend ---

_fifo_create() {
    local session_name="$1"
    local dir="${2:-.}"
    local fifo_path="${TEMP_DIR}/musician-${session_name}.fifo"
    # Store session metadata
    echo "$fifo_path" > "${TEMP_DIR}/session-${session_name}.name"
    # The FIFO loop script creates the FIFO itself on startup.
    # The Conductor launches the terminal window separately via launch-terminal.sh
    # with the command from get_terminal_cmd.
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

_fifo_terminal_cmd() {
    local session_name="$1"
    echo "bash ${SCRIPT_DIR}/session-fifo-loop.sh ${session_name} ${TEMP_DIR}"
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
    case "$SESSION_LAYER" in
        tmux) _tmux_terminal_cmd "$@" ;;
        fifo) _fifo_terminal_cmd "$@" ;;
        *)    echo "Error: Unknown SESSION_LAYER=$SESSION_LAYER" >&2; return 1 ;;
    esac
}
