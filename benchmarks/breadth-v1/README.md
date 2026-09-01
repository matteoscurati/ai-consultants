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

`smoke` uses only the synthetic fixture and the sentinel runner. It creates a
temporary directory, makes zero provider calls, and leaves no live-run state.

## Binding execution boundary

`run` first validates the private dataset and frozen preregistration. It prints
a receipt containing all identities, transports, models, efforts, hashes,
planned dispatches, pricing status, caps, and expiry. It creates no run state
until an action-time confirmation token derived from that receipt is supplied.
There is intentionally no enabled provider runner in P1.6: a maintainer must
inject an executable runner using `BREADTH_RUNNER=/absolute/path/runner` after
reviewing the receipt. The runner protocol is JSON-in/JSON-out and is tested
only with `scripts/sentinel-runner.sh`; no transport probing or health call is
performed by this harness.

Run state is append-only per-attempt and per-completion JSON records in the
ignored run directory, protected by a lock and installed with atomic `mv`.
Each request has a deterministic `call_id` and idempotency key. Completed call
IDs are never scheduled again. An admitted transient retry
is recorded but makes the binding run incomplete because 750 calls already
consume the full dispatch cap.
