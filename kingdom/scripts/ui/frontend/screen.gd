extends Control
## Base for every front-end screen: full-rect, dark-gold theme, runs while the tree is
## paused, Esc / gamepad-B goes back, optional backdrop art.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const FE := preload("res://scripts/ui/frontend/fe.gd")

signal closed

var can_back := true
## Over the running game (pause menu): dark veil instead of the painted backdrop.
var translucent := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = AF.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func add_backdrop(name: String, dim_alpha := 0.35) -> void:
	if translucent:
		add_child(FE.dim(0.82, Color(0.02, 0.015, 0.01)))
	else:
		add_child(FE.backdrop_stack(name, dim_alpha))


func back() -> void:
	FE.play("close")
	closed.emit()
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if can_back and is_visible_in_tree() and e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()


## A margin container filling the screen (default 40 px gutters, larger on wide phones).
func margin_box(m := 40) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	add_child(mc)
	return mc


func focus_first(root: Node = self) -> void:
	for c in root.find_children("*", "Button", true, false):
		var b := c as Button
		if b.focus_mode != Control.FOCUS_NONE and not b.disabled and b.is_visible_in_tree():
			b.call_deferred("grab_focus")
			return
