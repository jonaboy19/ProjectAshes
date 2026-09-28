extends Control
## Touch controls for techniques: four round slots on an outer arc around the
## attack button (bottom right, clear of dodge / block / talk), each with a
## cooldown sweep, a countdown, a dimmed face while the cost can't be paid and
## seal pips for sealed techniques. Tapping an empty slot asks for the skills
## screen. When a sealed technique is tapped, a seal pad of six hand seals
## appears in the middle of the screen with the sequence to tap and a timer.
##
## Wiring (HUD): see the hook lines in the skills report.
##   var tb := preload("res://scripts/ui/technique_buttons.gd").new()
##   tb.caster = player.get_node_or_null("TechniqueCaster")
##   controls.add_child(tb)

signal open_skills_requested

const Skills := preload("res://scripts/sim/skills.gd")
const Caster := preload("res://scripts/actors/technique_caster.gd")
const SLOT_SIZE := 72
## hud.gd places the 128 px attack button at `size - (168, 168)`: its centre sits
## (104, 104) from the bottom-right corner. Slots ring it outside dodge / block / talk.
const ATTACK_CENTER := Vector2(104, 104)
const RING_RADIUS := 252.0
const RING_ANGLES := [0.0, 30.0, 60.0, 90.0]    # degrees: 0 = left of the attack button, 90 = above it
const SEAL_SIZE := 84
const SEAL_COLOR := Color("6d8bff")
const TREE_ICONS := {"swordsmanship": "broadsword", "iaido": "broadsword", "command": "flag-objective",
	"fist_palm": "hand", "shadow": "eye-target"}

var caster: Node
var skills: RefCounted

var _slots: Array[TouchScreenButton] = []
var _glyphs: Array[Label] = []
var _captions: Array[Label] = []
var _shown: Array = []
var _overlay: Control
var _seal_root: Control
var _seal_buttons: Array[TouchScreenButton] = []
var _seal_chips: HBoxContainer
var _seal_title: Label
var _tex_cache := {}
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	for i in Skills.ACTIVE_SLOTS:
		_build_slot(i)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_seal_pad()
	get_viewport().size_changed.connect(_layout)
	_shown.resize(Skills.ACTIVE_SLOTS)
	_shown.fill(null)
	_layout()


func _process(_delta: float) -> void:
	if caster == null or not is_instance_valid(caster):
		caster = _find_caster()
		if caster:
			_bind_caster()
	if skills == null:
		return
	if _shown != skills.loadout:
		_refresh()
	for i in _glyphs.size():
		var id := String(skills.loadout[i]) if i < skills.loadout.size() else ""
		_glyphs[i].modulate.a = 0.15 if id != "" and skills.cooldown_left(id) > 0.0 else 1.0
	_overlay.queue_redraw()
	if _seal_root.visible:
		_update_seal_chips()


func _find_caster() -> Node:
	for p in get_tree().get_nodes_in_group("player"):
		var c := (p as Node).get_node_or_null("TechniqueCaster")
		if c:
			return c
	return null


func _bind_caster() -> void:
	skills = caster.get("skills")
	if caster.has_signal("seals_started"):
		caster.connect("seals_started", _on_seals_started)
		caster.connect("seals_ended", func(_id: String, _ok: bool) -> void: _seal_root.visible = false)
	_refresh()


# --- slots ---------------------------------------------------------------------

func _build_slot(i: int) -> void:
	var b := TouchScreenButton.new()
	var circle := CircleShape2D.new()
	circle.radius = SLOT_SIZE * 0.5
	b.shape = circle
	b.shape_centered = true
	b.pressed.connect(_on_slot.bind(i))
	var glyph := Label.new()
	glyph.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_override("font", UITheme.title_font_weight(700))
	glyph.add_theme_font_size_override("font_size", 22)
	glyph.add_theme_color_override("font_color", UITheme.TEXT)
	glyph.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	glyph.add_theme_constant_override("shadow_outline_size", 4)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(glyph)
	var cap := Label.new()
	cap.size = Vector2(SLOT_SIZE + 40, 18)
	cap.position = Vector2(-20, SLOT_SIZE + 1)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	cap.add_theme_constant_override("shadow_outline_size", 3)
	cap.clip_text = true
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cap)
	add_child(b)
	_slots.append(b)
	_glyphs.append(glyph)
	_captions.append(cap)


func _layout() -> void:
	var s := get_viewport_rect().size
	var c := s - ATTACK_CENTER
	for i in _slots.size():
		var a := deg_to_rad(float(RING_ANGLES[i]))
		var centre := c + Vector2(-cos(a), -sin(a)) * RING_RADIUS
		_slots[i].position = centre - Vector2(SLOT_SIZE, SLOT_SIZE) * 0.5
	_layout_seal_pad()


func slot_centre(i: int) -> Vector2:
	return _slots[i].position + Vector2(SLOT_SIZE, SLOT_SIZE) * 0.5


func _refresh() -> void:
	if skills == null:
		return
	_shown = skills.loadout.duplicate()
	for i in _slots.size():
		var id := String(_shown[i]) if i < _shown.size() else ""
		var b := _slots[i]
		if id == "":
			b.texture_normal = _face(UITheme.ACTION_UTIL.darkened(0.3), "")
			b.texture_pressed = _face(UITheme.ACTION_UTIL, "", true)
			_glyphs[i].text = "+"
			_captions[i].text = ""
			continue
		var def: Dictionary = skills.get_def(id)
		var col: Color = skills.color_of(id)
		var icon_name: String = TREE_ICONS.get(String(def.get("tree", "")), "")
		b.texture_normal = _face(col, icon_name)
		b.texture_pressed = _face(col, icon_name, true)
		_glyphs[i].text = "" if icon_name != "" and UITheme.icon(icon_name) else initials(String(def.get("name", "?")))
		_captions[i].text = String(def.get("name", ""))


func _face(col: Color, icon_name: String, pressed := false) -> Texture2D:
	var key := "%s|%s|%s" % [col.to_html(), icon_name, pressed]
	if not _tex_cache.has(key):
		_tex_cache[key] = UITheme.round_button(SLOT_SIZE, col.darkened(0.15), UITheme.icon(icon_name) if icon_name != "" else null, pressed)
	return _tex_cache[key]


## "Sword Qi Crescent" -> "SQ"; "Ember Orb" -> "EO"; "Quake" -> "Qu".
static func initials(n: String) -> String:
	var words := n.replace("-", " ").split(" ", false)
	if words.size() >= 2:
		return (words[0].left(1) + words[1].left(1)).to_upper()
	return n.left(2)


func _on_slot(i: int) -> void:
	if skills == null or caster == null:
		return
	if String(skills.loadout[i]) == "":
		open_skills_requested.emit()
		return
	caster.call("cast_slot", i, true)


func _draw_overlay() -> void:
	if skills == null:
		return
	for i in _slots.size():
		var id := String(skills.loadout[i]) if i < skills.loadout.size() else ""
		if id == "" or not _slots[i].visible:
			continue
		var c := slot_centre(i)
		var r := SLOT_SIZE * 0.5 - 2.0
		var frac: float = skills.cooldown_fraction(id)
		if frac > 0.0:
			_draw_pie(c, r, frac, Color(0.02, 0.03, 0.06, 0.62))
			var secs: float = skills.cooldown_left(id)
			var txt := "%.1f" % secs if secs < 10.0 else str(int(ceil(secs)))
			_overlay.draw_string_outline(_font, c + Vector2(-SLOT_SIZE * 0.5, 7), txt, HORIZONTAL_ALIGNMENT_CENTER,
				SLOT_SIZE, 20, 4, Color(0, 0, 0, 0.7))
			_overlay.draw_string(_font, c + Vector2(-SLOT_SIZE * 0.5, 7), txt, HORIZONTAL_ALIGNMENT_CENTER, SLOT_SIZE, 20, UITheme.TEXT)
		else:
			var ok: Dictionary = caster.call("can_cast_slot", i) if caster else {"ok": false}
			if not ok.get("ok", false):
				_overlay.draw_circle(c, r, Color(0.05, 0.05, 0.1, 0.5))
				_overlay.draw_arc(c, r, 0.0, TAU, 40, UITheme.DANGER.darkened(0.2), 2.0, true)
			else:
				_overlay.draw_arc(c, r + 1.0, 0.0, TAU, 40, Color(skills.color_of(id), 0.9), 2.0, true)
		# Seal pips along the bottom rim.
		var seals: Array = skills.get_def(id).get("seals", [])
		for k in seals.size():
			var a := PI * 0.5 + (k - (seals.size() - 1) * 0.5) * 0.28
			_overlay.draw_circle(c + Vector2(cos(a), sin(a)) * (r - 6.0), 3.0, UITheme.MAGIC.lightened(0.3))


## Dark pie from 12 o'clock, clockwise, covering `frac` of the circle.
func _draw_pie(c: Vector2, r: float, frac: float, col: Color) -> void:
	var pts := PackedVector2Array([c])
	var steps := maxi(3, int(40 * frac))
	for k in steps + 1:
		var a := -PI * 0.5 + TAU * frac * (k / float(steps))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	_overlay.draw_colored_polygon(pts, col)


# --- seal pad ------------------------------------------------------------------

func _build_seal_pad() -> void:
	_seal_root = Control.new()
	_seal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal_root.visible = false
	add_child(_seal_root)
	var head := VBoxContainer.new()
	head.name = "Head"
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal_root.add_child(head)
	_seal_title = Label.new()
	_seal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seal_title.add_theme_font_override("font", UITheme.title_font_weight(700))
	_seal_title.add_theme_font_size_override("font_size", 22)
	_seal_title.add_theme_color_override("font_color", UITheme.ACCENT)
	_seal_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_seal_title.add_theme_constant_override("shadow_outline_size", 5)
	head.add_child(_seal_title)
	_seal_chips = HBoxContainer.new()
	_seal_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_seal_chips.add_theme_constant_override("separation", 8)
	_seal_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_seal_chips)
	for seal: String in Skills.SEALS:
		var b := TouchScreenButton.new()
		b.texture_normal = UITheme.round_button(SEAL_SIZE, SEAL_COLOR)
		b.texture_pressed = UITheme.round_button(SEAL_SIZE, SEAL_COLOR, null, true)
		var circle := CircleShape2D.new()
		circle.radius = SEAL_SIZE * 0.5
		b.shape = circle
		b.shape_centered = true
		b.pressed.connect(func() -> void:
			if caster:
				caster.call("input_seal", seal))
		var l := Label.new()
		l.text = seal.capitalize()
		l.size = Vector2(SEAL_SIZE, SEAL_SIZE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", UITheme.title_font_weight(700))
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		l.add_theme_constant_override("shadow_outline_size", 4)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
		_seal_root.add_child(b)
		_seal_buttons.append(b)
	_seal_root.draw.connect(_draw_seal_timer)


## A 3 x 2 grid in the middle of the screen, sequence and timer above it.
func _layout_seal_pad() -> void:
	if _seal_root == null:
		return
	var s := get_viewport_rect().size
	var step := SEAL_SIZE + 16.0
	var origin := Vector2(s.x * 0.5 - step * 1.5 + 8.0, s.y * 0.5 - 10.0)
	for k in _seal_buttons.size():
		@warning_ignore("integer_division")
		_seal_buttons[k].position = origin + Vector2((k % 3) * step, (k / 3) * step)
	var head: Control = _seal_root.get_node("Head")
	head.size = Vector2(s.x, 70)
	head.position = Vector2(0, origin.y - 96.0)


func _on_seals_started(id: String, sequence: Array) -> void:
	_seal_title.text = String(skills.get_def(id).get("name", id)) if skills else id
	for c in _seal_chips.get_children():
		c.queue_free()
	for seal: Variant in sequence:
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.text = String(seal).capitalize()
		l.add_theme_font_size_override("font_size", 15)
		chip.add_child(l)
		_seal_chips.add_child(chip)
	_layout_seal_pad()
	_seal_root.visible = true
	_update_seal_chips()


func _update_seal_chips() -> void:
	if caster == null:
		return
	var at := int(caster.call("seal_progress"))
	var chips := _seal_chips.get_children()
	for k in chips.size():
		var chip := chips[k] as PanelContainer
		if chip == null or chip.is_queued_for_deletion():
			continue
		var done := k < at
		var cur := k == at
		chip.add_theme_stylebox_override("panel", UITheme.pill(
			UITheme.OK.darkened(0.55) if done else (UITheme.ACCENT.darkened(0.6) if cur else UITheme.BG),
			UITheme.OK if done else (UITheme.ACCENT if cur else UITheme.STROKE), 12))
	_seal_root.queue_redraw()


func _draw_seal_timer() -> void:
	if caster == null or not _seal_root.visible:
		return
	var head: Control = _seal_root.get_node("Head")
	var w := 260.0
	var frac := clampf(float(caster.call("seal_time_left")) / Caster.SEAL_TIME, 0.0, 1.0)
	var at := Vector2(head.size.x * 0.5 - w * 0.5, head.position.y + head.size.y + 6.0)
	_seal_root.draw_rect(Rect2(at, Vector2(w, 5)), Color(0, 0, 0, 0.5))
	_seal_root.draw_rect(Rect2(at, Vector2(w * frac, 5)), UITheme.MAGIC if frac > 0.3 else UITheme.DANGER)
