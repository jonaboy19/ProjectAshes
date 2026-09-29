extends Control
## Boot scene (project main scene): splash -> main menu -> new game / load -> loading -> main.tscn.
## QA launches (any `-- --arg`, headless, tests) skip straight to main.tscn unchanged.

const Flow := preload("res://scripts/ui/frontend/flow.gd")
const SS := preload("res://scripts/ui/frontend/settings_store.gd")
const Splash := preload("res://scripts/ui/frontend/splash.gd")
const MainMenu := preload("res://scripts/ui/frontend/main_menu.gd")

var _curtain: ColorRect
var _busy := false


func _ready() -> void:
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
		_show_splash()
	_fade(0.0, 0.6)


func _show_splash() -> void:
	var s := Splash.new()
	s.finished.connect(func() -> void: transition(_show_menu))
	add_child(s)
	move_child(_curtain, -1)


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
