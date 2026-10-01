extends InteriorDoor
## A cave mouth / dungeon door in the open world. Extends InteriorDoor so main.gd's existing
## interact handler (`target is InteriorDoor -> use()`), the HUD prompt, the camera handling, hiding
## of the exterior and the exit all work unchanged; the only difference is that the room is generated
## from a seed (dungeon_gen.gd) when you walk in and freed when you leave.

const Gen := preload("res://scripts/interiors/dungeon_gen.gd")
const Build := preload("res://scripts/interiors/dungeon_build.gd")

signal dungeon_entered(id: String)

var dungeon_id := ""
var seed_value := 0
var theme := "cave"
var tier := 1
var dname := "Cave"
var rooms := 0
var lead := ""              # hidden-site id that a journal found inside points at
var lvl_min := 1
var lvl_max := 10

static var _fallback_states: Dictionary = {}
static var _layout: Dictionary = {}


func configure(site: Dictionary) -> void:
	dungeon_id = String(site["dungeon_id"])
	seed_value = int(site["seed"])
	theme = String(site["theme"])
	tier = int(site["tier"])
	dname = String(site.get("name", "Cave"))
	rooms = int(site.get("rooms", 0))
	lead = String(site.get("lead", ""))
	var g := layout()
	lvl_min = int(g["level_min"])
	lvl_max = int(g["level_max"])
	prompt_text = "Enter %s  (Lv %d-%d)" % [dname, lvl_min, lvl_max]
	collision_layer = 0
	collision_mask = PLAYER_TRIGGER_LAYER
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.0, 2.4, 3.0)
	cs.shape = bx
	cs.position.y = 1.2
	add_child(cs)
	name = "CaveDoor_%s" % dungeon_id


## The layout for this door (cached for the last one built, so the prompt's level range is free).
func layout() -> Dictionary:
	if _layout.get("id", "") == dungeon_id:
		return _layout
	var opts := {"id": dungeon_id}
	if rooms > 0:
		opts["rooms"] = rooms
	_layout = Gen.generate(seed_value, theme, tier, opts)
	return _layout


func _can_enter() -> bool:
	return dungeon_id != ""


func _make_interior() -> Node3D:
	var g := layout()
	var state := state_for(dungeon_id)
	var life := get_node_or_null("/root/Life")
	var day := 1
	var ws := get_node_or_null("/root/WorldSim")
	if ws != null and ws.get("day") != null:
		day = int(ws.get("day"))
	state["visits"] = int(state.get("visits", 0)) + 1
	var root: Node3D = Build.build(g, state, {"day": day, "lead": lead, "exit_label": "Leave %s" % dname})
	var game := get_node_or_null("/root/Game")
	if game != null:
		game.call("say", "%s. Recommended level %d-%d. Some caves are dark: a torch helps." % [dname, lvl_min, lvl_max] if bool(g["dark"]) \
			else "%s. Recommended level %d-%d." % [dname, lvl_min, lvl_max])
	root.connect("lead_revealed", _on_lead)
	dungeon_entered.emit(dungeon_id)
	if life != null and life.get("realm") != null:
		var ex: Variant = life.realm.mod("exploration")
		if ex != null:
			ex.on_enter(dungeon_id, day)
	return root


## Persistent state for a dungeon: the realm module's dict when the game is running, else a static one.
static func state_for(id: String) -> Dictionary:
	var loop := Engine.get_main_loop() as SceneTree
	var life: Node = loop.root.get_node_or_null("/root/Life") if loop != null else null
	if life != null and life.get("realm") != null:
		var ex: Variant = life.realm.mod("exploration")
		if ex != null:
			return ex.state(id)
	if not _fallback_states.has(id):
		_fallback_states[id] = {}
	return _fallback_states[id]


func _on_lead(lead_id: String) -> void:
	var life := get_node_or_null("/root/Life")
	if life != null and life.get("realm") != null:
		var ex: Variant = life.realm.mod("exploration")
		if ex != null:
			ex.learn_lead(lead_id)
