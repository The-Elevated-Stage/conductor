<skill name="conductor-subagent-failure-handling" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- scope
- retry-policy
- failure-categories
- retry-decision-flowchart
- escalation-to-user
- integration-with-workflow
</sections>

<section id="scope">
<context>
# Subagent Failure Handling

This reference covers failures of **conductor subagents** (task instruction creation, monitoring) — NOT execution session errors. For execution session error handling, see SKILL.md Error Handling section and `examples/error-recovery-workflow.md`.
</context>
</section>

<section id="retry-policy">
<core>
## Retry Policy

**3 retries maximum** with the same prompt and inputs. After 3 failures, escalate to user.

```
Attempt 1: Launch subagent with original prompt
  ↓ failure
Attempt 2: Relaunch with same prompt (transient failures self-resolve)
  ↓ failure
Attempt 3: Relaunch with same prompt (last automatic retry)
  ↓ failure
Escalate: Present all 3 error messages to user with options
```
</core>
</section>

<section id="failure-categories">
<core>
## Failure Categories

Classify each failure to determine whether retrying is worthwhile.

### Category 1: Transient Failures

**Symptoms:** Timeout, connection reset, partial output, "context window exceeded" mid-generation.

**Retry strategy:** Retry immediately. These resolve on their own. No prompt modification needed.

**Example:**
```
Attempt 1 failed: Subagent timed out after 10 minutes
Action: Retry with same prompt (attempt 2)
```

### Category 2: Configuration Failures

**Symptoms:** Wrong skill name, missing file path, invalid tool call, "skill not found", "file does not exist".

**Retry strategy:** Fix the configuration error in the prompt before retrying. Do NOT retry with the same broken prompt — it will fail identically.

**Example:**
```
Attempt 1 failed: "Skill 'writing-instructions' not found"
Root cause: Skill name is 'copyist', not 'writing-instructions'
Action: Fix skill name in prompt, retry (attempt 2)
```

**Common configuration errors:**
- Wrong skill name (check `~/.claude/skills/` for exact names)
- Wrong file path (verify paths exist before including in prompt)
- Missing `subagent_type` parameter

### Category 3: Logic Errors

**Symptoms:** Subagent completes but output is wrong — validation script fails, wrong template used, missing sections, incorrect SQL table names.

**Retry strategy:** Add correction context to the prompt. Specify what went wrong and what the correct output looks like.

**Example:**
```
Attempt 1 failed: Validation shows 4 errors — wrong table name 'coordination_status'
Action: Add to prompt: "Use table name 'orchestration_tasks', NOT 'coordination_status'.
  The schema has 2 tables: orchestration_tasks and orchestration_messages."
Retry (attempt 2)
```

### Category 4: Systemic Failures

**Symptoms:** Subagent produces fundamentally wrong output despite correct prompt. Plan content may be ambiguous, task may be too complex for single subagent, or skill has a bug.

**Retry strategy:** Do NOT retry with same prompt. Escalate to user after first clear systemic failure, even if retry count < 3.

**Example:**
```
Attempt 1: Subagent created sequential instructions for a parallel phase
Attempt 2: Same issue — subagent ignores task type parameter
Assessment: Systemic — prompt template or skill may need fixing
Action: Escalate immediately (don't waste attempt 3)
```
</core>
</section>

<section id="retry-decision-flowchart">
<core>
## Retry Decision Flowchart

```
Subagent failed
  │
  ├─ Is this attempt 4+? ──YES──→ Escalate to user
  │
  NO
  │
  ├─ Is error transient (timeout, partial output)? ──YES──→ Retry same prompt
  │
  NO
  │
  ├─ Is error a configuration mistake? ──YES──→ Fix config, retry with corrected prompt
  │
  NO
  │
  ├─ Is error a logic error (wrong output)? ──YES──→ Add correction context, retry
  │
  NO
  │
  └─ Systemic failure ──→ Escalate to user (skip remaining retries)
```
</core>
</section>

<section id="escalation-to-user">
<core>
## Escalation to User

When escalating, provide structured information so the user can make an informed decision.

### Escalation Message Format
</core>

<template follow="format">
```
Subagent failed [N] times creating [WHAT].

Error summary:
- Attempt 1: [error description]
- Attempt 2: [error description]
- Attempt 3: [error description]

Failure category: [transient | configuration | logic | systemic]

Options:
1. **Retry manually** — I'll try again with a modified prompt (describe changes)
2. **Skip this phase** — Proceed without these task instructions, handle manually later
3. **Abort orchestration** — Stop all execution, preserve current state for manual recovery
4. **Modify inputs** — Adjust plan content or task scope, then retry

Recommendation: [which option and why]
```
</template>

<core>
### Example Escalation Messages

**Task instruction creation failure:**
```
Task instruction subagent failed 3 times creating Phase 2 instructions.

Error summary:
- Attempt 1: Validation failed — 6 errors (wrong SQL table names)
- Attempt 2: Validation failed — 2 errors (missing heartbeat in state transitions)
- Attempt 3: Validation failed — 1 error (completion report format missing)

Failure category: Logic error (progressive improvement but not converging)

Options:
1. Retry manually — I'll add explicit SQL examples from database-queries.md to the prompt
2. Skip Phase 2 — Proceed to Phase 3, create Phase 2 instructions later
3. Abort orchestration — Preserve current state
4. Modify inputs — Simplify Phase 2 tasks or split into smaller phases

Recommendation: Option 1. Errors are decreasing per attempt.
Adding explicit SQL examples should resolve the remaining issue.
```

**Monitoring subagent failure:**
```
Monitoring subagent failed 3 times for Phase 2.

Error summary:
- Attempt 1: Subagent returned without polling (misunderstood prompt)
- Attempt 2: Subagent returned without polling (same issue)
- Attempt 3: Subagent polled once then exited

Failure category: Logic error (subagent doesn't sustain polling loop)

Options:
1. Retry manually — Restructure prompt to be more explicit about polling behavior
2. Skip monitoring — Monitor manually via validate-coordination.sh
3. Abort orchestration — Preserve current state

Recommendation: Option 2. Manual monitoring via validate-coordination.sh
is reliable. Resume subagent monitoring when next phase starts.
```
</core>
</section>

<section id="integration-with-workflow">
<core>
## Integration with Conductor Workflow

### During Phase Planning (Task Instruction Creation)

```
1. Launch subagent with prompt from subagent-prompt-template.md
2. If subagent returns successfully:
   → Review output using STRATEGY checklist
   → Proceed to database insertion
3. If subagent fails:
   → Classify failure (transient/configuration/logic/systemic)
   → Apply retry strategy (see flowchart above)
   → After 3 failures or systemic detection: escalate
```

### During Monitoring

```
1. Launch monitoring subagent (background)
2. If subagent returns with state change report:
   → Handle event (review/error/complete)
   → Relaunch monitoring subagent
3. If subagent fails or returns without useful data:
   → Retry monitoring subagent (same 3-retry policy)
   → Fallback: run validate-coordination.sh manually
```

### Tracking Retries
</core>

<guidance>
Record retry attempts in STATUS.md Task Planning Notes:

```markdown
### Task Planning Notes
- Phase 2 instruction subagent: attempt 2/3 (fixed SQL table names, retrying)
- Monitoring subagent: fell back to manual monitoring (3 failures, option 2 chosen)
```

This provides context for resuming sessions and diagnosing patterns across orchestrations.
</guidance>
</section>

</skill>
