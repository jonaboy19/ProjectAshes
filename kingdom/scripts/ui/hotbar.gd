extends Control
## Numbered quick slots along the bottom centre (the user's HUD template): 1-4 are
## the equipped techniques (same data as technique_buttons.gd: icon, cooldown sweep,
## dimmed while the cost cannot be paid), 5-8 are the consumables you carry (bread,
## salves...; icon + count). Tap / click a slot, or press its number key.
##
## Keys 1-4 are also the army order keys (order_follow / hold / charge): while you
## lead soldiers the hotbar ignores 1-4 and leaves them to the orders.

signal open_skills_requested

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")

const SLOTS := 8
const SLOT := 52.0
const GAP := 6.0
const TREE_ICONS := {"swordsmanship": "broadsword", "iaido": "broadsword", "command": "flag-objective",
	"fist_palm": "hand", "shadow": "eye-target"}

var player: Node
var soldiers := 0
var _caster: Node
var _skills: RefCounted
var _consumables: Array = []       # [{id, count}] for slots 5..8
var _sig := ""
var _acc := 0.0
var _slot_box := StyleBoxFlat.new()
var _slot_sel := StyleBoxFlat.new()
var _font: Font
var _press := -1
var _repaint := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(SLOTS * SLOT + (SLOTS - 1) * GAP, SLOT + 16)
	custom_minimum_size = size
	_font = AF.wfont(700)
	_slot_box = AF.panel(Color(0.045, 0.04, 0.036, 0.82), Color(AF.GOLD, 0.5), 5, 0)
	_slot_box.shadow_size = 5
	_slot_sel = AF.panel(Color(0.09, 0.075, 0.05, 0.9), AF.GOLD, 5, 0)
	_slot_sel.shadow_size = 5
	if Life.has_signal("inventory_changed"):
		Life.inventory_changed.connect(func() -> void: _acc = 1.0)


func slot_rect(i: int) -> Rect2:
	return Rect2(Vector2(i * (SLOT + GAP), 12), Vector2(SLOT, SLOT))


func _process(delta: float) -> void:
	_acc += delta
	_repaint += delta
	if _repaint > 0.5 and _sig != "":
		_repaint = 0.0
		queue_redraw()      # icons that were still loading when first drawn
	if _acc < 0.1:
		return
	_acc = 0.0
	if not is_visible_in_tree():
		return
	_bind()
	var parts := PackedStringArray()
	if _skills != null:
		for i in 4:
			var id := String(_skills.loadout[i]) if i < _skills.loadout.size() else ""
			var cd := 0.0
			var ok := true
			if id != "":
				cd = _skills.cooldown_fraction(id)
				var can: Dictionary = _caster.call("can_cast_slot", i) if _caster else {"ok": true}
				ok = bool(can.get("ok", true))
			parts.append("%s:%.2f:%s" % [id, cd, ok])
	_consumables = _find_consumables()
	for c: Dictionary in _consumables:
		parts.append("%s:%d" % [c["id"], c["count"]])
	var sig := "|".join(parts)
	if sig != _sig:
		_sig = sig
		queue_redraw()


func _bind() -> void:
	if _caster != null and is_instance_valid(_caster):
		return
	_caster = null
	_skills = null
	if player and is_instance_valid(player):
		_caster = player.get_node_or_null("TechniqueCaster")
		if _caster:
			_skills = _caster.get("skills")


## Up to four different foods / medicines, medicines first.
func _find_consumables() -> Array:
	var out: Array = []
	var seen := {}
	var heals: Array = []
	var foods: Array = []
	for it in Life.inventory.get_items():
		var id: String = it.get_prototype().get_prototype_id()
		if seen.has(id):
			continue
		seen[id] = true
		var heal := int(Life.item_prop(id, "heal", 0))
		var nutrition := float(Life.item_prop(id, "nutrition", 0.0))
		if heal > 0:
			heals.append({"id": id, "count": Life.count(id)})
		elif nutrition > 0.0:
			foods.append({"id": id, "count": Life.count(id)})
	out.append_array(heals)
	out.append_array(foods)
	return out.slice(0, 4)


func _slot_info(i: int) -> Dictionary:
	if i < 4:
		if _skills == null:
			return {}
		var id := String(_skills.loadout[i]) if i < _skills.loadout.size() else ""
		if id == "":
			return {}
		var def: Dictionary = _skills.get_def(id)
		return {"kind": "tech", "id": id, "name": String(def.get("name", id)),
			"icon": TREE_ICONS.get(String(def.get("tree", "")), ""), "color": _skills.color_of(id)}
	var k := i - 4
	if k < _consumables.size():
		var c: Dictionary = _consumables[k]
		return {"kind": "item", "id": c["id"], "count": c["count"], "name": Life.item_name(String(c["id"]))}
	return {}


func activate(i: int) -> void:
	var info := _slot_info(i)
	if i < 4:
		if _caster == null or _skills == null:
			return
		if info.is_empty():
			open_skills_requested.emit()
		else:
			_caster.call("cast_slot", i, true)
	elif not info.is_empty():
		Game.say(Life.use_item(String(info["id"])))


## Number keys 1-8. Returns true when the key was used.
func handle_key(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var k := int((event as InputEventKey).physical_keycode) - KEY_1
	if k < 0 or k >= SLOTS:
		return false
	if k < 4 and soldiers > 0:
		return false
	activate(k)
	return true


func _gui_input(e: InputEvent) -> void:
	if not e is InputEventScreenTouch:
		return
	var idx := -1
	for i in SLOTS:
		if slot_rect(i).grow(3).has_point(e.position):
			idx = i
	if e.pressed:
		_press = idx
	else:
		if idx >= 0 and idx == _press:
			activate(idx)
			accept_event()
		_press = -1


func _draw() -> void:
	for i in SLOTS:
		var r := slot_rect(i)
		var info := _slot_info(i)
		var has := not info.is_empty()
		draw_style_box(_slot_sel if has else _slot_box, r)
		var centre := r.get_center()
		if has:
			var col: Color = info.get("color", Color(0.6, 0.5, 0.3))
			if info["kind"] == "tech":
				draw_circle(centre, SLOT * 0.36, Color(col, 0.3))
				var res := HudArt.resolve_icon(String(info["icon"]))
				var tex := res[0] as Texture2D
				if tex:
					var s := SLOT * 0.62
					draw_texture_rect(tex, Rect2(centre - Vector2(s, s) * 0.5, Vector2(s, s)), false,
						Color(1, 1, 1, 1) if not res[1] else HudArt.IVORY)
				else:
					var ini := String(info["name"]).left(2)
					draw_string(_font, centre + Vector2(-SLOT * 0.5, 7), ini, HORIZONTAL_ALIGNMENT_CENTER, SLOT, 20, HudArt.IVORY)
				# Cooldown sweep and "cannot afford" dimming.
				var frac: float = _skills.cooldown_fraction(String(info["id"]))
				if frac > 0.0:
					_pie(centre, SLOT * 0.5 - 3.0, frac, Color(0.02, 0.02, 0.04, 0.68))
					var secs: float = _skills.cooldown_left(String(info["id"]))
					var txt := "%.1f" % secs if secs < 10.0 else str(int(ceil(secs)))
					draw_string_outline(_font, centre + Vector2(-SLOT * 0.5, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, SLOT, 16, 4, Color(0, 0, 0, 0.7))
					draw_string(_font, centre + Vector2(-SLOT * 0.5, 6), txt, HORIZONTAL_ALIGNMENT_CENTER, SLOT, 16, HudArt.IVORY)
				else:
					var can: Dictionary = _caster.call("can_cast_slot", i) if _caster else {"ok": true}
					if not bool(can.get("ok", true)):
						draw_rect(r.grow(-2), Color(0.02, 0.02, 0.05, 0.5))
			else:
				var tex := HudArt.item_icon(String(info["id"]))
				draw_circle(centre, SLOT * 0.34, Color(AF.GOLD, 0.12))
				if tex:
					var s := SLOT * 0.66
					draw_texture_rect(tex, Rect2(centre - Vector2(s, s) * 0.5, Vector2(s, s)), false)
				else:
					draw_string(_font, centre + Vector2(-SLOT * 0.5, 8), String(info["name"]).left(1).to_upper(),
						HORIZONTAL_ALIGNMENT_CENTER, SLOT, 24, HudArt.IVORY)
				var n := int(info["count"])
				if n > 1:
					var t := "%d" % n
					draw_string_outline(_font, r.end - Vector2(SLOT - 32.0, 6), t, HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 34.0 + 2.0, 14, 4, Color(0, 0, 0, 0.8))
					draw_string(_font, r.end - Vector2(SLOT - 32.0, 6), t, HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 34.0 + 2.0, 14, HudArt.IVORY)
		# Number under the slot, like the template.
		draw_string(_font, Vector2(r.position.x, r.end.y + 12.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, SLOT, 12,
			Color(HudArt.IVORY, 0.85 if has else 0.45))


func _pie(c: Vector2, r: float, frac: float, col: Color) -> void:
	var pts := PackedVector2Array([c])
	var steps := maxi(3, int(36 * frac))
	for k in steps + 1:
		var a := -PI * 0.5 + TAU * frac * (k / float(steps))
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
