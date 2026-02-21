#!/usr/bin/env bash
# validate-coordination.sh — Check database state and report task statuses
# Usage: bash ~/.claude/skills/conductor/scripts/validate-coordination.sh [db_path]

DB="${1:-/home/kyle/claude/remindly/comms.db}"

if [ ! -f "$DB" ]; then
    echo "ERROR: Database not found at $DB"
    exit 1
fi

echo "=== Orchestration Database Validation ==="
echo "Database: $DB"
echo ""

# Check tables exist
echo "--- Table Check ---"
TASKS_EXISTS=$(sqlite3 "$DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='orchestration_tasks';")
MSGS_EXISTS=$(sqlite3 "$DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='orchestration_messages';")

if [ "$TASKS_EXISTS" -eq 0 ]; then
    echo "ERROR: orchestration_tasks table does not exist"
    exit 1
fi
if [ "$MSGS_EXISTS" -eq 0 ]; then
    echo "ERROR: orchestration_messages table does not exist"
    exit 1
fi
echo "orchestration_tasks: EXISTS"
echo "orchestration_messages: EXISTS"
echo ""

# Report task statuses
echo "--- Task Statuses ---"
sqlite3 -header -column "$DB" "
SELECT task_id, state, retry_count,
       CASE
           WHEN last_heartbeat IS NULL THEN 'N/A'
           ELSE CAST(ROUND((julianday('now') - julianday(last_heartbeat)) * 86400) AS INTEGER) || 's ago'
       END as heartbeat_age
FROM orchestration_tasks
ORDER BY task_id;
"
echo ""

# Count by state
echo "--- State Summary ---"
sqlite3 -header -column "$DB" "
SELECT state, COUNT(*) as count
FROM orchestration_tasks
GROUP BY state
ORDER BY count DESC;
"
echo ""

# Check for stale sessions
echo "--- Staleness Check ---"
STALE=$(sqlite3 "$DB" "
SELECT COUNT(*)
FROM orchestration_tasks
WHERE state IN ('working', 'review_approved', 'review_failed', 'fix_proposed')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
")
if [ "$STALE" -gt 0 ]; then
    echo "WARNING: $STALE stale session(s) detected:"
    sqlite3 -header -column "$DB" "
    SELECT task_id, state,
           CAST(ROUND((julianday('now') - julianday(last_heartbeat)) * 86400) AS INTEGER) as seconds_stale
    FROM orchestration_tasks
    WHERE state IN ('working', 'review_approved', 'review_failed', 'fix_proposed')
      AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
    "
else
    echo "No stale sessions detected"
fi
echo ""

# Recent messages
echo "--- Recent Messages (last 5) ---"
sqlite3 -header -column "$DB" "
SELECT id, task_id, from_session, substr(message, 1, 80) as message_preview, timestamp
FROM orchestration_messages
ORDER BY timestamp DESC
LIMIT 5;
"
echo ""

echo "=== Validation Complete ==="
