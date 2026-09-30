extends "res://scripts/region1/region1_look.gd"
## Presenter for the Hidden Vale and the exploration POIs: the same streaming, parts, scatter, lights and waterfall
## machinery as Region1Look, fed from hidden_valley.gd / region_pois.gd instead of data/region1/landmarks.json.
## Added by exploration_director.gd (which sets `focus` from RegionDressing each frame through its own `focus`).

const HV := preload("res://scripts/world/hidden_valley.gd")
const POIS := preload("res://scripts/world/region_pois.gd")


func _ready() -> void:
	name = "ValeLook"
	var lms: Array = []
	lms.append_array(HV.landmarks())
	lms.append_array(POIS.landmarks())
	_data = {"landmarks": lms, "cliff_kits": []}
	for lm: Dictionary in lms:
		var far := Node3D.new()
		far.name = String(lm["id"]) + "_far"
		add_child(far)
		_build_parts(far, lm, true)
		for wf: Dictionary in lm.get("waterfalls", []):
			_build_waterfall(far, wf)
	print("ValeLook: %d cliff rocks" % build_vale_cliffs())


# --- Cliff rocks on the rim and the gorge walls -------------------------------------------------------------------

const CLIFF_ROCKS := [["free:nature/rock_limestone_tall", 0.78], ["free:nature/rock_blue_brown", 0.14], ["free:nature/rock_grey_plain", 0.08]]
const CLIFF_STEP := 5.0
const CLIFF_CELL := 320.0


## Warm limestone boulders laid on every face steeper than ~48 degrees (the rim and the slot), batched in MultiMesh cells.
## Without them the 2 m terrain mesh smears the rock texture down the walls. Runs once at load (~15k cells).
func build_vale_cliffs() -> int:
	var meshes: Array[Mesh] = []
	var heights: Array[float] = []
	var weights: Array[float] = []
	var total := 0.0
	for r: Array in CLIFF_ROCKS:
		var paths := asset_paths(String(r[0]))
		if not ResourceLoader.exists(paths[0]):
			continue
		var mi := Assets.static_model(paths[0]) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		meshes.append(mi.mesh)
		heights.append(maxf(mi.mesh.get_aabb().size.y, 0.1))
		weights.append(float(r[1]))
		total += float(r[1])
		mi.free()
	if meshes.is_empty() or not HV.enabled():
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7711
	var cells: Dictionary = {}
	var count := 0
	var c := HV.CENTER
	var half := 460.0
	var z := c.y - half
	while z < c.y + half:
		var x := c.x - half
		while x < c.x + half:
			var px := x + rng.randf_range(-0.45, 0.45) * CLIFF_STEP
			var pz := z + rng.randf_range(-0.45, 0.45) * CLIFF_STEP
			x += CLIFF_STEP
			var p := Vector2(px, pz)
			var rn := HV.rn_at(p)
			var dg := HV.gorge_distance(p)
			var near_slot: bool = dg.x < HV.gorge_half_width(dg.y) + HV.gorge_wall(dg.y) + 3.0 if dg.x != INF else false
			if not ((rn > 1.42 and rn < 1.8) or near_slot):
				continue
			var gx := WorldGen.height(px + 2.0, pz) - WorldGen.height(px - 2.0, pz)
			var gz := WorldGen.height(px, pz + 2.0) - WorldGen.height(px, pz - 2.0)
			var g := Vector2(gx, gz).length() / 4.0
			if g < 1.05 or rng.randf() > minf(1.0, (g - 1.0) * 0.9):
				continue
			var pick := rng.randf() * total
			var mi_i := 0
			while mi_i < weights.size() - 1 and pick > weights[mi_i]:
				pick -= weights[mi_i]
				mi_i += 1
			var target := rng.randf_range(3.2, 8.0)
			var k := target / heights[mi_i]
			var yaw := atan2(-gx, -gz) + rng.randf_range(-0.6, 0.6)
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2))
			basis = basis * Basis.from_scale(Vector3(k * rng.randf_range(1.0, 1.7), k, k * rng.randf_range(0.6, 0.9)))
			var up := Vector2(gx, gz).normalized() * target * clampf(0.45 / g, 0.05, 0.4)      # near-vertical walls: barely sunk, so the rock shows
			var pos := Vector3(px + up.x, WorldGen.height(px, pz) - target * 0.3, pz + up.y)
			var key := Vector2i(floori(px / CLIFF_CELL), floori(pz / CLIFF_CELL))
			if not cells.has(key):
				var arrs := []
				for _m in meshes.size():
					arrs.append([] as Array[Transform3D])
				cells[key] = arrs
			(cells[key][mi_i] as Array[Transform3D]).append(Transform3D(basis, pos))
			count += 1
		z += CLIFF_STEP
	for key: Vector2i in cells:
		for m_i in meshes.size():
			var list: Array[Transform3D] = cells[key][m_i]
			if list.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[m_i]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "ValeCliffs_%d_%d_%d" % [key.x, key.y, m_i]
			mmi.multimesh = mm
			mmi.visibility_range_end = 250.0      # only where the streamed terrain is drawn (the far horizon mesh has its own rock texture)
			mmi.visibility_range_end_margin = 20.0
			add_child(mmi)
	return count
