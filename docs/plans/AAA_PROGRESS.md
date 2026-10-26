# AAA finish - progress log (append-only)

Resume protocol (from `AAA_FINISH_PLAN.md` C0):
1. Read this file; the last row names the step/sub-step in progress.
2. `git -C "C:/Users/Jonna/Documents/PA_wt_w3" status --short | head; git log --oneline -5; df -h /c`; check AC power.
3. Dirty tree with your own half-step: finish it to its acceptance check or `git stash push -m "wip <step>"` and log the stash here. Never leave the branch broken (parse + boot).
4. Row format: `| time | step | status (started/done/blocked:<why>) | commit | evidence | next |`. Commit this log with each step.
5. Branch `aaa/finish` (from `claude/anim-aaa`). One commit per sub-step `S<n>.<m>: summary`. Push after each step; merge into `claude/focused-curie-m09hbd` only when acceptance passes.

Rules: `export MSYS_NO_PATHCONV=1`; PC only; disk < 8 GB free = stop; one Godot at a time; never `--headless` for screenshots; `player.gd`/`hero_face_driver.gd` are CRLF; never commit `.import`/`.uid` churn, `project.godot` rewrites from `--import`, or `work/`.
Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (Claude took over from Codex on 2026-10-26: Codex out of usage).

## Owner decisions needed
(none yet)

| time | step | status | commit | evidence | next |
|---|---|---|---|---|---|
| 2026-10-26 | S0 | started | - | Claude takes over from Codex; remote backup `origin/backup/anim-codex-wip-2026-10-26`=026719f8 exists; worktree has 1325 dirty paths (697 .import churn, 419 qa strips, rest source) | S0.a docs/QA |
