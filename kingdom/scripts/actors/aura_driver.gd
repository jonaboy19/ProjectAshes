extends Node
## AR-1: thin node that owns the player's AuraState and feeds it from the input action. Attach with AuraDriver.attach(player)
## (PresenceLive does it once it finds the player). It publishes meta "aura_view" on the player every frame; PresenceLive hands that to
## Presence as the subject's facts, so Stim.AURA works with no further wiring. No animation or VFX here (Antigravity / Codex read
## `aura_view` and `state_name()`).

const AuraState := preload("res://scripts/sim/aura_state.gd")
const AuraInput := preload("res://scripts/sim/aura_input.gd")

var state: RefCounted = AuraState.new()
var _was_held := false
var _rep_t := 0.0
var _rep_graphs: Array = []   # StreetGraphs that currently carry a repulsion field from us


static func attach(player: Node) -> Node:
	var d := player.get_node_or_null("AuraDriver")
	if d != null:
		return d
	var n: Node = (load("res://scripts/actors/aura_driver.gd") as GDScript).new()
	n.name = "AuraDriver"
	player.add_child(n)
	return n


func _ready() -> void:
	AuraInput.ensure_actions()
	state.seed_value = WorldSim.SEED
	var life := get_node_or_null("/root/Life")
	if life != null and life.get("soul") != null:
		state.set_power_from_tier(int(life.soul.tier()))


func flare(technique_power: float) -> void:
	state.flare(technique_power)


func _physics_process(dt: float) -> void:
	var held := AuraInput.held()
	if held and not _was_held and state.holding:
		state.surge()
	state.update(dt, held, {"day": WorldSim.day})
	if AuraInput.rein_pressed():
		state.rein_in()
	_was_held = held
	var p := get_parent()
	if p != null:
		var view: Dictionary = state.subject_view()
		p.set_meta("aura_view", view)
		_rep_t += dt
		if _rep_t >= 0.5:
			_rep_t = 0.0
			_update_repulsion(p, view)


func state_name() -> String:
	return state.state_name()


## AR-4: every 0.5 s hand the near-tier settlement's street graph the repulsion field (cleared when the aura ends or the player leaves).
func _update_repulsion(p: Node, view: Dictionary) -> void:
	var emit := float(view.get("aura_emit", 0.0)) - float(view.get("aura_suppress", 0.0))
	var reach := float(view.get("reach_m", 0.0))
	var now := Time.get_ticks_msec() / 1000.0
	if emit < 0.05 or not (p is Node3D):
		for g: RefCounted in _rep_graphs:
			g.clear_repulsion()
		_rep_graphs.clear()
		return
	var pos3: Vector3 = (p as Node3D).global_position
	var src := Vector2(pos3.x, pos3.z)
	var keep: Array = []
	for i in WorldGen.settlements.size():
		var s: Dictionary = WorldGen.settlements[i]
		var c: Vector2 = s["pos"]
		if c.distance_to(src) > float(s.get("radius", 60.0)) + reach * 0.5:
			continue
		var g: RefCounted = (load("res://scripts/population/street_graph.gd") as GDScript).call("for_settlement", i)
		if g != null and g.set_repulsion(src, reach, emit, now):
			keep.append(g)
	for g2: RefCounted in _rep_graphs:
		if not (g2 in keep):
			g2.clear_repulsion()
	_rep_graphs = keep
