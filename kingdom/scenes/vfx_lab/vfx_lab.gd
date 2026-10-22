class_name VfxLab
extends Node3D
## vfx_lab: stage + the three Godot-native bending prototypes (water whip, fire blast, earth spikes) side by side,
## looping with a stand-in figure for scale. Open vfx_lab.tscn and press play. The effects themselves are
## LabFX subclasses (play(), seek(), finished) so gameplay can instance them later; see docs/art/vfx_lab/README.md.
## Not wired into the game: hook points are ElementFX.play(&"water", &"projectile"...) replacements, owned by the VFX/animation owner.
const EFFECTS := [
	["water", "res://scenes/vfx_lab/water_whip.gd", -7.0],
	["fire", "res://scenes/vfx_lab/fire_blast.gd", 0.0],
	["earth", "res://scenes/vfx_lab/earth_spikes.gd", 7.0],
]
@export var quality := 2
var _fx: Array = []
var _timer := 0.0

static func build_stage(parent: Node3D) -> Camera3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.52, 0.6)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.9, 0.75)
	sun.light_energy = 1.2
	sun.rotation_degrees = Vector3(-42, -35, 0)
	parent.add_child(sun)
	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(60, 40)
	ground.mesh = pl
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.3, 0.22)
	gm.roughness = 1.0
	ground.material_override = gm
	parent.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 48.0
	parent.add_child(cam)
	return cam

static func aim(cam: Camera3D, pos: Vector3, target: Vector3) -> void:
	cam.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)

static func stand_in(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = at
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 1.55
	body.mesh = cap
	body.position.y = 0.78
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.5, 0.45)
	body.material_override = m
	n.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.15
	sp.height = 0.3
	head.mesh = sp
	head.position.y = 1.65
	head.material_override = m
	n.add_child(head)
	return n

func _ready() -> void:
	var cam := build_stage(self)
	aim(cam, Vector3(0, 4.5, 11.0), Vector3(0, 0.8, -2.0))
	for e in EFFECTS:
		var holder := Node3D.new()
		holder.position = Vector3(e[2], 0, 0)
		add_child(holder)
		holder.add_child(stand_in(Vector3.ZERO))
		var fx: LabFX = load(e[1]).new()
		fx.quality = quality
		holder.add_child(fx)
		_fx.append(fx)
	_play_all()

func _play_all() -> void:
	for f in _fx:
		f.play()
	_timer = 0.0

func _process(delta: float) -> void:
	_timer += delta
	if _timer > 3.4:
		_play_all()
