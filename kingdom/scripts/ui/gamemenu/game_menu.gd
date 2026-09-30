extends Control
## The in-game tabbed menu (the user's UI templates): one big near-black translucent
## window with a thin gold frame, a top tab bar (Inventory, Character, Skills, Quests,
## Map, Journal, Realm; Q / E cycle, Esc / X close), the tab page in the middle and a key-hint
## bar at the bottom. It pauses the game while open, like the other full screens.
##
## Hotkeys while open: I C F2 J M L jump to a tab (the same key again closes),
## Q / E previous / next tab, Esc, X or Tab close. Each page has its own keys
## (shown in the bottom bar). Touch: every tab, chip and hint is a tappable button.
##
## Open it from the HUD (no class_name, so it also works before a class-cache rescan):
##   const GameMenu := preload("res://scripts/ui/gamemenu/game_menu.gd")
##   GameMenu.open(self, "inventory")      # "character" "skills" "quests" "map" "journal" "realm"
##   GameMenu.toggle(self, "map")

signal closed

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const SELF_PATH := "res://scripts/ui/gamemenu/game_menu.gd"
const DIR := "res://scripts/ui/gamemenu/"
## id, label, jump key, page script.
const TABS := [
	["inventory", "Inventory", KEY_I, "tab_inventory.gd"],
	["character", "Character", KEY_NONE, "tab_character.gd"],
	["skills", "Skills", KEY_F2, "tab_skills.gd"],
	["quests", "Quests", KEY_NONE, "tab_quests.gd"],
	["map", "Map", KEY_M, "tab_map.gd"],
	["journal", "Journal", KEY_NONE, "tab_journal.gd"],
	["realm", "Realm", KEY_NONE, "tab_realm.gd"],
]

## The HUD CanvasLayer this menu lives on (its world_map is hosted by the Map tab).
var hud: CanvasLayer
var tab := "inventory"

var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _body: Control
var _hint_left: HBoxContainer
var _was_paused := false
var _built := false


# ------------------------------------------------------------------ entry points ----

## Opens (creating on first use) the menu on `hud` at a tab. Closes any HUD popup menu.
static func open(hud_layer: CanvasLayer, tab_id := "inventory") -> Control:
	var m: Control = hud_layer.get_node_or_null("GameMenu")
	if m == null:
		m = (load(SELF_PATH) as GDScript).new()
		m.name = "GameMenu"
		m.set("hud", hud_layer)
		hud_layer.add_child(m)
	if hud_layer.has_method("close_menu"):
		hud_layer.call("close_menu")
	m.call("open_tab", tab_id)
	return m


## Opens the menu at `tab_id`, or closes it when it already shows that tab.
static func toggle(hud_layer: CanvasLayer, tab_id := "inventory") -> Control:
	var m: Control = hud_layer.get_node_or_null("GameMenu")
	if m != null and m.visible and String(m.get("tab")) == tab_id:
		m.call("close")
		return m
	return open(hud_layer, tab_id)


static func is_open(hud_layer: CanvasLayer) -> bool:
	var m: Control = hud_layer.get_node_or_null("GameMenu")
	return m != null and m.visible


## Records a finished or failed quest so the Completed / Failed tabs can list it by name
## (the game itself only counts them). state: "done" or "failed". Persisting the log
## needs a Life change (see the report).
static func log_quest(quest: Dictionary, state: String) -> void:
	(load(DIR + "menu_data.gd") as GDScript).call("log_quest", quest, state)


# ---------------------------------------------------------------------- lifecycle ----

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AF.theme()
	visible = false
	_build()


func _build() -> void:
	_built = true
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var win := PanelContainer.new()
	win.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.offset_left = 36
	win.offset_right = -36
	win.offset_top = 18
	win.offset_bottom = -18
	var sb := AF.panel(Color(0.043, 0.039, 0.035, 0.9), AF.GOLD, 4, 14)
	sb.shadow_size = 24
	win.add_theme_stylebox_override("panel", sb)
	add_child(win)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	win.add_child(col)
	# Tab bar: [Q] tabs... [E] [X].
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	col.add_child(bar)
	bar.add_child(_chip("Q", func() -> void: cycle(-1)))
	for t: Array in TABS:
		var b := Button.new()
		b.text = String(t[1])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", AF.title_font(600))
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(open_tab.bind(String(t[0])))
		bar.add_child(b)
		_tab_buttons[String(t[0])] = b
	bar.add_child(_chip("E", func() -> void: cycle(1)))
	bar.add_child(_chip("X", close))
	col.add_child(AF.separator())
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	col.add_child(_body)
	col.add_child(AF.separator())
	# Bottom key-hint bar: page hints on the left, the common ones on the right.
	var foot := HBoxContainer.new()
	foot.custom_minimum_size.y = 50
	foot.add_theme_constant_override("separation", 18)
	col.add_child(foot)
	_hint_left = HBoxContainer.new()
	_hint_left.add_theme_constant_override("separation", 20)
	foot.add_child(_hint_left)
	foot.add_child(Kit.hspacer())
	foot.add_child(Kit.hint("Q/E", "Switch Tab", func() -> void: cycle(1)))
	foot.add_child(Kit.hint("Esc", "Close", close))


func _chip(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 48)
	b.add_theme_font_override("font", AF.title_font(600))
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", Kit.box(Color(0, 0, 0, 0.5), AF.GOLD_DIM, 3, 4))
	b.add_theme_stylebox_override("hover", Kit.box(Color(0.16, 0.12, 0.06, 0.9), AF.GOLD, 3, 4))
	b.add_theme_stylebox_override("pressed", Kit.box(Color(0.24, 0.17, 0.07, 0.95), AF.GOLD_BRIGHT, 3, 4))
	b.add_theme_color_override("font_color", AF.TEXT)
	b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
	b.pressed.connect(cb)
	return b


func _tab_ids() -> Array:
	return TABS.map(func(t: Array) -> String: return String(t[0]))


func _page(id: String) -> Control:
	if _pages.has(id):
		return _pages[id]
	var script_name := ""
	for t: Array in TABS:
		if t[0] == id:
			script_name = String(t[3])
	var p: Control = (load(DIR + script_name) as GDScript).new()
	p.set("menu", self)
	p.visible = false
	_body.add_child(p)
	p.call("build")
	_pages[id] = p
	return p


func _style_tabs() -> void:
	for id: String in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var on := id == tab
		b.add_theme_stylebox_override("normal", AF.row(on, false) if on else Kit.box(Color(0.03, 0.028, 0.025, 0.5), Color(AF.GOLD_DIM, 0.4), 3, 6))
		b.add_theme_stylebox_override("hover", AF.row(on, true))
		b.add_theme_stylebox_override("pressed", AF.row(true, false))
		b.add_theme_stylebox_override("focus", AF.row(on, true))
		for st: String in ["normal", "hover", "pressed", "focus"]:
			var s: StyleBoxFlat = b.get_theme_stylebox(st)
			s.content_margin_left = 6
			s.content_margin_right = 6
		b.add_theme_color_override("font_color", AF.GOLD_BRIGHT if on else AF.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", AF.GOLD_BRIGHT)
		b.add_theme_color_override("font_pressed_color", AF.GOLD_BRIGHT)


## Shows a tab (opening and pausing first when the menu is closed).
func open_tab(tab_id: String) -> void:
	if not _tab_ids().has(tab_id):
		tab_id = "inventory"
	var fresh := not visible
	if fresh:
		_was_paused = get_tree().paused
		get_tree().paused = true
		visible = true
		Audio.play_ui("open")
	var old := tab
	if not fresh and old != tab_id and _pages.has(old):
		(_pages[old] as Control).call("on_hide")
		(_pages[old] as Control).visible = false
	tab = tab_id
	_style_tabs()
	var p := _page(tab_id)
	if fresh or old != tab_id:
		p.visible = true
		p.call("on_show")
		if old != tab_id and not fresh:
			Audio.play_ui("pickup")
	else:
		p.call("refresh")
	rebuild_hints()


func cycle(step: int) -> void:
	var ids := _tab_ids()
	var i := ids.find(tab)
	open_tab(String(ids[posmod(i + step, ids.size())]))


func close() -> void:
	if not visible:
		return
	if _pages.has(tab):
		(_pages[tab] as Control).call("on_hide")
	visible = false
	get_tree().paused = _was_paused
	Audio.play_ui("close")
	closed.emit()


func rebuild_hints() -> void:
	if _hint_left == null or not _pages.has(tab):
		return
	Kit.clear(_hint_left)
	for h: Array in (_pages[tab] as Control).call("hints"):
		_hint_left.add_child(Kit.hint(String(h[0]), String(h[1]), h[2], bool(h[3]) if h.size() > 3 else false))


## Pages tell the menu when shared data changed (the character page redraws its gear).
func notify_changed(what: String) -> void:
	if what == "equipment" and _pages.has("character"):
		var p: Control = _pages["character"]
		if p.visible:
			p.call("refresh")


## Quests tab "Show on Map": switches to the map and centres on a world position.
func show_on_map(pos: Vector2, _group := "") -> void:
	open_tab("map")
	(_pages["map"] as Control).call_deferred("focus_world", pos)


# -------------------------------------------------------------------------- input ----

func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventJoypadButton and e.pressed:
		match (e as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				cycle(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				cycle(1)
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				close()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if not (e is InputEventKey) or not e.pressed:
		return
	var k := e as InputEventKey
	var code := k.keycode
	if k.echo and code not in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return
	get_viewport().set_input_as_handled()
	match code:
		KEY_ESCAPE, KEY_X, KEY_TAB:
			close()
			return
		KEY_Q:
			cycle(-1)
			return
		KEY_E:
			cycle(1)
			return
	if _pages.has(tab) and bool((_pages[tab] as Control).call("handle_key", k)):
		return
	# Tab jumps: I / F2 / M (the same keys that open the menu from the world) and 1-7 in tab order.
	# C, J, L, R and the other combat keys are never menu keys (docs/controls.md).
	var jump := ""
	var by_letter := false
	for t: Array in TABS:
		if int(t[2]) != KEY_NONE and int(t[2]) == code:
			jump = String(t[0])
			by_letter = true
	if jump == "" and code >= KEY_1 and code < KEY_1 + TABS.size():
		jump = String(TABS[code - KEY_1][0])
	if jump != "":
		if jump == tab and by_letter:
			close()          # the opening key again closes, like Tab
		else:
			open_tab(jump)
