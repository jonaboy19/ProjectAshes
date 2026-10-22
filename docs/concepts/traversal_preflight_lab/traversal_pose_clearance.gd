extends RefCounted
## Offline/lab pose-volume check. Torso alone does not establish whole-body safety.
## Radius must come from the actual character/outfit envelope, not tuning to pass.
func torso_query(sample: Dictionary, radius: float) -> PhysicsShapeQueryParameters3D:
	return segment_query(sample, "pelvis", "neck_01", radius)

func segment_query(sample: Dictionary, start_bone: String, end_bone: String, radius: float) -> PhysicsShapeQueryParameters3D:
	if not is_finite(radius) or radius <= 0.0:
		return null
	var bones: Dictionary = sample.get("body_points", {})
	if not bones.has(start_bone) or not bones.has(end_bone):
		return null
	for name: String in [start_bone, end_bone]:
		var point: Variant = bones[name]
		if not point is Array or point.size() != 3:
			return null
		for component: Variant in point:
			if not (component is float or component is int):
				return null
	var a := Vector3(bones[start_bone][0], bones[start_bone][1], bones[start_bone][2])
	var b := Vector3(bones[end_bone][0], bones[end_bone][1], bones[end_bone][2])
	if not a.is_finite() or not b.is_finite() or a.distance_to(b) < 0.001:
		return null
	var axis := (b - a).normalized()
	var tangent := axis.cross(Vector3.FORWARD)
	if tangent.length_squared() < 0.001:
		tangent = axis.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var basis := Basis(tangent, axis, tangent.cross(axis)).orthonormalized()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = a.distance_to(b) + radius * 2.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(basis, (a + b) * 0.5)
	return query
