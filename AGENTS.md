# AI Consultants

Cross-vendor AI coverage panel for coding questions. It queries up to 10
consultants in parallel and returns the union of their distinct perspectives.

## Agent-host usage

Claude Code, Codex CLI, and Gemini hosts expose two commands:

```text
/ai-consultants:consult "Your coding question"
/ai-consultants:help
```

When an agent invokes the skill, follow `SKILL.md`'s execution contract:

- run `scripts/consult_all.sh`, never individual provider adapters;
- set `INVOKING_AGENT=claude|codex|gemini` for the actual host;
- write question text to a private mode-600 file and use `--query-file`;
- preserve `--preset` and `--strategy` before `--query-file`;
- pass referenced files as separately quoted `path@PRIMARY|CONTEXT` arguments;
- reject any run where the invoking host appears as a consultant artifact or
  synthesis provider.

## Direct Bash

```bash
./scripts/consult_all.sh "Your question"
./scripts/consult_all.sh --preset balanced "Question"
./scripts/consult_all.sh --strategy compare_only "Question"
```

## Current architecture

- 10 consultants: Gemini, Codex, Mistral, Kimi, Claude, Qwen3, GLM, Grok,
  DeepSeek, and MiniMax.
- Parallel fan-out with configurable personas.
- Coverage-union synthesis by default; majority and comparison strategies
  remain optional.
- Smart routing, cost tracking, semantic cache, quorum grading, health checks,
  and explicit response-quality/model-identity metadata.
- No voting/consensus, debate rounds, anonymous peer review, panic mode, or
  roster-audit workflow; those were removed in v3.0.

## Requirements

- At least two configured consultant CLIs or API transports.
- `bash`, `jq`, and `curl`; Python is used by context optimization when present.

See `SKILL.md`, `README.md`, and `docs/SETUP.md` for the maintained user
contract.
