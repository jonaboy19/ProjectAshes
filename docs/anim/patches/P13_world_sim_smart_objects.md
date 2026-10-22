# P13c: world_sim.gd — smart objects as schedule targets (cloud, small hook)

This patch touches only `autoload/world_sim.gd`, which is a cloud hot file. It adds about 15 lines.
`SmartObjects` (`scripts/living_world/smart_objects.gd`) is pure data: one instance holds every activity spot of
every generated settlement. Types and building placement live in `data/living_world/smart_objects.json`.

```gdscript
# --- members
var smart: SmartObjects
var _smart_done: Dictionary = {}      # settlement id -> true once its spots exist

# --- _ready(), after _populate()
	smart = SmartObjects.new()

# --- reset(): add
	smart = SmartObjects.new()
	_smart_done.clear()

# --- _spot(s, which, i): at the top, for work (1) and market (2) targets of settlements near the player
	if which != 0 and smart != null:
		var sid := int(s["id"])
		if not _smart_done.has(sid):
			_smart_done[sid] = true
			smart.populate_settlement(s, WorldGen.height)          # once per settlement, ~0.2 ms for a town
		var act := "work" if which == 1 else "shop"
		var c: Vector2 = s["pos"]
		var t := smart.target_for(i, Vector3(c.x, 0, c.y), act, job[i] if i < job.size() else 4,
			time_of_day, float(s["radius"]) * 2.5)
		if t != Vector2.INF:
			return t
	# ... existing code unchanged (fallback when no free spot fits)
```

`target_for()` claims the slot for the resident, so a crowd spreads over the anvils, stalls and field rows instead
of stacking on one point. It also releases that resident's previous claim.

Release on the home phase:

```gdscript
# _on_phase_change(i, old, new_phase), first line:
	if smart and new_phase == 0:
		smart.release(i)
```

When the resident is embodied, `Villager` (P13a §5) uses the same claim. It runs `smart.session(person, spot, slot)` for
the approach, align, enter, loop and exit, so the data tier and the body agree on who stands at the anvil.

Cost: `find()` is a 16 m grid lookup over the spots in range, and only runs at phase changes.
