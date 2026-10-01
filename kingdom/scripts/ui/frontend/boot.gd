extends Control
## Boot scene (project main scene): splash -> main menu -> new game / load -> loading -> main.tscn.
## QA launches (any `-- --arg`, headless, tests) skip straight to main.tscn unchanged.

const Flow := preload("res://scripts/ui/frontend/flow.gd")
const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const Splash := preload("res://scripts/ui/frontend/splash.gd")
const MainMenu := preload("res://scripts/ui/frontend/main_menu.gd")
const FirstRun := preload("res://scripts/boot/first_run.gd")

var _curtain: ColorRect
var _busy := false


func _ready() -> void:
	# Style Lab (docs/design/STYLE_LAB.md): `-- --style_lab` or `-- --shot=style_lab` opens it instead of the game.
	if OS.get_cmdline_user_args().has("--style_lab") or OS.get_cmdline_user_args().has("--shot=style_lab"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/style_lab/style_lab.tscn")
		return
	if Flow.is_qa_launch():
		get_tree().change_scene_to_file.call_deferred(Flow.MAIN_SCENE)
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("050403")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Flow.capture_pristine(get_tree())
	Flow.reset_world_state(get_tree())
	SS.apply_all(get_tree())
	_curtain = ColorRect.new()
	_curtain.color = Color.BLACK
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.z_index = 100
	add_child(_curtain)
	if Flow.skip_splash:
		_show_menu()
	else:
		_show_intro()
	_fade(0.0, 0.6)


## The studio logo film (assets/video/studio_intro.ogv), skippable by tap or key after 1 s.
func _show_intro() -> void:
	var s := StudioIntro.new()
	s.finished.connect(func() -> void: transition(_show_splash))
	add_child(s)
	move_child(_curtain, -1)


func _clear_screens() -> void:
	for c in get_children():
		if c != _curtain and c is Control and c.get_index() > 0:
			c.queue_free()


func _show_splash() -> void:
	_clear_screens()
	var s := Splash.new()
	s.finished.connect(func() -> void: transition(_after_splash))
	add_child(s)
	move_child(_curtain, -1)


## Once, on the very first launch: language, privacy notice, how-to-play hint.
func _after_splash() -> void:
	if FirstRun.needed():
		_clear_screens()
		var f := FirstRun.new()
		f.finished.connect(func() -> void: transition(_show_menu))
		add_child(f)
		move_child(_curtain, -1)
	else:
		_show_menu()


func _show_menu() -> void:
	for c in get_children():
		if c != _curtain and c is Control and c.get_index() > 0:
			c.queue_free()
	var m := MainMenu.new()
	add_child(m)
	move_child(_curtain, -1)


func _fade(to: float, t: float) -> Tween:
	var tw := create_tween()
	tw.tween_property(_curtain, "color:a", to, t)
	return tw


## Fade to black, run `fn` (swap screens), fade back in.
func transition(fn: Callable) -> void:
	if _busy:
		return
	_busy = true
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := _fade(1.0, 0.28)
	tw.finished.connect(func() -> void:
		fn.call()
		move_child(_curtain, -1)
		var t2 := _fade(0.0, 0.35)
		t2.finished.connect(func() -> void:
			_busy = false
			_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE))
