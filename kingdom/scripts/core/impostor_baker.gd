class_name ImpostorBaker
extends Node
## Renders each character type from four sides into a small sprite atlas at
## startup. Distant soldiers and crowds draw these sprites instead of skinned
## meshes, which is what lets hundreds of units stay cheap on a phone.

const FRAME := Vector2i(40, 56)
const SHADER := preload("res://shaders/impostor.gdshader")

## look_id -> ShaderMaterial
var materials: Dictionary = {}
var _viewport: SubViewport
var _holder: Node3D


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = FRAME
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	cam.position = Vector3(0, 0.95, 4)
	_viewport.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	_viewport.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	_holder = Node3D.new()
	_viewport.add_child(_holder)


## Bakes one look. `keep` = weapon/hat parts to show, `pose` = animation frame to freeze.
func bake(look_id: String, file: String, keep: Array[String], pose := "Idle") -> void:
	var model := Assets.character(file, 1.75, keep)
	_holder.add_child(model)
	var anim := Assets.animation_player(model)
	if anim and anim.has_animation(pose):
		anim.play(pose)
		anim.seek(0.2, true)
		anim.pause()
	var atlas := Image.create(FRAME.x * 4, FRAME.y, false, Image.FORMAT_RGBA8)
	for k in 4:
		# Frame k shows the unit as seen from 0°, 90°, 180°, 270° around it.
		model.rotation.y = -k * PI * 0.5
		# Plain frame waits (not frame_post_draw) so this also works in movie-capture mode.
		for f in 3:
			await get_tree().process_frame
		var img := _viewport.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, FRAME), Vector2i(k * FRAME.x, 0))
	model.queue_free()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("atlas", ImageTexture.create_from_image(atlas))
	materials[look_id] = mat


func set_light(value: float) -> void:
	for mat: ShaderMaterial in materials.values():
		mat.set_shader_parameter("light", value)


## A quad matching the bake camera's framing, origin at the character's feet.
static func quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(2.3 * FRAME.x / FRAME.y, 2.3)
	q.center_offset = Vector3(0, 0.95, 0)
	return q
