---
description: Audit the consultant roster for uncorrelated value — which consultants contribute a distinct approach vs echo the panel (candidates to drop or down-weight). Use when deciding roster composition or after noticing redundant consultations.
argument-hint: [--recent N] [--threshold PCT] [dir ...]
allowed-tools: Bash
---

# AI Consultants - Roster Audit

Measure each consultant's *uncorrelated value* across past consultations: a
consultant whose approach rarely differs from the rest (low keyword overlap) is
redundant; one that is often distinct earns its seat on diversity. This is the
"does it add signal the others miss?" bar, applied to the panel.

**Arguments:** $ARGUMENTS

## Instructions

1. Run the audit (pass `$ARGUMENTS` through; with no args it audits the most
   recent consultations under the output base):
   ```bash
   cd "${AI_CONSULTANTS_DIR:-$HOME/.claude/skills/ai-consultants}" && ./scripts/roster_audit.sh $ARGUMENTS
   ```
   - No args → the 20 most recent consultation dirs.
   - `--recent N` → the N most recent; `--threshold PCT` → correlation cutoff (default 20%).
   - Or pass explicit consultation output dirs; add `--json` for machine-readable output.

2. **Present the table** as-is (consultant · participated · distinct · distinct% ·
   verdict), then interpret each verdict:
   - **unique-value** — pulls its weight on diversity; keep.
   - **some-value** — contributes occasionally.
   - **redundant?** — correlated with the panel; candidate to drop or down-weight
     in `references/affinity.json` (lower its category affinities, or its
     capability axes when capability routing is enabled).
   - **insufficient-data** — too few samples; audit more consultations.

3. If the audit prints "nothing to audit" (exit 1), tell the user no consultations
   with ≥2 responders were found and suggest running some consultations first —
   each `consult_all.sh` run writes an output directory the audit can read.
