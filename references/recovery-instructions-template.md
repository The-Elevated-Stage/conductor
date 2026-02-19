# Recovery Instructions Template

Use this simple format when exiting the conductor session due to context management (step 3 in Context Management section).

Record these in STATUS.md under "Recovery Instructions" section for the resuming conductor session.

## Format

```markdown
## Recovery Instructions

**Timestamp:** 2026-02-10 14:35:00 UTC
**Context usage at exit:** 87%
**Reason for exit:** Context approaching limit (> 80%)

**Last checkpoint reached:** Phase 2 completion review
**Monitoring cycle status:** Just completed handling task-04 review, relaunching watcher

**Active tasks and states:**
- task-01: complete
- task-02: complete
- task-03: review_approved (awaiting execution continuation)
- task-04: complete
- task-05: working (active in external session)
- task-06: working (active in external session)

**Next action for resuming session:**
1. Read this full STATUS.md (cost: ~2-5k tokens)
2. Query orchestration_tasks to verify current states (cost: ~500 tokens)
3. Launch background message-watcher with normal prompt
4. Notify user: "Resumed orchestration. Monitoring Phase 2 completion. Active tasks: task-05, task-06."
5. Return to Monitoring step 2 (waiting for events)

**Additional context:**
- All Phase 1 and Phase 2 tasks complete
- Phase 3 execution sessions (task-05, task-06) launched 12 minutes ago, heartbeats current
- No pending reviews or errors
- No RAG processing in progress
```

## Key Sections

| Section | Purpose |
|---------|---------|
| **Timestamp** | When recovery instructions were written (helps resuming session understand recency) |
| **Context usage** | Helps resuming session understand how much headroom it has |
| **Last checkpoint** | What conductor was doing when it exited |
| **Active tasks** | Current state of all tasks (helps resuming session know what to monitor) |
| **Next action** | Specific, detailed instruction for resuming session (don't make it guess) |
| **Additional context** | Any notes that help resuming session understand the situation |

## Principles

- **Keep it concise:** Recovery instructions are read once, not referenced repeatedly
- **Be specific:** "Return to Monitoring step 2" not "continue monitoring"
- **List all tasks:** Resuming session needs full picture of what's happening
- **Record heartbeat timestamps if critical:** If a session is about to hit heartbeat timeout, note it
- **Mark anything urgent:** If resuming session needs to act immediately (e.g., retry a claim collision), say so clearly
