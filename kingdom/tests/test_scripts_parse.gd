extends GdUnitTestSuite
## Every game script must parse and compile. Scenes only load some scripts at
## runtime, so without this a typo in e.g. SettlementBuilder slips past tests.


func _scripts(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)


func test_all_game_scripts_compile() -> void:
	var files: Array[String] = []
	_scripts("res://scripts", files)
	_scripts("res://autoload", files)
	var broken: Array[String] = []
	for f in files:
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate():
			broken.append(f)
	assert_array(broken).is_empty()
	assert_int(files.size()).is_greater(30)
