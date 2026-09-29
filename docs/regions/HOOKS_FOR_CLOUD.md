# Region 1 hooks: exact code for the cloud session (H1 and H2)

Scaffold is in (package L0): `kingdom/scripts/region1/`, tests `kingdom/tests/test_region1_scaffold.gd`, guide `kingdom/data/region1/README.md`.
Each hook is one small commit with the comment `# Region1 hook (docs/regions/REGION_1_PLAN.md)`. Merge origin first.

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
