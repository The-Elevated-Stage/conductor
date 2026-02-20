<skill name="conductor-repetiteur-invocation" version="3.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Repetiteur Invocation Protocol
</metadata>

<sections>
- pre-spawn-checklist
- consultation-count-check
- pause-musicians
- blocker-report-format
- blocker-report-persistence
- blocker-report-preparation
- spawn-prompt-template
- consultation-communication
- passthrough-communication
- escalation-context
- handoff-reception
- task-annotation-matching
- plan-changeover
- superseded-plan-handling
- error-scenarios
</sections>

<section id="pre-spawn-checklist">
<mandatory>
# Repetiteur Invocation Protocol

## Pre-Spawn Checklist

Execute these steps in order before spawning the Repetiteur. Do not skip or reorder.

1. **Pause all Musicians** — Emergency broadcast to all active tasks (see pause-musicians section)
2. **Write blocker report** — Persist to `decisions/{feature-name}/` (see blocker-report-persistence section)
3. **Check consultation count** — Refuse r4, escalate to user instead (see consultation-count-check section)
4. **Spawn Repetiteur** — Teammate with opus, 1m context, structured blocker report (see spawn-prompt-template section)
</mandatory>
</section>

<section id="consultation-count-check">
<mandatory>
## Consultation Count Check

Before spawning, determine the current plan revision:

```sql
-- Read the current plan path from MEMORY.md, then check the plan-index for revision metadata
-- If <!-- revision:N --> is present, that's the current revision number
-- If no revision metadata, this is the original plan (revision 0)
```

If the current revision is `r3` (meaning the next consultation would produce `r4`): **refuse to spawn**. Three consultations have been exhausted. Escalate to user:

"Three Repetiteur consultations exhausted for this feature. The problem likely requires design-level revision, not another implementation attempt. Here is what was tried: [summary of r1, r2, r3 approaches and why each failed]."

The revision number is derivable from the plan filename (`{feature}-plan-r1.md`, `{feature}-plan-r2.md`, etc.) or from the `<!-- revision:N -->` metadata in the plan-index. No separate counter is needed.
</mandatory>
</section>

<section id="pause-musicians">
<mandatory>
## Pause All Musicians

Before spawning the Repetiteur, ALL running Musicians must be paused. No parallel work during consultation — the Repetiteur's impact assessment might reveal that "unaffected" work is actually affected.

Query for active tasks:

<template follow="exact">
```sql
SELECT task_id FROM orchestration_tasks
WHERE state IN ('working', 'needs_review', 'review_approved', 'review_failed', 'fix_proposed')
AND task_id != 'task-00';
```
</template>

Send emergency broadcast to each active task:

<template follow="exact">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
VALUES ('{task-id}', 'task-00',
    'CONSULTATION PAUSE: Repetiteur consultation in progress. Pause all work. Do not proceed with any new steps. Await further instructions.',
    'emergency');
```
</template>

One INSERT per active task_id. Musicians' watcher subagents detect the emergency message and pause.
</mandatory>
</section>

<section id="blocker-report-format">
<mandatory>
## Structured Blocker Report Format

The blocker report is the Repetiteur's primary input. All fields are mandatory — the Conductor has access to all this information and must provide it completely.

### Blocker Description
- **What failed** — the specific error, test failure, or impossibility encountered
- **What was tried** — the Conductor's resolution attempts and why each failed (up to 5 corrections)
- **Why it exceeds Conductor authority** — what makes this a Repetiteur-level problem (cross-phase dependency, architectural issue, mandatory constraint conflict)
- **Which task(s) surfaced the blocker** — task identifiers and the Musician's error report

### Plan State
- **Path to the current implementation plan** (original or most recent rX)
- **Which plan revision this is** (original, r1, r2, etc.)
- **Task completion state** — which tasks are completed, in-progress, blocked, or not yet started
- **Which phase the blocker occurred in** (unambiguous single phase number)

### Current Phase Task State
- **Task instruction file paths** for the current phase
- **Per-task status:** completed / paused / blocked / not started
- **The blocking task's instruction file** and the Musician's error report

### Artifact References
- **Path to the design document** (Dramaturg output)
- **Path to the decision journal directory** (`docs/plans/designs/decisions/{feature-name}/`)
- **List of journals present** (dramaturg-journal, arranger-journal, any prior consultation journals)

### Git State
- **Current branch**
- **Summary of commits** since plan execution began (or since last consultation)
- **Any uncommitted changes** or work-in-progress state
</mandatory>
</section>

<section id="blocker-report-persistence">
<mandatory>
## Blocker Report Persistence

Write the structured blocker report to the decisions directory BEFORE spawning the Repetiteur:

```
docs/plans/designs/decisions/{feature-name}/blocker-report-rN.md
```

Where N matches the plan revision that will be produced (if current plan is original, write `blocker-report-r1.md`; if current is r1, write `blocker-report-r2.md`).

This is crash recovery insurance. If the Conductor session dies during consultation, the blocker report persists and a resuming session (or the user) can understand why the Repetiteur was summoned. The Repetiteur may also read this file if the spawn message context is lost.
</mandatory>
</section>

<section id="blocker-report-preparation">
<guidance>
## Blocker Report Preparation

The "Current Phase Task State" section of the blocker report requires summaries of what each completed and paused task in the current phase actually implemented. This may require reading task instruction files.

For simple phases (2-3 tasks, small instructions): the Conductor can read and summarize directly.

For complex phases (4+ tasks, large instructions, >40k estimated tokens): delegate to a teammate. The teammate reads the current phase's task instruction files and returns distilled summaries. The Conductor incorporates these into the blocker report.

Prior completed phases do NOT get task-level breakdown — the Repetiteur works at phase level for historical phases. Only the current in-progress phase needs task-level detail.
</guidance>
</section>

<section id="spawn-prompt-template">
<mandatory>
## Spawn Prompt Template

The Repetiteur is spawned as a teammate using the Task tool with `model="opus"` and the Conductor's active `team_name`.

<template follow="format">
/repetiteur

Load the Repetiteur skill, then proceed with the consultation.

## Structured Blocker Report

### Blocker Description
What failed: {specific error or impossibility}
What was tried: {Conductor's resolution attempts, numbered 1-N}
Why it exceeds authority: {cross-phase / architectural / mandatory constraint}
Surfaced by: {task ID(s)} — error report at {path}

### Plan State
Current plan: {plan path}
Revision: {original / r1 / r2}
Phase: {N}
Task completion:
  {task-id}: {completed / paused / blocked / not started}
  ...

### Current Phase Task State
Task instructions:
  {task-id}: {instruction file path} — {status} — {brief summary of work done}
  ...
Blocking task: {task-id} — {instruction path}
Error report: {path to Musician's error report}

### Artifact References
Design document: {path}
Decision journals: docs/plans/designs/decisions/{feature-name}/
Journals present: {list}

### Git State
Branch: {branch name}
Commits since execution began: {count} — {brief summary}
Uncommitted changes: {yes/no — details if yes}
</template>

<mandatory>Repetiteur MUST be launched with opus and 1m context. It is extremely context-intensive — the consultation involves reading design documents, all decision journals, current plan sections, task instructions, and conducting impact assessment across the codebase.</mandatory>
</mandatory>
</section>

<section id="consultation-communication">
<core>
## Communication During Consultation

The Repetiteur communicates with the Conductor via SendMessage. The Conductor's role during consultation is **ground-truth provider** — it answers questions from its execution context, provides perspective on what actually happened during implementation, and flags conflicts with implementation reality. The Repetiteur makes the final decisions.

### Ingestion Clarifications (Early)

Brief, targeted questions to fill gaps in the blocker report. Answer from execution context — what you observed, what state things are in, what was actually implemented vs what the plan prescribed.

Examples the Repetiteur may ask:
- "Which specific API call returned the error?"
- "Did the musician attempt [alternative] before failing?"
- "What state is [component] in currently?"

### Ground-Truth Validation (During Resolution)

The Repetiteur consults the Conductor at key decision points. Provide execution perspective — what actually happened may differ from what the plan prescribed or what git shows.

Examples:
- "I'm proposing to change [approach A] to [approach B]. From your execution perspective, does this conflict with anything already implemented?"
- "The impact assessment suggests [completed task X] needs rollback. Can you confirm the current state?"

### Disagreement

If you explicitly disagree with a proposed approach, state the specific factual objection. The Repetiteur must resolve your concern before proceeding. If persistent disagreement (you've provided specific evidence and the Repetiteur still disagrees), the Repetiteur escalates to the user.
</core>
</section>

<section id="passthrough-communication">
<mandatory>
## Passthrough User Communication

During consultation, the user can see the Conductor's terminal output and may want to communicate with the Repetiteur.

- Relay ALL user input to the Repetiteur via SendMessage verbatim — no interpretation or filtering
- Reverse direction works naturally (Repetiteur's SendMessage appears in Conductor output, visible to user)
- When the Repetiteur is active, all user input goes to the Repetiteur UNLESS it is clearly a Conductor command ("stop", "abort", "status")
- Be verbose in terminal output during the Repetiteur workflow — the user needs visibility into re-planning
</mandatory>
</section>

<section id="escalation-context">
<core>
## Escalation Chain and Authority Scope

The Repetiteur invocation sits in a specific position in the escalation chain:

1. **Conductor** attempts fix (up to 5 corrections per blocker)
2. **Repetiteur** autonomously re-plans (up to 3 consultations per feature)
3. **User** only involved if Repetiteur escalates (vision deviation, 3rd consultation exhausted, significant unanticipated scope change)

The Conductor's authority boundary:
- **Can modify:** Intra-phase directions without breaking existing choices or architecture
- **Cannot modify:** Cross-phase dependencies, architectural decisions, protocol choices, items with mandatory authority in Arranger phase sections
- **Triggers Repetiteur:** When out-of-scope changes are required, OR after 5 correction attempts fail on the same blocker
</core>
</section>

<section id="handoff-reception">
<mandatory>
## Handoff Reception

The Repetiteur's handoff message via SendMessage contains:
- Path to the new remaining plan (Implementation Plan rX)
- Revision number
- Summary of what changed: approach revisions, rollbacks ordered, new phases added, phases preserved
- Whether rollback tasks exist and what they revert
- Which phase to begin execution from (first phase in the remaining plan)
- Path to the consultation journal for reference

When the Conductor receives this message, the Repetiteur has already:
- Committed the remaining plan to git
- Moved the superseded plan to `docs/plans/designs/superseded/`
- Committed the consultation journal

The directory state is clean. Proceed to the plan-changeover section.

If the handoff message is NOT received (Repetiteur crash or timeout): the Conductor's timeout detects the stall. The previous plan remains active. Report to user — state is recoverable.
</mandatory>
</section>

<section id="task-annotation-matching">
<mandatory>
## Task Annotation Matching

The Repetiteur annotates tasks inline in the remaining plan. Read the plan and match annotations to actions:

| Annotation | Meaning | Conductor Action |
|------------|---------|-----------------|
| No annotation | Task unchanged, verified unaffected | Resume paused Musician |
| `(REVISED)` | Task modified by Repetiteur | Close old kitty window, delete old instruction files, launch Copyist for new instructions, launch fresh Musician |
| `(NEW)` | Task added by Repetiteur | Insert new task row in database, launch Copyist for instructions, launch fresh Musician |
| `(REMOVED)` | Task eliminated by Repetiteur | Close kitty window, set task state to `exited`, remove instruction files |

This is NOT a full phase restart. Completed work stays. Unchanged paused Musicians resume. Only changed/failed/new tasks get fresh treatment.
</mandatory>
</section>

<section id="plan-changeover">
<mandatory>
## Plan Changeover Procedure

After receiving the handoff message, execute these steps in order:

1. **Verify lock indicator** — Read the remaining plan's verification index (`<!-- plan-index:start -->`). If missing or malformed, treat as unverified and report to user. Do NOT execute an unverified plan.

2. **Read plan sections** — Read Overview, Consultation Context, and Phase Summary from the remaining plan. The Consultation Context section explains what changed and why.

3. **Read conductor checkpoints** — Read the conductor-review sections for each remaining phase.

4. **Update MEMORY.md** — Replace the plan path with the new remaining plan path. This is the persistent anchor — if any plan reference doesn't match MEMORY.md after this point, something is wrong.

5. **Map task annotations** — Per the task-annotation-matching section, determine which tasks are unchanged, revised, new, or removed.

6. **Execute task actions:**
   - Resume paused Musicians for unchanged tasks
   - Close old kitty windows and launch fresh for revised tasks (via Copyist + Musician launch)
   - Close and clean up removed tasks
   - Create new task rows and launch for new tasks

7. **Resume normal execution** — Proceed to Phase Execution Protocol for monitoring and coordination.

8. **Do NOT re-verify completed work** marked as unaffected. The Repetiteur's impact assessment already verified isolation.

9. **Do NOT read the superseded plan.** The Consultation Context section in the remaining plan provides all historical context needed.
</mandatory>
</section>

<section id="superseded-plan-handling">
<core>
## Superseded Plan Directory

Superseded plans accumulate in `docs/plans/designs/superseded/`. The Repetiteur handles moving plans there before sending the handoff message.

```
docs/plans/designs/
  {feature}-plan-r2.md              ← active (current)
  decisions/
    {feature-name}/
      dramaturg-journal.md
      arranger-journal.md
      consultation-1-journal.md
      consultation-2-journal.md
      blocker-report-r1.md
      blocker-report-r2.md
  superseded/
    {feature}-plan.md               ← original
    {feature}-plan-r1.md            ← first revision
```

The Conductor never looks in `superseded/`. Only the Repetiteur reads superseded plans (for context in future consultations) and the journal analysis subagent references them for preventing circular fixes.
</core>
</section>

<section id="error-scenarios">
<core>
## Error Scenarios During Consultation

### Vision Deviation
The Repetiteur determines the blocker contradicts the design document itself (not just the implementation approach). It sends an escalation notice instead of a handoff. Relay to user — the design needs revision, not another implementation attempt.

### Verification Loop Failure
The Repetiteur's internal quality check cannot produce a clean plan. It messages that the consultation was unable to produce a verified plan. Relay to user — the blocker may be more fundamental than initially assessed.

### Handoff Parse Failure
The remaining plan's verification index is missing or malformed. Treat as unverified. Report to user — do NOT attempt to execute an unverified plan.

### Repetiteur Crash (No Handoff Received)
The Conductor never receives the handoff message and remains in waiting state. The previous plan may still be in `docs/plans/designs/` (not yet moved to `superseded/`), and the new plan may be committed but the Conductor doesn't know about it. Timeout detects the stall. Report to user — the state is recoverable (user can inspect directory and complete transition manually or restart consultation).

<mandatory>In all error scenarios where the handoff was never sent, the previous plan remains the active plan from the Conductor's perspective. MEMORY.md was not updated, so the plan reference is still correct.</mandatory>
</core>
</section>

</skill>
