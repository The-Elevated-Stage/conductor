<skill name="conductor-sentinel-monitoring" version="4.0">

<metadata>
type: reference
parent-skill: conductor
tier: 3
protocol: Sentinel Monitoring Protocol
</metadata>

<sections>
- concept
- anomaly-criteria
- behavior
- lifecycle
- prompt-template
- report-format
- temp-file-reference
- relationship-to-watcher
</sections>

<section id="concept">
<core>
# Sentinel Monitoring Protocol

The Sentinel is a lightweight teammate that watches all active Musicians' temp/ logs in real time and reports anomalies to the Conductor before they escalate into full errors. While the background message-watcher monitors the comms-link database for orchestration state changes, the Sentinel monitors the human-readable temp/ files for signs of trouble that haven't yet risen to the level of a state change.

The Sentinel operates on a fire-and-forget model: it detects, reports, and resumes. It does not diagnose, does not propose fixes, and does not wait for instructions. The Conductor receives its reports and decides independently whether action is warranted.
</core>
</section>

<section id="anomaly-criteria">
<mandatory>
## Anomaly Detection Criteria

The Sentinel watches for exactly four anomaly types. These are mechanical checks — no interpretation or judgment.

1. **Self-correction entry** — any line containing `self-correction` in `temp/task-{NN}-status`
2. **High severity deviation** — any line starting with `High:` in `temp/task-{NN}-deviations`
3. **Context usage spike** — context percentage jumps more than 15% between consecutive entries in `temp/task-{NN}-status`
4. **Stalled progress** — no new entries in `temp/task-{NN}-status` for more than 5 minutes

No other patterns trigger a report. The Sentinel does not interpret content, assess severity beyond these four criteria, or make recommendations.
</mandatory>
</section>

<section id="behavior">
<core>
## Polling and Reporting Behavior

The Sentinel reads all active Musicians' temp/ files on a ~10 second polling cycle:

1. Read `temp/task-{NN}-status` and `temp/task-{NN}-deviations` for each active task ID
2. Compare current content against last-seen content (track internally)
3. If any of the four anomaly criteria are detected, send a report to the Conductor via SendMessage
4. Immediately resume polling — do not wait for a response, do not pause, do not exit

<mandatory>The Sentinel never waits for Conductor responses. Every report is fire-and-forget. The Sentinel's only job is detection and reporting — the Conductor handles all decision-making.</mandatory>

If a file does not exist yet (Musician hasn't created it), skip it silently. If a file stops being updated, the "stalled progress" criterion will trigger after 5 minutes.
</core>
</section>

<section id="lifecycle">
<core>
## Lifecycle

One Sentinel instance per phase. The lifecycle is simple:

**Launch:** When the Conductor launches Musicians for a phase, it also launches the Sentinel as a teammate using the Task tool with `team_name` set to the orchestration team. The Sentinel receives the list of active task IDs to monitor.

**Run:** The Sentinel polls continuously throughout phase execution, running alongside the background message-watcher. They are independent — neither depends on or coordinates with the other.

**Shutdown:** When the phase completes (all tasks reach terminal state), the Conductor sends the Sentinel a message: "Phase complete, shut down." The Sentinel acknowledges and exits.

If the Conductor enters the Repetiteur Protocol (all Musicians paused), the Sentinel also shuts down — there are no active temp/ files to monitor during re-planning. A new Sentinel is launched when Musicians resume.
</core>
</section>

<section id="prompt-template">
<core>
## Sentinel Launch Prompt

<template follow="format">
You are the Sentinel — a monitoring teammate watching Musicians' progress logs for anomalies.

**Active tasks to monitor:** {TASK_ID_LIST}

**Your job:** Read the following files every ~10 seconds:
- `temp/task-{NN}-status` for each active task
- `temp/task-{NN}-deviations` for each active task

**Report these anomalies via SendMessage (fire-and-forget):**
1. Any line containing `self-correction` in a status log
2. Any line starting with `High:` in a deviations log
3. Context usage jumping more than 15% between consecutive status entries
4. No new entries in a status file for more than 5 minutes

**Report format:**
```
SENTINEL: [task-id]
Anomaly: [type — self-correction | high-deviation | context-spike | stalled]
Detail: [relevant data]
```

**Rules:**
- Do NOT wait for responses after sending a report — immediately resume polling
- Do NOT interpret or diagnose — just detect and report
- If a temp file doesn't exist yet, skip it silently
- Track what you've already reported to avoid duplicate reports for the same anomaly
- Continue until I message you to shut down
</template>
</core>
</section>

<section id="report-format">
<core>
## Anomaly Report Format

<template follow="format">
SENTINEL: [{timestamp}] {task-id}
Anomaly: {type}
Detail: {relevant data}
</template>

Examples:

**Self-correction detected:**
```
SENTINEL: [14:32:07] task-03
Anomaly: self-correction
Detail: "step 2 self-correction: test failure in parser, rewrote tokenizer [ctx: 34%]"
```

**Context spike:**
```
SENTINEL: [14:35:22] task-05
Anomaly: context-spike
Detail: Context jumped from 29% to 51% between step 2 and step 3 (+22%)
```

**Stalled progress:**
```
SENTINEL: [14:41:03] task-04
Anomaly: stalled
Detail: No new entries in temp/task-04-status for 7 minutes. Last entry: "step 3 agent 1 launched [ctx: 41%]"
```
</core>
</section>

<section id="temp-file-reference">
<context>
## Temp File Reference

The Sentinel reads temp/ files whose format is defined by the Musician skill. The Sentinel does not define or control these formats — it depends on Musicians writing entries in the expected patterns.

**Files the Sentinel monitors:**
- `temp/task-{NN}-status` — append-only execution log with context percentages and step markers
- `temp/task-{NN}-deviations` — severity-tagged deviation entries (Low/Medium/High)

**Files the Sentinel ignores:**
- `temp/task-{NN}-HANDOFF` — written only on clean exit, not during active execution
- `temp/musician-task-{NN}.pid` — PID tracking file, managed by the Conductor

The anomaly criteria depend on specific patterns in these files:
- `self-correction` keyword in status entries
- `High:` prefix in deviation entries
- `[ctx: XX%]` markers in status entries for context tracking
- Timestamp-based staleness detection from entry frequency
</context>
</section>

<section id="relationship-to-watcher">
<context>
## Relationship to Background Message-Watcher

The Sentinel and the background message-watcher serve different purposes and operate independently:

| | Background Message-Watcher | Sentinel |
|---|---|---|
| **Monitors** | comms-link database (orchestration state) | temp/ files (execution progress) |
| **Detects** | State changes (needs_review, error, complete) | Anomalies (self-correction, deviations, stalls) |
| **On detection** | Exits immediately — Conductor handles event | Sends report, continues polling |
| **Lifecycle** | Relaunched after every event handling cycle | Runs continuously until phase complete |
| **Type** | Regular Task subagent (background) | Teammate (SendMessage capability) |

The Sentinel is purely additive. The orchestration system works without it — the message-watcher handles all critical state transitions. The Sentinel adds proactive quality detection that catches problems earlier, before they escalate to database-level state changes.
</context>
</section>

</skill>
