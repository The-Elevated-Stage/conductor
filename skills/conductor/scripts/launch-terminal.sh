#!/usr/bin/env bash
# launch-terminal.sh — Terminal-agnostic window launcher
# Usage: launch-terminal.sh --title "NAME" --dir "PATH" --cmd "COMMAND" [--close-on-exit]
#
# Reads TERMINAL_CMD from the environment (set by Conductor from config).
# Falls back to 'kitty' if unset.
#
# Outputs the PID of the backgrounded terminal process to stdout.

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
