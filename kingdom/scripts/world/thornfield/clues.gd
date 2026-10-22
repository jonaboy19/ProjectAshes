extends RefCounted
## The four clues of "The Spoiled Barley" (data/quests/thornfield/spoiled_barley.json), placed as subtle props around
## the Thornfield Brewery's tithe granary and Hesta's long table. They carry no marker and no glow: a sack that is
## wet on top, boot and paw prints in the mud by the back wall, a forced hasp on the granary door, and a ledger lying
## open on the table. Each one is a Clue interactable (scripts/interaction/kinds/clue.gd) whose Examine fires
## `interact {id}` on the quest bus.
##
##   thornfield/clue/sack    the granary's top sacks, stained and sour
##   thornfield/clue/prints  boot prints (one worn heel) with a dog's paw prints beside them
##   thornfield/clue/lock    the granary hasp, prised off and put back
##   thornfield/clue/ledger  the brewery's count: eleven sacks written off in a different hand
##
## `build(parent)` returns the Clue nodes; tests call `specs()` for the ids and site-local spots.

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const IDS := ["thornfield/clue/sack", "thornfield/clue/prints", "thornfield/clue/lock", "thornfield/clue/ledger"]

## id -> {at: site-local Vector2, height, target, note}
static func specs() -> Dictionary:
	var b := Sites.BARN_DOOR
	return {
		"thornfield/clue/sack": {"at": Sites.BARN_AT + Vector2(2.6, 3.2), "h": 0.0, "target": "Spilled sacks",
			"note": "The top sacks are wet and sour-smelling, the ones underneath clean and dry. Someone has been at them on purpose."},
		"thornfield/clue/prints": {"at": b + Vector2(-2.3, 1.2), "h": 0.0, "target": "Muddy prints",
			"note": "Boot prints, one heel worn down, and a dog's paw prints keeping close beside them. They go in at the granary door and back out again."},
		"thornfield/clue/lock": {"at": b + Vector2(0.9, 0.35), "h": 1.1, "target": "Granary door",
			"note": "The hasp has been prised off and set back almost straight. The screws are fresh-scratched; the lock only looks closed."},
		"thornfield/clue/ledger": {"at": Sites.TABLE_AT + Vector2(0.2, -0.1), "h": 0.92, "target": "Open ledger",
			"note": "Hesta's count, in her hand. A second hand has written off eleven sacks as 'rot' and not initialled it."},
	}


static func build(parent: Node) -> Array:
	var out: Array = []
	var b := Sites.brewery()
	if b.is_empty():
		return out
	var sp := specs()
	for id: String in IDS:
		var s: Dictionary = sp[id]
		var w := Sites.to_world(b, s["at"])
		var y := WorldGen.height(w.x, w.y) + float(s["h"])
		var clue: Node3D = Clue.spawn(parent, Vector3(w.x, y, w.y), id, String(s["note"]), String(s["target"]))
		clue.set_meta("site_local", s["at"])
		_dress(clue, id, float(b["yaw"]))
		out.append(clue)
	return out


## The prop that makes each clue findable by eye. Small, low-contrast, made of simple shapes and a generated decal.
static func _dress(clue: Node3D, id: String, yaw: float) -> void:
	match id:
		"thornfield/clue/sack":
			var mesh: ArrayMesh = Assets.building_mesh("sack_pile")
			if mesh != null:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.scale = Vector3.ONE * 0.55
				mi.rotation.y = yaw + 0.7
				mi.position.y = -0.04
				clue.add_child(mi)
			# a dark wet stain on the ground around the sacks
			clue.add_child(_stain(Color(0.16, 0.13, 0.07, 0.55), 1.1, 0.0))
		"thornfield/clue/prints":
			var d := Decal.new()
			d.size = Vector3(2.4, 1.0, 1.6)
			d.texture_albedo = _prints_texture()
			d.cull_mask = 1
			d.rotation.y = yaw + 0.35
			d.position.y = 0.2
			clue.add_child(d)
		"thornfield/clue/lock":
			clue.add_child(_box(Vector3(0.22, 0.05, 0.12), Color(0.18, 0.16, 0.15), Vector3(0, 0, 0)))          # the hasp plate
			clue.add_child(_box(Vector3(0.09, 0.12, 0.05), Color(0.30, 0.26, 0.20), Vector3(0.08, -0.14, 0.03), 0.5))   # the lock, hanging askew
		"thornfield/clue/ledger":
			clue.add_child(_box(Vector3(0.34, 0.035, 0.24), Color(0.25, 0.14, 0.09), Vector3.ZERO, 0.0, 0.12))
			clue.add_child(_box(Vector3(0.30, 0.02, 0.21), Color(0.86, 0.80, 0.66), Vector3(0, 0.026, 0), 0.0, 0.12))


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _box(size: Vector3, c: Color, at: Vector3, roll := 0.0, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = at
	mi.rotation = Vector3(0.0, yaw, roll)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _stain(c: Color, r: float, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	mi.mesh = q
	mi.material_override = _mat(c)
	mi.position.y = y + 0.02
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _tex: ImageTexture = null


## A 128 x 64 mud-dark print sheet: two boot prints (one with a worn heel) and a trail of small paw prints.
static func _prints_texture() -> ImageTexture:
	if _tex != null:
		return _tex
	var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var ink := Color(0.10, 0.07, 0.04, 0.78)
	_ellipse(img, Vector2(26, 20), Vector2(9, 5), ink)       # sole
	_ellipse(img, Vector2(14, 20), Vector2(4, 3), Color(ink.r, ink.g, ink.b, 0.9))   # worn heel (deeper)
	_ellipse(img, Vector2(52, 40), Vector2(9, 5), ink)
	_ellipse(img, Vector2(40, 40), Vector2(5, 3), Color(ink.r, ink.g, ink.b, 0.5))
	for k in 4:
		var c := Vector2(76 + k * 14, 26 + (k % 2) * 14)
		_ellipse(img, c, Vector2(3.4, 3.0), ink)                                   # pad
		for t in 3:
			_ellipse(img, c + Vector2(-3.5 + t * 3.5, -4.2), Vector2(1.4, 1.7), ink)   # toes
	_tex = ImageTexture.create_from_image(img)
	return _tex


static func _ellipse(img: Image, c: Vector2, r: Vector2, col: Color) -> void:
	for y in range(maxi(0, int(c.y - r.y) - 1), mini(img.get_height(), int(c.y + r.y) + 2)):
		for x in range(maxi(0, int(c.x - r.x) - 1), mini(img.get_width(), int(c.x + r.x) + 2)):
			var d := Vector2((x - c.x) / r.x, (y - c.y) / r.y)
			if d.length_squared() <= 1.0:
				img.set_pixel(x, y, col)
