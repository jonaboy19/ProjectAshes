class_name AshGhost
extends Node3D
## One pooled Ashsight ghost (scene `scenes/region1/ash_ghost.tscn`): a soft grey-ember figure
## with drifting ash and ember footprints. All the look comes from
## `shaders/region1/ash_ghost.gdshader` (one alpha pass, no textures, no lights). The
## placeholder body is a simple robed figure; `set_model()` swaps in any character (a UAL model,
## an impostor) and gives it the ghost material, so the shader is the only look.
##
## Cost: `place()` is a transform set and, only when the fade changed, two shader parameters.

const ROLE_STYLE := {
	"bandit": {"ash": Color(0.96, 0.90, 0.84), "core": Color(0.80, 0.74, 0.70), "ember": Color(1.0, 0.56, 0.24), "hood": true},
	"villager": {"ash": Color(0.90, 0.95, 1.0), "core": Color(0.74, 0.80, 0.88), "ember": Color(0.66, 0.82, 1.0), "hood": false},
}
const DEFAULT_STYLE := {"ash": Color(0.82, 0.79, 0.75), "core": Color(0.60, 0.58, 0.58), "ember": Color(1.0, 0.64, 0.30), "hood": false}

var role := ""
var active := false
## Scratch value for the owner (the replay view stamps the frame it last saw this ghost).
var stamp := 0

var _mat: ShaderMaterial
var _alpha := -1.0
var _ash: GPUParticles3D
var _steps: GPUParticles3D
var _hood: Node3D
var _model: Node3D
var _halo_mat: ShaderMaterial


func _ready() -> void:
	_ash = get_node_or_null("Ash")
	_steps = get_node_or_null("Steps")
	_hood = get_node_or_null("Model/Hood")
	_model = get_node_or_null("Model")
	var halo := get_node_or_null("Halo") as MeshInstance3D
	if halo != null and halo.material_override is ShaderMaterial:
		_halo_mat = (halo.material_override as ShaderMaterial).duplicate()
		halo.material_override = _halo_mat
	# every ghost gets its own material so roles and fades do not leak between pooled ghosts
	var first := _first_mesh(self)
	if first != null and first.material_override is ShaderMaterial:
		_mat = (first.material_override as ShaderMaterial).duplicate()
		_apply_material(_model)
		_mat.set_shader_parameter(&"seed", float(get_instance_id() % 97) / 97.0)
	if _ash != null and _ash.process_material != null:
		_ash.process_material = _ash.process_material.duplicate()
	if _steps != null and _steps.process_material != null:
		_steps.process_material = _steps.process_material.duplicate()
	deactivate()


func _first_mesh(n: Node) -> MeshInstance3D:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		return c
	return null


func _apply_material(root: Node) -> void:
	if root == null or _mat == null:
		return
	for c in root.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = _mat
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Swap the placeholder body for another model (a Node3D with MeshInstance3D descendants).
## The model's feet must be at y = 0 and it should be about `height` metres tall.
func set_model(model: Node3D, height: float = 1.8) -> void:
	if _model != null:
		for c in _model.get_children():
			c.queue_free()
		_model.add_child(model)
		_apply_material(model)
	if _mat:
		_mat.set_shader_parameter(&"model_height", height)


func set_role(r: String) -> void:
	role = r
	var st: Dictionary = ROLE_STYLE.get(r, DEFAULT_STYLE)
	if _mat:
		_mat.set_shader_parameter(&"ash_color", st["ash"])
		_mat.set_shader_parameter(&"core_color", st["core"])
		_mat.set_shader_parameter(&"ember_color", st["ember"])
	if _halo_mat:
		_halo_mat.set_shader_parameter(&"ember_color", st["ember"])
	if _hood != null:
		_hood.visible = bool(st["hood"])
	if _ash != null and _ash.process_material is ParticleProcessMaterial:
		(_ash.process_material as ParticleProcessMaterial).color = (st["ash"] as Color).lerp(Color.WHITE, 0.3)
	if _steps != null and _steps.process_material is ParticleProcessMaterial:
		(_steps.process_material as ParticleProcessMaterial).color = (st["ember"] as Color).lerp(Color.WHITE, 0.15)


func activate(r: String = "") -> void:
	active = true
	visible = true
	set_role(r)
	_alpha = -1.0
	if _ash:
		_ash.emitting = true
		_ash.restart()
	if _steps:
		_steps.emitting = true
		_steps.restart()


func deactivate() -> void:
	active = false
	visible = false
	if _ash:
		_ash.emitting = false
	if _steps:
		_steps.emitting = false


## Move the ghost. `heading` is the yaw in radians (0 = facing -Z). `fade` 0..1.
func place(pos: Vector3, heading: float, fade: float) -> void:
	position = pos
	rotation.y = heading
	if _mat and absf(fade - _alpha) > 0.015:
		_alpha = fade
		_mat.set_shader_parameter(&"alpha", fade)
		if _halo_mat:
			_halo_mat.set_shader_parameter(&"alpha", fade)
		# smoothstep: the figure crumbles away as it fades, and re-forms as it arrives
		_mat.set_shader_parameter(&"dissolve", 1.0 - fade * fade * (3.0 - 2.0 * fade))


func material() -> ShaderMaterial:
	return _mat
