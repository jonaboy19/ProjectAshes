class_name VatAsset
extends Resource
## One baked Vertex Animation Texture character (tools_qa/living_world/vat_bake.gd).
##
## mesh:     a reduced, single-surface copy of the character (vertex colours = albedo, linear;
##           alpha = material mask: 0 skin, 0.5 hair, 1 clothing). UV2.x = the vertex's column
##           in the textures (an exact integer stored as float).
## pos_tex:  RGBA half floats, one row per baked frame, one column per vertex: the skinned
##           position in the model's own space (the node that Assets.mh_character scales).
## nrm_tex:  RGBA8, same layout, normal * 0.5 + 0.5.
## clips:    name -> {"row": first row, "frames": n, "loop": bool, "length": seconds}
## fps:      frames per second of the bake (rows are evenly spaced in time; a loop clip's
##           n rows cover exactly its length, so row n wraps to row 0 seamlessly).

@export var look := ""
@export var mesh: ArrayMesh
@export var pos_tex: ImageTexture
@export var nrm_tex: ImageTexture
@export var clips: Dictionary = {}
@export var fps := 10.0
@export var vertex_count := 0
@export var frame_count := 0
@export var height := 1.75          # natural standing height of the baked model, metres
@export var source := ""


func has_clip(clip: String) -> bool:
	return clips.has(clip)


## Per-instance custom data for VatCrowd: (row, signed frames, phase seconds, speed).
## Negative frames = a one-shot that holds its last frame.
func custom_for(clip: String, phase_s: float, speed := 1.0) -> Color:
	var c: Dictionary = clips.get(clip, clips.get("Idle", {}))
	if c.is_empty():
		return Color(0, 1, 0, 0)
	var n := float(c["frames"])
	return Color(float(c["row"]), n if c["loop"] else -n, phase_s, speed)


func clip_length(clip: String) -> float:
	var c: Dictionary = clips.get(clip, {})
	return float(c.get("length", 1.0))
