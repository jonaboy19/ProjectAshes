extends RefCounted
## Shows what the character wears and wields: when Equipment.changed(slot, item_id) fires, ItemsDB.visual_node(id) is put on
## the skeleton's bone(s) named by data/items/visuals.json ("attach": hand_r, hand_l, hand = both hands, lowerarm_l = shield,
## head, spine_03 = chest, pelvis, foot / calf = both feet / shins) and removed again on unequip or when the slot changes.
## Event driven: nothing runs per frame. Props are BoneAttachment3Ds named "Eq_<slot>_<n>" under the skeleton.
##
## The default hero's starter sword and shield (Assets._attach, plain BoneAttachment3Ds on the same bones) are hidden while an
## item of that slot has its own model, and shown again on unequip. Created and owned by player.gd (_build_body); call
## detach() before dropping one. No class_name.

const ItemsDB := preload("res://scripts/sim/items_db.gd")

## visuals.json "attach" -> bones that receive a copy (the second one gets the mirrored / left variant of the model).
const BONES := {
	"hand_r": ["hand_r"], "hand_l": ["hand_l"], "hand": ["hand_r", "hand_l"], "lowerarm_l": ["lowerarm_l"],
	"head": ["head"], "spine_03": ["spine_03"], "pelvis": ["pelvis"],
	"foot": ["foot_r", "foot_l"], "calf": ["calf_r", "calf_l"],
}
## Seating of a prop on its bone (metres, degrees): blade along the hand bone, cocked 45 degrees (-135 about the bone Z) so the
## idle blade rides up and out instead of lying flat across the hip (the UAL idle turns the palm forward, so -90 read as a
## horizontal bar). hand_l keeps the plain -90.
const SEAT := {
	"hand_r": [Vector3(0.05, 0.02, 0.0), Vector3(0, 0, -135)],
	"hand_l": [Vector3(0.05, 0.02, 0.0), Vector3(0, 0, -90)],
	"lowerarm_l": [Vector3(0.12, 0.0, 0.08), Vector3(0, 90, 0)],
}

## Held weapons are fitted by LENGTH, not by the model's native units (the KayKit weapon bits are 1.8-3.3 units long, so
## "scale 1.0" drew a 3 m blade): model basename prefix -> [length in metres of the longest axis (visuals.json "scale"
## multiplies it), grip position along the long axis from the butt (0..1), -1 = the model origin already is the grip].
const WEAPON_FIT := {
	"dagger": [0.38, -1.0], "sword": [0.95, -1.0], "axe": [0.75, -1.0], "hammer": [0.9, -1.0],
	"spear": [2.0, 0.40], "halberd": [2.0, 0.40], "staff": [1.7, 0.38], "wand": [0.42, -1.0],
	"bow_a": [1.0, -1.0], "bow_b": [1.25, -1.0], "crossbow": [0.75, -1.0], "fist": [0.28, -1.0],
}

var skeleton: Skeleton3D
var equipment: Object
var _nodes: Dictionary = {}          # slot -> Array[BoneAttachment3D] added by this object
var _hidden: Dictionary = {}         # slot -> Array[Node3D] default props hidden for it
var _defaults: Dictionary = {}       # lower-case bone name -> Array[BoneAttachment3D] that existed before (starter gear)


func _init(sk: Skeleton3D, eq: Object) -> void:
	skeleton = sk
	equipment = eq
	if skeleton == null or equipment == null:
		return
	for a in skeleton.find_children("*", "BoneAttachment3D", false, false):
		var att := a as BoneAttachment3D
		var key := att.bone_name.to_lower()
		if not _defaults.has(key):
			_defaults[key] = []
		(_defaults[key] as Array).append(att)
	equipment.changed.connect(_on_changed)
	for slot: String in equipment.slots:
		_set_slot(slot, String(equipment.slots[slot].get("id", "")))


## Disconnects and removes everything this object added (the character is being rebuilt or freed).
func detach() -> void:
	if equipment != null and is_instance_valid(equipment) and equipment.changed.is_connected(_on_changed):
		equipment.changed.disconnect(_on_changed)
	for slot: String in _nodes.keys():
		_clear_slot(slot)
	equipment = null


## Number of prop attachments currently shown (QA, tests).
func attachment_count() -> int:
	var n := 0
	for slot: String in _nodes:
		n += (_nodes[slot] as Array).size()
	return n


func attachments_for(slot: String) -> Array:
	return (_nodes.get(slot, []) as Array).duplicate()


func _on_changed(slot: String, item_id: String) -> void:
	_set_slot(slot, item_id)


func _set_slot(slot: String, id: String) -> void:
	_clear_slot(slot)
	if id == "" or skeleton == null or not is_instance_valid(skeleton):
		return
	var v := ItemsDB.visual(id)
	if v.is_empty() or not v.has("model"):
		return
	var bones: Array = BONES.get(String(v.get("attach", "")), [])
	var rig_scale: float = Assets._rig_scale(skeleton)   # the same conversion the starter weapons use
	var list: Array = []
	for i in bones.size():
		var bone := _bone(String(bones[i]))
		if bone == "":
			continue
		var prop := ItemsDB.visual_node(id, i == 1)
		if prop == null:
			continue
		if i == 1 and not v.has("model_l") and not bool(v.get("mirror_l", false)):
			prop.scale.x = -prop.scale.x     # the second foot / hand of a pair: mirrored copy
		var att := BoneAttachment3D.new()
		att.name = "Eq_%s_%d" % [slot, i]
		att.bone_name = bone
		skeleton.add_child(att)
		# Bone space is the rig's own units (the UE rig is in centimetres under a scaled Armature).
		var seat: Array = SEAT.get(String(bones[i]), [Vector3.ZERO, Vector3.ZERO])
		var seat_pos: Vector3 = seat[0]
		var rot_deg: Vector3 = seat[1]
		var fit := fit_for(String(v.get("model", "")))
		if not fit.is_empty() and prop.get_child_count() > 0:
			var inst := prop.get_child(0) as Node3D
			var box := Assets.visual_aabb(inst)
			var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
			if longest > 0.001:
				var mirror := signf(prop.scale.x)
				var k := float(fit[0]) * absf(prop.scale.y) / longest       # metres per model unit
				prop.scale = Vector3(k * mirror, k, k)
				seat_pos -= Basis.from_euler(rot_deg * (PI / 180.0)) * Vector3(0, box.position.y + float(fit[1]) * box.size.y, 0) * k \
					if float(fit[1]) >= 0.0 else Vector3.ZERO
				style_weapon(inst)
		prop.scale = prop.scale / rig_scale
		prop.position = seat_pos / rig_scale
		prop.rotation_degrees = rot_deg
		att.add_child(prop)
		list.append(att)
	if list.is_empty():
		return
	_nodes[slot] = list
	# Starter gear on the same bones makes way for the real item.
	var hide: Array = []
	for b: String in bones:
		for d: BoneAttachment3D in _defaults.get(b.to_lower(), []):
			if is_instance_valid(d) and d.visible:
				d.visible = false
				hide.append(d)
	if not hide.is_empty():
		_hidden[slot] = hide


func _clear_slot(slot: String) -> void:
	for att in _nodes.get(slot, []):
		if is_instance_valid(att):
			var a := att as Node
			if a.get_parent() != null:
				a.get_parent().remove_child(a)
			a.free()
	_nodes.erase(slot)
	for d in _hidden.get(slot, []):
		if is_instance_valid(d):
			(d as Node3D).visible = true
	_hidden.erase(slot)


## The skeleton's bone matching `name` ignoring case ("head" finds the UAL rig's "Head"); "" when absent.
func _bone(name: String) -> String:
	var i := skeleton.find_bone(name)
	if i >= 0:
		return name
	var low := name.to_lower()
	for k in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(k)
		if bn.to_lower() == low:
			return bn
	return ""


## [length_m, grip_fraction] for a weapon model path (visuals.json "model"), [] for anything that is not a held weapon.
static func fit_for(model_path: String) -> Array:
	if not model_path.contains("/weapons/"):
		return []
	var base := model_path.get_file().get_basename().to_lower()
	for key: String in WEAPON_FIT:
		if base.begins_with(key):
			return WEAPON_FIT[key]
	return []


## Style G for held metal and wood: the item's tint (flat bronze #d9a15a read as neon orange) is pulled toward grey and
## darkened, with a little metal and a soft roughness so the blade catches the sun instead of being a flat colour.
static func style_weapon(inst: Node) -> void:
	if inst is MeshInstance3D:
		var mi := inst as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_surface_override_material(i)
				if src == null:
					src = mi.mesh.surface_get_material(i)
				if src is StandardMaterial3D:
					var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					var c := m.albedo_color
					var grey := c.get_luminance()
					m.albedo_color = Color(c.r, c.g, c.b).lerp(Color(grey, grey, grey), 0.38) * 0.88
					m.metallic = 0.3
					m.metallic_specular = 0.6
					m.roughness = 0.55
					mi.set_surface_override_material(i, m)
	for ch in inst.get_children():
		style_weapon(ch)
