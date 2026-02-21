<skill name="conductor-danger-files-governance" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- definition
- governance-flow
- mitigation-patterns
- reporting-format
- skip-conditions
</sections>

<section id="definition">
<core>
# Danger Files Governance

## Definition

Danger files are files that MAY be modified by 2+ parallel execution sessions. They represent potential write-write conflicts that could cause merge failures or data loss.
</core>

<context>
## Examples

- Barrel export files (e.g., `src/components/index.ts`)
- Shared configuration files (e.g., `pubspec.yaml`, `package.json`)
- Documentation index files (e.g., `docs/knowledge-base/testing/README.md`)
- Database migration files that multiple tasks might touch
</context>
</section>

<section id="governance-flow">
<core>
## 3-Step Governance Flow

### Step 1: Implementation Plan (Human Decision)

When creating implementation plans, inline danger file annotations on tasks marked parallel-safe:

```markdown
### Phase 2: Parallel Extraction (Tasks 3-6)

Task 3: Extract Testing Docs
  - Source: docs/testing/*.md
  - Target: knowledge-base/testing/
  ⚠️ Danger Files: knowledge-base/testing/README.md (shared with Task 4)

Task 4: Extract API Docs
  - Source: docs/api/*.md
  - Target: knowledge-base/api/
  ⚠️ Danger Files: knowledge-base/testing/README.md (cross-references from Task 3)

Task 5: Extract Database Docs
  - Source: docs/database/*.md
  - Target: knowledge-base/database/
  (No danger files — fully independent)

Task 6: Extract Architecture Docs
  - Source: docs/architecture/*.md
  - Target: knowledge-base/architecture/
  (No danger files — fully independent)
```

### Step 2: Conductor Review (Context-Based Risk Analysis)

When planning a phase, extract all danger file annotations. For each danger file:

**Assess severity:**
- **Low:** Read-only overlap (both tasks read same file but don't modify it)
- **Medium:** One task modifies, another reads (temporal dependency)
- **High:** Both tasks modify same file (write-write conflict)

**Assess timeline:**
- Do the modifications happen at the same time or at different phases of each task?
- Can one task complete its modifications before the other starts?

**Decision matrix:**

| Severity | Timeline Overlap | Decision |
|----------|-----------------|----------|
| Low | Any | Keep parallel |
| Medium | None | Keep parallel, add ordering note |
| Medium | Yes | Keep parallel with mitigation, or move to sequential |
| High | Any | Move to sequential OR split into sub-steps |

### Step 3: Conductor Handoff (Data to Task Instruction Subagent)

If keeping tasks parallel despite danger files, pass context to the task instruction creation subagent:

```
## Parallel Task Dependencies

Task 3 and Task 4 share: knowledge-base/testing/README.md
- Task 3 creates the initial README with testing file index
- Task 4 adds cross-references to testing files

Mitigation: Task 3 should write README first (during early steps).
Task 4's cross-reference additions should be a late step.
If conflict at merge: Task 4's additions take priority for cross-references.
```

The subagent writes this coordination logic directly into the task instruction files.
</core>
</section>

<section id="mitigation-patterns">
<core>
## Mitigation Patterns

### Pattern 1: Ordering Within Tasks

Structure task instructions so that shared file modifications happen at predictable times:
- Task A modifies shared file in Step 2 (early)
- Task B modifies shared file in Step 7 (late)
- Temporal separation reduces conflict probability

### Pattern 2: Append-Only Modifications

Both tasks add content to the file without modifying existing content:
- Task A adds Section X
- Task B adds Section Y
- Git can auto-merge additions to different sections

### Pattern 3: Conductor Batching

Tasks report their modifications as proposals. Conductor applies all modifications in a single coordinated update:
- Task A: "Add these 3 entries to index.ts"
- Task B: "Add these 2 entries to index.ts"
- Conductor: combines both, writes once

### Pattern 4: Sequential Sub-Steps

Move only the danger file modification to a sequential sub-step:
- Tasks 3-6 run in parallel for all non-shared work
- After all complete, conductor runs a single sequential step to merge shared file changes
</core>
</section>

<section id="reporting-format">
<core>
## Reporting Format

Execution sessions report danger file interactions via messages:
</core>

<template follow="format">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    'task-03', '$CLAUDE_SESSION_ID',
    'DANGER FILE UPDATE:
     File: knowledge-base/testing/README.md
     Action: Created initial file with testing index (12 entries)
     Shared with: task-04
     Status: Complete, no conflicts detected',
    'instruction'
);
```
</template>
</section>

<section id="skip-conditions">
<core>
## When to Skip Danger File Analysis

- All tasks in phase are fully independent (no shared files)
- Phase has only 1 task (sequential)
- Shared files are read-only for all tasks in phase
</core>
</section>

</skill>
