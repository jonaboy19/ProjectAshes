---
name: ashes-parallel-commits
description: How the orchestrating Rising Ashes session commits and pushes safely while several subagents edit the same working tree - when to hold, partial staging, snapshot commits, pushing to branch and main. Use whenever agents run in parallel on one checkout, or when the stop hook reports uncommitted changes.
---

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
