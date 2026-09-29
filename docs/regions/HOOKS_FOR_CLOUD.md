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
