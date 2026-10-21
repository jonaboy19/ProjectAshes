extends Control
## Shared base of the "Affairs" panels (treasury, followers' will, court, letters). A panel only READS module getters and calls the
## player's own actions; it never ticks anything and never runs per frame. It is rebuilt on open, after each action, and from the
## menu when the tab is shown. Functional, themed with ashes_frame + gm_kit; visual polish is for the local PC session.
##   realm_override   tests / other hosts may inject a hub; otherwise Life.realm is used.
##   _fill(box)       subclass: add the page content to `box`.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const EMPTY := "Nothing to show yet."

var realm_override: RefCounted = null
var status_line := ""
## The GameMenu that hosts this panel (null in tests / when used standalone).
var menu: Control = null

var _status: Label
var _box: VBoxContainer
var _built := false
var _confirm := ""


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	if not _built:
		build()
	refresh()


func build() -> void:
	if _built:
		return
	_built = true
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_status = Kit.lbl("", 16, AF.GOLD_BRIGHT, true, "italic")
	_status.visible = false
	root.add_child(_status)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 12
	root.add_child(sc)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	sc.add_child(_box)


func on_show() -> void:
	refresh()


func on_hide() -> void:
	pass


func hints() -> Array:
	return []


func handle_key(_e: InputEventKey) -> bool:
	return false


func refresh() -> void:
	if not _built:
		build()
	_confirm = ""
	_redraw()


func _redraw() -> void:
	Kit.clear(_box)
	if hub() == null:
		_box.add_child(Kit.lbl(EMPTY, 17, AF.TEXT_DIM, true, "italic"))
		return
	_fill(_box)


func _fill(_b: VBoxContainer) -> void:
	pass


# ------------------------------------------------------------------ data access

func hub() -> Variant:
	if realm_override != null:
		return realm_override
	return Life.get("realm") if Life != null else null


func mod(n: String) -> Variant:
	var h: Variant = hub()
	return h.call("mod", n) if h != null else null


func today() -> int:
	return int(WorldSim.day)


## Nearest settlement id to the player (0 when there is no player), for filing cases and the like.
func here_sid() -> int:
	return player_sid()


static func player_sid() -> int:
	var pp := Vector2.ZERO
	var pl: Variant = Life.get("player") if Life != null else null
	if pl is Node3D and is_instance_valid(pl):
		pp = Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	var s: Dictionary = WorldGen.nearest_settlement(pp)
	return maxi(0, WorldGen.settlements.find(s)) if not s.is_empty() else 0


func follower_name(fid: String) -> String:
	var fo: Variant = mod("followers")
	if fo == null:
		return fid
	return String((fo.call("get_follower", fid) as Dictionary).get("name", fid))


# ------------------------------------------------------------------ words, not numbers

## Picks one of `words` for a 0..1 value (five words = five bands).
static func fuzzy(v: float, words: Array) -> String:
	var i := clampi(int(floor(clampf(v, 0.0, 0.999) * float(words.size()))), 0, words.size() - 1)
	return String(words[i])


static func nice(id: String) -> String:
	var s := id
	for pre: String in ["k:", "f:", "fo:", "i:", "ch:", "org:", "ss:", "t:", "tr:"]:
		if s.begins_with(pre):
			s = s.substr(pre.length())
			break
	return s.replace("_", " ").capitalize()


# ------------------------------------------------------------------ widgets

func _sec(text: String) -> void:
	_box.add_child(Kit.section(text))


func _txt(b: Container, text: String, color := AF.TEXT, size := 16, style := "body") -> Label:
	var l := Kit.lbl(text, size, color, true, style)
	b.add_child(l)
	return l


func _dim(b: Container, text: String) -> void:
	_txt(b, text, AF.TEXT_DIM, 15, "italic")


func _card(parent: Container) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(Kit.framed(v))
	return v


func _flow(parent: Container) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(f)
	return f


## A button that runs `cb` then redraws the panel. `cb` returns a status string (or nothing).
func _btn(parent: Container, text: String, cb: Callable, primary := false, disabled := false) -> Button:
	var b := Kit.button(text, primary, 44, 15)
	b.disabled = disabled
	b.pressed.connect(func() -> void:
		var r: Variant = cb.call()
		if r is String and String(r) != "":
			say(String(r))
		_redraw())
	parent.add_child(b)
	return b


func _chip(parent: Container, text: String, on: bool, cb: Callable) -> Button:
	var b := Kit.tab_button(text, on, func() -> void:
		cb.call()
		_redraw())
	parent.add_child(b)
	return b


## Two-step button for things that cannot be undone: the first press arms it, the second does it.
func _danger(parent: Container, key: String, text: String, cb: Callable, disabled := false) -> Button:
	var armed := _confirm == key
	var b := Kit.button(("Confirm: " + text) if armed else text, false, 44, 15)
	b.disabled = disabled
	if armed:
		b.add_theme_color_override("font_color", Kit.BAD)
	b.pressed.connect(func() -> void:
		if _confirm != key:
			_confirm = key
			_redraw()
			return
		_confirm = ""
		var r: Variant = cb.call()
		if r is String and String(r) != "":
			say(String(r))
		_redraw())
	parent.add_child(b)
	return b


func say(text: String) -> void:
	status_line = text
	if _status != null:
		_status.text = text
		_status.visible = text != ""


## Every label and button text under this panel (tests, and a cheap "did it populate" check).
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
