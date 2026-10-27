extends RefCounted
## Villager bodies inside a modular interior (package F6): a skinned character (the same looks and rigs the street
## villagers use, from PopulationLOD's job looks) with the pose of an indoor act, placed on a layout waypoint. They
## are decoration with identity (meta "person", group "interior_npc"), not brains: the schedule decides who is here
## (scripts/interiors/household.gd), the act decides the clip. Preload this script; no class_name.

const PopLod := preload("res://scripts/population/population_lod.gd")
const LifeLib := preload("res://scripts/living_world/life_library.gd")

const CLIPS := {
	"sleep": ["Life_Rest_Sleep_Ground", "Lie_Down_Idle", "Sitting_Idle"],
	"eat": ["Life_Eat_Bowl_Sit", "Life_Eat_Bread_Stand", "Sitting_Idle"],
	"hearth": ["Life_Rest_Sit_Chair", "Life_Rest_Sit_Bench", "Sitting_Idle"],
	"table": ["Life_Read_Sit", "Life_Rest_Sit_Chair", "Sitting_Idle"],
	"counter": ["Life_Shop_Counter_Lean", "Life_Shop_Tally", "Idle_Subtle", "Idle"],
	"drink": ["Life_Tavern_Sit_Drink", "Life_Rest_Sit_Chair", "Sitting_Idle"],
	"walk": ["Walk", "Life_Walk", "Idle"],
}
## Standing acts (the others sit or lie).
const STANDING := ["counter"]


## Clip names to try for an act on a waypoint (bench seats prefer the bench clips).
static func clips_for(act: String, so := "") -> Array:
	var list: Array = (CLIPS.get(act, ["Idle"]) as Array).duplicate()
	if so == "bench" and (act == "hearth" or act == "table"):
		list.push_front("Life_Rest_Sit_Bench")
	if act == "hearth" and so == "cook_pot":
		list = ["Life_Cook_Stir", "Idle_Subtle", "Idle"]
	return list


static func play(body: Node3D, clips: Array) -> String:
	var ap := Assets.animation_player(body)
	if ap == null:
		return ""
	for c: String in clips:
		if ap.has_animation(c):
			ap.play(c, 0.2)
			return c
	return ""


## Builds the body for `person` (null when no character model loads, e.g. in a bare test).
static func make(person: int) -> Node3D:
	var job := int(WorldSim.job[person]) if person >= 0 and person < WorldSim.job.size() else 4
	var look: String = PopLod.JOB_LOOK[clampi(job, 0, PopLod.JOB_LOOK.size() - 1)]
	var model: Array = PopLod.LOOK_MODEL.get(look, [])
	if model.is_empty():
		return null
	var keep: Array[String] = []
	keep.assign(model[1])
	var body: Node3D = Assets.character(String(model[0]), 1.7, keep)
	if body == null:
		return null
	var ap := Assets.animation_player(body)
	if ap != null:
		LifeLib.install(ap)
	body.name = "Person_%d" % person
	body.set_meta("person", person)
	body.add_to_group("interior_npc")
	return body


## Puts `body` on a waypoint dictionary ({p: Vector3 room-local, y: yaw degrees, so}) of `room` and plays the act.
static func pose(room: Node3D, body: Node3D, act: String, wp: Dictionary) -> void:
	body.set_meta("act", act)
	body.set_meta("in_bed", false)
	if act == "sleep" and String(wp.get("so", "")) == "bed":
		var ap := Assets.animation_player(body)
		if ap != null and ap.has_animation(BED_SLEEP):
			var sx := bed_stand(wp)
			body.position = sx.origin
			body.rotation = Vector3(0.0, sx.basis.get_euler().y, 0.0)
			ap.play(BED_SLEEP, 0.2)
			body.set_meta("in_bed", true)
			return
	body.position = wp["p"]
	body.rotation = Vector3(0.0, deg_to_rad(float(wp["y"])), 0.0)
	play(body, clips_for(act, String(wp.get("so", ""))))


## Bed clips (data/living_world/smart_objects.json type "bed"): the root stays on the floor at the slot, facing +Z;
## the bed centre is BED_BACK m behind it and the head end points along BED_HEAD in slot space.
const BED_SLEEP := "Life_Mz_Sleep_Bed"
const BED_WAKE := "Life_Mz_Wake_Bed"
const BED_BACK := 0.82
const BED_HEAD := Vector2(0.8, 0.6)    # (x, z)


## Slot transform (room-local, floor height) for a bed waypoint {p: bed centre at mattress height, y: yaw deg}.
## The kit bed (modular_interior.gd) has its headboard at local -Z.
static func bed_stand(wp: Dictionary) -> Transform3D:
	var c: Vector3 = wp["p"]
	var floor_y := c.y - 0.42
	var head := Basis(Vector3.UP, deg_to_rad(float(wp.get("y", 0.0)))) * Vector3(0, 0, -1)
	var theta := atan2(head.x, head.z) - atan2(BED_HEAD.x, BED_HEAD.y)
	var b := Basis(Vector3.UP, theta)
	var stand := Vector3(c.x, floor_y, c.z) + b * Vector3(0, 0, BED_BACK)
	return Transform3D(b, stand)
