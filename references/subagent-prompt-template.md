# Subagent Prompt Template — Task Instruction Creation

This template is used by the conductor to construct the `prompt` parameter when launching a Task subagent to create task instruction files for a phase.

The conductor fills in all `{{placeholders}}` before passing to the Task tool.

---

## Template

### Step 1: Prepare Overrides & Learnings

Before launching the subagent, the conductor reviews the implementation plan for the current phase and compiles any corrections, scope adjustments, danger file decisions, or lessons from prior phases. These are passed directly in the subagent prompt as the `## Overrides & Learnings` section.

If there are no overrides, write "None — follow the implementation plan as written."

### Step 2: Launch Subagent

```
Task("Create task instructions for Phase {{PHASE_NUMBER}}", prompt="""

Load the copyist skill, then create task instruction files for this phase.

## Phase Info
**Phase:** {{PHASE_NUMBER}} — {{PHASE_NAME}}
**Task type:** {{TASK_TYPE}} (sequential/parallel)
**Tasks to create:** {{TASK_LIST}}
**Implementation plan:** {{PLAN_PATH}}
**Output directory:** docs/tasks/

## Overrides & Learnings
{{OVERRIDES_AND_LEARNINGS}}

## Instructions
1. Read the implementation plan at `{{PLAN_PATH}}`
2. Invoke the `copyist` skill
3. Read the appropriate template (sequential or parallel) — following templates is MANDATORY
4. Extract the tasks listed above from the plan
5. Apply any Overrides & Learnings — these take precedence over the plan
6. Write instruction files to `docs/tasks/`
7. Validate each file and fix errors until all pass

## Quality Gate

Before returning, verify every instruction file:
- Passes validation script (0 errors)
- Contains no "see plan section X" references
- Has complete SQL with correct table names and heartbeats
- Has explicit file paths for all deliverables
- Sequential: has Initialization, Completion, Error Recovery sections
- Parallel: has Hook setup, Background subagent, Review checkpoint, Error Recovery sections

### Instruction Validation Checklist (ENH-L)

Verify each instruction file before returning:
1. **Plan coverage:** Does instruction cover all objectives from implementation plan for this task? No missing steps.
2. **Step clarity:** Each step is unambiguous — execution session can proceed without judgment calls.
3. **Safety flags:** Dangerous operations (force-push, destructive db changes) are explicitly marked with ⚠️ WARNING.
4. **Template compliance:** All sections from the selected template are present. Inapplicable sections marked N/A with reason, not omitted.
5. **Checkpoint quality:** Checkpoints are after significant deliverables, not arbitrary steps. One per 3-5 substantive steps.

Report the validation results for each file when done.

### Checkpoint Design Guidance (ENH-M)

When instruction includes checkpoints (parallel tasks or mid-task reviews):
1. **Frequency:** Place one checkpoint per 3-5 major steps. Too many: overhead. Too few: musician loses track.
2. **Granularity:** Each checkpoint tests a cohesive unit (e.g., "Extract & verify API schema section", not "Extract headers and endpoints separately").
3. **Verification strategy at each:** What test or verification confirms this checkpoint is complete? Include specific grep/ls/test commands, not vague descriptions.

""", model="opus", run_in_background=False)
```

---

## Conductor Usage

### Before Launch — Prepare Overrides & Learnings

The conductor reviews the implementation plan for the current phase and compiles overrides:

1. **Review STATUS.md Task Planning Notes** — any corrections or scope adjustments from prior phases
2. **Check danger file decisions** — resolved conflicts, mitigation strategies
3. **Note lessons learned** — patterns from completed phases that should inform this phase's instructions

Compile these into the `## Overrides & Learnings` section of the prompt. If none, write "None — follow the implementation plan as written."

Then launch the subagent with the template above, filling in all `{{placeholders}}`.

### Filling the Template

| Placeholder | Source |
|---|---|
| `{{PHASE_NUMBER}}` | Implementation plan phase structure |
| `{{PHASE_NAME}}` | Implementation plan phase name |
| `{{TASK_TYPE}}` | `sequential` or `parallel` — from plan analysis |
| `{{TASK_LIST}}` | Comma-separated task IDs for this phase |
| `{{PLAN_PATH}}` | Path to the implementation plan file |
| `{{OVERRIDES_AND_LEARNINGS}}` | Conductor-compiled corrections, scope adjustments, danger file decisions, lessons from prior phases. "None — follow the implementation plan as written." if empty |
| Output directory | Hardcoded to `docs/tasks/` unless user specifies otherwise |
| `{{TASK_ID}}` | Individual task ID (used in output filename pattern) |

### After Return — Conductor Review

The conductor reviews returned files from in-memory context (not re-reading the plan):

1. Check validation results reported by subagent
2. Review against Task Planning Notes from STATUS.md
3. Spot-check: instructions align with plan goals, appropriate task type, reasonable checkpoints
4. If issues found: prompt subagent with specific correction ("Missing X, check plan section Y")
5. Iteration limits: 2 loops max for same issue, 5 total reviews per instruction

### Pre-Fetching RAG Results (Optional)

For complex phases, the conductor can pre-fetch RAG results and include them in the prompt:

```python
# Before constructing prompt, query RAG for relevant patterns
rag_results = query_documents("SQL patterns coordination database queries templates")
# Append to plan content if score < 0.3
```

This reduces the subagent's need for independent RAG queries, saving context budget.
