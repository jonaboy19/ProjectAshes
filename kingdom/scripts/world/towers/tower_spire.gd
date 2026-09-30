extends RefCounted
## Procedural geometry of the tower exterior (no Blender needed, nothing to import): the colossal rune-lit spire in three
## levels of detail, all built from the same profile so they line up:
##   near()      ~5k tris: stepped apron, twisting octagonal tiers, galleries, buttresses, rune strips, arch, crown
##   mid()       ~1.5k tris: tiers + rune strips only
##   impostor()  one billboard with a painted silhouette (Image built once at boot) for the skyline beyond ~2.5 km
## Units are metres, origin at the centre of the base on the ground, +Z is the front (the entrance side).

const FG := preload("res://scripts/world/towers/floor_gen.gd")

const HEIGHT := 520.0
const BASE_R := 56.0
const SHAFT_FRAC := 0.86
const TIERS := 18
const SIDES := 8
const STONE := Color(0.46, 0.44, 0.42)
const STONE_DARK := Color(0.3, 0.29, 0.29)
const RUNE := Color(0.45, 0.85, 1.0)
const RUNE_WARM := Color(1.0, 0.72, 0.35)

static var _imp_tex: ImageTexture = null


## Shaft radius at height y (metres).
static func radius_at(y: float) -> float:
	var t := clampf(y / (HEIGHT * SHAFT_FRAC), 0.0, 1.0)
	if y > HEIGHT * SHAFT_FRAC:
		var k := clampf((y - HEIGHT * SHAFT_FRAC) / (HEIGHT * (1.0 - SHAFT_FRAC)), 0.0, 1.0)
		return lerpf(radius_at(HEIGHT * SHAFT_FRAC), 1.2, pow(k, 0.7))
	return BASE_R * (1.0 - 0.74 * pow(t, 0.9)) + 1.2 * sin(t * 26.0)


static func _stone(y: float, shade := 1.0) -> Color:
	var t := clampf(y / HEIGHT, 0.0, 1.0)
	var c := STONE.lerp(Color(0.62, 0.6, 0.6), t * 0.7)
	c = c.lerp(Color(0.3, 0.3, 0.32), 0.35 * (1.0 - t) * (0.5 + 0.5 * sin(y * 0.35)))
	return Color(c.r * shade, c.g * shade, c.b * shade)


static func near() -> Dictionary:
	return _build(true)


static func mid() -> Dictionary:
	return _build(false)


## {lit: ArrayMesh, glow: ArrayMesh, faces: PackedVector3Array (collision hull of the base)}
static func _build(detailed: bool) -> Dictionary:
	var lit := FG.MB.new()
	var glow := FG.MB.new()
	var shaft_h := HEIGHT * SHAFT_FRAC
	var th := shaft_h / float(TIERS)
	# apron: a low sloped octagon the camp and the walkway sit on (visual only)
	lit.prism(Vector3(0, 0, 0), BASE_R * 1.75, BASE_R * 1.22, 1.4, SIDES, STONE_DARK.lightened(0.05), STONE_DARK.lightened(0.12))
	lit.prism(Vector3(0, 1.3, 0), BASE_R * 1.22, BASE_R * 1.16, 1.6, SIDES, STONE_DARK.lightened(0.12), STONE.darkened(0.1))
	# shaft tiers, each a little narrower and twisted
	for i in TIERS:
		var y0 := 2.9 + (shaft_h - 2.9) * float(i) / float(TIERS)
		var y1 := 2.9 + (shaft_h - 2.9) * float(i + 1) / float(TIERS)
		var r0 := radius_at(y0)
		var r1 := radius_at(y1) * 0.97
		var yaw := float(i) * 0.1
		lit.prism(Vector3(0, y0, 0), r0, r1, y1 - y0, SIDES, _stone(y0, 0.95), _stone(y1, 1.05), false, yaw)
		# rune strips up the faces, segmented so they read like inscriptions
		var faces := SIDES if detailed else 4
		for f in faces:
			var a := yaw + TAU * (float(f) + 0.5) / float(SIDES) * (float(SIDES) / float(faces))
			var rm := (r0 + r1) * 0.5 * cos(PI / float(SIDES)) + 0.35
			var mid_y := (y0 + y1) * 0.5
			var glyph := Color(RUNE.r, RUNE.g, RUNE.b, 1.0) if (i + f) % 3 != 0 else RUNE_WARM
			glow.box(Vector3(sin(a) * rm, mid_y, cos(a) * rm), Vector3(1.4 + r1 * 0.03, (y1 - y0) * 0.62, 0.3), glyph, a)
		# galleries: a ring every third tier
		if i % 3 == 2:
			lit.prism(Vector3(0, y1 - 1.2, 0), r1 * 1.12, r1 * 1.08, 2.6, SIDES, _stone(y1, 0.8), _stone(y1, 1.15), false, yaw)
			glow.prism(Vector3(0, y1 + 1.35, 0), r1 * 1.1, r1 * 1.1, 0.5, SIDES, RUNE.darkened(0.15), Color(0, 0, 0, 0), false, yaw)
		if detailed and i % 2 == 1:
			# windows: tall glowing slits low on four faces
			for f in 4:
				var wa := yaw + PI * 0.5 * float(f) + 0.2
				var rr := (r0 + r1) * 0.5 * 0.93 + 0.2
				glow.box(Vector3(sin(wa) * rr, y0 + th * 0.4, cos(wa) * rr), Vector3(1.8, th * 0.45, 0.3), RUNE_WARM.darkened(0.15), wa)
	# buttresses: four leaning ribs around the base
	if detailed:
		for b in 4:
			var a := TAU * float(b) / 4.0 + PI * 0.25
			var bp := Vector3(sin(a) * BASE_R * 0.98, 0, cos(a) * BASE_R * 0.98)
			for seg in 5:
				var sy := 6.0 + float(seg) * 22.0
				var rr := BASE_R * (1.0 - 0.17 * float(seg)) * 1.0
				lit.box(Vector3(sin(a) * rr, sy + 11.0, cos(a) * rr), Vector3(10.0 - float(seg) * 1.4, 22.0, 14.0 - float(seg) * 2.0), _stone(sy, 0.8), a)
			glow.box(bp + Vector3(0, 28, 0) + Vector3(sin(a), 0, cos(a)) * 6.0, Vector3(0.8, 34.0, 0.4), RUNE_WARM, a)
	# the great arch on the front face
	_arch(lit, glow, detailed)
	# crown: a needle with floating rings and a beacon
	var cy := shaft_h
	lit.prism(Vector3(0, cy, 0), radius_at(cy), 1.2, HEIGHT - cy, 6, _stone(cy, 1.1), _stone(HEIGHT, 1.3))
	for k in 3:
		var ry := cy + 30.0 + float(k) * 26.0
		var rr := radius_at(ry) + 9.0 + float(k) * 1.5
		glow.prism(Vector3(0, ry, 0), rr, rr, 1.4, 12, RUNE.lightened(0.1), Color(0, 0, 0, 0), false, float(k))
	glow.prism(Vector3(0, HEIGHT - 6.0, 0), 3.4, 0.0, 14.0, 6, Color(1.0, 0.92, 0.65), Color(1.0, 1.0, 0.9))
	glow.prism(Vector3(0, HEIGHT - 6.0, 0), 3.4, 0.0, -8.0, 6, Color(1.0, 0.8, 0.45), Color(1.0, 0.9, 0.7))
	var out := {"lit": lit.mesh(FG.lit_material()), "glow": glow.mesh(FG.glow_material(1.8))}
	return out


static func _arch(lit: FG.MB, glow: FG.MB, detailed: bool) -> void:
	# stands on the apron in front of the shaft base (local +Z is front); the door panel is dark with a runic frame
	var z := radius_at(0.0) * 0.96
	var w := 16.0
	var h := 26.0
	lit.box(Vector3(-w * 0.5 - 2.5, h * 0.5, z + 2.0), Vector3(5.0, h, 6.0), STONE.lightened(0.05))
	lit.box(Vector3(w * 0.5 + 2.5, h * 0.5, z + 2.0), Vector3(5.0, h, 6.0), STONE.lightened(0.05))
	lit.box(Vector3(0, h + 2.0, z + 2.0), Vector3(w + 12.0, 5.0, 6.0), STONE.lightened(0.08))
	lit.box(Vector3(0, h * 0.5, z + 0.3), Vector3(w, h, 1.4), Color(0.05, 0.05, 0.07))
	glow.box(Vector3(0, h - 0.3, z + 5.15), Vector3(w, 0.8, 0.3), RUNE)
	glow.box(Vector3(-w * 0.5, h * 0.5, z + 5.15), Vector3(0.8, h, 0.3), RUNE)
	glow.box(Vector3(w * 0.5, h * 0.5, z + 5.15), Vector3(0.8, h, 0.3), RUNE)
	glow.box(Vector3(0, h * 0.55, z + 1.05), Vector3(w * 0.42, h * 0.62, 0.25), RUNE_WARM.darkened(0.25))
	if detailed:
		for s in [-1.0, 1.0]:
			# guardian statues
			lit.box(Vector3(s * (w * 0.5 + 9.0), 4.0, z + 6.0), Vector3(5.0, 8.0, 5.0), STONE.darkened(0.1))
			lit.prism(Vector3(s * (w * 0.5 + 9.0), 8.0, z + 6.0), 2.0, 1.2, 10.0, 6, STONE, STONE.lightened(0.15))
			glow.box(Vector3(s * (w * 0.5 + 9.0), 15.0, z + 6.0), Vector3(1.6, 1.6, 1.6), RUNE_WARM, 0.78)


## A billboard texture with the spire's silhouette. Built once.
static func impostor() -> ImageTexture:
	if _imp_tex != null:
		return _imp_tex
	var w := 128
	var h := 448
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var half_w := BASE_R * 1.75
	for py in h:
		var y := HEIGHT * (1.0 - (float(py) + 0.5) / float(h))
		var r := radius_at(y) if y > 2.0 else BASE_R * 1.75
		if y < 3.0:
			r = BASE_R * 1.5
		# galleries widen the silhouette
		var ti := int(floor(y / (HEIGHT * SHAFT_FRAC) * float(TIERS)))
		if y < HEIGHT * SHAFT_FRAC and ti % 3 == 2 and fmod(y / (HEIGHT * SHAFT_FRAC) * float(TIERS), 1.0) > 0.8:
			r *= 1.12
		var px_r := r / half_w * float(w) * 0.5
		for px in w:
			var dx := float(px) + 0.5 - float(w) * 0.5
			if absf(dx) <= px_r:
				var side := dx / maxf(px_r, 0.001)
				var c := _stone(y, 0.85 + 0.25 * (0.5 - side * 0.5))
				# rune line up the middle and warm windows
				var edge := clampf((px_r - absf(dx)) / 2.0, 0.0, 1.0)
				var glyph := absf(dx) < maxf(1.0, px_r * 0.08) and int(y / 14.0) % 3 != 0 and y > 8.0
				if glyph:
					c = RUNE
				img.set_pixel(px, py, Color(c.r, c.g, c.b, edge))
	# beacon at the top
	for dy in range(-7, 8):
		for dx in range(-5, 6):
			var d := sqrt(float(dx * dx + dy * dy) * 0.6)
			if d < 5.0:
				var px := w / 2 + dx
				var py := 3 + dy + 4
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, Color(1.0, 0.93, 0.7, 1.0))
	img.generate_mipmaps()
	_imp_tex = ImageTexture.create_from_image(img)
	return _imp_tex


static func impostor_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(BASE_R * 1.75 * 2.0, HEIGHT)
	q.center_offset = Vector3(0, HEIGHT * 0.5, 0)
	return q


static func impostor_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.35
	m.albedo_texture = impostor()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
