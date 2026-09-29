class_name WorldLoading
extends "res://scripts/ui/frontend/screen.gd"
## The veil the HUD shows while main.gd generates the world on the main thread (baking sprites,
## raising terrain, building villages). Same look as the front-end loading screen (backdrop, logo,
## tip panel, gold bar) so the hand-over from the menu is seamless, but the bar and step text
## are driven by main.gd through HUD.set_loading_text(text, progress). The bar eases toward the
## reported value and creeps a little between reports, so it never looks frozen while a step blocks
## a frame. `WorldLoading.finish()` fades it out (the HUD calls it from hide_loading).

const FRONT_LOADING := "res://scripts/ui/frontend/loading_screen.gd"

static var current: WorldLoading

var progress := 0.0
var _target := 0.0
var _bar: ProgressBar
var _step: Label
var _tip: Label
var _tips: Array = []
var _tip_i := 0
var _tip_t := 0.0
var _fading := false


func _init() -> void:
	super()
	can_back = false


func _ready() -> void:
	current = self
	var fl: Script = load(FRONT_LOADING)
	_tips = fl.get_script_constant_map().get("TIPS", []) if fl else []
	if _tips.is_empty():
		_tips = ["Runestones keep the wilds at bay."]
	add_backdrop("loading", 0.2)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 26
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lc := CenterContainer.new()
	lc.add_child(FE.logo(0.7))
	lc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(lc)
	add_child(top)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_left = 0.5
	bottom.anchor_right = 0.5
	bottom.offset_left = -400
	bottom.offset_right = 400
	bottom.offset_top = -190
	bottom.offset_bottom = -34
	bottom.add_theme_constant_override("separation", 16)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var pc := PanelContainer.new()
	var sb := AF.panel(Color(0.03, 0.028, 0.025, 0.78), AF.GOLD_DIM, 3, 14)
	sb.shadow_size = 0
	pc.add_theme_stylebox_override("panel", sb)
	bottom.add_child(pc)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	pc.add_child(tv)
	var tl := Label.new()
	tl.text = "TIP"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.add_theme_font_override("font", AF.wfont(700))
	tl.add_theme_font_size_override("font_size", 14)
	tl.add_theme_color_override("font_color", AF.GOLD)
	tv.add_child(tl)
	_tip = AF.label("", 19, AF.TEXT)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip.custom_minimum_size = Vector2(0, 54)
	tv.add_child(_tip)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	bottom.add_child(_bar)
	_step = Label.new()
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step.add_theme_font_override("font", AF.wfont(500))
	_step.add_theme_font_size_override("font_size", 15)
	_step.add_theme_color_override("font_color", AF.TEXT)
	_step.text = tr("Loading World...")
	bottom.add_child(_step)
	_tip_i = randi() % _tips.size()
	_tip.text = String(_tips[_tip_i])


## p in 0..1 (or -1 to keep the last value), text = the step being worked on.
func set_progress(p: float, text := "") -> void:
	if p >= 0.0:
		_target = clampf(p, 0.0, 1.0)
	if text != "" and _step:
		_step.text = "%s  %d%%" % [text, int(round(_target * 100.0))]


static func finish() -> void:
	if current == null or not is_instance_valid(current):
		current = null
		return
	var w := current
	current = null
	w._fading = true
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := w.create_tween()
	tw.tween_property(w, "modulate:a", 0.0, 0.6)
	tw.tween_callback(w.queue_free)


func _process(delta: float) -> void:
	if _fading:
		return
	var goal := minf(_target + 0.035, 0.985) if _target < 1.0 else 1.0
	progress = move_toward(progress, goal, delta * (0.8 if progress < _target else 0.04))
	_bar.value = progress
	_tip_t += delta
	if _tip_t >= 5.0:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % _tips.size()
		var tw := create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func() -> void: _tip.text = String(_tips[_tip_i]))
		tw.tween_property(_tip, "modulate:a", 1.0, 0.25)
