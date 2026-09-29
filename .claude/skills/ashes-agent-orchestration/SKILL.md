---
name: ashes-agent-orchestration
description: How the local Rising Ashes session splits work across subagents cheaply and safely on a branch shared with a cloud session and Codex. Use when starting several parallel tasks.
---

# Orchestration

- **Plan and judge with Opus. Execute with Sonnet** (build and asset work) **or Haiku** (file moves, renames, simple docs, licence checks).
- Every agent prompt includes:
  - the repo path and branch;
  - "commit only your own paths";
  - "merge origin first; use a temporary `git worktree` if the local checkout is dirty or behind";
  - "never `git add -A`";
  - "never kill Godot or Blender globally";
  - the commit trailer;
  - "revert unrelated `.import` rewrites";
  - "render and READ screenshots";
  - a report of at most 250 words.
- Give each agent disjoint paths, and say which topics other agents own right now.
- **Never** use `load_threaded_request` or a WorkerThreadPool for meshes or materials. It crashes; see `ashes-performance`.
- Tools on this PC:
  - Godot 4.6.3 console exe in `C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\`
  - Blender 5.2
  - ffmpeg (installed with winget)
  - WinDbg `cdb` for crash dumps
- After an agent finishes:
  1. Check its screenshots yourself.
  2. Run `ashes-aaa-review`.
  3. Update `docs/STATUS_LOCAL.md`.
  4. Send the best PNGs to the owner.
