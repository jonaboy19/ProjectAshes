extends "res://scripts/ui/gamemenu/gm_tab.gd"
## AFFAIRS: the lord's desk (game menu tab). Four sub-views, each a standalone panel in scripts/ui/affairs/:
##   Treasury   the ledger, scheduled payments, warnings, steward and audit
##   Followers  what each follower wants; requests, orders, your actions
##   Court      cases, evidence, filing, appeal, influence
##   Letters    the weekly digest and urgent word, with envoys at the door
## Opened by rebindable actions (menu_treasury, menu_followers, menu_court, menu_letters; see Game.KEYS) through
## TabAffairs.open_view(hud, "treasury"), or from the Pack menu tab bar. The page only reads module getters and calls the player's
## own actions; nothing here ticks.

const VIEWS := [["treasury", "Treasury", "res://scripts/ui/affairs/treasury_panel.gd"],
	["followers", "Followers", "res://scripts/ui/affairs/followers_will_panel.gd"],
	["court", "Court", "res://scripts/ui/affairs/court_panel.gd"],
	["letters", "Letters", "res://scripts/ui/affairs/letters_panel.gd"]]
const GM_PATH := "res://scripts/ui/gamemenu/game_menu.gd"

var view := "treasury"
var realm_override: RefCounted = null
var panels: Dictionary = {}
var _seg: HBoxContainer
var _stack: Control


## Opens the Affairs tab of the game menu on a sub-view (toggles closed when already there).
static func open_view(hud: CanvasLayer, which: String) -> void:
	var gm: GDScript = load(GM_PATH)
	var m: Control = hud.get_node_or_null("GameMenu")
	if m != null and m.visible and String(m.get("tab")) == "affairs":
		var p: Variant = m.call("_page", "affairs")
		if p != null and String(p.get("view")) == which:
			m.call("close")
			return
	var menu: Control = gm.call("open", hud, "affairs")
	var page: Variant = menu.call("_page", "affairs")
	if page != null:
		page.call("set_view", which)


func build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_seg = HBoxContainer.new()
	_seg.add_theme_constant_override("separation", 8)
	col.add_child(_seg)
	_stack = Control.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_stack)
	for v: Array in VIEWS:
		var p: Control = (load(String(v[2])) as GDScript).new()
		p.set("realm_override", realm_override)
		p.set("menu", menu)
		p.visible = false
		_stack.add_child(p)
		p.call("build")
		panels[String(v[0])] = p
	_style_seg()


func set_view(which: String) -> void:
	if not panels.has(which):
		return
	if panels.has(view):
		(panels[view] as Control).call("on_hide")
		(panels[view] as Control).visible = false
	view = which
	(panels[view] as Control).visible = true
	(panels[view] as Control).call("on_show")
	_style_seg()
	hints_changed()


func _style_seg() -> void:
	Kit.clear(_seg)
	for v: Array in VIEWS:
		var id := String(v[0])
		var label := String(v[1])
		if id == "letters" and panels.has(id):
			var n := int((panels[id] as Control).call("unread_count"))
			if n > 0:
				label += "  (%d)" % n
		var b := Kit.tab_button(label, id == view, set_view.bind(id), 150)
		_seg.add_child(b)


func on_show() -> void:
	if panels.has(view):
		(panels[view] as Control).visible = true
		(panels[view] as Control).call("on_show")
	_style_seg()


func on_hide() -> void:
	if panels.has(view):
		(panels[view] as Control).call("on_hide")
	_style_seg()


func refresh() -> void:
	if panels.has(view):
		(panels[view] as Control).call("refresh")
	_style_seg()


func handle_key(e: InputEventKey) -> bool:
	if e.keycode == KEY_LEFT or e.keycode == KEY_RIGHT:
		var i := 0
		for k in VIEWS.size():
			if VIEWS[k][0] == view:
				i = k
		set_view(String(VIEWS[posmod(i + (1 if e.keycode == KEY_RIGHT else -1), VIEWS.size())][0]))
		return true
	return false


func hints() -> Array:
	return [["Left/Right", "Switch Desk", func() -> void: handle_key(_key(KEY_RIGHT))]]


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	return e
