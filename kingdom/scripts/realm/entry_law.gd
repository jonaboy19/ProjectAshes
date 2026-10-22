extends RefCounted
## MN-7 town gates: pure verdicts for a party (the player plus companions) reaching a gate. Reads Status (the player's standing in
## the town's culture), the town's entry law (data/world/entry_laws.json) and social_perception for disguises.
## party: [{species, kind ("beast"|"monster"|"undead"|"human"), speech 0..4, civility 0..1, power (levels), named bool, bond_id}]
## town: {sid, name, culture|kingdom, kingdom, corruption 0..1, law (optional override), quarantine bool}
## ctx: {hour, day, seed, permits [{kind, species [], heads, expires, forged bool}], sponsor_status 0..1, guard {perception}, quality 0..1}
## check() -> {verdict "admit"|"admit_with_terms"|"turn_back"|"bar", law, terms, reasons, required, status, options, bribe_price, lines}
## Rolls are hashes of (seed, day, sid, party, option): the same gate on the same day gives the same answer.

const Data := preload("res://scripts/realm/mn_data.gd")
const Status := preload("res://scripts/realm/status.gd")
const SP := preload("res://scripts/realm/social_perception.gd")
const VERDICT_RANK := {"admit": 0, "admit_with_terms": 1, "turn_back": 2, "bar": 3}


static func law_of(town: Dictionary) -> Dictionary:
	var T: Dictionary = Data.table("entry_laws")
	var cult := Data.culture_of(town.get("culture", town.get("kingdom", "folk")))
	var base: Dictionary = ((T.get("laws", {}) as Dictionary).get(cult, (T.get("laws", {}) as Dictionary).get("folk", {})) as Dictionary).duplicate(true)
	var ov: Dictionary = (T.get("kingdom_override", {}) as Dictionary).get(String(town.get("kingdom", "")), {})
	for k: String in ov:
		base[k] = ov[k]
	if town.has("law"):
		base["law"] = town["law"]
	if bool(town.get("quarantine", false)):
		base["law"] = "quarantine"
	base["culture"] = cult
	return base


static func is_monster(c: Dictionary) -> bool:
	return String(c.get("kind", "monster")) != "human"


static func required_status(c: Dictionary, law: Dictionary) -> float:
	var fl: Dictionary = law.get("floor", {})
	var base := float(fl.get(String(c.get("species", "")), fl.get(String(c.get("kind", "")), fl.get("default", 0.25))))
	return base + 0.03 * float(c.get("power", 1))


static func party_hash(party: Array) -> int:
	var parts: Array = []
	for c: Variant in party:
		parts.append("%s%d" % [String((c as Dictionary).get("species", "?")), int((c as Dictionary).get("bond_id", 0))])
	return absi(hash(parts))


static func roll(ctx: Dictionary, town: Dictionary, party: Array, tag: String) -> float:
	return float(absi(hash([int(ctx.get("seed", 1)), tag, int(ctx.get("day", 0)), int(town.get("sid", 0)), party_hash(party)])) % 10000) / 10000.0


static func is_dusk(hour: int, T: Dictionary) -> bool:
	return hour >= int(T.get("dusk_hour", 20)) or hour < int(T.get("dawn_hour", 5))


static func _valid_permit(p: Dictionary, c: Dictionary, day: int) -> bool:
	if int(p.get("expires", 1 << 30)) < day:
		return false
	var sp: Array = p.get("species", [])
	return sp.is_empty() or String(c.get("species", "")) in sp


static func bribe_price(party: Array, town: Dictionary) -> int:
	var T: Dictionary = Data.table("entry_laws")
	var danger := 1.0
	for c: Variant in party:
		if is_monster(c):
			danger += 0.3 * float((c as Dictionary).get("power", 1)) * 0.2
	return int(round(float(T.get("bribe_base", 20)) * (0.3 + 0.7 * clampf(float(town.get("corruption", 0.3)), 0.0, 1.0)) * danger))


static func check(party: Array, town: Dictionary, status_value: float, ctx: Dictionary = {}) -> Dictionary:
	var T: Dictionary = Data.table("entry_laws")
	var law := law_of(town)
	var kind := String(law.get("law", "registry"))
	var hour := int(ctx.get("hour", 12))
	var out := {"verdict": "admit", "law": kind, "terms": [], "reasons": [], "required": 0.0, "status": status_value, "options": [],
		"bribe_price": 0, "lines": [], "fee": 0, "blockers": []}
	var mons: Array = []
	for c: Variant in party:
		if is_monster(c):
			mons.append(c)
	if mons.is_empty():
		out["lines"].append("Pass, traveller.")
		return out
	# Forbidden kinds are never admitted (data flag: undead naming forbidden, sealed servants only).
	var worst := "admit"
	var blockers: Array = []
	var req_max := 0.0
	var seal := _has_permit(ctx, "church_seal", mons, ctx) or bool(ctx.get("seal", false))
	var charter := _has_permit(ctx, "charter", mons, ctx)
	for c: Dictionary in mons:
		var req := required_status(c, law)
		req_max = maxf(req_max, req)
		var v := "admit"
		match kind:
			"open":
				v = "admit" if String(c.get("kind", "")) != "undead" else "bar"
			"ban":
				v = "admit_with_terms" if String(c.get("kind", "")) == "beast" and not bool(c.get("named", false)) else "bar"
			"quarantine":
				v = "turn_back" if bool(c.get("named", false)) else "admit_with_terms"
			"blessing":
				v = "admit_with_terms" if (seal or status_value >= req) else "turn_back"
			"escort":
				v = "admit_with_terms" if (status_value >= maxf(req, 0.5) or float(ctx.get("sponsor_status", 0.0)) >= 0.55) else "turn_back"
			"reserve":
				v = "admit_with_terms" if status_value >= req else "turn_back"
			_:
				v = "admit_with_terms" if status_value >= req or charter else "turn_back"
		if String(c.get("kind", "")) == "undead" and Data.flag("undead_naming_forbidden"):
			v = "bar"
		if int(VERDICT_RANK[v]) > int(VERDICT_RANK[worst]):
			worst = v
		if v in ["turn_back", "bar"]:
			blockers.append(c)
	if charter and worst == "turn_back" and kind in ["registry", "escort", "reserve"]:
		worst = "admit_with_terms"
		blockers = []
		out["reasons"].append("Your charter is recognised here.")
	out["required"] = req_max
	out["blockers"] = blockers
	# Terms.
	var terms: Array = []
	if worst == "admit_with_terms" or worst == "admit":
		match kind:
			"registry":
				terms.append("register")
				terms.append("collar_tag")
				out["fee"] = int(law.get("fee", 0)) * mons.size()
			"escort":
				terms.append("handler")
			"blessing":
				terms.append("seal_inspected")
				out["fee"] = int(law.get("fee", 0)) * mons.size()
			"reserve":
				terms.append("monster_quarter_only")
			"ban":
				terms.append("pen")
		for c: Dictionary in mons:
			if String(c.get("kind", "")) in ["beast", "tame_beast"] and kind in ["registry", "blessing"] and "muzzle" not in terms:
				terms.append("muzzle")
	if worst == "admit" and not terms.is_empty():
		worst = "admit_with_terms"
	# Curfew: strict towns bar monsters after dusk even with a permit.
	if bool(law.get("strict_curfew", false)) and is_dusk(hour, T) and kind != "open":
		worst = "bar"
		out["reasons"].append("No beast in the street after the bell.")
		terms.clear()
		out["fee"] = 0
	out["verdict"] = worst
	out["terms"] = terms
	if worst in ["turn_back", "bar"]:
		out["options"] = options_for(party, town, blockers, law, status_value, ctx, worst == "bar")
		out["bribe_price"] = bribe_price(party, town) * (2 if worst == "bar" else 1)
		out["reasons"].append("Status %.2f, needs %.2f." % [status_value, req_max])
	out["lines"] = gate_lines(out, town, mons)
	return out


static func _has_permit(ctx: Dictionary, kind: String, mons: Array, c2: Dictionary) -> bool:
	for p: Variant in ctx.get("permits", []):
		var pd: Dictionary = p
		if String(pd.get("kind", "")) != kind or bool(pd.get("forged", false)):
			continue
		var ok := true
		for m: Dictionary in mons:
			if not _valid_permit(pd, m, int(c2.get("day", 0))):
				ok = false
		if ok and int(pd.get("heads", 99)) >= mons.size():
			return true
	return false


static func options_for(party: Array, town: Dictionary, blockers: Array, law: Dictionary, status_value: float, ctx: Dictionary, barred: bool) -> Array:
	var T: Dictionary = Data.table("entry_laws")
	var ops: Array = [{"id": "leave_outside", "text": "Leave them at the gate camp.", "loyalty_per_day": -1}]
	var speech := 0
	for c: Dictionary in blockers:
		speech = maxi(speech, int(c.get("speech", 0)))
	ops.append({"id": "bribe", "text": "Slip the guard a bribe.", "price": bribe_price(party, town) * (2 if barred else 1)})
	if not barred:
		ops.append({"id": "sponsor", "text": "Find a sponsor of standing %.2f." % (float(law.get("floor", {}).get("default", 0.25)) + 0.3), "needs": 0.55})
		ops.append({"id": "permit", "text": "Show a permit (charter, seal or letter).", "prices": T.get("permit_price", {})})
		if String(law.get("culture", "")) == "solenne":
			var cr: Dictionary = T.get("cleansing_rite", {})
			ops.append({"id": "cleansing", "text": "Undergo a cleansing rite.", "days": int(cr.get("days", 3)), "gold": int(cr.get("days", 3)) * int(cr.get("gold_per_day", 3)),
				"status_bonus": float(cr.get("status_bonus", 0.1))})
	var all_deft := true
	for c: Dictionary in blockers:
		if int(c.get("form", 0)) < 3:
			all_deft = false
	if all_deft and not blockers.is_empty():
		ops.append({"id": "disguise", "text": "Dress them as servants."})
	if speech >= 2:
		ops.append({"id": "talk", "text": "Let it argue its own case.", "chance": talk_chance(speech)})
	return ops


static func talk_chance(speech: int) -> float:
	return clampf(0.15 + 0.1 * float(speech), 0.0, 0.9)


## Applies one option. Returns {ok, result, verdict, loyalty_delta, infamy_delta, gold, arrest, lines}.
static func apply_option(party: Array, town: Dictionary, opt: String, status_value: float, ctx: Dictionary = {}) -> Dictionary:
	var res := {"ok": false, "result": "", "verdict": "turn_back", "loyalty_delta": 0, "infamy_delta": 0.0, "gold": 0, "arrest": false, "lines": [], "evidence": false}
	var base := check(party, town, status_value, ctx)
	if base["verdict"] in ["admit", "admit_with_terms"]:
		res["ok"] = true
		res["verdict"] = base["verdict"]
		res["result"] = "no_need"
		return res
	var barred: bool = String(base["verdict"]) == "bar"
	match opt:
		"leave_outside":
			res["ok"] = true
			res["result"] = "left_outside"
			res["verdict"] = "admit"
			res["loyalty_delta"] = -1
			res["lines"].append("They wait at the gate camp.")
		"bribe":
			var price := int(base["bribe_price"])
			res["gold"] = -price
			var caught := roll(ctx, town, party, "bribe_witness") < 0.25 + 0.2 * (1.0 - clampf(float(town.get("corruption", 0.3)), 0.0, 1.0))
			res["ok"] = true
			res["result"] = "bribed"
			res["verdict"] = "admit_with_terms"
			res["infamy_delta"] = 2.0
			res["evidence"] = caught
			res["lines"].append("The guard looks the other way." + (" A witness saw the coin." if caught else ""))
		"sponsor":
			if barred:
				res["result"] = "sponsor_refused"
			elif float(ctx.get("sponsor_status", 0.0)) >= maxf(0.55, float(base["required"])):
				res["ok"] = true
				res["result"] = "sponsored"
				res["verdict"] = "admit_with_terms"
				res["lines"].append("A sponsor vouches for you at the gate.")
			else:
				res["result"] = "sponsor_too_low"
		"permit":
			var good := false
			for p: Variant in ctx.get("permits", []):
				var pd: Dictionary = p
				if bool(pd.get("forged", false)):
					if roll(ctx, town, party, "forged") < 0.55:
						res["arrest"] = true
						res["result"] = "forged_permit_caught"
						res["infamy_delta"] = 8.0
						res["lines"].append("The seal is wrong. Guards!")
						return res
					good = true
				elif int(pd.get("expires", 1 << 30)) >= int(ctx.get("day", 0)):
					good = true
			res["ok"] = good and not barred
			res["result"] = "permit_accepted" if res["ok"] else "no_permit"
			if res["ok"]:
				res["verdict"] = "admit_with_terms"
		"cleansing":
			res["ok"] = not barred and String(base["law"]) == "blessing"
			res["result"] = "cleansed" if res["ok"] else "not_offered"
			if res["ok"]:
				res["verdict"] = "admit_with_terms"
				res["gold"] = -int(Data.table("entry_laws").get("cleansing_rite", {}).get("days", 3)) * int(Data.table("entry_laws").get("cleansing_rite", {}).get("gold_per_day", 3))
		"disguise":
			var q := clampf(float(ctx.get("quality", 0.5)), 0.0, 1.0)
			var guard: Dictionary = (ctx.get("guard", {"perception": 0.4}) as Dictionary).duplicate()
			guard["id"] = "guard"
			if is_dusk(int(ctx.get("hour", 12)), Data.table("entry_laws")):
				guard["perception"] = float(guard.get("perception", 0.4)) * 0.8
			var subject := {"id": "disguised_monster", "disguise": {"quality": q, "identity": {"id": "servant", "title_rank": 0, "gear_value": 0.2}}}
			var sp := SP.new()
			sp.seed_value = int(ctx.get("seed", 1))
			var idn := sp.identity(guard, subject, {"day": int(ctx.get("day", 0)) + party_hash(party)})
			if bool(idn["exposed"]):
				res["result"] = "disguise_failed"
				res["arrest"] = true
				res["infamy_delta"] = 4.0
				res["lines"].append("The muzzle slips. The guard checks the papers.")
			else:
				res["ok"] = true
				res["result"] = "disguise_passed"
				res["verdict"] = "admit_with_terms"
				res["lines"].append("Nobody looks twice at the porter.")
		"talk":
			var sp2 := 0
			for c: Dictionary in base["blockers"]:
				sp2 = maxi(sp2, int(c.get("speech", 0)))
			if sp2 >= 2 and not barred and roll(ctx, town, party, "talk") < talk_chance(sp2):
				res["ok"] = true
				res["result"] = "argued_in"
				res["verdict"] = "admit_with_terms"
				res["lines"].append("The guard hears it out, and nods.")
			else:
				res["result"] = "talk_failed"
		_:
			res["result"] = "unknown_option"
	return res


## One plain sentence per town for the recruit screen (4.3): "Wolfhaven would admit you, with a muzzle on it."
static func forecast(party: Array, towns: Array, status_by_sid: Dictionary, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	for t: Variant in towns:
		var town: Dictionary = t
		var sv := float(status_by_sid.get(int(town.get("sid", 0)), status_by_sid.get("default", 0.3)))
		var r := check(party, town, sv, ctx)
		var nm := String(town.get("name", "The town"))
		var line := ""
		match r["verdict"]:
			"admit":
				line = "%s would admit you." % nm
			"admit_with_terms":
				var tw: Array = r["terms"]
				line = "%s would admit you%s." % [nm, (", with a %s on it" % String(tw[tw.find("muzzle")]) if "muzzle" in tw else (", on terms" if not tw.is_empty() else ""))]
			"turn_back":
				line = "%s would turn you away." % nm
			_:
				line = "%s would bar the gate to you." % nm
		out.append({"sid": int(town.get("sid", 0)), "verdict": r["verdict"], "cost": int(r["fee"]), "line": line})
	return out


static func gate_lines(r: Dictionary, town: Dictionary, mons: Array) -> Array:
	var cult := String(law_of(town).get("culture", "folk"))
	match String(r["verdict"]):
		"admit":
			return ["Pass."]
		"admit_with_terms":
			return ["Registry is at the red door. Collar is three marks, tags are free."] if cult == "caldric" else ["Pass, on the terms given."]
		"turn_back":
			return ["Unclean. Turn back."] if cult == "solenne" else ["Come back with papers, or a sponsor."]
		_:
			return ["The gate is shut to your company."]
