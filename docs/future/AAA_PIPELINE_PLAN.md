# AAA production pipeline plan (owner notes, 2026-10-01)

Status: **saved for later**. A reference list of studio-style tools and systems. Install items only when the owner OKs them. Verify each licence and account requirement first. Our past checks are noted in the table.

| Area | Tool / system | Gives us | Owner priority | Our notes |
|---|---|---|---|---|
| Animation authoring | Cascadeur | Physics-assisted combat animation, falls, finishers, creature attacks | Very high | **Our 2026-09-30 check: the free licence is non-commercial with no FBX export.** Needs a paid licence, so it's the owner's decision |
| Mocap | Rokoko Studio | Recording or video → FBX | Very high | Needs a login. The owner has to run it; we process the FBX |
| Locomotion | Godot Motion Matching (MIT) | Natural run, turn, stop, strafe | Test first | Lab plus a phone benchmark first |
| Animation cleanup | Blender + Blender MCP | Retargeting, layers, IK cleanup, compression | Very high | Blender done; MCP in `docs/TOOLCHAIN_PLAN.md` |
| Audio | Wwise + alessandrofama/wwise-godot-integration (Android/iOS, Godot 4.3+) | Layered impacts by weapon × surface × strength, music states, rooms/portals, occlusion | High (later) | Wwise licensing is free under a revenue/asset limit; must be checked. Delay |
| Camera | Phantom Camera | Combat framing, zones, cutscenes | High | Installed |
| VFX | Effekseer + Godot GPU particles | Reusable magic effects | High | Installed. See `docs/art/VFX_FUTURE_PLAN.md` |
| Materials | Material Maker (free) | Procedural PBR: `RA_Stone_Wet/Dry`, `RA_Wood_Old`, `RA_Plaster_Damaged`, `RA_Mud_Road`, `RA_Castle_Stone`, `RA_Iron_Worn` with age, dirt, wetness, moss and damage parameters | High | Installed. Fixes buildings looking like they come from different asset sets |
| Materials (premium) | Substance 3D Painter | Hero assets, weathering | Later | Paid |
| Terrain | Terrain3D | Large terrain, LOD, foliage | Very high | Installed |
| Dressing | ProtonScatter | Vegetation, rocks, clutter | Very high | Installed |
| Procedural towns | Blender Geometry Nodes | e.g. `RA_HouseGenerator` (width, depth, floors, wealth, district, roof, materials, shopfront, balcony, chimneys, damage, seed). Also roads, walls, farms, bridges, stalls, fences, ruins, castle walls, village plots | Very high | Not started. Great fit for Style G variety |
| Streaming | Scene Splitter (MIT) + `WorldRegionManager` | Near (0–80 m, full) / mid (80–300 m, HLOD + MultiMesh crowds + reduced AI) / far (>300 m, simulation data only) | Very high | Living-world VAT LOD exists; the region manager doesn't yet |
| Rendering | Godot HLOD visibility ranges, LOD, occlusion culling, MultiMesh | Dense mobile towns | Mandatory | Partly done (impostors, VAT, LOD) |
| Physics | Jolt (built in since 4.4; default for new 4.6 projects) | Better ragdolls, debris, knockback | High | Test on a branch, don't just flip the setting |
| AI | LimboAI | Behaviour trees over CombatAction | High | Installed |
| Dialogue | Dialogue Manager 3 | Dialogue and localisation | High | Installed |
| Crash reporting | Sentry (Godot SDK) | Device, crash and script errors with versions | Mandatory before release | Installer exists (`tools/install_sentry.sh`); needs a DSN/account from the owner |
| Telemetry | GameAnalytics (official Godot SDK) | Where players quit, die or get lost | Soft launch | Needs an account |
| Backend | Nakama | Accounts, cloud data, multiplayer | Only if needed | — |
| AI development | Godot MCP + Serena (+ Context7) | Agents operate the editor and fetch only the code they need | Very high | Being installed (`docs/TOOLCHAIN_PLAN.md`) |
| Testing | GdUnit4 | Regression tests | Mandatory | Installed; CI is blocked by the GitHub billing lock |
| Mobile profiling | Android Performance Analyzer / AGI | Real phone bottlenecks | Mandatory | AGI and Perfetto installed |

## Owner's recommended stack now
Godot plus:
- Godot MCP, Serena, Blender MCP
- Terrain3D, ProtonScatter, LimboAI
- Dialogue Manager 3, Phantom Camera, Effekseer
- Material Maker, GdUnit4, Git, Sentry

External tools: Blender Geometry Nodes, Cascadeur, Rokoko Studio. The last two need the owner's licence or account.

Systems to build:
1. the CombatAction framework (`docs/future/COMBAT_FRAMEWORK_PLAN.md`)
2. three-tier world simulation
3. region streaming
4. the HLOD/LOD/occlusion pipeline
5. a procedural settlement kit
6. a central VFX system
7. a central animation library
8. a central audio event system
9. automated Android testing

**Delay:** Wwise, motion matching, Substance, and any backend or networking.

Sources (owner's links): cascadeur.com, rokoko.com/pricing, github.com/alessandrofama/wwise-godot-integration, docs.blender.org (Geometry Nodes), docs.godotengine.org (visibility ranges, Jolt), godotengine.org/asset-library assets 3822 (motion matching), 4756 (Sentry), 5162 (GameAnalytics), materialmaker.org.
