extends RefCounted
## Settlement ledger model (READY_V1 C4 view): the player's foundings as plain rows for the Realm > Land tab.
## Pure: reads a founding module (realm/founding.gd) and returns dictionaries, so it is unit-testable headless.
##   rows(founding) -> [{fid, name, scale, next_scale, pop, pop_need, services, services_need, infra, infra_need,
##                       progress, stage_words, blockers, problems, escalation_words, land_words, actions}]
## actions: ["petition"] at the recognition stage with no petition filed, ["appoint"] at the government stage.

const Founding := preload("res://scripts/realm/founding.gd")


static func rows(founding: Object) -> Array:
	var out: Array = []
	if founding == null:
		return out
	for fid: int in founding.call("ids", true):
		var f: Dictionary = founding.call("get_founding", fid)
		if String(f.get("who", "")) != "player":
			continue
		var i: Dictionary = founding.call("info", fid)
		out.append(row_from_info(fid, i, int(f.get("sc", 0)), int(f.get("st", 0)), not (f.get("pet", {}) as Dictionary).is_empty()))
	return out


## One row from founding.info(); `sc` = scale index, `st` = stage index.
static func row_from_info(fid: int, i: Dictionary, sc: int, st: int, petition_filed: bool) -> Dictionary:
	var facts: Dictionary = i.get("facts", {})
	var nxt := mini(sc + 1, Founding.SCALES.size() - 1)
	var pop := int(facts.get("pop", 0))
	var sv := int(facts.get("services", 0))
	var inf := int(facts.get("infra", 0))
	var need_pop := int(Founding.SCALE_POP[nxt])
	var need_sv := int(Founding.SCALE_SERVICES[nxt])
	var need_inf := int(Founding.SCALE_INFRA[nxt])
	var parts: Array[float] = [ratio(pop, need_pop), ratio(sv, need_sv), ratio(inf, need_inf)]
	var actions: Array = []
	if st == 7 and not petition_filed:
		actions.append("petition")
	if st == 6:
		actions.append("appoint")
	var probs: Array = []
	for p: Dictionary in i.get("problems", []):
		probs.append(String(p.get("words", p.get("kind", ""))))
	return {"fid": fid, "name": String(i.get("name", "")), "scale": String(i.get("scale", "camp")),
		"next_scale": String(Founding.SCALES[nxt]) if nxt != sc else "", "pop": pop, "pop_need": need_pop,
		"services": sv, "services_need": need_sv, "infra": inf, "infra_need": need_inf,
		"progress": minf(minf(parts[0], parts[1]), parts[2]) if nxt != sc else 1.0,
		"stage_words": String(i.get("stage_words", "")), "blockers": i.get("next", []), "problems": probs,
		"escalation_words": String(i.get("escalation_words", "")), "land_words": String(i.get("land_words", "")),
		"service_list": i.get("services", []), "actions": actions}


static func ratio(have: int, need: int) -> float:
	return 1.0 if need <= 0 else clampf(float(have) / float(need), 0.0, 1.0)
