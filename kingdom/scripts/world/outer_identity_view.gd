extends Node3D
## Runtime half of the Rising Ashes outer identity (scripts/world/outer_identity.gd plans the props; this node draws what
## needs the live world): the ground tint where the wards end, and Soulbeast tracks around live ecology dens. Added by
## RegionDressing._ready. Preload; no class_name.
##
## Cost: one 1.5 s timer; decals only exist while the player is within BUILD metres and are freed past FREE. Decals are
## the Mobile renderer's 8-per-mesh kind, so a boundary uses 3 and a den 4, and nothing is built on LOW (TownDecals do not draw there).

const TownDecalsScript := preload("res://scripts/world/town_decals.gd")
const BUILD := 200.0
const FREE := 320.0
const TRACKS_PER_DEN := 4
const BIG_BEASTS := ["bear", "troll", "wyvern", "stagborn_warden", "ghoul", "apex"]

var _timer := 0.0
var _edges: Dictionary = {}      # site id -> Node3D
var _dens: Dictionary = {}       # den id -> Node3D
var _paw: ImageTexture
var _claw: ImageTexture


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.5
	refresh_now(false)


func _focus() -> Vector2:
	var p := get_parent()
	var f: Vector3 = p.focus if p != null and p.get("focus") != null else Vector3.ZERO
	return Vector2(f.x, f.z)


func _low() -> bool:
	var q: Node = get_node_or_null("/root/Quality")
	return q != null and q.tier == q.LOW


## Build and free everything for the current focus (also called by the QA shots). In the game (`all` false) at most one
## site is built per tick (decal nodes plus, once per beast class, a 64 x 256 print texture), so nothing hitches.
func refresh_now(all := true) -> void:
	if _low() or not TownDecalsScript.available():
		return
	var f := _focus()
	for site in WorldGen.sites:
		if String(site.get("ident", "")) != "ward_marker":
			continue
		var id: int = site["id"]
		var d := f.distance_to(site["pos"])
		if d < BUILD and not _edges.has(id):
			_edges[id] = _build_edge(site)
			if not all:
				return
		elif d > FREE and _edges.has(id):
			(_edges[id] as Node3D).queue_free()
			_edges.erase(id)
	var frontier: Node = get_node_or_null("/root/Frontier")
	if frontier != null and frontier.get("ecology") != null:
		for den: Dictionary in frontier.ecology.dens:
			var did: int = den["id"]
			var near: bool = f.distance_to(den["pos"]) < BUILD and den["alive"] and int(den["population"]) > 0
			if near and not _dens.has(did):
				_dens[did] = _build_tracks(den)
				if not all:
					return
			elif (not near and f.distance_to(den["pos"]) > FREE or not den["alive"]) and _dens.has(did):
				(_dens[did] as Node3D).queue_free()
				_dens.erase(did)


## Ash-grey ground across the road where the wards end, thinning out beyond: three decals along the unprotected direction.
func _build_edge(site: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "WardEdge%d" % int(site["id"])
	add_child(root)
	var p: Vector2 = site["pos"]
	var d: Vector2 = site["beyond"]
	var half: float = site["road_half"]
	# The marker sits to one side of the road: step across to the road's centre line first.
	var yaw: float = site["yaw"]
	var front := Vector2(sin(yaw), cos(yaw))
	var centre := p + front * (half + 3.4)
	var yaw_d := atan2(d.x, d.y)
	for k in 3:
		var at := centre + d * (8.0 + k * 20.0)
		var size := Vector3(half * 2.0 + 24.0 - k * 4.0, 2.5, 26.0)
		var dec := TownDecalsScript.make("dirt", size, TownDecalsScript.GROUND_LAYER, Color(0.36, 0.33, 0.32, 1.0 - k * 0.22))
		root.add_child(dec)
		dec.global_transform = Transform3D(Basis(Vector3.UP, yaw_d), Vector3(at.x, WorldGen.height(at.x, at.y) + 0.3, at.y))
	return root


## Paw or claw prints running out of a den, four strips on different bearings (a trail to water, to the road, to the woods).
func _build_tracks(den: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Tracks%d" % int(den["id"])
	add_child(root)
	var big := String(den["species"]) in BIG_BEASTS
	var tex := _texture(big)
	var c: Vector2 = den["pos"]
	var terr := float(den.get("territory", 40.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501 + int(den["id"]) * 131
	for i in TRACKS_PER_DEN:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(8.0, maxf(14.0, minf(terr * 0.7, 45.0)))
		var at := c + Vector2(cos(ang), sin(ang)) * dist
		if WorldGen.is_water(at.x, at.y):
			continue
		var run := ang + PI + rng.randf_range(-0.5, 0.5)    # the strip points back toward the den
		var dec := TownDecalsScript.make("dirt", Vector3(2.4 if not big else 3.2, 2.0, 9.0), TownDecalsScript.GROUND_LAYER, Color(0.22, 0.16, 0.11, 0.9))
		dec.texture_albedo = tex
		dec.texture_normal = null
		root.add_child(dec)
		dec.global_transform = Transform3D(Basis(Vector3.UP, atan2(cos(run), sin(run))), Vector3(at.x, WorldGen.height(at.x, at.y) + 0.3, at.y))
	return root


## One shared strip texture per beast class: 256 x 64, prints alternating along the long axis (image v runs along the decal's Z).
func _texture(big: bool) -> ImageTexture:
	if big and _claw != null:
		return _claw
	if not big and _paw != null:
		return _paw
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var steps := 5
	for i in steps:
		var cy := 28.0 + i * 48.0
		var cx := 22.0 if i % 2 == 0 else 42.0
		if big:
			_ellipse(img, Vector2(cx, cy), Vector2(11.0, 13.0))
			for k in 3:
				_ellipse(img, Vector2(cx - 12.0 + k * 12.0, cy - 17.0), Vector2(3.2, 7.0))
		else:
			_ellipse(img, Vector2(cx, cy), Vector2(6.0, 7.5))
			for k in 4:
				var a := -0.9 + k * 0.6
				_ellipse(img, Vector2(cx + sin(a) * 9.5, cy - cos(a) * 10.5 - 3.0), Vector2(2.8, 3.6))
	var tex := ImageTexture.create_from_image(img)
	if big:
		_claw = tex
	else:
		_paw = tex
	return tex


static func _ellipse(img: Image, c: Vector2, r: Vector2) -> void:
	for y in range(maxi(0, int(c.y - r.y - 1)), mini(img.get_height(), int(c.y + r.y + 2))):
		for x in range(maxi(0, int(c.x - r.x - 1)), mini(img.get_width(), int(c.x + r.x + 2))):
			var q := Vector2((x - c.x) / r.x, (y - c.y) / r.y)
			var a := clampf(1.0 - q.length(), 0.0, 1.0) * 3.0
			if a > 0.0:
				var old := img.get_pixel(x, y)
				img.set_pixel(x, y, Color(1, 1, 1, maxf(old.a, clampf(a, 0.0, 1.0))))
