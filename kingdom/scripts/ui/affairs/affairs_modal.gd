extends Control
## Base of the small modal dialogs (envoy audience, officer parley, gate prompt): a dimmed full-rect overlay with one framed card
## (title, body, option buttons, result line, close). Pauses the tree while open when `pause_game` (tests turn it off). Esc closes
## unless `can_dismiss` is false (the parley has no cheap way out). Subclasses override _build_options() and call finish().

signal closed

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")

var realm_override: RefCounted = null
var pause_game := true
var can_dismiss := true
var title_text := ""
var body_text := ""
var result_text := ""
var done := false

var _title: Label
var _body: Label
var _result: Label
var _opts: VBoxContainer
var _was_paused := false
var _built := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = AF.theme()


func _ready() -> void:
	if not _built:
		_build()
	if pause_game and is_inside_tree():
		_was_paused = get_tree().paused
		get_tree().paused = true
	refresh()


func hub() -> Variant:
	if realm_override != null:
		return realm_override
	return Life.get("realm") if Life != null else null


func mod(n: String) -> Variant:
	var h: Variant = hub()
	return h.call("mod", n) if h != null else null


func _build() -> void:
	_built = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(620, 0)
	card.add_theme_stylebox_override("panel", AF.panel(Color(0.043, 0.039, 0.035, 0.95), AF.GOLD, 4, 22))
	center.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	_title = Kit.lbl("", 24, AF.GOLD_BRIGHT, true, "title_bold")
	col.add_child(_title)
	col.add_child(AF.separator())
	_body = Kit.lbl("", 17, AF.TEXT, true)
	col.add_child(_body)
	_opts = VBoxContainer.new()
	_opts.add_theme_constant_override("separation", 6)
	col.add_child(_opts)
	_result = Kit.lbl("", 17, AF.GOLD_BRIGHT, true, "italic")
	col.add_child(_result)


func refresh() -> void:
	if not _built:
		_build()
	_compose()
	_title.text = title_text
	_body.text = body_text
	_result.text = result_text
	_result.visible = result_text != ""
	Kit.clear(_opts)
	if done:
		var c := Kit.button("Continue", true, 48, 17)
		c.pressed.connect(close)
		_opts.add_child(c)
	else:
		_build_options(_opts)
		if can_dismiss:
			var l := Kit.button("Not now", false, 44, 15)
			l.pressed.connect(close)
			_opts.add_child(l)


## Subclass: set title_text / body_text.
func _compose() -> void:
	pass


## Subclass: add option buttons to `box`.
func _build_options(_box: VBoxContainer) -> void:
	pass


func option(box: VBoxContainer, text: String, cb: Callable, disabled := false, tip := "") -> Button:
	var b := Kit.button(text, false, 48, 16)
	b.disabled = disabled
	if tip != "":
		b.tooltip_text = tip
	b.pressed.connect(func() -> void:
		cb.call()
		refresh())
	box.add_child(b)
	return b


func finish(text: String) -> void:
	result_text = text
	done = true


func close() -> void:
	if pause_game and is_inside_tree():
		get_tree().paused = _was_paused
	closed.emit()
	queue_free()


func _input(e: InputEvent) -> void:
	if can_dismiss and e is InputEventKey and e.pressed and not e.echo and (e as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func texts(n: Node = null, out: Array = []) -> Array:
	var node: Node = n if n != null else self
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		texts(c, out)
	return out


func find_button(text_part: String, n: Node = null) -> Button:
	var node: Node = n if n != null else self
	if node is Button and (node as Button).text.contains(text_part):
		return node as Button
	for c in node.get_children():
		var r := find_button(text_part, c)
		if r != null:
			return r
	return null
