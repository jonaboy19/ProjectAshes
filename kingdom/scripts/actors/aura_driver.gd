extends Node
## AR-1: thin node that owns the player's AuraState and feeds it from the input action. Attach with AuraDriver.attach(player)
## (PresenceLive does it once it finds the player). It publishes meta "aura_view" on the player every frame; PresenceLive hands that to
## Presence as the subject's facts, so Stim.AURA works with no further wiring. No animation or VFX here (Antigravity / Codex read
## `aura_view` and `state_name()`).

const AuraState := preload("res://scripts/sim/aura_state.gd")
const AuraInput := preload("res://scripts/sim/aura_input.gd")

var state: RefCounted = AuraState.new()
var _was_held := false


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
		p.set_meta("aura_view", state.subject_view())


func state_name() -> String:
	return state.state_name()
