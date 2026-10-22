extends GdUnitTestSuite
## MN-0: no vocabulary of the series that inspired the naming mechanic reaches shipped text, and the owner open questions are data flags.

const Terms := preload("res://scripts/sim/lore_terms.gd")
const Data := preload("res://scripts/realm/mn_data.gd")
const SKIP_DIRS := ["addons", ".godot", "tests", "tools_qa", "assets"]


func _files(dir: String, ext: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if sub in SKIP_DIRS or sub.begins_with("."):
			continue
		_files(dir.path_join(sub), ext, out)
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(dir.path_join(f))


func _deny() -> Dictionary:
	return Data.table("lore_denylist")


func _allowed(path: String) -> bool:
	for a: String in _deny().get("allow_files", []):
		if path.ends_with(a):
			return true
	return false


func _is_ident(s: String) -> bool:
	var re := RegEx.new()
	re.compile("^[a-z_0-9]+$")
	return re.search(s) != null


func _walk(o: Variant, path: String, f: String, terms: Array, proper: Array, hits: Array) -> void:
	if o is Dictionary:
		for k in o:
			_walk(o[k], path + "/" + String(k), f, terms, proper, hits)
	elif o is Array:
		for i in (o as Array).size():
			_walk(o[i], path + "/%d" % i, f, terms, proper, hits)
	elif o is String and not _is_ident(o):
		var low := (o as String).to_lower()
		for t: String in terms:
			if low.contains(t):
				hits.append("%s %s: %s" % [f, path, (o as String).substr(0, 60)])
		for p: String in proper:
			var re := RegEx.new()
			re.compile("\\b" + p.to_lower() + "\\b")
			if re.search(low) != null:
				hits.append("%s %s names %s" % [f, path, p])


func test_denylist_file_loads_and_is_not_empty() -> void:
	assert_int((_deny().get("proper_nouns", []) as Array).size()).is_greater(10)
	assert_bool("magicule" in (_deny().get("player_text_terms", []) as Array)).is_true()


func test_no_series_vocabulary_in_data_text() -> void:
	var files: Array = []
	_files("res://data", ".json", files)
	assert_int(files.size()).is_greater(20)
	var hits: Array = []
	var terms: Array = _deny().get("player_text_terms", [])
	var proper: Array = _deny().get("proper_nouns", [])
	for f: String in files:
		if _allowed(f):
			continue
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if j != null:
			_walk(j, "", f, terms, proper, hits)
	assert_array(hits).is_empty()


func test_no_series_vocabulary_in_script_text() -> void:
	var files: Array = []
	_files("res://scripts", ".gd", files)
	_files("res://autoload", ".gd", files)
	assert_int(files.size()).is_greater(100)
	var lit := RegEx.new()
	lit.compile("\"([^\"\\n]*)\"")
	var hits: Array = []
	var proper: Array = _deny().get("proper_nouns", [])
	var terms: Array = _deny().get("player_text_terms", [])
	for f: String in files:
		if _allowed(f):
			continue
		var text := FileAccess.get_file_as_string(f)
		var low := text.to_lower()
		for p: String in proper:
			var re := RegEx.new()
			re.compile("\\b" + p.to_lower() + "\\b")
			if re.search(low) != null:
				hits.append("%s names '%s'" % [f, p])
		for line in text.split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for m in lit.search_all(line):
				var s: String = m.get_string(1)
				if _is_ident(s):
					continue
				for t: String in terms:
					if s.to_lower().contains(t):
						hits.append("%s string '%s'" % [f, s.substr(0, 50)])
	assert_array(hits).is_empty()


func test_aliases_keep_old_keys_working() -> void:
	assert_str(Terms.canonical("soul_reserve")).is_equal("magicules")
	assert_str(Terms.canonical("ember_regen")).is_equal("magicule_regen")
	assert_str(Terms.canonical("magicules")).is_equal("magicules")
	assert_str(Terms.canonical("no_such_key")).is_equal("no_such_key")
	assert_str(Terms.display("magicules")).is_equal("soul reserve")
	assert_str(Terms.display("embers")).is_equal("soul reserve")
	# Old saves still load: the pool keeps its internal keys.
	var p := RAMagicules.new(50.0, 2.0, 3)
	var d := p.serialize()
	assert_bool(d.has("max") and d.has("regen")).is_true()
	var q := RAMagicules.new()
	q.deserialize(d)
	assert_float(q.max_pool).is_equal(50.0)


func test_player_text_says_soul_reserve() -> void:
	var p := RAMagicules.new(10.0, 1.0, 1)
	var r := p.spend(999.0)
	assert_bool(String(r["text"]).to_lower().contains("magicule")).is_false()
	var s := RANaming.new()
	assert_str(RANaming.evolution_hint("slime")).not_contains("absorb")
	assert_str(RANaming.evolution_hint("slime")).contains("filter")
	var pv := s.preview(p, 3, "goblin", 5)
	assert_bool(pv["possible"]).is_false()


func test_owner_open_questions_are_data_flags_with_conservative_defaults() -> void:
	assert_bool(bool(Data.flag("undead_naming_forbidden"))).is_true()
	assert_str(String(Data.flag("intermarriage"))).is_equal("story_only")
	assert_bool(bool(Data.flag("monsters_can_vote"))).is_false()
	assert_str(String(Data.flag("dragonkin_mode"))).is_equal("late_lizardfolk_form")
	assert_bool(bool(Data.flag("dragonkin_recruitable"))).is_false()
	var undead: Dictionary = Data.species_row("undead")
	assert_bool(bool(undead.get("forbidden", false))).is_true()
