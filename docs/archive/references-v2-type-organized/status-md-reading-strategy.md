<skill name="conductor-status-md-reading-strategy" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- problem
- tiered-reading
- decision-flowchart
- status-md-structure
- token-budget-impact
</sections>

<section id="problem">
<context>
# STATUS.md Reading Strategy

## Problem

If the conductor reads full STATUS.md on every checkpoint (5+ sessions x 4 checkpoints), that's 60-100k tokens wasted on redundant reads.
</context>
</section>

<section id="tiered-reading">
<core>
## Solution: Tiered Reading

### Tier 1: Database Queries (Frequent — Every Check)

For real-time state checks, query the database directly:
</core>

<template follow="exact">
```sql
SELECT task_id, state, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE task_id IN ('task-03', 'task-04', 'task-05', 'task-06')
ORDER BY task_id;
```
</template>

<core>
**When:** Every monitoring cycle, before/after reviews, error handling.
**Cost:** Near zero (database query, not file read).
**Returns:** Real-time state, heartbeat freshness, retry counts.

### Tier 2: Partial STATUS.md Reads (Selective — When Reviewing Specific Task)

Read only the relevant task section from STATUS.md:

```
Read from "### Task 3: [Name]" to the next "### Task 4:"
```

**When:** Actively reviewing a specific task's work, need narrative context beyond database state.
**Cost:** ~500-1k tokens per section.
**Why this is safe:** Task section names are stable (Task 1, Task 2, etc.) and won't be restructured mid-implementation. This is different from README headings which might change.

### Tier 3: Full STATUS.md Reads (Rare — Boundaries Only)

Read the entire STATUS.md file:

**When:**
- **Initialization** — First read at session start
- **Resumption** — New session resuming interrupted orchestration
- **Final completion** — Before writing final report
- **Phase transitions** — When moving from one phase to the next (optional, Tier 1 + Tier 2 often suffice)

**Cost:** ~2-5k tokens (one-time per occasion).
</core>
</section>

<section id="decision-flowchart">
<core>
## Decision Flowchart

```
Need task state?
  → Tier 1: Database query

Need task narrative (what was done, conductor notes)?
  → Tier 2: Partial STATUS.md read (that task's section)

Starting new session or completing orchestration?
  → Tier 3: Full STATUS.md read
```
</core>
</section>

<section id="status-md-structure">
<core>
## STATUS.md Structure (For Partial Reads)

STATUS.md follows a predictable structure:

```markdown
# STATUS.md — [Plan Name]

## Conductor Info
[Session ID, branch, database path]

## Phase Overview
[Phase list with status]

### Task 1: [Name]
[Status, notes, issues]

### Task 2: [Name]
[Status, notes, issues]

### Task 3: [Name]
[Status, notes, issues]
...

## Task Planning Notes
[Conductor's working memory — deviations, discoveries, decisions]

## Proposals Pending
[List of unprocessed proposals]

## Recovery Instructions
[Context exit recovery data]

## Project Decisions Log
[Key decisions and rationale]
```

Task sections (### Task N:) are the primary targets for Tier 2 partial reads.
</core>
</section>

<section id="token-budget-impact">
<context>
## Token Budget Impact

| Scenario | Without Strategy | With Strategy |
|----------|-----------------|---------------|
| 4-task phase, 3 reviews each | 12 full reads = 24-60k tokens | 12 DB queries + 12 partial reads = 6-12k tokens |
| 5-task phase, 2 reviews + 1 error each | 15 full reads = 30-75k tokens | 15 DB queries + 15 partial reads = 7-15k tokens |
| Full orchestration (3 phases) | 30+ full reads = 60-150k tokens | 30 DB queries + 30 partial reads + 3 full reads = 21-45k tokens |

**Savings:** 50-70% reduction in context consumed by STATUS.md reads.
</context>
</section>

</skill>
