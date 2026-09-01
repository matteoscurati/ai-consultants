# Breadth v1 maintainer benchmark

This tree is a maintainer-only, preregistered benchmark harness. It is not part
of the shipped package (see `package.json`) and does not change consultation
defaults. The held-out prompts and rubrics are deliberately local-only in
`private/heldout-v1.json`; that path is ignored. P1.7 may publish that corpus
only after a binding run.

## Offline checks

```bash
bash benchmarks/breadth-v1/scripts/breadth.sh validate \
  benchmarks/breadth-v1/private/heldout-v1.json
bash benchmarks/breadth-v1/scripts/breadth.sh smoke
bash benchmarks/breadth-v1/scripts/breadth.sh preflight --json
bash benchmarks/breadth-v1/scripts/breadth.sh analyze fixtures/positive-run.jsonl
```

CI uses the committed `fixtures/ci-dataset.json` and `ci-manifest.json`:

```bash
bash benchmarks/breadth-v1/scripts/breadth.sh validate --ci
```

It contains no held-out material and is permanently refused by `run`. `smoke`
uses only the synthetic fixture and sentinel runner. The hidden `test-run`
entrypoint additionally traverses the real 750-call scheduler, but accepts only
the bundled sentinel, temporary state, and an explicit test-only environment
gate. It can never accept evidence or a live runner.

## Binding execution boundary

`preflight --evidence FILE --json` validates the private dataset,
preregistration, exact premium roster, schedule, provider-backed identity
evidence, per-transport pricing and the three caps. Missing, stale, unpriced or
over-cap evidence produces a non-actionable receipt with no confirmation token.
The token binds manifest, preregistration, dataset, evidence, schedule, caps and
expiry. `run` requires that same evidence file and the action-time token before
creating state.

`scripts/live-runner.sh` is the only accepted binding runner. It pins each
transport/model/effort, disables panel routing, cache, fallback features and
adapter retry, creates distinct primary and joint-judge prompts, and records
the raw adapter envelope locally alongside normalized findings, accounted cost,
and provider-backed identity provenance. It remains fail-closed
until a reviewed evidence file exists and `BREADTH_LIVE_RUNNER_REVIEWED=true`
is set at action time. No such evidence file is committed by this PR.

Run state is append-only per-attempt and per-completion JSON records in the
ignored run directory, protected by a lock and installed with atomic `mv`.
Each request has a deterministic `call_id` and idempotency key. Admission is
durable before transport. Completed IDs are skipped on resume; an attempted ID
without a terminal record blocks resume as uncertain. Every attempt, including
the one preregistered transient retry, is checked against integer-cent cost,
dispatch and elapsed-time caps. Any retry makes the binding run incomplete.

`analyze` derives the item-by-arm matrix and aggregate metrics solely from the
single structured judge record per item. `eligibility` separately requires the
exact expected 750 call IDs, 30 valid judges, provider-backed identities, no
retry/incomplete/unpriced record, the three caps, and a manual audit attestation
binding the frozen inputs, evidence, records-set hash and analysis hash.
