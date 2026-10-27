extends Node3D
## The Steward's Post: a Station near a settlement's centre that opens the
## Lord's Council (scripts/ui/lord_council.gd) once the player holds that
## village (scripts/sim/lordship.gd). One is placed for every settlement as
## it's built, in a small ring offset from the plaza centre (spawn_ring),
## the same way village_services.gd places its keepers -- it just answers
## "this isn't your seat" until the player actually is that village's lord.

const LordCouncil := preload("res://scripts/ui/lord_council.gd")

var hud: HUD
var _spawned: Dictionary = {}   # settlement id -> true


func setup(p_hud: HUD) -> void:
	hud = p_hud
	# READY_V1 C5: a camp of yours that grows into a village gets its own Steward's Post (reuse spawn_for), now and after a load
	var lord: Variant = _lordship()
	if lord != null:
		if not lord.village_changed.is_connected(_on_village):
			lord.village_changed.connect(_on_village)
		for idx: int in lord.held_settlements():
			if lord.is_founded_idx(idx):
				_spawn_founded(lord, idx)


## The hall of a founded village: a Steward's Post beside the camp centre.
func _spawn_founded(lord: Variant, idx: int) -> void:
	var pl: Dictionary = lord._place(idx)
	spawn_for({"id": idx, "pos": pl["pos"]})


func _on_village(idx: int) -> void:
	var lord: Variant = _lordship()
	if lord == null or not lord.is_founded_idx(idx) or not lord.is_lord_of(idx) or _spawned.has(idx):
		return
	_spawn_founded(lord, idx)
	if hud != null:
		var name := String(lord.settlement_name(idx))
		preload("res://scripts/ui/life_event_popup.gd").present(hud, {"title": "Lord of %s" % name,
			"body": "Your camp has grown into a village, and its people look to you. The Steward's Post at %s is open: set the taxes, hear the matters of the day and start projects." % name,
			"choices": [["Take the seat.", Callable()]]})


## A ring of candidate spots around a settlement's centre, closest first, so
## the post can be offset from whatever else already stands at the plaza.
static func spawn_ring(center: Vector2, radius: float, count := 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in count:
		var ang := TAU * i / float(count) + 0.6
		out.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return out


## Places this settlement's Steward's Post (safe to call more than once).
func spawn_for(s: Dictionary) -> void:
	var sid := int(s["id"])
	if _spawned.has(sid):
		return
	_spawned[sid] = true
	var c: Vector2 = s["pos"]
	var spot := spawn_ring(c, 5.5)[0]
	var st := Station.new("Steward", "Council", _menu.bind(sid))
	add_child(st)
	st.global_position = Vector3(spot.x, WorldGen.height(spot.x, spot.y), spot.y)
	var to := c - spot
	st.rotation.y = atan2(to.x, to.y)


func _lordship() -> Variant:
	return Life.get("lordship")


func _menu(sid: int) -> Dictionary:
	var lord: Variant = _lordship()
	var name := String(WorldGen.settlements[sid].get("name", "the village")) if sid < WorldGen.settlements.size() else "the village"
	if lord != null and lord.is_founded_idx(sid):
		name = String(lord.settlement_name(sid))
	if lord == null or not lord.is_lord_of(sid):
		return {"title": "Steward's Post", "body": "\"This isn't your seat to hold, my lord.\"", "options": []}
	var v: Dictionary = lord.village(sid)
	var body := "\"%s awaits your word, my lord. %d matters need deciding.\"" % [name, (v["issues"] as Array).size()]
	return {"title": "Steward's Post", "body": body, "options": [["Open the council", func() -> String:
		if hud and hud.has_method("close_menu"):
			hud.close_menu()
		LordCouncil.open_for(hud, sid)
		return ""]]}


