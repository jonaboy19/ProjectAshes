extends RefCounted
## Base of a town's "special" script (the town file's `special`): the one-off code a town keeps for its own quest set pieces
## (Thornfield's barn figure, grain cart and clue props). The generic kit builds everything else; the hub calls these hooks in
## this order from its _ready / poll, and a special overrides only the ones it needs. One instance per hub.
##
##   build(hub)               after the roster is bound and the quest pump exists, before the threat node is made
##   after_threat(hub)        once hub.threat exists (attach wilds, give the cart its wolves)
##   poll(hub, dt)            every hub poll (0.5 s), after places and the threat were ticked, before the inventory is checked
##   ctx_extra(info)          dialogue keys the town's conversations use (stateless: also called without a hub)
##   prop(name)               a value the hub's `get()` exposes to callers (tests, QA tools): "cart", "figure", ...


func build(_hub: Node) -> void:
	pass


func after_threat(_hub: Node) -> void:
	pass


func poll(_hub: Node, _dt: float) -> void:
	pass


func ctx_extra(_info: Dictionary) -> Dictionary:
	return {}


func prop(_name: String) -> Variant:
	return null
