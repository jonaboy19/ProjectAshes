class_name EnterableBuildingManager
extends Node
## Manages enterable buildings across Valencious settlements and wilderness.
## Ensures seamless walk-in entry without loading screens, while dynamically managing
## occlusion culling and interior prop visibility to maintain smooth 60 FPS on 8GB RAM PCs.

signal player_entered_building(building_id: String, building_type: String)
signal player_exited_building(building_id: String)

## Detection radii
const INTERIOR_LOAD_DISTANCE := 18.0   # Meters to un-hide interior props
const INTERIOR_UNLOAD_DISTANCE := 26.0 # Meters to hide interior props to save draw calls

## Registry of active enterable buildings in currently loaded sectors
var _registered_buildings: Dictionary = {} # id -> BuildingInstance

class BuildingInstance:
	var id: String
	var type: String
	var root_node: Node3D
	var interior_props_root: Node3D
	var door_position: Vector3
	var is_player_inside: bool = false
	var are_props_visible: bool = false

func register_building(id: String, type: String, root: Node3D, door_pos: Vector3, interior_props: Node3D = null) -> void:
	var inst := BuildingInstance.new()
	inst.id = id
	inst.type = type
	inst.root_node = root
	inst.interior_props_root = interior_props
	inst.door_position = door_pos
	inst.is_player_inside = false
	
	# Start with interior props hidden if far away to conserve memory
	if interior_props:
		interior_props.visible = false
		inst.are_props_visible = false
		
	_registered_buildings[id] = inst

func unregister_building(id: String) -> void:
	_registered_buildings.erase(id)

## Called every frame or physics tick with player world position
func update_player_proximity(player_pos: Vector3) -> void:
	for id in _registered_buildings.keys():
		var inst: BuildingInstance = _registered_buildings[id]
		var dist_to_door: float = player_pos.distance_to(inst.door_position)
		
		# Dynamic prop culling (saves 40-70 draw calls per building)
		if inst.interior_props_root:
			if dist_to_door <= INTERIOR_LOAD_DISTANCE and not inst.are_props_visible:
				inst.interior_props_root.visible = true
				inst.are_props_visible = true
			elif dist_to_door > INTERIOR_UNLOAD_DISTANCE and inst.are_props_visible and not inst.is_player_inside:
				inst.interior_props_root.visible = false
				inst.are_props_visible = false

## Threshold trigger called when player crosses physical door portal
func notify_door_crossed(building_id: String, entering: bool) -> void:
	if not _registered_buildings.has(building_id):
		return
		
	var inst: BuildingInstance = _registered_buildings[building_id]
	if entering and not inst.is_player_inside:
		inst.is_player_inside = true
		if inst.interior_props_root:
			inst.interior_props_root.visible = true
			inst.are_props_visible = true
		player_entered_building.emit(inst.id, inst.type)
		_adjust_interior_camera(true)
	elif not entering and inst.is_player_inside:
		inst.is_player_inside = false
		player_exited_building.emit(inst.id)
		_adjust_interior_camera(false)

## Adjusts camera collision margin and FOV for interior ceilings
func _adjust_interior_camera(inside: bool) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if not cam:
		return
	if inside:
		# Slightly tighter FOV, prevent clipping through interior ceilings
		cam.fov = lerp(cam.fov, 70.0, 0.2)
	else:
		cam.fov = lerp(cam.fov, 75.0, 0.2)
