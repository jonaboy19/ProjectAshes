extends Node
## QA: colour statistics of the VAT crowd bakes (assets/generated/vat/*.res): mean / spread of the baked albedo and the tint mask.
func _ready() -> void:
	for f in ["vat_villager_man_a", "vat_villager_woman_a", "vat_villager_farmer", "vat_elder_man", "vat_child_boy"]:
		var a: Resource = load("res://assets/generated/vat/%s.res" % f)
		var mesh: Mesh = a.get("mesh")
		if mesh == null:
			print("VATCOL %s no mesh" % f)
			continue
		var arr := mesh.surface_get_arrays(0)
		var uvs: Variant = arr[Mesh.ARRAY_TEX_UV]
		print("VATUV %s uv=%s fmt=%d" % [f, "yes %d" % (uvs as PackedVector2Array).size() if uvs != null else "none", mesh.surface_get_format(0)])
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var s := Vector3.ZERO
		var mn := Vector3.ONE
		var mx := Vector3.ZERO
		var amask := 0.0
		for c in cols:
			var v := Vector3(c.r, c.g, c.b)
			s += v
			mn = mn.min(v)
			mx = mx.max(v)
			amask += c.a
		var n := maxf(cols.size(), 1)
		print("VATCOL %s verts=%d mean=%s min=%s max=%s tintmask_mean=%.2f" % [f, cols.size(), s / n, mn, mx, amask / n])
	get_tree().quit(0)
