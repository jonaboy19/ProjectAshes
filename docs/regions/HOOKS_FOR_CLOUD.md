# Region 1 hooks: exact code for the cloud session (H1 and H2)

Scaffold is in (package L0): `kingdom/scripts/region1/`, tests `kingdom/tests/test_region1_scaffold.gd`, guide `kingdom/data/region1/README.md`. H2 is implemented on Codex branch `gpt/living-world-integration`; review in draft PR #5 and do not duplicate it. H1 is not wired: `Main` does not instantiate `Region1Root`, and the module manifest is empty.
Re-read Claude's current work before applying remaining hooks; each change is additive and uses the comment `# Region1 hook (docs/regions/REGION_1_PLAN.md)`.

## H1: `kingdom/scripts/core/main.gd`, in `_ready`
Paste right after the `world.add_child(frontier)` / `Frontier.frontier_event.connect(...)` lines (any point after `world` exists and before the loading screen ends is fine; the node only reads the `WorldSim` autoload, so order does not matter):

```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	world.add_child(preload("res://scripts/region1/region1_root.gd").new())
```
Cost: one `Timer` (1 s) and nothing per frame. With no rows in `data/region1/modules.json` it does nothing.

## H2: `kingdom/autoload/life.gd`
In `snapshot()`, just before `if player and is_instance_valid(player):`:

```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	d["region1"] = Region1State.snapshot()
```

In `restore(d)`, just before `inventory_changed.emit()`:

```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	Region1State.restore(d.get("region1", {}))
```
Old saves without `region1` are fine (modules reset to defaults). `Region1State` is a global `class_name`; if the class cache is stale, open the editor once (or use `preload("res://scripts/region1/region1_state.gd")`).

## Save/load round-trip test for C-H
Add to a Life test (or a new `tests/test_region1_hooks.gd`):

```gdscript
func test_life_snapshot_keeps_region1_block() -> void:
	var State := preload("res://scripts/region1/region1_state.gd")
	var Demo := preload("res://scripts/region1/demo_sim.gd")
	State.clear()
	var s := Demo.new().setup(5) as Region1Sim
	for i in 10: s.tick(0.5)
	State.register_sim(s)
	var before := s.digest()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Life.snapshot()))
	assert_bool(snap.has("region1")).is_true()
	s.tick(3.0)   # diverge
	Life.restore(snap)
	assert_str(s.digest()).is_equal(before)
	State.clear()
```
(The pure registry round trip already passes in `test_region1_scaffold.gd`.)

## Later hooks (H3 to H7)
Unchanged from the plan. Sims will expose plain functions/Callables for them; each package adds its exact snippet to this file when it lands.

---

# L10 Ember Legacy and L11 Ashsight: hooks (H7, C5, C6)

Files: `kingdom/scripts/region1/ember_legacy.gd` (`EmberLegacy`), `ash_memory.gd` (`AshMemory`), `ash_replay_view.gd` (`AshReplayView`), `ash_ghost_pool.gd`, `ash_ghost.gd`, `scenes/region1/ash_ghost.tscn`, data `data/region1/ember_legacy.json`. Tests: `tests/test_region1_ember_legacy.gd`, `tests/test_region1_ash_memory.gd`. Sandbox: `tools_qa/region1/ashsight_demo.tscn`.
Class cache: open the editor once (or run `--import`) so `EmberLegacy`, `AshMemory`, `AshFakeRaid`, `AshGhost*`, `AshReplayView` are known.

## Manifest rows (`kingdom/data/region1/modules.json`, in the `modules` array)
```json
{"name": "ember_legacy", "script": "res://scripts/region1/ember_legacy.gd", "enabled": true},
{"name": "ash_memory",   "script": "res://scripts/region1/ash_memory.gd",   "enabled": true}
```
Both save through `Region1State` (H2), so heirlooms, ancestor stones, and recorded ashes persist. Cooling of the ashes runs from the root's normal tick (`dt` in game days).

## H7: `scripts/sim/family.gd`, in `succeed_to()`, right before `# Archive the outgoing life before anything else changes.`
(4 lines; `Life.echoes` and `Life.mastery` are read before the heir replaces the life, so the summary is complete.)

```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	const EmberLegacy := preload("res://scripts/region1/ember_legacy.gd")   # move next to the other consts
	EmberLegacy.emit_life_ended(Life.biography, Life.echoes, old_name, old_age, family_name, WorldSim.day,
		{"place": String(home_settlement), "mastery": Life.mastery.xp, "tendencies": Life.tendencies.values})
```
It files an ember (returns its id, or -1 when the module is not running) and emits the sim's `life_ended(summary)` signal. Old-age death without an heir ("the story ends") should call the same line from `death_screen.gd`.

Then the choice UI (L13's 3-card radial or a stub) calls, on the live sim `Region1State.sim(&"ember_legacy")`:
```gdscript
var el := Region1State.sim(&"ember_legacy") as EmberLegacy
var cards := el.choices_for(ember_id)            # [{choice, title, text}] x3
# player picked:
el.choose_runestone(ember_id, stone_id, stone_name)   # then el.apply_to_network(Frontier.runestones)
el.choose_heirloom(ember_id)                          # {heirloom}; give the item with el.heirloom_item(id)
var b := el.choose_heir(ember_id)                     # then, AFTER succeed_to(): el.apply_blessing(b, Life.echoes, WorldSim.day, Life.mastery)
el.on_succession()                                    # after the heir takes over: heirlooms level up
```
(`apply_blessing` adds one Echo to `Life.echoes` and a skill trace to `Life.mastery.xp`; it is idempotent.)

## C5 additions (ancestor barks and power)
- After loading a save or creating road stones: `el.apply_to_network(<RARunestoneNetwork instance>)`. It grows `radius`, lifts `power`/`condition` and tags the stone dict with `ancestor` and `ancestor_bonus`, all through fields the existing `coverage()`/`strength()` already read. Idempotent.
- On interact with a stone: `if el.is_ancestor_stone(s["id"]): Game.say(el.bark(s["id"], EmberLegacy.situation_for({"pack": pack_near, "raid": raid_near}, float(s["condition"]), has_rumour), {"heir": Life.life_path.full_name(), "place": place_name}))`. `el.card(id)` is the biography card for the tap UI. Map: gold marker for stones where `s.has("ancestor")`.

## C6: event emitters for Ashsight (all no-ops when the module is not running)
Flag the sites once (after stones exist, and whenever a farm or ambush spot is created):
```gdscript
# Region1 hook (docs/regions/REGION_1_PLAN.md), e.g. in Frontier after seed_road_stones()
for s in runestones.stones:
	AshMemory.flag_site_static(String(s["name"]), s["pos"])
```
1. **Raids:** `scripts/world/road_events.gd`, at the end of `_spawn_ambush()` (2 lines) and in `_process` timer branch (1 Hz already: `CHECK_INTERVAL`), plus the end in `_cleanup()`:
```gdscript
	# in _spawn_ambush(), after _active.append(...)
	_active[_active.size() - 1]["ash_id"] = AshMemory.open(&"raid", Vector2(base.x, base.z))   # Region1 hook
	# in _process(), inside the 1 Hz block, for each a in _active with a["ash_id"] >= 0:
	var actors := []
	for s in (a["squad"] as Squad).soldiers:
		if is_instance_valid(s): actors.append({"id": s.get_instance_id(), "role": "bandit", "pos": Vector2(s.global_position.x, s.global_position.z)})
	actors.append({"id": "player", "role": "villager", "pos": Vector2(focus.x, focus.z)})
	AshMemory.sample_now(actors)                                                                 # Region1 hook
	# in _cleanup(), when an ambush ends:
	AshMemory.close(int(a.get("ash_id", -1)))                                                    # Region1 hook
```
   (`sample_now` keeps its own 1 Hz gate and only records actors within 60 m of the incident, so calling it from every timer tick is fine.)
2. **Sabotage:** wherever a stone is sabotaged or drained (`RARunestoneNetwork.damage(stone_id, amount, drain_power)` when `drain_power > 0`, or the Ashen Hand's job): `AshMemory.report(&"sabotage", s["pos"], AshMemory.clock(), [saboteur_actor])`. For a long chisel scene use `open(&"sabotage", pos)` + `sample_now` + `close` like a raid.
3. **Monster attacks and fires:** `monster_ecology.gd` `_log_event` (livestock loss, apex arrival): `AshMemory.report(&"raid", ev_pos, AshMemory.clock())` when the event has a position. Burning buildings or the Scar burn-back: `AshMemory.report(&"fire", pos, AshMemory.clock())`.
4. **Deaths:** where a villager, soldier or the player dies: `AshMemory.report(&"death", Vector2(p.x, p.z), AshMemory.clock(), [{"id": name, "role": "villager", "pos": Vector2(p.x, p.z)}])`.
5. **Kneel at a site (interact):**
```gdscript
var mem := Region1State.sim(&"ash_memory") as AshMemory
var ids := mem.incidents_near(Vector2(player.x, player.z), 40.0)   # hottest first, only readable ones
if ids.is_empty(): Game.say("The ashes here are cold.")
else: replay_view.show_incident(mem, ids[0])                       # AshReplayView added under the world
```
   Read `replay_view.grade` (0..1) each frame to drain the screen to grey (environment saturation), `replay_view.cursor.seek(t)` for the scrub bar, `mem.trail(id, actor_id)` for the ember-trail footsteps and compass pin, `replay_view.pick(ray_origin, ray_dir)` to tap a ghost. `replay_view.ground = func(p: Vector2) -> float: return WorldGen.height(p.x, p.y)` puts ghosts on the terrain. `AshGhost.set_model(node)` swaps the placeholder body for a UAL character or impostor.
## C6b: Ashsight look upgrade (real humanoid ghosts, world grade, camera pull-in, scrub bar)
One node does the whole moment. Replace the bare `replay_view.show_incident(...)` call above with:
```gdscript
# once, when the world is built (any node under the 3D world; needs the game's Camera3D)
var ash := AshsightController.new()
world.add_child(ash)
ash.setup(main_camera, world_env.environment, func(p: Vector2) -> float: return WorldGen.height(p.x, p.y))   # env + ground are optional
ash.warm()        # optional, awaitable: builds the 8 ghost bodies one per frame (call at Region 1 load, not at first kneel)
# kneel at a site (replaces replay_view.show_incident):
var ids := mem.incidents_near(Vector2(player.x, player.z), 40.0)
if ids.is_empty(): Game.say("The ashes here are cold.")
else: ash.show_incident(mem, ids[0])
```
- **Camera:** while `ash.active` (and until `ash.cam_rig.active` is false again, about 1 s after it ends) do NOT write the camera's transform: a PhantomCameraHost on the camera blends to an Ashsight pcam (soft pull-in that frames the ghosts) and back to a copy of the player's view. Without the addon it falls back to a damped move.
- **Grade:** `AshsightGrade` is one full-screen pass (drawn before the ghosts, so they keep their colours): desaturate + warm + vignette + drifting ash flakes, only while replaying. LOW tier has no pass (only the bound Environment's saturation) and fewer motes. Tier comes from `Quality.tier` (LOW / MEDIUM / HIGH+); force it with `ash.detail = 0..2`.
- **HUD:** `AshsightHud` (in a CanvasLayer 20): title, caption of the current beat, scrub bar (drag, beat ticks), play/pause, slow motion 1x/0.5x/0.25x (`ash.cycle_slow_motion()`), close. `show_hud = false` if the game draws its own.
- **Ghost animation beats** (new, optional): besides paths, emitters can record per-actor beats that the ghosts play as real clips at the recorded instant:
```gdscript
mem.act(incident_id, AshMemory.clock(), actor_id, &"attack")   # the instant the blow lands; also &"hit", &"death", &"chisel"
```
  (`road_events.gd` when a bandit attacks / a soldier is hit; `death` where a villager or soldier dies; `chisel` for the saboteur.) Ghost bodies: bandits use `ARMORED/bandit`, villagers MakeHuman villagers, all with `Assets`' UAL clip library; clip choices are data in `ash_ghost_clips.gd`.
- **Sandbox:** `tools_qa/region1/ashsight_farm.tscn` (burned farm, 4 bandits + 2 villagers): `-- --check`, `-- --bench`, `-- --tier=low|med|high`, `-- --gallery`. Frame sheets: `docs/regions/ashsight/`.

## H3: coverage override for Wardlines (package L7)
`Wardlines.coverage_at(p)` is a drop-in for `RARunestoneNetwork.coverage(p)` (same 0..1 falloff). Every consumer (`RAThreatMap.evaluate`, `ecology.tick_day(runestones.coverage, ...)`, the Frontier spawn loops) already goes through `runestones.coverage`, so the smallest hook is inside that one function, `kingdom/scripts/sim/runestone_network.gd` (4 lines):

```gdscript
## Region1 hook (docs/regions/REGION_1_PLAN.md): Wardlines takes over coverage when set.
var coverage_override: Callable = Callable()

func coverage(p: Vector2) -> float:
	if coverage_override.is_valid():   # Region1 hook
		return coverage_override.call(p)
	... (existing body)
```
Wiring (package C3, in `main.gd` next to hook H1 or in `Frontier._ready` after `_seed_frontier()`; keep it guarded so old saves work):
```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md)
	var wl := Region1State.sim(&"wardlines") as Wardlines
	if wl:
		if wl.layout_source != "network":        # a loaded save already carries its own layout
			wl.bind_network(Frontier.runestones)  # stone id = network id; picks 5 Elder Stones (or pass ids)
		Frontier.runestones.coverage_override = wl.coverage_callable()
```
and add the row `{"name": "wardlines", "script": "res://scripts/region1/wardlines.gd", "enabled": true}` to `data/region1/modules.json`. While the override is on, do not call `runestones.tick_day` decay for wear (Wardlines owns wear); if you still want the old "X is failing" events, call `wl.push_to_network(Frontier.runestones)` once a day. Rumours: `wl.rumours()` has the same voice as `RARunestoneNetwork.rumours()`; every change also arrives as a `Region1Sim.event` (`road_rumour`, `road_clear`, `stone_dark`, `stone_lit`, `link_cut`, `glyph_carved`, `alarm`, `elder_strained`) with a ready `data.rumour` string.
Player-facing calls for C3/L13: `carve(stone_id, "ward"|"lure"|"alarm"|"bless"|"none")`, `add_link(a, b)`, `cut_link(a, b)`, `mend_link`, `set_pinned`, `repair`, `notify_threat(pos)` (alarm stones), `bless_at(pos)` (crop yield multiplier), `lure_points()` (for the ecology), `pressure(pos, r, amount)` (Scar Tide), `elder_status()`, `budget_report()`.
The recognizer for the carve canvas: `RuneGesture.new().recognize(strokes)` returns `{glyph, score, accepted, ...}`; pass `glyph` to `carve`.

## C8: onboarding with the tutorial director (package L16)
Files: `scripts/region1/tutorial_director.gd` (pure rules, 12 prompts), `tutorial_prompt_view.gd` (draws a prompt on the HUD), `tutorial_game_bridge.gd` (reads the running game and places the prompts). Prompt text lives in `locale/strings.csv` (`TUT_*`, en and nl). The demo sheet is `docs/regions/tutorial_demo_sheet.jpg`, and the sandbox is `tools_qa/region1/tutorial_sandbox.tscn`.

**Hook (3 lines), `kingdom/scripts/core/main.gd` `_ready`**, anywhere after `hud` and `player` exist (for example right after H1):
```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md) C8: contextual tutorial prompts
	var tutorial := Region1TutorialBridge.new()
	add_child(tutorial)
	tutorial.setup(player, hud)
```
That is all that's needed for move, look, talk, interact, eat, sleep, fight, block, dodge and map. The bridge:
- polls the input actions (the HUD's TouchScreenButtons press the same ones);
- watches `Life.needs` food and rest going up, the camera yaw and the player's velocity;
- finds enemies in group `team1`; wind-up is read from `is_winding_up()` if an enemy has it, else from `wolf.gd`'s `_winding` (X4: please add `is_winding_up()` to humanoids);
- blocks prompts while `hud.is_menu_open()`, the tree is paused, or a `cutscene_active` player is playing;
- saves through `Region1State` (key `tutorial`, rides on H2).

**The rest of the prompts** come from other packages. Each is one line:
```gdscript
Region1TutorialDirector.tell(&"carve")      # C3/L13: the runecarve canvas accepted a glyph
Region1TutorialDirector.tell(&"ashsight")   # C6: the player held Ashsight at a site
Region1TutorialDirector.tell(&"map")        # the Map tab opened (the Tab key already counts)
```
Context providers tell the bridge when those prompts are relevant (each is a `Callable(player_pos: Vector3) -> bool`):
```gdscript
tutorial.providers["near_dim_stone"] = func(p: Vector3) -> bool:   # C3
	var id := wl.nearest_stone(Vector2(p.x, p.z), 6.0)
	return id >= 0 and wl.stone_band(id) < Wardlines.BAND_GLOWING
tutorial.providers["knows_glyph"]   = func(_p: Vector3) -> bool: return story.has_flag("r1.a1.taught")                    # C7
tutorial.providers["near_ash_site"] = func(p: Vector3) -> bool: return ash_memory.has_site_near(p, 8.0)                  # C6 (L11 API)
tutorial.providers["new_marker"]    = func(_p: Vector3) -> bool: return quest_marker_unseen                              # C7
```
**Settings and menu:**
- Settings toggle "Tutorial tips" (`TUT_TIPS`): `tutorial.director.set_enabled(on)`.
- Game menu "Show all tips again" (`TUT_REPLAY_ALL`): `tutorial.director.replay_all()`.
- Replay a single tip (`TUT_REPLAY`): `tutorial.director.replay(&"block")`.
- The small x on a prompt skips it (`TUT_SKIP`).

**First 20 minutes (C8 flow):** birth → childhood → at age 8, quest step `a1_dark_stone` (C7 wiring below) → the Miller's Stone (`carve` prompt, first glyph, story flag `r1.a1.first_glyph` = the metric) → `a1_hesks_ember` emits `["spawn", "wolf", "ashford_ring", 1]`. That is the safe first fight: one lone wolf at dusk at the ring edge, which the fight, block and dodge prompts teach against. Make that wolf non-lethal (knockdown, not death) until `a1_wolf_at_dusk` is done.

## C7: story quest runtime (package L14)
Runtime: `scripts/region1/story_quest.gd` (`Region1StoryQuest extends Region1Sim`). Data: `data/region1/quests/r1_main.json` (schema in `data/region1/quests/README.md`). Story and cutscene beats: `docs/regions/STORY_R1.md`.

**Create and save** (next to H1, or as a manifest row once C7 wires the events). Loading happens in code because the quest needs its data file:
```gdscript
	# Region1 hook (docs/regions/REGION_1_PLAN.md) C7: main quest
	var story := Region1StoryQuest.new()
	story.setup(WorldSim.SEED)
	story.load_quest("res://data/region1/quests/r1_main.json")
	Region1State.register_sim(story)   # saves under "story_quest"; Region1Root ticks it (no-op)
```
**Context** for every call: `{"age": Life.age, "flags": <life_path flags as {name: true}>, "items": <inventory counts>, "vars": {"family": ..., "stone_name": ...}}`. Call `story.refresh(ctx)` once a second (Region1Root's tick is fine) and after loading.

**Events to feed** (from existing emitters; each is one line where the thing happens). `notify(type, params, ctx)`:
| When | Call |
|---|---|
| Player enters a registry place (C1 radius) | `story.notify(&"enter_area", {"place": id}, ctx)` |
| Kill (`wolf.gd`, `monster.gd`, X4 bandits) | `story.notify(&"kill", {"target": kind, "place": nearest_place_id, "amount": 1}, ctx)` |
| Boss or trial beaten | `story.notify(&"defeat", {"target": "antlered_warden"}, ctx)` |
| Wardlines `glyph_carved` event | `story.notify(&"carve", {"glyph": d.glyph, "stone": story_stone_id(d.id)}, ctx)` (map the network id to the registry stone by place) |
| Wardlines `link_made` | `story.notify(&"wardline_link", {"from": story_stone_id(d.a), "to": place_or_stone(d.b)}, ctx)` |
| Wardlines Elder Stone lit (`elder_calm` after a relight, or a `stone_lit` on an elder id) | `story.notify(&"relight_elder", {"stone": "elder_glade"}, ctx)` |
| Scar Tide cells contained or harvested (L9/C4) | `story.notify(&"scar_contain", {"place": id, "amount": cells}, ctx)` and `&"scar_harvest"` |
| Ashsight used at a site (C6) | `story.notify(&"ashsight", {"site": place_id}, ctx)` |
| Ember choice radial (C5/L13) | `story.notify(&"ember_choice", {"who": "rowan", "choice": "stone"}, ctx)` (choice: stone, heir or heirloom) |
| Cutscene finished (C9) | `story.notify(&"cutscene_done", {"cutscene": id}, ctx)` |

**Conversations:**
- `story.dialogue_entries(step_id)` → `[{file, node, speaker}]` lists what the step's giver offers now.
- Show them with `DialogueRunner.load_file(file, "res://data/region1/dialogue")`, passing `story.condition_ctx(ctx)` as the runner ctx.
- Hand each shown line's and chosen option's `do` to `story.apply_dialogue_actions(do, ctx, step_id)`.
- Call `story.notify(&"talk", {"node": node}, ctx)` for every node shown.

**Returned events:**
- `step_started` / `step_completed`: tracker pin, Journal and toasts.
- `action` events for you to apply:
  - `give` → `Life` inventory
  - `rep` → reputation
  - `gold`
  - `cutscene` → C9
  - `marker` → compass
  - `spawn` → Frontier
  - `tutorial` → `tutorial.director.replay(id)`
- `quest_completed`: the Region 1 complete card.

Tracker text is `story.step(id)["objective"]`; the Journal uses `title` and `journal`.

**Story v2 additions** (`docs/regions/EMOTION_MAP_R1.md`):

| What | Where | Wire it to |
|---|---|---|
| `staging` on every step | `r1_main.json` | On `step_started`, C12 switches the bed to `staging.music` (use the registry `music` fallback for missing cues; `silence` means fade the bed out). C9 and Codex read `camera`, `anim`, `vfx` and `needs` as the brief. |
| Kindling Night festival objective | `a1_kindling` (childhood, while the years pass to 12) | `story.notify(&"festival", {"festival": "kindling_night"}, ctx)` from `seasons.gd` festival start. The Act III Kindling (`a3_kindling_return`) is story-lit "early, for Idra" and only needs `enter_area ashford_ring`; stage it at night with lanterns whatever the calendar says. |
| `spawn` of `stagborn_fawn` at the ring (with the wolf) | `a1_hesks_ember` | Frontier; the wolf targets the fawn. The fawn is not a kill target. |
| `give` of `maren_staff` | `a4_dark_night` | inventory (new item in the registry `new_items`) |
| Ashsight sites `miller_stone` and `ashford_ring` | Act III | the same C6 call as the Pennick farm |
| Flags for other systems | throughout | `r1.a1.wren_joined` (retinue: Wren follows), `r1.a4.wren_left` / `r1.a4.wren_back` (Wren leaves and rejoins), `r1.thistle.freed` / `r1.thistle.kept` (Thistle with the herd, or with you), `r1.a3.maren_gone`, `r1.ending.*` (achievements) |

**Test:** `Godot --headless --path kingdom -s res://tools_qa/region1/lint_quests.gd` must stay at 0 errors. `tests/test_region1_story.gd` shows the calls step by step.


## H6: parchment map layer (`add_layer` for `ui/world_map.gd`)
Painted Region 1 map (sepia ink on parchment, poster style) drawn under the map's own icons, plus a painterly, toggleable fog of war.

**New files (all in this commit):**
- `kingdom/scripts/ui/map_parchment_layer.gd`, the layer. No `class_name`; `preload` it.
- `kingdom/assets/ui/maps/region1_parchment.png` (2048 px, opaque) and its `.import` (`compress/mode=2`, `high_quality=false`, mipmaps on = **ETC2 on mobile, 2.8 MB measured** on disk; budget was 4 MB).
- `kingdom/assets/ui/maps/region1_parchment.json`: the world to map transform, the alias table (Oakvale = Greenhollow, Highcliff = Highwatch Keep), and every drawn feature (`name`, `id_name`, `pos_m`, `pos_px`).
- Tools (re-run any time WorldGen changes): `tools_qa/map/dump_world.gd` (samples the real WorldGen, seed 1066), `paint_parchment.tscn/.gd`, `parchment_ink.gd`, `parchment_paper.gdshader`, `run_paint.sh`.

**Transform:** `px = (margin, margin) + (world - world_min) * px_per_m`, margin 88 px, `px_per_m` 0.2285 (4.38 m per pixel), world = (x, z), north = -z = up. The terrain rect is 1872 px = the whole 8 x 8 km region; the parchment frame extends 385 m past it.

**Hook in `scripts/ui/world_map.gd` (about 30 lines, all additive; tested in a scratch copy, not committed):**
```diff
@@ -151,6 +151,9 @@ var _card_info: Label
 var _travel_btn: Button
 var _loading: Label
 var _legend_btn: Button
+var _layers: Array[Control] = []          # H6: painted layers (map_parchment_layer.gd)
+var _layered := false
+var _bake_labels := false
 
 
 func _ready() -> void:
@@ -1032,17 +1035,21 @@ func _draw() -> void:
 	_draw_neighbours()
 	var h := WorldGen.WORLD_HALF
 	var world_rect := Rect2(to_screen(Vector2(-h, -h)), Vector2(h, h) * 2.0 * _zoom)
-	if _texture:
+	_layered = _paint_layers()
+	if _layered:
+		pass
+	elif _texture:
 		draw_texture_rect(_texture, world_rect, false)
 		if _paper:
 			draw_texture_rect(_paper, world_rect, false, Color(1, 1, 1, 0.1))
 	else:
 		draw_rect(world_rect, Color("b9c98a"))
-	_draw_border()
-	_draw_rivers()
-	_draw_roads()
+	if not _layered:
+		_draw_border()
+		_draw_rivers()
+		_draw_roads()
 	_draw_runestones()
-	if _fog_texture:
+	if _fog_texture and not _layered:
 		var rr := _region_rect()
 		draw_texture_rect(_fog_texture, Rect2(to_screen(rr.position), rr.size * _zoom), false)
 	_draw_places()
@@ -1067,6 +1074,25 @@ func _draw() -> void:
 		_draw_legend()
 
 
+## H6: adds a painted layer (scripts/ui/map_parchment_layer.gd). It paints under the icons via paint_under(self).
+func add_layer(l: Control) -> void:
+	_layers.append(l)
+	add_child(l)
+	if l.has_method("bind_map"):
+		l.call("bind_map", self)
+	queue_redraw()
+
+
+func _paint_layers() -> bool:
+	var done := false
+	_bake_labels = false
+	for l in _layers:
+		if l.visible and l.has_method("paint_under") and bool(l.call("paint_under", self)):
+			done = true
+			_bake_labels = _bake_labels or bool(l.get("bakes_labels"))
+	return done
+
+
 func _heading() -> float:
 	if player and is_instance_valid(player):
 		var cam: Variant = player.get("camera")
@@ -1219,6 +1245,8 @@ func _draw_places() -> void:
 		var c := to_screen(pl["pos"])
 		if not view.has_point(c) or not _passes(pl):
 			continue
+		if _bake_labels and not (not _selected.is_empty() and _selected["id"] == pl["id"]):
+			continue      # the parchment carries the names
 		var sel: bool = not _selected.is_empty() and _selected["id"] == pl["id"]
 		if is_area(kind):
 			_draw_area_label(pl, c, used)
```
(The three `@@` hunks above are: member vars, `_draw()` plus `add_layer()` / `_paint_layers()`, and the name-label skip in `_draw_places()`.)

**Wire it once** (C3, after the HUD builds the map: `hud.gd` right after `add_child(world_map)`):
```gdscript
var parchment := preload("res://scripts/ui/map_parchment_layer.gd").new()
world_map.add_layer(parchment)
world_map.closed.connect(parchment.release)      # frees the texture (VRAM) while the map is closed
```
**Toggles:** `parchment.fog_enabled = false` (show the whole painted map), `parchment.toggle_fog()`, `parchment.enabled = false` (the map draws its own terrain again),
`parchment.fog_strength`. Suggested UI: a "Fog" chip in the Map tab filter list (`tab_map.gd`) calling `toggle_fog()`.
**Discovered areas:** the layer reads the map's own `_fog_img` (the discovery field, 128 px over the region) and turns it into a 256 px painted mist (256 KB), rebuilt only when the map rebuilds its fog.
**Labels:** the sheet carries the poster names, so while the layer is on the map skips its own name labels (`bakes_labels`, selected place excepted). Set `parchment.bakes_labels = false` to keep the map's labels.
**H3 / Wardlines:** draw coverage as a second `add_layer(Control)` with its own `paint_under(canvas)` (same contract: return false to leave terrain to the map, true to replace it) or, simpler, from `_draw_runestones()`.
**Memory:** one 2.8 MB VRAM texture + the 256 KB fog while open; `release()` drops both. Do not `load_threaded_request` it (project rule); a synchronous `load()` of the ctex takes a few ms.
**Known limits:** at zoom above about 0.5 px/m the sheet is soft (4.4 m per source pixel); the map's coin icons cover the small baked pictograms; ideas: shrink map icons while the layer is on, or add a
1024 px detail tile for the home valley. Poster places without a WorldGen site yet (Silverford at (-640, 480), the five Elder Stones, Crownstead) are drawn at the `wardlines.json` / plan positions and
listed under `proposed_places` / `elder_stones` in the json: C1 should move them when the sites exist.
