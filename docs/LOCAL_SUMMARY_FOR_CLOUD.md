# Local PC session → cloud: everything done so far (2026-10-06)

Cloud session: **read this first after every pull.** The live status is in `docs/STATUS_LOCAL.md`; hook requests are in `docs/regions/HOOKS_FOR_CLOUD.md`; ownership notes are in `docs/LOCAL_SESSION_HANDOFF.md`.

## Owner decisions and plans
- `docs/regions/OWNER_DECISIONS.md`:
  - poster names are shown on screen;
  - royal courtship is traditional;
  - at most 3 settlements;
  - **retinue, settlement and ascension are built by the cloud** (`docs/design/RETINUE_SETTLEMENT_ASCENSION.md`).
- `docs/regions/REGION_1_PLAN.md`, `docs/regions/EMOTION_MAP_R1.md`, `STORY_R1.md`, `CAST_R1.md`.
- **On hold until the owner says go** (`docs/future/`):
  - `COMBAT_FRAMEWORK_PLAN.md`
  - `AAA_PIPELINE_PLAN.md`
  - `WORLD_VISION.md` (13 kingdoms, memory, careers, personality genome, Soulbeasts)
  - `../art/VFX_FUTURE_PLAN.md`
  - `../TOOLCHAIN_PLAN.md` + `TOOLCHAIN_AUDIT.md`
- **Current owner priority:** `docs/art/AAA_PRESENTATION_REVIEW.md`. Fix in this order:
  1. hero
  2. locomotion
  3. camera
  4. lighting
  5. materials
  6. HUD
  7. NPC models
  8. NPC animation
  9. clutter
  10. VFX
  11. dialogue
  12. sound
  13. LOD

  **Polish ONE Ashford street block as the quality benchmark before building more world.**

## Delivered by the local session (all on this branch)
- **Region 1 systems** (in `scripts/region1/`, wired via HOOKS_FOR_CLOUD):
  - the scaffold;
  - Wardlines and the rune gestures;
  - Ember Legacy;
  - Ashsight (ghost upgrade included);
  - the tutorial director;
  - quests and dialogue for "The Stones Are Dimming" (lint-clean).
- **Art:**
  - the Elder Stones;
  - the Highwatch kit;
  - the Silverford guild hall and chapel, with interiors;
  - the rift kit;
  - the Stagborn elk and the Warden;
  - Hollin's Reach valley and its landmarks;
  - the parchment map plus its layer;
  - the Style G passes (~74/100).
- **Build kit:** 81 snapping pieces in `data/build_kit/pieces.json`, plus Palworld-style build mode connected to the cloud's construction crews. Skill: `ashes-build-kit`.
- **Medieval towns:** 153 unused Meshy models placed across 21 sites.
- **Meshy downloads:**
  - batches 1 and 2: `assets/incoming/meshy_free/`;
  - the owner's batch 3: `assets/incoming/meshy_dl3/` (67 kept, including 10 rigged characters).
- **Animation:**
  - the living-world library (188 clips) plus VAT crowds and smart objects (patch P13);
  - combat (44 clips, a weapon trail, the timing file for 110 clips, P9–P12);
  - locomotion transitions and jumping (P5/P7);
  - casting v2;
  - creatures (wolf, boar, bear, spider, wasp, goblin, orc, troll), traversal and the farm animals;
  - horses work in progress (`local-wip/horses`).
  - Codex's branches are merged (P15).
- **AAA feel (bfc7f9bc):**
  - a 3.9 m shoulder camera at FOV 54 with occluder fade;
  - NPC labels reduced to the name only, with a Developer Simulation Overlay;
  - the RISING ASHES title;
  - calmer grade;
  - textured horses, braziers, frayed cobbles.

  Skill: `ashes-aaa-camera-hud`.
- **Environment:** the Rift caves rebuilt; squad "Line" labels only in command view. Skill: `ashes-environment-look`.
- **Phone (S22) release QA:** `docs/qa/RELEASE_READINESS.md`.
  - The APK went from 1.40 GB to about 0.5–0.6 GB (ETC2 and texture caps, export excludes, arm64).
  - GodotGAS and unused addons were removed.
  - A thermal guard and an Auto fps setting were added.
  - **Still NO-GO:** LOW is 26–29 fps, 3.2 GB memory and severe heat. A performance agent is working on it.
- **Tools:**
  - MCPs (DCC-MCP Godot and Blender, Serena, Context7) in `.mcp.json`;
  - Debug Draw 3D, gdtoolkit lint, scrcpy, RenderDoc, Perfetto, gltfpack, Real-ESRGAN, Krita, Piper and more.

  See `tools/README_EXTERNAL_TOOLS.md` and skill `ashes-external-tools`.

## Running now (local)
- AAA feel passes until 9+, plus the benchmark street.
- Hero Tier-A model, built from the owner's Meshy characters.
- Phone performance (fps, memory, heat).

## Please (cloud)
- Apply the pending hooks in `HOOKS_FOR_CLOUD.md`.
- Don't re-add removed addons.
- Mark quick test-stage renders as "test stage", not the real look. Hand visual QA to the local PC, which has the GPU and the phone.
- **Make every change cheap on mobile.** LOW is over budget.
