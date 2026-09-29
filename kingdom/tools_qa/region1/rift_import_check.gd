extends SceneTree
## Region 1 L4 import check for the two Rift monsters and the rift kit's own GLBs.
##
##   Godot --headless --path kingdom -s res://tools_qa/region1/rift_import_check.gd
##
## For each file: does it load as a PackedScene, how many mesh instances / triangles / surfaces, which materials and
## textures (is the emissive glow map present), the AABB, the skeleton (bones) and the animation names with lengths.
## Prints one PASS/FAIL line per file and a JSON blob; exit code 0 = all passed. Headless-safe (no rendering).

const FILES := {
	"rift_slime": {"path": "res://assets/incoming/monsters/quaternius/rift_slime.glb", "tris_max": 2000, "clips": ["idle", "walk", "attack", "hit", "death"], "glow": true},
	"rift_slime_lod1": {"path": "res://assets/incoming/monsters/quaternius/rift_slime_lod1.glb", "tris_max": 1000, "clips": ["idle", "walk", "attack", "hit", "death"], "glow": true},
	"rift_wraith": {"path": "res://assets/incoming/monsters/quaternius/rift_wraith.glb", "tris_max": 8000, "clips": ["idle", "run", "attack", "hit", "death"], "glow": true},
	"rift_wraith_lod1": {"path": "res://assets/incoming/monsters/quaternius/rift_wraith_lod1.glb", "tris_max": 2500, "clips": ["idle", "run", "attack", "hit", "death"], "glow": true},
	"scar_crystal_a": {"path": "res://assets/incoming/region1/rift/crystals/scar_crystal_a_lod0.glb", "tris_max": 4000, "clips": [], "glow": false},
	"scar_crystal_b": {"path": "res://assets/incoming/region1/rift/crystals/scar_crystal_b_lod0.glb", "tris_max": 4000, "clips": [], "glow": false},
	"scar_crystal_c": {"path": "res://assets/incoming/region1/rift/crystals/scar_crystal_c_lod0.glb", "tris_max": 4000, "clips": [], "glow": false},
	"scar_crystal_a_lod1": {"path": "res://assets/incoming/region1/rift/crystals/scar_crystal_a_lod1.glb", "tris_max": 1200, "clips": [], "glow": false},
}
const MATERIALS := ["rift_foliage", "rift_foliage_ground", "rift_bark", "rift_rock", "rift_moss", "rift_wolf", "rift_wolf_lod1", "rift_boar", "rift_boar_lod1"]


func _init() -> void:
	var fails := 0
	var report := {}
	for id in FILES:
		var cfg: Dictionary = FILES[id]
		var r := _check(id, cfg)
		report[id] = r
		var ok: bool = r["ok"]
		if not ok:
			fails += 1
		print("%s %-20s tris=%d surfaces=%d bones=%d aabb=%s clips=%s glow_tex=%s %s" % ["PASS" if ok else "FAIL", id, r["tris"], r["surfaces"], r["bones"], r["aabb"], r["clips"], r["glow"], r["notes"]])
	for m in MATERIALS:
		var res := load("res://assets/incoming/region1/rift/materials/%s.tres" % m)
		var ok := res != null
		if ok and res is ShaderMaterial:
			ok = (res as ShaderMaterial).shader != null
		print("%s material %s" % ["PASS" if ok else "FAIL", m])
		if not ok:
			fails += 1
	var scenes := ["res://assets/incoming/region1/rift/decals/rift_decal.tscn", "res://assets/incoming/region1/rift/decals/rift_decal_card.tscn"]
	for s in scenes:
		var ps := load(s) as PackedScene
		var ok := ps != null and ps.instantiate() != null
		print("%s scene %s" % ["PASS" if ok else "FAIL", s.get_file()])
		if not ok:
			fails += 1
	print("JSON ", JSON.stringify(report))
	quit(0 if fails == 0 else 1)


func _check(id: String, cfg: Dictionary) -> Dictionary:
	var out := {"ok": false, "tris": 0, "surfaces": 0, "bones": 0, "aabb": "", "clips": [], "glow": false, "notes": ""}
	var ps := load(cfg["path"]) as PackedScene
	if ps == null:
		out["notes"] = "does not load"
		return out
	var root := ps.instantiate()
	var box := AABB()
	var first := true
	var notes: Array[String] = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			out["surfaces"] += 1
			var arr := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			out["tris"] += (idx.size() if idx.size() > 0 else verts.size()) / 3
			var mat := m.surface_get_material(s)
			if mat is BaseMaterial3D:
				var b := mat as BaseMaterial3D
				if b.emission_enabled and (b.emission_texture != null or b.emission_energy_multiplier > 0.0):
					out["glow"] = true
					if b.emission_texture != null:
						notes.append("emission_texture")
				if b.emission_enabled and b.emission_energy_multiplier > 2.0:
					notes.append("strong emission %.1f" % b.emission_energy_multiplier)
		var bb := (mi as MeshInstance3D).global_transform * m.get_aabb() if (mi as MeshInstance3D).is_inside_tree() else m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	out["aabb"] = "%.2f x %.2f x %.2f (y0 %.2f)" % [box.size.x, box.size.y, box.size.z, box.position.y]
	for sk in root.find_children("*", "Skeleton3D", true, false):
		out["bones"] += (sk as Skeleton3D).get_bone_count()
	var clips: Array = []
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		for a in (ap as AnimationPlayer).get_animation_list():
			clips.append("%s(%.2fs)" % [a, (ap as AnimationPlayer).get_animation(a).length])
	out["clips"] = clips
	var missing: Array[String] = []
	for want in cfg["clips"]:
		var found := false
		for c in clips:
			if String(c).begins_with(want + "(") or String(c).to_lower().contains(want):
				found = true
		if not found:
			missing.append(want)
	if missing.size() > 0:
		notes.append("missing clips " + ",".join(missing))
	if out["tris"] > int(cfg["tris_max"]):
		notes.append("over tri budget %d" % cfg["tris_max"])
	if cfg["glow"] and not out["glow"]:
		notes.append("no emissive material found")
	out["notes"] = "; ".join(notes)
	out["ok"] = out["tris"] > 0 and missing.is_empty() and out["tris"] <= int(cfg["tris_max"]) and (not cfg["glow"] or out["glow"])
	root.free()
	return out
