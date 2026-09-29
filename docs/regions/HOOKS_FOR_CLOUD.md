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
