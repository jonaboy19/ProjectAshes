extends Node3D
## Gives the player's homestead (scripts/sim/homestead.gd) a body near the
## player: owned plots' placed pieces and crop plots build within BUILD metres
## and free past FREE, the same hysteresis RegionDressing uses for its sites.
## A cottage on a built plot gets a sleep interactable (a bed marker) that sets
## the player's spawn point and puts them to bed.
##
## Small scale on purpose (a handful of pieces per plot): every 0.5 s this does
## one full diff of the sim's pieces/crops against the nodes on screen, which is
## cheap next to RegionDressing's whole-region streaming.

const REGION := "res://assets/generated/region/"
const GEN := "res://assets/generated/"
const BUILD := 150.0
const FREE := 220.0
const REFRESH_PERIOD := 0.5

var focus := Vector3.ZERO
var _timer := 0.0
var _built_plots: Dictionary = {}       # plot index -> true
var _piece_nodes: Dictionary = {}       # "piece:<uid>" -> Node3D
var _crop_nodes: Dictionary = {}        # "crop:<uid>" -> {node, holder, loaded_crop}
var _beds: Dictionary = {}              # plot index -> HomesteadBed


## A bed beside the cottage: sets the player's spawn point and sleeps, like
## fishing_spot.gd's self-dispatched interactable.
class HomesteadBed extends Node3D:
	var plot := -1
	var _menu_was_open := false

	func _ready() -> void:
		add_to_group("interactable")

	func prompt() -> String:
		return "Sleep"

	func use() -> void:
		var p: Variant = Life.player
		if p is Node3D and is_instance_valid(p):
			p.spawn_point = global_position
		if Life.has_method("sleep"):
			var msg := String(Life.sleep(1.0))
			if msg != "":
				Game.say(msg)

	func _process(_delta: float) -> void:
		var p: Variant = Life.player
		if not (p is Node3D) or not is_instance_valid(p) or (p as Node3D).global_position.distance_squared_to(global_position) > 3.2 * 3.2:
			_menu_was_open = false
			return
		var scene := get_tree().current_scene
		var hud: Variant = scene.get("hud") if scene else null
		var menu_open: bool = hud is Object and is_instance_valid(hud) and (hud as Object).has_method("is_menu_open") \
			and bool((hud as Object).call("is_menu_open"))
		var was := _menu_was_open
		_menu_was_open = menu_open
		if menu_open or was or not Input.is_action_just_pressed("interact"):
			return
		if (p as Node3D).has_method("nearest_interactable") and (p as Node3D).call("nearest_interactable") == self:
			use()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_PERIOD
	_refresh()


func _refresh() -> void:
	var hs := Life.homestead
	var p := Vector2(focus.x, focus.z)
	for i in hs.plots().size():
		if not hs.is_owned(i):
			continue
		var d := p.distance_to((hs.plots()[i]["pos"] as Vector2))
		if d < BUILD:
			_built_plots[i] = true
		elif d > FREE:
			_built_plots.erase(i)

	var want_pieces := {}
	for pc: Dictionary in hs.pieces:
		if _built_plots.has(int(pc["plot"])):
			want_pieces["piece:%d" % int(pc["uid"])] = pc
	var want_crops := {}
	for cr: Dictionary in hs.crops:
		if _built_plots.has(int(cr["plot"])):
			want_crops["crop:%d" % int(cr["uid"])] = cr

	for key in _piece_nodes.keys().duplicate():
		if not want_pieces.has(key):
			_free_node(_piece_nodes[key])
			_piece_nodes.erase(key)
	for key in _crop_nodes.keys().duplicate():
		if not want_crops.has(key):
			_free_node((_crop_nodes[key] as Dictionary)["node"])
			_crop_nodes.erase(key)

	for key in want_pieces:
		if not _piece_nodes.has(key):
			_piece_nodes[key] = _build_piece(want_pieces[key])
	for key in want_crops:
		if not _crop_nodes.has(key):
			_crop_nodes[key] = _build_crop(want_crops[key])
		_update_crop_visual(key, want_crops[key])

	var want_beds := {}
	for pc: Dictionary in hs.pieces:
		if String(pc["kind"]) == "cottage" and _built_plots.has(int(pc["plot"])):
			want_beds[int(pc["plot"])] = pc
	for i in _beds.keys().duplicate():
		if not want_beds.has(i):
			_free_node(_beds[i])
			_beds.erase(i)
	for i in want_beds:
		if not _beds.has(i):
			_beds[i] = _build_bed(int(i), want_beds[i])


func _free_node(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()


## Builds every owned plot's pieces and crops at once (screenshots, teleports).
func build_all_now() -> void:
	var hs := Life.homestead
	for i in hs.plots().size():
		if hs.is_owned(i):
			_built_plots[i] = true
	_refresh()


func _build_piece(pc: Dictionary) -> Node3D:
	var hs := Life.homestead
	var plot := int(pc["plot"])
	var cfg: Dictionary = hs.CATALOG.get(String(pc["kind"]), {})
	var world: Vector2 = hs.cell_world(plot, pc["cell"])
	var yaw: float = float(hs.plots()[plot]["yaw"]) + float(pc["rot"]) * PI * 0.5
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(world.x, WorldGen.height(world.x, world.y), world.y)
	root.rotation.y = yaw
	var asset := String(cfg.get("asset", ""))
	if asset == "":
		return root
	var n := _spawn(asset)
	if n == null:
		return root
	root.add_child(n)
	if not asset.begins_with("building:"):
		var box := Assets.visual_aabb(n)
		if box.size.x * box.size.z > 0.3:
			_collider(n, box)
	return root


func _build_crop(cr: Dictionary) -> Dictionary:
	var hs := Life.homestead
	var plot := int(cr["plot"])
	var world: Vector2 = hs.cell_world(plot, cr["cell"])
	var root := Node3D.new()
	add_child(root)
	root.global_position = Vector3(world.x, WorldGen.height(world.x, world.y) + 0.02, world.y)
	var holder := Node3D.new()
	root.add_child(holder)
	return {"node": root, "holder": holder, "loaded_crop": ""}


## Swaps the crop mesh in when the planted crop changes, and scales it by
## growth stage (0.15 just planted, 1.0 ready to harvest).
func _update_crop_visual(key: String, cr: Dictionary) -> void:
	var e: Dictionary = _crop_nodes[key]
	var holder: Node3D = e["holder"]
	if not is_instance_valid(holder):
		return
	var crop := String(cr.get("crop", ""))
	if String(e.get("loaded_crop", "")) != crop:
		for c in holder.get_children():
			c.queue_free()
		e["loaded_crop"] = crop
		_crop_nodes[key] = e
		if crop != "":
			var cfg: Dictionary = Life.homestead.CROPS.get(crop, {})
			var n := _spawn(String(cfg.get("asset", "")))
			if n:
				holder.add_child(n)
	if crop != "":
		holder.scale = Vector3.ONE * clampf(Life.homestead.growth_stage(cr), 0.15, 1.0)


func _build_bed(plot: int, pc: Dictionary) -> Node3D:
	var hs := Life.homestead
	var world: Vector2 = hs.cell_world(plot, pc["cell"])
	var yaw: float = float(hs.plots()[plot]["yaw"]) + float(pc["rot"]) * PI * 0.5
	var at := world + Vector2(sin(yaw), cos(yaw)) * 2.0
	var bed := HomesteadBed.new()
	bed.plot = plot
	add_child(bed)
	bed.global_position = Vector3(at.x, WorldGen.height(at.x, at.y) + 0.05, at.y)
	return bed


## "building:key" -> Assets.building_node (scaled, its own collider); "farm/x" and
## "props/x" -> the plain region/prop GLB, uncollided (homestead pieces are few,
## so a merged/LOD pipeline like RegionDressing's would be overkill here).
func _spawn(asset: String) -> Node3D:
	if asset == "":
		return null
	if asset.begins_with("building:"):
		return Assets.building_node(asset.substr(9))
	var path := ""
	if asset.begins_with("farm/"):
		path = REGION + asset + ".glb"
	elif asset.begins_with("props/"):
		path = GEN + asset + ".glb"
	if path == "" or not ResourceLoader.exists(path):
		return null
	return (load(path) as PackedScene).instantiate()


func _collider(n: Node3D, box: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(box.size.x * 0.85, box.size.y, box.size.z * 0.85)
	shape.shape = b
	shape.position = box.get_center()
	body.add_child(shape)
	n.add_child(body)
