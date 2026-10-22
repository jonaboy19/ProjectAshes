extends GPUParticles3D
## A GPUParticles3D shell that vfx_kit.gd's emit() takes from a NodePool instead of allocating one per effect
## (emit() rewrites every property it uses, so a recycled shell is indistinguishable from a new one).
## `gen` increments on every release so a stale free_after() timer from an earlier use cannot cut a later one short.

var gen := 0


func on_acquire() -> void:
	pass


func on_release() -> void:
	emitting = false


func reset() -> void:
	gen += 1
	emitting = false
	process_material = null
	draw_pass_1 = null
	visible = true
	transform = Transform3D.IDENTITY
	one_shot = false
	explosiveness = 0.0
