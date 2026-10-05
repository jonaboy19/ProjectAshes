extends Node
## Alert glyphs: a small ? / ! above the head of the few NPCs who are paying attention to the player
## (notice, suspicious -> ?, searching -> ?, alarmed -> !), coloured by class. Cheap by construction:
##  - at most MAX_GLYPHS Sprite3D nodes exist, pooled and re-parented onto whoever is chosen (never one per NPC);
##  - all of them show regions of ONE shared atlas texture with identical flags, so they share one material;
##  - chosen at 4 Hz from the embodied villagers (24 at most) within SHOW_RANGE (25 m); beyond that hidden.
## The pick and the look are static functions (tested without a scene); the node only applies them.

const Perception := preload("res://scripts/population/perception.gd")

const MAX_GLYPHS := 4
const SHOW_RANGE := 25.0
const HZ := 0.25
const CELL := 32
const HEAD_Y := 2.45
const HEAD_Y_CHILD := 2.05

## 5x7 pixel font for the two glyphs.
const BITMAPS := {
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
}
const CELLS := {"?": 0, "!": 1}
const COLORS := [Color(1, 1, 1, 0), Color(0.92, 0.92, 0.88), Color(1.0, 0.86, 0.25), Color(1.0, 0.56, 0.16), Color(1.0, 0.2, 0.16)]

static var _atlas: ImageTexture

var _pool: Array[Sprite3D] = []
var _used := {}                  # person -> Sprite3D
var _acc := 0.0
var shown := 0                   # QA


## What to draw for a Perception.Cls: {} when calm, else {"cell": 0|1, "color": Color, "scale": float}.
static func glyph_for(cls: int) -> Dictionary:
	if cls <= Perception.Cls.CALM:
		return {}
	var bang := cls >= Perception.Cls.ALARMED
	return {"glyph": "!" if bang else "?", "cell": int(CELLS["!" if bang else "?"]), "color": COLORS[clampi(cls, 0, COLORS.size() - 1)],
		"scale": 1.0 + 0.15 * float(cls - 1)}


## Choose who gets a glyph from rows [distance_m, cls, person]: attentive (class >= NOTICE) and within SHOW_RANGE, the most
## alert first, nearest first among equals, at most `max_n`. Returns the chosen rows.
static func pick(rows: Array, max_n := MAX_GLYPHS) -> Array:
	var ok: Array = []
	for r: Array in rows:
		if int(r[1]) >= Perception.Cls.NOTICE and float(r[0]) <= SHOW_RANGE:
			ok.append(r)
	ok.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]):
			return int(a[1]) > int(b[1])
		if float(a[0]) != float(b[0]):
			return float(a[0]) < float(b[0])
		return int(a[2]) < int(b[2]))
	return ok.slice(0, max_n)


## The shared atlas: one white row of CELL x CELL cells ('?' then '!'), dark outline (tinted by the sprite's modulate).
static func atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var img := Image.create(CELL * 2, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for g: String in BITMAPS:
		var ox := int(CELLS[g]) * CELL + 8
		var oy := 4
		var rows: Array = BITMAPS[g]
		var on := {}
		for y in rows.size():
			for x in (rows[y] as String).length():
				if (rows[y] as String)[x] == "#":
					for dy in 3:
						for dx in 3:
							on[Vector2i(ox + x * 3 + dx, oy + y * 3 + dy)] = true
		for p: Vector2i in on:
			for oy2 in range(-2, 3):
				for ox2 in range(-2, 3):
					var q := p + Vector2i(ox2, oy2)
					if not on.has(q) and q.x >= 0 and q.y >= 0 and q.x < CELL * 2 and q.y < CELL:
						img.set_pixelv(q, Color(0.06, 0.05, 0.05, 0.95))
		for p: Vector2i in on:
			img.set_pixelv(p, Color(1, 1, 1, 1))
	_atlas = ImageTexture.create_from_image(img)
	return _atlas


func _make_sprite() -> Sprite3D:
	var sp := Sprite3D.new()
	sp.texture = atlas()
	sp.region_enabled = true
	sp.region_rect = Rect2(0, 0, CELL, CELL)
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.double_sided = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.pixel_size = 0.016
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.visibility_range_end = SHOW_RANGE + 2.0
	return sp


func _process(delta: float) -> void:
	_acc += delta
	if _acc < HZ:
		return
	_acc = 0.0
	refresh()


## Re-pick and re-assign the pooled sprites (4 Hz).
func refresh() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var pl := tree.get_first_node_in_group("player") as Node3D
	var rows: Array = []
	var nodes := {}
	if pl != null:
		for n in tree.get_nodes_in_group("villager"):
			var v := n as Node3D
			if v == null or not v.has_method("alert_class") or bool(v.call("is_indoors")) or not v.visible:
				continue
			var c := int(v.call("alert_class"))
			if c < Perception.Cls.NOTICE:
				continue
			var person := int(v.get("person"))
			rows.append([v.global_position.distance_to(pl.global_position), c, person])
			nodes[person] = v
	var chosen := pick(rows)
	var keep := {}
	for r: Array in chosen:
		keep[int(r[2])] = r
	for person: int in _used.keys():
		if not keep.has(person) or not is_instance_valid(nodes.get(person)):
			_release(person)
	for r: Array in chosen:
		var person := int(r[2])
		var host: Node3D = nodes.get(person)
		if host == null:
			continue
		var sp: Sprite3D = _used.get(person)
		if sp == null:
			sp = _take()
			if sp == null:
				continue
			_used[person] = sp
			if sp.get_parent() != host:
				if sp.get_parent() != null:
					sp.get_parent().remove_child(sp)
				host.add_child(sp)
			sp.position = Vector3(0, HEAD_Y_CHILD if bool(host.get("_child")) else HEAD_Y, 0)
		_style(sp, int(r[1]))
	shown = _used.size()


func _take() -> Sprite3D:
	for sp in _pool:
		if not _used.values().has(sp):
			return sp
	if _pool.size() >= MAX_GLYPHS:
		return null
	var sp := _make_sprite()
	_pool.append(sp)
	return sp


func _release(person: int) -> void:
	var sp: Sprite3D = _used.get(person)
	_used.erase(person)
	if sp != null and sp.get_parent() != null:
		sp.get_parent().remove_child(sp)


func _style(sp: Sprite3D, cls: int) -> void:
	var g := glyph_for(cls)
	if g.is_empty():
		sp.visible = false
		return
	sp.visible = true
	sp.region_rect = Rect2(int(g["cell"]) * CELL, 0, CELL, CELL)
	sp.modulate = g["color"]
	sp.scale = Vector3.ONE * float(g["scale"])


func _exit_tree() -> void:
	for sp in _pool:
		if is_instance_valid(sp):
			sp.queue_free()
	_pool.clear()
	_used.clear()
