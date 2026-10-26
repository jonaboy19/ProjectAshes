extends RefCounted
## Schools and academies for the Realm > Masters tab (realm/education.gd): adult entry routes (exam, military entry,
## tournament, sponsorship, private teacher; the childhood scout test stays where it was), and once enrolled the path
## teachers you can study under. Pure: turns the education module into rows.

const ROUTE_WORDS := {"exam": "Sit the entrance exam (10 gold)", "military_entry": "Enlist as a cadet (16+)",
	"tournament": "Enter as a tournament champion", "sponsorship": "Enter with your sponsor", "private_teacher": "Enter on your tutor's word",
	"scout": "Take the place the scout offered"}


## [{id, name, label, path, town, dist, routes: [{route, words}], blocked: [reason]}], nearest first.
static func schools(edu: Object, from: Vector2, limit := 8) -> Array:
	var out: Array = []
	if edu == null:
		return out
	var kinds: Dictionary = (edu.get_script() as Script).get_script_constant_map().get("KINDS", {})
	for inst: Dictionary in edu.call("institutions"):
		var def: Dictionary = kinds.get(String(inst["kind"]), {})
		var sid := int(inst["sid"])
		var town := ""
		var dist := 1e9
		for s: Dictionary in WorldGen.settlements:
			if int(s["id"]) == sid:
				town = String(s.get("name", ""))
				dist = from.distance_to(s["pos"])
		var routes: Array = []
		var blocked: Array = []
		for o: Dictionary in edu.call("admission_options", String(inst["id"])):
			if bool(o["available"]):
				routes.append({"route": String(o["route"]), "words": String(ROUTE_WORDS.get(String(o["route"]), String(o["route"])))})
			elif String(o["reason"]) != "":
				blocked.append(String(o["reason"]))
		out.append({"id": String(inst["id"]), "name": String(inst["name"]), "label": String(def.get("label", inst["kind"])),
			"path": String(def.get("path", "")), "town": town, "dist": dist, "routes": routes, "blocked": blocked})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	return out.slice(0, limit)
