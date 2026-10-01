---
name: ashes-handoff
description: Decide which Rising Ashes session should do a task (cloud Claude, local PC Claude, Codex, or free CI) and write the handoff so the other side can start without questions. Use when a task needs a GPU, lots of RAM, Blender with UI, a phone, Meshy, or animation work, or when the cloud container keeps OOM-killing renders.
---

# Who does what

| Work | Best owner | Why |
|---|---|---|
| Game systems, realm modules, data, tests, hooks, integration | cloud Claude | owns the code and orchestrates agents |
| Full test suite, secret and file-size checks | GitHub Actions (`ashes-ci`) | free, no tokens, no container memory |
| Full-game screenshots, visual QA sweeps, videos and trailers, fps on a real GPU, phone testing | **local Claude** | GPU and RAM; the cloud container OOMs with more than 1 render |
| Assets (Blender, Meshy), art fixes, LOD and impostors, the asset audit | local Claude | Blender UI, Meshy key, GPU bakes |
| All animation behaviour (clips, speeds, blends, foot slide) | Codex (`gpt/ai3d-assets`) | owns animation code |

## Writing a handoff
Add a dated section to `docs/LOCAL_SESSION_HANDOFF.md` headed "## YYYY-MM-DD (cloud -> local): <topic>". Each task needs:
1. **What and why**, with the user's words where they matter.
2. **Exact files and commands** (shot names, QA scripts, view lists such as `tools_qa/region1/world_views.json`).
3. **Done means:** a contact sheet path, numbers (draw calls at or below 150 on LOW), and tests.
4. **Ownership:** which files they may edit; anything else goes back as a request.

Push the handoff right away so the other side sees it on its next `git fetch`. When the other side reports "DONE" in that doc, integrate it and delete finished request lines.
