extends RefCounted
## Smaller war screens from the extra references (docs/design/war_ui_reference_2..4.webp): battle aftermath, territory
## occupation, logistics and supplies, officer profile, scout report. Static builders that fill a container; the views that
## own the container decide where they go (a panel, a modal).

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const WarUnits := preload("res://scripts/realm/war_units.gd")


static func _card(parent: Control, border := AF.GOLD_DIM) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Kit.box(Color(0.03, 0.028, 0.025, 0.6), border, 3, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	pc.add_child(v)
	parent.add_child(pc)
	return v


static func _stat(parent: Control, name_: String, value: String, col := AF.TEXT) -> void:
	var h := HBoxContainer.new()
	var l := Kit.lbl(name_, 15, AF.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(Kit.lbl(value, 16, col))
	parent.add_child(h)


## Losses split the way a field hospital would see them (R: battle aftermath): killed, wounded, missing, captured.
static func aftermath_stats(res: Dictionary, side: int) -> Dictionary:
	var cas := res.get("cas", {"a": 0, "b": 0}) as Dictionary
	var mine := int(cas["a" if side == 0 else "b"])
	var theirs := int(cas["b" if side == 0 else "a"])
	var won := String(res.get("winner", "")) == ("a" if side == 0 else "b")
	var lost_field := String(res.get("winner", "")) != "" and not won
	var my_k := int(round(float(mine) * 0.5))
	var my_w := int(round(float(mine) * 0.36))
	var my_m := mine - my_k - my_w
	var their_share_captured := 0.22 if won else 0.05
	var th_c := int(round(float(theirs) * their_share_captured))
	var th_k := int(round(float(theirs) * 0.5))
	var th_w := theirs - th_k - th_c
	return {"won": won, "drawn": String(res.get("winner", "")) == "", "mine": {"killed": my_k, "wounded": my_w, "missing": my_m, "captured": int(round(float(my_m) * 0.4)) if lost_field else 0},
		"theirs": {"killed": th_k, "wounded": th_w, "captured": th_c}, "total_mine": mine, "total_theirs": theirs}


## The aftermath card (reference 13): Victory / Defeat, both sides' losses, Pursue Enemy and Return to Camp.
static func build_aftermath(parent: Control, res: Dictionary, side: int, pursue: Callable, back: Callable) -> void:
	var st := aftermath_stats(res, side)
	var head := "Victory" if bool(st["won"]) else ("Stalemate" if bool(st["drawn"]) else "Defeat")
	var v := _card(parent, AF.GOLD)
	v.add_child(Kit.lbl("%s - %s" % [head, String(res.get("terrain", "the field"))], 22, Color("9be36a") if bool(st["won"]) else (AF.GOLD_BRIGHT if bool(st["drawn"]) else Color("ff7a6a")), false, "title_bold"))
	v.add_child(Kit.lbl(String(res.get("why", "")), 15, AF.TEXT_DIM, true, "italic"))
	var m := _card(parent)
	m.add_child(Kit.lbl("Your Forces", 17, Color("7fb0ff")))
	var mine: Dictionary = st["mine"]
	_stat(m, "Killed", str(mine["killed"]))
	_stat(m, "Wounded", str(mine["wounded"]))
	_stat(m, "Missing", str(mine["missing"]))
	var e := _card(parent)
	e.add_child(Kit.lbl("Enemy Forces", 17, Color("ff8a7a")))
	var th: Dictionary = st["theirs"]
	_stat(e, "Killed", str(th["killed"]))
	_stat(e, "Wounded", str(th["wounded"]))
	_stat(e, "Captured", str(th["captured"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if bool(st["won"]) and pursue.is_valid():
		var pb := Kit.button("Pursue Enemy", false, 52.0, 16)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.pressed.connect(pursue)
		row.add_child(pb)
	var rb := Kit.button("Return to Camp", true, 52.0, 16)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rb.pressed.connect(back)
	row.add_child(rb)
	parent.add_child(row)


## Territory occupation (reference 14): loyalty, population, tax, garrison, rebel risk. `realm`: the realm hub (may be null).
static func occupation_info(realm: RefCounted, node: int, garrison := 0) -> Dictionary:
	var name_ := "Settlement %d" % node
	var pop := 1200
	if node >= 0 and node < WorldGen.settlements.size():
		var s: Dictionary = WorldGen.settlements[node]
		name_ = String(s["name"])
		pop = int(float(s["radius"]) * 24.0)
	var loyalty := 40.0
	var unrest := 0.3
	var holder := "unknown"
	var occupier := "unknown"
	if realm != null:
		var land: RefCounted = realm.call("mod", "land")
		if land != null:
			loyalty = float(land.call("loyalty", str(node)))
			unrest = float(land.call("unrest", str(node)))
			var d: Dictionary = land.call("deed", str(node))
			holder = String(d.get("holder", holder))
			occupier = String(d.get("occupier", occupier))
	var risk := "Low" if unrest < 0.3 else ("Medium" if unrest < 0.6 else "High")
	return {"name": name_, "status": "Occupied (You)" if occupier == "player" else "Held by %s" % holder, "loyalty": loyalty, "population": pop, "tax": int(round(float(pop) * 0.15 * (loyalty / 100.0))),
		"garrison": garrison, "garrison_max": maxi(garrison, int(float(pop) / 6.0)), "rebel_risk": risk, "holder": holder, "occupier": occupier}


static func build_occupation(parent: Control, info: Dictionary, manage: Callable) -> void:
	var v := _card(parent, AF.GOLD)
	v.add_child(Kit.lbl("Territory Occupation: %s" % String(info["name"]), 19, AF.GOLD_BRIGHT, false, "title_bold"))
	_stat(v, "Status", String(info["status"]))
	_stat(v, "Loyalty", "%d%%" % int(round(float(info["loyalty"]))), Color("9be36a") if float(info["loyalty"]) >= 50.0 else Color("ffb070"))
	_stat(v, "Population", str(info["population"]))
	_stat(v, "Tax Income", "+%d / day" % int(info["tax"]))
	_stat(v, "Garrison", "%d / %d" % [int(info["garrison"]), int(info["garrison_max"])])
	_stat(v, "Rebel Risk", String(info["rebel_risk"]), Color("ff7a6a") if String(info["rebel_risk"]) == "High" else AF.TEXT)
	if manage.is_valid():
		var b := Kit.button("Manage Settlement", true, 52.0, 16)
		b.pressed.connect(manage)
		v.add_child(b)


## Logistics and supplies (reference 10 / 14): food, ammunition, medicine, horse feed, engineers, with supply-route risk.
static func logistics_info(cm: RefCounted, army_id: int) -> Dictionary:
	var sup: Dictionary = cm.call("supply_status", army_id)
	var days := float(sup.get("supply_days", 0.0))
	var connected := bool(sup.get("connected", false))
	var units: Array = cm.call("army_units", army_id)
	var men := 0
	var horse := 0
	var med := 0
	var eng := 0
	var arch := 0
	for u: Dictionary in units:
		men += int(u["men"])
		match String(u["kind"]):
			"heavy_cav", "light_cav", "scout":
				horse += int(u["men"])
			"medical":
				med += int(u["men"])
			"engineer":
				eng += int(u["men"])
			"archer", "mage":
				arch += int(u["men"])
	var route_risk := "Safe" if connected else "Risky"
	return {"men": men, "food": days, "ammo": days * (1.0 if arch > 0 else 0.0) * 1.1 + (2.0 if arch > 0 else 0.0), "medicine": days * 0.8 + float(med) / maxf(1.0, float(men)) * 40.0,
		"horse": days * (0.75 if horse > 0 else 0.0), "engineers": days * (1.1 if eng > 0 else 0.0), "connected": connected, "route_risk": route_risk}


static func build_logistics(parent: Control, info: Dictionary, name_: String) -> void:
	var v := _card(parent, AF.GOLD)
	v.add_child(Kit.lbl("Logistics & Supplies: %s (%s men)" % [name_, str(info["men"])], 18, AF.GOLD_BRIGHT, false, "title_bold"))
	for spec: Array in [["Food", "food"], ["Ammunition", "ammo"], ["Medicine", "medicine"], ["Horse Feed", "horse"], ["Engineers", "engineers"]]:
		var d := float(info[spec[1]])
		var h := HBoxContainer.new()
		var l := Kit.lbl(String(spec[0]), 15, AF.TEXT)
		l.custom_minimum_size = Vector2(110, 0)
		h.add_child(l)
		var b := Kit.bar(clampf(d / 12.0, 0.0, 1.0), 10.0, Color("5fae4c") if d >= 6.0 else (Color("d0a040") if d >= 3.0 else Color("c2412f")))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
		h.add_child(Kit.lbl("%d days" % int(round(d)), 15, AF.TEXT_DIM))
		v.add_child(h)
	_stat(v, "Supply route", String(info["route_risk"]), Color("9be36a") if bool(info["connected"]) else Color("ff9a6a"))
	v.add_child(Kit.lbl("Never expose supply lines: a cut road starves an army faster than a battle.", 13, AF.TEXT_DIM, true, "italic"))


static func build_officer(parent: Control, cm: RefCounted, army_id: int) -> void:
	var cmdv: Dictionary = cm.call("army_command", army_id)
	if cmdv.is_empty():
		return
	var c: Dictionary = cmdv["commander"]
	var v := _card(parent, AF.GOLD)
	v.add_child(Kit.lbl(String(c.get("name", "Commander")), 19, AF.GOLD_BRIGHT, false, "title_bold"))
	v.add_child(Kit.lbl("%s   Command capacity %d / %d men" % [String(c.get("personality", "")).capitalize(), int(c["men"]), int(c["capacity"])], 14, AF.TEXT_DIM, true))
	for k: String in WarUnits.ATTRS:
		_stat(v, k.capitalize(), str(int(c.get(k, 0))))
	for s: Dictionary in cmdv["subs"]:
		v.add_child(Kit.lbl("%s (%s): %d men" % [String(s["name"]), String(s["wing"]), int(s["men"])], 14, AF.TEXT, true))


static func build_scout_report(parent: Control, title: String, lo: int, hi: int, seen_ago_min: int, comp: Dictionary) -> void:
	var v := _card(parent, AF.GOLD)
	v.add_child(Kit.lbl(title, 19, AF.GOLD_BRIGHT, false, "title_bold"))
	_stat(v, "Estimated strength", "%d - %d" % [lo, hi])
	_stat(v, "Last seen", "%d min ago" % seen_ago_min)
	for k: String in comp:
		_stat(v, "Possible: %s" % k.capitalize().replace("_", " "), "~%d" % int(comp[k]))


## Unit-space dot layout for a formation (x across the front, y toward the rear), for previews and block drawing.
static func formation_points(name_: String, n: int, width := 12, depth := 3, spacing := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match name_:
		"column":
			var w := maxi(2, n / 10)
			for k in n:
				pts.append(Vector2(float(k % w) - float(w - 1) * 0.5, float(k / w)) - Vector2(0, float(n / w) * 0.5))
		"wedge":
			var row := 0
			var placed := 0
			while placed < n:
				for q in row + 1:
					if placed >= n:
						break
					pts.append(Vector2(float(q) - float(row) * 0.5, float(row) - float(n) * 0.06))
					placed += 1
				row += 1
		"square", "circle":
			var side_n := int(ceil(sqrt(float(n))))
			for k in n:
				if name_ == "circle":
					var a := TAU * float(k) / float(n)
					pts.append(Vector2(cos(a), sin(a)) * sqrt(float(n)) * 0.45)
				else:
					var x := k % side_n
					var y := k / side_n
					if x == 0 or y == 0 or x == side_n - 1 or y == (n - 1) / side_n or n < 20:
						pts.append(Vector2(float(x) - float(side_n - 1) * 0.5, float(y) - float(side_n - 1) * 0.5))
		"loose":
			for k in n:
				pts.append(Vector2(fmod(float(k) * 2.399, 9.0) - 4.5, fmod(float(k) * 1.618, 5.0) - 2.5) * 1.3)
		"deep_line", "layered":
			var w2 := maxi(3, int(ceil(float(n) / 6.0)))
			for k in n:
				pts.append(Vector2(float(k % w2) - float(w2 - 1) * 0.5, float(k / w2) * 0.9 - 2.0))
		"custom":
			var w3 := clampi(width, 4, 40)
			for k in n:
				pts.append(Vector2((float(k % w3) - float(w3 - 1) * 0.5) * spacing, (float(k / w3) - float(mini(depth, 8) - 1) * 0.5) * spacing) if k / w3 < depth else Vector2(0, 99))
		_:
			var w4 := maxi(6, int(ceil(float(n) / 3.0)))
			for k in n:
				pts.append(Vector2(float(k % w4) - float(w4 - 1) * 0.5, float(k / w4) - 1.0))
	return pts


