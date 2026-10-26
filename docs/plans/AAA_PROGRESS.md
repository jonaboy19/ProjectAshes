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
| 2026-10-26 | S0.a-g | done | 52df5ff3..711378d3 | 7 logical commits; `--import` clean (exit 0); run_tests.sh 10: 2277 cases, 1 failure (test_skills STOCK_CLIPS missing MA_Punch_Hook_R_A from S0.f) | S0.h fix, push, S1 |
| 2026-10-26 | S1 | done | merge of origin/claude/focused-curie-m09hbd into aaa/finish (docs-only delta, no conflicts) | tests green after S0.h (2277 cases); traversal_standalone.gd ran windowed: probes `vault`/`mantle_low` fire, sheet docs/qa/golden/s1_traversal.png read: player is framed at the far right edge of the tiles (harness camera is poor, pre-existing), mid-vault pose visible in tile 2, landing in tile 3; not a sufficient motion review, real traversal review moves to S3.2 with the wall_rig/Movie Maker runs | merge to main, S2 |

| 2026-10-26 | S1 | pushed | 7c14a5ad | aaa/finish fast-forwarded into claude/focused-curie-m09hbd | S2.1-S2.5 |
| 2026-10-26 | S2.1-S2.5 | done | see git log S2.* | golden_set.json: 757 clips (gold/probation/banned) combat 37/173/91 ; creature 0/114/215 ; death 0/2/7 ; interaction 14/9/3 ; locomotion 17/9/28 ; traversal 2/10/26; 226 slots; 70 gold = metrics-gold AND side-view strip review pass (3 held: Loco_Sprint_Stop_Skid, Mantle_Low, Shield_Bash); core locomotion (Walk 0.13 m/s slide mean, Jog_Fwd, Sprint) is metrics-BANNED because the raw clips slide: runtime foot lock/stride warp (S3.1) must fix, enforcement stays OFF (`enforce:false`) until gold replacements exist; test_golden_set 6/6, test_skills ok, headless boot ok; golden_gate is anim_qa.gd library mode + golden_gate.py (not .gd) | S3 player |

