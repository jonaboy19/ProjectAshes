class_name MarketGoods
extends RefCounted
## Market goods kit (CC0 Quaternius Fantasy Props MegaKit + Ultimate Food, re-authored by
## tools/blender/make_market_goods.py into ONE glb with a shared warm-painted atlas).
##
## Pieces are composed at load time into a few "dressing" meshes, one surface each (one draw per
## batch): stall themes (counter goods + hanging goods + ground goods in front), the crate/sack stacks
## that stand beside a stall, and the shop-front sets for townhouses. SettlementBuilder instances them
## per neighbourhood with _multimesh_cells(); nothing here collides.
##
## Stall frame (Godot, metres): origin at the stall's ground centre, +Z toward the customer (street),
## +X to the right when facing the customer. Counter top y = 0.9 (z 0.18 .. 0.93); the awning's front
## beam is at z = 1.13, y = 1.92. Shop-front frame: origin at the house's front wall foot, +Z out
## toward the street, X along the facade.

const GLB := "res://assets/market_goods/market_goods.glb"
const ATLAS := "res://assets/market_goods/market_goods_atlas.png"

## Stall themes in the order SettlementBuilder cycles them.
const THEMES := ["produce", "bakery", "pottery", "fish", "apothecary", "tools"]
const SHOPS := ["shop_greengrocer", "shop_potter", "shop_general", "shop_apothecary"]
## Footprints (stall-local x0, x1, z0, z1) SettlementBuilder tests against doors and lanes.
const FRONT_RECT := Rect2(-1.75, 1.15, 3.5, 0.8)   # ground goods in front of the awning
const SIDE_HALF := Vector2(0.55, 0.7)              # a side stack's half extents (x, z)
const SIDE_X := 2.3                                # its centre distance from the stall centre
const SHOP_HALF := Vector2(0.8, 0.5)               # a shop-front set's half extents (x, z)
const SHOP_X := 2.3                                # lateral offset from the door line
const SHOP_Z := 0.55                               # depth from the front wall

static var _pieces := {}       # name -> ArrayMesh (one surface, no material)
static var _material: StandardMaterial3D
static var _cache := {}        # id -> ArrayMesh
static var _loaded := false


## QA switch for before/after shots and benches: `-- --no-goods` builds the towns without the extra goods.
static var _off := OS.get_cmdline_user_args().has("--no-goods")


static func available() -> bool:
	return not _off and ResourceLoader.exists(GLB) and ResourceLoader.exists(ATLAS)


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = load(ATLAS)
		_material.vertex_color_use_as_albedo = true          # COLOR_0 = baked per-piece colour (linear)
		_material.roughness = 0.88
		_material.metallic_specular = 0.25
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_material.resource_name = "MarketGoods"
	return _material


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not available():
		return
	var inst: Node = Assets.scene(GLB).instantiate()
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh:
			_pieces[String(mi.name)] = mi.mesh
	inst.free()


static func piece(piece_name: String) -> Mesh:
	_load()
	return _pieces.get(piece_name)


static func piece_names() -> Array:
	_load()
	return _pieces.keys()


## One composed mesh (one surface, shared material) for a layout id; null if the kit is missing.
static func layout(id: String) -> ArrayMesh:
	if _cache.has(id):
		return _cache[id]
	_load()
	var items: Array = _layout_items(id)
	if items.is_empty() or _pieces.is_empty():
		_cache[id] = null
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for it: Array in items:
		var m: Mesh = _pieces.get(String(it[0]))
		if m == null:
			push_warning("MarketGoods: layout %s uses a missing piece '%s'" % [id, it[0]])
			continue
		var pos := Vector3(it[1], it[2], it[3])
		var yaw := deg_to_rad(float(it[4]))
		var sc: float = it[5] if it.size() > 5 else 1.0
		var pitch := deg_to_rad(float(it[6])) if it.size() > 6 else 0.0
		var roll := deg_to_rad(float(it[7])) if it.size() > 7 else 0.0
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll) * Basis.from_scale(Vector3.ONE * sc)
		st.append_from(m, 0, Transform3D(basis, pos))
	st.generate_normals()
	var out := st.commit()
	out.surface_set_material(0, material())
	_cache[id] = out
	return out


static func tri_count(id: String) -> int:
	var m := layout(id)
	if m == null:
		return 0
	return m.surface_get_array_index_len(0) / 3


# ---------------------------------------------------------------------------------------------
# Layout tables. Item = [piece, x, y, z, yaw_deg, scale = 1, pitch_deg = 0, roll_deg = 0].

const CT := 0.9      # counter top


static func _layout_items(id: String) -> Array:
	var full := not id.ends_with("_lite")
	var base := id.replace("_lite", "")
	match base:
		"stall_produce":
			return _stall_produce(full)
		"stall_bakery":
			return _stall_bakery(full)
		"stall_pottery":
			return _stall_pottery(full)
		"stall_fish":
			return _stall_fish(full)
		"stall_apothecary":
			return _stall_apothecary(full)
		"stall_tools":
			return _stall_tools(full)
		"side_a":
			return _side_a()
		"side_b":
			return _side_b()
		"shop_greengrocer":
			return _shop_greengrocer()
		"shop_potter":
			return _shop_potter()
		"shop_general":
			return _shop_general()
		"shop_apothecary":
			return _shop_apothecary()
	return []


static func _stall_produce(full: bool) -> Array:
	var a: Array = [
		# back row of the counter
		["cabbage", -1.30, CT, 0.30, 20], ["cabbage", -0.90, CT, 0.27, 75], ["pumpkin", 0.95, CT, 0.30, 10], ["pumpkin", 1.32, CT, 0.30, 140, 0.9],
		["crate_carrots", 0.05, CT, 0.36, 0, 0.85],
		# front lip: fruit piles
		["tomato", -1.40, CT, 0.80, 0], ["tomato", -1.25, CT, 0.84, 40], ["tomato", -1.33, CT + 0.09, 0.80, 90],
		["orange", 0.50, CT, 0.82, 0], ["orange", 0.66, CT, 0.80, 0], ["orange", 0.58, CT + 0.11, 0.81, 0],
		["apple_green", 1.15, CT, 0.80, 0], ["apple_green", 1.30, CT, 0.84, 0], ["apple_red", 1.22, CT + 0.12, 0.81, 0],
		# hanging from the awning beam: bunches of sausages and a chicken leg pair
		["sausage_hang", -0.55, 1.75, 1.08, 0], ["sausage_hang", -0.40, 1.75, 1.08, 20], ["sausage_hang", -0.25, 1.75, 1.08, 0],
		["lantern_hang", 1.35, 1.75, 1.08, 0, 0.8],
	]
	if full:
		a += [
			["crate_apples", -1.05, 0.0, 1.55, 8], ["crate_apples", -1.05, 0.245, 1.55, -6], ["crate_carrots", -0.25, 0.0, 1.55, 172],
			["barrel_apples", 0.75, 0.0, 1.5, 0], ["sack_grain", 1.45, 0.0, 1.45, 30, 0.9],
			["pumpkin", -0.55, 0.0, 1.95, 30], ["cabbage", 0.25, 0.0, 1.95, 60], ["apple_red", 0.05, 0.0, 1.9, 0],
		]
	return a


static func _stall_bakery(full: bool) -> Array:
	var a: Array = [
		["bread_round", -1.30, CT, 0.32, 0], ["bread_round", -0.95, CT, 0.30, 30], ["bread_round", 0.92, CT, 0.30, 60],
		["bread", -0.40, CT, 0.34, 90], ["bread", -0.05, CT, 0.32, 80], ["bread", 0.30, CT, 0.34, 100], ["bread", 1.30, CT, 0.34, 95],
		["cheese_round", 1.05, CT, 0.72, 0], ["cheese_round", 1.05, CT + 0.09, 0.72, 25], ["cheese_wedge", 1.38, CT, 0.76, 60],
		["cheese_wedge", 0.72, CT, 0.80, 210], ["jar", -1.45, CT, 0.78, 0], ["jar", -1.15, CT, 0.82, 0],
		["plate", 0.0, CT, 0.76, 0], ["bread", 0.0, CT + 0.03, 0.76, 45, 0.8],
		["wine_bottle", -0.65, CT, 0.80, 0], ["wine_bottle", -0.5, CT, 0.84, 0],
		["sausage_hang", -1.0, 1.75, 1.08, 0], ["sausage_hang", -0.85, 1.75, 1.08, 15], ["sausage_hang", -0.7, 1.75, 1.08, 0],
		["sausage_hang", 0.5, 1.75, 1.08, 20], ["sausage_hang", 0.65, 1.75, 1.08, 0],
	]
	if full:
		a += [
			["sack_grain", -1.10, 0.0, 1.5, 15], ["sack_grain", -0.55, 0.0, 1.55, -20, 0.95], ["sack_grain", -0.80, 0.0, 1.95, 60, 0.8],
			["crate_empty", 0.35, 0.0, 1.55, 0], ["bread_round", 0.25, 0.245, 1.55, 0], ["bread_round", 0.5, 0.245, 1.55, 40],
			["bucket_wood", 1.15, 0.0, 1.5, 0], ["barrel_apples", 1.6, 0.0, 1.4, 0, 0.9],
		]
	return a


static func _stall_pottery(full: bool) -> Array:
	var a: Array = [
		["vase_tall", -1.35, CT, 0.34, 0, 0.9], ["vase_tall", 1.35, CT, 0.34, 40, 0.9], ["jar", -0.95, CT, 0.32, 0], ["jar", 0.95, CT, 0.32, 50],
		["pot_iron", 0.0, CT, 0.34, 0, 0.9], ["mug", -0.65, CT, 0.80, 0, 0.8], ["mug", -0.40, CT, 0.82, 120, 0.8], ["mug", 0.45, CT, 0.80, 200, 0.8],
		["mug", 0.70, CT, 0.82, 260, 0.8], ["plate", -0.1, CT, 0.78, 0, 0.9], ["chalice", 1.0, CT, 0.80, 0], ["chalice", 1.2, CT, 0.84, 0],
		["candlestick", -1.32, CT, 0.80, 30, 0.9],
		["lantern_hang", -0.6, 1.75, 1.08, 0, 0.8], ["lantern_hang", 0.7, 1.75, 1.08, 0, 0.8],
	]
	if full:
		a += [
			["vase_big", -1.15, 0.0, 1.55, 0], ["vase_big", -0.40, 0.0, 1.7, 90, 0.85], ["vase_tall", 0.30, 0.0, 1.55, 0], ["vase_tall", 0.75, 0.0, 1.65, 0, 0.85],
			["cauldron", 1.35, 0.0, 1.5, 0, 0.9], ["bucket_metal", -1.7, 0.0, 1.35, 0],
		]
	return a


static func _stall_fish(full: bool) -> Array:
	var a: Array = [
		["fish", -1.20, CT, 0.76, 6], ["fish", -0.68, CT, 0.72, -8], ["fish", -0.15, CT, 0.78, 10], ["fish", 0.38, CT, 0.72, -4],
		["fish", 0.90, CT, 0.76, 8], ["fish", 1.30, CT, 0.70, -12],
		["bucket_wood", -1.38, CT, 0.30, 0], ["bucket_wood", 1.34, CT, 0.30, 90], ["crate_empty", 0.0, CT, 0.34, 0, 0.9],
		["fish", -0.12, CT + 0.2, 0.34, 20], ["fish", 0.15, CT + 0.2, 0.36, -25],
		["fish_hang", -1.1, 1.72, 1.08, 0], ["fish_hang", -0.85, 1.72, 1.08, 30], ["fish_hang", -0.6, 1.72, 1.08, 0],
		["fish_hang", 0.4, 1.72, 1.08, 20], ["fish_hang", 0.65, 1.72, 1.08, 0], ["fish_hang", 0.9, 1.72, 1.08, 35],
		["rope_coil", 1.4, 1.4, 1.08, 90, 0.5, 90],
	]
	if full:
		a += [
			["bucket_wood", -1.10, 0.0, 1.5, 0], ["bucket_wood", -0.55, 0.0, 1.6, 40], ["crate_empty", 0.2, 0.0, 1.55, 0], ["fish", 0.1, 0.245, 1.55, 15], ["fish", 0.38, 0.245, 1.6, -30],
			["barrel_apples", 1.15, 0.0, 1.5, 0, 0.9], ["bucket_metal", 1.75, 0.0, 1.4, 0], ["rope_coil", -1.6, 0.0, 1.9, 0, 1.0],
		]
	return a


static func _stall_apothecary(full: bool) -> Array:
	var a: Array = [
		["potion_b", -1.35, CT, 0.30, 0], ["potion_b", -1.15, CT, 0.32, 40], ["potion_c", -0.90, CT, 0.30, 0], ["potion_a", -0.70, CT, 0.32, 90],
		["bottle", 0.95, CT, 0.30, 0], ["bottle", 1.15, CT, 0.32, 60], ["potion_c", 1.38, CT, 0.30, 0],
		["bottles_row", 0.1, CT, 0.30, 0], ["book_stack_a", -0.40, CT, 0.62, 20, 0.9], ["books_small_a", 0.45, CT, 0.58, 160],
		["scroll", 0.0, CT, 0.80, 15], ["scroll", 0.55, CT, 0.84, -10], ["candle_a", -1.30, CT, 0.80, 0], ["candle_b", -1.10, CT, 0.82, 0],
		["candlestick", 1.20, CT, 0.80, 200], ["candle_a", 0.95, CT, 0.84, 0],
		["lantern_hang", -0.55, 1.75, 1.08, 0, 0.8], ["lantern_hang", 0.7, 1.75, 1.08, 0, 0.8],
	]
	if full:
		a += [
			["crate_wood", -1.1, 0.0, 1.55, 5, 0.75], ["book_stack_b", -1.1, 0.68, 1.55, 30, 0.9], ["pouch", -0.45, 0.0, 1.55, 30],
			["sack_grain", 0.35, 0.0, 1.5, 10, 0.85], ["crate_wood", 1.15, 0.0, 1.55, -8, 0.7], ["potion_b", 1.15, 0.65, 1.55, 0],
			["bucket_wood", 1.65, 0.0, 1.4, 0],
		]
	return a


static func _stall_tools(full: bool) -> Array:
	var a: Array = [
		["axe", -1.20, CT, 0.62, 80, 1.0, 90], ["axe", -0.70, CT, 0.66, 100, 1.0, 90], ["pickaxe", 0.05, CT, 0.72, 90, 0.9, 90],
		["bucket_metal", 1.15, CT, 0.34, 0], ["bucket_metal", 1.42, CT, 0.34, 40, 0.9], ["rope_coil", -1.35, CT, 0.30, 0, 0.8],
		["rope_coil", 0.6, CT, 0.32, 60, 0.7], ["torch", 0.9, CT, 0.78, 20, 1.0, 90], ["candlestick", -0.4, CT, 0.32, 0, 0.9],
		["pouch", 0.3, CT, 0.30, 15], ["mug", -0.1, CT, 0.32, 200, 0.8],
		["lantern_hang", -0.6, 1.75, 1.08, 0, 0.8], ["rope_coil", 0.6, 1.4, 1.08, 0, 0.5, 90], ["lantern_hang", 1.0, 1.75, 1.08, 0, 0.8],
	]
	if full:
		a += [
			["shield", -1.15, 0.28, 1.35, 15, 1.0, -78], ["shield", -0.35, 0.28, 1.4, -20, 0.9, -78], ["cauldron", 0.5, 0.0, 1.6, 0, 0.9],
			["bucket_metal", 1.15, 0.0, 1.5, 0], ["crate_wood", 1.7, 0.0, 1.4, 0, 0.7], ["pickaxe", 1.3, 0.55, 1.95, 60, 1.0, -68],
		]
	return a


# Stacks that stand just beside a stall's posts (built for the +X side).
static func _side_a() -> Array:
	return [
		["crate_wood", 0.0, 0.0, 0.0, 12, 0.85], ["crate_wood", 0.05, 0.78, 0.0, -10, 0.75], ["crate_apples", 0.05, 1.5, 0.0, 30, 0.7],
		["sack_grain", -0.15, 0.0, 0.78, 20, 0.9], ["pumpkin", 0.25, 0.0, 0.7, 0], ["barrel_apples", 0.05, 0.0, -0.75, 0, 0.9],
	]


static func _side_b() -> Array:
	return [
		["barrel_apples", 0.0, 0.0, 0.05, 0, 0.9], ["bucket_wood", 0.05, 0.0, 0.85, 0], ["sack_grain", -0.1, 0.0, -0.75, -30, 0.85],
		["crate_carrots", 0.25, 0.0, 0.5, 90, 0.7],
	]


# Shop-front sets against a townhouse facade (built for the +X side of the door).
static func _shop_greengrocer() -> Array:
	return [
		["crate_apples", -0.35, 0.0, 0.10, 4], ["crate_carrots", 0.45, 0.0, 0.05, -4, 0.85], ["crate_apples", -0.30, 0.245, 0.10, -8],
		["pumpkin", 0.10, 0.0, 0.45, 20], ["cabbage", -0.55, 0.0, 0.50, 50, 0.9], ["pumpkin", 0.62, 0.0, 0.48, 100, 0.85],
		["apple_red", 0.30, 0.0, 0.55, 0], ["orange", 0.42, 0.0, 0.58, 0],
	]


static func _shop_potter() -> Array:
	return [
		["vase_big", -0.5, 0.0, 0.15, 0, 0.9], ["vase_tall", 0.05, 0.0, 0.1, 0, 0.9], ["jar", 0.45, 0.0, 0.2, 0], ["vase_tall", 0.62, 0.0, 0.45, 40, 0.75],
		["jar", -0.25, 0.0, 0.5, 30], ["bucket_wood", -0.65, 0.0, 0.5, 0, 0.8],
	]


static func _shop_general() -> Array:
	return [
		["sack_grain", -0.5, 0.0, 0.12, 20], ["sack_grain", -0.05, 0.0, 0.1, -25, 0.85], ["crate_wood", 0.5, 0.0, 0.1, 4, 0.8],
		["rope_coil", 0.45, 0.68, 0.1, 0, 0.7], ["bucket_metal", -0.45, 0.0, 0.55, 0], ["stool", 0.15, 0.0, 0.55, 30, 0.9],
	]


static func _shop_apothecary() -> Array:
	return [
		["crate_wood", -0.4, 0.0, 0.12, 0, 0.8], ["potion_b", -0.55, 0.68, 0.1, 0], ["potion_a", -0.3, 0.68, 0.12, 0], ["books_small_b", -0.42, 0.68, 0.3, 40, 0.8],
		["crate_empty", 0.4, 0.0, 0.1, 0, 0.9], ["candle_b", 0.25, 0.22, 0.1, 0], ["bottles_row", 0.55, 0.22, 0.2, 0],
		["sack_grain", 0.1, 0.0, 0.55, 40, 0.8], ["pouch", 0.6, 0.0, 0.55, 0],
	]
