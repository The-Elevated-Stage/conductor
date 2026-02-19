# Example: Completion Coordination

This example shows the final integration workflow after all tasks complete.

## Scenario

All Phase 2 tasks (task-03 through task-06) have reached `complete` state.
Phase 3 is also complete. All implementation tasks are done.

## Step 1: Verify All Tasks Complete

```sql
SELECT task_id, state, completed_at, report_path
FROM orchestration_tasks
WHERE task_id != 'task-00'
ORDER BY task_id;
```

Expected (all `complete`):
```
task-01 | complete | 2026-02-04 10:15 | docs/implementation/reports/task-01-completion.md
task-03 | complete | 2026-02-04 11:30 | docs/implementation/reports/task-03-completion.md
task-04 | complete | 2026-02-04 11:45 | docs/implementation/reports/task-04-completion.md
task-05 | complete | 2026-02-04 12:00 | docs/implementation/reports/task-05-completion.md
task-06 | complete | 2026-02-04 11:15 | docs/implementation/reports/task-06-completion.md
task-07 | complete | 2026-02-04 14:30 | docs/implementation/reports/task-07-completion.md
task-08 | complete | 2026-02-04 14:45 | docs/implementation/reports/task-08-completion.md
task-09 | complete | 2026-02-04 15:00 | docs/implementation/reports/task-09-completion.md
task-10 | complete | 2026-02-04 15:30 | docs/implementation/reports/task-10-completion.md
```

If any task is `exited`, note it for the report but continue with integration.

## Step 2: Read Completion Reports

Read each report to compile deliverables list and identify any issues.

## Step 3: Verify Deliverables

```bash
# All expected files exist
ls -la docs/knowledge-base/testing/*.md
ls -la docs/knowledge-base/api/*.md
ls -la docs/knowledge-base/database/*.md
ls -la docs/knowledge-base/architecture/*.md

# Git status is clean
git status

# No uncommitted changes
git diff --stat
```

## Step 4: Run Final Verification

```bash
# All tests passing (if applicable)
# dart test
# npm test

# Check for files outside expected directories
find docs/ -name "*.md" -newer docs/plans/2026-02-04-docs-reorganization.md

# Verify no files in temp/ that should be elsewhere
ls -la temp/
```

## Step 5: Check for Proposals

```bash
# General proposals
ls -la docs/implementation/proposals/

# Learnings proposals
ls -la docs/proposals/claude-md/

# Verify nothing stuck in temp/
ls -la temp/*.md 2>/dev/null
```

Process each proposal:
- **CLAUDE.md additions** — integrate immediately
- **Memory snippets** — add to memory entities
- **RAG patterns** — verify ingested
- **Non-critical** — defer or note for follow-up

## Step 6: Integrate Proposals

Example CLAUDE.md addition:
```markdown
## New Rule: Knowledge-Base File Headers
All knowledge-base .md files require YAML frontmatter with: title, date, tags, source.
```

Example memory entity:
```
Pattern: Documentation extraction follows source→target mapping with cross-references.
Anti-pattern: Don't create cross-references before target files exist.
```

## Step 7: Ask About Human-Readable Docs

```markdown
Implementation complete. The following reference documentation could be
generated from the RAG knowledge-base:

- reference/testing-guide.md (from knowledge-base/testing/)
- reference/api-guide.md (from knowledge-base/api/)
- reference/database-guide.md (from knowledge-base/database/)
- reference/architecture-guide.md (from knowledge-base/architecture/)

Generate consolidated guides now?
```

## Step 8: Prepare PR

```bash
# Review all commits
git log --oneline feat/docs-reorganization..HEAD

# Check for sensitive data
git diff main --stat
```

Suggest PR:
```markdown
**Title:** feat(docs): reorganize documentation into knowledge-base structure

**Description:**
## Summary
- Reorganized documentation from flat docs/ into structured knowledge-base/
- Created 4 knowledge-base sections: testing, api, database, architecture
- Extracted and cross-referenced 35+ documentation files
- Added YAML frontmatter metadata to all knowledge-base files

## Tasks Completed
- Task 1: Documentation structure foundation
- Tasks 3-6: Parallel extraction (testing, api, database, architecture)
- Tasks 7-10: Migration and cross-referencing

## Test Plan
- [ ] All knowledge-base files have YAML frontmatter
- [ ] Cross-references resolve to existing files
- [ ] No broken links in documentation
- [ ] RAG ingestion successful for all files
```

## Step 9: Report to User

```markdown
Implementation complete!

**Deliverables:**
- 35 knowledge-base files across 4 sections
- 9 completion reports in docs/implementation/reports/
- 3 proposals integrated (CLAUDE.md, memory, RAG)
- Feature branch: feat/docs-reorganization

**Statistics:**
- 9 tasks completed (0 exited)
- Average smoothness: 2.1/9
- Total execution time: ~6 hours
- Review cycles: 4 (all approved first attempt)

**Recommendations:**
- Review PR before merging
- Consider generating reference guides from knowledge-base
- Delete docs/ after merge

Waiting for your feedback.
```

## Step 10: Set Conductor Complete

```sql
UPDATE orchestration_tasks
SET state = 'complete', last_heartbeat = datetime('now'),
    completed_at = datetime('now')
WHERE task_id = 'task-00';
```

Hook detects `complete` state → session can now exit normally.
