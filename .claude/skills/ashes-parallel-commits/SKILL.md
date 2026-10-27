---
name: ashes-parallel-commits
description: How the orchestrating Rising Ashes session commits and pushes safely while several subagents edit the same working tree - when to hold, partial staging, snapshot commits, pushing to branch and main. Use whenever agents run in parallel on one checkout, or when the stop hook reports uncommitted changes.
---

> **Mandatory for every task (owner rules, 2026-10-28):** (1) `ashes-best-tool-first` — use every fitting Godot built-in, installed addon, external tool (Blender, ffmpeg, Meshy, Mixamo, Poly Haven/ambientCG CC0) and cloud offload instead of hand-rolling; (2) `ashes-aaa-gate` — nothing is done or sent until it passes the AAA gate against `docs/plans/ref_aaa/`. The game is **PC-only** (min-spec: regular PC, possibly integrated GPU); ignore any mobile/phone wording below.

# Committing while agents share one tree

Subagents never run git. The orchestrator commits for them.

## When to commit
- As soon as an agent reports, commit the files only it created or changed, if they stand alone (new files plus their registration line).
- Once the **full suite passes on the whole tree**, commit the whole tree as one snapshot, including half-done work that still passes. Later deltas get their own commits. This beats waiting hours for the last agent.
- Hold only when the tree fails to parse or the suite is red. Tell the user why once; don't repeat the explanation on every stop-hook ping.

## How
- New files: `git add <paths>`. Never `git add -A` while an agent is mid-edit, unless you are deliberately committing a tested snapshot.
- Part of a shared file (the hub line only): `git show HEAD:f > /tmp/f`, add just your hunk, `git hash-object -w /tmp/f`, then `git update-index --cacheinfo 100644,<sha>,f`.
- Revert unrelated `.import` churn first: `git diff --name-only | grep '\.import$'`, then `git checkout --` those files.
- Then fetch, `git merge --no-edit origin/<branch>`, `git push origin HEAD:<branch>` and `git push origin HEAD:main` (the user allowed main).
- Merge blocked by untracked `.uid` or `.import` files: delete those files and merge again.
- Check for large files before pushing (nothing over 90 MB). The repo is public, so never commit keys; CI `guard` also checks.

## Commit message
Say what the player gets, list the systems, and note anything unverified. End with the Co-Authored-By and Claude-Session trailers.

## Shared-worktree rules (2026-10-28, learned the hard way)
Several local workers share ONE worktree (PA_wt_w3) and ONE git index.
- **Commit:** pathspec commits only, `git commit -m "..." -- <your paths>`. Never a bare `git commit` after `git add`: it sweeps up other workers' staged changes. For files several workers edit (player.gd, assets.gd), ask the file's owner to commit your hunk, or wait until their edits are committed.
- **Sync:** fetch `+refs/heads/aaa/finish:refs/remotes/origin/aaa/finish`. If you have local commits not on origin, `git rebase origin/aaa/finish`, or if others' uncommitted files block it, cherry-pick onto origin in a temp worktree (`git worktree add --detach ../PA_tmp origin/aaa/finish`), push from there and remove the worktree. Only with NO local commits use `git reset --keep origin/aaa/finish` (it silently drops unpushed commits). Push right after committing.
- **Never commit** an import-time rewrite of `project.godot`; restore it with `git checkout -- kingdom/project.godot`.
- **GPU:** wrap every Godot recording or perf run with the shared GPU lock (`tools/qa/gpu_lock.sh`, lock dir `PA_plans/locks/gpu.lock`); skip a run if free RAM is under 3 GB.
- **Merging cloud branches:** the coordinator merges in a temp worktree; conflicts in `docs/plans/AAA_PROGRESS.md` are resolved by keeping both sides.
