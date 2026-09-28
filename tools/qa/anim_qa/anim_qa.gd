extends SceneTree
## Animation QA for Rising Ashes. Loads every character / creature / animal type the
## game uses through the game's own loaders (Assets.mh_character, the CampMonster /
## Wolf / Critter setup), samples most clips at 30 fps and quadruped gaits at 120 fps,
## and measures foot sliding,
## ground penetration, floating, bone stretch, pops and loop seams, T-pose / scale
## leaks, root drift and clip speed vs. the movement speed the game drives it at.
## Optionally renders 8-frame side-view strips and contact sheets on the GPU.
##
## Run (from the repo root; see README.md):
##   godot --path kingdom -s <abs>/tools/qa/anim_qa/anim_qa.gd -- [--no-strips] [--only=<substr>]
## Outputs: docs/qa/anim_qa_report.md, docs/qa/anim_qa_results.csv, docs/qa/anim_strips/, docs/qa/anim_sheet_*.png

const FPS := 30.0
const CRITTER_GAIT_FPS := 120.0 # Short quadruped contacts can fall between 30 Hz samples.
const Catalog := preload("catalog.gd")

# ---- thresholds (see the report's "Thresholds" section for the reasoning) ----
const SLIDE_WARN := 8.0          # cm/s, p90 planted-foot slip vs. the clip's own ground speed
const SLIDE_FAIL := 20.0
const PEN_WARN := 2.0            # cm below the floor (lowest skinned vertex or foot joint)
const PEN_FAIL := 5.0
const HOVER_WARN := 3.0          # cm: lowest foot never touches the floor
const HOVER_FAIL := 6.0
const AIR_H := 5.0               # cm: a foot this far above its contact level counts as airborne
const AIR_WARN := 0.20           # s both feet airborne in a row (non-jump clips)
const AIR_FAIL := 0.35
const STRETCH_WARN := 1.0        # % bone length change vs. rest
const STRETCH_FAIL := 5.0
const SCALE_WARN := 1.0          # % bone scale away from 1
const SCALE_FAIL := 5.0
const POP_ABS := 25.0            # deg/frame^2 at 30 fps: angular acceleration spike ...
const POP_REL := 6.0             # ... that is also this many times the bone's p90 in the clip
const SEAM_WARN := 2.0           # deg pose gap at the loop seam
const SEAM_FAIL := 8.0
const SEAM_POS_WARN := 1.0       # cm hips gap at the loop seam
const SEAM_POS_FAIL := 3.0
const DRIFT_WARN := 3.0          # cm hips drift over one in-place loop
const DRIFT_FAIL := 8.0
const ONESHOT_MOVE_WARN := 40.0  # cm hips displacement in a one-shot (game does not use root motion)
const TPOSE_DEG := 4.0           # mean major-bone deviation from rest below this = T-pose frame
const STATIC_DEG := 0.5          # an idle loop moving less than this looks frozen
const SPEED_OK := [0.85, 1.18]   # game speed / clip ground speed
const SPEED_WARN := [0.7, 1.4]

const EXCLUDE_MAJOR := ["index", "middle", "ring", "pinky", "thumb", "leaf", "ik", "pole", "target",
	"_end", "headfront", "jaw", "tongue", "eye"]

var repo := ""
var out_dir := ""
var strips_on := true
var only := ""
var dump := ""
var results: Array[Dictionary] = []     # one per subject x clip
var natural := {}                        # "subject|clip" -> ground speed m/s
var subject_info := {}                   # id -> {height, group, ...}
var stage: Node3D


func _initialize() -> void:
	var here := (get_script() as Script).resource_path.get_base_dir()
	repo = here.path_join("../../..").simplify_path()
	out_dir = repo.path_join("docs/qa")
	for a in OS.get_cmdline_user_args():
		if a == "--no-strips":
			strips_on = false
		elif a.begins_with("--dump="):
			dump = a.substr(7)
		elif a.begins_with("--only="):
			only = a.substr(7)
	if DisplayServer.get_name() == "headless":
		strips_on = false
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("anim_strips"))
	_main()


func _main() -> void:
	await process_frame
	stage = Node3D.new()
	root.add_child(stage)
	var subs := Catalog.subjects()
	var t0 := Time.get_ticks_msec()
	for s in subs:
		if only != "" and not String(s["id"]).contains(only):
			continue
		var node := _build(s)
		if node == null:
			printerr("SKIP (missing) ", s["id"])
			continue
		stage.add_child(node)
		_analyse(s, node)
		node.queue_free()
		await process_frame
		print("analysed %-24s  %5.1fs" % [s["id"], (Time.get_ticks_msec() - t0) / 1000.0])
	var speeds := _speed_table()
	_write_csv()
	_write_report(speeds)
	if strips_on:
		await _render_all(subs, speeds)
	print("ANIM_QA_DONE rows=%d" % results.size())
	# Free the analysis stage and the strip-rendering SubViewport (root.add_child(vp) in
	# _setup_stage(), never freed) before quit(). Skipping this raced WorkerThreadPool/
	# RenderingServer teardown against live RIDs and produced the ntdll heap-corruption
	# crashes in the Windows event log -- see docs/qa/stability.md.
	if is_instance_valid(stage):
		stage.queue_free()
		stage = null
	if is_instance_valid(vp):
		vp.queue_free()
		vp = null
	for i in 10:
		await process_frame
	quit()


# ---------------------------------------------------------------------------------------
# Loading, mirroring the game code
# ---------------------------------------------------------------------------------------

func _build(s: Dictionary) -> Node3D:
	var file: String = s["file"]
	match String(s["kind"]):
		"ual":
			var probe := (file if file.contains("/") else Assets.MH_DIR + file) + ".glb"
			if not ResourceLoader.exists(probe):
				return null
			return Assets.mh_character(file, float(s["height"]))       # the game's loader
		"qmonster":     # CampMonster._ready
			if not ResourceLoader.exists(file):
				return null
			var model: Node3D = (load(file) as PackedScene).instantiate()
			var box := Assets.visual_aabb(model)
			model.scale = Vector3.ONE * (float(s["height"]) / maxf(box.size.y, 0.01))
			var holder := Node3D.new()
			holder.add_child(model)
			_set_loops(model, s)
			if s.has("tint"):
				_tint(model, s["tint"])
			return holder
		"qwolf":        # Wolf._ready
			var model: Node3D = (load(file) as PackedScene).instantiate()
			var box := Assets.visual_aabb(model)
			model.scale = Vector3.ONE * (0.85 / maxf(box.size.y, 0.01))
			var holder := Node3D.new()
			holder.add_child(model)
			_set_loops(model, s)
			return holder
		_:              # Meshy creatures and Critter: native scale
			if not ResourceLoader.exists(file):
				return null
			var model: Node3D = (load(file) as PackedScene).instantiate()
			var holder := Node3D.new()
			holder.add_child(model)
			_set_loops(model, s)
			return holder


func _set_loops(model: Node, s: Dictionary) -> void:
	var ap := Assets.animation_player(model)
	if ap == null:
		return
	for a: String in s.get("loops", []):
		if ap.has_animation(a):
			ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR


func _tint(model: Node, tint: Color) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m is BaseMaterial3D:
				var d := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.albedo_color = d.albedo_color * tint
				mi.set_surface_override_material(i, d)


# ---------------------------------------------------------------------------------------
# Rig helpers
# ---------------------------------------------------------------------------------------

class Rig:
	var sk: Skeleton3D
	var ap: AnimationPlayer
	var feet: Array = []          # Array of PackedInt32Array (bones of one foot)
	var foot_rest: Array = []     # per foot: PackedFloat32Array rest heights (world) of its bones
	var foot_verts: Array = []    # per foot: PackedInt32Array of sole-region vertex indices (into vpos)
	var vrest_y := PackedFloat32Array()
	var vrest_p := PackedVector3Array()
	var hips := -1
	var hip_chain := {}           # hips and its ancestors: translated by design, not "bones" to stretch
	var stretch_ok: Array[bool] = []   # bones whose parent link is a real rigid bone
	var major := PackedInt32Array()
	var rest_len := PackedFloat32Array()
	var rest_rot: Array[Quaternion] = []
	# sampled skin vertices
	var vpos := PackedVector3Array()
	var vbind := PackedInt32Array()   # 4 per vertex, index into binds
	var vw := PackedFloat32Array()
	var bind_bone := PackedInt32Array()
	var bind_pose: Array[Transform3D] = []
	var height := 1.0
	var length := 1.0
	var rest_min_y := 0.0
	var face := 1.0
	var center_z := 0.0


func _make_rig(s: Dictionary, node: Node3D) -> Rig:
	var r := Rig.new()
	var sks := node.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	# the skeleton with most bones
	r.sk = sks[0]
	for k in sks:
		if (k as Skeleton3D).get_bone_count() > r.sk.get_bone_count():
			r.sk = k
	r.ap = Assets.animation_player(node)
	var sk := r.sk
	sk.reset_bone_poses()
	var xf := sk.global_transform
	var n := sk.get_bone_count()
	for b in n:
		r.rest_rot.append(sk.get_bone_rest(b).basis.get_rotation_quaternion())
		var p := sk.get_bone_parent(b)
		var l := 0.0
		if p >= 0:
			l = (xf * sk.get_bone_global_rest(b).origin).distance_to(xf * sk.get_bone_global_rest(p).origin)
		r.rest_len.append(l)
		var nm := sk.get_bone_name(b).to_lower()
		var skip := false
		skip = nm.begins_with("ear")
		for e: String in EXCLUDE_MAJOR:
			if nm.contains(e):
				skip = true
		if not skip:
			r.major.append(b)
	_collect_vertices(r, node)
	# feet: named foot bones for the UAL rig; everything else clusters its sole vertices
	var feet_names: Array = s["feet"] if String(s["kind"]) == "ual" else []
	if feet_names.is_empty():
		_cluster_feet(r)
	for f: Array in feet_names:
		var ids := PackedInt32Array()
		var rh := PackedFloat32Array()
		for bn: String in f:
			var b := sk.find_bone(bn)
			if b >= 0:
				ids.append(b)
				rh.append((xf * sk.get_bone_global_rest(b).origin).y - r.rest_min_y)
		if not ids.is_empty():
			r.feet.append(ids)
			r.foot_rest.append(rh)
	# sole vertices per foot: feet-region vertices whose strongest bone is in the foot's subtree
	for f: PackedInt32Array in (r.feet if r.foot_verts.is_empty() else []):
		var sub := {}
		for b in f:
			sub[b] = true
		var grew := true
		while grew:
			grew = false
			for b in n:
				if not sub.has(b) and sub.has(sk.get_bone_parent(b)):
					sub[b] = true
					grew = true
		var fv := PackedInt32Array()
		for v in r.vpos.size():
			if r.vrest_y[v] < r.height * 0.06 and r.vw[v * 4] > 0.0 and sub.has(r.bind_bone[r.vbind[v * 4]]):
				fv.append(v)
		r.foot_verts.append(fv)
	if dump != "":
		for fi in r.foot_verts.size():
			var fvv: PackedInt32Array = r.foot_verts[fi]
			var lo := 0
			for k in fvv.size():
				if r.vrest_y[fvv[k]] < r.vrest_y[fvv[lo]]:
					lo = k
			var v := fvv[lo]
			var desc := ""
			for k in 4:
				desc += "%s:%.2f " % [sk.get_bone_name(r.bind_bone[r.vbind[v * 4 + k]]), r.vw[v * 4 + k]]
			print("  foot %d lowest rest vert y=%.3f %s" % [fi, r.vrest_y[v], desc])
		var glo := 0
		for v in r.vpos.size():
			if r.vrest_y[v] < r.vrest_y[glo]:
				glo = v
		var gd := ""
		for k in 4:
			gd += "%s:%.2f " % [sk.get_bone_name(r.bind_bone[r.vbind[glo * 4 + k]]), r.vw[glo * 4 + k]]
		print("  global lowest vert %s at %s" % [gd, r.vrest_p[glo]])
	r.hips = _lca(r)
	var hb := r.hips
	while hb >= 0:
		r.hip_chain[hb] = true
		hb = sk.get_bone_parent(hb)
	# no feet (e.g. unknown rig): treat top-level bones as translated roots
	for b in n:
		if sk.get_bone_parent(b) < 0:
			r.hip_chain[b] = true
	# stretch is only meaningful for a bone hanging off a real bone: skip the hips chain,
	# helpers parented above the hips (IK targets, poles) and IK-named bones
	for b in n:
		var p := sk.get_bone_parent(b)
		var nm := sk.get_bone_name(b).to_lower()
		var ok := p >= 0 and not r.hip_chain.has(b) and not (r.hip_chain.has(p) and p != r.hips)
		for e in ["ik", "pole", "target"]:
			if nm.contains(e):
				ok = false
		r.stretch_ok.append(ok)
	return r


## Feet for non-UAL rigs: cluster the sole-region vertices (bottom 6 % of the body at
## rest) by rest position; each cluster is one foot / paw / hoof. Tail and wing
## vertices are ignored. Also sets r.feet (dominant bone per foot) for the hips LCA.
func _cluster_feet(r: Rig) -> void:
	var cand := PackedInt32Array()
	for v in r.vpos.size():
		if r.vrest_y[v] >= r.height * 0.06 or r.vw[v * 4] <= 0.0:
			continue
		var bn := r.sk.get_bone_name(r.bind_bone[r.vbind[v * 4]])
		var lbn := bn.to_lower()
		if lbn.contains("tail") or lbn.contains("wing") or lbn.begins_with("ear") or lbn.contains("finger"):
			continue
		cand.append(v)
	var d := clampf(0.045 * r.height, 0.012, 0.12)
	var parent: Array[int] = []   # Array (reference type) so the lambda sees updates
	parent.resize(cand.size())
	for i in cand.size():
		parent[i] = i
	var find := func(x: int) -> int:
		while parent[x] != x:
			x = parent[x]
		return x
	for i in cand.size():
		var pi: Vector3 = r.vrest_p[cand[i]]
		for j in range(i + 1, cand.size()):
			var pj: Vector3 = r.vrest_p[cand[j]]
			if Vector2(pi.x - pj.x, pi.z - pj.z).length() < d:
				var a: int = find.call(i)
				var b: int = find.call(j)
				if a != b:
					parent[a] = b
	var groups := {}
	for i in cand.size():
		var root_i: int = find.call(i)
		if not groups.has(root_i):
			groups[root_i] = []
		(groups[root_i] as Array).append(cand[i])
	var lst: Array = groups.values()
	lst.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	if lst.is_empty():
		return
	var biggest: int = (lst[0] as Array).size()
	for ga: Array in lst:
		var g := PackedInt32Array(ga)
		if g.size() < maxi(3, biggest / 8) or r.foot_verts.size() >= 8:
			continue
		r.foot_verts.append(g)
		var votes := {}
		for v in g:
			var b := r.bind_bone[r.vbind[v * 4]]
			votes[b] = votes.get(b, 0) + 1
		var best := -1
		for b: int in votes:
			if best < 0 or votes[b] > votes[best]:
				best = b
		r.feet.append(PackedInt32Array([best]))
		r.foot_rest.append(PackedFloat32Array([(r.sk.global_transform * r.sk.get_bone_global_rest(best).origin).y - r.rest_min_y]))


func _auto_feet(r: Rig) -> Array:
	# Lowest bone ends of the legs: leaf-most bones (ignoring tails, ears, IK helpers)
	# whose rest joint sits in the bottom 15 % of the body.
	var sk := r.sk
	var xf := sk.global_transform
	var has_child := {}
	for b in sk.get_bone_count():
		var p := sk.get_bone_parent(b)
		if p >= 0 and _usable_leg_bone(sk.get_bone_name(b)):
			has_child[p] = true
	var out: Array = []
	for b in sk.get_bone_count():
		if has_child.has(b) or not _usable_leg_bone(sk.get_bone_name(b)):
			continue
		var y := (xf * sk.get_bone_global_rest(b).origin).y - r.rest_min_y
		if y < r.height * 0.15:
			out.append([sk.get_bone_name(b)])
	return out


func _usable_leg_bone(n: String) -> bool:
	var l := n.to_lower()
	for e in ["tail", "ik", "pole", "target", "jaw", "tongue", "eye", "wing", "finger"]:
		if l.contains(e):
			return false
	return true


func _lca(r: Rig) -> int:
	if r.feet.is_empty():
		return 0
	var chains: Array = []
	for f: PackedInt32Array in r.feet:
		var c := []
		var b := f[0]
		while b >= 0:
			c.append(b)
			b = r.sk.get_bone_parent(b)
		chains.append(c)
	for b: int in chains[0]:
		var ok := true
		for c: Array in chains:
			if not c.has(b):
				ok = false
		if ok:
			return b
	return 0


func _collect_vertices(r: Rig, node: Node3D) -> void:
	var sk := r.sk
	var all_pos := PackedVector3Array()
	var all_b := PackedInt32Array()
	var all_w := PackedFloat32Array()
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var msk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if msk != sk:
			continue
		var skin := mi.skin
		var base := r.bind_bone.size()
		if skin:
			for i in skin.get_bind_count():
				var bb := skin.get_bind_bone(i)
				if bb < 0:
					bb = sk.find_bone(skin.get_bind_name(i))
				r.bind_bone.append(maxi(bb, 0))
				r.bind_pose.append(skin.get_bind_pose(i))
		else:
			for i in sk.get_bone_count():
				r.bind_bone.append(i)
				r.bind_pose.append(sk.get_bone_global_rest(i).affine_inverse())
		for surf in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(surf)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_BONES] == null:
				continue
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
			for v in verts.size():
				all_pos.append(verts[v])
				# keep the 4 strongest influences
				var pairs := []
				for k in per:
					pairs.append([weights[v * per + k], bones[v * per + k]])
				pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
				for k in 4:
					if k < pairs.size():
						all_b.append(base + int(pairs[k][1]))
						all_w.append(float(pairs[k][0]))
					else:
						all_b.append(base)
						all_w.append(0.0)
	# skin at rest to find floor / height, then keep feet-region verts + a stride sample
	var mats := _bind_mats(r)
	var rest_y := PackedFloat32Array()
	var rest_p := PackedVector3Array()
	var mn := INF
	var mx := -INF
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	for v in all_pos.size():
		var p := _skin(all_pos[v], all_b, all_w, v, mats)
		rest_y.append(p.y)
		rest_p.append(p)
		mn = minf(mn, p.y)
		mx = maxf(mx, p.y)
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
	if all_pos.is_empty():
		mn = 0.0
		mx = 1.0
	r.rest_min_y = mn
	r.height = maxf(mx - mn, 0.05)
	r.length = maxf(maxf(maxx - minx, maxz - minz), 0.05)
	r.center_z = (minz + maxz) * 0.5 if all_pos.size() > 0 else 0.0
	var stride := maxi(1, all_pos.size() / 900)
	for v in all_pos.size():
		if rest_y[v] - mn < r.height * 0.06 or v % stride == 0:
			r.vpos.append(all_pos[v])
			r.vrest_y.append(rest_y[v] - mn)
			r.vrest_p.append(rest_p[v])
			for k in 4:
				r.vbind.append(all_b[v * 4 + k])
				r.vw.append(all_w[v * 4 + k])


func _bind_mats(r: Rig) -> Array[Transform3D]:
	var xf := r.sk.global_transform
	var out: Array[Transform3D] = []
	for i in r.bind_bone.size():
		out.append(xf * r.sk.get_bone_global_pose(r.bind_bone[i]) * r.bind_pose[i])
	return out


func _skin(p: Vector3, bs: PackedInt32Array, ws: PackedFloat32Array, v: int, mats: Array[Transform3D]) -> Vector3:
	var acc := Vector3.ZERO
	var tw := 0.0
	for k in 4:
		var w := ws[v * 4 + k]
		if w <= 0.0:
			continue
		acc += (mats[bs[v * 4 + k]] * p) * w
		tw += w
	return acc / tw if tw > 0.0 else p


func _lowest_vertex(r: Rig) -> float:
	var mats := _bind_mats(r)
	var mn := INF
	for v in r.vpos.size():
		mn = minf(mn, _skin(r.vpos[v], r.vbind, r.vw, v, mats).y)
	return mn


# ---------------------------------------------------------------------------------------
# Sampling and metrics
# ---------------------------------------------------------------------------------------

func _analyse(s: Dictionary, node: Node3D) -> void:
	var r := _make_rig(s, node)
	if r == null or r.ap == null:
		printerr("no rig/anim for ", s["id"])
		return
	var fvc := []
	for fv: PackedInt32Array in r.foot_verts:
		fvc.append(fv.size())
	var fnames := []
	for f: PackedInt32Array in r.feet:
		fnames.append(r.sk.get_bone_name(f[0]))
	# facing (+1 = +Z): bipeds from toes vs. ankle, quadrupeds from where the head is
	var fz := 0.0
	if bool(s["biped"]) or String(s["kind"]) == "ual":
		for fi in r.foot_verts.size():
			var fv: PackedInt32Array = r.foot_verts[fi]
			var c := 0.0
			for v in fv:
				c += r.vrest_p[v].z
			if fv.size() > 0:
				var jb: int = (r.feet[fi] as PackedInt32Array)[0]
				fz += c / fv.size() - (r.sk.global_transform * r.sk.get_bone_global_rest(jb).origin).z
	else:
		var top := 0.0
		var nt := 0
		var all := 0.0
		for v in r.vpos.size():
			all += r.vrest_p[v].z
			if r.vrest_y[v] > r.height * 0.75:
				top += r.vrest_p[v].z
				nt += 1
		if nt > 0:
			fz = top / nt - all / maxi(r.vpos.size(), 1)
	r.face = 1.0 if fz >= 0.0 else -1.0
	if float(s.get("face", 0.0)) != 0.0:
		r.face = float(s["face"])    # known convention from the game code
	subject_info[s["id"]] = {"face": r.face, "height": r.height, "group": s["group"], "feet": r.feet.size(),
		"hips": r.sk.get_bone_name(r.hips), "rest_min_y": r.rest_min_y, "length": r.length, "center_z": r.center_z}
	var clips: Dictionary = s["clips"]
	for clip: String in clips:
		if not r.ap.has_animation(clip):
			results.append({"subject": s["id"], "group": s["group"], "clip": clip, "kind": clips[clip]["kind"],
				"game": clips[clip]["game"], "status": "FAIL", "notes": ["clip missing"], "missing": true})
			continue
		var row := _measure(s, r, clip, clips[clip])
		results.append(row)


func _measure(s: Dictionary, r: Rig, clip: String, info: Dictionary) -> Dictionary:
	var kind: String = info["kind"]
	var sample_fps := CRITTER_GAIT_FPS if String(s.get("group", "")) == "animals" and kind in ["loco", "loop"] else FPS
	var sk := r.sk
	var ap := r.ap
	var anim := ap.get_animation(clip)
	var L := anim.length
	var loop_mode := anim.loop_mode
	anim.loop_mode = Animation.LOOP_NONE
	sk.reset_bone_poses()
	ap.play(clip, 0.0)
	var n := maxi(2, int(round(L * sample_fps)))
	var xf := sk.global_transform
	var nb := sk.get_bone_count()
	var sole: Array = []          # per frame: PackedFloat32Array per foot (cm)
	var footxz: Array = []        # per frame: per foot Vector2(lowest bone index, 0)
	var gps: Array = []           # per frame: world bone positions
	var footpts: Array = []       # per frame: per foot skinned sole vertices
	var hips: PackedVector3Array = []
	var rots: Array = []          # per frame: Array[Quaternion] for major bones
	var max_stretch := 0.0
	var stretch_bone := ""
	var max_scale := 0.0
	var scale_bone := ""
	var low_v := PackedFloat32Array()   # lowest vertex per sampled frame (cm)
	var tpose_frames := 0
	var min_foot_joint := INF
	for i in n + 1:
		var t := minf(i / sample_fps, L)
		ap.seek(t, true)
		var gp := PackedVector3Array()
		gp.resize(nb)
		for b in nb:
			gp[b] = xf * sk.get_bone_global_pose(b).origin
		# feet
		var so := PackedFloat32Array()
		var fx := PackedVector2Array()
		var fp: Array = []
		var mats := _bind_mats(r)
		for fi in r.feet.size():
			var fv: PackedInt32Array = r.foot_verts[fi]
			if fv.size() > 0:
				# contact point = the lowest skinned vertex of this foot
				var pts := PackedVector3Array()
				pts.resize(fv.size())
				var hv := INF
				var bv := 0
				for k in fv.size():
					var p := _skin(r.vpos[fv[k]], r.vbind, r.vw, fv[k], mats)
					pts[k] = p
					if p.y < hv:
						hv = p.y
						bv = k
				so.append((hv - r.rest_min_y) * 100.0)
				fx.append(Vector2(bv, 1))
				fp.append(pts)
				continue
			var f: PackedInt32Array = r.feet[fi]
			var rh: PackedFloat32Array = r.foot_rest[fi]
			var h := INF
			var best := 0
			for k in f.size():
				var y := gp[f[k]].y - r.rest_min_y - rh[k]
				if y < h:
					h = y
					best = k
			so.append(h * 100.0)
			fx.append(Vector2(f[best], 0))
			fp.append(PackedVector3Array())
		sole.append(so)
		footxz.append(fx)
		footpts.append(fp)
		gps.append(gp)
		hips.append(gp[r.hips])
		# rotations, stretch, scale, T-pose
		var q: Array[Quaternion] = []
		var dev := 0.0
		for b in r.major:
			var qq := sk.get_bone_pose_rotation(b)
			q.append(qq)
			dev += rad_to_deg(qq.angle_to(r.rest_rot[b]))
		rots.append(q)
		if r.major.size() > 0 and dev / r.major.size() < TPOSE_DEG:
			tpose_frames += 1
		for b in nb:
			var p := sk.get_bone_parent(b)
			if p >= 0 and r.rest_len[b] > 0.01 * r.height and r.stretch_ok[b]:
				var st := absf(gp[b].distance_to(gp[p]) / r.rest_len[b] - 1.0) * 100.0
				if st > max_stretch:
					max_stretch = st
					stretch_bone = sk.get_bone_name(b)
			var sc := sk.get_bone_pose_scale(b)
			var sd := maxf(absf(sc.x - 1.0), maxf(absf(sc.y - 1.0), absf(sc.z - 1.0))) * 100.0
			if sd > max_scale:
				max_scale = sd
				scale_bone = sk.get_bone_name(b)
		if i % 3 == 0 or i == n:
			low_v.append((_lowest_vertex(r) - r.rest_min_y) * 100.0)
	anim.loop_mode = loop_mode
	sk.reset_bone_poses()

	var row := {"subject": s["id"], "group": s["group"], "clip": clip, "kind": kind, "game": info["game"],
		"length": L, "frames": n + 1, "looping": loop_mode != Animation.LOOP_NONE}
	var notes: Array[String] = []
	var st := {}    # metric -> PASS/WARN/FAIL

	# ---- ground contact: penetration / hover / airborne ----
	var nf := r.feet.size()
	var lowest_v := INF
	for v in low_v:
		lowest_v = minf(lowest_v, v)
	row["lowest_vertex_cm"] = lowest_v
	var min_sole := INF
	var per_foot_min := PackedFloat32Array()
	var per_foot_thr := PackedFloat32Array()
	for fi in nf:
		var m := INF
		for fr: PackedFloat32Array in sole:
			m = minf(m, fr[fi])
		per_foot_min.append(m)
		var mx := -INF
		for fr: PackedFloat32Array in sole:
			mx = maxf(mx, fr[fi])
		# contact band: 30 % of this foot's lift range, 0.5-2.5 cm (small animals barely lift their paws)
		per_foot_thr.append(clampf(0.3 * (mx - m), 0.5, 2.5))
		min_sole = minf(min_sole, m)
	row["min_foot_cm"] = min_sole if nf > 0 else 0.0
	var pen := maxf(-lowest_v, -min_sole if nf > 0 else 0.0)
	row["penetration_cm"] = maxf(pen, 0.0)
	st["penetration"] = _grade(pen, PEN_WARN, PEN_FAIL)
	if pen >= PEN_WARN:
		notes.append("%.1f cm below floor (%s)" % [pen, "mesh" if -lowest_v >= -min_sole else "foot joint"])
	# hover: the lowest foot never reaches the floor (exempt: death, sit, jump)
	var hover := 0.0
	if nf > 0 and not kind in ["death", "sit", "jump"]:
		# per frame lowest foot, then the minimum over the clip
		hover = min_sole
		st["hover"] = _grade(hover, HOVER_WARN, HOVER_FAIL)
		if hover >= HOVER_WARN:
			notes.append("feet never touch the floor (lowest %.1f cm above)" % hover)
	row["hover_cm"] = maxf(hover, 0.0)
	var air_s := 0.0
	if nf > 0 and not kind in ["death", "sit", "jump"]:
		var streak := 0
		var best := 0
		for fr: PackedFloat32Array in sole:
			var all_up := true
			for fi in nf:
				if fr[fi] - maxf(per_foot_min[fi], 0.0) < AIR_H:
					all_up = false
			streak = streak + 1 if all_up else 0
			best = maxi(best, streak)
		air_s = best / sample_fps
		st["airborne"] = _grade(air_s, AIR_WARN, AIR_FAIL)
		if air_s >= AIR_WARN:
			notes.append("all feet off the ground for %.2f s" % air_s)
	row["airborne_s"] = air_s
	if kind == "death" and low_v.size() > 0:
		var end_low := low_v[low_v.size() - 1]
		row["death_end_low_cm"] = end_low
		if end_low > 10.0:
			st["death_rest"] = "FAIL"
			notes.append("death ends %.0f cm above the floor" % end_low)
		elif end_low > 5.0:
			st["death_rest"] = "WARN"
			notes.append("death ends %.0f cm above the floor" % end_low)

	# ---- foot sliding and natural ground speed ----
	var slide := -1.0
	var ground_speed := 0.0
	var dt := 1.0 / sample_fps
	if nf > 0 and kind != "death":
		var vels: Array[Vector2] = []
		var hip_v := Vector2.ZERO
		if hips.size() > 1:
			var d := hips[hips.size() - 1] - hips[0]
			hip_v = Vector2(d.x, d.z) / maxf(L, dt)
		if dump != "" and clip == dump:
			for i in range(1, sole.size() - 1):
				var line := "%5.2f" % (i / sample_fps)
				for fi in nf:
					var sel: Vector2 = footxz[i][fi]
					var p: Vector3 = (footpts[i][fi] as PackedVector3Array)[int(sel.x)] if sel.y > 0.5 else (gps[i] as PackedVector3Array)[int(sel.x)]
					line += " | h=%5.1f x=%6.3f z=%6.3f v%d" % [sole[i][fi], p.x, p.z, int(sel.x)]
				line += " | hips y=%.3f z=%.3f" % [hips[i].y, hips[i].z]
				print(line)
		for i in range(1, sole.size() - 1):
			for fi in nf:
				var h: float = sole[i][fi]
				if h - maxf(per_foot_min[fi], 0.0) < per_foot_thr[fi] and h < 6.0:
					# velocity of the joint that is lowest (in contact) at this frame
					var sel: Vector2 = footxz[i][fi]
					var b := int(sel.x)
					var d3: Vector3
					if sel.y > 0.5:     # sole vertex
						d3 = ((footpts[i + 1][fi] as PackedVector3Array)[b] - (footpts[i - 1][fi] as PackedVector3Array)[b]) / (2.0 * dt)
					else:               # joint fallback
						d3 = ((gps[i + 1] as PackedVector3Array)[b] - (gps[i - 1] as PackedVector3Array)[b]) / (2.0 * dt)
					if absf(d3.y) > maxf(0.1, 0.15 * r.height):
						continue    # lifting off / landing, not planted
					vels.append(Vector2(d3.x, d3.z) - hip_v)
		if vels.size() >= 3:
			var ref := Vector2.ZERO
			if kind == "loco":
				var xs := PackedFloat32Array()
				var zs := PackedFloat32Array()
				for v in vels:
					xs.append(v.x)
					zs.append(v.y)
				ref = Vector2(_median(xs), _median(zs))
				ground_speed = ref.length()
				if String(s["kind"]) == "ual":
					# UAL rig: take the speed from the ball joints, independent of skin
					# weights (some re-rigged meshes weight the boots to the thigh).
					var jv := _joint_ground_speed(r, gps, hip_v, dt)
					if jv > 0.0:
						ground_speed = jv
						ref = ref.normalized() * jv if ref.length() > 0.001 else Vector2(0, -jv)
				if dump == clip:
					print("  vels=%d ref=%s sample=%s" % [vels.size(), ref, vels.slice(0, 12)])
				# heading check: planted feet must travel backwards relative to the facing
				var face: float = r.face
				if ref.y * face > 0.05 and ground_speed > 0.2:
					notes.append("planted feet move FORWARD (moonwalk / reversed clip)")
					st["direction"] = "FAIL"
			var errs := PackedFloat32Array()
			for v in vels:
				errs.append((v - ref).length() * 100.0)
			slide = _pct(errs, 0.75)
			st["slide"] = _grade(slide, SLIDE_WARN, SLIDE_FAIL)
			if slide >= SLIDE_WARN:
				notes.append("planted foot slips %.0f cm/s (p75)" % slide)
		elif kind in ["loco", "loop"]:
			notes.append("no ground-contact frames found")
		if kind == "loco" and ground_speed == 0.0 and String(s["kind"]) == "ual":
			ground_speed = _joint_ground_speed(r, gps, hip_v, dt)
	row["slide_cm_s"] = slide
	row["ground_speed"] = ground_speed
	if kind == "loco":
		natural[String(s["id"]) + "|" + clip] = ground_speed

	# ---- bone stretch / scale keys ----
	row["stretch_pct"] = max_stretch
	st["stretch"] = _grade(max_stretch, STRETCH_WARN, STRETCH_FAIL)
	if max_stretch >= STRETCH_WARN:
		notes.append("bone '%s' stretches %.1f %%" % [stretch_bone, max_stretch])
	row["scale_pct"] = max_scale
	st["scale"] = _grade(max_scale, SCALE_WARN, SCALE_FAIL)
	if max_scale >= SCALE_WARN:
		notes.append("scale key on '%s' (%.1f %%)" % [scale_bone, max_scale])

	# ---- pops / jitter (angular acceleration spikes) ----
	var pops := 0
	var max_acc := 0.0
	var pop_bone := ""
	var pop_t := 0.0
	var worst_pop := 0.0
	var nm := r.major.size()
	if rots.size() >= 4:
		for j in nm:
			var accs := PackedFloat32Array()
			var prev := Vector3.ZERO
			for i in range(1, rots.size()):
				var dq: Quaternion = (rots[i - 1][j] as Quaternion).inverse() * (rots[i][j] as Quaternion)
				var rv := _rotvec(dq)
				if i >= 2:
					# Normalize to the original 30 Hz threshold scale.
					accs.append(rad_to_deg((rv - prev).length()) * pow(sample_fps / FPS, 2.0))
				prev = rv
			var p90 := _pct(accs, 0.9)
			for k in accs.size():
				var a := accs[k]
				if a > max_acc:
					max_acc = a
				if a > POP_ABS and a > POP_REL * maxf(p90, 0.5):
					pops += 1
					if a >= worst_pop:
						worst_pop = a
						pop_bone = sk.get_bone_name(r.major[j])
						pop_t = (k + 1) / sample_fps
	row["max_ang_acc"] = max_acc
	row["pops"] = pops
	if pops > 0:
		st["pops"] = "FAIL" if pops > 3 else "WARN"
		notes.append("%d pop(s), worst on '%s' at %.2f s (%.0f deg/frame^2)" % [pops, pop_bone, pop_t, worst_pop])
	else:
		st["pops"] = "PASS"

	# ---- loop seam / root drift ----
	var game_loops := kind in ["loop", "loco"] or (kind == "sit" and clip.contains("Idle")) or clip.contains("Talking")
	row["seam_deg"] = 0.0
	row["seam_cm"] = 0.0
	row["drift_cm"] = 0.0
	if game_loops:
		if loop_mode == Animation.LOOP_NONE:
			st["loop_flag"] = "FAIL"
			notes.append("clip is not set to loop (freezes on its last frame)")
		var gap := 0.0
		var gap_bone := ""
		var last: Array = rots[rots.size() - 1]
		var first: Array = rots[0]
		var pre: Array = rots[rots.size() - 2]
		var post: Array = rots[1]
		for j in nm:
			# jump at the wrap, minus one ordinary frame step (a clip without a duplicated
			# end frame steps last -> first like any other frame; that is not a pop)
			var raw := rad_to_deg((last[j] as Quaternion).angle_to(first[j] as Quaternion))
			var step := maxf(rad_to_deg((pre[j] as Quaternion).angle_to(last[j] as Quaternion)),
				rad_to_deg((first[j] as Quaternion).angle_to(post[j] as Quaternion)))
			var g := maxf(0.0, raw - step)
			if g > gap:
				gap = g
				gap_bone = sk.get_bone_name(r.major[j])
		var hp := hips[hips.size() - 1] - hips[0]
		var hstep := maxf(absf(hips[hips.size() - 1].y - hips[hips.size() - 2].y), absf(hips[1].y - hips[0].y))
		var seam_cm := maxf(0.0, absf(hp.y) - hstep) * 100.0
		var drift := Vector2(hp.x, hp.z).length() * 100.0
		row["seam_deg"] = gap
		row["seam_cm"] = seam_cm
		row["drift_cm"] = drift
		st["seam"] = _worst(_grade(gap, SEAM_WARN, SEAM_FAIL), _grade(seam_cm, SEAM_POS_WARN, SEAM_POS_FAIL))
		if gap >= SEAM_WARN:
			notes.append("loop seam jumps %.1f deg ('%s')" % [gap, gap_bone])
		if seam_cm >= SEAM_POS_WARN:
			notes.append("loop seam hips height jump %.1f cm" % seam_cm)
		st["drift"] = _grade(drift, DRIFT_WARN, DRIFT_FAIL)
		if drift >= DRIFT_WARN:
			notes.append("hips drift %.0f cm per loop (snaps back at the seam)" % drift)
	else:
		var hp2 := hips[hips.size() - 1] - hips[0]
		var mv := Vector2(hp2.x, hp2.z).length() * 100.0
		row["drift_cm"] = mv
		if mv >= ONESHOT_MOVE_WARN and kind != "death":
			st["drift"] = "WARN"
			notes.append("one-shot moves the body %.0f cm (baked root motion; snaps back after)" % mv)

	# ---- T-pose / static ----
	row["tpose_frames"] = tpose_frames
	if bool(s["biped"]) and not clip.contains("TPose"):
		if tpose_frames >= 2:
			st["tpose"] = "FAIL"
			notes.append("%d T-pose frame(s)" % tpose_frames)
		elif tpose_frames == 1:
			st["tpose"] = "WARN"
			notes.append("1 T-pose frame")
	if kind in ["loop"] and nm > 0:
		var rng := 0.0
		for j in nm:
			for fr: Array in rots:
				rng = maxf(rng, rad_to_deg((fr[j] as Quaternion).angle_to(rots[0][j] as Quaternion)))
		row["motion_deg"] = rng
		if rng < STATIC_DEG:
			st["static"] = "WARN"
			notes.append("idle barely moves (%.2f deg): looks frozen" % rng)

	if info.get("upper", false):
		# CharacterAnimator plays this clip on the upper-body layer only (play_upper), so
		# the legs come from locomotion in game: leg/ground checks are informational.
		var kept: Array[String] = []
		for nt in notes:
			if not (nt.contains("floor") or nt.contains("slips") or nt.contains("feet") or nt.contains("drift") or nt.contains("moves the body")):
				kept.append(nt)
		if kept.size() != notes.size():
			kept.append("(legs ignored: upper-body layer in game)")
		notes = kept
		for k in ["slide", "hover", "airborne", "penetration", "direction", "drift"]:
			st.erase(k)
	var status := "PASS"
	for k in st:
		status = _worst(status, st[k])
	row["status"] = status
	row["checks"] = st
	row["notes"] = notes
	return row


func _joint_ground_speed(r: Rig, gps: Array, hip_v: Vector2, dt: float) -> float:
	var zs := PackedFloat32Array()
	for fi in r.feet.size():
		var f: PackedInt32Array = r.feet[fi]
		var b := f[f.size() - 1]
		var mn := INF
		for fr: PackedVector3Array in gps:
			mn = minf(mn, fr[b].y)
		for i in range(1, gps.size() - 1):
			if (gps[i] as PackedVector3Array)[b].y - mn < 0.015:
				var d: Vector3 = ((gps[i + 1] as PackedVector3Array)[b] - (gps[i - 1] as PackedVector3Array)[b]) / (2.0 * dt)
				if absf(d.y) < maxf(0.1, 0.15 * r.height):
					zs.append((Vector2(d.x, d.z) - hip_v).length())
	return _median(zs) if zs.size() >= 3 else 0.0


func _rotvec(q: Quaternion) -> Vector3:
	var qq := q.normalized()
	if qq.w < 0.0:
		qq = -qq
	var ang := 2.0 * acos(clampf(qq.w, -1.0, 1.0))
	var s := sqrt(maxf(1.0 - qq.w * qq.w, 0.0))
	if s < 1e-6:
		return Vector3.ZERO
	return Vector3(qq.x, qq.y, qq.z) / s * ang


func _grade(v: float, warn: float, fail: float) -> String:
	if v >= fail:
		return "FAIL"
	if v >= warn:
		return "WARN"
	return "PASS"


func _worst(a: String, b: String) -> String:
	var order := {"PASS": 0, "WARN": 1, "FAIL": 2}
	return a if order[a] >= order[b] else b


func _median(a: PackedFloat32Array) -> float:
	return _pct(a, 0.5)


func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(round(p * (b.size() - 1))), 0, b.size() - 1)]


# ---------------------------------------------------------------------------------------
# Speed sanity (moonwalk / ice-skating)
# ---------------------------------------------------------------------------------------

func _speed_table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in Catalog.speed_cases():
		var sid: String = c["subject"]
		if not subject_info.has(sid):
			continue
		var speed: float = c["speed"]
		var v_eff := 0.0
		var desc := ""
		if c.has("blend"):
			# BlendSpace1D weights between the two neighbouring points; feet blend linearly.
			var pts: Array = c["blend"]
			var lo: Array = pts[0]
			var hi: Array = pts[pts.size() - 1]
			for i in range(pts.size() - 1):
				if speed >= float(pts[i][1]) and speed <= float(pts[i + 1][1]):
					lo = pts[i]
					hi = pts[i + 1]
			var w := 0.0 if float(hi[1]) == float(lo[1]) else (speed - float(lo[1])) / (float(hi[1]) - float(lo[1]))
			w = clampf(w, 0.0, 1.0)
			var v_lo: float = natural.get(sid + "|" + String(lo[0]), 0.0)
			var v_hi: float = natural.get(sid + "|" + String(hi[0]), 0.0)
			v_eff = v_lo * (1.0 - w) + v_hi * w
			desc = "%s %.0f%% + %s %.0f%%" % [lo[0], (1.0 - w) * 100.0, hi[0], w * 100.0]
		else:
			v_eff = natural.get(sid + "|" + String(c["clip"]), 0.0)
			desc = String(c["clip"])
		var playback_rate := float(c.get("rate", 1.0))
		var driven_clip_speed := v_eff * playback_rate
		if not is_equal_approx(playback_rate, 1.0):
			desc += " x%.2f" % playback_rate
		var ratio := speed / driven_clip_speed if driven_clip_speed > 0.01 else INF
		var status := "PASS"
		if ratio < SPEED_WARN[0] or ratio > SPEED_WARN[1]:
			status = "FAIL"
		elif ratio < SPEED_OK[0] or ratio > SPEED_OK[1]:
			status = "WARN"
		var effect := "ok"
		if ratio > SPEED_OK[1]:
			effect = "ice-skating (body outruns the feet)"
		elif ratio < SPEED_OK[0]:
			effect = "moonwalk / treadmill (feet outrun the body)"
		out.append({"agent": c["agent"], "subject": sid, "speed": speed, "anim": desc, "clip_speed": v_eff,
			"clip": String(c.get("clip", "")), "rate": playback_rate,
			"ratio": ratio, "status": status, "effect": effect, "src": c["src"],
			"slip_cm_s": absf(speed - driven_clip_speed) * 100.0,
			"fix_scale": speed / driven_clip_speed if driven_clip_speed > 0.01 else 0.0})
	return out


# ---------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------

func _write_csv() -> void:
	var f := FileAccess.open(out_dir.path_join("anim_qa_results%s.csv" % _suffix()), FileAccess.WRITE)
	f.store_line("group,subject,clip,kind,game_uses,status,length_s,looping,slide_cm_s,ground_speed_m_s,penetration_cm,hover_cm,airborne_s,stretch_pct,scale_pct,pops,max_ang_acc_deg_f2,seam_deg,seam_cm,drift_cm,tpose_frames,notes")
	for r in results:
		if r.get("missing", false):
			f.store_line("%s,%s,%s,%s,%s,FAIL,,,,,,,,,,,,,,,,clip missing" % [r["group"], r["subject"], r["clip"], r["kind"], r["game"]])
			continue
		f.store_line("%s,%s,%s,%s,%s,%s,%.2f,%s,%.1f,%.2f,%.1f,%.1f,%.2f,%.2f,%.2f,%d,%.1f,%.1f,%.1f,%.1f,%d,\"%s\"" % [
			r["group"], r["subject"], r["clip"], r["kind"], r["game"], r["status"], r["length"], r["looping"],
			r["slide_cm_s"], r["ground_speed"], r["penetration_cm"], r["hover_cm"], r["airborne_s"], r["stretch_pct"],
			r["scale_pct"], r["pops"], r["max_ang_acc"], r["seam_deg"], r["seam_cm"], r["drift_cm"], r["tpose_frames"],
			"; ".join(r["notes"])])
	f.close()


func _severity(r: Dictionary) -> float:
	# ranking score for "worst problems": how far past the FAIL line the worst metric is
	if r.get("missing", false):
		return 5.0
	var s := 0.0
	s = maxf(s, float(r["slide_cm_s"]) / SLIDE_FAIL)
	s = maxf(s, float(r["penetration_cm"]) / PEN_FAIL)
	s = maxf(s, float(r["hover_cm"]) / HOVER_FAIL)
	s = maxf(s, float(r["airborne_s"]) / AIR_FAIL)
	s = maxf(s, float(r["stretch_pct"]) / STRETCH_FAIL)
	s = maxf(s, float(r["scale_pct"]) / SCALE_FAIL)
	s = maxf(s, float(r["pops"]) / 4.0)
	s = maxf(s, float(r["seam_deg"]) / SEAM_FAIL if r["looping"] or r["kind"] in ["loop", "loco"] else 0.0)
	var chk: Dictionary = r["checks"]
	if chk.get("loop_flag", "") == "FAIL" or chk.get("direction", "") == "FAIL" or chk.get("tpose", "") == "FAIL":
		s = maxf(s, 2.0)
	return s


func _write_report(speeds: Array[Dictionary]) -> void:
	var path := out_dir.path_join("anim_qa_report%s.md" % _suffix())
	var manual := ""
	if FileAccess.file_exists(path):
		var old := FileAccess.get_file_as_string(path)
		var a := old.find("<!-- MANUAL START -->")
		var b := old.find("<!-- MANUAL END -->")
		if a >= 0 and b > a:
			manual = old.substr(a, b - a + "<!-- MANUAL END -->".length())
	if manual == "":
		manual = "<!-- MANUAL START -->\n## Visual review and judgement\n\n(to be written after looking at the strips)\n\n## For the cloud session\n\n(recommendations)\n<!-- MANUAL END -->"
	var counts := {"PASS": 0, "WARN": 0, "FAIL": 0}
	var game_counts := {"PASS": 0, "WARN": 0, "FAIL": 0}
	for r in results:
		counts[r["status"]] += 1
		if r["game"]:
			game_counts[r["status"]] += 1
	var sp_counts := {"PASS": 0, "WARN": 0, "FAIL": 0}
	for c in speeds:
		sp_counts[c["status"]] += 1
	var L: PackedStringArray = []
	L.append("# Animation QA report")
	L.append("")
	L.append("Generated by `tools/qa/anim_qa/run.sh` on %s (Godot %s). Every character, creature and animal type is loaded through the game's own loader (`Assets.mh_character`, or a copy of the `CampMonster` / `Wolf` / `Critter` setup code). Clips are sampled at the in-game size; animal locomotion and loop clips use 120 fps to catch short paw contacts, and other clips use 30 fps. The numbers below are measured on the posed skeleton and skinned mesh." % [Time.get_datetime_string_from_system(false, true), Engine.get_version_info()["string"]])
	L.append("")
	L.append("**Clip checks: %d rows: %d PASS, %d WARN, %d FAIL** (clips the game plays today: %d PASS, %d WARN, %d FAIL)." % [results.size(), counts["PASS"], counts["WARN"], counts["FAIL"], game_counts["PASS"], game_counts["WARN"], game_counts["FAIL"]])
	L.append("")
	L.append("**Speed checks: %d cases: %d PASS, %d WARN, %d FAIL.**" % [speeds.size(), sp_counts["PASS"], sp_counts["WARN"], sp_counts["FAIL"]])
	L.append("")
	L.append(manual)
	L.append("")
	# ranked worst problems
	L.append("## Ranked problems (auto)")
	L.append("")
	L.append("Speed mismatches first (they affect every frame of locomotion), then clip rows by how far their worst metric is past its FAIL line. Rows that share one clip file across many characters are merged.")
	L.append("")
	var bad_speed := speeds.filter(func(c: Dictionary) -> bool: return c["status"] != "PASS")
	bad_speed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(log(a["ratio"])) > absf(log(b["ratio"])))
	var rank := 1
	for c in bad_speed:
		L.append("%d. **%s** %s: moves at %.2f m/s but `%s` covers %.2f m/s (x%.2f) -> %s. Source: `%s`." % [rank, c["status"], c["agent"], c["speed"], c["anim"], c["clip_speed"], c["ratio"], c["effect"], c["src"]])
		rank += 1
	var merged := {}
	for r in results:
		if r["status"] == "PASS":
			continue
		var key := String(r["clip"]) + "|" + ("; ".join(r["notes"]).left(40))
		if String(r["group"]) != "villagers" and String(r["group"]) != "armored":
			key = String(r["subject"]) + "|" + key
		if not merged.has(key) or _severity(r) > _severity(merged[key]["row"]):
			var cnt: int = merged[key]["n"] if merged.has(key) else 0
			merged[key] = {"row": r, "n": cnt}
		merged[key]["n"] += 1
	var ms := merged.values()
	ms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _severity(a["row"]) > _severity(b["row"]))
	for m in ms.slice(0, 40):
		var r: Dictionary = m["row"]
		var who := String(r["subject"]) + (" (+%d more characters)" % (int(m["n"]) - 1) if int(m["n"]) > 1 else "")
		L.append("%d. **%s** `%s` on %s%s: %s" % [rank, r["status"], r["clip"], who, "" if r["game"] else " *(not used by the game yet)*", "; ".join(r["notes"])])
		rank += 1
	L.append("")
	# speed table
	L.append("## Playback speed vs. movement speed")
	L.append("")
	L.append("Clip ground speed = the speed at which the planted foot travels backwards in the in-place clip (median over contact frames, at the in-game model size). Ratio = game speed / clip speed. Above %.2f the body outruns the feet (ice-skating); below %.2f the feet outrun the body (moonwalking / treadmill)." % [SPEED_OK[1], SPEED_OK[0]])
	L.append("")
	L.append("| status | agent | game speed m/s | animation | clip speed m/s | ratio | foot slip cm/s | effect | source |")
	L.append("|---|---|---:|---|---:|---:|---:|---|---|")
	for c in speeds:
		L.append("| %s | %s | %.2f | %s | %.2f | %.2f | %.0f | %s | `%s` |" % [c["status"], c["agent"], c["speed"], c["anim"], c["clip_speed"], c["ratio"], c["slip_cm_s"], c["effect"], c["src"]])
	L.append("")
	L.append("Natural ground speed of every locomotion clip (use these as blend-space points / speed_scale references):")
	L.append("")
	L.append("| subject | clip | ground speed m/s | cadence (length s) |")
	L.append("|---|---|---:|---:|")
	for r in results:
		if r["kind"] == "loco" and not r.get("missing", false):
			L.append("| %s | %s | %.2f | %.2f |" % [r["subject"], r["clip"], r["ground_speed"], r["length"]])
	L.append("")
	_thresholds(L)
	# per character tables
	L.append("## Per character x clip")
	L.append("")
	L.append("Columns: slide = p90 planted-foot slip (cm/s); pen = deepest point below the floor (cm); hover = lowest foot above the floor (cm); air = longest both-feet-off time (s); str = max bone-length change (%); scl = max bone scale away from 1 (%); pops = angular-acceleration spikes; seam = pose gap at the loop seam (deg); drift = hips travel over the clip (cm). `*` = clip not used by the game yet.")
	L.append("")
	var by_subject := {}
	for r in results:
		if not by_subject.has(r["subject"]):
			by_subject[r["subject"]] = []
		by_subject[r["subject"]].append(r)
	for sid: String in by_subject:
		var rows: Array = by_subject[sid]
		var sc := {"PASS": 0, "WARN": 0, "FAIL": 0}
		for r: Dictionary in rows:
			sc[r["status"]] += 1
		var inf: Dictionary = subject_info.get(sid, {})
		L.append("### %s (%s, %.2f m, %d PASS / %d WARN / %d FAIL)" % [sid, inf.get("group", ""), float(inf.get("height", 0.0)), sc["PASS"], sc["WARN"], sc["FAIL"]])
		L.append("")
		L.append("| clip | status | slide | pen | hover | air | str | scl | pops | seam | drift | notes |")
		L.append("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")
		for r: Dictionary in rows:
			if r.get("missing", false):
				L.append("| %s%s | FAIL | | | | | | | | | | clip missing |" % [r["clip"], "" if r["game"] else "*"])
				continue
			L.append("| %s%s | %s | %s | %.1f | %.1f | %.2f | %.1f | %.1f | %d | %.1f | %.0f | %s |" % [r["clip"], "" if r["game"] else "*", r["status"],
				("%.0f" % r["slide_cm_s"]) if float(r["slide_cm_s"]) >= 0.0 else "-", r["penetration_cm"], r["hover_cm"], r["airborne_s"],
				r["stretch_pct"], r["scale_pct"], r["pops"], r["seam_deg"], r["drift_cm"], "; ".join(r["notes"])])
		L.append("")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()


func _thresholds(L: PackedStringArray) -> void:
	L.append("## Thresholds and why")
	L.append("")
	L.append("| check | PASS | WARN | FAIL | why |")
	L.append("|---|---|---|---|---|")
	L.append("| foot slide (p90 slip of a planted foot, cm/s) | < %.0f | < %.0f | >= %.0f | A foot is 'planted' when it is within 2.5 cm of its lowest height in the clip. For in-place locomotion the slip is measured against the clip's own treadmill speed, so this is sliding baked into the clip; speed mismatches with the game are a separate table. ~8 cm/s is about where slip becomes visible at third-person distance; 20 cm/s reads as skating. |" % [SLIDE_WARN, SLIDE_FAIL, SLIDE_FAIL])
	L.append("| ground penetration (cm) | < %.0f | < %.0f | >= %.0f | Lowest skinned vertex (feet-region vertices plus a 900-vertex sample of the body) or foot joint below y = 0. 2 cm hides in grass/terrain; 5 cm visibly sinks a boot or clips a body through the floor. |" % [PEN_WARN, PEN_FAIL, PEN_FAIL])
	L.append("| hover (cm) | < %.0f | < %.0f | >= %.0f | The lowest foot never gets closer than this to the floor during a standing / moving clip: the character floats. |" % [HOVER_WARN, HOVER_FAIL, HOVER_FAIL])
	L.append("| airborne (s) | < %.2f | < %.2f | >= %.2f | Both feet > %.0f cm above their contact height in a row, in non-jump clips. A real run has ~0.1 s flight per stride; > 0.2 s looks floaty. |" % [AIR_WARN, AIR_FAIL, AIR_FAIL, AIR_H])
	L.append("| bone stretch (%%) | < %.0f | < %.0f | >= %.0f | Joint-to-joint distance vs. rest. Skeletal animation should be rigid; >1%% means position keys fight the character's proportions (retarget leftovers). |" % [STRETCH_WARN, STRETCH_FAIL, STRETCH_FAIL])
	L.append("| scale keys (%%) | < %.0f | < %.0f | >= %.0f | Any bone scaled away from 1 (e.g. Meshy's hips x1.18) inflates the mesh. |" % [SCALE_WARN, SCALE_FAIL, SCALE_FAIL])
	L.append("| pops | 0 | 1-3 | > 3 | Frame where a major bone's angular acceleration exceeds %.0f deg/frame^2 at 30 fps and is %.0fx that bone's p90 in the clip: a one-frame snap, not a fast but smooth swing. Fingers, leaf and IK helper bones are ignored. |" % [POP_ABS, POP_REL])
	L.append("| loop seam | < %.0f deg and < %.0f cm | < %.0f deg / < %.0f cm | above | Pose jump when a looping clip wraps (last frame -> first frame), minus one ordinary frame step of that bone, max over major bones; plus the same for the hips height. What is left is a visible hitch every cycle. |" % [SEAM_WARN, SEAM_POS_WARN, SEAM_FAIL, SEAM_POS_FAIL])
	L.append("| root drift, in-place loops (cm) | < %.0f | < %.0f | >= %.0f | The hips travel this far over one loop and snap back at the seam (the game moves the node, not root motion). |" % [DRIFT_WARN, DRIFT_FAIL, DRIFT_FAIL])
	L.append("| one-shot displacement (cm) | < %.0f | >= %.0f | | A one-shot with baked travel moves the body away from its collider and snaps back when the next clip starts (death is exempt). |" % [ONESHOT_MOVE_WARN, ONESHOT_MOVE_WARN])
	L.append("| T-pose frames | 0 | 1 | >= 2 | Frames whose mean major-bone rotation is within %.0f deg of the bind (T) pose. |" % TPOSE_DEG)
	L.append("| loop flag | looping | | not looping | Idle / walk / run / sit-idle / talk clips must be set to loop or they freeze on the last frame. |")
	L.append("| static idle | > %.1f deg | <= %.1f deg | | An idle loop that barely moves reads as a mannequin. |" % [STATIC_DEG, STATIC_DEG])
	L.append("| speed ratio (game / clip) | %.2f-%.2f | %.2f-%.2f | outside | 15-20%% mismatch is hard to see; beyond 40%% the feet visibly skate or moonwalk. |" % [SPEED_OK[0], SPEED_OK[1], SPEED_WARN[0], SPEED_WARN[1]])
	L.append("")


# ---------------------------------------------------------------------------------------
# Strips (GPU)
# ---------------------------------------------------------------------------------------

const TILE_W := 160
const TILE_H := 214
const TILES := 8

var vp: SubViewport
var cam: Camera3D
var label: Label
var holder: Node3D
var grid: MeshInstance3D


func _setup_stage() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	vp = SubViewport.new()
	vp.size = Vector2i(TILE_W * 2, TILE_H * 2)      # rendered 2x, downsampled per tile
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	if OS.get_cmdline_user_args().has("--no-lod"):
		vp.mesh_lod_threshold = 0.0
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.80, 0.84, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 60, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	holder = Node3D.new()
	vp.add_child(holder)
	grid = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	grid.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
uniform float minor = 0.25;
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(w.xz / minor + 0.5) - 0.5) / fwidth(w.xz / minor);
	float l = 1.0 - min(min(g.x, g.y), 1.0);
	vec2 g2 = abs(fract(w.xz + 0.5) - 0.5) / fwidth(w.xz);
	float l2 = 1.0 - min(min(g2.x, g2.y), 1.0);
	vec3 c = vec3(0.55, 0.52, 0.45);
	c = mix(c, vec3(0.35, 0.33, 0.28), l * 0.8);
	c = mix(c, vec3(0.15, 0.12, 0.1), l2);
	ALBEDO = c;
}"""
	sm.shader = sh
	grid.material_override = sm
	vp.add_child(grid)
	# a thin floor line so the ground plane reads from a pure side view
	var line := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(400, 0.004, 0.004)
	line.mesh = bm
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.8, 0.1, 0.1)
	line.material_override = lm
	line.rotation_degrees.y = 90
	vp.add_child(line)
	var canvas := CanvasLayer.new()
	vp.add_child(canvas)
	label = Label.new()
	label.position = Vector2(6, 4)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.1))
	canvas.add_child(label)


func _render_all(subs: Array[Dictionary], speeds: Array[Dictionary]) -> void:
	if only == "":   # full run: drop strips of clips that are no longer tested
		var sd := out_dir.path_join("anim_strips")
		for f in DirAccess.get_files_at(sd):
			if f.ends_with(".jpg"):
				DirAccess.remove_absolute(sd.path_join(f))
	_setup_stage()
	# worst rows not already covered get a strip too
	var wanted := {}
	for s in subs:
		wanted[s["id"]] = (s["strips"] as Array).duplicate()
	var bad := results.filter(func(r: Dictionary) -> bool: return r["status"] == "FAIL" and not r.get("missing", false))
	bad.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _severity(a) > _severity(b))
	for r in bad.slice(0, 20):
		if wanted.has(r["subject"]) and not (wanted[r["subject"]] as Array).has(r["clip"]):
			(wanted[r["subject"]] as Array).append(r["clip"])
	var game_speed := {}
	var game_rate := {}
	for c in speeds:
		if not c.has("clip"):
			continue
		var k := String(c["subject"]) + "|" + String(c["clip"])
		if not game_speed.has(k):
			game_speed[k] = c["speed"]
			game_rate[k] = float(c.get("rate", 1.0))
	var groups := {}
	for s in subs:
		if only != "" and not String(s["id"]).contains(only):
			continue
		var node := _build(s)
		if node == null:
			continue
		holder.add_child(node)
		var ap := Assets.animation_player(node)
		var sk: Skeleton3D = node.find_children("*", "Skeleton3D", true, false)[0]
		var inf: Dictionary = subject_info.get(s["id"], {})
		var box := _skinned_box(node)
		if not inf.is_empty():
			# the skinned rest bounds measured by the metrics pass (mesh AABBs ignore the skeleton scale)
			var hh: float = inf["height"]
			var ll: float = inf["length"]
			box = AABB(Vector3(-ll * 0.5, float(inf["rest_min_y"]), float(inf["center_z"]) - ll * 0.5), Vector3(ll, hh, ll))
		sk.reset_bone_poses()
		await RenderingServer.frame_post_draw
		for clip: String in wanted[s["id"]]:
			if ap == null or not ap.has_animation(clip):
				continue
			var kind: String = (s["clips"] as Dictionary).get(clip, {"kind": "once"})["kind"]
			var spd := 0.0
			var rate := 1.0
			var spd_note := ""
			if kind == "loco":
				var speed_key := String(s["id"]) + "|" + clip
				spd = game_speed.get(speed_key, natural.get(speed_key, 0.0))
				rate = float(game_rate.get(speed_key, 1.0))
				spd_note = " @%.1f m/s x%.2f" % [spd, rate]
			var img := await _strip(s, node, ap, sk, clip, kind, spd, rate, box, spd_note)
			var fname := "%s__%s.jpg" % [s["id"], clip]
			img.save_jpg(out_dir.path_join("anim_strips/" + fname), 0.72)
			var g: String = s["group"]
			if not groups.has(g):
				groups[g] = []
			(groups[g] as Array).append([s["id"], clip, fname])
		node.queue_free()
		await process_frame
		print("strips %s" % s["id"])
	_sheets(groups)


func _skinned_box(node: Node3D) -> AABB:
	var b := Assets.visual_aabb(node)
	if b.size.y < 0.05:
		b = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1.8, 1))
	return b


func _strip(s: Dictionary, node: Node3D, ap: AnimationPlayer, sk: Skeleton3D, clip: String, kind: String,
		spd: float, rate: float, box: AABB, spd_note: String) -> Image:
	var anim := ap.get_animation(clip)
	var L := anim.length
	var loop_mode := anim.loop_mode
	anim.loop_mode = Animation.LOOP_NONE
	sk.reset_bone_poses()
	ap.play(clip, 0.0)
	var h := maxf(box.size.y, 0.3)
	var ext := maxf(h, maxf(box.size.x, box.size.z))
	cam.size = ext * (1.25 if kind != "death" else 1.6)
	var hb := sk.find_bone(String((subject_info.get(s["id"], {}) as Dictionary).get("hips", "")))
	var out := Image.create(TILE_W * TILES, TILE_H, false, Image.FORMAT_RGB8)
	var face: float = float((subject_info.get(s["id"], {}) as Dictionary).get("face", 1.0))
	for i in TILES:
		var t := (L * i / TILES / maxf(rate, 0.01)) if kind in ["loop", "loco"] else (L * i / (TILES - 1))
		var clip_t := t * rate if kind == "loco" else t
		ap.seek(fposmod(clip_t, L) if kind in ["loop", "loco"] else clip_t, true)
		# locomotion: move the model along its facing at the speed the game uses, camera follows,
		# so planted feet should stay still against the grid.
		var z := spd * t * face
		node.position = Vector3(0, 0, z)
		var cz := box.get_center().z + z
		if kind != "loco" and hb >= 0:
			cz = (sk.global_transform * sk.get_bone_global_pose(hb).origin).z   # follow the hips (rolls, deaths)
		var cy := box.position.y + h * 0.5 if kind != "death" else h * 0.3
		cam.position = Vector3(ext * 4.0, cy + ext * 0.35, cz)
		cam.look_at(Vector3(0, cy, cz), Vector3.UP)
		label.text = ("%s  %s%s\n" % [s["id"], clip, spd_note] if i == 0 else "") + "t=%.2fs" % t
		label.add_theme_font_size_override("font_size", 20)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.resize(TILE_W, TILE_H, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		out.blit_rect(img, Rect2i(0, 0, TILE_W, TILE_H), Vector2i(i * TILE_W, 0))
		# tile separator
		out.fill_rect(Rect2i(i * TILE_W, 0, 1, TILE_H), Color(0.3, 0.3, 0.3))
	node.position = Vector3.ZERO
	anim.loop_mode = loop_mode
	return out


func _sheets(groups: Dictionary) -> void:
	# One contact sheet per group: one row per subject, the row being its strips at half
	# size (4 frames each: 0, 2, 4, 6 of 8) side by side, max 1600 px wide.
	for g: String in groups:
		var items: Array = groups[g]
		var per_subject := {}
		var order: Array = []
		for it: Array in items:
			if not per_subject.has(it[0]):
				per_subject[it[0]] = []
				order.append(it[0])
			(per_subject[it[0]] as Array).append(it)
		var cell_w := 90
		var cell_h := 120
		var strip_w := cell_w * 4 + 6
		var cols := maxi(1, 1600 / strip_w)
		var rows_img: Array[Image] = []
		for sid: String in order:
			var list: Array = per_subject[sid]
			# prefer the main clips in the sheet
			var pick: Array = []
			for it: Array in list:
				if pick.size() < cols:
					pick.append(it)
			var row := Image.create(strip_w * cols, cell_h, false, Image.FORMAT_RGB8)
			row.fill(Color(1, 1, 1))
			for ci in pick.size():
				var src := Image.load_from_file(out_dir.path_join("anim_strips/" + String(pick[ci][2])))
				if src == null:
					continue
				for k in 4:
					var tile := src.get_region(Rect2i(k * 2 * TILE_W, 0, TILE_W, TILE_H))
					tile.resize(cell_w, cell_h, Image.INTERPOLATE_LANCZOS)
					row.blit_rect(tile, Rect2i(0, 0, cell_w, cell_h), Vector2i(ci * strip_w + k * cell_w, 0))
			rows_img.append(row)
		if rows_img.is_empty():
			continue
		var w := rows_img[0].get_width()
		var sheet := Image.create(w, rows_img.size() * (cell_h + 4), false, Image.FORMAT_RGB8)
		sheet.fill(Color(1, 1, 1))
		for i in rows_img.size():
			sheet.blit_rect(rows_img[i], Rect2i(0, 0, w, cell_h), Vector2i(0, i * (cell_h + 4)))
		sheet.save_jpg(out_dir.path_join("anim_sheet_%s.jpg" % g), 0.8)


## Partial runs (--only=...) write their own report so the full report is never clobbered.
func _suffix() -> String:
	return "" if only == "" else "_only_" + only.validate_filename()
