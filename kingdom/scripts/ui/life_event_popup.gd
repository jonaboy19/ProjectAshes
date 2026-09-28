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
	p.call("_open_card", event)
	return p


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UITheme.theme()
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


func _pick(cb: Callable) -> void:
	close()
	if cb.is_valid():
		cb.call()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(UITheme.BG_SOLID, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := UITheme.panel_box(18)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", UITheme.ACCENT)
	_title_label.add_theme_font_override("font", UITheme.title_font())
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title_label)
	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.add_theme_color_override("font_color", UITheme.TEXT)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body_label)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	col.add_child(_choices)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 44)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", UITheme.pill(UITheme.SURFACE, UITheme.STROKE, 12))
	b.add_theme_stylebox_override("hover", UITheme.pill(UITheme.SURFACE_HOVER, UITheme.ACCENT.darkened(0.2), 12))
	b.pressed.connect(_pick.bind(cb))
	return b
