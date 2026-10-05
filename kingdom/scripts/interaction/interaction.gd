class_name Interaction
extends RefCounted
## The one entry point from the world to the player's interact button: gathers every candidate (the
## "interactable" group, each through its Interactable component or legacy wrapper, plus registered providers),
## lets InteractionPicker choose, and runs the choice. Player.nearest_interactable(), the HUD label and the
## interact key all go through here, so what the button says is exactly what the key does.

const Picker := preload("res://scripts/interaction/interaction_picker.gd")

## Extra candidate sources: Callable(player_pos: Vector3, facing: Vector3) -> Array of candidate dictionaries.
## A provider candidate may carry `interact` (Callable(player)), `verb`, `target`, `hold_time` instead of `source`.
static var providers: Array[Callable] = []


## The running game's HUD / VillageServices (main.gd's `hud` and `services`), or null in a bare test scene.
static func hud(from: Node) -> Node:
	var scene := from.get_tree().current_scene if from != null and from.get_tree() != null else null
	var h: Variant = scene.get("hud") if scene else null
	return h as Node if h is Node and is_instance_valid(h) else null


static func services(from: Node) -> Object:
	var scene := from.get_tree().current_scene if from != null and from.get_tree() != null else null
	var sv: Variant = scene.get("services") if scene else null
	return sv as Object if sv is Object and is_instance_valid(sv) else null


static func add_provider(c: Callable) -> void:
	if not providers.has(c):
		providers.append(c)


static func remove_provider(c: Callable) -> void:
	providers.erase(c)


static func facing_of(player: Node3D) -> Vector3:
	if player.has_method("facing"):
		return player.call("facing")
	return -player.global_transform.basis.z


## The horse the player is riding, or null.
static func mounted_horse(player: Node) -> Node3D:
	var m: Variant = player.get("_mount")
	if m is Object and is_instance_valid(m):
		var h: Variant = (m as Object).get("horse")
		if h is Node3D and is_instance_valid(h):
			return h
	return null


## Every available candidate as picker dictionaries (group members only; providers are added by the picker).
static func candidates(player: Node3D) -> Array:
	var out: Array = []
	var tree := player.get_tree()
	if tree == null:
		return out
	for node in tree.get_nodes_in_group("interactable"):
		if node == player or not (node is Node3D) or not is_instance_valid(node):
			continue
		var c := Interactable.for_node(node)
		if c == null or not c.can_interact(player):
			continue
		out.append(c.candidate())
	var horse := mounted_horse(player)
	if horse != null:
		var hc := Interactable.for_node(horse)
		if hc != null:
			var cand := hc.candidate()
			cand["mount"] = true
			cand["range"] = 1.0e6
			cand["id"] = "mount"
			out.append(cand)
	return out


## The chosen candidate dictionary, {} when nothing is in reach.
static func best(player: Node3D) -> Dictionary:
	if player == null or not is_instance_valid(player):
		return {}
	var provs: Array = []
	provs.assign(providers)
	return Picker.pick(player.global_position, facing_of(player), candidates(player), provs, mounted_horse(player) != null)


## The host node of the chosen candidate (what Player.nearest_interactable() returns).
static func best_node(player: Node3D) -> Node3D:
	return node_of(best(player))


static func node_of(c: Dictionary) -> Node3D:
	var src: Variant = c.get("source", null)
	if src is Interactable and is_instance_valid(src):
		return (src as Interactable).host()
	var n: Variant = c.get("node", null)
	return n as Node3D if n is Node3D and is_instance_valid(n) else null


## {verb, target, text, icon} of a candidate for the HUD.
static func label_of(c: Dictionary) -> Dictionary:
	var src: Variant = c.get("source", null)
	if src is Interactable and is_instance_valid(src):
		return (src as Interactable).label()
	var IL := load("res://scripts/ui/interact_label.gd")
	return IL.call("pack", String(c.get("verb", "Use")), String(c.get("target", "")))


## Runs a candidate's action. Returns true when something ran.
static func run(c: Dictionary, player: Node3D) -> bool:
	if c.is_empty():
		return false
	var src: Variant = c.get("source", null)
	if src is Interactable and is_instance_valid(src):
		var comp := src as Interactable
		if not comp.can_interact(player):
			return false
		if bool(c.get("mount", false)) and mounted_horse(player) != null and player.has_method("toggle_mount"):
			player.call("toggle_mount")
			return true
		comp.interact(player)
		return true
	var fn: Variant = c.get("interact", null)
	if fn is Callable and (fn as Callable).is_valid():
		(fn as Callable).call(player)
		return true
	return false


## Picks and runs (a tap). The single place the interact action ends up.
static func activate(player: Node3D) -> bool:
	return run(best(player), player)
