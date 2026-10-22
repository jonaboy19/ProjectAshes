class_name WorldMacro
extends RefCounted
## Macro heightmap of Valencious (phase W1 of PA_plans/WORLD_BRIEF.md). WorldGen._raw_height() replaces its noise hills/ridges with
## `sample(x, z)` when `active`; everything else (settlement pads, roads, rivers, lake, stamps) still shapes the result, so
## WorldGen.height() stays the single source of truth.
##   "noise"      (default until W5 sign-off) legacy noise terrain, byte-identical to before.
##   "valencious" data/world/macro/height_16.png (4097 x 4097, 16-bit, 3 m/px, h = -20 + v/65535 * 320), made by tools/world/gen_valencious.py.
## Resolution order (same as TerrainBackend): `override` (tests) -> --world_macro=noise|valencious -> env ASHES_WORLD_MACRO ->
## user://settings.cfg [world] macro -> "noise".
## The PNG is written with filter 0 on every row, so it is decoded here (Godot's own loader would drop it to 8 bits):
## zlib inflate (the IDAT stream as is), then strip the row filter bytes. The 34 MB uint16 buffer stays big-endian; sample() is read-only and thread-safe.

const NOISE := "noise"
const VALENCIOUS := "valencious"
const SETTINGS_PATH := "user://settings.cfg"
const PATH := "res://data/world/macro/height_16.png"
const BIOME_PATH := "res://data/world/macro/biome_ids.png"
const SPLAT_PATH := "res://data/world/macro/splat_weights.png"
const SIZE := 4097
const MPP := 3.0
const HALF := 6144.0
const H_MIN := -20.0
const H_RANGE := 320.0
const BIOME_MPP := 12.0
const BIOME_SIZE := 1024

## Tests set this ("" = off). Not saved.
static var override := ""
static var _cached := ""
## True while WorldGen._raw_height should read the macro (loaded and not suspended).
static var active := false
static var _loaded := false
static var _data := PackedByteArray()      # SIZE * SIZE big-endian uint16
static var _biome := PackedByteArray()     # BIOME_SIZE^2 ids
static var _splat := PackedByteArray()     # BIOME_SIZE^2 * 4 RGBA


static func mode() -> String:
	var want := override
	if want == "":
		if _cached == "":
			_cached = _resolve()
		want = _cached
	return want if want == VALENCIOUS else NOISE


static func wants() -> bool:
	return mode() == VALENCIOUS


static func set_mode(m: String) -> void:
	_cached = VALENCIOUS if m == VALENCIOUS else NOISE
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("world", "macro", _cached)
	cf.save(SETTINGS_PATH)


static func _resolve() -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--world_macro="):
			return a.get_slice("=", 1).strip_edges().to_lower()
	var env := OS.get_environment("ASHES_WORLD_MACRO").strip_edges().to_lower()
	if env != "":
		return env
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		return String(cf.get_value("world", "macro", NOISE)).to_lower()
	return NOISE


## Called by WorldGen.setup on the main thread. Loads once; returns whether the macro is usable.
static func prepare() -> bool:
	if not wants():
		active = false
		return false
	if not _loaded:
		_loaded = _load()
	active = _loaded
	return _loaded


## WorldGen.setup suspends the macro while it places settlements/camps/sites (so positions never depend on it) and resumes it after.
static func suspend() -> void:
	active = false


static func resume() -> void:
	active = _loaded and wants()


static func is_loaded() -> bool:
	return _loaded


static func memory_bytes() -> int:
	return _data.size() + _biome.size() + _splat.size()


static func _load() -> bool:
	var raw := _decode16(PATH)
	if raw.size() != SIZE * SIZE * 2:
		push_warning("WorldMacro: %s missing or wrong size (%d)" % [PATH, raw.size()])
		return false
	_data = raw
	var bi := Image.new()
	if bi.load_png_from_buffer(FileAccess.get_file_as_bytes(BIOME_PATH)) == OK and bi.get_size() == Vector2i(BIOME_SIZE, BIOME_SIZE):
		bi.convert(Image.FORMAT_L8)
		_biome = bi.get_data()
	var si := Image.new()
	if si.load_png_from_buffer(FileAccess.get_file_as_bytes(SPLAT_PATH)) == OK and si.get_size() == Vector2i(BIOME_SIZE, BIOME_SIZE):
		si.convert(Image.FORMAT_RGBA8)
		_splat = si.get_data()
	return true


## Decodes a 16-bit grayscale PNG written with filter type 0 on every row. Returns big-endian uint16 samples, row-major.
static func _decode16(path: String) -> PackedByteArray:
	var f := PackedByteArray()
	if FileAccess.file_exists(path):
		f = FileAccess.get_file_as_bytes(path)
	if f.size() < 64:
		return PackedByteArray()
	var pos := 8
	var idat := PackedByteArray()
	var w := 0
	var h := 0
	while pos + 8 <= f.size():
		var n := (f[pos] << 24) | (f[pos + 1] << 16) | (f[pos + 2] << 8) | f[pos + 3]
		var t := f.slice(pos + 4, pos + 8).get_string_from_ascii()
		if t == "IHDR":
			w = (f[pos + 8] << 24) | (f[pos + 9] << 16) | (f[pos + 10] << 8) | f[pos + 11]
			h = (f[pos + 12] << 24) | (f[pos + 13] << 16) | (f[pos + 14] << 8) | f[pos + 15]
			if f[pos + 16] != 16 or f[pos + 17] != 0:
				return PackedByteArray()
		elif t == "IDAT":
			idat.append_array(f.slice(pos + 8, pos + 8 + n))
		pos += 12 + n
	if w != SIZE or h != SIZE or idat.size() < 7:
		return PackedByteArray()
	var rows := idat.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)   # Godot's DEFLATE mode reads the zlib wrapper
	var stride := 1 + 2 * w
	if rows.size() != stride * h:
		return PackedByteArray()
	var out := PackedByteArray()
	for r in h:
		if rows[r * stride] != 0:
			return PackedByteArray()     # a filtered row: the generator must write filter 0
		out.append_array(rows.slice(r * stride + 1, (r + 1) * stride))
	return out


static func _px(i: int) -> int:
	return (_data[i * 2] << 8) | _data[i * 2 + 1]


## Macro height in metres at world (x, z), bilinear. Clamped at the edge.
static func sample(x: float, z: float) -> float:
	var u := clampf((x + HALF) / MPP, 0.0, SIZE - 1.001)
	var v := clampf((z + HALF) / MPP, 0.0, SIZE - 1.001)
	var iu := int(u)
	var iv := int(v)
	var fu := u - iu
	var fv := v - iv
	var i := iv * SIZE + iu
	var a := lerpf(float(_px(i)), float(_px(i + 1)), fu)
	var b := lerpf(float(_px(i + SIZE)), float(_px(i + SIZE + 1)), fu)
	return H_MIN + lerpf(a, b, fv) / 65535.0 * H_RANGE


## Biome id (0 grass 1 forest 2 meadow 3 farmland 4 marsh 5 highland 6 rift 7 snow) at (x, z); 0 when the map is not loaded.
static func biome_at(x: float, z: float) -> int:
	if _biome.is_empty():
		return 0
	var u := clampi(int(floorf((x + HALF) / BIOME_MPP)), 0, BIOME_SIZE - 1)
	var v := clampi(int(floorf((z + HALF) / BIOME_MPP)), 0, BIOME_SIZE - 1)
	return _biome[v * BIOME_SIZE + u]


## Splat weights (meadow, farmland, marsh, rift ash), each 0..1, bilinear between the 12 m cells; zero when not loaded.
static func splat_at(x: float, z: float) -> Color:
	if _splat.is_empty():
		return Color(0, 0, 0, 0)
	var u := clampf((x + HALF) / BIOME_MPP - 0.5, 0.0, BIOME_SIZE - 1.001)
	var v := clampf((z + HALF) / BIOME_MPP - 0.5, 0.0, BIOME_SIZE - 1.001)
	var iu := int(u)
	var iv := int(v)
	var fu := u - iu
	var fv := v - iv
	var o := (iv * BIOME_SIZE + iu) * 4
	var r := Color(0, 0, 0, 0)
	for c in 4:
		var a0 := lerpf(float(_splat[o + c]), float(_splat[o + 4 + c]), fu)
		var a1 := lerpf(float(_splat[o + BIOME_SIZE * 4 + c]), float(_splat[o + BIOME_SIZE * 4 + 4 + c]), fu)
		r[c] = lerpf(a0, a1, fv) / 255.0
	return r
