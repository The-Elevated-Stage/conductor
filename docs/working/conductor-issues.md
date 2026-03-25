# Conductor Skill Issues

Issues encountered while using the Conductor skill for the hockey simulation project.

## 1. SessionStart Hook Obsolete (2026-03-24)

The conductor skill references `tools/implementation-hook/session-start-hook.sh` and `hooks.json` as infrastructure to verify during initialization (Step 8). The SessionStart hook that injects `CLAUDE_SESSION_ID` via `additionalContext` is obsolete — user confirmed it should be completely ignored. The session ID is already available in the system prompt without any hook.

The skill's Step 8 verification checklist should not require this hook's existence.

## 2. Git-Centric Assumptions (2026-03-24)

The conductor skill assumes Git throughout:
- Step 2 references `scripts/check-git-branch.sh` and "not on main" git branch checks
- References to git worktrees, git branches, git push
- The `isolation: "worktree"` agent parameter assumes git

This project uses Plastic SCM. Had to adapt Step 2 to use `cm branch create` and `cm switch` instead. The skill should be VCS-agnostic or have adapter patterns.

## 3. Hardcoded Project Paths in References (2026-03-24)

`references/database-queries.md` hardcodes `/home/kyle/claude/remindly/comms.db` as the database location. The comms-link MCP server manages this transparently, but the stop hook references use direct sqlite3 with hardcoded paths. This couples the skill to the remindly project.

## 4. Stop Hook Uses Wrong DB Path (2026-03-24)

The stop hook at `remindly/tools/implementation-hook/stop-hook.sh` uses `DB_PATH="$PROJECT_DIR/database.db"` but the comms-link MCP uses `comms.db`. These are different databases. The stop hook would not find orchestration tasks. This needs alignment.

## 5. Kitty Terminal Assumed Available (2026-03-24)

The conductor skill assumes `kitty` is installed for launching musician sessions. The launch template hardcodes `kitty --directory ...`. In a distrobox container, kitty may not be installed and host terminal access requires `distrobox-host-exec`. The skill should document kitty as a prerequisite or support alternative launch methods (screen, tmux, or generic terminal launchers).

## 6. Completed Musician Sessions Don't Exit (2026-03-24)

Without a working stop hook, musician sessions that complete their tasks (set state to 'complete') remain idle in their kitty windows. This means stale claude processes accumulate, potentially preventing new sessions from launching. The conductor must manually kill completed session processes before launching new ones. This caused task-09 and task-11 to fail twice — kitty windows opened but claude couldn't start inside them due to resource constraints from stale sessions.

**Workaround:** After a task completes, kill its kitty process before launching new sessions. Consider implementing a cleanup step in the monitoring cycle.

## 7. Kitty Direct Prompt Argument Fails Silently (2026-03-24)

The conductor skill's launch template passes the musician prompt directly as a command-line argument to `claude` via `kitty -- env -u CLAUDECODE claude --permission-mode acceptEdits "prompt"`. This worked for earlier tasks but failed silently for task-09 and task-11 — kitty opened but claude never started. No error was visible.

**Root cause:** Likely shell escaping issues with backticks and special characters in the prompt when passed as a direct argument through kitty's `--` separator.

**Working alternative:** Write the prompt to a file, then launch with:
```bash
kitty --title "Musician: task-XX" -- bash -c 'cd /path/to/project && env -u CLAUDECODE claude --permission-mode acceptEdits -p "$(cat temp/task-XX-prompt.txt)"' &
```
This avoids shell escaping issues by reading the prompt from a file.
