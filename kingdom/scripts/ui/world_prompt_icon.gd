extends Control
## Small interaction icon ON the object (AAA pass 2, 2026-10-06; owner review: "a small icon next to the object, not a big
## black box"). The HUD hands it the current interactable and the round icon face it already builds for the interact
## button; this projects the object's top to the screen every frame, eases in/out and shows the verb in small type.
## Hidden behind the camera, off screen, in menus and when nothing is in reach. Pure UI: no physics, one draw call.

const SIZE := 46.0               # px at 1080p
var target: Node3D
var verb := ""
var face: Texture2D
var _a := 0.0
var _pos := Vector2.ZERO
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func step(delta: float, cam: Camera3D, allowed: bool) -> void:
	var want := 0.0
	if allowed and is_instance_valid(target) and cam != null:
		var top := target.global_position + Vector3(0, _height(target), 0)
		if not cam.is_position_behind(top):
			var p := cam.unproject_position(top)
			var r := get_viewport_rect()
			if r.grow(-20.0).has_point(p):
				_pos = p if _a <= 0.01 else _pos.lerp(p, 1.0 - exp(-25.0 * delta))
				want = 1.0
	_a = move_toward(_a, want, delta * 6.0)
	visible = _a > 0.01
	queue_redraw()


static func _height(n: Node3D) -> float:
	if n is CharacterBody3D or n.is_in_group("villager"):
		return 2.15
	if n.get("kind") != null and String(n.get("kind")).begins_with("horse"):
		return 2.2
	return 1.3


func _draw() -> void:
	if face == null:
		return
	var k := clampf(get_viewport_rect().size.y / 1080.0, 0.6, 2.0)
	var s := SIZE * k * lerpf(0.85, 1.0, _a)
	var c := Color(1, 1, 1, _a)
	draw_texture_rect(face, Rect2(_pos - Vector2(s, s) * 0.5, Vector2(s, s)), false, c)
	if verb != "":
		var fs := int(15.0 * k)
		var w := _font.get_string_size(verb, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		var at := _pos + Vector2(-w * 0.5, s * 0.5 + fs + 2.0)
		draw_string_outline(_font, at, verb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.05, 0.04, 0.03, 0.8 * _a))
		draw_string(_font, at, verb, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.93, 0.75, _a))
