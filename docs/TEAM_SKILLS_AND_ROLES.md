# Project Ashes: Team Skills, Architecture & Coordination (Claude, Codex, Antigravity)

This document formalizes the division of labor, specialized skills, and workflows between the three autonomous engineering agents collaborating on *Project Ashes*.

---

## 1. Role & Capability Matrix

| Capability / Domain | **Claude** (Cloud Session) | **Codex** (Local Gameplay / Combat) | **Antigravity** (Local 3D & World Lead) |
|---|---|---|---|
| **Primary Environment** | Linux container, headless Godot, allowlisted network | Local Windows, Godot Editor, fast iteration | Local Windows, GPU (RTX 4070), Blender 5.2, Python |
| **Branch Ownership** | `claude/focused-curie-m09hbd` | Feature branches (`gpt/*`, `local/*`) | `antigravity/aaa-mocap-animations` |
| **Core Skills** | Core GDScript, quest systems, dialogue, state machines, AI behavior trees | Combat feel, camera controller, hitboxes, UAL clip blending, gamepad input | 3D world streaming, PBR materials, Blender LODs, UAL mocap retargeting, renders |
| **Visual / Graphics** | Headless software render verification | In-editor visual playtesting | Cycles & EEVEE 1080p renders, Forward+ lighting profiles, 8GB RAM PC optimization |
| **Coordination Doc** | Reads & updates `docs/LOCAL_SESSION_HANDOFF.md` | Reads & updates `docs/LOCAL_SESSION_HANDOFF.md` | Authors `LOCAL_SESSION_HANDOFF.md` & HTML Showcases |

---

## 2. In-Depth Agent Skill Profiles

### A. Claude (Cloud Architectural Lead)
* **What Claude Does Best:**
  * **Systemic GDScript Engineering:** Designing clean, decoupled architecture across `kingdom/scripts/core/`, `sim/`, and `ui/`.
  * **Quest & Dialogue Integration:** Wiring `DialogueManager` dialogue resources (`.dialogue`), `QuestWeaver` quest graphs, and dynamic NPC branching.
  * **Behavior & Scheduling:** Authoring `LimboAI` behavior trees (`BTPlayer`, `BTTask`) and daily schedule planners for villagers, guards, and merchants.
  * **Engine Life Systems:** The life path engine (`life.gd`), aging, economy, trade prices, guild commissions, and war simulations (`war_sim.gd`).
* **Cloud Constraints & How We Support Claude:**
  * Claude runs in a headless container without a dedicated GPU or soundcard.
  * *Antigravity's support:* We pre-bake, optimize, and test all 3D GLBs, audio banks, and mocap files locally, committing clean assets to `kingdom/assets/incoming/` and `kingdom/assets/generated/` so Claude only needs to reference valid file paths.

---

### B. Codex (Gameplay, Combat & Feel Specialist)
* **What Codex Does Best:**
  * **Combat Combo State Machine:** Weapon movesets (one-handed swords, greatswords, dual daggers, polearms, bows, umbrellas).
  * **Animation Blending & Mechanics:** Integrating the Universal Animation Library (`UAL1_Standard.glb`, `UAL2_Standard.glb`, `UAL_Extra_100STYLE.glb`) into smooth combat transitions with root motion and blend trees.
  * **Input & Camera Responsiveness:** Camera pitch/yaw damping, lock-on targeting (`PhantomCamera`), dodge i-frame windows, parry deflections, and controller vibration.
  * **Hitbox / Hurtbox Spatial Queries:** Area3D physics queries, stagger durations, and damage calculations.
* **Collaboration with Codex:**
  * Antigravity provides retargeted UAL clips (`UAL_AAA_*.glb`) and verified collision hulls, freeing Codex to tune timing curves, cancel frames, and stamina costs.

---

### C. Antigravity (Local 3D Engine, World & Mocap Lead)
* **What Antigravity Does Best:**
  * **32km Valencious World Architecture:** Authoring the 64 × 64 sector grid (`valencious_32km_sectors.json`), coordinate systems, and background chunk streaming.
  * **Blender 5.2 Automation Pipeline:** Headless Python tools (`tools/pc_world_upgrade.py`, `tools/meshy/bake_lod.py`, `tools/capture_screenshots.py`) for voxel remeshing, PBR material creation, and LOD decimation.
  * **Real-GPU Rendering & Visual Proof:** Generating authentic 1080p PBR beauty renders with EEVEE/Cycles, eliminating placeholder cylinders.
  * **UAL Humanoid Rigging & Mocap:** Rigging custom meshes (Orc Warchief, Dark Elf, High Elf, Draco-Horse) onto the standard UAL bone hierarchy so all 300+ clips play without distortion.
  * **PC Performance Tuning:** Enforcing the **$\le 4.2$ GB engine RAM envelope for 8GB RAM PCs**, optimizing draw calls, MultiMesh grass scattering, and shadow split distances.

---

## 3. Data Contract & Source of Truth

| System | JSON Source of Truth | Engine Loader Script | Owner / Maintainer |
|---|---|---|---|
| **World Sectors** | `kingdom/data/world/valencious_32km_sectors.json` | `WorldGen` / `TerrainStreamer` | Antigravity |
| **World POIs & Map** | `kingdom/data/world/valencious_map_pois.json` | `WorldGen` / `RegionSites` | Antigravity |
| **First Region Lore** | `kingdom/data/world/first_region.json` | `first_region.json` | Claude |
| **Races & Evolution** | `kingdom/data/world/races.json` (v3) | `RaceEvolutionSystem` | Antigravity / Claude |
| **AI Race Profiles** | `kingdom/data/ai/race_behavior_profiles.json` | `LimboAI` / `CampMonster` | Antigravity / Codex |
| **PC Asset Manifest** | `kingdom/data/world/pc_world_assets_manifest.json` | `Assets.gd` / `Quality.gd` | Antigravity |
| **Interiors Pipeline** | `kingdom/scenes/interiors/*.tscn` | `EnterableBuildingManager` | Antigravity (scenes) / Claude (triggers) |

---

## 4. Git Branching Hygiene

1. **Keep Claude's branch clean:** `claude/focused-curie-m09hbd` must remain clean and synchronizable with remote.
2. **Deliver via feature branches:** Local 3D assets, mocap animations, and manifest files are staged on `antigravity/aaa-mocap-animations` and merged cleanly.
3. **Persistent Local Files:** All renders, HTML viewers, and interactive maps are mirrored to disk (`docs/VALENCIOUS_WORLD_VIEWER.html` and `brain/interactive_valencious_world_viewer.html`) so branch switching never deletes them.
