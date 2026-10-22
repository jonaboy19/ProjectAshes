extends RefCounted
## Terrain for the War Map: samples the REAL world (WorldGen height, water, forest) into small data
## textures, a few rows per frame, and a shader paints them in one of three styles with hill-shading and
## contour lines. Sampling is progressive (never a hitch) and cached; switching style only changes a uniform.
##   world  : the whole 12 km world at ~40 m / texel (baked once, shared)
##   region : a ~3.6 km square around the focus at ~15 m / texel
##   local  : a ~1.1 km square around the focus at ~4.5 m / texel (the actual area)

const WORLD_RES := 300            # ~40 m per texel over the 12 km world (200 for 8 km)
const REGION_SPAN := 3600.0
const REGION_RES := 240
const LOCAL_SPAN := 1100.0
const LOCAL_RES := 256
const MAX_DETAIL := 6

const SHADER := """
shader_type canvas_item;
uniform sampler2D data : filter_nearest, repeat_disable;
uniform vec2 data_size = vec2(200.0);
uniform float texel_m = 40.0;
uniform int style = 0;
uniform float contour = 15.0;

vec4 fetch(ivec2 p) {
	ivec2 mx = ivec2(data_size) - ivec2(1);
	return texelFetch(data, clamp(p, ivec2(0), mx), 0);
}
float dec(vec4 t) {
	return (t.r * 255.0 + t.g * 255.0 * 256.0) / 65535.0 * 300.0 - 60.0;
}
float H(vec2 p) {
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	return mix(mix(dec(fetch(i)), dec(fetch(i + ivec2(1, 0))), f.x), mix(dec(fetch(i + ivec2(0, 1))), dec(fetch(i + ivec2(1, 1))), f.x), f.y);
}
void fragment() {
	vec2 p = UV * data_size - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	vec4 a = fetch(i);
	vec4 b = fetch(i + ivec2(1, 0));
	vec4 c = fetch(i + ivec2(0, 1));
	vec4 d = fetch(i + ivec2(1, 1));
	float h = mix(mix(dec(a), dec(b), f.x), mix(dec(c), dec(d), f.x), f.y);
	float forest = mix(mix(a.b, b.b, f.x), mix(c.b, d.b, f.x), f.y);
	float water = mix(mix(a.a, b.a, f.x), mix(c.a, d.a, f.x), f.y);
	float gx = (H(p + vec2(1.0, 0.0)) - H(p - vec2(1.0, 0.0))) / (2.0 * texel_m);
	float gy = (H(p + vec2(0.0, 1.0)) - H(p - vec2(0.0, 1.0))) / (2.0 * texel_m);
	float shade = clamp(0.5 + (gx * 0.75 + gy * 0.65) * 1.5, 0.0, 1.0);
	float slope = length(vec2(gx, gy));
	float t = clamp((h - 5.0) / 140.0, 0.0, 1.0);
	float cv = h / contour;
	float line = 1.0 - smoothstep(0.0, max(fwidth(cv) * 1.1, 0.001), abs(fract(cv - 0.5) - 0.5));
	float cvm = h / (contour * 5.0);
	float linem = 1.0 - smoothstep(0.0, max(fwidth(cvm) * 1.6, 0.001), abs(fract(cvm - 0.5) - 0.5));
	float wet = smoothstep(0.35, 0.65, water);
	vec3 col;
	if (style == 0) {
		vec3 lo = vec3(0.72, 0.74, 0.60);
		vec3 mid = vec3(0.64, 0.60, 0.47);
		vec3 hi = vec3(0.56, 0.50, 0.41);
		col = mix(mix(lo, mid, smoothstep(0.0, 0.5, t)), hi, smoothstep(0.45, 1.0, t));
		col = mix(col, vec3(0.44, 0.52, 0.38), forest * 0.6);
		col = mix(col, vec3(0.72, 0.68, 0.60), smoothstep(0.55, 1.1, slope) * 0.5);
		col *= 0.80 + 0.40 * shade;
		col = mix(col, col * vec3(0.72, 0.66, 0.55), line * 0.5 + linem * 0.35);
		col = mix(col, vec3(0.55, 0.65, 0.68), wet);
	} else if (style == 1) {
		vec3 lo = vec3(0.13, 0.17, 0.20);
		vec3 hi = vec3(0.31, 0.35, 0.38);
		col = mix(lo, hi, t);
		col = mix(col, vec3(0.08, 0.26, 0.20), forest * 0.85);
		col *= 0.80 + 0.40 * shade;
		col += vec3(0.05, 0.06, 0.07) * (line * 0.8 + linem * 0.7);
		col = mix(col, vec3(0.05, 0.16, 0.28), wet);
	} else {
		vec3 lo = vec3(0.86, 0.77, 0.58);
		vec3 hi = vec3(0.74, 0.60, 0.40);
		col = mix(lo, hi, t * 0.9);
		col = mix(col, vec3(0.62, 0.66, 0.42), forest * 0.45);
		col *= 0.82 + 0.32 * shade;
		col = mix(col, vec3(0.42, 0.29, 0.14), line * 0.30 + linem * 0.30);
		col = mix(col, vec3(0.60, 0.72, 0.70), wet);
		float n = fract(sin(dot(floor(UV * data_size * 3.0), vec2(12.9898, 78.233))) * 43758.5453);
		col *= 0.97 + 0.06 * n;
	}
	COLOR = vec4(col, 1.0);
}
"""

static var _shader: Shader
static var _world_cache: Dictionary = {}      # world signature -> Field


class Field extends RefCounted:
	var rect := Rect2()
	var res := Vector2i(1, 1)
	var data := PackedByteArray()
	var row := 0
	var tex: ImageTexture = null
	var ready := false
	var texel_m := 40.0
	var span_key := ""

	func _init(r: Rect2, n: int) -> void:
		rect = r
		res = Vector2i(n, n)
		texel_m = r.size.x / float(n)
		data.resize(n * n * 4)

	## Samples rows until the budget is spent. Returns true when finished.
	func step(budget_us: int) -> bool:
		if ready:
			return true
		var t0 := Time.get_ticks_usec()
		while row < res.y:
			var wz := rect.position.y + (float(row) + 0.5) * texel_m
			for x in res.x:
				var wx := rect.position.x + (float(x) + 0.5) * texel_m
				var h := WorldGen.height(wx, wz)
				var u := clampi(int((h + 60.0) / 300.0 * 65535.0), 0, 65535)
				var o := (row * res.x + x) * 4
				data[o] = u & 255
				data[o + 1] = u >> 8
				data[o + 2] = int(clampf(WorldGen.forest_density(wx, wz), 0.0, 1.0) * 255.0)
				data[o + 3] = 255 if WorldGen.is_water(wx, wz) else 0
			row += 1
			if Time.get_ticks_usec() - t0 > budget_us:
				break
		if row >= res.y:
			var img := Image.create_from_data(res.x, res.y, false, Image.FORMAT_RGBA8, data)
			tex = ImageTexture.create_from_image(img)
			ready = true
		return ready


var _details: Array = []        # Field, oldest first
var _queue: Array = []          # unfinished fields


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader


static func world_signature() -> String:
	if WorldGen.settlements.is_empty():
		return "empty"
	return "%d|%s|%s" % [WorldGen.settlements.size(), str((WorldGen.settlements[0] as Dictionary)["pos"]), str(WorldGen.lake_center)]


## The whole world (shared between map instances).
func world() -> Field:
	var sig := world_signature()
	if not _world_cache.has(sig):
		var half := WorldGen.WORLD_HALF
		var f := Field.new(Rect2(-half, -half, half * 2.0, half * 2.0), WORLD_RES)
		_world_cache[sig] = f
	var fld: Field = _world_cache[sig]
	if not fld.ready and not _queue.has(fld):
		_queue.append(fld)
	return fld


## A detail field of `span` metres around `center` (snapped so nearby requests share it).
func request(center: Vector2, span: float, n: int) -> Field:
	var snap := span / 6.0
	var c := Vector2(roundf(center.x / snap) * snap, roundf(center.y / snap) * snap)
	var key := "%d|%d|%d|%d" % [int(c.x), int(c.y), int(span), n]
	for f: Field in _details:
		if f.span_key == key:
			_details.erase(f)
			_details.append(f)
			return f
	var fld := Field.new(Rect2(c - Vector2(span, span) * 0.5, Vector2(span, span)), n)
	fld.span_key = key
	_details.append(fld)
	_queue.append(fld)
	while _details.size() > MAX_DETAIL:
		var old: Field = _details.pop_front()
		_queue.erase(old)
	return fld


func pending() -> bool:
	return not _queue.is_empty()


## Advance the newest unfinished field. Returns true while more work remains.
func step(budget_us: int) -> bool:
	while not _queue.is_empty():
		var f: Field = _queue.back()      # the most recently requested is the one being looked at
		if f.step(budget_us):
			_queue.pop_back()
			continue
		return true
	return false


## Bake everything queued right now (tests, screenshots).
func finish_all() -> void:
	while pending():
		step(1000000)


static func make_material(field: Field, style: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("data", field.tex)
	m.set_shader_parameter("data_size", Vector2(field.res))
	m.set_shader_parameter("texel_m", field.texel_m)
	m.set_shader_parameter("style", style)
	m.set_shader_parameter("contour", 20.0 if field.texel_m > 20.0 else (12.0 if field.texel_m > 8.0 else 6.0))
	return m
