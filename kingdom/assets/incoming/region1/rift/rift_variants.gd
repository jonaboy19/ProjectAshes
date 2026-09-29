class_name RiftVariants
extends RefCounted
## Region 1 rift-touched kit (L4): material swap helpers. Nothing here duplicates a mesh: a rift tree is the
## normal region nature mesh with the RG_* materials replaced by the rift_*.tres materials in this folder.
##
##   var tree := MeshInstance3D.new()
##   tree.mesh = Assets.nature_mesh("region/nature/oak_a")
##   RiftVariants.apply(tree)                       # surface overrides, the shared mesh is untouched
##
##   var wolf: Node3D = load(".../wolf_lod1.glb").instantiate()
##   RiftVariants.apply_creature(wolf, "wolf", true)   # lod1 texture
##
## `amount` is not a shader blend: call apply() only on rift-touched instances (a spreading front can swap
## one tree at a time when the corruption reaches it, see mechanic N2).

const DIR := "res://assets/incoming/region1/rift/materials/"
const SWAP := {
	"rg_foliage": "rift_foliage",
	"rg_foliage_ground": "rift_foliage_ground",
	"rg_bark": "rift_bark",
	"rg_rock": "rift_rock",
	"rg_moss": "rift_moss",
}

static var _cache: Dictionary = {}


static func material(name: String) -> Material:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".tres")
	return _cache[name]


## The rift material for a region-nature surface material, or null if it has no rift variant.
## Works on the ShaderMaterial the game already swapped in (rg_foliage.tres ...) and on a raw GLB
## material named RG_Foliage / RG_Bark / RG_Rock / RG_Moss (pass ground=true for grass, flowers, ferns).
static func variant_for(m: Material, ground := false) -> Material:
	if m == null:
		return null
	var key := ""
	if m.resource_path != "":
		key = m.resource_path.get_file().get_basename().to_lower()
	if not SWAP.has(key):
		var n := String(m.resource_name).to_lower()
		if n.begins_with("rg_foliage"):
			key = "rg_foliage_ground" if ground else "rg_foliage"
		elif n.begins_with("rg_bark"):
			key = "rg_bark"
		elif n.begins_with("rg_rock"):
			key = "rg_rock"
		elif n.begins_with("rg_moss"):
			key = "rg_moss"
		elif n.begins_with("rg_impostor"):
			return material("rift_impostor")
	if not SWAP.has(key):
		return null
	return material(SWAP[key])


## Swap every region-nature surface under `root` (MeshInstance3D or a node tree) to its rift variant.
static func apply(root: Node, ground := false) -> int:
	var swapped := 0
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for n in nodes:
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var v := variant_for(mi.get_active_material(i), ground)
			if v != null:
				mi.set_surface_override_material(i, v)
				swapped += 1
	return swapped


## Rift wolf / boar: one violet-fur material for the whole creature (Meshy creatures have one surface).
static func apply_creature(root: Node, kind: String, lod1 := true) -> int:
	var m := material("rift_%s%s" % [kind, "_lod1" if lod1 else ""])
	var n := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = m
		n += 1
	return n
