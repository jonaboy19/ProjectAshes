extends RefCounted
## F10: the Soulbeast save path. Its state lives in the realm followers module as a creature entry (id "soulbeast",
## species wolf), the same pattern as followers.gd taming, so Life.realm.serialize()/deserialize() carry it with no new
## save key. The brain's snapshot rides in the entry's "soulbeast" field; "trust" (0..1) and "status" mirror it for the
## Realm tab and existing taming readers. Preloaded (no class_name).

const ID := "soulbeast"


static func status_for(brain: RefCounted) -> String:
	if brain.bonded:
		return "tamed"
	return "taming" if brain.trust > 0.0 else "wild"


## Writes `brain`'s snapshot into the followers module `fm` (a realm_hub.mod("followers")).
static func store(fm: RefCounted, brain: RefCounted) -> void:
	if fm == null:
		return
	if fm.creature(ID).is_empty():
		fm.start_taming(ID, "wolf")
	var c: Dictionary = fm.creature(ID)
	c["soulbeast"] = brain.to_dict()
	c["name"] = brain.soul_name if brain.soul_name != "" else "soulbeast"
	c["trust"] = clampf(brain.trust / 100.0, 0.0, 1.0)
	c["status"] = status_for(brain)


## Reads the snapshot back into `brain`. False when there is none (a fresh game).
static func load_into(fm: RefCounted, brain: RefCounted) -> bool:
	if fm == null:
		return false
	var c: Dictionary = fm.creature(ID)
	if c.is_empty() or not c.has("soulbeast"):
		return false
	brain.from_dict(c["soulbeast"])
	return true
