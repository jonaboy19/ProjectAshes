extends RefCounted
## Procedural ink face (brows, lids, mouth) on one 2-triangle quad parented to the Head bone. docs/art/FACES.md
## Villagers: one shared ShaderMaterial + per-instance uniforms (Mobile / Forward+ only, NEAR tier only, created on MEDIUM+).
## Hero (`hero = true`): own material with plain uniforms (works in Compatibility too), draws the mouth only (brows live in
## hero_character.gdshader, lids in the Lids patch); created on every tier, always visible.

const FaceState := preload("res://scripts/living_world/face_state.gd")
const SHADER := "res://shaders/npc/npc_face_card.gdshader"
const HERO_SHADER := "res://shaders/npc/hero_face_card.gdshader"
const OFFSETS := "res://data/living_world/face_offsets.json"
const DEFAULT_OFFSET := Vector3(0.0, 0.075, 0.095)
const DEFAULT_SIZE := Vector2(0.11, 0.1)
const DEFAULT_LAYOUT := Vector4(-0.04, 0.024, 0.03, 0.034)   # mouth_y, mouth half width, eye_x, brow_y (card-local metres)

static var _mat: ShaderMaterial
static var _debug_mat: ShaderMaterial
static var _offsets: Dictionary = {}
static var _offsets_loaded := false

var state := FaceState.new()
var mesh: MeshInstance3D
var attach: BoneAttachment3D
var _hero := false
var _own: ShaderMaterial
var _sent := {"brow": 9.0, "lids": 9.0, "mouth_open": 9.0, "mouth_curve": 9.0}
var _hero_lids := false


## Layout vector of a placement entry ("layout": [mouth_y, mouth_half_width, eye_x, brow_y]) or the default.
static func layout_of(o: Dictionary) -> Vector4:
	var l: Array = o.get("layout", [])
	return Vector4(l[0], l[1], l[2], l[3]) if l.size() == 4 else DEFAULT_LAYOUT


## The per-look placement from face_offsets.json: {"offset": [x,y,z], "size": [w,h], "disabled": bool} or {}.
static func offsets_for(look: String) -> Dictionary:
	if not _offsets_loaded:
		_offsets_loaded = true
		if FileAccess.file_exists(OFFSETS):
			var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFSETS))
			if j is Dictionary:
				_offsets = j
	return _offsets.get(look, {})


func _init(skeleton: Skeleton3D, offset := DEFAULT_OFFSET, size := DEFAULT_SIZE, hero := false, face_layout := DEFAULT_LAYOUT) -> void:
	_hero = hero
	if skeleton == null or skeleton.find_bone("Head") < 0:
		return
	attach = BoneAttachment3D.new()
	attach.name = "FaceCard"
	attach.bone_name = "Head"
	skeleton.add_child(attach)
	mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mesh.mesh = q
	mesh.position = offset
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if hero:
		_own = ShaderMaterial.new()
		_own.shader = load(HERO_SHADER)
		_own.set_shader_parameter("card_size", size)
		_own.set_shader_parameter("face_layout", face_layout)
		mesh.material_override = _own
	else:
		if _mat == null:
			_mat = ShaderMaterial.new()
			_mat.shader = load(SHADER)
		mesh.material_override = _mat
		mesh.visibility_range_end = 12.0
		mesh.visibility_range_end_margin = 1.5
		mesh.visible = false
		q.size = DEFAULT_SIZE            # the shared shader assumes this aspect; a per-look size scales the node
		mesh.scale = Vector3(size.x / DEFAULT_SIZE.x, size.y / DEFAULT_SIZE.y, 1.0)
	attach.add_child(mesh)
	if not hero and face_layout != DEFAULT_LAYOUT:
		mesh.set_instance_shader_parameter("face_layout", face_layout)


func is_valid() -> bool:
	return mesh != null


func set_mood(m: String) -> void:
	state.set_mood(m)


func say(text: String) -> void:
	state.say(FaceState.say_seconds(text))


func say_seconds(s: float) -> void:
	state.say(s)


func say_loop(on: bool) -> void:
	state.say_loop(on)


## Villagers pass lids to the card; the hero keeps its Lids patch (lids = false).
func set_hero_lids(on: bool) -> void:
	_hero_lids = on
	if _own:
		_own.set_shader_parameter("lids_on", 1.0 if on else 0.0)


func set_debug(on: bool) -> void:
	if mesh == null:
		return
	if _hero:
		_own.set_shader_parameter("debug", 1.0 if on else 0.0)
	elif on:
		if _debug_mat == null:
			_debug_mat = _mat.duplicate() as ShaderMaterial
			_debug_mat.set_shader_parameter("debug", 1.0)
		mesh.material_override = _debug_mat
	else:
		mesh.material_override = _mat


## Steps the state (villagers: only while `near`) and writes changed uniforms. Returns the face values.
func tick(dt: float, near := true) -> Dictionary:
	if mesh == null:
		return {}
	if not _hero:
		mesh.visible = near
		if not near:
			return {}
	var f := state.step(dt)
	for k: String in f:
		var v := float(f[k])
		if absf(v - float(_sent[k])) > 0.005:
			_sent[k] = v
			if _hero:
				_own.set_shader_parameter(k, v)
			else:
				mesh.set_instance_shader_parameter(k, v)
	return f
