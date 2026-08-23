# AI Consultation Report

## Metadata

| Field | Value |
|-------|-------|
| **Date** | {{TIMESTAMP}} |
| **Category** | {{CATEGORY}} |
| **Quorum** | {{SUCCESSFUL_CONSULTANTS}} / {{ATTEMPTED_CONSULTANTS}} ({{QUORUM_OUTCOME}}) |
| **Active Consultants** | {{ACTIVE_CONSULTANTS}} |

---

## Question

> {{QUERY}}

---

## Coverage Synthesis

{{#IF_SYNTHESIS}}

**Strategy:** {{SYNTHESIS_STRATEGY}}

**Summary:** {{SYNTHESIS_SUMMARY}}

### Distinct Considerations

{{#EACH COVERAGE_POINTS}}
- {{POINT}} — raised by {{CONSULTANTS}}
{{/EACH}}

{{/IF_SYNTHESIS}}

{{#IF_NO_SYNTHESIS}}
*Automatic synthesis was unavailable. The coverage below is assembled from the
successful individual responses.*
{{/IF_NO_SYNTHESIS}}

---

## Consultant Summary

| Consultant | Model | Quality | Confidence | Approach | Key Insight |
|------------|-------|---------|------------|----------|-------------|
{{#EACH CONSULTANT_SUMMARIES}}
| {{CONSULTANT}} | {{MODEL}} | {{RESPONSE_QUALITY}} | {{CONFIDENCE}}/10 | {{APPROACH}} | {{SUMMARY}} |
{{/EACH}}

---

## Risks & Caveats

{{#EACH RISKS}}
- **{{DESCRIPTION}}** — {{SEVERITY}}; raised by {{IDENTIFIED_BY}}
{{/EACH}}

---

## Suggested Next Steps

{{#EACH ACTION_ITEMS}}
- **{{ACTION}}** — {{RATIONALE}}
{{/EACH}}

---

## Diagnosed Failures

{{#EACH DIAGNOSED_FAILURES}}
- **{{CONSULTANT}}:** {{REASON}}
{{/EACH}}

---

## Output Files

| File | Description |
|------|-------------|
| `{{OUTPUT_DIR}}/context.md` | Built consultation context |
| `{{OUTPUT_DIR}}/<consultant>.json` | Individual consultant envelopes |
| `{{OUTPUT_DIR}}/synthesis.json` | Coverage-union synthesis, when available |
| `{{OUTPUT_DIR}}/optimization_metrics.json` | Quorum and optimization metadata |
| `{{OUTPUT_DIR}}/report.md` | Rendered report |
