#!/usr/bin/env bash
# check-git-branch.sh — Verify not on main branch, report current branch
# Usage: bash ~/.claude/skills/conductor/scripts/check-git-branch.sh

CURRENT=$(git branch --show-current 2>/dev/null)

if [ -z "$CURRENT" ]; then
    echo "ERROR: Not in a git repository or detached HEAD"
    exit 1
fi

echo "Current branch: $CURRENT"

if [ "$CURRENT" = "main" ] || [ "$CURRENT" = "master" ]; then
    echo "WARNING: On $CURRENT branch — create a feature branch before proceeding"
    echo ""
    echo "Suggested:"
    echo "  git checkout -b feat/<plan-name>"
    exit 1
else
    echo "OK: Not on main/master"
    exit 0
fi
