class_name InteriorRoom
extends Node3D
## Root script of the generated interior scenes (scenes/interiors/*_interior.tscn).
## - Flickers the OmniLights tagged metadata/flicker = true (hearth, forge).
## - Optionally spawns the NPCs at the markers under "NPCs" (Marker3D with
##   metadata look / height / anim / role), using Assets.character() when that
##   API exists. Turn `spawn_npcs` off to place your own villagers or stations
##   at the markers instead (see scenes/interiors/README.md).
## The scene also runs standalone (F6 in the editor): it keeps its preview camera
## and WorldEnvironment unless an InteriorDoor embedded it.

signal npcs_spawned(npcs: Array)

@export var spawn_npcs := true
@export var flicker := true

var npcs: Array[Node3D] = []
var _lights: Array = []    # [light, base_energy, phase]
var _t := 0.0


func _ready() -> void:
	for l in find_children("*", "OmniLight3D", true, false):
		if bool(l.get_meta("flicker", false)):
			_lights.append([l, (l as OmniLight3D).light_energy, randf() * TAU])
	set_process(flicker and not _lights.is_empty())
	if spawn_npcs:
		_spawn_npcs.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	for e: Array in _lights:
		var ph: float = e[2]
		var k := 1.0 + 0.07 * sin(_t * 7.3 + ph) + 0.05 * sin(_t * 13.7 + ph * 2.1) + 0.03 * sin(_t * 23.0 + ph)
		(e[0] as OmniLight3D).light_energy = float(e[1]) * k


## Marker3D nodes whose name starts with "NPC_" (under the NPCs node).
func npc_markers() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for m in find_children("NPC_*", "Marker3D", true, false):
		out.append(m as Marker3D)
	return out


func _spawn_npcs() -> void:
	var assets: GDScript = load("res://scripts/world/assets.gd") if ResourceLoader.exists("res://scripts/world/assets.gd") else null
	if assets == null:
		return
	for m in npc_markers():
		var look := String(m.get_meta("look", "Rogue_Hooded"))
		var height := float(m.get_meta("height", 1.75))
		var npc: Node3D = assets.call("character", look, height)
		if npc == null:
			continue
		npc.name = String(m.name).trim_prefix("NPC_")
		add_child(npc)
		# Character models face +Z; markers face -Z (Godot forward).
		npc.global_transform = Transform3D(m.global_basis.rotated(Vector3.UP, PI).orthonormalized(), m.global_position)
		npc.set_meta("role", m.get_meta("role", ""))
		npc.add_to_group("interior_npc")
		var ap: AnimationPlayer = assets.call("animation_player", npc)
		if ap:
			var want := String(m.get_meta("anim", "Idle"))
			for a in [want, "Idle"]:
				if ap.has_animation(a):
					ap.play(a)
					break
		npcs.append(npc)
	npcs_spawned.emit(npcs)
