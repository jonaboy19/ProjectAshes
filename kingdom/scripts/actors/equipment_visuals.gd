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
## horizontal bar). hand_l has its own seat: the left hand bone is mirrored and yawed out, so the right-hand seat put the
## blade across the body; -90 about Z with the arm's yaw taken out.
const SEAT := {
	"hand_r": [Vector3(0.05, 0.02, 0.0), Vector3(0, 0, -135)],
	"hand_l": [Vector3(0.05, 0.02, 0.0), Vector3(0, 0, -90)],
	"lowerarm_l": [Vector3(0.12, 0.0, 0.08), Vector3(0, 90, 0)],
}
## Models whose long axis is not +Y get their own seat per bone (solved in the idle pose with
## tools_qa/visual_pass/weapons_fit_standalone.gd, which prints the bone-local Euler that stands the prop up):
## a bow's limbs run along model X and belly toward -Z, so it is stood upright with the string facing the archer; a crossbow's
## stock runs along model +Z and points where the body faces.
const SEAT_BY_FIT := {
	"bow_a": {"hand_r": [Vector3(0.05, 0.02, 0.0), Vector3(-30, 0, -90)], "hand_l": [Vector3(0.05, 0.02, 0.0), Vector3(-28, -20, -90)]},
	"bow_b": {"hand_r": [Vector3(0.05, 0.02, 0.0), Vector3(-30, 0, -90)], "hand_l": [Vector3(0.05, 0.02, 0.0), Vector3(-28, -20, -90)]},
	"crossbow": {"hand_r": [Vector3(0.05, 0.02, 0.0), Vector3(-30, 0, -170)]},
}

## Held weapons are fitted by LENGTH, not by the model's native units (the KayKit weapon bits are 1.8-3.3 units long, so
## "scale 1.0" drew a 3 m blade): model basename prefix -> [length in metres of the longest axis (visuals.json "scale"
## multiplies it), grip position along the long axis from the butt (0..1), -1 = the model origin already is the grip,
## optional: the long axis index 0 = X, 1 = Y (default), 2 = Z].
const WEAPON_FIT := {
	"dagger": [0.38, -1.0], "sword": [0.95, -1.0], "axe": [0.75, -1.0], "hammer": [0.9, -1.0],
	"spear": [2.0, 0.40], "halberd": [2.0, 0.40], "staff": [1.7, 0.38], "wand": [0.42, -1.0],
	"bow_a": [1.0, -1.0, 0], "bow_b": [1.25, -1.0, 0], "crossbow": [0.75, 0.3, 2], "fist": [0.28, -1.0],
}

var skeleton: Skeleton3D
var equipment: Object
var _nodes: Dictionary = {}          # slot -> Array[BoneAttachment3D] added by this object
var _hidden: Dictionary = {}         # slot -> Array[Node3D] default props hidden for it
var _defaults: Dictionary = {}       # lower-case bone name -> Array[BoneAttachment3D] that existed before (starter gear)
var _two_hidden: Array = []          # off-hand attachments hidden because a two-handed weapon is wielded

## Weapon classes (docs/plans/AAA_PROGRESS.md equipment matrix): polearm / great (two-handed, carried upright, left hand assists in
## combat) and bow (two-handed, no shield). Everything else is one-handed.
const TWO_HANDED := ["polearm", "great", "bow"]
## Longest side (m) of a shield model of the off hand, by item id: a bare model is far bigger than a held shield.
const SHIELD_LEN := {"buckler": 0.38, "kite": 0.85, "default": 0.62}


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
		var fit := fit_for(String(v.get("model", "")))
		var seat: Array = SEAT.get(String(bones[i]), [Vector3.ZERO, Vector3.ZERO])
		var by_fit: Dictionary = SEAT_BY_FIT.get(fit_key(String(v.get("model", ""))), {})
		if by_fit.has(String(bones[i])):
			seat = by_fit[String(bones[i])]
		var seat_pos: Vector3 = seat[0]
		var rot_deg: Vector3 = seat[1]
		if not fit.is_empty() and prop.get_child_count() > 0:
			var inst := prop.get_child(0) as Node3D
			var box := Assets.visual_aabb(inst)
			var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
			var axis_i := int(fit[2]) if fit.size() > 2 else 1
			var axis := Vector3.ZERO
			axis[axis_i] = 1.0
			if longest > 0.001:
				var mirror := signf(prop.scale.x)
				var k := float(fit[0]) * absf(prop.scale.y) / longest       # metres per model unit
				prop.scale = Vector3(k * mirror, k, k)
				seat_pos -= Basis.from_euler(rot_deg * (PI / 180.0)) * axis * (box.position[axis_i] + float(fit[1]) * box.size[axis_i]) * k \
					if float(fit[1]) >= 0.0 else Vector3.ZERO
				style_weapon(inst)
		if String(bones[i]) == "lowerarm_l" and fit.is_empty() and prop.get_child_count() > 0:
			# held shields are fitted by size too (the raw models are up to 1.4 m across)
			var sbox := Assets.visual_aabb(prop.get_child(0) as Node3D)
			var slong := maxf(sbox.size.x, maxf(sbox.size.y, sbox.size.z))
			var want: float = SHIELD_LEN["buckler"] if id.contains("buckler") else (SHIELD_LEN["kite"] if id.contains("kite") else SHIELD_LEN["default"])
			if slong > 0.001:
				prop.scale = prop.scale * (want * absf(float(v.get("scale", 1.0))) / slong)
		prop.scale = prop.scale / rig_scale
		prop.position = seat_pos / rig_scale
		prop.rotation_degrees = rot_deg
		var wc := _weapon_class(id, String(v.get("model", "")))
		if wc != "" and String(bones[i]).begins_with("hand"):
			prop.set_meta(&"wclass", wc)
			var fa := fit_for(String(v.get("model", "")))
			prop.set_meta(&"axis", Vector3(0, 1, 0) if fa.size() < 3 else (Vector3(1, 0, 0) if int(fa[2]) == 0 else Vector3(0, 0, 1)))
			prop.set_meta(&"grip2", 0.5 if wc == "polearm" else -0.22)
		if fit_key(String(v.get("model", ""))) == "" and String(v.get("model", "")).get_file().get_basename() == "torch":
			_add_flame(prop)
			prop.set_meta(&"wclass", "torch")       # held upright by the rig (ProceduralRig._two_hand_rest), whatever the hand does
			prop.set_meta(&"axis", Vector3(0, 1, 0))
		att.add_child(prop)
		list.append(att)
	if list.is_empty():
		return
	_nodes[slot] = list
	# Starter gear on the same bones makes way for the real item (a held off-hand item also takes the starter shield off the arm).
	var hide: Array = []
	var make_way: Array = bones.duplicate()
	if slot == "off_hand" and bones.has("hand_l"):
		make_way.append("lowerarm_l")
	for b: String in make_way:
		for d: BoneAttachment3D in _defaults.get(b.to_lower(), []):
			if is_instance_valid(d) and d.visible:
				d.visible = false
				hide.append(d)
	if not hide.is_empty():
		_hidden[slot] = hide
	_update_two_handed()


## "polearm" | "great" | "bow" | "" (one-handed / not a weapon) from the item id and model.
static func _weapon_class(id: String, model: String) -> String:
	var base := model.get_file().get_basename().to_lower()
	if id.contains("greatsword") or id.contains("battleaxe") or id.contains("warhammer"):
		return "great"
	if base.begins_with("spear") or base.begins_with("halberd") or base.begins_with("staff") 			or base in ["shovel", "fishing_rod", "pitchfork", "hoe", "rake"]:      # long tools: carried upright, both hands in use
		return "polearm"
	if base.begins_with("bow") or base.begins_with("crossbow"):
		return "bow"
	return ""


## A two-handed weapon in the main hand takes the shield (starter and equipped) off the arm; it comes back when the weapon goes.
func _update_two_handed() -> void:
	var two := false
	for att in _nodes.get("main_hand", []):
		for c in (att as Node).get_children():
			if c.has_meta(&"wclass") and TWO_HANDED.has(String(c.get_meta(&"wclass"))):
				two = true
	for d in _two_hidden:
		if is_instance_valid(d):
			(d as Node3D).visible = true
	_two_hidden.clear()
	if not two:
		return
	var shields: Array = (_defaults.get("lowerarm_l", []) as Array).duplicate()
	for att in _nodes.get("off_hand", []):
		shields.append(att)
	for d in shields:
		if is_instance_valid(d) and (d as Node3D).visible:
			(d as Node3D).visible = false
			_two_hidden.append(d)


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
	_update_two_handed()


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
	var key := fit_key(model_path)
	return WEAPON_FIT[key] if key != "" else []


## The WEAPON_FIT key ("sword", "bow_b", ...) a weapon model path matches, "" for anything that is not a held weapon.
static func fit_key(model_path: String) -> String:
	if not model_path.contains("/weapons/"):
		return ""
	var base := model_path.get_file().get_basename().to_lower()
	for key: String in WEAPON_FIT:
		if base.begins_with(key):
			return key
	return ""


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


## A lit torch: a flickering warm light and a small flame sprite at the rag wrap (model space, +Y up the stick, 0.38 m).
static func _add_flame(prop: Node3D) -> void:
	var top := Node3D.new()
	top.name = "Flame"
	top.position = Vector3(0, 0.47, 0)
	prop.add_child(top)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.66, 0.32)
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.shadow_enabled = false
	top.add_child(light)
	var fire := GPUParticles3D.new()
	fire.amount = 36
	fire.lifetime = 0.45
	fire.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
	grad.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	fire.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.13, 0.17)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	var soft := GradientTexture2D.new()          # a soft round flame puff, not a square
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var sg := Gradient.new()
	sg.set_color(0, Color(1, 1, 1, 1))
	sg.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = sg
	qm.albedo_texture = soft
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.billboard_keep_scale = true
	q.material = qm
	fire.draw_pass_1 = q
	top.add_child(fire)
	light.set_meta(&"flicker", true)
