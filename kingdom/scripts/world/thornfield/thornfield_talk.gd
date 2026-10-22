extends RefCounted
## Talk-menu side of the Thornfield quests: the town kit's talk helpers (scripts/world/town_kit/town_talk.gd, which
## VillageServices calls for every town) plus Thornfield's own dialogue keys (Wilm's confession and bribe nodes, which live in
## special.gd). Kept so the Thornfield tests and QA tools keep their call shapes.

const KitTalk := preload("res://scripts/world/town_kit/town_talk.gd")
const Special := preload("res://scripts/world/thornfield/special.gd")
const CULPRIT := "thornfield_the_culprit"


static func keys_of(info: Dictionary) -> Array[String]:
	return KitTalk.keys_of(info)


static func ctx_extra(info: Dictionary) -> Dictionary:
	return Special.new().ctx_extra(info)


static func on_node(info: Dictionary, node: String) -> void:
	KitTalk.on_node(info, node)


static func pending_deliveries(r: QuestRunner, info: Dictionary) -> Array:
	return KitTalk.pending_deliveries(r, info)


static func add_options(opts: Array, info: Dictionary) -> void:
	KitTalk.add_options(opts, info)


static func hand_over(info: Dictionary, item: String, n: int) -> String:
	return KitTalk.hand_over(info, item, n)
