extends Node3D
## Standalone combat-feel clip: the REAL Player and a real bandit Soldier on a flat arena, no main scene.
## Records the light / light / riposte-heavy / finisher chain so the tiers (hit-stop, FOV, roll, flash), the
## pooled impact, the lock rim and the ragdoll fall can be read off a contact sheet (ashes-video-review).
##   xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan \
##     --write-movie /tmp/claude-0/aaa_combat/clip/f.png --fixed-fps 30 --quit-after 200 \
##     res://tools_qa/combat/feel_clip.tscn
## Never --headless (no frames). Events go to stdout as "CLIP f=<frame> ...".

const PlayerScript := preload("res://scripts/actors/player.gd")
const SoldierScript := preload("res://scripts/army/soldier.gd")
const StyleGLib := preload("res://scripts/style_g.gd")
const Feel := preload("res://scripts/combat/combat_feel.gd")

var _f := 0
var _p: Node3D
var _b: Node3D
var _label: Label
var _swings := 0
var _note := ""
var _fov_peak := 0.0
var _roll_peak := 0.0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 2, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -1, 0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.38, 0.28)
	ground.material_override = gm
	ground.position = Vector3(0, 1.0, 0)
	floor_body.add_child(ground)
	add_child(floor_body)
	var env := StyleGLib.make_environment("high")
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	add_child(StyleGLib.make_sun("high"))
	add_child(StyleGLib.make_fill())
	_p = PlayerScript.new()
	add_child(_p)
	_p.global_position = Vector3(0, 0.1, 0)
	_p.stamina = 100.0
	var keep: Array[String] = []
	_b = SoldierScript.create(1, "", "Guard", keep)
	add_child(_b)
	_b.global_position = Vector3(0, 0.1, 0) + _p.facing() * 2.3
	_b._attack_cooldown = 999.0
	_p.swing_started.connect(_on_swing)
	_p.hit_confirmed.connect(func(points: Array, fin: bool, _m: Array) -> void:
		var a: Resource = _p.get("_action")
		var tier := Feel.tier_for(fin, false, a.knockback, a.damage, a.poise_damage, false) if a else 0
		_note = "HIT tier=%s fin=%s pts=%d" % [Feel.TIER_NAMES[tier], fin, points.size()]
		print("CLIP f=%d %s" % [_f, _note]))
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)


func _on_swing(action: Resource, info: Dictionary) -> void:
	_swings += 1
	print("CLIP f=%d swing %d %s riposte=%s" % [_f, _swings, action.id, info["riposte"]])
	if _swings == 2:
		_p._parry_bonus = 1.0     # the next swing is a riposte: heavy tier


func _process(_delta: float) -> void:
	_f += 1
	if _f == 14 and is_instance_valid(_b):
		_p.toggle_lock()
	if _f >= 30 and _f % 11 == 0 and _swings < 4:
		_p.attack()
	_fov_peak = maxf(_fov_peak, _p._impact_fov)
	_roll_peak = maxf(_roll_peak, absf(_p._impact_roll))
	var cam: Camera3D = _p.camera
	_label.text = "f%03d  %s  fov+%.1f roll%.3f cam.fov %.1f  bandit %s" % [_f, _note, _p._impact_fov, _p._impact_roll,
		cam.fov, "down" if is_instance_valid(_b) and _b.dead else "up"]
	if _f == 199:
		print("CLIP peaks fov+%.2f roll %.3f" % [_fov_peak, _roll_peak])
