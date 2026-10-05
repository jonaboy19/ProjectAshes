extends RefCounted
## Reading path manuals (items `pm_*`, data/items/misc.json type manual with power_manual): pure rules over the
## power_paths and cultivation modules so tests run without Life. Manuals written in old script (dungeon and tower
## finds) need glyphs: the reader must know `old_script` glyphs (Scribe: study the glyph tables, translate), or hand the
## book to a bookseller-scribe (translate_old_script service).

const PowerTrees := preload("res://scripts/abilities/power_trees.gd")


## -> {ok, text}. `ctx.glyphs` = old-script glyphs known. A refused read never spends or removes the book.
static func read_manual(pp: Object, cult: Object, manual_id: String, info: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	if manual_id == "":
		return {"ok": false, "text": "The pages mean nothing to you."}
	var need := int(info.get("old_script", 0))
	if need > 0 and int(ctx.get("glyphs", 0)) < need:
		return {"ok": false, "text": "Written in old script: you know %d of the %d glyphs it needs. A scribe could translate it." % [int(ctx.get("glyphs", 0)), need]}
	var pm := PowerTrees.manual(manual_id)
	var path := String(pm.get("path", info.get("power_path", "")))
	if pm.is_empty():
		# One of cultivation.json's manuals (m_mg1 ...).
		if cult == null:
			return {"ok": false, "text": "You are not cultivating."}
		var r: Dictionary = cult.call("learn_manual", manual_id)
		if bool(r.get("ok", false)):
			return {"ok": true, "text": "You study the manual and it settles into your practice."}
		return {"ok": false, "text": _why(String(r.get("reason", "")), path)}
	if pp == null or not bool(pp.call("knows", path)):
		return {"ok": false, "text": "You walk no %s path: the lessons slide off you." % PowerTrees.path_name(path).to_lower()}
	var realms := {}
	if cult != null and bool(cult.call("has_path", path)):
		realms[path] = int(cult.call("realm_of", path))
	var res: Dictionary = pp.call("learn_manual", manual_id, {"realms": realms})
	if not bool(res.get("ok", false)):
		return {"ok": false, "text": _why(String(res.get("reason", "")), path)}
	if pm.has("milestone"):
		pp.call("add_milestone", path, String(pm["milestone"]))        # a text that teaches no form, only a state
	if cult != null:
		cult.call("add_insight", 1.0, "lore", "manual_" + manual_id)
	var names: Array = []
	for t: Variant in pm.get("techniques", []):
		names.append(String(PowerTrees.technique(String(t)).get("name", t)))
	return {"ok": true, "text": "You study %s.%s" % [String(pm.get("name", manual_id)), " (%s)" % ", ".join(PackedStringArray(names)) if not names.is_empty() else ""]}


static func _why(reason: String, path: String) -> String:
	match reason:
		"known":
			return "You already know this manual by heart."
		"too_advanced":
			return "Too advanced: you need to be nearer the realm it is written for."
		"not_cultivating":
			return "You are not cultivating the %s path." % path
		"unknown":
			return "The pages mean nothing to you."
	return "You cannot make sense of it yet."
