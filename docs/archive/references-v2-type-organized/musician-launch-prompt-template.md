<skill name="conductor-musician-launch-prompt-template" version="2.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
</metadata>

<sections>
- overview
- template
- conductor-usage
- launching-multiple-tasks
- launching-replacement-sessions
- design-points
- integration
</sections>

<section id="overview">
<context>
# Musician Launch Prompt Template

When launching execution sessions (sequential or parallel), use this template for each session. The conductor launches kitty windows directly via the Bash tool — no user intervention needed.
</context>

<mandatory>All external execution sessions must use this template. Do not deviate from this pattern.</mandatory>
</section>

<section id="template">
<core>
## Template

Replace `{{TASK_ID}}`, `{{PHASE_NUMBER}}`, and `{{PHASE_NAME}}` with actual values.

### Kitty Launch Command
</core>

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: {{TASK_ID}}" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
\`\`\`sql
SELECT message FROM orchestration_messages
WHERE task_id = '{{TASK_ID}}' AND message_type = 'instruction';
\`\`\`

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: {{TASK_ID}}
- Phase: {{PHASE_NUMBER}} — {{PHASE_NAME}}

Do not proceed without reading the full instruction message. All steps are there." &
```
</template>

<context>
The `&` at the end detaches the kitty process so the conductor's Bash call returns immediately.
</context>
</section>

<section id="conductor-usage">
<core>
## Conductor Usage

When launching a session, substitute the placeholders with actual values and execute via the Bash tool:

| Placeholder | Source | Example |
|---|---|---|
| `{{TASK_ID}}` | Task ID from orchestration plan | `task-03` |
| `{{PHASE_NUMBER}}` | Phase number from plan | `2` |
| `{{PHASE_NAME}}` | Phase name from plan | `Core API Implementation` |

### Example: Filled-In Launch Command
</core>

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: task-03" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
\`\`\`sql
SELECT message FROM orchestration_messages
WHERE task_id = 'task-03' AND message_type = 'instruction';
\`\`\`

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

**Context:**
- Task ID: task-03
- Phase: 2 — Core API Implementation

Do not proceed without reading the full instruction message. All steps are there." &
```
</template>
</section>

<section id="launching-multiple-tasks">
<core>
### Launching Multiple Tasks (Parallel Phase)

For parallel phases, launch all tasks by issuing one Bash call per task. Use parallel Bash tool calls (one per kitty window) so all sessions start simultaneously:

```
Bash: kitty --directory /home/kyle/claude/remindly --title "Musician: task-03" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician ..." &
Bash: kitty --directory /home/kyle/claude/remindly --title "Musician: task-04" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician ..." &
Bash: kitty --directory /home/kyle/claude/remindly --title "Musician: task-05" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician ..." &
Bash: kitty --directory /home/kyle/claude/remindly --title "Musician: task-06" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician ..." &
```
</core>
</section>

<section id="launching-replacement-sessions">
<core>
### Launching Replacement Sessions (Handoff)

For session handoffs, launch a replacement kitty window with the same template. The new session picks up from the handoff state in the database:
</core>

<template follow="exact">
```bash
kitty --directory /home/kyle/claude/remindly --title "Musician: {{TASK_ID}} (S2)" -- env -u CLAUDECODE claude --permission-mode acceptEdits "/musician

Load the musician skill first, then proceed.

**Your task:**

Run this SQL query via comms-link:
\`\`\`sql
SELECT message FROM orchestration_messages
WHERE task_id = '{{TASK_ID}}' AND message_type = 'instruction';
\`\`\`

Read the returned message. It contains your complete task instructions for this phase. Follow every step, checkpoint, and requirement exactly as specified.

Previous session: {{PREVIOUS_WORKED_BY}}
New session will be: {{NEW_WORKED_BY}}
Read HANDOFF from temp/ for context.

**Context:**
- Task ID: {{TASK_ID}}
- Phase: {{PHASE_NUMBER}} — {{PHASE_NAME}}

Do not proceed without reading the full instruction message. All steps are there." &
```
</template>
</section>

<section id="design-points">
<context>
## Key Design Points

- **`/musician` first:** Skill loads automatically and provides musician context
- **SQL query explicit:** Musician doesn't need to discover table structure or message types
- **Message-driven:** Task instructions live in the database message, not passed in prompt (saves musician context)
- **No hardcoded paths:** File paths are in the message content, reducing bootstrap cognitive load
- **Concise:** Minimal but complete bootstrap information
- **Kitty windows:** Each task runs in its own OS window for visual separation and independent lifecycle
- **Background launch:** `&` suffix ensures conductor is not blocked by the kitty process
</context>
</section>

<section id="integration">
<context>
## Integration with Copyist Skill

The copyist skill (when creating task instruction files) should include instructions for execution sessions to:
1. Invoke `/musician` skill
2. Run the provided SQL query
3. Read the returned message
4. Follow all steps in the message

See `copyist` skill references for task template integration.
</context>

<core>
## Reference in Conductor Skill

The conductor references this template in the "Launching Execution Sessions" section:
- **Sequential tasks:** Launch one kitty window at a time using this template
- **Parallel tasks:** Launch one kitty window per task simultaneously using this template

See SKILL.md "Launching Execution Sessions" section for context on when and how to use this template.
</core>
</section>

</skill>
