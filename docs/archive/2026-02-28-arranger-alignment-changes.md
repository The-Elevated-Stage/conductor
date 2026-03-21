# Conductor — Changes Needed for Arranger Alignment

**Date:** 2026-02-28
**Source:** `stagecraft/docs/working/2026-02-28-arranger-design-action-plan.md`
**Purpose:** Document all changes needed to the Conductor skill so that a separate session can execute them.

---

## Context

The Arranger-Conductor alignment review (2026-02-28) found **strong alignment with no critical issues**. The core contract — plan-index sentinel markers, selective line-range reading, dual-audience sections, task decomposition boundary — is well-specified on both sides. The changes below are refinements that improve the Conductor's ability to leverage the Arranger's richer Tier 2 format.

Key alignment points that are already working and should NOT be changed:
- Plan-index verification as a hard gate during initialization
- Phase-level task decomposition (Arranger provides goals, Conductor decomposes)
- Selective line-range reading for phase sections
- Repetiteur escalation chain (5 corrections → Repetiteur, 3 consultations → user)
- Decision journal directory lifecycle and cleanup

---

## Changes Required

### 1. Authority Tag Interpretation — Add to Phase Execution Reference

**Current state:** The Conductor treats all items in conductor-review sections equally — all must pass before proceeding. Phase section content is consumed for decomposition context without authority tag awareness.

**Required change:** Add a subsection to `skill/references/phase-execution.md` documenting authority tag interpretation:

**In phase sections:**
- `<mandatory>` items have plan-level authority and are NOT modifiable by the Conductor, even within intra-phase authority. This rule already exists in the Conductor's mandatory section but the mechanics of detecting and respecting these tags are not described.
- `<guidance>` items are recommendations that the Conductor can adapt based on runtime conditions.
- `<core>` is primary implementation content.

**In conductor-review sections:**
- `<mandatory>` items are hard verification gates — must pass before proceeding to the next phase.
- `<guidance>` items are recommendations, not hard gates. The Conductor should consider them but can proceed if they aren't fully satisfied.

**User override flags:** Conductor checkpoint sections may contain override flags in the format: `USER OVERRIDE: [setting] set to X despite research indicating Y -- user has workaround, see journal entry [ref]`. These should be noted and propagated to the Copyist's Overrides & Learnings section in the launch prompt, but should not be blocked on.

### 2. Tier 2 Hybrid Document Awareness

**Current state:** The Conductor's reference files do not mention Tier 2, `<sections>` indices, or `<section>` tags in the context of reading the implementation plan.

**Required change:** Add a brief note to `skill/references/initialization.md` or `skill/references/phase-execution.md` acknowledging:

- The implementation plan is a Tier 2 hybrid document with YAML frontmatter, `<sections>` index, and `<section id="...">` tags
- Sentinel markers + plan-index remain the primary navigation system
- `<section>` tags provide fallback navigation if plan-index line ranges become stale (e.g., after a partial edit that shifts line numbers)
- YAML frontmatter contains `feature`, `design-doc`, `tier`, and other metadata fields

### 3. Plan-Index Consumption — Overview and Phase-Summary Entries

**Current state:** `references/initialization.md` `plan-bootstrap-reading` section says the Conductor reads Overview and Phase Summary "via plan-index line range." The plan-index format historically only included `phase:N` and `conductor-review:N` entries.

**Required change:** Once the Arranger's plan-index is updated to include `overview` and `phase-summary` entries, the Conductor's bootstrap reading naturally works. Update the Conductor's documentation to explicitly reference these new plan-index entry types:

```
<!-- overview lines:NN-NN -->
<!-- phase-summary lines:NN-NN -->
```

If implementing before the Arranger is built, add a note that these entries are expected in the plan-index and fall back to sentinel marker scanning (`<!-- overview -->` / `<!-- phase-summary -->`) if the entries are absent.

### 4. Plan Path Convention

**Current state:** There's an inconsistency within the Conductor's own examples:
- Initialization example uses `docs/plans/2026-02-04-docs-reorganization.md` (note: `docs/plans/`, not `docs/plans/designs/`)
- MEMORY.md tracking uses `docs/plans/designs/{feature}-plan.md`

**Required change:** Standardize all references and examples to `docs/plans/designs/{feature}-plan.md`. This matches the Arranger's output path convention and the decisions directory convention.

### 5. YAML Frontmatter Note

**Current state:** The Conductor does not explicitly parse YAML frontmatter from the plan.

**Required change:** Add a note to initialization documentation that the plan includes YAML frontmatter with the following fields:

```yaml
title: "[Feature] Implementation Plan"
date: YYYY-MM-DD
type: implementation-plan
tier: 2
feature: "{feature-name}"
design-doc: "docs/plans/designs/{design-doc-name}.md"
```

The `feature` field in frontmatter matches the feature name used for the decisions directory and branch naming. The Conductor currently derives these from the Overview section or MEMORY.md — YAML frontmatter provides a machine-parseable source.

### 6. Danger File Annotation Format

**Current state:** The Conductor's danger-file-assessment section says to "check for inline annotations in the phase section" but the annotation format is not specified.

**Required change:** Document the convention once the Arranger defines it:

```
<!-- danger-file: path/to/file.dart shared-with="phase:3" -->
```

The Conductor treats these as supplementary — self-discovery remains the primary method for danger file identification. Arranger annotations provide a starting point.

---

## Validation

After changes are made, verify:
- [ ] Authority tag interpretation is documented in phase-execution reference with clear mechanics
- [ ] `<mandatory>` items in phase sections are explicitly noted as non-modifiable by the Conductor
- [ ] `<guidance>` items in conductor-review sections are explicitly noted as non-blocking
- [ ] Tier 2 document structure is acknowledged in initialization or phase-execution reference
- [ ] Plan-index documentation includes `overview` and `phase-summary` entry types
- [ ] All plan path references are consistent (`docs/plans/designs/{feature}-plan.md`)
- [ ] YAML frontmatter fields are documented
- [ ] Danger file annotation format is documented
