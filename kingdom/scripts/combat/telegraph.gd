extends RefCounted
## One call site for enemy attack telegraphs: a ground ring under heavy attacks and charged casts
## (vfx/telegraph_rings.gd) and the red strike highlight (enemy_highlight.gd). Bodies (monster, wolf, soldier)
## call begin() at windup start; both effects expire on their own when the windup ends, end() cancels early.
## The nameplate "!" cue stays with the bodies. Static helpers only, no scene state of their own.

const Feel := preload("res://scripts/combat/combat_feel.gd")
const Rings := preload("res://scripts/vfx/telegraph_rings.gd")
const Highlight := preload("res://scripts/combat/enemy_highlight.gd")


## `move` is the CombatAction being swung (or null); `heavy_default` decides when there is no move row.
## The strike highlight always shows; the ring only for heavy attacks.
static func begin(actor: Node3D, move: Resource, reach: float, windup: float, heavy_default := false) -> void:
	if actor == null or not actor.is_inside_tree() or actor.get_parent() == null:
		return
	var world := actor.get_parent()
	Highlight.at(world).strike(actor, windup)
	var heavy := Feel.is_heavy_move(move) if move != null else heavy_default
	if heavy:
		Rings.at(world).begin(actor, maxf(reach, 1.2), windup, "", true)


## Charged cast (chant or windup): ring in the ability's element palette, scaled to its radius or range.
static func begin_cast(actor: Node3D, element: String, radius: float, seconds: float) -> void:
	if actor == null or not actor.is_inside_tree() or actor.get_parent() == null:
		return
	var world := actor.get_parent()
	Highlight.at(world).strike(actor, seconds)
	Rings.at(world).begin(actor, clampf(radius, 1.2, 6.0), seconds, element, true)


static func end(actor: Node3D) -> void:
	if actor == null or not actor.is_inside_tree() or actor.get_parent() == null:
		return
	var world := actor.get_parent()
	var r := world.get_node_or_null(Rings.NODE_NAME)
	if r:
		r.end(actor)
	var h := world.get_node_or_null(Highlight.NODE_NAME)
	if h:
		h.clear(actor)
