extends RefCounted
## Guards carry lanterns at night (package F6). Each guard gets a small lantern prop (cage + emissive glass) on its
## hand; at night every lantern glows (an emissive mesh costs nothing) but only the MAX_LIT nearest to the focus point
## also carry a real OmniLight3D, because lights are what hurts on phones. A single driver node ticks at 4 Hz and picks
## the nearest set, so no guard runs per-frame code.
##
##   GuardLantern.attach(guard)                  # called by villager.gd for job 3
##   GuardLantern.night(hour) -> bool
##   GuardLantern.nearest(cands, n) -> Array     # pure: ids of the n closest of [{id, dist}]
##   GuardLantern.update(tree, focus, hour) -> int   # lights now on
##
## Preload this script; no class_name.

const MAX_LIT := 4
const GROUP := &"guard_lantern"
const DUSK := 19.0
const DAWN := 5.5
const LIGHT_RANGE := 7.0

static var _driver: Node = null
static var _mesh_body: BoxMesh
static var _mesh_glass: BoxMesh
static var _mat_body: StandardMaterial3D
static var _mat_glass: StandardMaterial3D


static func night(hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	return h >= DUSK or h < DAWN


## Ids of the `n` nearest candidates ({id, dist}), nearest first.
static func nearest(cands: Array, n: int) -> Array:
	var sorted := cands.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	var out: Array = []
	for i in mini(n, sorted.size()):
		out.append((sorted[i] as Dictionary)["id"])
	return out


static func _resources() -> void:
	if _mesh_body != null:
		return
	_mesh_body = BoxMesh.new()
	_mesh_body.size = Vector3(0.14, 0.2, 0.14)
	_mesh_glass = BoxMesh.new()
	_mesh_glass.size = Vector3(0.1, 0.14, 0.1)
	_mat_body = StandardMaterial3D.new()
	_mat_body.albedo_color = Color(0.12, 0.1, 0.09)
	_mat_body.roughness = 0.8
	_mat_glass = StandardMaterial3D.new()
	_mat_glass.albedo_color = Color(1.0, 0.8, 0.45)
	_mat_glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_glass.emission_enabled = true
	_mat_glass.emission = Color(1.0, 0.7, 0.3)
	_mat_glass.emission_energy_multiplier = 2.0


## Builds the lantern on `guard` (a Node3D) and makes sure the driver exists. Returns the lantern node.
static func attach(guard: Node3D) -> Node3D:
	if guard == null or guard.has_node("GuardLantern"):
		return guard.get_node_or_null("GuardLantern") as Node3D if guard != null else null
	_resources()
	var root := Node3D.new()
	root.name = "GuardLantern"
	root.position = Vector3(0.38, 0.95, 0.22)
	var body := MeshInstance3D.new()
	body.name = "Cage"
	body.mesh = _mesh_body
	body.material_override = _mat_body
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = _mesh_glass
	glass.material_override = _mat_glass
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.68, 0.32)
	light.omni_range = LIGHT_RANGE
	light.light_energy = 1.1
	light.shadow_enabled = false
	light.visible = false
	root.add_child(light)
	root.visible = false
	root.add_to_group(GROUP)
	guard.add_child(root)
	_ensure_driver(guard)
	return root


static func _ensure_driver(from: Node) -> void:
	if _driver != null and is_instance_valid(_driver):
		return
	var d := Node.new()
	d.name = "GuardLanternDriver"
	d.set_script(load("res://scripts/population/guard_lantern_driver.gd"))
	_driver = d
	from.get_tree().root.add_child.call_deferred(d)


## Lights up the nearest MAX_LIT lanterns (when it is night) and shows/hides every lantern. Returns the number of
## real lights now on.
static func update(tree: SceneTree, focus: Vector3, hour: float, max_lit := MAX_LIT) -> int:
	var is_night := night(hour)
	var cands: Array = []
	var by_id := {}
	for n: Node in tree.get_nodes_in_group(GROUP):
		var root := n as Node3D
		if root == null:
			continue
		root.visible = is_night
		var light := root.get_node_or_null("Light") as OmniLight3D
		if light == null:
			continue
		light.visible = false
		if not is_night or not root.is_inside_tree():
			continue
		var id := root.get_instance_id()
		by_id[id] = light
		cands.append({"id": id, "dist": root.global_position.distance_to(focus)})
	var on := 0
	for id: int in nearest(cands, max_lit):
		(by_id[id] as OmniLight3D).visible = true
		on += 1
	return on
