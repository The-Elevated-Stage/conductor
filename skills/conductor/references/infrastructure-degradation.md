<skill name="conductor-infrastructure-degradation" version="5.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Infrastructure Degradation Protocol
</metadata>

<sections>
- detection
- escalation-ladder
- step-1-self-heal
- step-2-souffleur-relaunch
- step-3-post-relaunch
- step-4-critical-failure
- integration
</sections>

<section id="detection">
<core>
# Infrastructure Degradation Protocol

## Detection Criteria

The Conductor enters this protocol when it recognizes a pattern of tool degradation — not a single failure (that is a retry), but a systemic pattern.

**Triggers:**
- Same tool fails 3+ times in a row with non-task-related errors (e.g., bash returning "command not found" for a previously working command, MCP timeout on a tool that was working minutes ago)
- Multiple unrelated tools fail within a short window (systemic degradation — the session environment is breaking down)
- comms-link becomes unresponsive (most critical — this is the orchestration backbone; without it, the Conductor cannot monitor Musicians, send messages, or update state)

**Not triggers:**
- A single tool failure (retry normally)
- Musician-reported errors (route to Error Recovery Protocol)
- Expected failures (e.g., a file not found when checking if something exists)
</core>
</section>

<section id="escalation-ladder">
<core>
## Escalation Ladder

```
Step 1: Self-heal ──→ resolved? ──→ return to previous work
         │ no
         ▼
Step 2: Souffleur relaunch ──→ resolved? ──→ continue orchestration
         │ no (limit reached)
         ▼
Step 3: Post-relaunch workarounds ──→ resolved? ──→ continue
         │ no
         ▼
Step 4: Critical failure ──→ pause Musicians, report to user
```

Each step is described in its own section below.
</core>
</section>

<section id="step-1-self-heal">
<core>
## Step 1: Self-Heal

<mandatory>
The self-heal step is the most important step in this ladder. A Souffleur relaunch is disruptive — it pauses the entire orchestration, kills the Conductor session, and requires a full recovery bootstrap. The Conductor should treat escalation to Step 2 as a last resort, not a convenience.

Attempt at least DEGRADATION_FIX_ATTEMPTS (default 5) different approaches before escalating. This is a minimum recommendation, not a ceiling — more attempts are better. The Conductor may escalate sooner only if self-healing is provably impossible (e.g., comms-link is entirely unreachable after multiple connection attempts).
</mandatory>

**The Conductor determines approach.** No prescribed fixes — the right workaround depends on what is actually broken. Examples of self-heal strategies:

- **MCP timeout:** Retry with backoff. Try a simpler query first. Check if the MCP server process is alive.
- **Bash failures:** Try alternative commands. Check if PATH is correct. Try absolute paths.
- **comms-link unresponsive:** Retry connection. Check if the database file is accessible. Try a simple SELECT 1 query.
- **Multiple tools failing:** Consider whether the session environment is corrupted. Try resetting tool state.

**If resolved:** Return to the work that was in progress when degradation was detected.

**If still failing after thorough attempts:** Proceed to Step 2.
</core>
</section>

<section id="step-2-souffleur-relaunch">
<mandatory>
## Step 2: Request Souffleur Relaunch

ORDERING IS CRITICAL — follow the same sequence as the existing context-exhaustion-trigger in error-recovery.md. The state change is the Souffleur's kill trigger — once set, the Conductor may be killed at any moment. All persistent writes must complete first.

1. **Write learnings:** Append degradation details to `temp/conductor-learnings.log`:
   ```
   [{timestamp}] INFRASTRUCTURE DEGRADATION: {tool} failed {N} times. Attempted fixes: {list}. Requesting Souffleur relaunch.
   ```

2. **Insert message:** Record the degradation in orchestration_messages:
   ```sql
   INSERT INTO orchestration_messages (task_id, from_session, message, message_type) VALUES (
       'task-00', '$CLAUDE_SESSION_ID',
       'INFRASTRUCTURE DEGRADATION: Conductor tools degraded. Tool: {tool}. Failures: {N}. Self-heal attempts: {N}. Requesting relaunch.',
       'system'
   );
   ```

3. **Set state:** Trigger the Souffleur kill:
   ```sql
   UPDATE orchestration_tasks
   SET state = 'context_recovery', last_heartbeat = datetime('now')
   WHERE task_id = 'task-00';
   ```

The Souffleur detects the state change, kills the session, and relaunches via recovery bootstrap. The degradation context in the learnings file is preserved and read by the new Conductor during recovery Step 3.
</mandatory>
</section>

<section id="step-3-post-relaunch">
<core>
## Step 3: Post-Relaunch Fallback

If the same tool failures recur after a Souffleur relaunch, the problem may be environmental rather than session-specific. After DEGRADATION_RELAUNCH_LIMIT (default 2) failed relaunches, try any remaining workarounds not yet attempted.

The recovery bootstrap's learnings file reading (Step 3 in recovery-bootstrap.md) provides the history of what was tried. The new Conductor session should:

1. Read the degradation entries from `temp/conductor-learnings.log`
2. Try different approaches than what was already attempted
3. If resolved: continue orchestration normally

If no new approaches are available: proceed to Step 4.
</core>
</section>

<section id="step-4-critical-failure">
<mandatory>
## Step 4: Critical Failure

All self-heal options and Souffleur relaunches exhausted. The orchestration cannot continue autonomously.

1. **Pause all Musicians:** Send emergency broadcast to all active tasks:
   ```sql
   INSERT INTO orchestration_messages (task_id, from_session, message, message_type)
   VALUES ('{task-id}', 'task-00',
       'EMERGENCY: Conductor infrastructure critically degraded. All work paused. Awaiting user intervention.',
       'emergency');
   ```
   (One INSERT per active task_id.)

2. **Terminal output:** Print a clear summary for the user:
   ```
   === CRITICAL: Infrastructure Degradation ===
   Tool(s) failing: {list}
   Self-heal attempts: {N}
   Souffleur relaunches: {N}
   What was tried: {summary}

   The orchestration cannot continue automatically.
   Please investigate the tool failures and restart the Conductor.
   =============================================
   ```

3. **Set state:**
   ```sql
   UPDATE orchestration_tasks
   SET state = 'exit_requested', last_heartbeat = datetime('now')
   WHERE task_id = 'task-00';
   ```
</mandatory>
</section>

<section id="integration">
<core>
## Integration with Other Protocols

**Error Recovery Protocol:** Infrastructure degradation is distinct from Musician errors. If the Conductor encounters tool failures while handling a Musician error, it enters this protocol, resolves the tool issue, then returns to error recovery. The two protocols do not overlap — one handles Musician problems, the other handles Conductor problems.

**Recovery Bootstrap Protocol:** No changes needed. The recovery bootstrap already reads `temp/conductor-learnings.log` (Step 3) and reconstructs state from the database. Degradation context flows naturally through the existing recovery pipeline.

**Completion Protocol:** If the Conductor detects degradation during the completion phase, it should still attempt self-healing. Escalating to Souffleur relaunch during completion is wasteful — the work is done, only final verification remains. Prefer reporting the degradation to the user and letting them decide.
</core>
</section>

</skill>
