<skill name="conductor-orchestration-principles" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- context-headroom
- external-sessions-vs-subagents
- delegation-patterns
- overload-signs
</sections>

<section id="context-headroom">
<core>
# Orchestration Principles

## Context Headroom is Valuable

The conductor's 200k-token context window is a shared resource. Every token spent on implementation detail is a token unavailable for coordination, review, and strategic decisions.

**Use conductor context for:**
- Wide-scope understanding of the full plan and all task states
- Strategic decisions: phase ordering, danger file mitigations, parallelism choices
- Cross-task coordination: detecting conflicts, managing shared resources
- Quality assurance: reviewing proposals, evaluating smoothness scores
- Error triage: analyzing root causes, proposing fixes across tasks

**Delegate to subagents for:**
- Task instruction creation (plan content — too expensive to hold in conductor context)
- Background monitoring (polling database every 30 seconds)
- RAG queries and document retrieval

**Delegate to external execution sessions for:**
- All implementation work (code, tests, documentation, file creation)
- Step-by-step task execution
- Verification and testing
- Completion reporting

This delegation strategy keeps the conductor's context free for what only the conductor can do: see the full picture across all tasks simultaneously.

### Context Budget Guidelines

Typical context costs per conductor action:

| Action | Cost | Frequency |
|--------|------|-----------|
| Read implementation plan | 5-15k tokens | Once |
| Read STATUS.md (full) | 2-5k tokens | 2-3 times per orchestration |
| Review proposal | 2-5k tokens per review | Per checkpoint |
| Error analysis | 3-8k tokens per error | Per error |
| Database query results | 0.5-1k tokens | Frequent |
| Monitoring subagent launch | 0.5k tokens | Per relaunch |
</core>

<context>
For a 10-task orchestration with 2 phases: expect 40-80k tokens of conductor context usage, leaving 120-160k tokens of headroom for unexpected events.
</context>
</section>

<section id="external-sessions-vs-subagents">
<mandatory>
## External Sessions Are Not Subagents

This distinction is the most common source of confusion. Confusing these breaks the orchestration model.
</mandatory>

<core>
### External Execution Sessions (Tier 1)

- Full Claude Code sessions launched in **separate kitty windows** by the conductor via the Bash tool
- Have their **own 200k-token context** — completely independent from conductor
- Execute task instructions **autonomously** — read instruction file, follow steps, report via database
- Coordinate via **comms-link database** — read messages, write state changes
- Conductor **launches these directly** — `kitty --directory /home/kyle/claude/remindly --title "..." -- env -u CLAUDECODE claude --permission-mode acceptEdits "prompt" &` via Bash tool
- Can launch their own subagents (Tier 2) for implementation work
- Exit when task reaches `complete` or `exited` state

### Subagents (Tier 2, or Conductor's Own)

- Spawned by the conductor (or by Tier 1 sessions) using the **Task tool**
- Run **within the parent session's context budget** — they share context pressure
- Used for: task instruction creation, monitoring, RAG queries
- Cannot launch external processes or kitty windows
- Return results directly to the spawning session
- Ephemeral — no persistent state between invocations

### Why This Matters

**Wrong mental model:** "I'll launch a subagent to implement task-03"
- Subagents have limited context and cannot interact with terminals, git, or complex toolchains
- Implementation requires full Claude Code capabilities

**Correct mental model:** "I'll launch a kitty window for task-03, then monitor via database"
- Execution sessions have full capabilities and independent context
- Database coordination handles communication asynchronously

### Quick Reference

| Capability | External Session | Subagent |
|-----------|-----------------|----------|
| Context window | Own 200k | Shared with parent |
| Launch method | Conductor runs `kitty --directory /home/kyle/claude/remindly -- env -u CLAUDECODE claude --permission-mode acceptEdits "prompt"` via Bash | Task tool in code |
| Git operations | Yes | Yes |
| File editing | Yes | Yes |
| Launch sub-subagents | Yes (Tier 2) | Limited |
| Persistent state | Via database | None (ephemeral) |
| Exit control | Hook-based (`complete`/`exited`) | Returns to parent |
| Who launches | Conductor (via kitty + Bash tool) | Conductor or Tier 1 session |
</core>
</section>

<section id="delegation-patterns">
<core>
## Delegation Patterns

### What the Conductor Keeps

- Plan interpretation and phase ordering decisions
- Danger file risk assessment and mitigation strategy
- Review evaluation (smoothness scoring, approve/reject decisions)
- Error triage and fix proposal creation
- Cross-task coordination (detecting when task-04 depends on task-03 output)
- User communication and escalation
- STATUS.md and database state management

### What Gets Delegated to Subagents

- Task instruction file creation (via `copyist` skill)
- Background database polling (monitoring subagents)
- RAG document queries (pre-fetching context for instruction creation)
- Validation script execution (checking instruction quality)

### What Gets Delegated to External Sessions

- All code writing, testing, and verification
- File creation and modification in target directories
- Git commits within the feature branch
- Completion reports and proposal generation
- Self-review and checkpoint reporting

### Anti-Patterns
</core>

<guidance>
**Conductor doing implementation work:**
The conductor should never write code, create documentation files, or run tests directly. This consumes context that should be reserved for coordination.

**Subagent for complex implementation:**
Subagents lack the full Claude Code environment needed for complex multi-step implementation. Use external sessions instead.

**External session for monitoring:**
External sessions are expensive (200k context each) and user-launched. Don't use them for simple polling tasks that subagents handle well.
</guidance>
</section>

<section id="overload-signs">
<core>
## Signs the Conductor is Overloaded

Watch for these indicators and take corrective action.

### Context Pressure

- **> 70% context used:** Complete current action, then write Recovery Instructions to STATUS.md. Set state to `exit_requested` and exit. A new session resumes with fresh context.
- **Growing context without progress:** If context increases 20k+ tokens without completing a review or handling an event, the conductor is reading too much. Use database queries instead of file reads.

### Cognitive Overload

- **Monitoring cycle takes > 5 minutes of reasoning:** Too many parallel tasks or too complex a review. Simplify: reduce parallelism, break tasks into smaller units, or add more review checkpoints.
- **Repeated re-reading of the same information:** The conductor is losing track. Write key facts to STATUS.md Task Planning Notes as working memory, then reference those notes instead of re-reading source files.
- **Many simultaneous state changes:** If 4+ tasks change state in the same monitoring cycle, handle them one at a time in priority order: `error` first, then `needs_review`, then `complete`.

### Recovery Actions

| Symptom | Action |
|---------|--------|
| Context > 70% | Write Recovery Instructions, exit, resume in new session |
| Many parallel events | Handle one at a time: errors, reviews, completions (in that order) |
| Re-reading same files | Write summaries to Task Planning Notes, reference notes instead |
| Subagent failures accumulating | Fall back to manual monitoring with `validate-coordination.sh` |
| User unresponsive to escalation | Pause orchestration, set conductor to `exit_requested` with clear resumption instructions |
</core>
</section>

</skill>
