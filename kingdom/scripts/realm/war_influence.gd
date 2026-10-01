extends RefCounted
## "Your part in the war": what the player's character can do about a war (or the road to one) at ANY rank.
## A thin, stateless facade over war_sim.gd (tension, casus belli, weariness, peace), campaign.gd (armies,
## couriers, depots, covert ops, engagements), factions.gd (relations, war reputation) and society.gd (evidence).
## Cooldowns and the act log live in war_sim (serialised with it), so this object can be rebuilt at will:
##     var wi := WarInfluence.new(Life, Life.realm)
##     for a in wi.actions(day): ... a.id, a.label, a.blurb, a.ok, a.reason, a.cost
##     var res := wi.do("scout_front", {})   # {ok, text, ...}; the text is also Game.say-able
## Every action states what it feeds: war_sim tension/support/weariness/goal, factions relations and war_rep,
## campaign engagements/couriers/depots/covert evidence. Gates are role, rank, standing and gold; nothing is
## shown as a glowing marker: leads() returns plain sentences.
## `override` replaces any profile() field (tests, scripted scenes).

const PLAYER := "player"
const CALDRENN := "caldrenn"

## id -> {label, blurb, cooldown (days), cost (gold), needs ("war"|"peace"|"any"), feeds}
const ACTIONS := {
	"enlist": {"label": "Enlist in the crown's host", "cooldown": 60, "cost": 0, "needs": "war",
		"blurb": "Take the crown's coin and march with a company. Steadies the line a little and earns the crown's trust.",
		"feeds": "campaign army morale, war_sim support, crown trust"},
	"raise_militia": {"label": "Raise a militia", "cooldown": 20, "cost": 60, "needs": "war",
		"blurb": "Call the able men of your home settlement under your own banner. Needs land, fame or the crown's trust.",
		"feeds": "campaign (a personal army), war_sim weariness and support"},
	"scout_front": {"label": "Scout the front", "cooldown": 1, "cost": 0, "needs": "any",
		"blurb": "Ride the border and report. At war it marks the nearest enemy host on your war map; at peace it tells you who is angry and why.",
		"feeds": "campaign intel, war_sim casus belli lookup"},
	"carry_message": {"label": "Carry an order yourself", "cooldown": 1, "cost": 0, "needs": "war",
		"blurb": "Ride an order to an army in person: faster than a hired courier and never cut down on the road.",
		"feeds": "campaign courier (speed x1.6, safe)"},
	"supply_army": {"label": "Sell to the army depots", "cooldown": 0, "cost": 0, "needs": "war",
		"blurb": "Quartermasters pay well for what the host eats and wears. Fills a depot, keeps the crown's men fed.",
		"feeds": "campaign depot and army supply, war_sim support, gold"},
	"run_caravan": {"label": "Run a caravan through the front", "cooldown": 6, "cost": 0, "needs": "war",
		"blurb": "Haul goods to the frontier towns: double pay and a full depot if you pass the raiders, a lost cargo if not.",
		"feeds": "campaign depot, war_sim support, enterprise caravan route"},
	"sabotage": {"label": "Sabotage their supply", "cooldown": 4, "cost": 40, "needs": "war",
		"blurb": "Cut a supply line and spoil a depot. Leaves evidence that may surface.",
		"feeds": "campaign covert_op, society evidence, war_sim support and (if exposed) tension"},
	"spy": {"label": "Spy on their camp", "cooldown": 3, "cost": 25, "needs": "war",
		"blurb": "Slip into an enemy host and count the tents. Precise intel, few traces.",
		"feeds": "campaign covert_op and intel, society evidence"},
	"assassinate": {"label": "Kill a commander", "cooldown": 10, "cost": 80, "needs": "war",
		"blurb": "A blade for an enemy captain: a green commander, a shaken host. If the trail is found, it is blood on your hands.",
		"feeds": "campaign covert_op, society evidence, war_sim support, factions war_rep"},
	"forge_letter": {"label": "Forge a letter", "cooldown": 6, "cost": 30, "needs": "war",
		"blurb": "A false order in the enemy's hand sends a host the wrong way for two days.",
		"feeds": "campaign covert_op, society evidence"},
	"broker_peace": {"label": "Broker a peace", "cooldown": 15, "cost": 0, "needs": "war",
		"blurb": "Carry terms between the courts. Needs the ear of both: the crown's trust and some standing with the enemy, or great fame. The weary listen.",
		"feeds": "war_sim peace pressure and treaty, factions relations"},
	"mediate": {"label": "Mediate a quarrel", "cooldown": 20, "cost": 0, "needs": "peace",
		"blurb": "Sit between two angry courts before it comes to blows. Eases tension at the angriest border.",
		"feeds": "war_sim tension, factions relations"},
	"provoke": {"label": "Provoke an incident", "cooldown": 12, "cost": 20, "needs": "peace",
		"blurb": "A burned barn, a cut-down envoy, a rumour in the right tavern. Raises tension and hands someone a casus belli. Under a truce it breaks the treaty.",
		"feeds": "war_sim tension and casus belli, factions relations and war_rep"},
	"champion": {"label": "Fight in the line", "cooldown": 2, "cost": 0, "needs": "war",
		"blurb": "Take a place in a live engagement: a champion in the front rank steadies the crown's troops, and you may be wounded.",
		"feeds": "campaign engagement (champion, tactical hero), war_sim via the result"},
	"defend_home": {"label": "Defend your home settlement", "cooldown": 8, "cost": 25, "needs": "war",
		"blurb": "Arm the watch and stand the walls. Raiders are turned back for ten days and the people remember it.",
		"feeds": "war_sim guard, land loyalty, factions war_rep"},
	"push_goal": {"label": "Press a war goal at council", "cooldown": 20, "cost": 0, "needs": "war",
		"blurb": "Use your standing with a lord or the council to change what the war is for: land, tribute, hostages or a marriage.",
		"feeds": "war_sim goal (and so the peace terms), campaign war goals"},
}

var life: Variant
var hub: RefCounted
var override: Dictionary = {}
var _last_text := ""


func _init(life_node: Variant = null, hub_ref: RefCounted = null) -> void:
	life = life_node
	hub = hub_ref
	if hub == null and life != null and "realm" in life:
		hub = life.realm


# --- access ---------------------------------------------------------------------------------------

func war() -> Variant:
	if life != null and "war" in life:
		return life.war
	return null


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func campaign() -> RefCounted:
	var c := _mod("campaign")
	if c != null and c.get("_life") == null and life != null:
		c.call("bind_life", life)
	return c


func _day() -> int:
	var w: Variant = war()
	if w != null:
		return int(w._day)
	return int(WorldSim.day)


func _gold() -> int:
	return int(override.get("gold", Game.gold))


func _pay(n: int) -> void:
	if n != 0:
		Game.add_gold(n)


func _count(item: String) -> int:
	if life != null and life.has_method("count"):
		return int(life.count(item))
	return 0


func _item_value(item: String) -> int:
	if life != null and life.has_method("item_prop"):
		return int(life.item_prop(item, "price", 10))
	return 10


func _rel(a: String, b: String) -> Dictionary:
	var f := _mod("factions")
	return f.call("relation", a, b) if f != null else {"trust": 40.0, "grievance": 0.0, "stance": "neutral"}


func _change(a: String, b: String, field: String, delta: float) -> void:
	var f := _mod("factions")
	if f != null:
		f.call("change_relation", a, b, field, delta)


func _act(act: String) -> void:
	var f := _mod("factions")
	if f != null:
		f.call("record_war_act", PLAYER, act)


func _home_sid() -> int:
	return int(override.get("home", 0))


func _home_name() -> String:
	var sid := _home_sid()
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "home"


## Who you are to the war: role, rank, standing, purse. Every gate reads this.
func profile() -> Dictionary:
	var w: Variant = war()
	var p := {"at_war": w != null and w.is_at_war(), "enemy": "", "rank": "", "soldier": false, "merchant": false, "landholder": false,
		"tier": 1, "crown_trust": 40.0, "enemy_trust": 30.0, "gold": Game.gold, "honour": 0.0}
	if w != null and w.is_at_war():
		p["enemy"] = w.enemy_id()
	if life != null:
		p["rank"] = String(life.career_rank) if "career_rank" in life else ""
		p["soldier"] = "career_id" in life and String(life.career_id) == "soldier"
		p["merchant"] = "career_id" in life and String(life.career_id) == "merchant"
	var ent := _mod("enterprise")
	if ent != null and (bool(ent.get("license_owned")) or not (ent.call("list_caravans") as Array).is_empty()):
		p["merchant"] = true
	var land := _mod("land")
	if land != null:
		for region in land.regions():
			var d: Dictionary = land.deed(region)
			if String(d.get("holder", "")) == PLAYER or String(d.get("occupier", "")) == PLAYER:
				p["landholder"] = true
				break
	var soc := _mod("society")
	if soc != null:
		p["tier"] = int(soc.call("player_tier"))
	p["crown_trust"] = float(_rel(PLAYER, CALDRENN).get("trust", 40.0))
	if p["enemy"] != "":
		p["enemy_trust"] = float(_rel(PLAYER, String(p["enemy"])).get("trust", 30.0))
	var f := _mod("factions")
	if f != null:
		p["honour"] = float(f.call("war_rep", PLAYER).get("honour", 0.0))
	for k: String in override:
		p[k] = override[k]
	return p


## The nation the player is most likely to meet at the border: the enemy at war, else the tenser candidate.
func focus_nation() -> String:
	var w: Variant = war()
	if w == null:
		return ""
	if w.is_at_war():
		return w.enemy_id()
	var best := ""
	var bt := -1.0
	for id: String in w.WAR_CANDIDATES:
		if w.tension_of(id) > bt:
			bt = w.tension_of(id)
			best = id
	return best


# --- gating ------------------------------------------------------------------------------------------

## {ok, reason}: may the player do `id` right now? `params` as in do().
func can(id: String, params: Dictionary = {}) -> Dictionary:
	if not ACTIONS.has(id):
		return {"ok": false, "reason": "Unknown action."}
	var w: Variant = war()
	if w == null:
		return {"ok": false, "reason": "There is no war to speak of."}
	var def: Dictionary = ACTIONS[id]
	var p := profile()
	var day := _day()
	var needs := String(def["needs"])
	if needs == "war" and not bool(p["at_war"]):
		return {"ok": false, "reason": "The realm is not at war."}
	if needs == "peace" and bool(p["at_war"]):
		return {"ok": false, "reason": "Too late for that: the armies are marching."}
	if int(def["cooldown"]) > 0 and not w.act_ready(id, day, int(def["cooldown"])):
		return {"ok": false, "reason": "You have done that too recently."}
	if int(def["cost"]) > 0 and int(p["gold"]) < int(def["cost"]):
		return {"ok": false, "reason": "It costs %d gold." % int(def["cost"])}
	var c := campaign()
	match id:
		"enlist":
			if bool(p["soldier"]):
				return {"ok": false, "reason": "You already wear the crown's colours."}
			if int(w.act_days.get("enlist", -9999)) >= int(w.war.get("started_day", 0)):
				return {"ok": false, "reason": "You already enlisted for this war."}
			if c == null or _crown_armies(c).is_empty():
				return {"ok": false, "reason": "No crown company is mustering."}
		"raise_militia":
			if not (bool(p["landholder"]) or int(p["tier"]) >= 2 or float(p["crown_trust"]) >= 50.0 or bool(p["soldier"])):
				return {"ok": false, "reason": "Nobody will follow an unknown: you need land, fame, rank or the crown's trust."}
			if c == null:
				return {"ok": false, "reason": "No war map."}
		"scout_front":
			if bool(p["at_war"]) and (c == null or _enemy_armies(c).is_empty()):
				return {"ok": false, "reason": "No enemy host is near enough to find."}
		"carry_message":
			if c == null or _crown_armies(c).is_empty():
				return {"ok": false, "reason": "You have no army to carry an order to."}
		"supply_army":
			if String(params.get("good", "")) != "" and _count(String(params["good"])) < 1:
				return {"ok": false, "reason": "You have none of that to sell."}
			if _supply_goods().is_empty() and String(params.get("good", "")) == "":
				return {"ok": false, "reason": "You carry nothing the army wants."}
		"run_caravan":
			if not bool(p["merchant"]) and _supply_goods().is_empty():
				return {"ok": false, "reason": "You need goods to haul, or a caravan."}
		"sabotage", "spy", "assassinate", "forge_letter":
			if c == null or _enemy_armies(c).is_empty():
				return {"ok": false, "reason": "You do not know where to strike: scout first."}
			if id == "assassinate" and float(p["honour"]) > 40.0:
				return {"ok": false, "reason": "Your name is too honourable for that work."}
		"broker_peace":
			if w.war_day() < 10:
				return {"ok": false, "reason": "The war is too young: nobody listens yet."}
			var ears := float(p["crown_trust"]) >= 40.0 and float(p["enemy_trust"]) >= 25.0
			if not (ears or int(p["tier"]) >= 4):
				return {"ok": false, "reason": "Neither court trusts you enough to hear terms."}
		"mediate":
			if float(p["crown_trust"]) < 35.0 and int(p["tier"]) < 2:
				return {"ok": false, "reason": "You are nobody to either court."}
			if w.tension_of(focus_nation()) < 25.0:
				return {"ok": false, "reason": "There is no quarrel worth a mediator."}
		"provoke":
			if focus_nation() == "":
				return {"ok": false, "reason": "No one to provoke."}
		"champion":
			if c == null or _live_engagement(c).is_empty():
				return {"ok": false, "reason": "There is no fight on your map to join."}
		"defend_home":
			if not _threatened_home(w, p):
				return {"ok": false, "reason": "%s is not in danger." % _home_name()}
		"push_goal":
			if not (float(p["crown_trust"]) >= 55.0 or bool(p["landholder"]) or int(p["tier"]) >= 3):
				return {"ok": false, "reason": "No lord listens to you yet: land, fame or the crown's trust."}
			var g := String(params.get("goal", ""))
			if g != "" and not (g in ["land", "tribute", "hostages", "marriage"]):
				return {"ok": false, "reason": "Unknown goal."}
	return {"ok": true, "reason": ""}


## All actions with their gate state: [{id, label, blurb, feeds, cost, cooldown, ok, reason}], available ones first.
func actions(_day_unused := -1) -> Array:
	var out: Array = []
	for id: String in ACTIONS:
		var def: Dictionary = ACTIONS[id]
		var c := can(id)
		out.append({"id": id, "label": def["label"], "blurb": def["blurb"], "feeds": def["feeds"], "cost": def["cost"], "cooldown": def["cooldown"],
			"ok": bool(c["ok"]), "reason": String(c["reason"]), "needs": def["needs"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["ok"]) != bool(b["ok"]):
			return bool(a["ok"])
		return false)
	return out


func _crown_armies(c: RefCounted) -> Array:
	return (c.call("armies") as Array).filter(func(a: Dictionary) -> bool: return a["faction"] == PLAYER)


func _enemy_armies(c: RefCounted) -> Array:
	return (c.call("armies") as Array).filter(func(a: Dictionary) -> bool: return a["faction"] != PLAYER)


func _live_engagement(c: RefCounted) -> Dictionary:
	for e: Dictionary in (c.call("engagements", true) as Array):
		if String(e["status"]) != "ended":
			return e
	return {}


## Goods the player carries that an army wants ({good: count}) for the UI's sell buttons.
func supply_goods() -> Dictionary:
	var out := {}
	for g: String in _supply_goods():
		out[g] = _count(g)
	return out


func last_text() -> String:
	return _last_text


func _supply_goods() -> Array:
	var out: Array = []
	for g: String in ["bread", "cheese", "stew", "iron_sword", "iron_helm", "leather_jerkin", "firewood", "apple"]:
		if _count(g) > 0:
			out.append(g)
	return out


func _threatened_home(w: Variant, _p: Dictionary) -> bool:
	if not w.is_at_war():
		return false
	var hp := Vector2.ZERO
	var sid := _home_sid()
	if sid >= 0 and sid < WorldGen.settlements.size():
		hp = WorldGen.settlements[sid]["pos"]
	for r: Dictionary in w.raided_today():
		if String(r["settlement_name"]) == _home_name():
			return true
	# the front is near when any front region is within 2.5 km of home
	for f: Dictionary in w.front():
		if (f["pos"] as Vector2).distance_to(hp) < 2500.0:
			return true
	return bool(override.get("home_threatened", false))


## Plain-sentence opportunities the player can notice (text only). Empty when nothing is afoot.
func leads() -> Array[String]:
	var out: Array[String] = []
	var w: Variant = war()
	if w == null:
		return out
	var p := profile()
	var c := campaign()
	if w.is_at_war():
		var id: String = w.enemy_id()
		out.append("Recruiting sergeants are working the roads: the %s war wants men." % w.display_name(id))
		if w.exhaustion() > 0.6:
			out.append("Soldiers mutter that the war has gone on long enough. A go-between might be heard.")
		var goods: Dictionary = w.contract_for_merchant(_day())
		if not goods.is_empty():
			out.append("A quartermaster is paying over the odds for %s." % String(goods["good"]).replace("_", " "))
		if _threatened_home(w, p):
			out.append("Riders say raiders have been seen near %s." % _home_name())
		if c != null and _live_engagement(c).size() > 0:
			out.append("A fight is going badly somewhere near the front; a good sword might turn it.")
		if c != null and not _enemy_armies(c).is_empty():
			out.append("An enemy captain is camped without much guard. Someone could cut his road, or his throat.")
	else:
		for n: Dictionary in w.all_diplomacy():
			if String(n["state"]) == "truce" and int(n["truce_days"]) < 30:
				out.append("The truce with %s runs out within the month." % n["name"])
			for line: String in (n["reasons"] as Array):
				out.append("Word at the inns: %s" % line)
			if float(n["tension"]) > 50.0:
				out.append("%s envoys are seen in the great houses; someone could calm them, or stir them." % n["name"])
	return out


# --- doing ---------------------------------------------------------------------------------------------

## Performs an action. params by action: supply_army {good, qty}, carry_message {army_id, kind, target},
## run_caravan {good, qty, caravan_id}, sabotage/spy/assassinate/forge_letter {target} (army id or node),
## broker_peace {terms: "fair"|"lenient"|"harsh"}, provoke {nation, incident}, push_goal {goal}.
## Returns {ok, text, ...action fields}. On failure {ok:false, text: reason} and nothing changes.
func do(id: String, params: Dictionary = {}) -> Dictionary:
	var g := can(id, params)
	if not bool(g["ok"]):
		return {"ok": false, "text": String(g["reason"])}
	var w: Variant = war()
	var day := _day()
	var res: Dictionary
	match id:
		"enlist":
			res = _do_enlist(w, day)
		"raise_militia":
			res = _do_militia(w, day, params)
		"scout_front":
			res = _do_scout(w, day)
		"carry_message":
			res = _do_carry(w, day, params)
		"supply_army":
			res = _do_supply(w, day, params)
		"run_caravan":
			res = _do_caravan(w, day, params)
		"sabotage", "spy", "assassinate", "forge_letter":
			res = _do_covert(w, day, id, params)
		"broker_peace":
			res = _do_broker(w, day, params)
		"mediate":
			res = _do_mediate(w, day)
		"provoke":
			res = _do_provoke(w, day, params)
		"champion":
			res = _do_champion(w, day)
		"defend_home":
			res = _do_defend(w, day)
		"push_goal":
			res = _do_goal(w, day, params)
		_:
			res = {"ok": false, "text": "Unknown action."}
	if bool(res.get("ok", false)):
		var cost := int((ACTIONS[id] as Dictionary)["cost"])
		if cost > 0 and not res.has("paid"):
			_pay(-cost)
		w.note_act(id, day, String(res["text"]))
		_last_text = String(res["text"])
	return res


func _do_enlist(w: Variant, day: int) -> Dictionary:
	var c := campaign()
	var a: Dictionary = _crown_armies(c)[0]
	for x: Dictionary in _crown_armies(c):
		if int(x["strength"]) > int(a["strength"]):
			a = x
	var army: Dictionary = c.call("_army", int(a["id"]))
	army["morale"] = clampf(float(army["morale"]) + 0.05, 0.0, 1.0)
	army["strength"] = int(army["strength"]) + 1
	army["max_strength"] = maxi(int(army["max_strength"]), int(army["strength"]))
	w.add_support(0.01)
	_change(PLAYER, CALDRENN, "trust", 4.0)
	_act("enlist")
	_pay(15)
	return {"ok": true, "text": "You take the crown's shilling and fall in with %s (+15 gold). The company is a little steadier for one more sword." % String(a["name"]),
		"army_id": int(a["id"]), "paid": 15}


func _do_militia(w: Variant, day: int, params: Dictionary) -> Dictionary:
	var c := campaign()
	var men := clampi(int(params.get("men", 40)), 10, 120)
	var cost := 60 + 2 * (men - 40)
	if _gold() < cost:
		return {"ok": false, "text": "Arming %d men costs %d gold." % [men, cost]}
	var node: int = int(c.call("nearest_node", WorldGen.settlements[_home_sid()]["pos"])) if _home_sid() < WorldGen.settlements.size() else 0
	var aid: int = int(c.call("raise_militia", node, men, "%s Militia" % _home_name()))
	c.call("set_army_owner", aid, "personal")
	w.add_support(0.02)
	w.ease_weariness(-0.03)
	_change(PLAYER, CALDRENN, "trust", 3.0)
	var land := _mod("land")
	if land != null:
		land.adjust_loyalty(_home_sid(), 3.0)
	_act("raise_militia")
	_pay(-cost)
	return {"ok": true, "text": "%d men of %s take up spears under your banner (-%d gold). They are green, but they are yours to command." % [men, _home_name(), cost],
		"army_id": aid, "men": men, "paid": -cost}


func _do_scout(w: Variant, day: int) -> Dictionary:
	var c := campaign()
	if w.is_at_war():
		var foes := _enemy_armies(c)
		var me := Vector2.ZERO
		if _home_sid() < WorldGen.settlements.size():
			me = WorldGen.settlements[_home_sid()]["pos"]
		foes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["pos"] as Vector2).distance_squared_to(me) < (b["pos"] as Vector2).distance_squared_to(me))
		var f: Dictionary = foes[0]
		c.call("add_intel", int(f["id"]), "scout", 0.15, 0.85)
		_change(PLAYER, CALDRENN, "trust", 1.0)
		return {"ok": true, "text": "You ride the border and find %s: about %d men. It is on your war map now." % [String(f["name"]), int(round(float(f["strength"]) / 10.0)) * 10],
			"army_id": int(f["id"])}
	var id := focus_nation()
	var d: Dictionary = w.diplomacy(id)
	var lines: Array = d["reasons"]
	var t := "The border with %s is quiet for now." % w.display_name(id)
	if not lines.is_empty():
		t = "You hear it at the border posts: %s" % String(lines[0])
	elif float(d["tension"]) > 40.0:
		t = "Patrols with %s grow sharp-tongued, though no one can name a cause yet." % w.display_name(id)
	return {"ok": true, "text": t, "tension": d["tension"], "reasons": lines}


func _do_carry(w: Variant, day: int, params: Dictionary) -> Dictionary:
	var c := campaign()
	var aid := int(params.get("army_id", 0))
	if aid == 0:
		aid = int(_crown_armies(c)[0]["id"])
	var order: Dictionary = params.get("order", {"kind": "hold", "target": int((c.call("armies") as Array)[0]["node"])})
	var cour: Dictionary = c.call("issue_order", aid, order, {"speed_mult": 1.6, "safe": true})
	if cour.is_empty():
		return {"ok": false, "text": "That army cannot be found."}
	_change(PLAYER, CALDRENN, "trust", 1.0)
	_act("carry_message")
	return {"ok": true, "text": "You ride the order through yourself: it will reach them in about %d hours, and nobody will stop you." % int(cour["eta_hours"]),
		"courier": cour}


func _do_supply(w: Variant, day: int, params: Dictionary) -> Dictionary:
	var c := campaign()
	var good := String(params.get("good", ""))
	if good == "":
		good = String(_supply_goods()[0])
	var qty := clampi(int(params.get("qty", 1)), 1, maxi(1, _count(good)))
	qty = mini(qty, _count(good))
	var enemy_side := String(params.get("side", "crown")) == "enemy"
	var contract: Dictionary = w.contract_for_merchant(day)
	var mult := 1.0
	if not contract.is_empty() and String(contract["good"]) == good:
		mult = float(contract["pay_mult"])
	if enemy_side:
		mult *= 1.6
	var pay := int(round(float(_item_value(good) * qty) * mult))
	if not life.take(good, qty):
		return {"ok": false, "text": "You do not have %d %s." % [qty, good.replace("_", " ")]}
	_pay(pay)
	if enemy_side:
		w.add_support(-minf(0.03, 0.004 * qty))
		_change(PLAYER, w.enemy_id(), "trust", 3.0)
		_change(PLAYER, CALDRENN, "grievance", 6.0)
		_act("profiteer")
		return {"ok": true, "text": "You quietly sell %d %s to the enemy's foragers for %d gold. The crown would hang you for it." % [qty, good.replace("_", " "), pay],
			"paid": pay, "qty": qty}
	var node: int = int(c.call("nearest_node", WorldGen.settlements[_home_sid()]["pos"]))
	var crown := _crown_armies(c)
	if not crown.is_empty():
		node = int(crown[0]["node"])
	var stock: float = float(c.call("supply_depot", node, float(qty) * 6.0))
	w.add_support(minf(0.03, 0.004 * qty * mult))
	_change(PLAYER, CALDRENN, "trust", minf(4.0, 0.5 * qty))
	_act("supply_army")
	return {"ok": true, "text": "The quartermaster counts out %d gold for %d %s. The depot now holds about %d." % [pay, qty, good.replace("_", " "), int(stock)],
		"paid": pay, "qty": qty, "depot_stock": stock}


func _do_caravan(w: Variant, day: int, params: Dictionary) -> Dictionary:
	var c := campaign()
	var fronts: Array = w.front()
	var f: Dictionary = fronts[0]
	var node: int = int(c.call("nearest_node", f["pos"]))
	# the risk: how hard the raiders hold the road (control of the front) and the season
	var ctrl: float = w.avg_control()
	var chance := clampf(0.45 + 0.4 * ctrl + float(params.get("guards", 0)) * 0.05, 0.25, 0.92)
	var r := RandomNumberGenerator.new()
	r.seed = hash([day, "caravan", w.wars_total, _count("bread")])
	var good := String(params.get("good", ""))
	var ent := _mod("enterprise")
	var cid := int(params.get("caravan_id", -1))
	var worth := 0
	var qty := 0
	if cid >= 0 and ent != null and not (ent.call("get_caravan", cid) as Dictionary).is_empty():
		# a caravan of the company: point its route at the front town
		var sid := int(WorldGen.nearest_settlement(f["pos"]).get("id", 0))
		ent.call("set_caravan_route", cid, [sid])
		qty = 10
		worth = 120
	else:
		if good == "":
			good = String(_supply_goods()[0])
		qty = clampi(int(params.get("qty", 5)), 1, maxi(1, _count(good)))
		qty = mini(qty, _count(good))
		worth = _item_value(good) * qty
		if not life.take(good, qty):
			return {"ok": false, "text": "You have no cargo to haul."}
	if r.randf() < chance:
		var pay := worth * 2
		_pay(pay)
		var stock: float = float(c.call("supply_depot", node, float(qty) * 8.0))
		w.add_support(0.02)
		_change(PLAYER, CALDRENN, "trust", 3.0)
		_act("supply_army")
		return {"ok": true, "text": "You run the cargo through the raiders to %s: %d gold and a full depot (about %d)." % [String(f["name"]), pay, int(stock)],
			"paid": pay, "qty": qty, "through": true}
	_change(PLAYER, CALDRENN, "trust", -1.0)
	return {"ok": true, "text": "Raiders catch the caravan short of %s. The cargo is lost, and you are lucky to ride away." % String(f["name"]),
		"paid": 0, "qty": qty, "through": false}


func _do_covert(w: Variant, day: int, id: String, params: Dictionary) -> Dictionary:
	var c := campaign()
	var kind := {"sabotage": "sabotage", "spy": "spy", "assassinate": "assassination", "forge_letter": "forged_letter"}[id] as String
	var foes := _enemy_armies(c)
	var target := int(params.get("target", -1))
	if target < 0:
		target = int(foes[0]["node"]) if kind == "sabotage" else int(foes[0]["id"])
	var cost := int((ACTIONS[id] as Dictionary)["cost"])
	var res: Dictionary = c.call("covert_op", kind, target, {"crestless": bool(params.get("crestless", true)), "agent_skill": int(params.get("agent_skill", 0))})
	if res.get("evidence_id", -1) == -1 and not bool(res.get("ok", false)):
		return {"ok": false, "text": "That target cannot be found."}
	var ok := bool(res["ok"])
	_pay(-cost)
	_act("covert")
	if id == "assassinate":
		_act("kill_prisoners" if not ok else "covert_exposed")   # the stain is recorded whether or not the blow lands
	var names := {"sabotage": "You cut the enemy's supply road and spoil a store", "spy": "You count the tents and the watchfires",
		"assassinate": "The commander falls and his host is shaken", "forge_letter": "The forged order goes out in the enemy's hand"}
	var fails := {"sabotage": "The raid is beaten off and the dogs are loose", "spy": "You are nearly caught in their camp", "assassinate": "The blow fails and the alarm is raised",
		"forge_letter": "The seal is not quite right and the courier is turned back"}
	var text := "%s. Some trace may remain (evidence %s)." % [(names if ok else fails)[id], String(res.get("society_evidence", ""))]
	if not ok:
		_change(PLAYER, String(res["target_faction"]), "grievance", 4.0)
	return {"ok": true, "text": text, "success": ok, "evidence_id": int(res["evidence_id"]), "society_evidence": res.get("society_evidence", ""), "paid": -cost}


func _do_broker(w: Variant, day: int, params: Dictionary) -> Dictionary:
	var p := profile()
	var enemy: String = w.enemy_id()
	var weary: float = maxf(w.exhaustion(), w.enemy_exhaustion())
	var trust := (float(p["crown_trust"]) + float(p["enemy_trust"])) * 0.5
	var chance := clampf(0.2 + weary * 0.45 + trust / 250.0 + float(int(p["tier"])) * 0.03, 0.1, 0.95)
	var r := RandomNumberGenerator.new()
	r.seed = hash([day, "broker", w.wars_total])
	var terms_kind := String(params.get("terms", "fair"))
	if terms_kind == "lenient":
		chance += 0.1
	elif terms_kind == "harsh":
		chance -= 0.1
	if r.randf() >= chance:
		_change(PLAYER, CALDRENN, "trust", -1.0)
		_change(PLAYER, enemy, "trust", -1.0)
		return {"ok": true, "success": false, "text": "You carry terms between the courts, but neither will be the first to bend. (%d%% chance)" % int(chance * 100.0), "chance": chance}
	w.push_peace(0.5 if terms_kind != "harsh" else 0.35)
	_change(PLAYER, CALDRENN, "trust", 3.0)
	_change(PLAYER, enemy, "trust", 5.0)
	_act("broker_peace")
	var text := "Both courts agree to talk. The war is closer to its end."
	var concluded := false
	if w.exhaustion() + w.enemy_exhaustion() + float(w.war.get("pressure", 0.0)) >= 1.0:
		var t: Dictionary = w.propose_terms()
		if terms_kind == "lenient":
			t["tribute"] = int(int(t["tribute"]) * 0.5)
			t["truce_days"] = int(t["truce_days"]) + 90
		elif terms_kind == "harsh":
			t["truce_days"] = int(t["truce_days"]) - 60
		t["text"] = String(t["text"]) + ", by your brokering"
		w.conclude_peace(day, t)
		concluded = true
		text = "Your terms are signed: %s." % String(t["text"])
		var gift := 50 + 10 * int(p["tier"])
		_pay(gift)
		text += " Both sides send you gifts worth %d gold." % gift
	return {"ok": true, "success": true, "concluded": concluded, "text": text, "chance": chance}


func _do_mediate(w: Variant, day: int) -> Dictionary:
	var id := focus_nation()
	var before: float = w.tension_of(id)
	w.add_tension(id, -15.0)
	w.remove_cb(id, "incident")
	_change(PLAYER, id, "trust", 3.0)
	_change(PLAYER, CALDRENN, "trust", 2.0)
	_act("broker_peace")
	return {"ok": true, "text": "You sit between the envoys of %s and the crown until tempers cool. Tension falls from %d to %d." % [w.display_name(id), int(before), int(w.tension_of(id))],
		"nation": id, "tension": w.tension_of(id)}


func _do_provoke(w: Variant, day: int, params: Dictionary) -> Dictionary:
	var id := String(params.get("nation", focus_nation()))
	var kind := String(params.get("incident", "incident"))
	var broke := false
	if w.under_truce(id, day):
		broke = w.break_truce(id, PLAYER, day)
		_act("break_treaty")
	w.add_tension(id, 12.0)
	var text := "A burned granary on the %s border, and the right whispers in the right inns." % w.display_name(id)
	w.offer_cb(id, "insult" if kind == "insult" else "incident", text, day, "enemy")
	_change(PLAYER, id, "grievance", 10.0)
	_change(PLAYER, id, "trust", -8.0)
	_act("provoke")
	# a hand behind it may be found
	var c := campaign()
	var soc := _mod("society")
	var ev := ""
	if soc != null:
		ev = String(soc.call("add_evidence", "war_provocation", "torch_and_tar", 0.3, _home_sid()))
	if c != null:
		c.call("note_trace", "provocation", 0, id, 0.25, ev)
	return {"ok": true, "text": "%s Tension with %s rises to %d.%s" % [text, w.display_name(id), int(w.tension_of(id)), " The truce is broken." if broke else ""],
		"nation": id, "tension": w.tension_of(id), "broke_truce": broke, "society_evidence": ev}


func _do_champion(w: Variant, day: int) -> Dictionary:
	var c := campaign()
	var e := _live_engagement(c)
	var r: Dictionary = c.call("join_engagement", int(e["id"]))
	if not bool(r.get("ok", false)):
		return {"ok": false, "text": String(r.get("reason", "You cannot join."))}
	_act("champion")
	_change(PLAYER, CALDRENN, "trust", 3.0)
	var wound := ""
	if bool(r.get("wounded", false)) and life != null and "injuries" in life:
		life.injuries.add("deep_cut", day)
		wound = " A blade opens your arm: you are wounded."
	return {"ok": true, "text": "You push into the front rank beside the crown's banner. The line steadies around you.%s" % wound, "engagement": int(e["id"]),
		"wounded": bool(r.get("wounded", false))}


func _do_defend(w: Variant, day: int) -> Dictionary:
	var name := _home_name()
	w.guard_settlement(name, day + 10)
	var land := _mod("land")
	if land != null:
		land.adjust_loyalty(_home_sid(), 6.0)
		land.remember(_home_sid(), "relief", 0.4, day)
	_act("defend_home")
	_change(PLAYER, CALDRENN, "trust", 2.0)
	return {"ok": true, "text": "You arm the watch and stand the walls of %s. Raiders will be turned back for ten days (-25 gold)." % name, "settlement": name, "until": day + 10}


func _do_goal(w: Variant, day: int, params: Dictionary) -> Dictionary:
	var goal := String(params.get("goal", "land"))
	var old := String(w.war.get("goal", "tribute"))
	if goal == old:
		return {"ok": false, "text": "The lords already fight for that."}
	w.set_goal(goal)
	_change(PLAYER, CALDRENN, "trust", 1.0)
	var c := campaign()
	if c != null:
		var f: Dictionary = (w.front() as Array)[0]
		var sid := int(WorldGen.nearest_settlement(f["pos"]).get("id", 0))
		var kinds := {"land": "recover_land", "tribute": "tribute", "hostages": "free_prisoners", "marriage": "install_claimant"}
		c.call("add_war_goal", kinds[goal], sid, w.enemy_id(), {"text": "Your council pushes for %s" % goal})
	var names := {"land": "land", "tribute": "tribute", "hostages": "hostages", "marriage": "a marriage"}
	return {"ok": true, "text": "At council you argue that this war is for %s, not %s. The lords come round." % [names[goal], names.get(old, old)], "goal": goal, "old": old}
