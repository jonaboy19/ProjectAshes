class_name Ladder
extends Node3D
## A simple vertical move between two markers: "Climb" at the bottom takes the player to the top marker and "Climb"
## at the top takes them back down. Each end is a child Marker3D carrying its own Interactable, so the picker
## offers whichever end the player stands at. A player with a traversal driver (scripts/actors/traversal.gd)
## climbs over time with the ladder clip; any other node is moved at once.

signal climbed(to_top: bool)

var bottom: Marker3D
var top: Marker3D


## A ladder whose bottom is at `bottom_pos` and top at `top_pos` (both global). The top marker is where the
## player is put, so give it a spot on the upper floor, not on the rung.
static func spawn(parent: Node, bottom_pos: Vector3, top_pos: Vector3, label := "Ladder") -> Ladder:
	var l := Ladder.new()
	l.name = label.replace(" ", "")
	parent.add_child(l)
	l.global_position = bottom_pos
	var lean := Vector2(top_pos.x - bottom_pos.x, top_pos.z - bottom_pos.z)
	if lean.length() > 0.05:
		l.rotation.y = atan2(lean.x, lean.y)      # the ladder faces the climber (rails across, the top marker beyond it)
	l.bottom.global_position = bottom_pos
	l.top.global_position = top_pos
	l._build_visual(top_pos.y - bottom_pos.y)
	return l


func _init() -> void:
	bottom = Marker3D.new()
	bottom.name = "Bottom"
	add_child(bottom)
	top = Marker3D.new()
	top.name = "Top"
	add_child(top)


func _ready() -> void:
	Interactable.attach(bottom, {"id_fn": func() -> String: return "ladder/%s/bottom" % name, "verb": "Climb", "target": "Ladder",
		"range": 2.2, "do": func(p: Node) -> void: climb(p as Node3D, true)})
	Interactable.attach(top, {"id_fn": func() -> String: return "ladder/%s/top" % name, "verb": "Climb", "target": "Ladder",
		"range": 2.2, "do": func(p: Node) -> void: climb(p as Node3D, false)})


func height() -> float:
	return top.global_position.y - bottom.global_position.y


## Puts the player at the far end. `to_top` true goes up. Returns the destination.
func climb(player: Node3D, to_top: bool) -> Vector3:
	var dest := top.global_position if to_top else bottom.global_position
	if player == null:
		return dest
	# F2: a player with a traversal driver climbs over time (ladder clip, scripted move); anything else is moved at once.
	var trav: Variant = player.get("_trav")
	if trav is Object and (trav as Object).has_method("begin_ladder") \
			and bool((trav as Object).call("begin_ladder", global_position, dest, to_top, func() -> void: climbed.emit(to_top), global_basis.z)):
		return dest
	player.global_position = dest
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if player.has_method("reset_physics_interpolation"):
		player.call("reset_physics_interpolation")
	climbed.emit(to_top)
	return dest


## Rung spacing and first-rung height: they match the climb clip's hand / foot contacts (Ladder_Climb_Up: 0.31 m), so the hand IK in
## scripts/actors/traversal.gd (_ladder_hands) lands the hands on real rungs. Keep in sync with data/movement/traversal.json "ladder".
const RUNG := 0.31
const RUNG_BASE := 0.39
const RAIL_GLB := "res://assets/generated/props/ladder/ladder_rail.glb"
const RUNG_GLB := "res://assets/generated/props/ladder/ladder_rung.glb"
static var _wood: StandardMaterial3D
static var _rope: StandardMaterial3D


static func _materials() -> void:
	if _wood != null:
		return
	var tex := "res://assets/incoming/polyhaven/textures/medieval_wood/medieval_wood_"
	_wood = StandardMaterial3D.new()
	_wood.albedo_texture = load(tex + "diff_2k.jpg")
	_wood.albedo_color = Color(0.82, 0.78, 0.72)          # weathered: a little grey and pale
	_wood.normal_enabled = true
	_wood.normal_texture = load(tex + "nor_gl_2k.jpg")
	_wood.roughness_texture = load(tex + "arm_2k.jpg")
	_wood.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	_wood.ao_enabled = true
	_wood.ao_texture = load(tex + "arm_2k.jpg")
	_wood.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_wood.uv1_triplanar = true
	_wood.uv1_scale = Vector3(2.0, 2.0, 2.0)
	_rope = StandardMaterial3D.new()
	_rope.albedo_color = Color(0.56, 0.47, 0.33)
	_rope.roughness = 0.95


func _build_visual(h: float) -> void:
	_materials()
	var rail_len := h + 0.35                # the rails stand above the top so the climber has something to hold on the top-out
	if ResourceLoader.exists(RAIL_GLB) and ResourceLoader.exists(RUNG_GLB):
		for sx in [-0.26, 0.26]:
			var r: Node3D = (load(RAIL_GLB) as PackedScene).instantiate()
			r.scale = Vector3(-1.0 if sx < 0.0 else 1.0, rail_len, 1.0)      # split faces inward
			r.position = Vector3(sx, 0, 0)
			_paint(r, _wood)
			add_child(r)
		var y := RUNG_BASE
		while y < h + 0.05:
			var g: Node3D = (load(RUNG_GLB) as PackedScene).instantiate()
			g.position = Vector3(0, y, 0)
			g.rotation.y = randf_range(-0.03, 0.03)
			_paint(g, null)
			add_child(g)
			y += RUNG
		return
	# fallback (no generated parts)
	for sx in [-0.22, 0.22]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.06, h, 0.06)
		rail.mesh = rm
		rail.material_override = _wood
		rail.position = Vector3(sx, h * 0.5, 0)
		add_child(rail)


## Wood surfaces get the textured wood, the rope keeps a rope colour (surface material names from build_ladder.py).
static func _paint(n: Node, force: Material) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			var nm := String(src.resource_name) if src != null else ""
			m.set_surface_override_material(si, force if force != null else (_rope if nm.contains("Rope") else _wood))

