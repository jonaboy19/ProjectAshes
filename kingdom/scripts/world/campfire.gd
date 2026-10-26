extends Node3D
## A player-built (or placed) campfire: stone ring, crossed logs, looping flames + smoke, a flickering light.
## Gameplay: group "heat_source" (Life warms the player within HEAT_RADIUS), and it is a "campfire" crafting
## station (cooking recipes in data/recipes.json) via the build kit (pieces.json "campfire").
## Weather: wind leans and fans the flames (Weather.wind_strength), rain damps them (smaller, dimmer, more smoke).

const K := preload("res://scripts/vfx/vfx_kit.gd")
const WeatherScript := preload("res://scripts/world/weather.gd")
const HEAT_RADIUS := 4.0
const GROUP := &"heat_source"

var _light: OmniLight3D
var _flames: GPUParticles3D
var _smoke: GPUParticles3D
var _t := 0.0
var _rain := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_build()
	set_process(DisplayServer.get_name() != "headless")


## Pure: flame intensity 0..1.2 from rain amount (0..1) and wind strength (1 = calm).
static func flame_strength(rain: float, wind: float) -> float:
	return clampf(1.0 - 0.55 * clampf(rain, 0.0, 1.0) + 0.15 * clampf(wind - 1.0, 0.0, 1.5), 0.25, 1.2)


## Pure: horizontal lean of flames/smoke (m/s^2) for a wind strength.
static func wind_push(wind: float) -> Vector3:
	return Vector3(1.0, 0.0, 0.35).normalized() * clampf((wind - 1.0) * 2.5 + 0.4, 0.0, 4.0)


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.43, 0.40)
	stone.roughness = 0.95
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.21, 0.12)
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(0.15, 0.07, 0.04)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.35, 0.08)
	ember.emission_energy_multiplier = 2.0
	for i in 9:
		var a := TAU * i / 9.0
		var mi := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.13
		bm.height = 0.18
		mi.mesh = bm
		mi.material_override = stone
		mi.position = Vector3(cos(a) * 0.48, 0.06, sin(a) * 0.48)
		mi.scale = Vector3(1.0 + 0.2 * sin(i * 3.1), 1.0, 0.9)
		add_child(mi)
	for i in 3:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.06
		cm.height = 0.7
		mi.mesh = cm
		mi.material_override = wood
		mi.rotation = Vector3(deg_to_rad(70.0), TAU * i / 3.0, 0.0)
		mi.position = Vector3(0, 0.14, 0)
		add_child(mi)
	var bed := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.34
	cyl.height = 0.04
	bed.mesh = cyl
	bed.material_override = ember
	bed.position.y = 0.02
	add_child(bed)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.omni_range = 7.0
	_light.light_energy = 1.6
	_light.shadow_enabled = false
	_light.position.y = 0.6
	add_child(_light)
	if DisplayServer.get_name() == "headless":
		return
	_flames = K.emit(self, global_position + Vector3(0, 0.12, 0), {"amount": 28, "life": 0.7, "one_shot": false, "local": true,
		"shape": "sphere", "radius": 0.16, "v": Vector2(0.6, 1.3), "spread": 12.0, "gravity": Vector3(0, 1.2, 0),
		"damping": Vector2(0.5, 1.0), "size": Vector2(0.18, 0.42),
		"mat": K.sprite_mat(K.SMOKE_PUFF, K.pal_from(Color(1.0, 0.55, 0.15)), 4.0, {"heat": 1.6})})
	_smoke = K.emit(self, global_position + Vector3(0, 0.6, 0), {"amount": 10, "life": 2.6, "one_shot": false, "local": false,
		"shape": "sphere", "radius": 0.12, "v": Vector2(0.4, 0.8), "spread": 10.0, "gravity": Vector3(0, 0.35, 0),
		"damping": Vector2(0.2, 0.4), "size": Vector2(0.3, 0.9),
		"mat": K.sprite_mat(K.SMOKE_PUFF, K.pal_from(Color(0.35, 0.33, 0.32, 0.45)), 0.6)})


func _process(delta: float) -> void:
	_t += delta
	var w := get_tree().get_first_node_in_group(&"weather")
	var rain := 0.0
	if w != null and w.has_method("rain_amount"):
		rain = float(w.call("rain_amount"))
	_rain = lerpf(_rain, rain, 1.0 - exp(-0.5 * delta))
	var wind := WeatherScript.wind_strength
	var k := flame_strength(_rain, wind)
	var gust := 0.12 * sin(_t * 9.0) + 0.08 * sin(_t * 23.0 + 1.3) + 0.1 * (wind - 1.0) * sin(_t * 3.7)
	_light.light_energy = 1.6 * k + gust
	var push := wind_push(wind)
	for p: GPUParticles3D in [_flames, _smoke]:
		if p != null and p.process_material is ParticleProcessMaterial:
			var pm := p.process_material as ParticleProcessMaterial
			var f := 1.0 if p == _smoke else 0.4
			pm.gravity = Vector3(push.x * f, pm.gravity.y, push.z * f)
	if _flames != null:
		_flames.amount_ratio = k / 1.2
	if _smoke != null:
		_smoke.amount_ratio = clampf(0.5 + _rain * 0.5, 0.0, 1.0)
