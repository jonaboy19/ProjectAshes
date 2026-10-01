# Systems Mining: Combat, Abilities, World and RPG Economy

Reference-textbook study of three shipped open-source games, turned into Rising Ashes (Godot 4.6, mobile) designs.
No code, data or assets were copied. Everything below is prose in our own words; file/function names are citations only.

## 0. Licences and coverage

| Project | Licence | Rule | Read |
|---|---|---|---|
| Jedi Academy (grayj/Jedi-Academy, code/game) | GPLv2 | read only, never copy | bg_panimate.cpp (saberMoveData, chain/transition), wp_saber.cpp (WP_SaberParry, WP_SaberBlock*, forcePowerNeeded, WP_ForcePower*), AI_Jedi.cpp (Jedi_AttackDecide, Jedi_CombatTimersUpdate, Jedi_CombatDistance, Jedi_Strafe, Jedi_DodgeEvasion), NPC_combat.cpp |
| Ryzom Core (ryzom/ryzomcore, server entities_game_service) | AGPLv3 | read only, never copy | phrase_manager/combat_phrase.cpp, combat_action*.cpp, combat_defender.cpp, faber_phrase.cpp, forage_phrase.cpp, harvest_source.cpp, forage_progress.h, creature_manager/harvestable.cpp, mission_manager/, egs_pd + pd_scripts, building_manager/ |
| O3DE StarterGame + startergame-assets (assets CC BY-NC) | Apache-2/MIT code, assets CC BY-NC (reference only) | no assets ever | NOT READ: github.com/o3de/StarterGame was not reachable from the sandbox (clone asked for credentials; the repo is gone or private). startergame-assets resolves but is art only. Section 4 is therefore from general knowledge of the Lumberyard sample's architecture (component entities, event buses, Lua/ScriptCanvas AI), flagged as unverified. Re-mine if a mirror is found. |

Clones were sparse, shallow (36 MB) and deleted at the end.

## 1. Melee combat (Jedi Academy)

### How it does it
- **Move table, not code branches.** `saberMoveData[]` is one row per move: animation, start quadrant, end quadrant, anim flags, blend time, blocking class (none/wide/tight), `chain_idle` (move to fall back to), `chain_attack` (move if the player presses attack again), trail length. A whole fighting style is data plus a transition rule.
- **Quadrant continuity.** Each swing ends in a quadrant (TL, T, TR, L, R, BL, B, BR). The next swing must start where the last one ended; if not, a short "transition" move is inserted (`transitionMove[end][start]`). That makes chains look physically connected and gives a tell: transitions are the vulnerable moments.
- **Move state machine in the player-movement layer** (`PM_SetSaberMove`, torso anim timer). Torso and legs are separate: attack plays on the torso while legs keep locomotion, with some moves locking legs (flips, lunges). Input is read each frame, and a "can chain" gate is the anim timer running down.
- **Blocking is positional.** Hit location picks one of five parry directions (`BLOCKED_UPPER_RIGHT` etc, `WP_SaberBlockNonRandom`); the parry anim comes from that. Blocking quality is gated by saber-defence level and by whether the defender is mid-attack/transition/bounce/knockaway (`WP_SaberParry` refuses to play a parry when already attacking: attacking commits you).
- **Parry outcomes are graded.** Parry -> bounce on attacker (attacker enters a "bounce" move), knockaway, or "broken parry" when the defender is overwhelmed (low force/defence), which stuns and opens them. Damage already registered in that swing is cleared on parry.
- **Clash/lock.** When two blades meet during attacks, `G_SaberLockAnim` picks lock animations by both styles and top/side; the loser/winner is decided by a lock contest over time (mash/strength), with win/lose/super-break outcomes. NPCs that win a lock get a skill-weighted chance to immediately press the advantage (`SEF_LOCK_WON` in `Jedi_AttackDecide`); a non-locked NPC refuses to join a lock it is not in.
- **Damage is a continuous trace** along the blade each frame (`WP_SaberDamageTrace`) during active frames, not a single hit event; hit-once-per-swing bookkeeping prevents multi-hit.
- **Force resource.** One pool, per-power costs table (`forcePowerNeeded`), power levels 0..3 scale effects, powers are "instant" or "hold/duration" (drain per tick), regen is a slow +1 tick that pauses while a power is active, `WP_ForcePowerAvailable` is the single gate. NPCs are exempt from the drain (infinite force).
- **NPC fighter AI** (AI_Jedi): an *aggression* scalar adjusted on timers by situation (enemy unarmed -> +2, enemy ranged and not shooting -> +1, too close -> +1); combat distance logic (close in, hold, retreat), strafing with random min/max timers, a separate evasion layer for incoming projectiles (`Jedi_DodgeEvasion`, deflect vs dodge by rank), and per-class "chance" numbers (boss 20, elite 10, grunt rank) used for opportunistic follow-ups. Behaviour = timers + dice weighted by rank, not a behaviour tree.

### Strengths / weaknesses
+ Table-driven chains are easy to balance and mod; quadrant rule gives readable, physical-looking flow.
+ Parry/knockaway/broken-parry ladder creates risk/reward without a "perfect parry" button.
+ AI skill expressed as numbers (rank, chance), cheap per frame.
- 8-direction blocking needs mocap for every quadrant; huge anim count (we cannot afford it).
- Per-frame blade traces are costly and need exact collision; on mobile use sampled swept shapes.
- Lock minigame needs a dedicated paired animation set; high content cost.
- Aggression scalar with many magic numbers is hard to tune without a test arena.

### Mobile applicability
- Keep: data-driven move rows, cancel windows, graded parry result, rank-weighted AI dice, aggression scalar, resource gate. 
- Reduce: 8 quadrants -> 3 lanes (high/mid/low or just left/right/thrust) used for block *effects* not unique animations; lock -> a 0.6 s "clash" beat (hit-stop, spark, both pushed back) resolved instantly; blade trace -> 3 sampled sweeps per active window.
- Touch: one-thumb attack, hold-to-block, swipe-dodge; auto-facing assist (we have it).

### Compared with our code
Player (`kingdom/scripts/actors/player.gd`) already has: 4-step `COMBO` table (anim, speed, damage, cost, hit time, lock), early-press `ATTACK_BUFFER`, `SWING_CANCEL` tail, dodge-cancel and active-frame protection (`_in_active_frames`), weak (tired) swings, parry with 8 stamina refund + riposte bonus (`_parry`, `_track_block`), hit-stop, target assist/lunge, blade-synced trail. Monster (`monster.gd`) has per-species windup/recover/cooldown/reach/damage, telegraph, attack tokens (`creature_attack_tokens.gd`: capped close-attack slots, stagger), circling at a ring radius. Wolf has its own copy.

Gaps: (1) combo is a const array inside player.gd, not a reusable resource, so NPCs/other weapons cannot share it. (2) Monsters have a single attack; no move choice, no chains. (3) No guard-break/poise: a parry is binary and the monster cannot clash back. (4) Player blocking has no directional/graded outcome (parry, block, broken guard). (5) Humanoid NPC fighters (bandits, sect/knight students, guards) do not exist as a decision model; they would reuse the monster path. (6) Hit resolution is a timer callback (`create_timer(hit_t)`), not an anim-event/active-window; multiple victims and "hit once" are ad hoc. (7) No test arena that simulates N fights headlessly for balance.

### Design: CombatAction architecture for Rising Ashes
`CombatAction` is a `Resource` (data) plus one small runner node; both player and NPCs use it.

```
CombatAction (Resource)
  id, owner_kind        # "sword", "fist", "sect_palm", "knight_charge", "wolf_bite"
  windup, active, recovery            # seconds at 1.0 speed
  cancel_into: Array[{action_tag, from_t, to_t}]   # e.g. ["attack","dodge"] in last 22% recovery
  hit_shape: {kind: arc|line|circle, reach, width, angle}  # sampled at active start/mid/end
  damage, poise_damage, knockback, hitstop
  cost: {stamina, qi, mana}
  lane: high|mid|low                  # for block/parry matching only
  props: unblockable, parryable, armor_during_windup, super_armor, tracks_target
  anim_role, anim_speed, move_during: lunge curve (distance, ease)
  telegraph: {color, cue_t}           # fed to monster nameplate/VFX
  chain: next_if_press, next_if_none  # Jedi's chain_attack/chain_idle
```
Runner state machine: IDLE -> WINDUP -> ACTIVE -> RECOVERY (-> next action | IDLE), plus STAGGER, GUARD_BROKEN, CLASHED. Timing source: **data-driven** (windup/active/recovery numbers) and animations are time-scaled to fit (as player.gd already does with `speed`); anim markers are an optional override for trails only. This keeps headless tests deterministic (no AnimationPlayer needed) and makes weak/haste buffs trivial.

Clash resolution (instead of a lock minigame), evaluated when an ACTIVE hitbox overlaps a defender in WINDUP/ACTIVE with an overlapping ACTIVE hitbox:
1. both attacks ACTIVE within 0.12 s of each other and both parryable -> CLASH: compare `poise_damage` plus stat (strength/skill rank + realm bonus + small seeded random); winner continues with a shortened recovery, loser enters CLASHED (0.45 s, no damage, pushed back 1.5 m). A tie bounces both.
2. Defender blocking (holding guard): lane match -> full block (stamina cost = damage * 0.6), lane mismatch -> partial; poise damage > remaining guard poise -> GUARD_BROKEN (0.9 s stagger, riposte window for attacker).
3. Defender blocking in first 0.18 s (existing PARRY window) -> parry: attacker CLASHED, defender gets riposte bonus (already exists) and stamina refund.
4. Otherwise hit.
Graded result enum: HIT, BLOCKED, PARRIED, GUARD_BROKEN, CLASHED, DODGED. One function `CombatResolver.resolve(attack, defender) -> result` (pure, static, unit-testable like `Tokens`).

NPC fighter decision model (humanoids and beasts), Jedi-style but cheap:
- Inputs per think (0.2-0.3 s tier, not per frame): distance, target state (windup/recovery/blocking/staggered), own stamina/poise, tokens held, pack count, rank 0..10.
- `aggression` 0..1 scalar, nudged on a 2-5 s roam timer: +0.2 when target is recovering or out of stamina, +0.2 when target has a ranged tool and is not using it, -0.2 when own HP low, rank sets the baseline. Aggression picks between: APPROACH, CIRCLE (existing ring), POKE (single light attack), COMBO (full chain), GUARD, RETREAT, FEINT (rank 6+: start windup, cancel at 40%, punishes early parry).
- Reaction: when the target enters WINDUP within reach, roll `react_chance = rank*0.07` to GUARD or DODGE (reaction delay 0.25 - rank*0.015 s so low ranks are beatable). Never react twice inside 1.2 s.
- Follow-up: after a clash/guard-break win, roll `rank/30` to press the advantage immediately (Jedi `SEF_LOCK_WON` idea).
- Attack tokens remain the pack governor; tokens hold ring positions, and `STRIKE_GAP` already staggers strikes.
- Archetype data: `{moves:[CombatAction ids with weights], rank, poise, react, style_tags}`. Wolf, goblin, bandit, sect disciple, knight recruit differ only by data.

Mobile budgets: <= 8 actively deciding fighters in 40 m (others sleep on the 0.5 s tier), decision tick 4 Hz, hit test = 3 sampled shape queries per attack (not per frame), at most 1 CombatResolver call per attack. Hit-stop and clash VFX pooled. Target < 0.4 ms/frame for combat logic at 8 fighters.

## 2. Ability system (Jedi force powers, Ryzom phrases/bricks)

### Jedi
Single pool, table of costs, levels 0-3, instant vs hold powers, `WP_ForcePowerStart/Run/Stop` lifecycle (start deducts, run ticks drain and applies effect, stop cleans up), cone+radius targeting query (`WP_ForceThrowable`), counter-powers (absorb, protect) checked at application time (`WP_AbsorbConversion`). Weakness: powers are hard-coded in 12k-line file; cooldown is a debounce timestamp per power.

### Ryzom (the stronger textbook)
Abilities are **phrases built from bricks**: a combat/magic/craft/forage phrase is a list of bricks (action + option + credit/cost modifiers) validated by a common lifecycle `evaluate -> validate -> update (cast time) -> launch -> execute -> apply`. Costs (HP/sap/stamina/focus) are summed from bricks; a bonus option raises cost and success; sustain costs for auras. Effects are separate objects with duration, family (so same-family effects do not stack: `lookForActiveEffect`, effect families), and `combat_action_*` modifiers (stun, bleed, DoT, slow, disarm) attached to a hit. Defence is a skill (`getCurrentDodgeLevel/ParryLevel`) compared to attacker skill, with debuff effects that lower it.
Strengths: composition scales to thousands of abilities from tens of modifiers; effect families prevent stack abuse; one lifecycle for every ability class including gathering and crafting.
Weaknesses: server-heavy, MMO UX of building phrases is bad on mobile. Take the data model, not the UI.

### Compared with our code
`technique_caster.gd` (830 lines): slots U/Y/O/H, seal-chant minigame (`begin_seals`, `input_seal`, `SEAL_TIME`), `_pay` per-resource, `_resolve` branching to area/launch/chain/dash/blink/support, burn DoT, training tags. `skills.gd`: trees, ranks, passive slots, manuals, cooldowns (`cooldown_of`, `tick`), `begin_cast(id,pools,sealed)`, cultivation realm/stage/breakthrough. `power_paths.gd`: five paths (magic/bending/sect/knight/beast) with distinct resources, strain, injuries, cross-training penalty, prodigy gate.

Gaps: (1) the technique caster fuses input, resource payment, targeting, effect and VFX; monsters and NPCs cannot cast. (2) No effect objects with families/duration/stacking rules; burns and buffs are one-offs (`add_buff` with stats). (3) Chantless vs chant is a boolean `sealed` flag; ACADEMY_PLAN says chantless is advanced-only, so the gate belongs in data and `power_paths`, not in the caster. (4) Sect and knight arts share the same technique engine without their different flavour (sect: strain/channels/manuals; knight: aura, reinforced forms, charge, armour arts). (5) Defence skill does not scale with path/rank. (6) No counter-power (ward/absorb) vs techniques.

### Design: Ability pipeline
```
AbilityDef (data row; JSON or Resource)
  id, path: magic|bending|sect|knight|beast, tier
  cast: {kind: instant|chant|channel|charge, chant_seals: [..], chant_time, chantless_req: {magic_level, spell_theory, milestones}}
  costs: {resource: amount}  # resource names come from power_paths.POOL per path
  cooldown, global_lockout
  targeting: {kind: self|target|cone|line|circle_at_point|chain|projectile, range, radius, angle, max_targets, lock_assist}
  effects: [ {type: damage|heal|dot|slow|stun|buff|shield|dash|blink|summon, magnitude, duration, family, tags} ]
  action: CombatAction id (optional) for melee-integrated arts (sect palm, knight charge)
  vfx_role, anim_role, audio_role
```
Lifecycle (single class `AbilityRunner`, one per actor, used by player and NPCs): `can_use` (resources, cooldown, silence/stun, path rules, injuries) -> `begin` (pays on start for instant, on release for chant) -> `windup/chant` -> `resolve` (targeting query, effects applied via `EffectSet.apply(target, effect)`) -> `recover`. `EffectSet` per actor: keyed by effect `family`, rules: refresh | replace-if-stronger | stack-to-N; tick on 0.5 s tier; serialisable.
Path flavours:
- **Magic**: mana pool; beginner abilities require chant seals (existing minigame); chant shortens with level; **chantless** only when `chantless_req` met (high magic level, spell-theory mastery, N path milestones), default `cast.kind` chant; overdraw risk from `power_paths`.
- **Sect (donghua)**: qi pool + channel strain; techniques learned from manuals; stances and breath; abilities may bind to CombatActions (palm strike with qi add-on); breakthroughs unlock tiers; overuse injures channels.
- **Knight (anime-style)**: stamina + aura reinforcement; abilities are mostly CombatActions with aura modifiers (reinforced slash, charge, armour art), work with empty qi; armour load scales cost.
- **Bending / beast**: element gate (`environment_factor`), bond sync for beast commands.
Defence parity: `defence_rating(actor)` combines path rank, armour, stance; counters (ward, absorb) are effects with families that the resolver checks before damage.
Cooldown model: per-ability timestamp plus a short global lockout (0.3 s, existing `CAST_LOCK`); no hold-power drain on NPCs (copy of Jedi trick): NPC abilities use cooldown only, with a stamina-less budget so AI stays cheap.
Mobile: max 4 equipped slots (we have U/Y/O/H) plus one dash; touch uses a radial cluster; targeting uses tap-lock and auto-aim cone; effect ticks on 2 Hz tier; VFX cap per scene already governed by `ashes-performance`.

## 3. Large world, creatures and persistence (Ryzom, partially O3DE)

- **Ryzom creatures**: `creature_manager/` creatures own harvestable material (`harvestable.cpp`): a corpse carries typed raw materials by creature sheet; skill decides what you can take. Loot/harvest state machine (`loot_harvest_state`). NPC AI lives in a separate service (AIS) reading "sheets" (data files) with groups, behaviours and spawn rules; EGS (game service) is authoritative for combat. Lesson: AI behaviours are data-selected, spawning is controlled by zones.
- **World data**: "continents", "deposits" (`deposit.cpp`: ore/forage areas with quantity that depletes and regrows), outposts, buildings with rooms/instances (`building_manager`). Everything static is "sheets" loaded at boot; dynamic state lives in persistent data (PD) containers generated from schema files (`pd_scripts`) with a DB log of every change.
- **Persistence**: schema-defined PD classes (`egs_pd`, `guild_pd`, `fame_pd`) so saving and replication are generated; only deltas are written; characters, guilds, fame, missions are separate containers saved on different cadences.
- **O3DE StarterGame** (unverified, not read): composed of level prefabs, slices, component entities (each behaviour a component: camera, locomotion, weapon, AI), event buses for decoupling weapon<->character, objective markers as entities with triggers, doors as state-machine entities. These same ideas are Godot-native already (scenes, signals, Area3D).

### Compared with our code
We already have `save_manager.gd`, realm modules with tick tiers (`ashes-realm-module` skill), chunked day ticks, region sites with ids and discovery. Gaps: (1) no depletable/regrowing gather deposits as persistent world entities (gathering is item-table-driven); (2) per-container save cadence and dirty tracking (a large world saved wholesale); (3) creatures do not carry harvestable-by-skill part tables; (4) missions data are not a separate schema with prerequisites/events.

### Design: world data and persistence
- **Static vs dynamic split**: sites, deposits, creature species, abilities, recipes are read-only data (JSON/Resource, loaded lazily per region). Dynamic overlay per entity id: `{id: {depleted_until_day, qty, owner, state}}` only for entities that differ from default. Save = overlay dictionaries only.
- **Dirty containers** (player, inventory, realm modules, region overlays, missions) each with `version`, `dirty` flag; autosave writes dirty ones on a 30-60 s idle tick and on pause (mobile app-suspend hook), atomically (write temp, rename).
- **Chunked streaming**: region overlay loaded when region activates; far regions advance by day-tick catch-up (formula-based regrowth) instead of simulating.
- **Objective markers** (from StarterGame idea): a `Marker` data row (id, world pos or site id, label key, visible_if) shown by a single marker layer on map/compass; max 12 on screen.
- **Interactive doors/containers**: one `Interactable` state machine (closed/open/locked/broken) with id and overlay state; reuse for chests.

## 4. Third-person camera/locomotion, weapon-character communication, AI wander/attack (StarterGame, unverified)
Our player.gd already exceeds a starter sample (acceleration curves, pivot brake, coyote time, lean, multiple view rigs, camera blocker layer). Keep. From the architecture: weapon<->character via signals/events not direct calls. Rising Ashes: equipment visuals (`equipment_visuals.gd`) should raise `hit_confirmed`, `swing_started` signals that VFX/audio/trail subscribe to, instead of `player.gd` calling VFX directly (it currently calls `VFX.*` and `Audio.*` inline in `_start_swing` and `_parry`). AI wander/attack: monster.gd has WANDER/ALERT/ATTACK/FOLLOW/YIELD; add DISENGAGE and GUARD states in the fighter model above.

## 5. Skills, gathering, crafting, inventory (Ryzom)

### How Ryzom does it
- **Skills tree by use**: skills are leaves in a tree (`skills.cpp`); use grants XP to that skill and its parent chain; level caps by tree branch ("progression" by actually doing). Actions are gated by *skill level vs action level*, difference modifies success (`deltaLvl = skillLevel - itemQuality` in `faber_phrase`).
- **Forage (gathering) is a mini-session** (`forage_progress`, `forage_phrase`): find deposit by prospecting (`fg_prospection_phrase`), spawn a *source* at a spot (`harvest_source.cpp`) with its own property vector and quantity, extract in repeated actions that spend focus, "care" actions that stabilise the source against random bad events (explosion/toxic), result computed from the session and then taken as raw materials. The deposit's total quantity is consumed (`_ForageSite->consume`), sources expire and the site regrows.
- **Raw materials have properties** (vectors of stats per material; quality per property). Crafting a plan sums required property ranges: materials aren't just "iron x3", they're quality-bearing. `getFillFaberRms` checks inputs; success rate depends on skill delta and plan quality; result quality derives from material quality and skill; failures partially consume materials.
- **Crafting action** uses phrase lifecycle with duration, tool requirement (crafting tool type), and optional bricks to push quality or success.
- **Inventory**: containers by slot (bag, pack animal, room, guild), item stack with quality and wear; equipment slots by body part; armour absorbs by location (`applyArmorProtections`), shield effective only if used; locations also take special effects.
- **Missions** (`mission_desc`, `mission_manager`): data rows of steps with events (kill, item, talk, enter area), actions (give item/xp/fame), preconditions; separate runtime step state per player persisted in `mission_pd`.
- **Death penalties** (`death_penalties`): small structured loss (skill XP debt), not item loss.

### Compared with our code
`crafting.gd`: 687 recipes with skill, stations, tools, `roll_quality(lvl, recipe_level)`, `add_xp`, salvage, tool bonus, station scan of interiors. `progression.gd`: activity XP with repetition decay (`repetition_factor`), attributes. `gathering_items.gd`: hunting/fishing/forage tables. `items_db.gd`: 1,200 items.

Gaps (ranked in section 7): (1) gather is a roll, not a skill-gated session with a risk/care choice; (2) deposits do not deplete or regrow persistently; (3) materials have a single quality int, not property vectors; fine for mobile but quality of inputs should feed output quality; (4) failure consumes nothing (no tension); (5) skill delta vs recipe level should modify success rate and crit-quality, we have only `roll_quality`; (6) no skill-tree parent-chain XP so training sword also trains "martial" parent; (7) no death-penalty structure; (8) mission data schema missing.

### Design: RPG economy upgrades
- `GatherSession` (RefCounted): `start(deposit_id, skill)`, `extract()` x N (tap), `care()` (optional 1 tap that cancels the next hazard), `finish()` -> items. Hazard probability falls with skill delta. Deposits: `{qty, regrow_per_day, quality_range}` in overlay. Mobile UI: 3-6 taps, a single meter. Never exceed 10 s.
- Input quality: `craft()` takes mean input quality (`inv` stack quality) into `roll_quality` as a bonus (cap +/- 20%).
- Success: `chance = clamp(0.55 + 0.04*(skill - recipe_level) + tool_bonus, 0.35, 0.98)`; on fail return 50% materials, XP half.
- Skill parent XP: `add_xp(leaf)` also gives 25% to parent in `skills.gd`/`crafting.gd` skill table.
- Armour by location lite: `{head, torso, arms, legs}` multipliers on incoming hit height (high/mid/low lane) using the combat lane.
- Death: lose 5% of the current-level XP progress, never items; plus temporary "weak" debuff.
- Missions: row schema `{id, prereq:[ids], steps:[{event, target, count}], rewards:[...]}` evaluated by a realm module on events; per-player step state is the only saved part.

## 6. Mobile budgets (Snapdragon 8 Gen 1 class, 60 fps target)
- Combat logic total <= 0.5 ms/frame; AI think tier 0.25 s for <= 8 fighters, 1 s for the rest within 60 m, none beyond.
- Hit tests sampled (<= 3 per attack), no per-frame physics queries by dormant NPCs.
- EffectSet ticks 2 Hz; pooled VFX; max 6 simultaneous particle bursts.
- Save: delta overlays under 1 MB each, write < 20 ms on a worker thread, atomic rename.
- Gather/craft UI sessions: no per-frame allocations, tap input only.

## 7. Prioritised gap list vs our code
| # | Gap | Impact | Effort | Where |
|---|---|---|---|---|
| 1 | CombatAction resource + runner shared by player/NPC (windup/active/recovery, cancel windows) | very high | M | new scripts/combat/, refactor player.gd COMBO |
| 2 | CombatResolver with HIT/BLOCK/PARRY/GUARD_BREAK/CLASH + poise | very high | S | pure static, tests |
| 3 | Humanoid NPC fighter model (aggression, rank, reaction, feint) on top of tokens | high | M | monster.gd/wolf.gd share via archetype data |
| 4 | AbilityDef + AbilityRunner + EffectSet (families, stacking) split from technique_caster | high | L | technique_caster.gd, skills.gd |
| 5 | Chantless gate in data (ACADEMY_PLAN) enforced in `can_use` | high | S | power_paths.gd, skills.gd |
| 6 | Sect vs knight art flavour via CombatAction binding | medium | M | content |
| 7 | Persistent depletable deposits + GatherSession | medium | M | gathering_items.gd, region sites |
| 8 | Dirty-container save + atomic write + overlay-only saves | medium | M | save_manager.gd |
| 9 | Craft success/fail tension, input quality, skill-delta | medium | S | crafting.gd |
| 10 | Signals between weapon/character/VFX instead of inline VFX calls | low | S | player.gd |
| 11 | Mission schema module | medium | M | realm module |
| 12 | Headless fight-arena balance test (N seeded duels, assert win rates) | high | S | tests |

## 8. Implementation order
1 -> 2 -> 12 (test arena before content) -> 3 -> 5 -> 4 -> 9 -> 7 -> 8 -> 6 -> 11 -> 10.
