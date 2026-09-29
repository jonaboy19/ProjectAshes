extends Control
## A character bust rendered by its own tiny 3D world (own World3D, one model, two
## lights): the HUD's round portrait, the dialogue's big NPC bust and the character
## creator's preview. Cheap by design: nothing else of the game is drawn in it, and
## unless `live` is set it renders a handful of frames and then stops updating.
##
##   var p := Portrait.new()
##   p.setup(Vector2i(256, 320), "bust")
##   p.set_model(Assets.mh_character("villager_man_a", 1.75))
##
## `frame`: "face" (head only), "bust" (head and shoulders, dialogue) or "half" (to the hips).

const AF := preload("res://scripts/ui/ashes_frame.gd")

var live := false
var yaw_deg := -18.0
var frame := "bust"

var _vp: SubViewport
var _rect: TextureRect
var _cam: Camera3D
var _stage: Node3D
var _model: Node3D
var _anim: AnimationPlayer
var _frames_left := 0
var _head := Vector3.ZERO
var _spin := 0.0


func setup(px: Vector2i, frame_kind := "bust", is_live := false) -> void:
	frame = frame_kind
	live = is_live
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.size = px
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_disable_input = true
	add_child(_vp)
	_rect = TextureRect.new()
	_rect.texture = _vp.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_stage = Node3D.new()
	_vp.add_child(_stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.62)
	env.ambient_light_energy = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.7
	key.rotation_degrees = Vector3(-32, -34, 0)
	key.shadow_enabled = false
	_stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.62, 0.72, 1.0)
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-18, 155, 0)
	rim.shadow_enabled = false
	_stage.add_child(rim)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_cam.current = true
	_stage.add_child(_cam)


## Puts `model` (a character root from Assets.mh_character / character) on the stage.
func set_model(model: Node3D) -> void:
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = model
	_stage.add_child(model)
	_model.rotation_degrees.y = yaw_deg
	_anim = Assets.animation_player(model)
	if _anim:
		var idle := "Idle" if _anim.has_animation("Idle") else (_anim.get_animation_list()[0] if _anim.get_animation_list().size() > 0 else "")
		if idle != "":
			_anim.play(idle)
			_anim.advance(0.35)
	if is_inside_tree():
		_frame_camera()
	refresh()


func _ready() -> void:
	if _model:
		_frame_camera()


## Adds a duplicate of a live NPC's model (its skeleton modifiers and LOD fades are stripped).
func set_model_copy(src: Node3D) -> void:
	var dup := src.duplicate() as Node3D
	dup.position = Vector3.ZERO
	dup.rotation = Vector3.ZERO
	for m in dup.find_children("*", "SkeletonModifier3D", true, false):
		m.get_parent().remove_child(m)
		m.free()
	for g in dup.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		gi.visible = true
		gi.visibility_range_end = 0.0
		gi.visibility_range_begin = 0.0
		gi.layers = 1
	set_model(dup)


## Clip the render to a circle (round HUD portrait).
func set_circle(on: bool, mask: Material = null) -> void:
	_rect.material = mask if on else null


func model() -> Node3D:
	return _model


func spin_to(deg: float) -> void:
	yaw_deg = deg
	if _model:
		_model.rotation_degrees.y = deg
	refresh()


## Re-renders (a few frames, so a moved pose and a new texture reach the screen).
func refresh() -> void:
	_frames_left = 6
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _process(_delta: float) -> void:
	if live or _vp == null:
		return
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func texture() -> Texture2D:
	return _vp.get_texture() if _vp else null


func _frame_camera() -> void:
	var sk: Skeleton3D = null
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		sk = found[0]
	_head = Vector3(0, 1.55, 0)
	if sk:
		var bi := sk.find_bone("Head")
		if bi < 0:
			bi = sk.find_bone("head")
		if bi >= 0:
			_head = sk.to_global(sk.get_bone_global_rest(bi).origin)
	var span := 0.5
	var centre := _head
	match frame:
		"face":
			span = 0.46
			centre = _head + Vector3(0, 0.09, 0)
		"bust":
			span = 0.9
			centre = _head + Vector3(0, -0.13, 0)
		"half":
			span = 1.3
			centre = _head + Vector3(0, -0.36, 0)
		"full":
			span = 2.1
			centre = _head + Vector3(0, -0.72, 0)
	var aspect := float(_vp.size.x) / float(_vp.size.y)
	var vfov := deg_to_rad(_cam.fov)
	var need_v := span * 0.5 / tan(vfov * 0.5)
	# Keep the width in frame too (half-width ~ 0.36 m for a bust, wider lower down).
	var half_w := 0.34 if frame == "face" else (0.42 if frame == "bust" else 0.55)
	var need_h := half_w / (tan(vfov * 0.5) * aspect)
	var d := maxf(need_v, need_h)
	_cam.position = centre + Vector3(0, 0, d)
	_cam.look_at(centre, Vector3.UP)
