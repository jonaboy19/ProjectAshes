extends "res://scripts/ui/affairs/affairs_base.gd"
## READY_V1 C4: the SETTLEMENT page of the Affairs desk. One card per camp you founded: tier and the checklist for the next one,
## people against room, food (stock, days of food, made and eaten a day), the contentment breakdown, and the jobs. Every number
## is read from the growth module's ledger(gid) (scripts/realm/settlement_growth.gd); nothing here is computed or ticks.

const Growth := preload("res://scripts/realm/settlement_growth.gd")


func rows() -> Array:
	var g: Variant = mod("growth")
	var kit: Variant = mod("build_kit")
	var out: Array = []
	if g == null or kit == null:
		return out
	var gids: Array = kit.grids.keys()
	gids.sort()
	for gid: int in gids:
		var l: Dictionary = g.call("ledger", gid)
		if not l.is_empty():
			out.append(l)
	return out


func _fill(b: VBoxContainer) -> void:
	var list := rows()
	if list.is_empty():
		_dim(b, "You have founded no camp yet. Press X on open ground to found one.")
		return
	for l: Dictionary in list:
		_camp(b, l)


func _camp(b: VBoxContainer, l: Dictionary) -> void:
	_sec(String(l["name"]))
	var card := _card(b)
	var head := _flow(card)
	_txt(head, String(l["tier_name"]), AF.GOLD_BRIGHT, 20, "title")
	_txt(head, "%d people, room for %d" % [int(l["pop"]), int(l["capacity"])], AF.TEXT, 16)
	if String(l["next_tier"]) != "":
		_dim(card, "To become a %s:" % String(l["next_tier"]).to_lower())
		for c: Dictionary in l["checklist"]:
			var mark := "✔" if bool(c["ok"]) else "✘"
			_txt(card, "%s  %s  %s / %s" % [mark, String(c["label"]), _num(c["have"]), _num(c["need"])], Kit.GREEN if bool(c["ok"]) else AF.TEXT, 16)
	else:
		_dim(card, "A village. The lords of the Vale will take notice.")
	var food := _card(b)
	_txt(food, "Food", AF.GOLD, 17, "title")
	var starving := bool(l["starving"])
	food.add_child(Kit.bar(clampf(float(l["food"]) / maxf(float(l["store_cap"]), 1.0), 0.0, 1.0), 10.0, Kit.BAD if starving else AF.GOLD,
		"%d of %d in store" % [int(round(float(l["food"]))), int(round(float(l["store_cap"])))]))
	_txt(food, "%.1f days of food. Made %.1f a day, eaten %.1f a day.%s" % [float(l["food_days"]), float(l["food_made"]), float(l["food_eaten"]),
		"  The people are starving." if starving else ""], Kit.BAD if starving else AF.TEXT, 16)
	var mood := _card(b)
	_txt(mood, "Contentment", AF.GOLD, 17, "title")
	mood.add_child(Kit.bar(float(l["content"]), 10.0, AF.GOLD, "%d%%" % int(round(float(l["content"]) * 100.0))))
	for p: Array in l["content_parts"]:
		var d := float(p[1])
		if absf(d) < 0.0005:
			continue
		_txt(mood, "%s  %s%d" % [String(p[0]), "+" if d > 0.0 else "-", int(round(absf(d) * 100.0))], Kit.GREEN if d > 0.0 else Kit.BAD, 15)
	var jobs: Dictionary = l["jobs"]
	var work := _card(b)
	_txt(work, "Work", AF.GOLD, 17, "title")
	_txt(work, "%d of %d can work: %d farm, %d build. %d jobs for %d. %d followers lend a hand." % [int(jobs["workers"]), int(l["pop"]),
		int(jobs["farmers"]), int(jobs["builders"]), int(jobs["slots"]), int(jobs["employed"]), int(jobs["followers"])], AF.TEXT, 16)
	var st: Dictionary = l["structures"]
	_txt(work, "%d houses, %s, %s." % [int(l["houses"]), "a well" if bool(st["well"]) else "no well", "a hall" if bool(st["hall"]) else "no hall"], AF.TEXT_DIM, 15)


static func _num(v: Variant) -> String:
	return str(int(v)) if float(v) == floorf(float(v)) else "%.1f" % float(v)
