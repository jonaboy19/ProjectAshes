extends Node3D
## A Rift vent in the Weeping Hall (F9 environment hazard). Idle, then a 1.4 s warning (the crack glows and pulses),
## then a burst that hurts anything of the player's standing inside `radius`. Visible, readable and dodgeable.
## step(dt) is the whole clock, so tests can run a cycle without a scene tree. Group "rift_vent".

var period := 7.0
var telegraph := 1.4
var damage := 9
var radius := 1.9
var phase := "idle"              # idle | warn | burst
var bursts := 0
var hits := 0
var _t := 0.0
var _burst_left := 0.0
var _disc: MeshInstance3D
var _mat: StandardMaterial3D
var _light: OmniLight3D


func configure(cfg: Dictionary, offset := 0.0) -> void:
	period = float(cfg.get("period", period))
	telegraph = float(cfg.get("telegraph", telegraph))
	damage = int(cfg.get("damage", damage))
	radius = float(cfg.get("radius", radius))
	_t = fposmod(offset, period)


func _ready() -> void:
	add_to_group("rift_vent")
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.25, 0.1, 0.35, 0.8)
	_disc = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.55
	cyl.bottom_radius = radius * 0.55
	cyl.height = 0.04
	cyl.radial_segments = 16
	_disc.mesh = cyl
	_disc.position.y = 0.05
	_disc.material_override = _mat
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.8, 0.45, 1.0)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position.y = 0.8
	add_child(_light)
	_paint()


func _process(delta: float) -> void:
	step(delta)


## Advance the clock; returns true on the frame a burst fires.
func step(dt: float) -> bool:
	var fired := false
	if phase == "burst":
		_burst_left -= dt
		if _burst_left <= 0.0:
			phase = "idle"
			_t = 0.0
	else:
		_t += dt
		if _t >= period:
			phase = "burst"
			_burst_left = 0.45
			bursts += 1
			fired = true
			_hurt()
		elif _t >= period - telegraph:
			phase = "warn"
		else:
			phase = "idle"
	if is_inside_tree():
		_paint()
	return fired


func _hurt() -> void:
	if not is_inside_tree():
		return
	for p: Node in get_tree().get_nodes_in_group("player"):
		if p is Node3D and not (p.get("dead") == true):
			var d := Vector2((p as Node3D).global_position.x - global_position.x, (p as Node3D).global_position.z - global_position.z).length()
			if d < radius and p.has_method("take_damage"):
				hits += 1
				p.call("take_damage", damage, self, Vector3.ZERO)


func _paint() -> void:
	if _mat == null:
		return
	match phase:
		"warn":
			var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
			_mat.albedo_color = Color(1.0, 0.35 + 0.2 * k, 0.15, 0.55 + 0.35 * k)
			_light.light_energy = 0.8 * k
		"burst":
			_mat.albedo_color = Color(0.85, 0.5, 1.0, 0.95)
			_light.light_energy = 2.6
		_:
			_mat.albedo_color = Color(0.25, 0.1, 0.35, 0.8)
			_light.light_energy = 0.0
