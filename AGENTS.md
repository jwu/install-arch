# AGENTS.md

## Project

Orchestrator for a bare Arch Linux machine. It is not an application and has no
build system: `install.sh` clones/updates the three config repos under `~/bin`
and runs their installers in order.

## Key structure

- `install.sh` — the whole entry point: a `step` runner, the repo sync, the
  pi CLI check and the calls into `configs` / `pi-config`.
- The repos it drives live outside this one: `jwu/configs`,
  `jwu/desktop-settings`, `jwu/pi-config`.

## Working rules

- Make **small, targeted changes**.
- Keep `install.sh` **idempotent** and safe to re-run.
- Keep every step **best-effort**: record the failure, continue, report at the
  end. Never let one failed step skip the ones after it — that is the bug this
  repo exists to fix.
- Do not let a step depend on the network during dry checks: a bare machine
  might be offline, and the run must still finish and summarize.
- Source comments stay short and in English; reasoning/gotchas go in the
  READMEs and in `configs/docs/`.

## Validation

```bash
bash -n install.sh
```

`shellcheck` is not installed on the reference machine; `bash -n` is the
smallest relevant check.

## Adding a step

Add a function that returns non-zero on failure, then register it with
`step "<description>" <function> [args...]` in the run section. Keep it after
the repos it needs are synced.
