class_name Lakeside
extends Node3D
## Dresses Emberglass Mere: a pier (Blender, tools/blender/make_pier.py) on the
## shore facing Ashford, a moored rowboat, and a fishing hut on stilts.

const GEN := "res://assets/generated/"
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


func _spawn(path: String, height := 0.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	if height > 0.0:
		var box := Assets.visual_aabb(n)
		n.scale = Vector3.ONE * (height / maxf(box.size.y, 0.01))
	add_child(n)
	return n
