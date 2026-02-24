<skill name="conductor-error-recovery" version="4.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Error Recovery Protocol
</metadata>

<sections>
- entry-points
- error-classification
- musician-error-workflow
- context-warning-protocol
- stale-heartbeat-recovery
- claim-failure-recovery
- copyist-output-errors
- complex-error-investigation
- subagent-failure-handling
- escalation-to-repetiteur
- error-prioritization
- error-state-transitions
- retry-limits
- error-reporting-sql
- fix-proposal-sql
- context-warning-detection-sql
- staleness-detection-sql
- context-situation-checklist
- context-exhaustion-trigger
</sections>

<section id="entry-points">
<core>
# Error Recovery Protocol

## Entry Points

This protocol has multiple entry points depending on how the Conductor arrives. Each entry point section is self-contained — read the relevant section for your situation.

| Situation | Start At |
|-----------|----------|
| Background watcher detected `error` state | musician-error-workflow |
| Background watcher detected `error` with `last_error = 'context_exhaustion_warning'` | context-warning-protocol |
| Stale heartbeat detected (Musician not responding) | stale-heartbeat-recovery |
| `claim_blocked` message detected | claim-failure-recovery |
| Copyist returned faulty task instructions | copyist-output-errors |
| Complex error needing investigation (>40k estimated tokens) | complex-error-investigation |
| Review loop reached 5 cycles (routed from Review Protocol) | escalation-to-repetiteur |
| Multiple events pending simultaneously | error-prioritization |

Each section handles its scenario and routes to the next appropriate action. When crossing protocol boundaries, return to SKILL.md to locate the named protocol.
</core>
</section>

<section id="error-classification">
<core>
## Error Classification

When a Musician reports an error, classify it before proposing a fix:

- **Simple fix** (typo, config, missing import) — propose fix immediately via fix-proposal-sql. Low context cost, high confidence.
- **Complex** (logic error, integration failure, test failure cascade) — investigate via teammate before proposing. See complex-error-investigation section.
- **Uncertain** (root cause unclear, multiple possible causes) — delegate to teammate for investigation. If teammate investigation fails to identify root cause, escalate to the Repetiteur Protocol via SKILL.md rather than burning correction attempts on guesses.
- **Beyond authority** (requires cross-phase changes, architectural decisions, or modification of items with mandatory authority in the Arranger plan) — escalate immediately to the Repetiteur Protocol via SKILL.md. Do not consume correction attempts on out-of-scope changes.

<guidance>
If the first two correction attempts don't show progress toward resolution, seriously consider whether this is actually a Repetiteur-level problem. Burning all 5 attempts on variations of the same wrong approach wastes context and delays the real fix.
</guidance>
</core>
</section>

<section id="musician-error-workflow">
<core>
## Musician Error Workflow

When the background watcher detects `error` state on a task:

### Step 1: Check last_error field
```sql
SELECT task_id, state, last_error, retry_count FROM orchestration_tasks
WHERE state = 'error' AND task_id NOT IN ('task-00', 'souffleur');
```

If `last_error = 'context_exhaustion_warning'`, go to context-warning-protocol section instead.

### Step 2: Read error report
Read the error report from the message:

<template follow="exact">
```sql
SELECT message FROM orchestration_messages
WHERE task_id = '{task-id}' AND message_type = 'error'
ORDER BY timestamp DESC LIMIT 1;
```
</template>

### Step 3: Check retry count

<mandatory>Before proposing a fix, check retry_count. If retry_count >= 5, do not propose another fix — proceed to escalation-to-repetiteur section.</mandatory>

### Step 4: Classify and respond
Apply error-classification logic. Propose fix using fix-proposal-sql or escalate as appropriate.

### Step 5: Return to monitoring
After sending the fix proposal, return to SKILL.md and locate the Phase Execution Protocol. The monitoring cycle re-entry handles checking for additional events.

<mandatory>After error handling completes, proceed to SKILL.md → Message-Watcher Exit Protocol if the watcher is not already running.</mandatory>

<guidance>
After resolving errors, consider appending reusable insights to `temp/conductor-learnings.log` — patterns, workarounds, or gotchas that future Conductor generations should know.
</guidance>
</core>
</section>

<section id="context-warning-protocol">
<core>
## Context Warning Protocol

When `last_error = 'context_exhaustion_warning'`, the Musician reports remaining context but can still propose a path forward.

### Assessment

Evaluate using the context-situation-checklist section:
- Is self-correction flag active? (context estimates ~6x unreliable)
- How many deviations and how severe?
- How far to next checkpoint?
- How many agents remain and at what cost?
- Has this task had prior context warnings?

### Response Options

Respond with ONE of:
- **`review_approved`:** Proceed with Musician's proposal (reach checkpoint OR run N more agents — whatever Musician suggested)
- **`fix_proposed`:** Override Musician's proposal — "Only do X then prepare handoff" or "Adjust approach to reduce context"
- **`review_failed`:** Stop now, prepare handoff immediately

Use the appropriate SQL from the review-approval or fix-proposal sections.

After responding, return to SKILL.md and locate the Phase Execution Protocol for monitoring re-entry.
</core>

<guidance>
When the Conductor itself is running low on context (not a Musician), route to the context-exhaustion-trigger section instead of continuing to orchestrate. The Conductor detects its own context exhaustion via the same platform-level context warnings that Musicians receive — no custom monitoring infrastructure needed. If the Conductor receives a context warning about itself, stop dispatching new work and execute the context-exhaustion-trigger sequence.
</guidance>
</section>

<section id="stale-heartbeat-recovery">
<core>
## Stale Heartbeat Recovery

When a Musician's heartbeat goes stale (>9 minutes without update):

### Step 1: Check PID status

```bash
PID=$(cat temp/musician-task-XX.pid 2>/dev/null)
if [ -n "$PID" ] && kill -0 $PID 2>/dev/null; then
    echo "PID alive but heartbeat stale — watcher died, session stuck"
else
    echo "PID dead — session crashed"
fi
```

### Step 2: Respond based on PID status

**PID alive, heartbeat stale:** The watcher died but the Musician session is still running (probably stuck in a loop or waiting for something that won't come). Proceed to SKILL.md and locate the Musician Lifecycle Protocol for window cleanup and re-launch.

**PID dead:** The session genuinely crashed. Proceed to SKILL.md and locate the Musician Lifecycle Protocol — follow the crash handoff procedure.

<template follow="exact">
```sql
SELECT task_id, state, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE state IN ('working', 'review_approved', 'review_failed', 'fix_proposed')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
```
</template>
</core>
</section>

<section id="claim-failure-recovery">
<core>
## Claim Failure Recovery

When a `claim_blocked` message is detected (a Musician failed to claim its assigned task because another session already claimed it):

### Autonomous Recovery Flow

1. Close the failed Musician's kitty window (read PID file, SIGTERM, remove PID file)
2. Check the original task's state — was it successfully claimed by another session?
3. **If yes (task in `working` state):** The collision is resolved. Clean up the fallback row and proceed.
4. **If no (task still in a claimable state):** Reset the task row (update state back to `watching`, clear session_id), re-insert the instruction message, re-launch a new Musician.
5. **If second claim also fails:** Report to user for manual investigation — something unexpected is blocking the claim.

For window cleanup and re-launch mechanics, proceed to SKILL.md and locate the Musician Lifecycle Protocol.

<template follow="exact">
```sql
-- Clean up fallback row after resolution
DELETE FROM orchestration_tasks WHERE task_id LIKE 'fallback-%' AND session_id = '{failed-session-id}';
```
</template>
</core>
</section>

<section id="copyist-output-errors">
<core>
## Copyist Output Errors

When the Copyist returns task instruction files that have errors:

- **Small errors** (wrong file path, minor SQL typo, missing section marker): Edit inline. The Conductor can fix these directly without re-launching the Copyist.
- **Larger issues** (wrong task type, missing sections, structurally broken instructions): Re-launch the Copyist teammate to correct or rewrite. The Copyist teammate is resumable — if the first attempt doesn't fully resolve, send it back with specific feedback.

<mandatory>Copyist is launched as a teammate (not a regular subagent) for >40k token work. Teammates are resumable with preserved context.</mandatory>
</core>
</section>

<section id="complex-error-investigation">
<core>
## Complex Error Investigation

For errors where the root cause isn't immediately clear or the fix requires deep codebase analysis:

1. Launch a teammate for focused investigation. The teammate has full context and can use Explorer for codebase analysis, Gemini for external research, and Serena for semantic code navigation.
2. The teammate investigates the error, traces code paths, identifies the root cause, and proposes a fix.
3. The Conductor reviews the teammate's findings and decides: propose the fix to the Musician, or escalate if the issue exceeds intra-phase authority.

<guidance>
Use this approach when:
- The error report doesn't clearly identify the root cause
- Multiple possible causes exist and narrowing down requires code exploration
- The estimated investigation context is >40k tokens
- Previous simple fix attempts haven't resolved the issue

If the teammate investigation also fails to identify a clear fix, escalate to the Repetiteur Protocol via SKILL.md rather than continuing to guess.
</guidance>
</core>
</section>

<section id="subagent-failure-handling">
<core>
## Subagent Failure Handling

This section covers failures of **Conductor subagents** (task instruction creation teammates, monitoring watchers, RAG processing subagents) — NOT Musician session errors. Musician errors are handled by the musician-error-workflow section.

### Retry Policy

**3 retries maximum** with the same prompt and inputs. After 3 failures, escalate.

```
Attempt 1: Launch subagent with original prompt
  ↓ failure
Attempt 2: Relaunch with same prompt (transient failures self-resolve)
  ↓ failure
Attempt 3: Relaunch with same prompt (last automatic retry)
  ↓ failure
Escalate: Do not retry — the approach is wrong
```

### Failure Categories

Classify each failure to determine whether retrying is worthwhile:

**Category 1: Transient Failures**
Symptoms: Timeout, connection reset, partial output, "context window exceeded" mid-generation.
Retry strategy: Retry immediately. These resolve on their own. No prompt modification needed.

```
Attempt 1 failed: Subagent timed out after 10 minutes
Action: Retry with same prompt (attempt 2)
```

**Category 2: Configuration Failures**
Symptoms: Wrong skill name, missing file path, invalid tool call, "skill not found", "file does not exist".
Retry strategy: Fix the configuration error in the prompt BEFORE retrying. Do NOT retry with the same broken prompt — it will fail identically.

```
Attempt 1 failed: "Skill 'writing-instructions' not found"
Root cause: Skill name is 'copyist', not 'writing-instructions'
Action: Fix skill name in prompt, retry (attempt 2)
```

Common configuration errors:
- Wrong skill name (check `~/.claude/skills/` for exact names)
- Wrong file path (verify paths exist before including in prompt)
- Missing `subagent_type` parameter

**Category 3: Logic Errors**
Symptoms: Subagent completes but output is wrong — validation script fails, wrong template used, missing sections, incorrect SQL table names.
Retry strategy: Add correction context to the prompt. Specify what went wrong and what the correct output looks like.

```
Attempt 1 failed: Validation shows 4 errors — wrong table name 'coordination_status'
Action: Add to prompt: "Use table name 'orchestration_tasks', NOT 'coordination_status'."
Retry (attempt 2)
```

**Category 4: Systemic Failures**
Symptoms: Subagent produces fundamentally wrong output despite correct prompt. Plan content may be ambiguous, task may be too complex for single subagent, or skill has a bug.
Retry strategy: Do NOT retry with same prompt. Escalate after first clear systemic failure, even if retry count < 3.

```
Attempt 1: Subagent created sequential instructions for a parallel phase
Attempt 2: Same issue — subagent ignores task type parameter
Assessment: Systemic — prompt or skill may need fixing
Action: Escalate immediately (don't waste attempt 3)
```

### Retry Decision Flowchart

```
Subagent failed
  │
  ├─ Is this attempt 4+? ──YES──→ Escalate
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
  └─ Systemic failure ──→ Escalate (skip remaining retries)
```

### Escalation After 3 Failures

<mandatory>Do not exceed 3 retries for the same subagent prompt. After 3, the approach is wrong — retrying won't fix it.</mandatory>

Escalation chain:
1. Can the Conductor work around the subagent failure? (e.g., do the work directly, use a different approach, fall back to manual process)
2. If not, proceed to SKILL.md and locate the Repetiteur Protocol for re-planning assistance
3. User is involved only if the Repetiteur also escalates

### Escalation Message Format

<template follow="format">
Subagent failed {N} times creating {WHAT}.

Error summary:
- Attempt 1: {error description}
- Attempt 2: {error description}
- Attempt 3: {error description}

Failure category: {transient | configuration | logic | systemic}

Assessment: {why retrying won't help}
Next action: {what the Conductor will try instead — workaround, Repetiteur escalation, etc.}
</template>

### Integration with Conductor Workflow

**During Phase Planning (Copyist Teammate Failures):**
1. Launch Copyist teammate with prompt from copyist-launch-template
2. If teammate returns successfully → review output, proceed to database insertion
3. If teammate fails → classify failure, apply retry strategy
4. After 3 failures or systemic detection → escalate (workaround or Repetiteur)

**During Monitoring (Watcher Subagent Failures):**
1. Launch monitoring subagent (background)
2. If subagent returns with state change report → handle event, relaunch
3. If subagent fails or returns without useful data → retry (same 3-retry policy)
4. Fallback: run `scripts/validate-coordination.sh` manually for monitoring
</core>
</section>

<section id="escalation-to-repetiteur">
<mandatory>
## Escalation to Repetiteur

The Conductor escalates to the Repetiteur Protocol when:

1. **5 correction attempts exhausted** on the same Musician error without resolution
2. **Beyond authority** — the fix requires cross-phase changes, architectural decisions, or modifying items with mandatory authority in the Arranger plan
3. **Review loop exhausted** — 5 review cycles for the same checkpoint without passing (routed from Review Protocol)
4. **Subagent failures exhausted** — 3 retries on the same subagent task without success, and no workaround exists

When escalation is triggered, proceed to SKILL.md and locate the Repetiteur Protocol. The Repetiteur Protocol's pre-spawn checklist handles pausing Musicians, writing the blocker report, and spawning the Repetiteur.

Do not attempt to resolve cross-phase or architectural issues yourself. The Conductor's authority is strictly intra-phase. Attempting out-of-scope fixes wastes correction attempts and delays the real fix.
</mandatory>
</section>

<section id="error-prioritization">
<core>
## Error Prioritization

When the Conductor has multiple pending events, handle in this order:

1. **Errors** — task in `error` state (blocking Musician, needs fix proposal)
2. **Reviews** — task in `needs_review` state (blocking Musician, needs verdict)
3. **Completions** — task reporting complete (non-blocking, acknowledgment only)

Errors are always first because they represent blocked Musicians consuming no context but making no progress. Reviews are second because Musicians are paused but stable. Completions are non-blocking and can wait.
</core>
</section>

<section id="error-state-transitions">
<core>
## Error State Transitions

Two states are directly involved in error recovery:

- **`error`** — Set by Musician. Awaiting Conductor fix proposal. Musician is paused.
- **`fix_proposed`** — Set by Conductor. Musician applies fix and resumes.

```
working → error → [Conductor: fix_proposed] → working → ...
working → error → [Conductor: fix_proposed] → working → error → ... (x5) → exited
```

Terminal path: After 5 error/fix cycles, the Musician self-exits. The Conductor then escalates to the Repetiteur Protocol via SKILL.md.

<mandatory>Every state transition MUST include `last_heartbeat = datetime('now')`. Omitting the heartbeat from a state update is a bug.</mandatory>
</core>
</section>

<section id="retry-limits">
<core>
## Retry Limits

| Scope | Limit | On Exhaustion |
|-------|-------|---------------|
| Musician error retries | 5 | Musician self-exits. Conductor escalates to Repetiteur Protocol via SKILL.md. |
| Conductor subagent retries | 3 | Conductor escalates (workaround → Repetiteur → user). |
| Review cycles per checkpoint | 5 | Conductor routes to Error Recovery (this protocol) for deeper investigation. |

`retry_count` tracks Musician error retries only, not review cycles or subagent failures.
</core>
</section>

<section id="error-reporting-sql">
<core>
## Error Reporting SQL (Reference — Musician Side)

This is the format Musicians use to report errors. The Conductor reads these messages. Included for reference.

<template follow="format">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', '$CLAUDE_SESSION_ID',
    'ERROR (Retry {N}/5):
     Context Usage: {XX}%
     Self-Correction: {YES/NO}
     Error: {description}
     Report: docs/implementation/reports/{task-id}-error-retry-{N}.md
     Awaiting conductor fix proposal',
    'error'
);

UPDATE orchestration_tasks
SET state = 'error',
    retry_count = retry_count + 1,
    last_error = '{error summary}',
    last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';
```
</template>
</core>
</section>

<section id="fix-proposal-sql">
<core>
## Fix Proposal SQL

When proposing a fix to a Musician:

<template follow="format">
```sql
INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
    '{task-id}', 'task-00',
    'FIX PROPOSAL (Retry {N}/5):
     Root cause: {analysis}
     Fix: {specific instructions}
     Retry: {what to do after applying fix}',
    'fix_proposal'
);

UPDATE orchestration_tasks
SET state = 'fix_proposed', last_heartbeat = datetime('now')
WHERE task_id = '{task-id}';
```
</template>
</core>
</section>

<section id="context-warning-detection-sql">
<core>
## Context Warning Detection SQL

Detect context warning (distinguished from regular errors by `last_error` value):

<template follow="exact">
```sql
SELECT task_id, state, last_error, retry_count
FROM orchestration_tasks
WHERE state = 'error' AND last_error = 'context_exhaustion_warning';
```
</template>

If this query returns results, use the context-warning-protocol section instead of the standard musician-error-workflow.
</core>
</section>

<section id="staleness-detection-sql">
<core>
## Staleness Detection SQL

Detect tasks with stale heartbeats (>9 minutes):

<template follow="exact">
```sql
SELECT task_id, state, last_heartbeat,
       (julianday('now') - julianday(last_heartbeat)) * 86400 as seconds_stale
FROM orchestration_tasks
WHERE state IN ('working', 'review_approved', 'review_failed', 'fix_proposed')
  AND (julianday('now') - julianday(last_heartbeat)) * 86400 > 540;
```
</template>

When stale tasks are found, proceed to stale-heartbeat-recovery section.
</core>
</section>

<section id="context-situation-checklist">
<core>
## Context Situation Checklist

When evaluating a Musician with context warnings or error reports:

- [ ] Self-correction flag active? (YES = context estimates ~6x bloat)
- [ ] Context usage vs task instruction estimates? (>2x = may need additional session)
- [ ] How many deviations and severity? (high severity + high context = risky)
- [ ] How far to next checkpoint? (far = higher risk)
- [ ] How many agents remain and at what cost? (many + high cost = likely to exceed budget)
- [ ] Prior context warnings on this task? (multiple = pattern of scope creep)
- [ ] Proposed action specificity? (vague = less confidence)

Use results to choose response: `review_approved` (proceed), `fix_proposed` (override approach), or `review_failed` (stop and handoff).
</core>
</section>

<section id="context-exhaustion-trigger">
<core>
## Context Exhaustion Trigger (Conductor)

The Conductor's pre-death sequence when detecting its own context exhaustion. This sequence must execute in strict order — `context_recovery` is the kill trigger that signals the Souffleur to terminate and relaunch the Conductor.

### Step 1: Write Handoff

Write handoff to `temp/HANDOFFS/Conductor/handoff.md` — single file, overwritten each time. Include:
- Current phase number and name
- Active tasks and their states
- Pending events (from MEMORY.md)
- In-progress decisions or notes
- Any relevant context the replacement Conductor should know

Content is freeform markdown — write whatever the dying Conductor considers useful for the replacement session.

### Step 2: Update MEMORY.md

Update MEMORY.md with:
- Plan path (for replacement Conductor to find the plan)
- Handoff location (`temp/HANDOFFS/Conductor/handoff.md`)
- Active task PIDs (for recovery cleanup)

### Step 3: Close All External Musician Sessions

For each active Musician task:

```bash
# 1. Set state to exited FIRST (before SIGTERM)
# SQL via comms-link:
# UPDATE orchestration_tasks SET state = 'exited', last_heartbeat = datetime('now') WHERE task_id = '{task_id}';

# 2. Kill the session
kill -0 $(cat temp/musician-{task_id}.pid) 2>/dev/null && kill $(cat temp/musician-{task_id}.pid)

# 3. Clean up PID file
rm temp/musician-{task_id}.pid
```
</core>

<mandatory>
States MUST be set to `exited` BEFORE sending SIGTERM. The stop hook blocks session exit for Musicians in non-terminal states like `working` or `needs_review`. If the Conductor sends SIGTERM first, the hook may prevent the session from exiting, leaving a zombie process.
</mandatory>

<core>
### Step 4: Set context_recovery State
</core>

<mandatory>
This MUST be the last step — after all Musicians are closed and all handoff data is written.

```sql
UPDATE orchestration_tasks
SET state = 'context_recovery', last_heartbeat = datetime('now')
WHERE task_id = 'task-00';
```

Setting `context_recovery` is the Souffleur's kill trigger. After this state is set, the Souffleur will terminate this Conductor session and launch a replacement. No further actions should be taken after this UPDATE — the session is effectively dead.
</mandatory>
</section>

</skill>
