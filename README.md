# Conductor

Coordinates autonomous execution of multi-task implementation plans. The Conductor is the top-level orchestrator in a three-tier model: **Conductor** (coordination) > Musician (implementation) > Subagents (focused work).

## What It Does

- Discovers active plans, stalled sessions, and ready-to-start work
- Decomposes plans into phased task sequences via Copyist
- Launches and monitors Musician sessions for each task
- Manages parallel execution with database-driven state tracking
- Handles review cycles, error recovery, and completion coordination

## Structure

```
conductor/
  SKILL.md              # Skill definition (entry point)
  docs/archive/         # Historical design documents
  examples/             # Workflow examples (init, monitoring, review, errors)
  references/           # Templates, checklists, state machine, coordination patterns
  scripts/              # Validation and safety checks
```

## Usage

Invoked manually via `/conductor` in Claude Code. Requires the orchestration database (`comms.db`) and the Musician + Copyist skills to be available.

## Origin

Design doc: [kyle-skills/orchestration](https://github.com/kyle-skills/orchestration) `docs/designs/orchestration-protocol.md`
