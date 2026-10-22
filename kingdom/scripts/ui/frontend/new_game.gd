extends "res://scripts/ui/frontend/screen.gd"
## New Game: mode cards (left) + preview panel (right) + gold Start Game button, then
## character creation (if present) and the loading screen.

const Flow := preload("res://scripts/ui/frontend/flow.gd")
const LoadingScreen := preload("res://scripts/ui/frontend/loading_screen.gd")

const MODES := [
	{"id": "story", "name": "Story Mode", "short": "A guided experience with key stories.", "icon": "conversation", "bg": "new_game",
		"long": "Experience a rich, living world with guided stories, meaningful choices, and emergent events.",
		"points": ["Authored story threads that bend to your deeds", "Gentle difficulty with helpful guidance", "Every career and every ending stays open"]},
	{"id": "sandbox", "name": "Sandbox Mode", "short": "Create your own story.", "icon": "hand", "bg": "loading",
		"long": "No fixed plot. Pick a trade, build a home, gather a household and rise or fall on your own terms.",
		"points": ["Freedom to live any life the world allows", "Relaxed needs and forgiving economy", "Ideal for building, trading and exploring"]},
	{"id": "survival", "name": "Survival Mode", "short": "Harsher world, limited resources.", "icon": "broadsword", "bg": "settings",
		"long": "A harsher world with limited resources. Hunger, cold and wounds are real, and the roads are deadly after dark.",
		"points": ["Needs, weather and injuries matter", "Scarce coin, dangerous wilderness", "Autosave only on entering settlements"]},
	{"id": "custom", "name": "Custom", "short": "Adjust all settings.", "icon": "checked-shield", "bg": "splash",
		"long": "Tune the rules of your world: difficulty, danger, economy, ageing and more, then begin your life.",
		"points": ["Choose your own difficulty and danger", "Set the pace of the economy and seasons", "Rules can be changed later in Settings"]},
]

var _idx := 0
var _cards: Array[Button] = []
var _img: TextureRect
var _title: Label
var _desc: Label
var _points: VBoxContainer
var _group := ButtonGroup.new()


static func open(parent: Node) -> Control:
	var s: Variant = load("res://scripts/ui/frontend/new_game.gd").new()
	parent.add_child(s)
	return s


func _ready() -> void:
	add_backdrop("new_game", 0.55)
	var mc := margin_box(36)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	mc.add_child(col)
	col.add_child(FE.header("New Game", back))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 22)
	col.add_child(row)
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(360, 0)
	list.add_theme_constant_override("separation", 10)
	row.add_child(list)
	for i in MODES.size():
		var c := _card(MODES[i], i)
		list.add_child(c)
		_cards.append(c)
	# Preview panel.
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", AF.panel(AF.PANEL, AF.GOLD_DIM, 4, 16))
	row.add_child(pc)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pc.add_child(pv)
	_img = TextureRect.new()
	_img.custom_minimum_size = Vector2(0, 250)
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_img.clip_contents = true
	pv.add_child(_img)
	_title = Label.new()
	_title.add_theme_font_override("font", AF.wfont(600))
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", AF.TEXT)
	pv.add_child(_title)
	_desc = AF.label("", 19, AF.TEXT_DIM)
	pv.add_child(_desc)
	_points = VBoxContainer.new()
	_points.add_theme_constant_override("separation", 4)
	pv.add_child(_points)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(fill)
	var start := FE.gold_btn("Start Game", _start, 260)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.custom_minimum_size = Vector2(300, 54)
	pv.add_child(start)
	if not Flow.is_mobile():
		var h := FE.key_hints([["↑↓", "Choose mode"], ["Enter", "Select"], ["Esc", "Back"]])
		col.add_child(h)
	_select(0)
	FE.fade_in(self, 0.3)
	_cards[0].call_deferred("grab_focus")


func _card(m: Dictionary, i: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _group
	b.custom_minimum_size = Vector2(0, 92)
	b.focus_mode = Control.FOCUS_ALL
	var n := AF.panel(Color(0.04, 0.036, 0.03, 0.86), AF.GOLD_DIM, 3, 12)
	n.shadow_size = 0
	var s := AF.panel(Color(0.5, 0.36, 0.13, 0.28), AF.GOLD, 3, 12)
	s.shadow_size = 0
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", s)
	for st: String in ["pressed", "focus", "hover_pressed"]:
		b.add_theme_stylebox_override(st, s)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -10
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ic := TextureRect.new()
	ic.texture = FE.icon(String(m["icon"]))
	ic.custom_minimum_size = Vector2(46, 46)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.modulate = AF.GOLD_BRIGHT
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var t := Label.new()
	t.text = String(m["name"])
	t.add_theme_font_override("font", AF.wfont(600))
	t.add_theme_font_size_override("font_size", 21)
	t.add_theme_color_override("font_color", AF.TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := AF.label(String(m["short"]), 15, AF.TEXT_DIM)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	b.focus_entered.connect(_select.bind(i))
	b.pressed.connect(_select.bind(i))
	return b


func _select(i: int) -> void:
	_idx = i
	var m: Dictionary = MODES[i]
	if not _cards[i].button_pressed:
		_cards[i].set_pressed_no_signal(true)
	_title.text = String(m["name"])
	_desc.text = String(m["long"])
	var tex: Texture2D = null
	for ext: String in [".png", ".jpg", ".webp"]:
		var p: String = AF.BG_DIR + String(m["bg"]) + ext
		if ResourceLoader.exists(p):
			tex = load(p)
			break
	_img.texture = tex
	for c in _points.get_children():
		c.queue_free()
	for pt: String in m["points"]:
		var l := AF.label("◆  " + pt, 16, AF.TEXT)
		_points.add_child(l)


func _start() -> void:
	Flow.mode = String(MODES[_idx]["id"])
	Flow.creation = {}
	Flow.pending_load = ""
	Flow.reset_world_state(get_tree())
	FE.play("open")
	if Flow.character_creation_available():
		var cc: GDScript = load(Flow.CHAR_CREATION)
		cc.call("open", self, _on_created)
	else:
		_on_created({})


func _on_created(choices: Dictionary) -> void:
	Flow.creation = choices
	# Life began its default life at boot; overlay the player's choices on it now.
	var life := get_tree().root.get_node_or_null("Life")
	if life and life.has_method("apply_creation"):
		life.call("apply_creation", choices)
	LoadingScreen.open(self)
