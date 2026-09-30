extends Control
## CREATE YOUR CHARACTER (the user's template): tabs Appearance / Background / Starting Path /
## Review, a live 3D preview of the chosen character in the middle.
##
##   CharacterCreation.open(parent, func(result: Dictionary) -> void: ...)   # on_done gets the dict below
##   var model := CharacterCreation.build_model(result["appearance"], 1.75)  # the same look, anywhere
##
## The preview uses the modular G6 human (assets/incoming/characters/g6-ual/g6_{m,f}_modular_all):
## real, swappable meshes for HEAD (6 male / 3 female), HAIR (6 / 3, plus bald), BODY = the outfit set,
## with SKIN and HAIR colour tints. COSMETIC ONLY (stored in the result, no mesh yet): Beard,
## Scars, Voice, and the family / birthplace flavour. Beard/scar overlays and voice pitch are for later.
##
## Result dictionary (also stored by the front end in Flow.creation):
##   {given_name, family_name ("" = as born), sex "male"|"female", culture (lore id), birthplace (id),
##    father_trade / mother_trade (WorldSim.JOBS names), paths: [ids],
##    tendencies: {key: delta} (Life.tendencies.nudge_many), appearance: {...see default_appearance()}}
## Back on the first tab just closes the screen (on_done is not called).

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")
const Portrait := preload("res://scripts/ui/portrait.gd")

const G6 := "res://assets/incoming/characters/g6-ual/"
const TABS := ["Appearance", "Background", "Starting Path", "Review"]
const SKINS := [Color("f1d3bb"), Color("e0b48c"), Color("c68f65"), Color("94633f"), Color("5f3d26")]
const HAIR_TINTS := [Color("2a1c14"), Color("5b3a22"), Color("a4743f"), Color("d9b46a"), Color("a63f22")]
const HAIR_TINT_NAMES := ["Black", "Brown", "Chestnut", "Blond", "Ginger"]
const SKIN_NAMES := ["Fair", "Light", "Tan", "Brown", "Dark"]
## Body row = the outfit set: name, armour, boots, gloves mesh suffixes (same names on both sexes).
const OUTFITS := [
	{"name": "Villager Tunic", "armor": "light_armor_2", "boots": "light_boots_2", "gloves": ""},
	{"name": "Worker's Apron", "armor": "light_armor_4", "boots": "light_boots", "gloves": ""},
	{"name": "Hunter's Leathers", "armor": "medium_armor", "boots": "medium_boots", "gloves": "medium_gloves"},
	{"name": "Smith's Leathers", "armor": "light_armor_3", "boots": "light_boots", "gloves": "light_gloves_3"},
	{"name": "Traveller's Gear", "armor": "light_armor", "boots": "light_boots", "gloves": "light_gloves"},
]
const BEARDS := ["Clean-shaven", "Stubble", "Short beard", "Full beard"]
const SCARS := ["None", "Brow", "Cheek", "Eye", "Jaw"]
const VOICES := ["Low", "Medium", "High", "Soft", "Gruff"]
const MALE_HEADS := 6
const FEMALE_HEADS := 3
const MALE_HAIRS := 6
const FEMALE_HAIRS := 3

const BACKGROUNDS := [
	{"id": "farmstead", "name": "Ashford Farmstead", "blurb": "Wheat, mud and early mornings. Your parents work the fields on the village edge.",
		"father": "Farmer", "mother": "Farmer", "nudge": {"farming": 0.06, "compassion": 0.02}},
	{"id": "smithy", "name": "The Smithy on Forge Lane", "blurb": "Soot, hammer-ring and warm iron. Your father shapes the village's tools.",
		"father": "Blacksmith", "mother": "Laborer", "nudge": {"craft": 0.06, "martial": 0.02}},
	{"id": "market", "name": "A Market-Stall Family", "blurb": "You grew up counting coin and haggling in the square.",
		"father": "Merchant", "mother": "Merchant", "nudge": {"trade": 0.06, "scholarship": 0.02}},
	{"id": "woodcutters", "name": "The Woodcutters' Row", "blurb": "Sawdust, axes and the forest always at your back.",
		"father": "Woodcutter", "mother": "Laborer", "nudge": {"wilderness": 0.06, "leadership": 0.01}},
	{"id": "guardhouse", "name": "A Guardsman's Home", "blurb": "Your father walks the wall. You know the watch's songs by heart.",
		"father": "Guard", "mother": "Laborer", "nudge": {"martial": 0.06, "leadership": 0.02}},
]
const PATHS := [
	{"id": "sword", "name": "Sword & Shield", "blurb": "Drills, wooden swords and dreams of the militia.", "nudge": {"martial": 0.12, "leadership": 0.04}},
	{"id": "hearth", "name": "Craft & Hearth", "blurb": "Hands that like to make things.", "nudge": {"craft": 0.12, "farming": 0.03}},
	{"id": "coin", "name": "Coin & Bargains", "blurb": "You count everything twice.", "nudge": {"trade": 0.12, "scholarship": 0.04}},
	{"id": "field", "name": "Field & Furrow", "blurb": "Comfort in dirt under your nails.", "nudge": {"farming": 0.12, "compassion": 0.04}},
	{"id": "wild", "name": "Wild & Woods", "blurb": "The forest edge calls you.", "nudge": {"wilderness": 0.12, "mischief": 0.03}},
	{"id": "faith", "name": "Temple & Tales", "blurb": "The old stories and the temple bell stay with you.", "nudge": {"faith": 0.12, "scholarship": 0.05}},
]

var on_done: Callable
var ap: Dictionary = {}
var given_name := "Ren"
var family_name := ""
var culture := "caldric"
var background := 0
var paths: Array = [0]
var _tab := 0
var _page_holder: Control
var _tab_buttons: Array[Button] = []
var _next: Button
var _back: Button
var _preview: Portrait
var _preview_frame: Control
var _val_labels := {}
var _grid_holder: GridContainer
var _sex_buttons: Array[Button] = []
var _skin_buttons: Array[Button] = []
var _hair_buttons: Array[Button] = []
var _thumb_cells: Array[Button] = []
var _name_edit: LineEdit
var _family_edit: LineEdit
var _culture_label: Label
var _bg_cards: Array[Button] = []
var _path_cards: Array[Button] = []
var _review_label: RichTextLabel
var _cultures: Array = []


static func open(parent: Node, on_done_cb: Callable) -> Control:
	var s: Control = (load("res://scripts/ui/character_creation.gd") as GDScript).new()
	s.on_done = on_done_cb
	s.name = "CharacterCreation"
	parent.add_child(s)
	return s


static func default_appearance(sex := "male") -> Dictionary:
	return {"sex": sex, "head": 0, "hair": 1, "hair_color": 1, "beard": 0, "body": 0, "scars": 0, "voice": 1, "skin": 1}


static func _n_heads(sex: String) -> int:
	return MALE_HEADS if sex == "male" else FEMALE_HEADS


static func _n_hairs(sex: String) -> int:
	return (MALE_HAIRS if sex == "male" else FEMALE_HAIRS) + 1     # +1 for bald


## The chosen character as a rigged, animated model (`height` metres). Cosmetic-only choices do not change it.
static func build_model(look: Dictionary, height := 1.75, keep: Array[String] = []) -> Node3D:
	var sex := String(look.get("sex", "male"))
	var g := "male" if sex == "male" else "female"
	var file := G6 + ("g6_m_modular_all" if sex == "male" else "g6_f_modular_all")
	var model := Assets.mh_character(file, height, keep)
	var head_i := clampi(int(look.get("head", 0)), 0, _n_heads(sex) - 1)
	var hair_i := clampi(int(look.get("hair", 1)), 0, _n_hairs(sex) - 1)
	var outfit: Dictionary = OUTFITS[clampi(int(look.get("body", 0)), 0, OUTFITS.size() - 1)]
	# The model's own texture is a light tan: divide by it so "Light" is the untouched texture.
	var sw: Color = SKINS[clampi(int(look.get("skin", 1)), 0, SKINS.size() - 1)]
	var base: Color = SKINS[1]
	var skin := Color(minf(sw.r / base.r, 1.0), minf(sw.g / base.g, 1.0), minf(sw.b / base.b, 1.0))
	var hair_col: Color = HAIR_TINTS[clampi(int(look.get("hair_color", 1)), 0, HAIR_TINTS.size() - 1)]
	var want := {
		"head_default" if head_i == 0 else "head_%d" % (head_i + 1): "skin",
		"hands_default": "skin", outfit["armor"]: "", outfit["boots"]: "",
	}
	if hair_i > 0:
		want["hair_%d" % hair_i] = "hair"
	if String(outfit["gloves"]) != "":
		want[outfit["gloves"]] = ""
	var prefix := "human_%s_" % g
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not String(m.name).begins_with(prefix):
			continue                          # a held prop (sword, shield), not a body part
		var part := String(m.name).trim_prefix(prefix)
		m.visible = want.has(part)
		if not m.visible:
			continue
		var tint := Color.WHITE
		match String(want[part]):
			"skin": tint = skin
			"hair": tint = hair_col
		if tint != Color.WHITE:
			for si in m.mesh.get_surface_count():
				var mat := m.get_active_material(si)
				if mat is BaseMaterial3D:
					var t := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
					t.albedo_color = tint
					m.set_surface_override_material(si, t)
	return model


# --- screen --------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = AF.theme()
	ap = default_appearance("male")
	for id: String in Life.lore.cultures:
		_cultures.append(id)
	if _cultures.is_empty():
		_cultures = ["caldric"]
	if not _cultures.has(culture):
		culture = String(_cultures[0])
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.016, 0.012, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 36
	frame.offset_right = -36
	frame.offset_top = 24
	frame.offset_bottom = -24
	var sb := AF.panel(Color(0.04, 0.036, 0.032, 0.97), AF.GOLD, 4, 22)
	sb.content_margin_top = 34
	sb.content_margin_bottom = 30
	sb.shadow_size = 30
	frame.add_theme_stylebox_override("panel", sb)
	add_child(frame)
	var orn := Control.new()
	orn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orn.draw.connect(func() -> void: HudArt.draw_ornate_frame(orn, Rect2(Vector2(6, 6), orn.size - Vector2(12, 12)), AF.GOLD, 1.0, 16.0))
	frame.add_child(orn)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)
	var title := Label.new()
	title.text = "CREATE YOUR CHARACTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", AF.wfont(700))
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", HudArt.IVORY)
	col.add_child(title)
	col.add_child(AF.separator())
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 26)
	col.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.custom_minimum_size = Vector2(190, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", AF.wfont(600))
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_show_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	_page_holder = Control.new()
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_holder.clip_contents = true
	col.add_child(_page_holder)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 20)
	col.add_child(foot)
	_back = _foot_button("Back")
	_back.pressed.connect(_on_back)
	foot.add_child(_back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	_next = _foot_button("Next")
	_next.pressed.connect(_on_next)
	foot.add_child(_next)
	_build_preview()
	_show_tab(0)


func _foot_button(text: String) -> Button:
	var b := AF.gold_button(text)
	b.custom_minimum_size = Vector2(190, 44)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _tab_style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(AF.GOLD.r, AF.GOLD.g, AF.GOLD.b, 0.2) if selected else Color(0, 0, 0, 0)
	s.border_color = AF.GOLD if selected else Color(AF.GOLD, 0.0)
	s.set_border_width_all(1)
	s.set_corner_radius_all(18)
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s


func _show_tab(i: int) -> void:
	_tab = i
	for k in _tab_buttons.size():
		var b := _tab_buttons[k]
		b.add_theme_stylebox_override("normal", _tab_style(k == i))
		b.add_theme_stylebox_override("hover", _tab_style(true))
		b.add_theme_stylebox_override("pressed", _tab_style(true))
		b.add_theme_color_override("font_color", AF.GOLD_BRIGHT if k == i else AF.TEXT_DIM)
	if _preview_frame and _preview_frame.get_parent():
		_preview_frame.get_parent().remove_child(_preview_frame)
	for c in _page_holder.get_children():
		_page_holder.remove_child(c)
		c.queue_free()
	_val_labels.clear()
	var page: Control
	match i:
		0: page = _page_appearance()
		1: page = _page_background()
		2: page = _page_paths()
		_: page = _page_review()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_holder.add_child(page)
	_back.text = "Back"
	_next.text = "Begin Life" if i == TABS.size() - 1 else "Next"


func _on_back() -> void:
	if _tab == 0:
		queue_free()
	else:
		_show_tab(_tab - 1)


func _on_next() -> void:
	if _tab < TABS.size() - 1:
		_show_tab(_tab + 1)
		return
	var result := result_dict()
	queue_free()
	if on_done.is_valid():
		on_done.call(result)


## The answer handed to on_done (public so tests / tools can read it without the UI flow).
func result_dict() -> Dictionary:
	var bg: Dictionary = BACKGROUNDS[background]
	var tend := {}
	for k: String in bg["nudge"]:
		tend[k] = float(tend.get(k, 0.0)) + float(bg["nudge"][k])
	var path_ids: Array = []
	for pi: int in paths:
		path_ids.append(PATHS[pi]["id"])
		for k: String in PATHS[pi]["nudge"]:
			tend[k] = float(tend.get(k, 0.0)) + float(PATHS[pi]["nudge"][k])
	return {"given_name": given_name.strip_edges() if given_name.strip_edges() != "" else "Ren",
		"family_name": family_name.strip_edges(), "sex": String(ap["sex"]), "culture": culture,
		"birthplace": String(bg["id"]), "father_trade": String(bg["father"]), "mother_trade": String(bg["mother"]),
		"paths": path_ids, "tendencies": tend, "appearance": ap.duplicate()}


# --- preview -------------------------------------------------------------------------

func _build_preview() -> void:
	_preview_frame = Control.new()
	_preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_frame.gui_input.connect(_preview_input)
	_preview = Portrait.new()
	_preview.setup(Vector2i(760, 640), "half", true)
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_frame.add_child(_preview)
	_preview.yaw_deg = -14.0
	_refresh_preview()


func _preview_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_preview.spin_to(_preview.yaw_deg + e.relative.x * 0.6)
	elif e is InputEventScreenDrag:
		_preview.spin_to(_preview.yaw_deg + e.relative.x * 0.6)


func _refresh_preview() -> void:
	var yaw := _preview.yaw_deg
	_preview.set_model(build_model(ap, 1.75))
	_preview.spin_to(yaw)


func _changed(rebuild_thumbs := false) -> void:
	_refresh_preview()
	for k: String in _val_labels:
		_val_labels[k].text = _value_text(k)
	for i in _sex_buttons.size():
		_sex_buttons[i].button_pressed = (i == 0) == (ap["sex"] == "male")
	for i in _skin_buttons.size():
		_skin_buttons[i].queue_redraw()
	for i in _hair_buttons.size():
		_hair_buttons[i].queue_redraw()
	if rebuild_thumbs and _grid_holder:
		_fill_grid()
	_mark_thumbs()


func _value_text(key: String) -> String:
	var sex := String(ap["sex"])
	match key:
		"head": return "Face %d / %d" % [int(ap["head"]) + 1, _n_heads(sex)]
		"hair": return "Bald" if int(ap["hair"]) == 0 else "Style %d / %d" % [int(ap["hair"]), _n_hairs(sex) - 1]
		"beard": return BEARDS[int(ap["beard"])] if sex == "male" else "-"
		"body": return OUTFITS[int(ap["body"])]["name"]
		"scars": return SCARS[int(ap["scars"])]
		"voice": return VOICES[int(ap["voice"])]
	return ""


func _count_of(key: String) -> int:
	var sex := String(ap["sex"])
	match key:
		"head": return _n_heads(sex)
		"hair": return _n_hairs(sex)
		"beard": return BEARDS.size() if sex == "male" else 1
		"body": return OUTFITS.size()
		"scars": return SCARS.size()
		"voice": return VOICES.size()
	return 1


func _step(key: String, dir: int) -> void:
	ap[key] = posmod(int(ap[key]) + dir, _count_of(key))
	_changed()


func _randomize() -> void:
	var sex := String(ap["sex"])
	ap["head"] = randi() % _n_heads(sex)
	ap["hair"] = randi() % _n_hairs(sex)
	ap["hair_color"] = randi() % HAIR_TINTS.size()
	ap["skin"] = randi() % SKINS.size()
	ap["body"] = randi() % OUTFITS.size()
	ap["beard"] = randi() % _count_of("beard")
	ap["scars"] = randi() % SCARS.size()
	ap["voice"] = randi() % VOICES.size()
	_changed(true)


func _set_sex(sex: String) -> void:
	if ap["sex"] == sex:
		_changed()
		return
	var keep := {"skin": ap["skin"], "hair_color": ap["hair_color"], "body": ap["body"], "voice": ap["voice"]}
	ap = default_appearance(sex)
	for k: String in keep:
		ap[k] = keep[k]
	_changed(true)


# --- pages ---------------------------------------------------------------------------

func _page_appearance() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	# Left: sex toggle and the selector rows.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	var sexes := HBoxContainer.new()
	sexes.add_theme_constant_override("separation", 10)
	left.add_child(sexes)
	_sex_buttons.clear()
	for s: String in ["Male", "Female"]:
		var b := Button.new()
		b.text = s
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(140, 40)
		b.button_pressed = (s == "Male") == (ap["sex"] == "male")
		b.add_theme_stylebox_override("normal", AF.slot(false))
		b.add_theme_stylebox_override("hover", AF.slot(true))
		b.add_theme_stylebox_override("pressed", AF.row(true))
		b.pressed.connect(_set_sex.bind(s.to_lower()))
		sexes.add_child(b)
		_sex_buttons.append(b)
	left.add_child(Control.new())
	for def: Array in [["Head", "head", false], ["Hair", "hair", false], ["Beard", "beard", true], ["Body", "body", false],
			["Scars", "scars", true], ["Voice", "voice", true]]:
		left.add_child(_selector(def[0], def[1], def[2]))
	# Middle: the preview.
	row.add_child(_preview_frame)
	# Right: face presets, skin, hair colour, randomize.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(290, 0)
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(_caption("Face presets"))
	_grid_holder = GridContainer.new()
	_grid_holder.columns = 3
	_grid_holder.add_theme_constant_override("h_separation", 10)
	_grid_holder.add_theme_constant_override("v_separation", 10)
	right.add_child(_grid_holder)
	_fill_grid()
	right.add_child(_caption("Skin tone"))
	right.add_child(_swatches(SKINS, "skin", _skin_buttons))
	right.add_child(_caption("Hair colour"))
	right.add_child(_swatches(HAIR_TINTS, "hair_color", _hair_buttons))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	var rnd := Button.new()
	rnd.text = "Randomize"
	rnd.custom_minimum_size = Vector2(0, 42)
	rnd.focus_mode = Control.FOCUS_NONE
	rnd.add_theme_stylebox_override("normal", AF.slot(false))
	rnd.add_theme_stylebox_override("hover", AF.slot(true))
	rnd.pressed.connect(_randomize)
	right.add_child(rnd)
	return row


func _plain(t: String, size := 18, col := AF.TEXT_DIM) -> Label:
	var l := AF.label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _caption(t: String) -> Label:
	var l := AF.label(t, 15, AF.TEXT_DIM)
	l.add_theme_font_override("font", AF.wfont(600))
	return l


func _selector(label: String, key: String, cosmetic: bool) -> Control:
	var r := HBoxContainer.new()
	r.custom_minimum_size = Vector2(0, 44)
	r.add_theme_constant_override("separation", 6)
	var name_l := _plain(label, 18, HudArt.IVORY)
	name_l.custom_minimum_size = Vector2(72, 0)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(name_l)
	r.add_child(_arrow("◀", _step.bind(key, -1)))
	var v := AF.label(_value_text(key), 16, AF.GOLD_BRIGHT if not cosmetic else AF.TEXT_DIM)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.clip_text = true
	_val_labels[key] = v
	r.add_child(v)
	r.add_child(_arrow("▶", _step.bind(key, 1)))
	if cosmetic:
		r.tooltip_text = "Cosmetic only for now: saved with your character, no model change yet."
	return r


func _arrow(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(38, 38)
	b.add_theme_stylebox_override("normal", AF.slot(false))
	b.add_theme_stylebox_override("hover", AF.slot(true))
	b.add_theme_stylebox_override("pressed", AF.row(true))
	b.pressed.connect(cb)
	return b


func _swatches(colors: Array, key: String, store: Array[Button]) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	store.clear()
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 34)
		b.focus_mode = Control.FOCUS_NONE
		for st: String in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var col: Color = colors[i]
		var idx := i
		b.draw.connect(func() -> void:
			var sel := int(ap[key]) == idx
			b.draw_rect(Rect2(Vector2(2, 2), b.size - Vector2(4, 4)), col)
			b.draw_rect(Rect2(Vector2(1, 1), b.size - Vector2(2, 2)), AF.GOLD_BRIGHT if sel else Color(AF.GOLD, 0.35), false, 2.0 if sel else 1.0))
		b.pressed.connect(func() -> void:
			ap[key] = idx
			_changed(key == "skin"))
		h.add_child(b)
		store.append(b)
	return h


## Six face presets: head + hair pairs, each a small live render of that face.
func _presets() -> Array:
	var sex := String(ap["sex"])
	var out: Array = []
	if sex == "male":
		for i in 6:
			out.append({"head": i, "hair": i + 1})
	else:
		for i in 6:
			out.append({"head": i % 3, "hair": [1, 2, 3, 3, 1, 2][i]})
	return out


func _fill_grid() -> void:
	for c in _grid_holder.get_children():
		_grid_holder.remove_child(c)
		c.queue_free()
	_thumb_cells.clear()
	var presets := _presets()
	for i in presets.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(88, 88)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_contents = true
		for st: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var p := Portrait.new()
		p.setup(Vector2i(176, 200), "face", false)
		p.yaw_deg = -10.0
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var look := ap.duplicate()
		look["head"] = presets[i]["head"]
		look["hair"] = presets[i]["hair"]
		b.add_child(p)
		p.set_model(build_model(look, 1.75))
		var idx := i
		b.draw.connect(func() -> void:
			var on := int(ap["head"]) == int(presets[idx]["head"]) and int(ap["hair"]) == int(presets[idx]["hair"])
			b.draw_rect(Rect2(Vector2.ZERO, b.size), AF.GOLD_BRIGHT if on else Color(AF.GOLD, 0.4), false, 2.0 if on else 1.0))
		b.pressed.connect(func() -> void:
			ap["head"] = presets[idx]["head"]
			ap["hair"] = presets[idx]["hair"]
			_changed())
		_grid_holder.add_child(b)
		_thumb_cells.append(b)


func _mark_thumbs() -> void:
	for b in _thumb_cells:
		b.queue_redraw()


func _page_background() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 40)
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	top.add_child(_plain("First name"))
	_name_edit = LineEdit.new()
	_name_edit.text = given_name
	_name_edit.max_length = 14
	_name_edit.custom_minimum_size = Vector2(190, 38)
	_name_edit.text_changed.connect(func(t: String) -> void: given_name = t)
	top.add_child(_name_edit)
	top.add_child(_plain("Family name"))
	_family_edit = LineEdit.new()
	_family_edit.text = family_name
	_family_edit.placeholder_text = "as born"
	_family_edit.max_length = 16
	_family_edit.custom_minimum_size = Vector2(190, 38)
	_family_edit.text_changed.connect(func(t: String) -> void: family_name = t)
	top.add_child(_family_edit)
	top.add_child(_plain("Culture"))
	top.add_child(_arrow("◀", _step_culture.bind(-1)))
	_culture_label = _plain(_culture_name(), 18, AF.GOLD_BRIGHT)
	_culture_label.custom_minimum_size = Vector2(120, 0)
	_culture_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_culture_label)
	top.add_child(_arrow("▶", _step_culture.bind(1)))
	v.add_child(AF.heading("Where were you born?", 20))
	var hint := AF.label("You start life as a child of four in Ashford. Your family shapes the first years: what your parents do, and what you grow up around.", 16, AF.TEXT_DIM, true)
	v.add_child(hint)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	_bg_cards.clear()
	for i in BACKGROUNDS.size():
		var b := _card(BACKGROUNDS[i], "%s / %s" % [BACKGROUNDS[i]["father"], BACKGROUNDS[i]["mother"]])
		var idx := i
		b.pressed.connect(func() -> void:
			background = idx
			for k in _bg_cards.size():
				_bg_cards[k].button_pressed = k == idx
				_bg_cards[k].queue_redraw())
		b.button_pressed = i == background
		grid.add_child(b)
		_bg_cards.append(b)
	return v


func _culture_name() -> String:
	var c: Dictionary = Life.lore.culture(culture)
	return String(c.get("name", culture.capitalize()))


func _step_culture(dir: int) -> void:
	var i := _cultures.find(culture)
	culture = String(_cultures[posmod(i + dir, _cultures.size())])
	_culture_label.text = _culture_name()


func _card(d: Dictionary, sub: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ""
	b.add_theme_stylebox_override("normal", AF.slot(false))
	b.add_theme_stylebox_override("hover", AF.slot(true))
	b.add_theme_stylebox_override("pressed", AF.row(true))
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 14
	inner.offset_top = 8
	inner.offset_right = -12
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 2)
	var t := AF.label(String(d["name"]), 19, AF.GOLD_BRIGHT)
	t.add_theme_font_override("font", AF.wfont(700))
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(t)
	var bl := AF.label(String(d["blurb"]), 15, HudArt.IVORY)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(bl)
	var s := AF.label(sub, 13, AF.TEXT_DIM, true)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(s)
	b.add_child(inner)
	return b


func _page_paths() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(AF.heading("Starting path", 22))
	v.add_child(AF.label("What were you drawn to as a small child? Pick up to two. These are only nudges: what you actually do in the years ahead matters more.", 16, AF.TEXT_DIM, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	_path_cards.clear()
	for i in PATHS.size():
		var b := _card(PATHS[i], ", ".join(PATHS[i]["nudge"].keys()).replace("_", " ") + " leaning")
		var idx := i
		b.button_pressed = paths.has(i)
		b.pressed.connect(func() -> void:
			if paths.has(idx):
				paths.erase(idx)
			else:
				paths.append(idx)
				if paths.size() > 2:
					paths.pop_front()
			for k in _path_cards.size():
				_path_cards[k].button_pressed = paths.has(k))
		grid.add_child(b)
		_path_cards.append(b)
	return v


func _page_review() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.add_child(_preview_frame)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(AF.heading("Review", 22))
	_review_label = RichTextLabel.new()
	_review_label.bbcode_enabled = true
	_review_label.fit_content = false
	_review_label.scroll_active = false
	_review_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_review_label.add_theme_font_override("normal_font", AF.font())
	_review_label.add_theme_font_size_override("normal_font_size", 18)
	_review_label.add_theme_color_override("default_color", HudArt.IVORY)
	right.add_child(_review_label)
	_review_label.text = _review_text()
	return row


func _review_text() -> String:
	var r := result_dict()
	var sex := String(ap["sex"])
	var gold := "#%s" % AF.GOLD_BRIGHT.to_html(false)
	var dim := "#%s" % Color(0.8, 0.76, 0.66).to_html(false)
	var lines: Array[String] = []
	lines.append("[font_size=26][color=%s]%s %s[/color][/font_size]" % [gold, r["given_name"], r["family_name"] if r["family_name"] != "" else "(family as born)"])
	lines.append("[color=%s]%s  ·  %s culture[/color]" % [dim, sex.capitalize(), _culture_name()])
	lines.append("")
	lines.append("[color=%s]Appearance[/color]  Face %d, %s hair, %s skin, %s" % [gold, int(ap["head"]) + 1,
		"no" if int(ap["hair"]) == 0 else HAIR_TINT_NAMES[int(ap["hair_color"])].to_lower(), SKIN_NAMES[int(ap["skin"])].to_lower(), OUTFITS[int(ap["body"])]["name"]])
	lines.append("[color=%s]Cosmetic only[/color]  %s, scars: %s, voice: %s" % [dim, BEARDS[int(ap["beard"])].to_lower() if sex == "male" else "no beard",
		SCARS[int(ap["scars"])].to_lower(), VOICES[int(ap["voice"])].to_lower()])
	lines.append("")
	var bg: Dictionary = BACKGROUNDS[background]
	lines.append("[color=%s]Born into[/color]  %s (father: %s, mother: %s)" % [gold, bg["name"], String(bg["father"]).to_lower(), String(bg["mother"]).to_lower()])
	var pn: Array[String] = []
	for pi: int in paths:
		pn.append(PATHS[pi]["name"])
	lines.append("[color=%s]Drawn to[/color]  %s" % [gold, ", ".join(pn) if not pn.is_empty() else "nothing in particular"])
	lines.append("")
	lines.append("[color=%s]You begin as a child of four in Ashford.[/color]" % dim)
	return "\n".join(lines)
