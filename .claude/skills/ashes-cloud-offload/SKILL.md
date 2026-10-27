---
name: ashes-cloud-offload
description: Offload Rising Ashes work to cloud Claude sessions (RemoteTrigger one-shot routines) so the 16 GB laptop only does GPU/visual work - what qualifies, the routine template, PR flow into aaa/finish, review-and-merge routines and how to check results. Use whenever a task is code + headless tests, review, merging, data or docs.
---

# Cloud offload

## What goes to the cloud
Anything that needs no GPU/window: simulation and systems code with gdUnit tests, data, generators, refactors, PR review + merge, docs, headless bot stages. Local laptop keeps: animation sheets, visual captures, perf on real hardware, Blender renders.

## Routine template (RemoteTrigger create)
- environment `env_011PGxABSirdeU5dXGSuDGYc`, model `claude-sonnet-5-5`, source repo `https://github.com/jonaboy19/ProjectAshes`, allowed tools Bash/Read/Write/Edit/Glob/Grep (+WebFetch/WebSearch if research), `run_once_at` = now + 3 min (UTC).
- Prompt must be self-contained: shallow single-branch clone of **aaa/finish** (the only integration branch), branch name, the work package (point at its section in `docs/plans/MASTER_BACKLOG.md` when it exists), files not to touch (player.gd CRLF, animation files, terrain/town files owned by local workers), install Godot 4.6.3 headless Linux, gdUnit `--ignoreHeadlessMode`, commit trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, PR into aaa/finish, summary at the end, list of what needs local GPU verification.
- One routine per independent work package; avoid two routines editing the same functions (say so in the prompt if adjacent).

## After it runs
`RemoteTrigger list_runs` / `get_run_log`; open PRs with `gh pr list`. Merge via a review routine (review diff, rebase on latest aaa/finish, run tests, fix, `gh pr merge --merge`). GitHub Actions currently fail in ~3 s (infrastructure) — don't rely on them. Usage-limit failures: re-run with `RemoteTrigger run`.
