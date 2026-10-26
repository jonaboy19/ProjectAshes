# Rising Ashes — big handoff to Codex (2026-10-26)

From the local Claude session. The owner wants Codex to carry most of the work from here to save Claude usage. Claude keeps only what Codex can't do: **Meshy AI** (character/animation generation, credits) and anything else needing Claude-only tools. Everything below is current as of 2026-10-26.

Repo: `github.com/jonaboy19/ProjectAshes`. Main working branch: **`claude/focused-curie-m09hbd`**. Godot 4.6.3 (`C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe`). Owner GPU: RTX 4070 Laptop 8 GB, 15 GB RAM.

---

## 1. Owner direction (in force)
- **PC game only** (since 2026-10-20). Don't spend effort on mobile; leave mobile code paths as they are.
- **Core loop:** NPCs, recruiting, founding your own settlement → village → lordship. "I want the game ready: playable, all mechanics, animations, things to do."
- **Animations must be perfect.** Reuse existing animations first (our libraries, Codex's, Antigravity's packs); generate only for real gaps.
- **Fewer NPCs, AAA-style** (few fully simulated near the player, cheap crowds beyond) — research: `docs/plans/NPC_DENSITY_RESEARCH.md`.
- **World:** 12 288 m Valencious Region 1 on Terrain3D (32 km was discussed; owner said "leave it 12 for now").
- **Style G storybook look** (`docs/art/reference/00_MAIN_kingsreach_gate_market.webp`): lush green ground, warm key light, cool blue-violet shadows (never grey/black).
- **60 fps** at PC_HIGH 1440p is the goal; no freezes.
- **No Blender yet** for world work (owner); Blender was fine for character/asset cleanup earlier.
- **Never spend Meshy credits** without the owner's OK (Claude handles Meshy).

## 2. Plans to read (all in the repo under `docs/plans/` on main, local copies in `C:\Users\Jonna\Documents\PA_plans\`)
| File | What |
|---|---|
| `READY_V1.md` | Ready-v1 scope (M/S/L), gap list, cloud tasks C1–C16, lanes, release gate (headless bot). **The master plan.** |
| `NPC_DENSITY_RESEARCH.md` | AAA crowd research + recommended PC numbers (already applied to PC_TIERS). |
| `ANIM_AAA_BRIEF.md` | AAA mocap wiring + wall-contact/traversal realism (local copy; 108 clips → ~45 worth wiring; wall brace, slope slide, balance, edge stop). |
| `ANTIGRAVITY_REVIEW.md` | What to keep/drop from Antigravity's unmerged work. |
| local only: `PERF60_BRIEF.md` | Plan to reach 60 fps in the Kingsreach gate market (ResidentIndex, sprite pass rewrite, critter director, NpcTicker, VillagerPool). |
| local only: `SURVEY_2026-10-26.md` | Survey of everything since 10-22 (branches, PRs, uncommitted work, docs). |
| `docs/world/plans/WORLD_BRIEF.md`, `PC1_BRIEF.md` (branch `claude/world-t3d`) | World W0–W5 and PC renderer plans. |

Copy the local-only files into `docs/plans/` when you start (they're in `C:\Users\Jonna\Documents\PA_plans\`).

## 3. State of the work

### Merged on `claude/focused-curie-m09hbd`
- **World (W0–W5):** world bible `docs/world/VALENCIOUS_WORLD.md` (343 places), `valencious_places.json`, 12 sub-regions; macro heightmap generator `kingdom/tools/world/gen_valencious.py` → `kingdom/data/world/macro/*`; `WorldMacro` adapter + `world_gen.gd` hook; Terrain3D bridge with 11 ground slots, biome shader override (`shaders/terrain3d_ground.gdshader`, `terrain3d_look.gd`), biome dressing (`world_biomes.gd`, scatter by biome), rivers/roads/pads (road grade 47 %→7 % over 12 %), landmarks + stamps (Rift trench, Ashen Scar craters, mine benches, Grimfen notch, 21 POI kits, forest groves), camera-in-SubViewport fix for Terrain3D, height-thinned blue-violet fog. Docs: `docs/world/TERRAIN_PIPELINE.md`, `QA_W5.md` (98 captures with verdicts), `W1_W2_RESULTS.md`, `W3_RESULTS.md`, `W4_LANDMARKS.md`, `HANDOFF_TO_CODEX.md`.
  - **Defaults are still OFF**: `--terrain_backend=terrain3d --world_macro=valencious` to see it. Owner hasn't approved flipping them.
  - Open: hard-edged mid-field ground patches (Terrain3D 2-layer control map → needs shader multi-slot blend), flat planes near the Rift/Greywood/past the rim, dawn/dusk pinning ignored near towns, Heartvale still slightly brown. Terrain3D 1.0.2 crashes with FSR2 → PC uses FSR1+TAA when terrain3d is on (wait for Terrain3D 1.1 stable, then switch back).
- **Perf / freezes** (`docs/qa/perf/HITCH_RESULTS.md`): settings file read 3×/physics tick (fixed, cached), 1 Hz story script error (fixed), per-material shader compiles (shared), physics catch-up spiral (PC cap 3), sliced sprite pass, far villagers every other tick, NPC density PC rows (npc_full 8/10/14/18 etc.). Gate market 8.5 → ~24 fps, 0 freezes > 100 ms. Still main-thread bound (~41–45 ms: scripts ~31 ms). `--perf-legacy`, `--hitchlog`, `--qset=key=val`, `town_route.gd` flags, `run_hitch.sh`, `analyze.py`.
  - **Decision pending (owner):** physics 30 Hz on PC_HIGH gave ~19→25 fps but changes combat feel — not applied.
- **PC:** `PC_TIERS` + `Quality.profile` ("pc"/"mobile") + capability keys; Windows export preset; FSR/TAA modes; mouse look + capture, gamepad, PC hint strip, touch controls hidden (`docs/controls.md`); PC texture compression (`texture_vram.py --pc`, `.import` rewrite commit).
- **Antigravity parts:** manor + trader interiors wired; AAA mocap packs staged (`kingdom/assets/incoming/animations/aaa/`, `SOURCES.md`), not yet wired.
- **Earlier:** animation takeover (P9/P5/P2b/creature tables/casting v2), villager LifeAmbience + CrowdAnimLOD + VAT residents, T-pose fix, faces v1 (ink face card), audit-2 lighting, name-plate de-overlap.

### Branches NOT merged (review/merge these)
| Branch | What | Notes |
|---|---|---|
| `claude/anim-aaa` (pushed 10-26) | 3 commits: AAA clip wiring (`aaa_clips.gd` + manifest), wall contact (`wall_contact.gd`), ground realism, hand IK | 0 behind main → merges cleanly. Newest animation source. |
| `backup/anim-codex-wip-2026-10-26` | **Safety snapshot** of the Codex session's ~500 uncommitted files in `C:\Users\Jonna\Documents\PA_wt_w3` on top of `claude/anim-aaa` (excludes the 451 MB `work/` scratch dir except `work/CLAUDE_HANDOFF_2026-10-25.md`) | Unreviewed. The working tree is untouched — commit it properly in logical pieces from `PA_wt_w3`. |
| `claude/perf60` | step 1 of PERF60 (ResidentIndex) | Codex measured it 0.78× (slower) and removed it in its copy — re-measure on AC or drop. |
| `claude/ag-merge` | staged Antigravity parts | superseded (merged via `claude/pc-tex-ag`); delete. |
| `gpt/character-feel-finish`, `gpt/living-world-integration` | old Codex | pushed 10-22; check if anything left to merge. |
| `antigravity/*`, `antigravity/uncommitted-snapshot-2026-10-22`, `antigravity/stash-valencious-world-renders` | Antigravity backups | see `ANTIGRAVITY_REVIEW.md`; mostly drop. |
| `claude/npc-tier-a` (in progress, Claude) | 6 Meshy key NPCs — see §5 | Claude pushes it; review before merge. |

### Open PRs from the cloud agents (Ready v1) — review, rebase, merge
| PR | Task | Notes from its report |
|---|---|---|
| #14 `claude/v1-harness` | C1 headless release harness `kingdom/tools_qa/v1/run_v1.sh` + headless-safe bot | release gate |
| #8 `claude/v1-settlement-unify` | C2 one settlement model (build grid = founding = settlement row) | C3/C4/C5 depend on it |
| #13 `claude/v1-companions` | C6 companions fight, Down/revive, the Call | lists missing animation clips → feed into the animation pass |
| #9 `claude/v1-companion-content` | C7 Brannoc Tallow (spy), Sister Oriel Vane (healer), Hesk Ironbrow (builder/siege) — bios, dialogue, 3-step quests | follow-ups: nothing sets `hero.male/female`; clue props `duskbriar/ash/*` missing; `mab_larkin`, `lucan` not spawned; role flags not read by recruitment yet |
| #12 `claude/v1-hunting` | C10 skinning, yields, recipes, hunter job | also edits `critter.gd` (conflicts with Codex WIP) |
| #11 `claude/v1-pc-controls` | C11 rebinding + glyphs | |
| #10 `claude/v1-balance` | C13 duel sim, danger tiers | |
| #7 `claude/v1-doors` | C16 interior doors win over stations | |
| #3 `gpt/feel-audit-followup` | older Codex: block facing, wolf turns, ragdoll recovery | |
Each was ~28 commits behind main when surveyed. **Not started:** C3 found-a-camp flow, C4 settlement growth + ledger, C5 lordship milestone, C8 taming v1, C9 raids, C12 Acts 2–5 fixes, C14 whole-state save soak — specs in `READY_V1.md`.

### Uncommitted local work (on the owner's laptop)
- `C:\Users\Jonna\Documents\PA_wt_w3` (branch `claude/anim-aaa`): the Codex animation session since 10-24 — ~36 source/test/tool files + `work/` (451 MB). Notes: `work/CLAUDE_HANDOFF_2026-10-25.md`, `docs/anim/aaa_wiring/AUDIT_2026-10-24.md`, `docs/qa/PC_QUALITY_STATUS_2026-10-26.md`. Results: 108 AAA clips reviewed → 19 add / 6 compare / 83 skip; traversal GLB rebuilt (19 clips; shimmy/climb/mantle contact fixed); sheep walk wired (`critter.gd`); creature speed tables fixed; snow ambience; work-loop variation; **library audit of game-used clips: 297 PASS / 94 WARN / 190 FAIL**. Open: vault leg penetration ≤ 6.7 cm, sheep Run, pig Walk/Run, `Stagger_Back` root motion, traversal GLB needs clean reimport.
- `C:\Users\Jonna\Documents\PA_wt_audit` (branch `claude/perf60`): perf work tree (import cache present).
- `C:\Users\Jonna\Documents\PA_wt_mcp` (branch `claude/mcp-editor`): Godot editor + dcc-mcp copy (local addon install, stash `mcp-local`). Start: `powershell -ExecutionPolicy Bypass -File C:\Users\Jonna\Tools\dcc-mcp\start_godot_mcp.ps1` (http://127.0.0.1:8765/mcp; README `C:\Users\Jonna\Tools\dcc-mcp\README_CLAUDE.md`; world is built at runtime so play a capture scene inside the editor).
- `C:\Users\Jonna\Documents\ProjectAshes` main checkout is on stale `antigravity/aaa-mocap-animations` (~750 behind) with ~140 uncommitted Antigravity files (backed up to `antigravity/uncommitted-snapshot-2026-10-22`).

## 4. Recommended order for Codex
1. **Animation (owner priority: perfect):** commit `PA_wt_w3` in logical pieces on a branch from `claude/anim-aaa`, clean `--import`, focused tests, merge to main. Then the 190 FAIL rows in this order: (a) swap to an existing clip that passes (UAL, life, combat, traversal, AAA "add" set), (b) fix speed/foot-sync tables, (c) only then re-author — sheep Run, pig Walk/Run, horse, fox, dog are the known re-author list. If a clip truly doesn't exist anywhere, **ask Claude to generate it with Meshy** (preset library ~600 motions at 3 credits, or text-to-motion 3/10 credits; retarget to the UAL rig like hero v2). Player pass: `Stagger_Back`, `Block_Hit`, wall contact, running vault (see `ANIM_AAA_BRIEF.md` acceptance numbers: foot slide planted < 0.05 m/s mean, < 0.15 max; no pops in `motion.png`; blends 0.15–0.25 s; hit frame ±1 of marker). Verify every change frame by frame with Movie Maker + `tools/qa/video_to_sheets.sh` (skill `ashes-video-review`).
2. **Merge the cloud PRs** (#14 first, then #8, #13, #9, #12 — resolve `critter.gd` with the anim work —, #11, #10, #7), rebasing on main; run `run_v1.sh` headless after each.
3. **Remaining Ready-v1 tasks** C3, C4, C5, C8, C9, C12, C14 (specs in `READY_V1.md`). Missing clips from C6/C8/C9 (revive kneel, Down pose, horn, calm lean-in, tamed wolf follow/guard) → reuse existing first, else Meshy via Claude.
4. **Perf to 60 fps:** `PERF60_BRIEF.md` steps 2–7 (sprite pass rewrite, BodyRegistry, critter director, NpcTicker, VillagerPool); re-measure step 1 on AC power. Decide physics 30 Hz with the owner.
5. **World polish:** shader multi-slot blend for the hard-edged ground patches; remove flat planes; time-of-day pinning near towns; flip terrain defaults only after the owner approves.
6. **Faces:** faces v1 is an ink card (5–6/10). Note: MPFB (MakeHuman for Blender) is installed as a Blender extension — check its expression units. Next idea: MakeHuman face expression units as shape keys/face bones for villagers (check if installed/exportable; any download needs owner approval with name/source/licence/size). Claude is making 6 detailed Meshy key NPCs (§5).

## 5. What Claude is still doing (Claude-only tools)
- **Meshy key NPCs** (owner approved ≤ 140 credits on 10-26; credits reset 10-27): Brannoc Tallow, Sister Oriel Vane, Hesk Ironbrow, Captain Hollis, Hesta, King Aldric III (or the most important named NPC if one isn't central). Route: text-to-image concept (3) → `meshy-t2` image-to-3d + 2K texture (15) → rig (5). Staged in `C:\Users\Jonna\Documents\ProjectAshes_art_staging\npc_meshy\<name>\`; if disk allows, integrated on branch `claude/npc-tier-a` (not merged). Review it, then merge.
- On request: Meshy animations for genuine gaps (tell Claude the clip name, character, and what it's for).

## 6. Rules that bit us (keep them)
- Git Bash: `export MSYS_NO_PATHCONV=1`; quote Windows paths for worktrees (`"C:/Users/..."`) or they become `C:\c\...`.
- **Disk:** each worktree with `.godot` ≈ 14.5 GB; C: has hit 0 GB twice (corruption risk). Check `df -h /c`; prefer reusing worktrees; never `rm -rf` outside your own worktree; deletions of user files go to the Recycle Bin (owner empties it).
- **RAM:** 15 GB — run at most ~2 Godot instances total; never kill Godot processes you didn't start (`taskkill /IM` forbidden).
- **Power:** perf numbers are only valid on AC (`(Get-CimInstance Win32_Battery).BatteryStatus` 2 = AC); the laptop was on battery for most past runs.
- Never `--headless` for screenshots (black frames). Read every image you claim to have checked.
- Don't commit `.import`/`.uid` churn, `kingdom/.godot/`, or `project.godot` rewrites from `--import`.
- `player.gd` and `hero_face_driver.gd` are CRLF — keep them CRLF.
- gdUnit needs `--ignoreHeadlessMode`; `py -I` hides numpy/PIL — use `py -E -B`.
- `Agent isolation: "remote"` in Claude ran on the laptop, not the cloud; real cloud agents = Claude Code routines (claude.ai/code/routines).
- Licences: free + commercial-OK only; no account creation; no Meshy spend without the owner.

## 7. Open owner decisions
1. Flip world defaults to Terrain3D + Valencious macro?
2. Physics 30 Hz on PC_HIGH (fps vs combat feel)?
3. Silverford position (keep at Ironmarch, recommended); repaint parchment map for 12 km; Regions 2–4 later.
4. Antigravity IP-flavoured animation packs (Bending/Mythic/Umbrella) — excluded unless the owner OKs.
5. Undo Antigravity commit `8355beff` (32 km map POIs + team skills table) that got onto main?

## 8. Update (later on 2026-10-26)
### Meshy key NPCs — made, NOT integrated (Codex: please integrate)
- 6 characters generated + rigged by Meshy (138 credits; 42 left until the 10-27 reset): **Brannoc Tallow** (hooded spy), **Sister Oriel Vane** (healer), **Hesk Ironbrow** (stonemason/siege engineer), **Captain Bram Hollis** (Ashford Guard captain, the story's betrayer — CAST_R1/STORY_R1), **Hesta Thorne** (Thornfield brewer/tithe keeper, `hesta_body.gd`), **King Aldric III** (House Caldrenn).
- Files: `C:\Users\Jonna\Documents\ProjectAshes_art_staging\npc_meshy\<name>\{concept.png, preview.png, rigged.glb}` (+ `concept_clean.png` for Brannoc/Aldric); lineup `npc_meshy\lineup_meshy_previews.jpg`. ~10k polys, 2K texture, Meshy skeleton.
- Owner/Claude ratings from previews: Hollis 8, Hesta 8, Aldric 7.5, Oriel 7.5, Brannoc 7, Hesk 7. Long cloaks/skirts (Aldric, Oriel, Brannoc) may skin poorly; Hesk is squat with very wide hands.
- **To do (Codex):** re-rig each onto the game's UAL skeleton in Blender the same way hero v2 was done (see `docs/art/hero_tier_a/`, `kingdom/scripts/actors/hero_tier_a.gd`, `tools/blender/hero_tier_a/`), LODs at 12/30 m, put under `kingdom/assets/generated/characters/npc_tier_a/`, and use each as the body of that named NPC/companion where the code spawns them (companions come from PR #9). Then an in-engine lineup render + walk/idle/talk frame sheets. Don't use Meshy's own animations for gameplay — once on the UAL rig they get every existing clip.

### Blender add-ons (installed 2026-10-26, Blender 5.2) — full list in `C:\Users\Jonna\Tools\BLENDER_ADDONS.md`
- **Installed + enabled:** Rigify 0.6.10 (bundled), AnimAll 0.14.0 (extensions.blender.org, GPL), Copy Attributes Menu 0.6.3 (extensions.blender.org, GPL), TexTools 1.6.1 (github franMarz/TexTools-Blender, GPL; harmless KeyError on exit).
- **Already present:** MPFB (MakeHuman for Blender — face expression units for villager faces), Expy Kit (retargeting), Bone Dynamics + Wiggle 2 (secondary motion; not enabled — Wiggle 2 pref entry points at a missing install), dcc_mcp_blender (Blender MCP, under `C:\Users\Jonna\Tools\dcc-mcp`).
- **Skipped:** Animation Layers (paid), Godot Game Tools (repo gone; only a GPL-2.0 2022 fork without Blender 5 support), Bone Selection Sets (not available for 5.2). Downloads in `C:\Users\Jonna\Tools\blender-downloads\`.

### Godot editor MCP
- Restarted and working (http://127.0.0.1:8765/mcp, editor on `C:\Users\Jonna\Documents\PA_wt_mcp\kingdom`). If it's down: `powershell -ExecutionPolicy Bypass -File C:\Users\Jonna\Tools\dcc-mcp\start_godot_mcp.ps1` (prints READY). In Claude Code it must be reconnected via /mcp after a restart.

### Meshy vs our animation pipeline (owner asked)
Meshy animations are generic clips on Meshy's own rig, 3 credits each (presets) / 3–10 (text-to-motion), with no hit/foot-sync timing data. The game uses hundreds of clips on one shared UAL skeleton. So: retarget characters once to UAL and reuse everything; ask Claude for Meshy only for clips that exist nowhere.
