extends RefCounted
## Ranks in the independent trades (owner vision: "ranks in every profession"). The org careers (soldier, smith, inn,
## scribe...) have ladders in data/careers/ladders.json and need a post; fishers, miners, woodcutters, hunters, herbalists
## and cooks work for themselves, so their rank is earned purely by doing: mastery in the trade's discipline plus how
## many times you have done the work (life_path.actions). Every trade is tracked at once; promotions are announced.

## trade -> {disc, tag (life_path action counted), ranks: [[title, mastery level, times done], ...]}
const TRADES := {
	"fisher": {"disc": "fishing", "tag": "fished", "ranks": [["Angler", 0, 1], ["Fisher", 8, 25], ["Master Fisher", 24, 120], ["Fishmaster", 45, 400]]},
	"miner": {"disc": "mining", "tag": "mined", "ranks": [["Rock Breaker", 0, 1], ["Miner", 8, 30], ["Master Miner", 24, 150], ["Delver", 45, 450]]},
	"woodcutter": {"disc": "carpentry", "tag": "chopped_wood", "ranks": [["Wood Gatherer", 0, 1], ["Woodcutter", 8, 30], ["Forester", 24, 150], ["Master of the Woods", 45, 450]]},
	"hunter": {"disc": "hunting", "tag": "hunted", "ranks": [["Trapper", 0, 1], ["Hunter", 10, 15], ["Huntmaster", 28, 80], ["Beastslayer", 48, 250]]},
	"herbalist": {"disc": "herbalism", "tag": "foraged", "ranks": [["Gatherer", 0, 1], ["Herbalist", 8, 30], ["Wise One", 24, 150], ["Master Herbalist", 45, 400]]},
	"thief": {"disc": "", "tag": "stole_unseen", "ranks": [["Cutpurse", 0, 1], ["Thief", 0, 25], ["Master Thief", 0, 120], ["Shadow of the Guild", 0, 400]]},
	"cook": {"disc": "cooking", "tag": "cooked", "ranks": [["Kitchen Hand", 0, 1], ["Cook", 8, 20], ["Chef", 24, 100], ["Master Chef", 45, 300]]},
}

var ranks: Dictionary = {}   # trade -> rank index reached (absent = not started)


## Rank index for a mastery level and count (-1 = not started).
static func rank_for(trade: String, level: int, done: float) -> int:
	var t: Dictionary = TRADES.get(trade, {})
	var r := -1
	var rows: Array = t.get("ranks", [])
	for i in rows.size():
		if level >= int(rows[i][1]) and done >= float(rows[i][2]):
			r = i
	return r


## Re-checks every trade; returns the promotion lines (and stores the new ranks). mastery: RAMastery, actions: life_path.actions.
func update(mastery: Object, actions: Dictionary) -> Array:
	var out: Array = []
	for trade: String in TRADES:
		var t: Dictionary = TRADES[trade]
		var lvl := int(mastery.call("level", String(t["disc"]))) if mastery != null and String(t["disc"]) != "" else 0
		var r := rank_for(trade, lvl, float(actions.get(String(t["tag"]), 0.0)))
		if r > int(ranks.get(trade, -1)):
			ranks[trade] = r
			if r > 0:
				out.append("You are now a %s." % String(t["ranks"][r][0]))
	return out


## Rows for the career screen: [{trade, title, next, need_level, need_done, level, done}]
func rows(mastery: Object, actions: Dictionary) -> Array:
	var out: Array = []
	for trade: String in ranks:
		var t: Dictionary = TRADES[trade]
		var r := int(ranks[trade])
		var rws: Array = t["ranks"]
		var nxt: Array = rws[r + 1] if r + 1 < rws.size() else []
		out.append({"trade": trade, "title": String(rws[r][0]), "next": String(nxt[0]) if not nxt.is_empty() else "",
			"need_level": int(nxt[1]) if not nxt.is_empty() else 0, "need_done": int(nxt[2]) if not nxt.is_empty() else 0,
			"disc": String(t["disc"]), "level": int(mastery.call("level", String(t["disc"]))) if mastery != null and String(t["disc"]) != "" else 0,
			"done": int(actions.get(String(t["tag"]), 0.0))})
	return out


func serialize() -> Dictionary:
	return {"ranks": ranks.duplicate()}


func deserialize(d: Dictionary) -> void:
	ranks = (d.get("ranks", {}) as Dictionary).duplicate()
