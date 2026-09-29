extends VBoxContainer
## Stacked notification popups on the left edge (the user's template): a dark card
## with a round gold-rimmed icon, a title ("Quest Updated", "Item Acquired", ...) and a
## subtitle. Newest at the bottom, at most MAX_VISIBLE at once, each fades on its own.
##
##   stack.push("item", "Item Acquired", "Fresh Bread x3", "bread")
##
## kinds: quest, item, location, reputation, level, gold, info. `icon` is an item id
## (for "item") or ignored; each kind has its own painted glyph.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const HudArt := preload("res://scripts/ui/hud_art.gd")

const MAX_VISIBLE := 4
const LIFETIME := 4.6
const FADE := 0.55
const CARD_W := 292.0
const CARD_H := 56.0

var _gold_card: Control              # the newest gold card, merged into while fresh
var _gold_total := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)


func push(kind: String, title: String, subtitle := "", icon := "") -> void:
	var card := _make_card(kind, title, subtitle, icon)
	add_child(card)
	# Over the cap: the oldest goes at once.
	var live := get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	while live.size() > MAX_VISIBLE:
		var old: Node = live.pop_front()
		if old == _gold_card:
			_gold_card = null
		old.queue_free()
	var inner: Control = card.get_child(0)
	card.custom_minimum_size.y = 0.0
	inner.modulate.a = 0.0
	inner.position.x = -70.0
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "custom_minimum_size:y", CARD_H, 0.22).set_ease(Tween.EASE_OUT)
	tw.tween_property(inner, "modulate:a", 1.0, 0.25)
	tw.tween_property(inner, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var out := card.create_tween()
	out.tween_interval(LIFETIME)
	out.tween_property(inner, "modulate:a", 0.0, FADE)
	out.tween_property(card, "custom_minimum_size:y", 0.0, 0.2)
	out.tween_callback(func() -> void:
		if card == _gold_card:
			_gold_card = null
		card.queue_free())


## "+N gold": payouts within a couple of seconds add up on one card.
func push_gold(amount: int) -> void:
	if _gold_card and is_instance_valid(_gold_card) and not _gold_card.is_queued_for_deletion() \
			and float(_gold_card.get_meta("age", 99.0)) < 2.5:
		_gold_total += amount
		_gold_card.set_meta("age", 0.0)
		(_gold_card.get_meta("sub") as Label).text = "%+d gold" % _gold_total
		return
	_gold_total = amount
	push("gold", "Gold", "%+d gold" % amount)
	var kids := get_children()
	_gold_card = kids[kids.size() - 1] as Control


func _process(delta: float) -> void:
	if _gold_card and is_instance_valid(_gold_card):
		_gold_card.set_meta("age", float(_gold_card.get_meta("age", 0.0)) + delta)


func clear_all() -> void:
	for c in get_children():
		c.queue_free()
	_gold_card = null


func _make_card(kind: String, title: String, subtitle: String, icon: String) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(CARD_W, CARD_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.clip_contents = false
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2.ZERO
	panel.size = Vector2(CARD_W, CARD_H)
	var sb := HudArt.card_box(0.9, 6)
	sb.content_margin_left = 6
	sb.content_margin_right = 12
	panel.add_theme_stylebox_override("panel", sb)
	wrap.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var ic := Icon.new()
	ic.setup(kind, icon)
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", AF.wfont(700))
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", HudArt.IVORY)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(t)
	var s := Label.new()
	s.text = subtitle
	s.add_theme_font_override("font", AF.font())
	s.add_theme_font_size_override("font_size", 15)
	s.add_theme_color_override("font_color", HudArt.OK_GREEN if kind == "reputation" else (AF.GOLD_BRIGHT if kind == "gold" else AF.TEXT_DIM))
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(s)
	wrap.set_meta("sub", s)
	wrap.set_meta("age", 0.0)
	return wrap


# ------------------------------------------------------------------------------------
class Icon extends Control:
	const AF := preload("res://scripts/ui/ashes_frame.gd")
	const HudArt := preload("res://scripts/ui/hud_art.gd")
	var kind := "info"
	var item := ""

	func setup(k: String, item_id: String) -> void:
		kind = k
		item = item_id
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _ready() -> void:
		HudArt.redraw_soon(self, 0.15)
		HudArt.redraw_soon(self, 0.6)

	func _draw() -> void:
		var c := size * 0.5
		var r := 21.0
		draw_circle(c, r, Color(0.09, 0.075, 0.05, 1.0))
		draw_arc(c, r - 1.0, 0, TAU, 40, AF.GOLD, 2.0, true)
		draw_arc(c, r - 4.0, 0, TAU, 40, Color(AF.GOLD, 0.25), 1.0, true)
		match kind:
			"quest":
				draw_string(AF.wfont(800), c + Vector2(-10, 9), "!", HORIZONTAL_ALIGNMENT_CENTER, 20, 28, AF.GOLD_BRIGHT)
			"item":
				var tex := HudArt.item_icon(item) if item != "" else null
				if tex == null:
					tex = HudArt.icon("inventory")
				if tex:
					draw_texture_rect(tex, Rect2(c - Vector2(15, 15), Vector2(30, 30)), false)
			"location":
				var m := HudArt.emblem("tower_crown")
				if m:
					draw_texture_rect(m, Rect2(c - Vector2(15, 15), Vector2(30, 30)), false)
			"reputation":
				HudArt.draw_crest(self, Rect2(c - Vector2(11, 14), Vector2(22, 28)), HudArt.emblem("oak_tree"), Color("1f4a2b"))
			"level":
				var m := HudArt.emblem("phoenix")
				if m:
					draw_texture_rect(m, Rect2(c - Vector2(16, 16), Vector2(32, 32)), false)
			"gold":
				draw_circle(c, 11.0, AF.GOLD)
				draw_arc(c, 11.0, 0, TAU, 28, AF.GOLD_BRIGHT, 1.6, true)
				draw_arc(c, 7.0, 0, TAU, 24, Color("8a6224"), 1.6, true)
			_:
				HudArt.diamond(self, c, 7.0, AF.GOLD)
