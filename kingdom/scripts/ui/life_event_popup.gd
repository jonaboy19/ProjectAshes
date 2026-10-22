extends Control
## A small childhood/awakening story card: a title, a paragraph of text and
## 2-3 choices. Used by childhood_events.gd (a moment from growing up) and
## awakening.gd (the age-12 Blessing ceremony). Pauses the game while open,
## like the world map and the inventory screen.
##
##   const LifeEventPopup := preload("res://scripts/ui/life_event_popup.gd")
##   LifeEventPopup.present(hud, {"title": "...", "body": "...",
##       "choices": [["Follow him into the fields.", some_callable], ...]})
##
## (Named `present`, not `show`: Control already has an instance `show()`
## from CanvasItem, and a static method of the same name fails to compile.)
##
## Each choice Callable is called with no arguments when picked, and the card
## closes. A single choice with an empty label list still needs at least one
## entry so the card can be dismissed.

const SELF_PATH := "res://scripts/ui/life_event_popup.gd"
const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")

var _was_paused := false
var _title_label: Label
var _body_label: Label
var _choices: VBoxContainer


## Shows the card as a child of `host` (the HUD layer, or anything that can
## parent a full-rect Control). Reuses one instance per host.
static func present(host: Node, event: Dictionary) -> Control:
	var p: Control = host.get_node_or_null("LifeEventPopup")
	if p == null:
		p = (load(SELF_PATH) as GDScript).new()
		p.name = "LifeEventPopup"
		host.add_child(p)
	if host.has_method("close_menu"):
		host.call("close_menu")
	p.call("open", event)   # was "_open_card", which doesn't exist: no life-event card ever opened
	return p


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AF.theme()
	visible = false
	_build()


func open(event: Dictionary) -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	visible = true
	Audio.play_ui("open")
	_title_label.text = String(event.get("title", "")).to_upper()
	_body_label.text = String(event.get("body", ""))
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	var choices: Array = event.get("choices", [])
	if choices.is_empty():
		choices = [["Go on.", Callable()]]
	for row: Array in choices:
		_choices.add_child(_button(String(row[0]), row[1] as Callable))


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and not e.echo:
		var n := int((e as InputEventKey).physical_keycode) - KEY_1
		if n >= 0 and n < _choices.get_child_count():
			(_choices.get_child(n) as Button).pressed.emit()
			get_viewport().set_input_as_handled()


func _pick(cb: Callable) -> void:
	close()
	if cb.is_valid():
		cb.call()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.016, 0.012, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := AF.panel(Color(0.043, 0.039, 0.035, 0.96), AF.GOLD, 5, 26)
	sb.shadow_size = 24
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(500, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	# Crest ornament over the title, like the event banners.
	var crest := TextureRect.new()
	crest.texture = HudArt.emblem("phoenix")
	crest.custom_minimum_size = Vector2(54, 54)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(crest)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", AF.GOLD_BRIGHT)
	_title_label.add_theme_font_override("font", AF.title_font(700))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title_label)
	col.add_child(AF.separator())
	_body_label = Label.new()
	_body_label.add_theme_font_override("font", AF.font())
	_body_label.add_theme_font_size_override("font_size", 19)
	_body_label.add_theme_color_override("font_color", HudArt.IVORY)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body_label)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	col.add_child(_choices)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "%d.  %s" % [_choices.get_child_count() + 1, text]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 18)
	var rest := AF.row(false)
	rest.bg_color = Color(1, 1, 1, 0.035)
	rest.border_color = Color(AF.GOLD, 0.28)
	rest.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", rest)
	b.add_theme_stylebox_override("hover", AF.row(true))
	b.add_theme_stylebox_override("pressed", AF.row(true))
	b.pressed.connect(_pick.bind(cb))
	return b
