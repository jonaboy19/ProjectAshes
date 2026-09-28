---
name: ashes-collab
description: How to work on Rising Ashes alongside the parallel cloud Claude session and the Codex session without conflicts. Use at the start of every session on this repo, before any commit or push, and whenever a merge fails.
---

# Working in parallel on ProjectAshes

Repo: `C:\Users\Jonna\Documents\ProjectAshes` (GitHub jonaboy19/ProjectAshes), branch **`claude/focused-curie-m09hbd`**, shared by:
- the **cloud Claude session**: game code, systems and placing assets in the world;
- the **Codex session** (branch `gpt/ai3d-assets`, merged in regularly): **all animation behaviour** (locomotion speed, foot slide, clip choice, blend times). Don't touch animation code;
- the **local PC session** (this one, with GPU, Blender, Godot and Meshy): assets, optimization and **frame rate**, QA tools, store kit, release.

## Start of every session
1. `git fetch && git merge --no-edit origin/claude/focused-curie-m09hbd`.
2. Read `docs/LOCAL_SESSION_HANDOFF.md` (who owns what, what's ready, requests).
3. Read the skills: `ashes-asset-pipeline`, `ashes-open-source-sourcing`, `ashes-performance`.

## Commit and push
- Commit **only your own paths** (`git add <paths>`, never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Before each commit: fetch and merge, then push right away. Small, focused commits.
- If a push is rejected ("cannot lock ref"): fetch, merge, push again.
- **Merge aborted by untracked files:** list them (`git merge ... | grep "^\t"`). If they're `.import` or extracted `.jpg` files, delete just those (they're regenerated) and merge again. Stash stale local edits to docs with `git stash push -- <paths>`.
- **Godot imports rewrite hundreds of unrelated `.import` files.** Before committing: `git diff --name-only | grep '\.import$'` and `git checkout --` the ones that aren't yours.
- Raw Meshy GLBs live in the gdignored `kingdom/assets/incoming/ai3d/meshy/_raw/`. Never commit files over 90 MB.

## Ownership changes
When you start work that touches another side's files, add a dated line to `docs/LOCAL_SESSION_HANDOFF.md` ("local is editing X now") and push it first. Cancel the line if you stop. The user's word decides ownership (e.g. "Codex is doing animation").

## Tools on this PC
- Godot 4.6: `/c/Users/Jonna/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe`. Launchers: `Open Godot Editor.bat` and `Play Game.bat` in the repo root.
- Blender 5.2: `/c/Program Files/Blender Foundation/Blender 5.2/blender.exe`. No Python on PATH: use Blender's Python, or PowerShell for images.
- Never kill Godot or Blender globally; other agents run jobs. Kill only your own PID.
- Screen control can't drive Godot (portable exe), so test through the playtest bot and bench scripts, and **look at their screenshots**.

## Always show the user
The user wants to **see** results: send the PNGs (SendUserFile), rebuild the asset gallery (`bash tools/gallery/build_gallery.sh`), and test visually, not just by numbers.
