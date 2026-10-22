extends RefCounted
## Tactical AI commanders (docs/design/WAR_COMMAND_RULEBOOK.md §29-33, §35). One brain per side, run every few steps by
## tactical.gd. It obeys the player's rules: it only knows enemies its units have seen (or last saw), its orders go out
## by banner, horn or runner and arrive late, and forces it hides can be spotted. Difficulty is better decisions:
##   0 weak       reactive frontal attack, leaves openings, no reserves
##   1 moderate   reserves, flank screens, sensible terrain, waits for a target
##   2 advanced   feints, hidden movement, false retreat, logistics raids, phases
##   3 elite      reads the enemy's composition, baits, times attacks with arriving armies, changes plan mid battle
##   4 legendary  double envelopment, defeat in detail, commits reserves at the exact moment of collapse
## Doctrines (valencios / steppe / forest / eastern) change which of these it reaches for.

const WarUnits := preload("res://scripts/realm/war_units.gd")

var _seen_cache_t := -1.0


# --------------------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------------------

static func axis_v(tt: RefCounted, k: int) -> Vector2:
	return Vector2.from_angle(float((tt.S[k] as Dictionary)["axis"]))


static func anchor_v(tt: RefCounted, k: int) -> Vector2:
	var a: Array = (tt.S[k] as Dictionary)["anchor"]
	return Vector2(float(a[0]), float(a[1]))


## Lateral offset of p from the side's line (negative left of the axis, positive right).
static func lateral(tt: RefCounted, k: int, p: Vector2) -> float:
	var ax := axis_v(tt, k)
	var pv := Vector2(-ax.y, ax.x)
	return (p - anchor_v(tt, k)).dot(pv)


static func known_enemies(tt: RefCounted, k: int) -> Dictionary:
	var en := {"n": 0, "i": PackedInt32Array(), "x": PackedFloat32Array(), "y": PackedFloat32Array(), "cls": PackedInt32Array(), "men": PackedFloat32Array(),
		"seen": PackedByteArray(), "mor": PackedFloat32Array(), "age": PackedFloat32Array()}
	var ai_: PackedInt32Array = en["i"]
	var ax_: PackedFloat32Array = en["x"]
	var ay_: PackedFloat32Array = en["y"]
	var ac_: PackedInt32Array = en["cls"]
	var am_: PackedFloat32Array = en["men"]
	var as_: PackedByteArray = en["seen"]
	var ao_: PackedFloat32Array = en["mor"]
	var ag_: PackedFloat32Array = en["age"]
	var e := 1 - k
	var cnt := 0
	for i in tt.u_side.size():
		if tt.u_side[i] != e or tt.u_st[i] >= tt.S_DEAD:
			continue
		var seen: bool = ((tt.u_seen[i] >> k) & 1) == 1
		if seen:
			ai_.append(i)
			ax_.append(tt.u_x[i])
			ay_.append(tt.u_y[i])
			ac_.append(tt.u_cls[i])
			am_.append(tt.u_men[i])
			as_.append(1)
			ao_.append(tt.u_mor[i])
			ag_.append(0.0)
			cnt += 1
		elif tt.u_lst[i] >= 0.0 and tt.t - tt.u_lst[i] < 600.0:
			ai_.append(i)
			ax_.append(tt.u_lsx[i])
			ay_.append(tt.u_lsy[i])
			ac_.append(tt.u_cls[i])
			am_.append(tt.u_men0[i])
			as_.append(0)
			ao_.append(0.7)
			ag_.append(tt.t - tt.u_lst[i])
			cnt += 1
	en["n"] = cnt
	return en


static func epos(en: Dictionary, j: int) -> Vector2:
	return Vector2((en["x"] as PackedFloat32Array)[j], (en["y"] as PackedFloat32Array)[j])


static func _centroid(tt: RefCounted, ids: Array) -> Vector2:
	var c := Vector2.ZERO
	var w := 0.0
	for i: int in ids:
		c += Vector2(tt.u_x[i], tt.u_y[i]) * float(maxf(tt.u_men[i], 1.0))
		w += maxf(tt.u_men[i], 1.0)
	return c / maxf(w, 1.0)


static func _en_centroid(en: Dictionary, fallback: Vector2) -> Vector2:
	var n := int(en["n"])
	if n == 0:
		return fallback
	var c := Vector2.ZERO
	for j in n:
		c += epos(en, j)
	return c / float(n)


## Does this commander see through a trick (R§32-33)? Experience, tactics and scouting decide; a little luck fixed per battle.
static func recognises(tt: RefCounted, k: int, trick: String) -> bool:
	var cmd: Dictionary = (tt.S[k] as Dictionary)["cmd"]
	var sc := (float(cmd.get("tactics", 40)) + float(cmd.get("experience", 40)) + float(cmd.get("scouting", 40))) / 3.0
	sc += 4.0 * float(int((tt.S[k] as Dictionary)["tier"]))
	var jitter: float = (tt._hash(tt.seed, k * 7 + 1, trick.length()) - 0.5) * 12.0
	var need := 58.0 if trick == "bait" else 54.0
	return sc + jitter >= need


static func _say(tt: RefCounted, k: int, key: String, text: String) -> void:
	var ai: Dictionary = (tt.S[k] as Dictionary)["ai"]
	var lg: Array = ai.get("log", [])
	lg.append({"t": tt.t, "key": key, "text": text})
	if lg.size() > 40:
		lg.pop_front()
	ai["log"] = lg


static func ai_log(tt: RefCounted, k: int, key := "") -> Array:
	var out: Array = []
	for e: Dictionary in ((tt.S[k] as Dictionary)["ai"] as Dictionary).get("log", []):
		if key == "" or String(e["key"]) == key:
			out.append(e)
	return out


## Sends an order unless the unit is already doing (or has been sent) the same thing.
static func give(tt: RefCounted, k: int, i: int, behavior: String, p := Vector2.INF, target := -1, extra := {}) -> void:
	var ai: Dictionary = (tt.S[k] as Dictionary)["ai"]
	var sent: Array = ai["sent"]
	while sent.size() <= i:
		sent.append([])
	var s: Array = sent[i]
	if not s.is_empty():
		var seek := behavior in ["advance", "charge", "intercept", "commit", "flank"]
		var lim := 62500.0 if seek else 2025.0
		if String(s[0]) == behavior and int(s[3]) == target and (p == Vector2.INF or Vector2(float(s[1]), float(s[2])).distance_squared_to(p) < lim) and tt.t - float(s[4]) < (360.0 if seek else 240.0):
			return
	var o := {"behavior": behavior}
	if p != Vector2.INF:
		o["x"] = p.x
		o["y"] = p.y
	if target >= 0:
		o["target"] = target
	for kk: String in extra:
		o[kk] = extra[kk]
	var r: Dictionary = tt.order(k, i, o)
	if bool(r.get("ok", false)):
		sent[i] = [behavior, p.x if p != Vector2.INF else 0.0, p.y if p != Vector2.INF else 0.0, target, tt.t]


# --------------------------------------------------------------------------------------------------
# deployment
# --------------------------------------------------------------------------------------------------

func deploy(tt: RefCounted, k: int) -> void:
	var sd: Dictionary = tt.S[k]
	var tier := int(sd["tier"])
	var doc: Dictionary = tt.DOCTRINE.get(String(sd["doctrine"]), tt.DOCTRINE["valencios"])
	var pers := String((sd["cmd"] as Dictionary).get("personality", "loyal"))
	sd["ai"] = {"phase": "approach", "log": [], "sent": [], "fr": "", "feint": [], "plan": "", "bait": -1}
	var share := float(doc["ambush"])
	if share > 0.0 and tier >= 1:
		var ids: Array = tt.side_units(k)
		var cand: Array = []
		for i: int in ids:
			var cls := int(tt.u_cls[i])
			if cls in [2, 3, 4] or (cls == 0 and String((tt.u_meta[i] as Dictionary)["layer"]) != "front"):
				cand.append(i)
		var want := int(round(share * float(ids.size())))
		for c in mini(want, cand.size()):
			_seek_cover(tt, k, cand[c])
	if pers == "cautious" and tier >= 1:
		sd["formation"] = "deep_line" if String(sd["formation"]) == "line" else sd["formation"]


## Moves a unit into forest / broken ground on its side's forward flank and tells it to lie in ambush.
func _seek_cover(tt: RefCounted, k: int, i: int) -> void:
	var ax := axis_v(tt, k)
	var pv := Vector2(-ax.y, ax.x)
	var anc := anchor_v(tt, k)
	var best := Vector2.INF
	var bd := 1.0e9
	var side_sgn := 1.0 if tt._hash(tt.seed, i, 4) < 0.5 else -1.0
	for r in range(2, 12):
		for a in 10:
			var ang := float(a) / 10.0 * TAU
			var p: Vector2 = anc + ax * 90.0 + pv * side_sgn * 160.0 + Vector2.from_angle(ang) * float(r) * tt.cell
			if p.x < 20.0 or p.y < 20.0 or p.x > tt.size_m() - 20.0 or p.y > tt.size_m() - 20.0:
				continue
			var code: int = tt.code_at(p.x, p.y)
			if tt.HIDE_T[code] >= 0.2 and tt.SPEED_T[code] > 0.0:
				var d := p.distance_to(anc + ax * 90.0 + pv * side_sgn * 160.0)
				if d < bd:
					bd = d
					best = p
		if best != Vector2.INF:
			break
	if best != Vector2.INF:
		tt.u_x[i] = best.x
		tt.u_y[i] = best.y
		tt.u_tx[i] = best.x
		tt.u_ty[i] = best.y
		tt._apply_order(i, {"behavior": "ambush", "x": best.x, "y": best.y})
		tt.u_hid[i] = 1
		(tt.u_meta[i] as Dictionary)["role"] = "ambush"


# --------------------------------------------------------------------------------------------------
# thinking
# --------------------------------------------------------------------------------------------------

func think(tt: RefCounted, k: int) -> void:
	var sd: Dictionary = tt.S[k]
	if bool(sd["retreat"]) or tt.phase != "battle":
		return
	var tier := int(sd["tier"])
	var mine: Array = tt.side_units(k)
	if mine.is_empty():
		return
	if not (sd["ai"] as Dictionary).has("sent"):
		sd["ai"] = {"phase": "approach", "log": [], "sent": [], "fr": "", "feint": [], "plan": "", "bait": -1}
	var st := {"mine": mine, "en": known_enemies(tt, k), "tier": tier, "role": "attack" if k == tt.attacker else "defend",
		"pers": String((sd["cmd"] as Dictionary).get("personality", "loyal")), "doc": String(sd["doctrine"])}
	_bait_watch(tt, k, st)
	match tier:
		0:
			_weak(tt, k, st)
		1:
			_moderate(tt, k, st)
		_:
			_advanced(tt, k, st)


## A cheap fingerprint of what the commander can see and what his units are doing. When it has not changed since the
## last look there is nothing new to decide.
func _signature(tt: RefCounted, k: int, mine: Array) -> int:
	var ust: PackedInt32Array = tt.u_st
	var idle := 0
	var fight := 0
	var rout := 0
	for i: int in mine:
		var s: int = ust[i]
		if s == 0:
			idle += 1
		elif s == 2:
			fight += 1
	var seen_n := 0
	var near := 0
	var usd: PackedInt32Array = tt.u_side
	var useen: PackedInt32Array = tt.u_seen
	var ux: PackedFloat32Array = tt.u_x
	var uy: PackedFloat32Array = tt.u_y
	var cen := _centroid(tt, mine)
	for j in usd.size():
		if usd[j] != k:
			if ust[j] < 7 and ((useen[j] >> k) & 1) == 1:
				seen_n += 1
				var dx := ux[j] - cen.x
				var dy := uy[j] - cen.y
				if dx * dx + dy * dy < 250000.0:
					near = 1
		elif ust[j] == 4:
			rout += 1
	var fb := 0 if fight == 0 else (1 if fight < 4 else 2)
	return (((seen_n * 31 + idle) * 7 + fb) * 11 + rout) * 2 + near


## A seen enemy unit backing away with its morale high and few losses is not running: it is bait (R§32). Experienced
## commanders recognise that and keep their line; the rest give chase.
func _bait_watch(tt: RefCounted, k: int, st: Dictionary) -> void:
	var ai: Dictionary = (tt.S[k] as Dictionary)["ai"]
	if ai.get("bait_seen", false):
		return
	var en: Dictionary = st["en"]
	var seen: PackedByteArray = en["seen"]
	var eid: PackedInt32Array = en["i"]
	var cen := _centroid(tt, st["mine"])
	var suspect := -1
	for j in int(en["n"]):
		if seen[j] == 0:
			continue
		var idx := eid[j]
		var s: int = tt.u_st[idx]
		if s != tt.S_MOVE and s != tt.S_RETREAT:
			continue
		var to_me := (cen - epos(en, j)).normalized()
		if Vector2.from_angle(tt.u_face[idx]).dot(to_me) > -0.4:
			continue
		var loss: float = tt.u_cas[idx] / maxf(tt.u_men0[idx], 1.0)
		if tt.u_mor[idx] > 0.5 and loss < 0.2 and tt.u_cas[idx] > 0.0:
			suspect = idx
			break
	if suspect < 0:
		return
	ai["bait_seen"] = true
	if recognises(tt, k, "bait"):
		ai["bait_ignored"] = true
		_say(tt, k, "ignored_bait", "%s suspects a feigned retreat and keeps the line." % String((tt.S[k] as Dictionary)["name"]))
		for i: int in st["mine"]:
			if tt.u_tgt[i] == suspect or (int(tt.u_st[i]) == tt.S_MOVE and _pos(tt, i).distance_to(Vector2(tt.u_x[suspect], tt.u_y[suspect])) < 420.0 and int(tt.u_cls[i]) != 3):
				give(tt, k, i, "hold")
	else:
		_say(tt, k, "took_bait", "%s sees the enemy break and gives chase." % String((tt.S[k] as Dictionary)["name"]))
		for i2: int in st["mine"]:
			if int(tt.u_cls[i2]) in [0, 1, 3] and String((tt.u_meta[i2] as Dictionary)["layer"]) != "reserve":
				give(tt, k, i2, "charge", Vector2(tt.u_x[suspect], tt.u_y[suspect]))


## Index (into the known-enemy arrays) of the enemy nearest p, or -1. cls_only >= 0 restricts to one unit class.
static func nearest(p: Vector2, en: Dictionary, cls_only := -1) -> int:
	var best := -1
	var bd := 1.0e18
	var xs: PackedFloat32Array = en["x"]
	var ys: PackedFloat32Array = en["y"]
	var cs: PackedInt32Array = en["cls"]
	for j in int(en["n"]):
		if cls_only >= 0 and cs[j] != cls_only:
			continue
		var dx := xs[j] - p.x
		var dy := ys[j] - p.y
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = j
	return best


func _front_ids(tt: RefCounted, mine: Array) -> Array:
	var out: Array = []
	for i: int in mine:
		if int(tt.u_cls[i]) in [0, 1] and String((tt.u_meta[i] as Dictionary)["layer"]) in ["front", "second"]:
			out.append(i)
	return out


func _pos(tt: RefCounted, i: int) -> Vector2:
	return Vector2(tt.u_x[i], tt.u_y[i])


## Weak commander: everything walks at the nearest enemy and hits it head on.
func _weak(tt: RefCounted, k: int, st: Dictionary) -> void:
	var en: Dictionary = st["en"]
	var goal := anchor_v(tt, 1 - k)
	for i: int in (st["mine"] as Array):
		if tt.u_st[i] == tt.S_FIGHT or tt.u_st[i] == tt.S_ROUT:
			continue
		var p := _pos(tt, i)
		var j := nearest(p, en)
		if st["role"] == "defend" and (j < 0 or p.distance_to(epos(en, j)) > 380.0):
			if String(((tt.u_meta[i] as Dictionary)["order"] as Dictionary).get("behavior", "hold")) != "hold":
				give(tt, k, i, "hold")
			continue
		var target: Vector2 = epos(en, j) if j >= 0 else goal
		if int(tt.u_cls[i]) == 3 and j >= 0:
			give(tt, k, i, "charge", target)
		else:
			give(tt, k, i, "advance", target)


## Moderate commander: line advance, a reserve released on trouble, flank screens, terrain sense.
func _moderate(tt: RefCounted, k: int, st: Dictionary) -> void:
	var mine: Array = st["mine"]
	var en: Dictionary = st["en"]
	var goal := anchor_v(tt, 1 - k)
	var sd: Dictionary = tt.S[k]
	var ai: Dictionary = sd["ai"]
	var ust: PackedInt32Array = tt.u_st
	var ucls: PackedInt32Array = tt.u_cls
	var umor: PackedFloat32Array = tt.u_mor
	var ux: PackedFloat32Array = tt.u_x
	var uy: PackedFloat32Array = tt.u_y
	var urad: PackedFloat32Array = tt.u_rad
	var umeta: Array = tt.u_meta
	var usd: PackedInt32Array = tt.u_side
	var cav_t: PackedFloat32Array = tt.CAV_T
	var attack: bool = st["role"] == "attack"
	var front: Array = []
	var cx := 0.0
	var cy := 0.0
	var cw := 0.0
	var trouble := false
	for i: int in mine:
		var ly: String = (umeta[i] as Dictionary)["layer"]
		if ucls[i] < 2 and (ly == "front" or ly == "second"):
			front.append(i)
			if umor[i] < 0.42:
				trouble = true
	var use_ids: Array = front if not front.is_empty() else mine
	for i0: int in use_ids:
		var w := maxf(tt.u_men[i0], 1.0)
		cx += ux[i0] * w
		cy += uy[i0] * w
		cw += w
	var cen := Vector2(cx, cy) / maxf(cw, 1.0)
	var jn := nearest(cen, en)
	var dist_en := cen.distance_to(epos(en, jn)) if jn >= 0 else 99999.0
	for i2 in usd.size():
		if usd[i2] == k and ust[i2] == 4:
			trouble = true
			break
	if not trouble and tt.side_morale(k) < 0.5:
		trouble = true
	var engaged := dist_en < 330.0
	var ax := axis_v(tt, k)
	var pv := Vector2(-ax.y, ax.x)
	var eid: PackedInt32Array = en["i"]
	for i3: int in mine:
		var meta: Dictionary = umeta[i3]
		var layer: String = meta["layer"]
		var ustate := ust[i3]
		if ustate == 4 or (ustate == 2 and layer != "reserve"):
			continue
		if ustate == 1 and attack and layer != "reserve" and layer != "flank_l" and layer != "flank_r":
			continue
		var cls := ucls[i3]
		var p := Vector2(ux[i3], uy[i3])
		var j := nearest(p, en)
		var tpos: Vector2 = epos(en, j) if j >= 0 else goal
		if layer == "reserve":
			if (trouble or (engaged and attack and ai.get("commit", false))) and not bool(ai.get("committed_" + str(i3), false)):
				ai["committed_" + str(i3)] = true
				give(tt, k, i3, "commit", _weakest_point(tt, k, en, mine))
				_say(tt, k, "reserve", "%s committed the reserve." % String(sd["name"]))
		elif layer == "flank_l" or layer == "flank_r":
			var sgn := -1.0 if layer == "flank_l" else 1.0
			var screen_pt: Vector2 = cen + ax * 40.0 + pv * sgn * (220.0 + float(urad[i3]))
			var jc := nearest(screen_pt, en, 3)
			if cls == 3 and jc >= 0 and screen_pt.distance_to(epos(en, jc)) < 420.0:
				give(tt, k, i3, "intercept", epos(en, jc), eid[jc])
			elif engaged and cls == 3 and j >= 0:
				if cav_t[tt.code_at(tpos.x, tpos.y)] < 0.75:
					give(tt, k, i3, "screen", screen_pt)
				else:
					give(tt, k, i3, "flank", tpos + pv * sgn * 120.0)
			else:
				give(tt, k, i3, "screen", screen_pt)
		elif not attack and not engaged:
			give(tt, k, i3, "hold")
		elif cls == 2 or cls == 6:
			if p.distance_to(tpos) > 240.0:
				give(tt, k, i3, "advance", tpos)
			else:
				give(tt, k, i3, "hold")
		elif cls == 4:
			if engaged:
				give(tt, k, i3, "advance", tpos)
			else:
				give(tt, k, i3, "hold")
		elif cls == 3:
			give(tt, k, i3, "charge", tpos)
		else:
			give(tt, k, i3, "advance", tpos)
	if engaged:
		ai["commit"] = true


func _weakest_point(tt: RefCounted, k: int, en: Dictionary, mine: Array) -> Vector2:
	var worst := Vector2.INF
	var wm := 2.0
	for i: int in mine:
		if tt.u_st[i] < tt.S_DEAD and String((tt.u_meta[i] as Dictionary)["layer"]) != "reserve" and tt.u_mor[i] < wm and int(tt.u_cls[i]) in [0, 1]:
			wm = tt.u_mor[i]
			worst = _pos(tt, i)
	if worst != Vector2.INF:
		return worst
	var j := nearest(anchor_v(tt, k), en)
	return epos(en, j) if j >= 0 else anchor_v(tt, 1 - k)


## Advanced and better: moderate behaviour plus feints, hidden movement, false retreat, raids on the rear, phases and replanning.
func _advanced(tt: RefCounted, k: int, st: Dictionary) -> void:
	var sd: Dictionary = tt.S[k]
	var ai: Dictionary = sd["ai"]
	var tier := int(st["tier"])
	var mine: Array = st["mine"]
	var en: Dictionary = st["en"]
	var doc: Dictionary = tt.DOCTRINE.get(String(sd["doctrine"]), tt.DOCTRINE["valencios"])
	var front := _front_ids(tt, mine)
	var cen := _centroid(tt, mine if front.is_empty() else front)
	var ax := axis_v(tt, k)
	var pv := Vector2(-ax.y, ax.x)
	var goal := anchor_v(tt, 1 - k)
	var jn := nearest(cen, en)
	var dist_en := cen.distance_to(epos(en, jn)) if jn >= 0 else 99999.0
	var f: Dictionary = tt.forces(k)
	var ef: Dictionary = tt.enemy_intel(k)
	if tier >= 3:
		_read_enemy(tt, k, st, ai, ef)
	_watch_wings(tt, k, st, ai, cen, ef)
	if String(ai.get("plan", "")) == "" and tt.t < 400.0:
		_plan(tt, k, st, ai, doc, cen, ax, pv, goal)
	if tier >= 3:
		_replan(tt, k, st, ai, f)
	_run_plan(tt, k, st, ai, cen, ax, pv, goal, dist_en)
	_moderate_rest(tt, k, st, ai)


func _read_enemy(tt: RefCounted, k: int, st: Dictionary, ai: Dictionary, ef: Dictionary) -> void:
	var comp: Dictionary = ef["comp"]
	var tot := 0.0
	for c: String in comp:
		tot += float(comp[c])
	if tot <= 0.0:
		return
	var cav := (float(comp.get("heavy_cav", 0)) + float(comp.get("light_cav", 0))) / tot
	var arch := (float(comp.get("archer", 0)) + float(comp.get("mage", 0))) / tot
	if cav > 0.22 and not ai.get("anti_cav", false):
		ai["anti_cav"] = true
		for i: int in st["mine"]:
			if String((tt.u_meta[i] as Dictionary)["kind"]) == "spear":
				tt.set_formation(i, "spear_wall")
		_say(tt, k, "anticipate", "Enemy cavalry strength noted: spears to the wall.")
	if arch > 0.25 and not ai.get("anti_arch", false):
		ai["anti_arch"] = true
		for i2: int in st["mine"]:
			if int(tt.u_cls[i2]) == 0 and String((tt.u_meta[i2] as Dictionary)["layer"]) == "front":
				tt.set_formation(i2, "shield")
		_say(tt, k, "anticipate", "Enemy archers noted: shields up.")


## Seen enemies per wing of our own line. A small detachment pressing a wing may be a feint: weak eyes reinforce, sharp eyes do not.
func _watch_wings(tt: RefCounted, k: int, st: Dictionary, ai: Dictionary, cen: Vector2, ef: Dictionary) -> void:
	var left := 0.0
	var right := 0.0
	var en: Dictionary = st["en"]
	var seen: PackedByteArray = en["seen"]
	var men: PackedFloat32Array = en["men"]
	for j in int(en["n"]):
		if seen[j] == 0:
			continue
		var lat := lateral(tt, k, epos(en, j))
		if lat < -150.0:
			left += men[j]
		elif lat > 150.0:
			right += men[j]
	var est_total := float(ef["est_max"])
	if est_total <= 0.0 or (left <= 0.0 and right <= 0.0):
		return
	for wing: String in ["left", "right"]:
		var m := left if wing == "left" else right
		if m <= 0.0 or ai.get("wing_" + wing, false):
			continue
		var mine_there := 0.0
		for i: int in st["mine"]:
			var lt := lateral(tt, k, _pos(tt, i))
			if (wing == "left" and lt < -150.0) or (wing == "right" and lt > 150.0):
				mine_there += tt.u_men[i]
		if m > 0.7 * mine_there and tt.t > 120.0:
			ai["wing_" + wing] = true
			if m < 0.36 * est_total and recognises(tt, k, "feint"):
				_say(tt, k, "ignored_feint", "%s sees through the demonstration on the %s and keeps its reserve." % [String((tt.S[k] as Dictionary)["name"]), wing])
			else:
				ai["reinforce"] = wing
				_say(tt, k, "reinforce_wing", "%s moves to reinforce the %s wing." % [String((tt.S[k] as Dictionary)["name"]), wing])
				var sgn := -1.0 if wing == "left" else 1.0
				var spot: Vector2 = cen + pv_of(tt, k) * sgn * 230.0
				for i2: int in st["mine"]:
					if String((tt.u_meta[i2] as Dictionary)["layer"]) == "reserve" or (int(tt.u_cls[i2]) == 1 and String((tt.u_meta[i2] as Dictionary)["layer"]) == "second"):
						var was_res := String((tt.u_meta[i2] as Dictionary)["layer"]) == "reserve"
						give(tt, k, i2, "commit" if was_res else "advance", spot)
						(tt.u_meta[i2] as Dictionary)["layer"] = "front"
						break


static func pv_of(tt: RefCounted, k: int) -> Vector2:
	var ax := axis_v(tt, k)
	return Vector2(-ax.y, ax.x)


func _plan(tt: RefCounted, k: int, st: Dictionary, ai: Dictionary, doc: Dictionary, cen: Vector2, ax: Vector2, pv: Vector2, _goal: Vector2) -> void:
	var tier := int(st["tier"])
	var mine: Array = st["mine"]
	var cav: Array = []
	var light: Array = []
	for i: int in mine:
		if int(tt.u_cls[i]) == 3:
			cav.append(i)
			if String((tt.u_meta[i] as Dictionary)["kind"]) == "light_cav":
				light.append(i)
	var plan := "line"
	var rnd: float = tt._hash(tt.seed, 41, k + 5)
	if tier >= 4 and cav.size() >= 2:
		plan = "pincer"
	elif bool(doc["false_retreat"]) and not light.is_empty() and mine.size() >= 4 and rnd < 0.8:
		plan = "false_retreat"
	elif tier >= 2 and mine.size() >= 5 and rnd < 0.55 and st["role"] == "attack":
		plan = "feint"
	elif tier >= 3 and st["role"] == "defend":
		plan = "bait"
	elif float(doc["ambush"]) > 0.0:
		plan = "ambush"
	elif tier >= 2:
		plan = "screen"
	if String(ai.get("force_plan", "")) != "":
		plan = String(ai["force_plan"])
	ai["plan"] = plan
	_say(tt, k, "plan_" + plan, "%s adopts the %s plan." % [String((tt.S[k] as Dictionary)["name"]), plan.replace("_", " ")])
	match plan:
		"false_retreat":
			if light.is_empty():
				ai["fr"] = "done"
				return
			var bait: int = light[0]
			ai["bait_unit"] = bait
			ai["fr"] = "engage"
			var hidden: Array = []
			for j: int in mine:
				if j == bait or int(tt.u_cls[j]) == 3:
					continue
				if String((tt.u_meta[j] as Dictionary)["layer"]) in ["second", "third"] and hidden.size() < 3:
					hidden.append(j)
			ai["ambushers"] = hidden
			ai["trap"] = [cen.x + ax.x * 60.0 + pv.x * 200.0, cen.y + ax.y * 60.0 + pv.y * 200.0]
			# the ambushers go to ground now, before the bait is offered
			for q in hidden.size():
				var a: int = hidden[q]
				var tp := Vector2(float((ai["trap"] as Array)[0]), float((ai["trap"] as Array)[1])) + pv * float(q - 1) * 70.0
				give(tt, k, a, "ambush", tp)
		"feint":
			var det: Array = []
			for j2: int in mine:
				if String((tt.u_meta[j2] as Dictionary)["layer"]) == "second" and int(tt.u_cls[j2]) in [0, 1] and det.size() < 1:
					det.append(j2)
			if det.is_empty() and not light.is_empty():
				det.append(light[0])
			ai["feint"] = det
			ai["feint_side"] = 1.0 if tt._hash(tt.seed, 13, k) < 0.5 else -1.0
		"bait":
			var weak := -1
			for j3: int in mine:
				if int(tt.u_cls[j3]) in [0, 1] and String((tt.u_meta[j3] as Dictionary)["layer"]) in ["front", "second"] and (weak < 0 or tt.u_q[j3] < tt.u_q[weak]):
					weak = j3
			ai["bait"] = weak
			if weak >= 0:
				(tt.u_meta[weak] as Dictionary)["role"] = "bait"
				give(tt, k, weak, "hold", cen + ax * 190.0)
		"pincer":
			ai["pincer"] = cav.duplicate()


func _run_plan(tt: RefCounted, k: int, st: Dictionary, ai: Dictionary, cen: Vector2, ax: Vector2, pv: Vector2, goal: Vector2, dist_en: float) -> void:
	var plan := String(ai.get("plan", ""))
	var en: Dictionary = st["en"]
	var mine: Array = st["mine"]
	var seen: PackedByteArray = en["seen"]
	match plan:
		"false_retreat":
			var fr := String(ai.get("fr", ""))
			var bait := int(ai.get("bait_unit", -1))
			if bait < 0 or tt.u_st[bait] >= tt.S_DEAD or fr == "done" or fr == "":
				return
			var trap := Vector2(float((ai["trap"] as Array)[0]), float((ai["trap"] as Array)[1]))
			var amb: Array = ai.get("ambushers", [])
			if fr == "engage":
				var j := nearest(_pos(tt, bait), en)
				if j >= 0:
					give(tt, k, bait, "harass", epos(en, j))
				else:
					give(tt, k, bait, "advance", goal)
				if float(ai.get("fr_t", 0.0)) == 0.0 and (tt.u_cas[bait] > 0.5 or tt.u_st[bait] == tt.S_FIGHT):
					ai["fr_t"] = tt.t
				if float(ai.get("fr_t", 0.0)) > 0.0:
					ai["fr"] = "retreat"
					ai["fr_t"] = tt.t
					give(tt, k, bait, "false_retreat", trap - ax * 40.0)
					_say(tt, k, "false_retreat", "%s feigns a retreat." % String((tt.u_meta[bait] as Dictionary)["name"]))
			elif fr == "retreat":
				give(tt, k, bait, "false_retreat", trap - ax * 40.0)
				var chasers := 0
				for j2 in int(en["n"]):
					if seen[j2] == 1 and epos(en, j2).distance_to(trap) < 260.0:
						chasers += 1
				if chasers > 0 or tt.t - float(ai.get("fr_t", 0.0)) > 240.0:
					ai["fr"] = "spring"
					for a2: int in amb:
						var nr := nearest(_pos(tt, a2), en)
						give(tt, k, a2, "charge" if int(tt.u_cls[a2]) in [0, 1, 3] else "advance", epos(en, nr) if nr >= 0 else goal)
					give(tt, k, bait, "charge", trap + ax * 120.0)
					_say(tt, k, "spring", "The trap is sprung.")
			elif fr == "spring":
				var n2 := nearest(_pos(tt, bait), en)
				if n2 >= 0:
					give(tt, k, bait, "charge", epos(en, n2))
		"feint":
			var det: Array = ai.get("feint", [])
			var sgn := float(ai.get("feint_side", 1.0))
			var spot: Vector2 = cen + ax * 360.0 + pv * sgn * 260.0
			for d: int in det:
				if tt.u_st[d] < tt.S_DEAD:
					give(tt, k, d, "feint", spot)
			if dist_en < 700.0 or tt.t > 300.0:
				for i: int in mine:
					if int(tt.u_cls[i]) == 3 and not det.has(i):
						give(tt, k, i, "flank", cen + ax * 420.0 - pv * sgn * 330.0)
		"pincer":
			var pc: Array = ai.get("pincer", [])
			var enc := _en_centroid(en, goal)
			for q in pc.size():
				var i2: int = pc[q]
				if tt.u_st[i2] < tt.S_DEAD:
					var sgn2 := -1.0 if q % 2 == 0 else 1.0
					if dist_en > 420.0:
						give(tt, k, i2, "flank", enc + pv * sgn2 * 340.0 + ax * 80.0)
					else:
						var nr2 := nearest(_pos(tt, i2), en)
						give(tt, k, i2, "charge", epos(en, nr2) if nr2 >= 0 else enc)
		"ambush":
			for j3: int in mine:
				if String((tt.u_meta[j3] as Dictionary)["role"]) == "ambush" and tt.u_st[j3] < tt.S_DEAD:
					var nr3 := nearest(_pos(tt, j3), en)
					if nr3 >= 0 and _pos(tt, j3).distance_to(epos(en, nr3)) < 150.0:
						give(tt, k, j3, "charge", epos(en, nr3))
						(tt.u_meta[j3] as Dictionary)["role"] = "sprung"
		"screen":
			for j4: int in mine:
				if String((tt.u_meta[j4] as Dictionary)["kind"]) in ["light_cav", "scout"] and tt.t < 300.0:
					var nr4 := nearest(_pos(tt, j4), en)
					if nr4 < 0:
						give(tt, k, j4, "advance", cen + ax * 280.0)
					else:
						give(tt, k, j4, "harass", epos(en, nr4))
		"bait":
			var bu := int(ai.get("bait", -1))
			if bu >= 0 and tt.u_st[bu] < tt.S_DEAD and not ai.get("bait_sprung", false):
				var eng := 0
				for j5 in int(en["n"]):
					if seen[j5] == 1 and epos(en, j5).distance_to(_pos(tt, bu)) < 160.0:
						eng += 1
				if eng >= 1:
					ai["bait_sprung"] = true
					_say(tt, k, "bait_taken", "The bait is taken: the line closes.")
					for j6: int in mine:
						if j6 != bu and String((tt.u_meta[j6] as Dictionary)["layer"]) != "reserve" and int(tt.u_cls[j6]) in [0, 1, 3]:
							var n5 := nearest(_pos(tt, j6), en)
							if n5 >= 0:
								give(tt, k, j6, "advance" if int(tt.u_cls[j6]) != 3 else "flank", epos(en, n5))
	# rear raids (advanced+): light cavalry hunt archers, mages and trains
	if int(st["tier"]) >= 2 and plan != "false_retreat" and plan != "pincer" and tt.t > 240.0:
		var soft := _soft_target(en)
		if soft >= 0:
			for j7: int in mine:
				if String((tt.u_meta[j7] as Dictionary)["kind"]) == "light_cav" and not (ai.get("feint", []) as Array).has(j7):
					give(tt, k, j7, "intercept", epos(en, soft), int((en["i"] as PackedInt32Array)[soft]))


func _soft_target(en: Dictionary) -> int:
	var best := -1
	var bm := 1.0e9
	var cs: PackedInt32Array = en["cls"]
	var seen: PackedByteArray = en["seen"]
	var men: PackedFloat32Array = en["men"]
	for j in int(en["n"]):
		if seen[j] == 1 and (cs[j] == 2 or cs[j] == 4 or cs[j] == 6):
			var score: float = men[j] + (0.0 if cs[j] == 4 else 40.0)
			if score < bm:
				bm = score
				best = j
	return best


## Changes plan mid battle (elite+): falls back when losing, presses and pursues when the enemy wavers.
func _replan(tt: RefCounted, k: int, st: Dictionary, ai: Dictionary, f: Dictionary) -> void:
	var en: Dictionary = st["en"]
	var lost := 1.0 - float(f["men"]) / maxf(1.0, float(f["men0"]))
	var cur := String(ai.get("phase", "approach"))
	var emor := 0.0
	var en_seen := 0
	var seen: PackedByteArray = en["seen"]
	var mors: PackedFloat32Array = en["mor"]
	for j in int(en["n"]):
		if seen[j] == 1:
			emor += mors[j]
			en_seen += 1
	emor /= maxf(1.0, float(en_seen))
	var next := cur
	if lost > 0.38 and float(f["morale"]) < 0.55 and cur != "defensive":
		next = "defensive"
	elif en_seen > 0 and emor < 0.4 and cur != "pursuit":
		next = "pursuit"
	elif cur == "approach" and tt.t > 200.0:
		next = "engage"
	if next != cur:
		ai["phase"] = next
		_say(tt, k, "replan_" + next, "%s changes its plan: %s." % [String((tt.S[k] as Dictionary)["name"]), next])
		if next == "defensive":
			var line := anchor_v(tt, k) - axis_v(tt, k) * 120.0
			for i: int in st["mine"]:
				if int(tt.u_cls[i]) in [0, 1]:
					give(tt, k, i, "defend", line + pv_of(tt, k) * (lateral(tt, k, _pos(tt, i)) * 0.6))
		elif next == "pursuit":
			for i2: int in st["mine"]:
				if int(tt.u_cls[i2]) == 3 or String((tt.u_meta[i2] as Dictionary)["layer"]) == "reserve":
					var nr := nearest(_pos(tt, i2), en)
					if nr >= 0:
						give(tt, k, i2, "charge", epos(en, nr))
	# timing with arriving armies (R§35): strike before the enemy's second army lands, or wait for our own
	var mine_arr: Array = tt.arrivals(k)
	var foe_arr: Array = tt.arrivals(1 - k)
	if not foe_arr.is_empty() and not ai.get("rush", false) and bool((tt.u_meta[int(foe_arr[0]["i"])] as Dictionary).get("known", false)):
		ai["rush"] = true
		_say(tt, k, "defeat_in_detail", "Enemy reinforcements are coming: strike their army before it joins.")
		for i3: int in st["mine"]:
			var n3 := nearest(_pos(tt, i3), en)
			if n3 >= 0 and int(tt.u_cls[i3]) in [0, 1, 3]:
				give(tt, k, i3, "charge" if int(tt.u_cls[i3]) == 3 else "advance", epos(en, n3))
	if not mine_arr.is_empty() and not ai.get("wait", false) and tt.t < float(mine_arr[0]["due"]):
		ai["wait"] = true
		_say(tt, k, "coordinated", "%s waits for its second army before committing." % String((tt.S[k] as Dictionary)["name"]))


## Units the plan did not name behave as under a moderate commander.
func _moderate_rest(tt: RefCounted, k: int, st: Dictionary, ai: Dictionary) -> void:
	var plan := String(ai.get("plan", ""))
	var named := {}
	if plan == "false_retreat":
		named[int(ai.get("bait_unit", -1))] = true
		for a: int in ai.get("ambushers", []):
			named[a] = true
	for d: int in ai.get("feint", []):
		named[d] = true
	if plan == "pincer":
		for c: int in ai.get("pincer", []):
			named[c] = true
	if int(ai.get("bait", -1)) >= 0:
		named[int(ai["bait"])] = true
	var mine2: Array = []
	for i: int in st["mine"]:
		if not named.has(i) and not (String((tt.u_meta[i] as Dictionary)["role"]) == "ambush"):
			mine2.append(i)
	if ai.get("wait", false) and tt.t < 300.0 and st["role"] == "attack":
		return
	if String(ai.get("phase", "")) == "defensive":
		return
	var st2 := st.duplicate()
	st2["mine"] = mine2
	_moderate(tt, k, st2)
