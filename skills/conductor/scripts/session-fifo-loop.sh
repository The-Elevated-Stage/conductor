#!/usr/bin/env bash
# session-fifo-loop.sh — FIFO backend loop script
# Runs inside a terminal window. Creates a named FIFO, reads commands from it
# in a loop, executes each command, waits for exit, then reads next.
#
# Usage: session-fifo-loop.sh SESSION_NAME TEMP_DIR
#
# Note: -e is intentionally omitted from set flags — eval'd commands may return
# non-zero and should not kill the loop.

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
