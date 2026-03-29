---
name: verify
description: Run bash syntax checks on all scripts, then preflight and doctor checks to verify the codebase is healthy.
---

Run the following verification steps in order. Stop and report on first failure.

## 1. Bash syntax check

Run `bash -n` on every `.sh` file in `scripts/` and `scripts/lib/`:

```bash
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f" || echo "FAIL: $f"; done
```

## 2. ShellCheck (if available)

Run ShellCheck on changed files (or all if none specified):

```bash
shellcheck -x scripts/*.sh scripts/lib/*.sh
```

Report warnings but don't fail on style-only issues (SC2034, SC2086 are common in this codebase).

## 3. Preflight check

```bash
./scripts/preflight_check.sh
```

## 4. Doctor

```bash
./scripts/doctor.sh
```

Report a summary table of pass/fail for each step.
