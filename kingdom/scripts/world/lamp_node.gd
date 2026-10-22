extends Node3D
## LampNode: one street lamp / torch / brazier light source of a town. Replaces the bare OmniLight3D that
## settlement_builder and region1_look used to add. It stays in group "street_lamp" and keeps the two properties
## every reader uses, `light_energy` (main.gd sets it from the night amount) and `omni_range` (npc_world.sync_lamps
## feeds Perception.register_light with both), so the perception light model works unchanged.
##
## What it shows depends on the tier (Quality): LOW and MEDIUM have NO realtime light, only the flickering billboard
## glow batch (LampGlow, one MultiMesh per town); HIGH and ULTRA add a real OmniLight3D child.
## `light_energy` is also what lights the glow (energy / LIT_ENERGY = 0..1).

const LIT_ENERGY := 1.6
const OMNI_MIN_TIER := 2

var omni_range := 9.0
var light_color := Color(1.0, 0.72, 0.4)
var batch: Node3D                     ## the shared glow MultiMeshInstance3D (may be null)
var light_energy := 0.0:
	set(v):
		light_energy = v
		_apply()
var _omni: OmniLight3D


func _ready() -> void:
	add_to_group("street_lamp")
	var q := get_node_or_null("/root/Quality")
	if q and q.has_signal("changed") and not q.is_connected("changed", _on_quality):
		q.connect("changed", _on_quality)
	_on_quality()


func uses_omni() -> bool:
	var q := get_node_or_null("/root/Quality")
	return q != null and int(q.get("tier")) >= OMNI_MIN_TIER


func has_omni() -> bool:
	return _omni != null and is_instance_valid(_omni)


func _on_quality() -> void:
	if uses_omni():
		if not has_omni():
			_omni = OmniLight3D.new()
			_omni.light_color = light_color
			_omni.omni_range = omni_range
			_omni.shadow_enabled = false
			_omni.light_energy = light_energy
			add_child(_omni)
	elif has_omni():
		_omni.queue_free()
		_omni = null
	_apply()


func _apply() -> void:
	if has_omni():
		_omni.light_energy = light_energy
	var lit := clampf(light_energy / LIT_ENERGY, 0.0, 1.0)
	if batch != null and is_instance_valid(batch):
		var mat := (batch as GeometryInstance3D).material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("lit", lit)
		batch.visible = lit > 0.01
