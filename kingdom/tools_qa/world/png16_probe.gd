extends SceneTree
func _initialize() -> void:
	var path := "res://data/world/macro/height_16.png"
	print("exists ", FileAccess.file_exists(path))
	var f := FileAccess.get_file_as_bytes(path)
	print("size ", f.size())
	var t0 := Time.get_ticks_msec()
	var r := WorldMacro._decode16(path)
	print("decoded ", r.size(), " ms ", Time.get_ticks_msec() - t0)
	quit(0)
