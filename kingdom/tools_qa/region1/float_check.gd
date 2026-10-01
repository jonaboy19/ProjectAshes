extends RefCounted
## Floating-prop check (docs/regions/LOOK_R1.md, pass 3). Walks the props that sit on the ground near a camera —
## region sites and landmarks (RegionDressing, Region1Look, ValeLook, the exploration POIs), the terrain streamer's
## trees and scatter, and settlement props — and flags every instance whose whole base hangs more than LIMIT m above
## the RENDERED terrain (Region1Look.ground_at: the exact 2 m / 4 m grid mesh, lower of the two).
## Used by look_capture.gd --floatcheck; returns report lines "FLOAT <view> <what> at (x, y, z) gap=<m>".

const LIMIT := 0.3
const RANGE := 160.0
const MAX_INSTANCES := 9000

var flagged := 0
var checked := 0


func check(view: String, world: Node, cam_pos: Vector3) -> Array[String]:
	var out: Array[String] = []
	var roots: Array[Node] = []
	for n in world.get_children():
		var sc: Script = n.get_script()
		var file := sc.resource_path.get_file() if sc else ""
		if file in ["region_dressing.gd", "terrain_streamer.gd", "settlement_builder.gd"]:
			roots.append(n)
	var budget := MAX_INSTANCES
	for r in roots:
		for g in r.find_children("*", "GeometryInstance3D", true, false):
			if budget <= 0:
				break
			if _skip(g as Node, r):
				continue
			if g is MultiMeshInstance3D:
				var mm := (g as MultiMeshInstance3D).multimesh
				if mm == null or mm.mesh == null:
					continue
				var box := mm.mesh.get_aabb()
				if box.size.y < 0.35:
					continue          # grass tufts, flower cards, litter: too small to read as floating
				var gx := (g as Node3D).global_transform
				var stride := maxi(1, mm.instance_count / 400)
				for i in range(0, mm.instance_count, stride):
					var xf := gx * mm.get_instance_transform(i)
					if xf.origin.distance_to(cam_pos) > RANGE:
						continue
					budget -= 1
					_one(out, view, _label(g as Node), xf, box)
			elif g is MeshInstance3D:
				var mi := g as MeshInstance3D
				if mi.mesh == null or not mi.is_visible_in_tree():
					continue
				var xf2 := mi.global_transform
				if xf2.origin.distance_to(cam_pos) > RANGE:
					continue
				var box2 := mi.mesh.get_aabb()
				if box2.size.y < 0.35 or box2.size.x * box2.size.z > 1600.0:
					continue      # tiny cards, or a ground/terrain-sized mesh
				budget -= 1
				_one(out, view, _label(mi), xf2, box2)
	return out


func _one(out: Array[String], view: String, what: String, xf: Transform3D, box: AABB) -> void:
	checked += 1
	var pts: Array[Vector3] = []
	for i in 8:
		pts.append(xf * box.get_endpoint(i))
	pts.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	var gap := INF
	for i in 4:
		var p := pts[i]
		var lv := WorldGen.water_level_at(p.x, p.z)
		if not is_nan(lv) and p.y < lv + 0.6:
			return        # sits in / on water (piers, the Drowned Bell, boats)
		gap = minf(gap, p.y - ground_at(p.x, p.z))
	if gap > LIMIT:
		flagged += 1
		out.append("FLOAT %s %s at (%.1f, %.1f, %.1f) gap=%.2f" % [view, what, xf.origin.x, xf.origin.y, xf.origin.z, gap])


func _skip(g: Node, root: Node) -> bool:
	var n := g
	while n != null and n != root:
		var nm := String(n.name)
		if nm.begins_with("Region1Horizon") or nm.begins_with("Waterfall") or nm.begins_with("PlungePool") or nm.begins_with("FallsFoam") \
				or nm.begins_with("FallsMist") or nm.contains("Bridge") or nm.contains("Impostor") or nm.begins_with("Water"):
			return true
		n = n.get_parent()
	var gi := g as GeometryInstance3D
	return gi.visibility_range_begin > 0.0      # far LOD stand-ins (their near twin is checked)


static func _label(n: Node) -> String:
	var parts: Array[String] = []
	var c := n
	for i in 3:
		if c == null:
			break
		parts.push_front(String(c.name))
		c = c.get_parent()
	var s := "/".join(parts)
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh and (n as MultiMeshInstance3D).multimesh.mesh:
		s += "[" + (n as MultiMeshInstance3D).multimesh.mesh.resource_name + "]"
	return s.replace(" ", "_")


## Rendered terrain height (same maths as Region1Look.ground_at: the 2 m and 4 m grid meshes split on the b-c
## diagonal, the lower of the two), duplicated so this check runs on any build.
static func mesh_grid(x: float, z: float, g: float) -> float:
	var ix := floorf(x / g)
	var iz := floorf(z / g)
	var fx := x / g - ix
	var fz := z / g - iz
	var x0 := ix * g
	var z0 := iz * g
	var hb := WorldGen.height(x0 + g, z0)
	var hc := WorldGen.height(x0, z0 + g)
	if fx + fz <= 1.0:
		var ha := WorldGen.height(x0, z0)
		return ha + (hb - ha) * fx + (hc - ha) * fz
	var hd := WorldGen.height(x0 + g, z0 + g)
	return hd + (hc - hd) * (1.0 - fx) + (hb - hd) * (1.0 - fz)


static func ground_at(x: float, z: float) -> float:
	return minf(mesh_grid(x, z, 2.0), mesh_grid(x, z, 4.0))
