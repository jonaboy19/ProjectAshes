extends Control
## Painted parchment layer for the world map (Region 1, the Ashford Vale). Drop-in for the H6 `add_layer()` extension point
## (docs/regions/HOOKS_FOR_CLOUD.md). It draws the baked hand-painted map (assets/ui/maps/region1_parchment.png, made from the REAL
## WorldGen data by tools_qa/map/paint_parchment.gd) UNDER the map's own icons, and a painterly fog of war over the undiscovered parts.
##
##   var layer := preload("res://scripts/ui/map_parchment_layer.gd").new()
##   world_map.add_layer(layer)              # once, after the map exists
##   layer.fog_enabled = false               # show the whole painted map (debug / "Reveal" toggle)
##   layer.enabled = false                   # fall back to the map's own terrain
##
## Memory: one 2048x2048 texture. The .import must be VRAM compressed (compress/mode=2, high_quality=false = ETC2 on mobile):
## ~2.8 MB with mipmaps, under the 4 MB budget. The fog is a 256x256 RGBA image (256 KB). Call release() when the map closes
## to drop the texture reference (it is reloaded from the cache on the next open).
##
## The map must expose: to_screen(Vector2) and a redraw on paint. The layer itself never draws in its own _draw; the map calls
## paint_under(map) from inside its own _draw so the parchment stays pixel-locked to the icons while panning.

signal changed

const TEX_PATH := "res://assets/ui/maps/region1_parchment.png"
const META_PATH := "res://assets/ui/maps/region1_parchment.json"
const FOG_RES := 256
const FOG_PAPER := Color(0.93, 0.85, 0.66)
const FOG_INK := Color(0.42, 0.29, 0.14)

## Master switch: false = the map draws its own terrain again.
var enabled := true : set = set_enabled
## Fog of war over places the player has not discovered (uses the map's own discovery fog field).
var fog_enabled := true : set = set_fog_enabled
## The parchment carries the place names (poster names), so the map skips its own name labels while this is on.
var bakes_labels := true
## Overall fog strength 0..1.
var fog_strength := 1.0

var _tex: Texture2D
var _meta: Dictionary = {}
var _origin := Vector2(-4096, -4096)     # world metres of the terrain rect's top-left corner
var _ppm := 0.2285
var _margin := 88.0
var _img_size := Vector2(2048, 2048)
var _fog_tex: ImageTexture
var _fog_src: Image
var _map: Control
var _noise: FastNoiseLite
var _loaded := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ZERO
	size = Vector2.ZERO


## Called by world_map.add_layer().
func bind_map(m: Control) -> void:
	_map = m
	m.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # the 2048 px sheet is shown minified


func set_enabled(v: bool) -> void:
	enabled = v
	_request_redraw()
	changed.emit()


func set_fog_enabled(v: bool) -> void:
	fog_enabled = v
	_request_redraw()
	changed.emit()


func toggle_fog() -> bool:
	fog_enabled = not fog_enabled
	_request_redraw()
	changed.emit()
	return fog_enabled


func _request_redraw() -> void:
	if _map != null and is_instance_valid(_map):
		_map.queue_redraw()


## True once the texture and transform are loaded.
func is_ready() -> bool:
	return _ensure_loaded()


func _ensure_loaded() -> bool:
	if _tex != null:
		return true
	if not ResourceLoader.exists(TEX_PATH):
		return false
	_tex = load(TEX_PATH) as Texture2D
	if _tex == null:
		return false
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(META_PATH):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
			if d is Dictionary:
				_meta = d
				var wm: Array = d.get("world_min", [-4096, -4096])
				_origin = Vector2(float(wm[0]), float(wm[1]))
				_ppm = float(d.get("px_per_m", _ppm))
				_margin = float(d.get("margin_px", _margin))
				var isz: Array = d.get("image_size", [2048, 2048])
				_img_size = Vector2(float(isz[0]), float(isz[1]))
	return true


## True when the painted sheet spans the whole streamed world. The sheet is baked offline (GPU, tools_qa/map/run_paint.sh);
## the 12 km world outgrew the 8 km sheet, so until it is repainted the map draws its own terrain instead of showing
## the new land as blank paper.
func covers_world() -> bool:
	return -_origin.x >= WorldGen.WORLD_HALF - 8.0 and -_origin.y >= WorldGen.WORLD_HALF - 8.0


## Frees the texture reference (VRAM) while the map is closed.
func release() -> void:
	_tex = null
	_fog_tex = null
	_fog_src = null


# --- transform -------------------------------------------------------------------------

## World metres (x, z) -> pixel in the parchment image.
func world_to_image(p: Vector2) -> Vector2:
	return Vector2(_margin, _margin) + (p - _origin) * _ppm


func image_to_world(px: Vector2) -> Vector2:
	return (px - Vector2(_margin, _margin)) / _ppm + _origin


## Poster/display name for a data place name (Oakvale -> Greenhollow ...), from the sheet's metadata.
func display_name(data_name: String) -> String:
	var al: Dictionary = _meta.get("aliases", {})
	return String(al.get(data_name, data_name))


# --- painting --------------------------------------------------------------------------

## Called from world_map._draw(): paints the parchment (+fog) in the map's own canvas. Returns true when it did, so the map
## skips its own terrain, rivers, roads and fog.
func paint_under(canvas: Control) -> bool:
	if not enabled or not _ensure_loaded() or not covers_world():
		return false
	var top_left: Vector2 = canvas.call("to_screen", image_to_world(Vector2.ZERO))
	var bottom_right: Vector2 = canvas.call("to_screen", image_to_world(_img_size))
	var view := Rect2(Vector2.ZERO, canvas.size)
	var rect := Rect2(top_left, bottom_right - top_left)
	if rect.intersects(view):
		canvas.draw_texture_rect(_tex, rect, false)
	if fog_enabled:
		_paint_fog(canvas)
	return true


func _paint_fog(canvas: Control) -> void:
	var img: Variant = canvas.get("_fog_img")
	if not (img is Image):
		return
	if img != _fog_src or _fog_tex == null:
		_fog_src = img
		_fog_tex = _build_fog(img)
	var rr: Rect2 = canvas.call("_region_rect")
	var tl: Vector2 = canvas.call("to_screen", rr.position)
	var br: Vector2 = canvas.call("to_screen", rr.end)
	canvas.draw_texture_rect(_fog_tex, Rect2(tl, br - tl), false, Color(1, 1, 1, clampf(fog_strength, 0.0, 1.0)))


## Turns the map's 128x128 fog field into a painterly 256x256 mist: soft ragged edge, mottled paper, faint pen stipple.
func _build_fog(src: Image) -> ImageTexture:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 11
		_noise.frequency = 0.045
		_noise.fractal_octaves = 3
	var up := src.duplicate() as Image
	up.resize(FOG_RES, FOG_RES, Image.INTERPOLATE_BILINEAR)
	var out := Image.create(FOG_RES, FOG_RES, false, Image.FORMAT_RGBA8)
	for y in FOG_RES:
		for x in FOG_RES:
			var a := up.get_pixel(x, y).a
			var nz := _noise.get_noise_2d(x, y)
			a = smoothstep(0.22, 0.72, a / 0.8 + nz * 0.18)
			var tone := 0.5 + 0.5 * _noise.get_noise_2d(x * 2.3 + 40.0, y * 2.3)
			var col := FOG_PAPER.lerp(FOG_INK, 0.06 * tone + 0.08 * smoothstep(0.6, 1.0, a))
			var stipple := 0.0
			if a > 0.55 and ((x * 7 + y * 13) % 11) == 0:
				stipple = 0.10
			out.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a * 0.72 + stipple * a, 0.0, 0.76)))
	return ImageTexture.create_from_image(out)
