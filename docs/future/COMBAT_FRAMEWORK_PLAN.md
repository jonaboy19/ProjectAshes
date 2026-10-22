# Combat framework plan (owner notes, 2026-10-01): do NOT build yet

Status: **saved for later**. Start only when the owner says "work on the combat system".

These are the owner's research notes (from ChatGPT), condensed. Every link and licence must be re-verified when work starts.

Combat work already done locally (keep it, build on it):
- `docs/anim/COMBAT_AUDIT.md`: the 44 combat clips, the weapon trail module, the timing file for 110 clips (windup, hit, trail, combo and cancel windows), and patches P9–P12.
- The elemental effects: `scripts/vfx/element_fx.gd`.
- Casting clips v2, the living-world clips, the horses work in progress, and the creature telegraphs.

## Principle
- **Do not build combat from zero.** Integrate permissively licensed Godot code and assets (MIT, CC0, Unlicense).
- **Never copy** code, animations, models or effects from commercial games such as Elden Ring or Sekiro. Copy ideas only.
- Aim for an AAA *feel* (responsiveness, reactions, effects, sound, AI), not AAA content volume.

## Donor projects (licences to verify)

| Project | What to take | Role |
|---|---|---|
| Souls-Like-Controller v1.0.0 (Godot asset 5485, MIT, 2026-09-25) | Combos, lock-on, hit reactions, weapon switching, enemy AI sharing the player's weapon and hitbox system | Strongest donor. Don't ship it unchanged |
| Snaiel/Godot4ThirdPersonCombatPrototype (MIT) | Movement, camera, animation structure, combat AI, UI and sound patterns | Reference, plus selected pieces |
| catprisbrey Cats-Godot4-Modular-Souls-like-Template (Unlicense code, assets said to be CC0) | Root motion, parry, dodge, targeting, knockback, ragdoll, 110+ animations | Parts warehouse only (its author says the architecture didn't reuse well) |
| GuilhermeGSousa/godot-motion-matching (MIT) | Natural locomotion (run, turn, stop, strafe) | Test in a lab first. No Android or iOS binaries were found earlier. Exploration only; attacks stay authored |
| MixaBridge (Godot asset 5096) | Mixamo import → bone mapping → AnimationLibrary | Note: Mixamo needs an Adobe account, which we can't create |
| LimboAI (installed) | Enemy decisions on top of the same combat API | Yes |
| GoHitHurt | Hit/hurtbox plumbing | Maybe |
| HitboxGen3D (SnapGamesStudio) | Automatic per-bone hurtboxes | Very useful for body-zone damage |

## Architecture: one data-driven `CombatAction` system for everything
Sword, martial arts, magic, hybrids, creatures, Soulbeasts and mounted combat all use the same system. A new attack is a `.tres` resource (for example `RA_Action_FirePalmHeavy.tres`), not a new script.

| Resource | Contains |
|---|---|
| `CombatAction` | Animation, startup/active/recovery timing, input buffer, combo routes, cancel windows, stamina/mana cost, tags |
| `HitProfile` | Hit shapes, damage types, posture/poise damage, knockback/launch, block damage |
| `MotionProfile` | Root motion, facing, tracking, rotation permissions |
| `DefenseProfile` | Block, perfect block, deflect, parry, dodge i-frames, evade, hyperarmor |
| `ReactionProfile` | Stagger, launch, knockdown, limb/directional reactions |
| `ComboGraph` | Legal follow-ups: light/heavy, direction, stance, after dodge, after parry, airborne, skill |
| `VFXProfile` / `VFXDefinition` | Phases (startup, active, trail, impact, residual), attach bone, pooling, HIGH/MED/LOW budgets, LOD |
| `SFXProfile` | Swing, impact (by surface), magic, environment |
| `CameraProfile` | Shake, zoom, hitstop, FOV impulse, haptics |
| `AIProfile` | When an NPC may or should use the move |
| `AbilityTags` | sword, fire, counter, aerial, guard-break… |

Other classes: `Combatant`, `WeaponMoveset`, `Stance`, `HitResult`, `ReactionProfile`.

## Key systems
- **Frame structure:** startup → active → recovery, plus input buffer, combo, cancel and parry windows, hyperarmor, and movement/rotation permissions. Example light slash: 120 / 160 / 260 ms.
- **Combo graphs**, not fixed strings. Examples: Light→Light→Heavy, Light→Dodge→Heavy, Parry→Riposte, Sprint→Thrust, Backstep→Lunge, Launch→Aerial.
- **Stances and schools.** A school changes the animation set, locomotion, guard pose, combo graph, parry timing, counters, skills and stamina behaviour. Martial-arts examples (not canon): Stone Body, Flowing Current, Gale Step, Ember Fist, Silent Fang.
- **Martial arts as body combat.** Contact points: hands, feet, elbows, knees, and grapple points later. Moves include jab/cross/roundhouse, palm→elbow→sweep, parry→shoulder strike→takedown, aerial spin kick, dash knee, disarm and infused strikes.
- **Weapons:** 1H, 2H, sword+shield, dual, spear/polearm, heavy, bow, staff, unarmed, mounted.
- **Magic uses the same pipeline.** Payload types: projectile, beam, area, field, channel, barrier, counter, mobility, weapon imbue, body imbue, summon, trap, terrain, status, environmental, transformation. Hybrids: a flaming strike is a melee HitProfile plus a Fire payload; a lightning counter is deflect → counter → chain lightning.
- **Swept melee hit detection.** Keep the previous and current blade base/tip and sweep between them, so fast swings can't tunnel through targets. Add skeletal hurt zones: head, neck, chest, abdomen, arms, hands, legs. Soulbeasts get head, horn, wing, tail, armour plate and core.
- **Reaction matrix:** direction × height × strength × damage type × state. Results: recoil, medium or heavy stagger, spin, fall back or forward, kneel, launch, wall impact, ground impact.
- **Defence set:** block, perfect block, deflect, parry, counter, dodge (i-frames), evade (no i-frames), poise, posture/guard break, hyperarmor.
- **Animation layers:**
  - lower body: locomotion and feet;
  - upper body: aim, block, cast;
  - full body: big attacks, rolls, finishers, knockdowns;
  - additive: breathing, injury, recoil, aim offset.
- **IK** (selective): feet on terrain, two-handed grip, shield alignment, grapple contact, finisher placement, mounted weapons.
- **The AAA hit chain (~100 ms):** contact at the true point → directional upper-body reaction → trail ends → sparks at the contact point → sound by material → camera impulse → a few ms of hitstop → vibration → posture loss → nearby AI hears it → the reaction resumes naturally.
- **AI uses the player's actions.** LimboAI chooses CombatActions by range, stamina, target state, openings, danger, personality and skill. No enemy-only attack code.
- **Gameplay is separate from presentation.** Damage never depends on whether effects, sound or camera actually play.
- **Pooling** for projectiles, impacts, particles and decals.
- **Effects:** native GPUParticles3D, RibbonTrailMesh/TubeTrailMesh, shaders and meshes. Effekseer is optional, not a dependency. See `docs/art/VFX_FUTURE_PLAN.md`.
- **combat_lab scene:** test every weapon class, martial-arts action, defence, payload, reaction and effect tier without loading the world.
- **Debug visualisation:** hurtboxes, sweeps, state, windows, posture, AI choice, animation events. Debug Draw 3D is in `docs/TOOLCHAIN_PLAN.md`.
- **Tests:** CombatAction validity, combo graphs, costs, hit detection, save compatibility, state transitions.
- **Android:** benchmark after every layer.

## Work order (when it starts)
1. combat_lab branch: test Souls-Like-Controller without touching the current player.
2. Compare its parts with Rising Ashes' existing systems (keep what's better).
3. Harvest from Snaiel and Cat's projects.
4. Build CombatAction, Combatant, WeaponMoveset, Stance, HitResult and ReactionProfile around the donor code.
5. Swept hits plus bone hurtboxes (HitboxGen3D).
6. Retarget one shared humanoid animation library.
7. Defence: block, parry, deflect, dodge, poise, posture, stagger.
8. Combo/cancel graph.
9. LimboAI on top of the same API.
10. Motion-matching lab with a phone benchmark.
11. Effects, sound, hitstop, camera and haptics last.
12. An Android benchmark after each step.

Then content becomes cheap. For example: "Create the first Wind martial-art school with 18 CombatActions."

## Owner's master task: "RISING ASHES — ADVANCED COMBAT FRAMEWORK"
Use the full prompt the owner pasted on 2026-10-01; the bullets above cover all of its requirements. Its core rules:
- inspect existing systems first;
- data-driven, with no one-off scripts;
- one pipeline for melee, martial arts and magic;
- swept collision and hurt zones;
- directional reactions and the full defence set;
- animation layering and IK hooks;
- combo graphs;
- AI using the same actions;
- a central VFXDefinition with HIGH/MED/LOW tiers and pooling;
- gameplay separate from presentation;
- centralised hit feedback;
- readability over particle count;
- combat_lab, debug visualisation, automated tests;
- frequent Android benchmarks;
- incremental work, preserving the systems that already work;
- documentation for creating attacks, styles, spells, movesets and effects, and for AI use.

## Free animation sources (verify before use)
- **Rokoko** free packs:
  - 6 martial arts
  - 13 fight
  - magic-themed
  - 263-asset pack

  Rokoko says they're commercial-OK. **Note:** our 2026-09-30 check found Rokoko downloads and plugins need a login. The owner would have to download them, then we process them.
- CMU mocap (in use).
- Quaternius UAL and KayKit, CC0 (in use).
- The phone-video tool with RTMPose (installed).

Sources (owner's research links): godotengine.org/asset-library/asset/5485, github.com/Snaiel/Godot4ThirdPersonCombatPrototype, github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template, github.com/GuilhermeGSousa/godot-motion-matching, github.com/SnapGamesStudio/HitboxGen3D, godotengine.org/asset-library/asset/4852 (LimboAI), godotengine.org/asset-library/asset/5096 (MixaBridge), rokoko.com resources pages.
