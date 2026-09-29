---
name: ashes-aaa-review
description: Self-review checklist to run after finishing ANY Rising Ashes task (asset, VFX, animation, UI, system). Asks "is this really done, and what would make it feel premium/AAA?" and turns the answers into next tasks. Use at every task completion and before reporting to the owner.
---

# "Is it finished?" loop

The owner wants the game pushed toward a premium, AAA feel on mobile. Never report "done" without running this loop.

## 1. Is it actually done?
- **Runs in the real game**, not only in a gallery. If it isn't integrated yet, there is a drop-in note for the owning session (cloud = game code/levels, Codex = animation behaviour).
- **I looked at it.** A screenshot or frame strip rendered on GPU (never use `--headless` for renders), read by me and compared with `docs/art/reference/00_MAIN_kingsreach_gate_market.webp`. See `ashes-art-style` and `ashes-visual-qa`.
- **Performance** is measured (fps/ms) and fits the budget in `ashes-performance`: 60 fps on mid-range Android, with a LOW-tier fallback.
- **Stability:** full boot → gameplay with zero errors in the log, and the QA boot test still passes.
- **Licence** is verified for commercial use and recorded in `CREDITS.md`.
- **Committed and pushed**, touching only my own paths. `docs/LOCAL_SESSION_HANDOFF.md` and `docs/STATUS_LOCAL.md` are updated.

## 2. What would make it feel AAA?
Ask these about every result:
- **Readability:** does it read instantly at phone size (silhouette, colour, contrast)?
- **Juice and feedback:** anticipation → action → impact → follow-through; hitstop, camera shake, a sound hook, particles, rumble.
- **Motion quality:** no foot sliding, blends under 0.2 s, correct root motion, secondary motion (cloth, hair, spring bones).
- **Consistency:** one warm storybook style and no off-style asset.
- **Polished edges:** transitions, loading, empty states, error states, localisation, accessibility.
- **Scale:** does it hold up with 30+ NPCs, at night, in rain, and on the LOW tier?

## 3. Turn the answers into work
1. Write each gap as a concrete next task in the Backlog of `docs/STATUS_LOCAL.md`.
2. Pick the task with the best value for its effort and keep going.
3. Hand cheap or mechanical tasks to Haiku/Sonnet subagents; keep planning and judging on Opus (see `ashes-agent-orchestration`).
