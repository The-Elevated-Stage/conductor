<skill name="conductor-rag-query-guide" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- overview
- conductor-queries
- execution-queries
- infrastructure-queries
- template-queries
- decision-workflow-queries
- overlap-detection-queries
- query-tips
- recommended-workflow
- file-to-query-map
</sections>

<section id="overview">
<core>
# RAG Query Guide for Orchestration

## Overview

18 comprehensive RAG files (13,471 lines) are ingested in the local-rag MCP server, covering all aspects of autonomous parallel orchestration.

**Score interpretation:** < 0.3 = good match, 0.3-0.5 = moderate, > 0.5 = refine query.
</core>
</section>

<section id="conductor-queries">
<core>
## Quick Reference: Query by Need

### Conductor Queries

| Need | Query |
|------|-------|
| Architecture overview | `autonomous parallel orchestration architecture when to use pattern selection` |
| Conductor initialization | `conductor initialization setup database custom hook activation` |
| Batch coordination | `batch coordination parallel tasks launch background subagent monitoring` |
| Review workflow | `conductor review approval workflow execution checkpoint proposal evaluation` |
| Error triage | `conductor error triage retry logic decision tree fix proposal` |
| Completion workflow | `conductor completion detection integration verification final state` |
| Context monitoring | `conductor context budget runtime token tracking smoothness scale` |
| Conductor state machine | `conductor state transitions state machine exit criteria custom hooks` |
</core>
</section>

<section id="execution-queries">
<core>
### Execution Queries

| Need | Query |
|------|-------|
| Execution initialization | `execution session initialization atomic claim pattern hook setup` |
| Coordination checkpoints | `execution coordination checkpoints review request blocking subagent approval` |
| Error reporting | `execution error reporting structured template retry logic terminal error` |
| Execution state machine | `execution session states state machine transitions lifecycle custom hooks` |
| Step patterns | `execution step patterns verification completion criteria completion report` |
</core>
</section>

<section id="infrastructure-queries">
<core>
### Infrastructure Queries

| Need | Query |
|------|-------|
| Database DDL | `database setup initialization DDL schema all tables CHECK constraints` |
| State machine schema | `state machine database schema all states CHECK constraints single table orchestration_tasks` |
| Session isolation | `session isolation atomic claim crash recovery session ID naming convention` |
| Hook configuration | `custom hook setup implementation-hook preset configuration exit criteria` |
</core>
</section>

<section id="template-queries">
<core>
### Template Queries

| Need | Query |
|------|-------|
| All SQL patterns | `SQL patterns coordination database queries templates conductor execution` |
| Error report template | `error report template structured format examples retry count stack trace` |
| Completion report template | `completion report template structure sections verification results context budget` |
| Bash scripts | `bash scripts session ID generation database queries hook activation` |
</core>
</section>

<section id="decision-workflow-queries">
<core>
### Decision & Workflow Queries

| Need | Query |
|------|-------|
| Complete workflow | `autonomous orchestration workflow complete phases decision trees integration` |
| Parallelization decision | `parallelization decision matrix write conflicts danger files pattern selection` |
| Pattern selection | `when to use autonomous parallel orchestration vs sequential vs subagent-driven` |
| Anti-patterns | `anti-patterns learnings mistakes to avoid best practices autonomous orchestration` |
| Danger files | `danger files protocol shared resources barrel exports coordination batching` |
</core>
</section>

<section id="overlap-detection-queries">
<core>
### Overlap Detection Queries

Used by the overlap-check subagent during RAG proposal processing. These queries help identify existing knowledge-base content that may overlap with a proposed RAG addition.

| Need | Query Pattern |
|------|---------------|
| Check for topic overlap | `[proposed file's primary topic] [key technical terms from proposal]` |
| Find related patterns | `[category] [parent_topic value from proposal frontmatter]` |
| Check for duplicate decisions | `decision rationale [specific decision topic]` |
| Find existing anti-patterns | `anti-pattern [topic] what NOT to do` |

**Threshold for overlap detection:** Query at 0.5 (full moderate range). Interpret results:
- **< 0.3:** Strong overlap — likely duplicate or very closely related. Flag for user review.
- **0.3-0.4:** Moderate overlap — related content exists. Include in review with merge recommendation.
- **0.4-0.5:** Weak overlap — tangentially related. Note but recommend approving as new file.
- **> 0.5:** No meaningful overlap. Safe to ingest as new file.
</core>

<context>
**Important:** The musician pre-screens at 0.4 threshold and includes matches in the proposal. The overlap subagent uses these as a head start but must query at 0.5 to catch the 0.4-0.5 band the musician missed.
</context>
</section>

<section id="query-tips">
<guidance>
## Query Tips

1. **Include role** — `conductor error handling` not just `error handling`
2. **Add action verbs** — `initialize conductor setup` not just `conductor setup`
3. **Specify document type** — `SQL patterns templates` not just `patterns`
4. **Use technical terms** — `CHECK constraints state enumeration` not just `database validation`
5. **Query for examples** — `example TypeError error report stack trace` not just `error report format`
</guidance>
</section>

<section id="recommended-workflow">
<guidance>
## Recommended Workflow

For task instruction creation:

1. Architecture overview (pattern appropriate?)
2. Setup requirements (DDL, initialization)
3. Role-specific initialization (conductor or execution)
4. Coordination patterns (reviews, monitoring)
5. Error handling (triage, reporting)
6. Completion workflow (detection, integration)
7. SQL patterns (all needed queries)
8. State machine (transitions, terminal states)
9. Quality standards (smoothness scale)
10. Assemble into instruction file
</guidance>
</section>

<section id="file-to-query-map">
<core>
## File-to-Query Map

| File | Query |
|------|-------|
| `autonomous-parallel-orchestration-complete-architecture.md` | `autonomous parallel orchestration architecture when to use` |
| `state-machine-database-schema-complete.md` | `state machine database schema all states CHECK constraints` |
| `conductor-initialization-setup-complete.md` | `conductor initialization setup database custom hook` |
| `batch-coordination-review-approval-complete.md` | `batch coordination review approval background subagent` |
| `error-triage-retry-logic-complete.md` | `conductor error triage retry logic decision tree` |
| `completion-integration-verification-complete.md` | `conductor completion integration verification final` |
| `context-budget-smoothness-scale-complete.md` | `context budget smoothness scale quality rubric` |
| `conductor-state-transitions-complete.md` | `conductor state transitions exit criteria hooks` |
| `danger-files-anti-patterns-learnings.md` | `danger files anti-patterns shared resources batching` |
| `execution-initialization-atomic-claim-complete.md` | `execution initialization atomic claim pattern hook` |
| `execution-coordination-checkpoints-complete.md` | `execution coordination checkpoints review request blocking` |
| `error-reporting-execution-complete.md` | `execution error reporting structured template retry` |
| `execution-state-transitions-session-lifecycle-complete.md` | `execution session states lifecycle transitions hooks` |
| `execution-step-patterns-verification-complete.md` | `execution step patterns verification completion report` |
| `autonomous-orchestration-setup-initialization-complete.md` | `database setup initialization DDL complete all tables` |
| `autonomous-orchestration-workflow-decision-trees-complete.md` | `workflow phases decision trees parallelization matrix` |
| `autonomous-orchestration-templates-complete.md` | `SQL patterns templates error report completion report` |
</core>
</section>

</skill>
