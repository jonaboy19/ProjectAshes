class_name Lakeside
extends Node3D
## Dresses Emberglass Mere: a pier (Blender, tools/blender/make_pier.py) on the
## shore facing Ashford, a moored rowboat, and a fishing hut on stilts.
## Fishing spots (fishing_spot.gd): the pier end, a few points round the lake
## shore and a couple on the banks of the Ashrun.

const FishingSpot := preload("res://scripts/world/fishing_spot.gd")
const GEN := "res://assets/generated/"
## Pier deck height above the lake (pier origin +0.6, deck +0.2 above origin).
const PIER_DECK := 0.8
const PIER_END := 15.8
const PACK := "res://assets/incoming/3dassets-dev-ai/medieval-mmo-starter-realm/"


func _ready() -> void:
	var c: Vector2 = WorldGen.lake_center
	if c.x > 1.0e5:
		return
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var out := (home - c).normalized()
	# Walk out from the centre to the first dry ground: that's the shore.
	var shore := c
	var t := 0.0
	while t < WorldGen.lake_radius * 2.0:
		var q := c + out * t
		if not WorldGen.is_water(q.x, q.y):
			shore = q
			break
		t += 1.0
	var into := -out
	var level: float = WorldGen.lake_level
	# Pier: its seaward end is local +Z, 18 m long, deck 0.2 m above origin.
	var pier := _spawn(GEN + "pier.glb")
	if pier:
		var mid := shore + into * 7.5
		pier.global_position = Vector3(mid.x, level + 0.6, mid.y)
		pier.rotation.y = atan2(into.x, into.y)
	var boat := _spawn(GEN + "rowboat.glb")
	if boat:
		var side := Vector2(into.y, -into.x)
		var bp := shore + into * 14.0 + side * 3.2
		boat.global_position = Vector3(bp.x, level - 0.25, bp.y)
		boat.rotation.y = atan2(into.x, into.y) + 0.15
	var hut := _spawn(PACK + "fishing-hut-on-stilts.glb", 6.0)
	if hut:
		var side2 := Vector2(-into.y, into.x)
		var hp := shore + side2 * 22.0 + into * 3.0
		hut.global_position = Vector3(hp.x, maxf(WorldGen.height(hp.x, hp.y), level - 0.8), hp.y)
		hut.rotation.y = atan2(into.x, into.y)
	_place_fishing(c, shore, into, level, pier != null)


## Fishing spots: pier end (if the pier exists), three lake shore points spread
## round the Mere away from the pier and hut, and two on the Ashrun's banks.
func _place_fishing(c: Vector2, shore: Vector2, into: Vector2, level: float, has_pier: bool) -> void:
	var hut_at := shore + Vector2(-into.y, into.x) * 22.0
	if has_pier:
		var end := shore + into * PIER_END
		var cast := shore + into * (PIER_END + 5.0)
		_spot(Vector3(end.x, level + PIER_DECK, end.y), Vector3(cast.x, level, cast.y), false, "Emberglass Mere")
	var out := -into
	for turn: float in [1.7, PI, -1.7]:
		var dir := out.rotated(turn)
		var t := 0.0
		while t < WorldGen.lake_radius * 2.0:
			var q := c + dir * t
			if not WorldGen.is_water(q.x, q.y):
				var stand := q + dir * 1.2
				var cast := q - dir * 6.0
				if stand.distance_to(hut_at) > 10.0 and WorldGen.road_distance(stand.x, stand.y) > 4.0 \
						and not WorldGen.is_water(stand.x, stand.y):
					_spot(Vector3(stand.x, WorldGen.height(stand.x, stand.y), stand.y),
						Vector3(cast.x, level, cast.y), false, "Emberglass Mere")
				break
			t += 1.0
	# The Ashrun: the arm that feeds the Mere (WorldGen.rivers[0]).
	if WorldGen.rivers.is_empty():
		return
	var pts: PackedVector2Array = WorldGen.rivers[0]["points"]
	var placed := 0
	for frac: float in [0.55, 0.75, 0.4, 0.85]:
		if placed >= 2 or pts.size() < 4:
			break
		var i := clampi(int(pts.size() * frac), 0, pts.size() - 2)
		var p := pts[i]
		var tangent := (pts[i + 1] - p).normalized()
		var n := Vector2(-tangent.y, tangent.x)
		var near := WorldGen.nearest_settlement(p)
		if not near.is_empty() and p.distance_to(near["pos"]) < float(near["radius"]) * 1.3:
			continue
		var d := 0.0
		while d < 30.0 and WorldGen.is_water(p.x + n.x * d, p.y + n.y * d):
			d += 0.5
		if d >= 30.0:
			continue
		var stand := p + n * (d + 1.0)
		var lv := WorldGen.water_level_at(p.x, p.y)
		if is_nan(lv) or WorldGen.road_distance(stand.x, stand.y) < 4.0:
			continue
		_spot(Vector3(stand.x, WorldGen.height(stand.x, stand.y), stand.y), Vector3(p.x, lv, p.y), true, "the Ashrun")
		placed += 1


func _spot(at: Vector3, cast: Vector3, river: bool, water_name: String) -> void:
	var s: Node3D = FishingSpot.new()
	s.set("water_point", cast)
	s.set("river", river)
	s.set("water_name", water_name)
	s.name = "FishingSpot"
	add_child(s, true)
	s.global_position = at


func _spawn(path: String, height := 0.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	if height > 0.0:
		var box := Assets.visual_aabb(n)
		n.scale = Vector3.ONE * (height / maxf(box.size.y, 0.01))
	add_child(n)
	return n
