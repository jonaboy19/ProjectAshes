extends RefCounted
## What the player wears and carries in hand: head, body, hands, feet, main hand,
## off hand and a trinket. Each slot holds {id, quality, durability}. Item stats
## (armour, damage, speed) come from data/items.json and scale with the crafted
## quality (crafting.gd QUALITY_MULT); worn-out gear (durability 0) gives half.
##
## Also holds timed buffs from cooked food and draughts (the same stat names plus
## stamina_regen and max_health), since stats() is the one place combat reads.
##
## Pure data and serialisable. Inventory moves are duck-typed on the Life autoload
## (count / give / take and its GLoot `inventory`), so tests can pass a fake.
##
## Visual swaps are hooks only: connect `changed(slot, item_id)` in player.gd.

signal changed(slot: String, item_id: String)
signal buffs_changed

const Crafting := preload("res://scripts/sim/crafting.gd")
const ItemsDB := preload("res://scripts/sim/items_db.gd")

## The first seven are the original slots (old saves keep loading); legs, cloak, ring and amulet came with the Region 1 item set.
const SLOTS := ["head", "body", "hands", "feet", "main_hand", "off_hand", "trinket", "legs", "cloak", "ring", "amulet"]
const SLOT_NAMES := {"head": "Head", "body": "Body", "hands": "Hands", "feet": "Feet",
	"main_hand": "Main hand", "off_hand": "Off hand", "trinket": "Trinket", "legs": "Legs", "cloak": "Cloak",
	"ring": "Ring", "amulet": "Amulet"}
const STATS := ["armour", "damage", "speed", "stamina_regen", "max_health", "magic", "block", "resist", "crit", "qi_regen", "max_stamina"]
## Other numeric item fields that count toward stats() when an item has them (equipment and set bonuses).
const EXTRA_STATS := ["stealth", "luck", "heal_power", "potion_power", "forge_quality", "charm", "regen", "armour_pierce"]
const WORN_MULT := 0.5

## slot -> {id, quality, durability}; empty slots are absent.
var slots: Dictionary = {}
## [{name, stat, value, until (absolute in-game hours)}]
var buffs: Array[Dictionary] = []
## Returns absolute in-game hours (Life: `equipment.clock = _abs_hours`). Unset: buffs never expire.
var clock: Callable


static func item_info(id: String) -> Dictionary:
	return Crafting.item_info(id)


static func slot_of(id: String) -> String:
	return String(item_info(id).get("slot", ""))


static func is_equippable(id: String) -> bool:
	return SLOTS.has(slot_of(id))


static func max_durability(id: String, quality := 1) -> int:
	return maxi(1, int(round(float(item_info(id).get("durability", 100)) * float(Crafting.QUALITY_MULT[clampi(quality, 0, 2)]))))


## Stats one item gives at a quality (durability < 0 = like new).
static func item_stats(id: String, quality := 1, durability := -1) -> Dictionary:
	var info := item_info(id)
	var m := float(Crafting.QUALITY_MULT[clampi(quality, 0, 2)])
	if durability == 0:
		m *= WORN_MULT
	var out := {"armour": float(info.get("armour", 0)) * m, "damage": float(info.get("damage", 0)) * m,
		"speed": float(info.get("speed", 0.0)) * (m if float(info.get("speed", 0.0)) > 0.0 else 1.0)}
	# Region 1 items: magic, block, resist, crit, qi_regen, max_health ... (same quality scaling, nothing for old items).
	for k: String in STATS:
		if k != "armour" and k != "damage" and k != "speed" and info.has(k):
			out[k] = float(info[k]) * (m if float(info[k]) > 0.0 else 1.0)
	for k: String in EXTRA_STATS:
		if info.has(k):
			out[k] = float(info[k]) * (m if float(info[k]) > 0.0 else 1.0)
	return out


## Whether a character of `level` may use the item (see items' req_level). Not enforced by equip(); UIs and quests can ask.
static func meets_requirements(id: String, level: int) -> bool:
	return ItemsDB.meets_requirements(id, level)


func equipped(slot: String) -> Dictionary:
	return slots.get(slot, {})


func item_in(slot: String) -> String:
	return String(slots.get(slot, {}).get("id", ""))


## Puts `id` in its slot and returns what was there ({} if empty). Does not touch
## the inventory; see equip_from() for that.
func equip(id: String, quality := 1, durability := -1) -> Dictionary:
	var slot := slot_of(id)
	if not SLOTS.has(slot):
		return {}
	var old: Dictionary = slots.get(slot, {})
	var maxd := max_durability(id, quality)
	slots[slot] = {"id": id, "quality": clampi(quality, 0, 2),
		"durability": maxd if durability < 0 else clampi(durability, 0, maxd)}
	changed.emit(slot, id)
	return old


func unequip(slot: String) -> Dictionary:
	var old: Dictionary = slots.get(slot, {})
	if slots.erase(slot):
		changed.emit(slot, "")
	return old


## Sums of every worn item plus active buffs: {armour, damage, speed, stamina_regen, max_health}.
func stats(now := NAN) -> Dictionary:
	var out := {}
	for s: String in STATS:
		out[s] = 0.0
	var worn: Array = []
	for slot: String in slots:
		var e: Dictionary = slots[slot]
		worn.append(String(e["id"]))
		var st := item_stats(String(e["id"]), int(e["quality"]), int(e["durability"]))
		for k: String in st:
			out[k] = float(out.get(k, 0.0)) + float(st[k])
	if worn.size() >= 2:
		var bonus := ItemsDB.set_bonus_stats(worn)
		for k: String in bonus:
			out[k] = float(out.get(k, 0.0)) + float(bonus[k])
	var t := _now(now)
	for b in buffs:
		if is_nan(t) or float(b["until"]) > t:
			out[String(b["stat"])] = float(out.get(String(b["stat"]), 0.0)) + float(b["value"])
	return out


func _now(now: float) -> float:
	if not is_nan(now):
		return now
	return float(clock.call()) if clock.is_valid() else NAN


# --- durability ----------------------------------------------------------------------

## Wears one slot down; returns true if it just broke (reached 0).
func wear(slot: String, amount := 1) -> bool:
	if not slots.has(slot):
		return false
	var e: Dictionary = slots[slot]
	var before := int(e["durability"])
	e["durability"] = maxi(0, before - amount)
	return before > 0 and int(e["durability"]) == 0


## A hit taken wears one random worn armour piece (call from player.take_damage).
func wear_armour(amount := 1, roll := -1.0) -> String:
	var worn := []
	for slot: String in ["head", "body", "hands", "legs", "feet", "cloak", "off_hand"]:
		if slots.has(slot):
			worn.append(slot)
	if worn.is_empty():
		return ""
	var r := randf() if roll < 0.0 else roll
	var slot: String = worn[mini(int(r * worn.size()), worn.size() - 1)]
	wear(slot, amount)
	return slot


## Adds `fraction` of each worn piece's maximum durability back (repair kits). Returns how many pieces improved.
func repair_partial(fraction: float) -> int:
	var n := 0
	for slot: String in slots:
		var e: Dictionary = slots[slot]
		var maxd := max_durability(String(e["id"]), int(e["quality"]))
		if int(e["durability"]) < maxd:
			e["durability"] = mini(maxd, int(e["durability"]) + int(round(float(maxd) * clampf(fraction, 0.0, 1.0))))
			n += 1
	return n


func needs_repair() -> bool:
	for slot: String in slots:
		var e: Dictionary = slots[slot]
		if int(e["durability"]) < max_durability(String(e["id"]), int(e["quality"])):
			return true
	return false


## Restores every worn item to `fraction` of its maximum (never lowers). Returns how many improved.
func repair_all(fraction := 1.0) -> int:
	var n := 0
	for slot: String in slots:
		var e: Dictionary = slots[slot]
		var target := int(round(max_durability(String(e["id"]), int(e["quality"])) * clampf(fraction, 0.0, 1.0)))
		if int(e["durability"]) < target:
			e["durability"] = target
			n += 1
	return n


# --- buffs ---------------------------------------------------------------------------

## Adds or refreshes a buff (same name replaces).
func add_buff(buff_name: String, stat: String, value: float, hours: float, now := NAN) -> void:
	var t := _now(now)
	for i in range(buffs.size() - 1, -1, -1):
		if buffs[i]["name"] == buff_name:
			buffs.remove_at(i)
	buffs.append({"name": buff_name, "stat": stat, "value": value, "until": (0.0 if is_nan(t) else t) + hours})
	buffs_changed.emit()


func active_buffs(now := NAN) -> Array[Dictionary]:
	var t := _now(now)
	var out: Array[Dictionary] = []
	for b in buffs:
		if is_nan(t) or float(b["until"]) > t:
			out.append(b)
	return out


func prune_buffs(now := NAN) -> void:
	var t := _now(now)
	if is_nan(t):
		return
	var before := buffs.size()
	buffs = buffs.filter(func(b: Dictionary) -> bool: return float(b["until"]) > t)
	if buffs.size() != before:
		buffs_changed.emit()


## Eats, drinks or applies an item: its buff (buff_stat/buff_value/buff_hours),
## cures ("cures": injury type) and then Life.use_item for nutrition and healing.
## Returns the message.
func consume(life: Object, id: String, now := NAN) -> String:
	if int(life.call("count", id)) <= 0:
		return "You have no %s." % Crafting.item_name(id)
	if item_info(id).has("rest_bonus") and life.has_method("camp_here"):
		return String(life.call("camp_here", id))      # a bedroll or tent: camps for the night, is never used up (any level)
	if life.has_method("player_level") and not meets_requirements(id, int(life.call("player_level"))):
		return "You need level %d to use %s." % [ItemsDB.req_level(id), Crafting.item_name(id)]
	var info := item_info(id)
	if info.has("power_manual") and life.has_method("read_power_manual"):
		# A path manual: reading teaches it; the book is kept (it can be sold or lent) and a refused read costs nothing.
		return String((life.call("read_power_manual", id, info) as Dictionary).get("text", ""))
	var extra := PackedStringArray()
	var cured := String(info.get("cures", ""))
	var did := false
	if cured != "":
		var inj: Variant = life.get("injuries")
		if inj is Object:
			var active: Array = (inj as Object).get("active")
			var kept: Array[Dictionary] = []
			for i: Dictionary in active:
				if String(i.get("type", "")) != cured:
					kept.append(i)
			if kept.size() != active.size():
				(inj as Object).set("active", kept)
				extra.append("The fever breaks.")
				var mag: Variant = life.get("magicules")
				if mag is Object and (mag as Object).has_method("apply_effects"):
					(mag as Object).call("apply_effects", (inj as Object).call("effects"))
		did = true
	if info.has("buff_stat"):
		add_buff(String(info.get("buff_name", Crafting.item_name(id))), String(info["buff_stat"]),
			float(info.get("buff_value", 0.0)), float(info.get("buff_hours", 1.0)), now)
		extra.append("%s (%dh)." % [info.get("buff_name", "Buff"), int(info.get("buff_hours", 1))])
		did = true
	if info.has("qi_restore"):
		var mag2: Variant = life.get("magicules")
		if mag2 is Object:
			var o := mag2 as Object
			var cap := float(o.call("effective_max")) if o.has_method("effective_max") else float(o.get("max_pool"))
			o.set("current", minf(cap, float(o.get("current")) + float(info["qi_restore"])))
			extra.append("Qi +%d." % int(info["qi_restore"]))
			did = true
	if info.has("repair_fraction"):
		var fixed := repair_partial(float(info["repair_fraction"]))
		extra.append("%d piece%s mended." % [fixed, "" if fixed == 1 else "s"])
		did = true
	# Effects only the cultivation / combat / world systems can apply (pills, scrolls, coatings, recall ...): they hook in
	# by giving Life an apply_item_effect(id, info) -> String. Without one the item is not spent.
	for k: String in ["cultivation_xp", "breakthrough_bonus", "permanent_stat", "casts", "effect", "coating"]:
		if info.has(k) and life.has_method("apply_item_effect"):
			var res: Variant = life.call("apply_item_effect", id, info)
			if res is String and String(res) != "":
				extra.append(String(res))
			did = true
			break
	var msg := ""
	if float(info.get("nutrition", 0.0)) > 0.0 or (int(info.get("heal", 0)) > 0 and String(info.get("category", "")) != "healing"):
		msg = String(life.call("use_item", id))
	elif int(info.get("heal", 0)) > 0:
		life.call("take", id, 1)
		var pl: Variant = life.get("player")
		if pl is Object and (pl as Object).has_method("heal"):
			(pl as Object).call("heal", int(info["heal"]))
		msg = "%s. +%d health." % [Crafting.item_name(id), int(info["heal"])]
	elif did:
		life.call("take", id, 1)
		msg = "%s." % Crafting.item_name(id)
	else:
		return "You can't use %s." % Crafting.item_name(id)
	if not extra.is_empty():
		msg += " " + " ".join(extra)
	return msg


# --- inventory moves (duck-typed Life) --------------------------------------------------

## Quality of a GLoot item instance (FINE when the property isn't set).
static func quality_of(item: Object) -> int:
	return int(item.call("get_property", "quality", Crafting.Quality.FINE)) if item else Crafting.Quality.FINE


## C13 (Region 1 balance): the "Requires Level N" line on a piece of gear is a rule, not a hint. Without it gold alone buys the best kit
## in the region within weeks, and the gear tier of the end-of-region target (docs/regions/BALANCE_R1.md) could not hold. Issued
## kit (the soldier's rank kit, `issued` true) is exempt: the army hands it out whatever the wearer's level.
const ENFORCE_LEVEL := true

## Takes one `id` (of `quality`, or the best one carried when quality < 0) out of
## the pack and wears it; whatever the slot held goes back into the pack.
func equip_from(life: Object, id: String, quality := -1, issued := false) -> String:
	if not is_equippable(id):
		return "%s can't be worn." % Crafting.item_name(id)
	if int(life.call("count", id)) <= 0:
		return "You have no %s." % Crafting.item_name(id)
	if ENFORCE_LEVEL and not issued and life.has_method("player_level") and not meets_requirements(id, int(life.call("player_level"))):
		return "You need level %d to wear %s." % [ItemsDB.req_level(id), Crafting.item_name(id)]
	var q := quality
	var dur := -1
	var g: Variant = life.get("inventory")
	if g is Object and (g as Object).has_method("get_items_with_prototype_id"):
		var best: Object = null
		for it: Object in (g as Object).call("get_items_with_prototype_id", id):
			var iq := quality_of(it)
			if (quality >= 0 and iq == quality) or (quality < 0 and (best == null or iq > quality_of(best))):
				best = it
		if best == null:
			return "You have no %s %s." % [Crafting.quality_name(quality).to_lower(), Crafting.item_name(id)]
		q = quality_of(best)
		dur = int(best.call("get_property", "durability_left", -1))
		if int(best.call("get_stack_size")) > 1:
			best.call("set_stack_size", int(best.call("get_stack_size")) - 1)
		else:
			(g as Object).call("remove_item", best)
		if life.has_signal("inventory_changed"):
			life.emit_signal("inventory_changed")
	else:
		life.call("take", id, 1)
		q = Crafting.Quality.FINE if quality < 0 else quality
	var old := equip(id, q, dur)
	if not old.is_empty():
		_return_to_pack(life, old)
	return "You equip the %s%s." % [(Crafting.quality_name(q).to_lower() + " ") if q != Crafting.Quality.FINE else "", Crafting.item_name(id)]


func unequip_to(life: Object, slot: String) -> String:
	var old := unequip(slot)
	if old.is_empty():
		return ""
	_return_to_pack(life, old)
	return "You take off the %s." % Crafting.item_name(String(old["id"]))


func _return_to_pack(life: Object, e: Dictionary) -> void:
	var id := String(e["id"])
	var q := int(e.get("quality", 1))
	var dur := int(e.get("durability", -1))
	var g: Variant = life.get("inventory")
	if g is Object and (g as Object).has_method("create_item"):
		var it: Object = (g as Object).call("create_item", id)
		if it:
			if q != Crafting.Quality.FINE:
				it.call("set_property", "quality", q)
			if dur >= 0 and dur < max_durability(id, q):
				it.call("set_property", "durability_left", dur)
			(g as Object).call("add_item_automerge", it)
			if life.has_signal("inventory_changed"):
				life.emit_signal("inventory_changed")
			return
	Crafting.give_item(life, id, 1, q)


# --- save ------------------------------------------------------------------------------

func serialize() -> Dictionary:
	var s := {}
	for slot: String in slots:
		s[slot] = (slots[slot] as Dictionary).duplicate()
	var b := []
	for x in buffs:
		b.append(x.duplicate())
	return {"slots": s, "buffs": b}


func deserialize(data: Dictionary) -> void:
	slots.clear()
	var s: Dictionary = data.get("slots", {})
	for slot: String in s:
		var e: Dictionary = s[slot]
		var id := String(e.get("id", ""))
		if SLOTS.has(slot) and slot_of(id) == slot:
			slots[slot] = {"id": id, "quality": int(e.get("quality", 1)), "durability": int(e.get("durability", max_durability(id, int(e.get("quality", 1)))))}
	buffs.clear()
	for b: Dictionary in data.get("buffs", []):
		buffs.append({"name": String(b.get("name", "")), "stat": String(b.get("stat", "")),
			"value": float(b.get("value", 0.0)), "until": float(b.get("until", 0.0))})
	for slot: String in SLOTS:
		changed.emit(slot, item_in(slot))
	buffs_changed.emit()
