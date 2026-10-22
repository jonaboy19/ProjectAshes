extends RefCounted
## Headless (dummy renderer) MultiMeshes forget every instance transform the moment it is set, so the linter could not see
## where any scatter, cliff rock or settlement building stands. lint_core.gd rewrites `X.set_instance_transform(` in the
## builder scripts (in memory only, restored after the run) to call rec(), which keeps a copy on the MultiMesh itself
## (meta "lint_xf": Array of Transform3D, null where never set) and then does the normal call.


static func rec(mm: MultiMesh, i: int, t: Transform3D) -> void:
	var arr: Array
	if mm.has_meta("lint_xf"):
		arr = mm.get_meta("lint_xf")
	else:
		arr = []
		arr.resize(mm.instance_count)
		mm.set_meta("lint_xf", arr)
	if i >= arr.size():
		arr.resize(i + 1)
	arr[i] = t
	mm.set_instance_transform(i, t)


static func rec_col(mm: MultiMesh, i: int, c: Color) -> void:
	var arr: Array
	if mm.has_meta("lint_col"):
		arr = mm.get_meta("lint_col")
	else:
		arr = []
		arr.resize(mm.instance_count)
		mm.set_meta("lint_col", arr)
	if i >= arr.size():
		arr.resize(i + 1)
	arr[i] = c
	mm.set_instance_color(i, c)
