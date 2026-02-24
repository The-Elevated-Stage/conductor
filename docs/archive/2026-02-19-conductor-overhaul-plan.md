# Conductor Skill Overhaul — Implementation Plan

> **For Claude:** This plan restructures skill files, not application code. Steps involve content migration, teammate coordination, and review — not TDD cycles. Execute phases in order. Each phase has verification before proceeding.

**Goal:** Transform the Conductor skill from a monolithic markdown file into a protocol-dispatching architecture with prompt-style SKILL.md and protocol-organized reference files.

**Architecture:** Protocol-dispatching SKILL.md (~250 lines) routes to 8 protocol reference files. Content migrated from 15 type-organized files to protocol-organized files via teammate extraction proposals then content creation. See design document for full architecture.

**Key Artifacts:**
- Design: `skills_staged/orchestration/docs/designs/2026-02-19-conductor-overhaul-design.md`
- SKILL.md skeleton: `skills_staged/orchestration/docs/designs/conductor-skill-skeleton-v3.md`
- Current skill: `skills_staged/conductor/`

---

## Phase 1: Naming Cleanup

**Goal:** Update all old terminology across the 23 Conductor files before any content changes, preventing downstream confusion.

**Files:** All files in `skills_staged/conductor/` (SKILL.md + 15 references + 7 examples)

### Step 1: Find old names

Search all 23 files for:
- `Orchestrator` (old name for Conductor)
- `Task-Writer` or `Task Writer` (old name for Copyist)
- `Executor` (old name for Musician)
- `docs/plans/implementation/` (old path, canonical is `docs/tasks/`)
- `200k` context budget references (now 1m)
- `STATUS.md` references (eliminated)

Record all findings with file and line numbers.

### Step 2: Apply replacements

- `Orchestrator` → `Conductor`
- `Task-Writer` / `Task Writer` → `Copyist`
- `Executor` → `Musician`
- `docs/plans/implementation/` → `docs/tasks/`
- `200k` context references → `1m` (where referring to Conductor budget)
- `STATUS.md` references → remove or replace per context

### Step 3: Verify and commit

Review each replacement for correctness (some may be in narrative context that needs rewording, not just find-and-replace).

```bash
cd skills_staged/conductor
git add -A
git commit -m "chore: update terminology and paths across all Conductor files"
```

**Verification:** Grep for all old terms — zero matches expected.

---

## Phase 2: SKILL.md Replacement

**Goal:** Replace the current monolithic SKILL.md with the approved protocol-dispatching skeleton.

### Step 1: Back up current SKILL.md

```bash
cp skills_staged/conductor/SKILL.md skills_staged/conductor/docs/archive/SKILL-v2-monolithic.md
```

### Step 2: Install skeleton as SKILL.md

Copy the approved skeleton to replace SKILL.md:

```bash
cp skills_staged/orchestration/docs/designs/conductor-skill-skeleton-v3.md skills_staged/conductor/SKILL.md
```

### Step 3: Commit

```bash
cd skills_staged/conductor
git add SKILL.md docs/archive/SKILL-v2-monolithic.md
git commit -m "refactor: replace monolithic SKILL.md with protocol-dispatching skeleton v3"
```

**Verification:** Read SKILL.md, confirm it matches the skeleton. Confirm old SKILL.md is archived.

---

## Phase 3a: Extraction Proposals

**Goal:** Map every piece of content from the 15 existing reference files to its target protocol file. Pure exploration — no file creation yet.

### Step 1: Create staging directory

```bash
mkdir -p skills_staged/conductor/references/protocols
mkdir -p skills_staged/conductor/temp/proposals
```

### Step 2: Launch extraction teammates

Create a team. Launch one Opus teammate per target protocol file (8 teammates). Each teammate receives:

**Prompt template (adapted per protocol):**
```
You are extracting content for the [PROTOCOL NAME] protocol reference file.

Read ALL 15 reference files in skills_staged/conductor/references/ (exclude the protocols/ subdirectory).
Also read the design document at skills_staged/orchestration/docs/designs/2026-02-19-conductor-overhaul-design.md (Section 12 has the file mapping table).

For each piece of content that belongs in [PROTOCOL NAME], produce a proposal entry:

## [Brief description of content]
**Source:** references/[filename].md, lines [start]-[end]
**Authority:** [mandatory|core|guidance|context] (preserve original classification)
**Proposed section ID:** [section-id-in-new-file]
**Duplication note:** [if this content also belongs in another protocol, note which one]
**Modification needed:** [none / describe what the design document says should change]

Write your complete proposal to: skills_staged/conductor/temp/proposals/[protocol-name]-proposal.md

IMPORTANT:
- This is exploration only — do NOT create the protocol file
- Duplication across protocols is expected and correct (SQL co-location)
- If content doesn't clearly belong to any protocol, include it with a "UNCERTAIN" flag
- Preserve authority classifications — mandatory stays mandatory
- Note where the design document specifies content changes vs pure migration
```

**Teammates to launch (one each):**
1. `initialization` — bootstrap, database DDL, plan loading
2. `phase-execution` — phase workflow, Copyist, Musicians, monitoring
3. `review-protocol` — review checklists, scoring, approvals
4. `error-recovery` — error classification, fix proposals, retries
5. `repetiteur-invocation` — spawn, blocker report, handoff
6. `musician-lifecycle` — PID, cleanup, resume, context exit
7. `sentinel-monitoring` — temp log watcher, anomaly criteria
8. `completion` — final verification, PR, cleanup

### Step 3: Review proposals for completeness

After all teammates report, verify:

1. **Coverage check:** Every paragraph in every original reference file appears in at least one proposal. Create a checklist by reading each original file and confirming each section is claimed.

2. **Scope check:** No proposal includes content outside its protocol's scope. Flag any that do.

3. **Authority preservation:** Content tagged `<mandatory>` in original files stays `<mandatory>` in proposals.

4. **UNCERTAIN flags:** Resolve any uncertain content assignments.

5. **Deletion check:** Confirm `status-md-reading-strategy.md` and `recovery-instructions-template.md` are not claimed by any proposal (they should be deleted, not migrated).

6. **Absorption check:** Confirm `orchestration-principles.md` content is flagged for SKILL.md absorption, not claimed by a protocol file.

### Step 4: Iterate if needed

If coverage gaps or scope issues are found, message the relevant teammate to revise. Teammates are resumable.

### Step 5: Approve proposals

When all proposals pass the review checks, mark Phase 3a as complete.

**Verification:** Every original reference file paragraph is accounted for in proposals. Zero UNCERTAIN flags remaining. Proposals committed for reference:

```bash
cd skills_staged/conductor
git add temp/proposals/
git commit -m "docs: extraction proposals for protocol reference restructuring"
```

---

## Phase 3b: Content Creation

**Goal:** Create the 8 new protocol reference files from approved proposals plus design document changes.

### Step 1: Launch content creation teammates

Reuse the same team or create a new one. One Opus teammate per protocol file. Each teammate receives:

**Prompt template (adapted per protocol):**
```
Create the [PROTOCOL NAME] protocol reference file for the Conductor skill.

Work from these inputs:
1. Your approved extraction proposal at: skills_staged/conductor/temp/proposals/[protocol-name]-proposal.md
   — This is your checklist. Every item in the proposal MUST appear in the output file.
2. The design document at: skills_staged/orchestration/docs/designs/2026-02-19-conductor-overhaul-design.md
   — Section [N] describes content changes and additions for this protocol.
3. The original reference files at: skills_staged/conductor/references/
   — Read the exact source lines from each proposal entry.

Write the protocol file to: skills_staged/conductor/references/protocols/[protocol-name].md

Format: Tier 3 with <skill> wrapper. Use the Musician watcher-protocol as your template:
skills_staged/musician/references/watcher-protocol.md

Rules:
- Every proposal entry must be present in the output — check off each one
- Apply modifications noted in proposals (from design document)
- Add NEW content from the design document that wasn't in original files
- SQL templates that must be reproduced exactly: <template follow="exact">
- Message format patterns: <template follow="format">
- All text inside authority tags — no naked markdown (Tier 3 strict)
- At protocol boundaries, name the next protocol — do NOT reference other protocol files directly
- Use exact protocol names from the SKILL.md registry:
  Initialization Protocol, Phase Execution Protocol, Review Protocol,
  Error Recovery Protocol, Repetiteur Protocol, Musician Lifecycle Protocol,
  Sentinel Monitoring Protocol, Completion Protocol
- Co-locate SQL where it's used — duplication across protocols is correct

Pause and message me if you encounter:
- Proposal entries that conflict with the design document
- Content that doesn't fit cleanly into Tier 3 structure
- Uncertainty about authority classification for new content
```

### Step 2: Review each protocol file

As teammates complete, review each file for:

1. **Proposal coverage:** Every proposal entry is present
2. **Design additions:** New content from design document is included
3. **Tier 3 compliance:** All text inside tags, no naked markdown
4. **Protocol scoping:** File describes only its protocol's work
5. **Boundary naming:** At boundaries, names next protocol (exact registry name), doesn't reference other files directly
6. **Template correctness:** SQL has `follow="exact"`, message formats have `follow="format"`

### Step 3: Cross-reference check

Launch a dedicated review **teammate** (not a one-shot subagent — it needs to be resumable if issues are found). The review teammate:

- Reads every approved proposal in `temp/proposals/`
- Reads every created protocol file in `references/protocols/`
- For each proposal entry, verifies it appears in the corresponding protocol file
- Reports findings: matched entries, missing entries, authority classification mismatches
- Also checks the original 15 reference files to confirm no content dropped that wasn't in any proposal

The review teammate reports its findings. If it finds missing content, message the relevant content creation teammate to add it (teammates are resumable). Iterate until the review teammate reports zero gaps.

### Step 4: Commit protocol files

```bash
cd skills_staged/conductor
git add references/protocols/
git commit -m "feat: create protocol-organized reference files from extraction proposals"
```

**Verification:** 8 protocol files in `references/protocols/`. Cross-reference check passes. All proposal entries accounted for.

---

## Phase 4: SKILL.md Refinement

**Goal:** Update SKILL.md with precise reference pointers to the now-complete protocol files and add inline reinforcement.

### Step 1: Update reference paths

For each protocol section in SKILL.md, update the `<reference>` tag to point to the actual protocol file with section-level specificity where appropriate:

```xml
<reference path="references/protocols/phase-execution.md" load="required">
```

Verify each path resolves to an actual file.

### Step 2: Add inline mandatory reinforcement

Review each protocol section for violation-prone points that need inline `<mandatory>` reminders. Key reinforcement points from the design:

- Message-watcher relaunch after every event (Phase Execution, Review, Error Recovery sections)
- Selective reference reading reminder on every `<reference>` tag
- Protocol transition through SKILL.md reminder in preamble

### Step 3: Absorb orchestration-principles.md

Content from `orchestration-principles.md` that belongs in SKILL.md (high-level principles) should be integrated into the preamble or protocol `<context>` blocks as appropriate.

### Step 4: Fix known issues from Opus review

Address the critical and important issues found in the skeleton review:
- Literal XML tags in text that get consumed by parser (reword to avoid angle brackets)
- HTML comments inside XML tags that get silently dropped (reword)
- Any missing routing paths or incomplete protocol transitions

### Step 5: Commit

```bash
cd skills_staged/conductor
git add SKILL.md
git commit -m "refactor: refine SKILL.md with precise reference pointers and reinforcement"
```

**Verification:** Every `<reference>` path resolves. No literal XML tags inside XML blocks. All protocol sections have appropriate inline `<mandatory>` reinforcement.

---

## Phase 5: Example File Updates

**Goal:** Assess and update the 7 example files to align with the new protocol structure.

### Step 1: Assess each example

For each of the 7 example files, determine:
- Does this example demonstrate a single protocol's workflow? → Move to that protocol's scope or keep as standalone
- Does this example demonstrate a cross-protocol workflow? → Keep as standalone, update to use new protocol names
- Is this example obsolete? → Archive to `docs/archive/`

Current examples:
1. `conductor-initialization.md` → likely maps to Initialization Protocol
2. `launching-execution-sessions.md` → likely maps to Phase Execution Protocol
3. `monitoring-subagent-prompts.md` → likely maps to Phase Execution or Sentinel Monitoring
4. `error-recovery-workflow.md` → likely maps to Error Recovery Protocol
5. `review-approval-workflow.md` → likely maps to Review Protocol
6. `completion-coordination.md` → likely maps to Completion Protocol
7. `rag-processing-subagent-prompts.md` → likely maps to Review Protocol

### Step 2: Update retained examples

For examples that are retained:
- Update terminology (should already be done from Phase 1)
- Update references to old file structure → new protocol files
- Verify Tier 3 structure is intact
- Update any SQL or commands that changed

### Step 3: Archive obsolete examples

Move any obsolete examples to `docs/archive/`.

### Step 4: Commit

```bash
cd skills_staged/conductor
git add examples/ docs/archive/
git commit -m "refactor: update example files for protocol-dispatching architecture"
```

**Verification:** Each retained example is internally consistent with the new architecture. No references to deleted files or old structure.

---

## Phase 6: Cutover and Final Verification

**Goal:** Replace old reference files with new protocol files, run final verification, clean up.

### Step 1: Archive old reference files

```bash
mkdir -p skills_staged/conductor/docs/archive/references-v2-type-organized
mv skills_staged/conductor/references/*.md skills_staged/conductor/docs/archive/references-v2-type-organized/
```

### Step 2: Move protocol files to references/

```bash
mv skills_staged/conductor/references/protocols/*.md skills_staged/conductor/references/
rmdir skills_staged/conductor/references/protocols
```

### Step 3: Update SKILL.md reference paths

Update all `<reference path="references/protocols/...">` to `<reference path="references/...">`.

### Step 4: Final verification

Launch an Opus review agent to verify the complete skill:

1. **SKILL.md structural check:** Tier 3 compliance, sections index matches actual sections, all reference paths resolve
2. **Reference file structural check:** Each protocol file is Tier 3 compliant, has sections index, all text inside tags
3. **Protocol naming consistency:** Every protocol name in SKILL.md registry matches usage in reference files
4. **Boundary routing:** Every reference file's boundary transitions name protocols from the registry (exact match)
5. **Content preservation:** Cross-reference archived originals vs new protocol files — nothing dropped
6. **No old references:** No file references old file names, deleted files, or STATUS.md
7. **No old terminology:** Zero matches for Orchestrator, Task-Writer, Executor

### Step 5: Clean up temp files

```bash
rm -rf skills_staged/conductor/temp/proposals
```

### Step 6: Final commit

```bash
cd skills_staged/conductor
git add -A
git commit -m "feat: complete Conductor skill overhaul — protocol-dispatching architecture

Protocol-dispatching SKILL.md with prompt-style framing.
8 protocol reference files organized by workflow.
Content migrated from 15 type-organized files.
Autonomous operation, Arranger/Repetiteur integration,
sentinel monitoring, Musician lifecycle management.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

**Verification:** Full skill is internally consistent, all references resolve, all protocol boundaries route correctly, all content preserved.

---

## Execution Notes

**This plan is designed for teammate-based execution.** Phases 3a and 3b are the heaviest — they involve 8 teammates each working on a protocol file. Phases 1, 2, 4, 5 are smaller and can be done by a single session or delegated as appropriate.

**Phase dependencies are strict:**
- Phase 1 must complete before anything else (naming cleanup prevents confusion)
- Phase 2 must complete before Phase 3 (SKILL.md defines the protocol registry)
- Phase 3a must complete and be approved before Phase 3b (proposals before content)
- Phase 3b must complete before Phase 4 (reference files must exist for SKILL.md pointers)
- Phase 4 must complete before Phase 5 (SKILL.md must be finalized before examples reference it)
- Phase 5 must complete before Phase 6 (all content finalized before cutover)
