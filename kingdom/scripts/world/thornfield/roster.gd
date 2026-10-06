extends RefCounted
## Thornfield's roster, as the town kit sees it: a thin facade over scripts/world/town_kit/town_roster.gd bound to the town
## "thornfield" (data/region1/towns/thornfield.json). It keeps the call shapes the Thornfield tests and QA tools were written
## against; the game's own hooks (WorldSim, PopulationLOD, the interiors, VillageServices) call the kit directly.
## Preload this script (no class_name); every function is static.

const TID := "thornfield"
const TOWN := "Thornfield"
const KitRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const KitData := preload("res://scripts/world/town_kit/town_data.gd")
const KEEPER_ROLES := KitRoster.KEEPER_ROLES


static func data() -> Dictionary:
	return KitData.town(TID)


static func residents() -> Array:
	return KitData.residents(TID)


static func entry(id: String) -> Dictionary:
	return KitRoster.entry(id)


static func clear() -> void:
	KitRoster.clear()


static func settlement_id() -> int:
	return KitRoster.settlement_id(TID)


static func is_bound() -> bool:
	return KitRoster.is_bound(TID)


## Binds Thornfield's residents to WorldSim rows. Returns {id: row}.
static func bind(force := false) -> Dictionary:
	return KitRoster.bind(TID, force)


static func row_of(id: String) -> int:
	return KitRoster.row_of(id)


static func id_of(row: int) -> String:
	return KitRoster.id_of(row)


static func is_named(row: int) -> bool:
	return KitRoster.is_named(row)


static func bound_rows() -> Array:
	return KitRoster.bound_rows()


static func name_of(row: int) -> String:
	return KitRoster.name_of(row)


static func info_for(row: int) -> Dictionary:
	return KitRoster.info_for(row)


static func info_for_id(id: String) -> Dictionary:
	return KitRoster.info_for_id(id)


static func rows_at(sid: int, lot: int, which: int) -> Array[int]:
	return KitRoster.rows_at(sid, lot, which)


static func relationship(a: String, b: String) -> Dictionary:
	return KitRoster.relationship(a, b)


static func seed_social_graph(graph: Variant, seed_value: int) -> int:
	return KitRoster.seed_social_graph(graph, seed_value, TID)


static func override_phase(row: int, h: float, base: int) -> int:
	return KitRoster.override_phase(row, h, base)


static func spot(row: int, which: int) -> Vector2:
	return KitRoster.spot(row, which)


static func embody_weight(row: int) -> float:
	return KitRoster.embody_weight(row)


static func on_died(row: int) -> void:
	KitRoster.on_died(row)


static func keeper_of(bid: String) -> Dictionary:
	return KitRoster.keeper_of(bid)


static func look_of(e: Dictionary) -> String:
	return KitRoster.look_of(e)


static func building_name(bid: String) -> String:
	return KitRoster.building_name(bid)
