extends "res://scripts/realm/realm_module.gd"
## Lighter, real ladders for the four working careers (data/careers/ladders.json): each has two or
## three skill mechanics that feed the ladder's counters (career_stats), and ties into an existing
## system instead of a new one.
##
##   farmer      tenant -> landowner -> estate owner     sow-and-tend (crop fit to season + care), a lease
##                                                        from homestead.gd (rent, landlord share and eviction
##                                                        are homestead's), settling tenants of your own
##   soldier     recruit -> squad -> officer -> commander drills, squad missions (orders judged against the
##                                                        enemy; men lost on bad calls), campaign muster
##                                                        (callups.gd levies, campaign.set_player_rank)
##   merchant    stall -> shop -> caravan -> company     haggling rounds, stall stock against demand,
##                                                        caravans and workshops counted from enterprise.gd
##   blacksmith  apprentice -> smith -> master -> owner  forging (heat and strike set the quality tier via
##                                                        crafting.gd odds), commissions with a minimum
##                                                        tier, workshop from enterprise.gd
##
## A task is a list of steps; each step is a "timing" (the screen reports a quality) or a "choice"
## (options carry hidden quality from the scenario). submit(value) walks the steps; the last one pays.
## Money rule: never touches the purse; the presenter calls take_pending_gold().

const CareerLadders := preload("res://scripts/sim/career_ladders.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")

const CAREERS := ["farmer", "soldier", "merchant", "blacksmith"]
const DISCIPLINE := {"farmer": "farming", "soldier": "soldiering", "merchant": "trading", "blacksmith": "smithing"}
const SPHERE := {"farmer": "farming", "soldier": "military", "merchant": "trade", "blacksmith": "craft"}
const TITLE := {"farmer": "Farmer", "soldier": "Soldier", "merchant": "Merchant", "blacksmith": "Blacksmith"}
const TENANT_COST := 80
const TENANT_RENT := 4
const XP := 1.4
const TASK_HOURS := {"sow": 3.0, "tenant": 1.0, "drill": 2.0, "squad": 4.0, "muster": 1.0, "haggle": 2.0, "stall": 6.0, "forge": 2.0, "commission": 3.0}
const MAX_HOURS := 10.0

const SEASON_CROPS := {
	"spring": {"barley": 0.9, "flax": 0.7, "turnips": 0.5, "wheat": 0.3},
	"summer": {"wheat": 0.9, "barley": 0.6, "flax": 0.4, "turnips": 0.3},
	"autumn": {"turnips": 0.9, "wheat": 0.6, "barley": 0.4, "flax": 0.2},
	"winter": {"turnips": 0.6, "barley": 0.3, "wheat": 0.2, "flax": 0.1},
}
## Scenario (enemy) -> best approach and best stand.
const ENEMIES := {
	"bandit ambush on the road": {"approach": "Send a scout ahead and keep to the open", "stand": "Wedge through and scatter them"},
	"wolves at the flock": {"approach": "Move downwind in a close file", "stand": "Hold a spear line"},
	"raiders at the ford": {"approach": "Take the high bank first", "stand": "Form a shield wall"},
	"cavalry on the plain": {"approach": "Fall back to broken ground", "stand": "Set pikes and brace"},
}
const APPROACH_WRONG := ["March straight down the road", "Split the squad to cover more ground", "Wait where you are and see what comes"]
const STAND_WRONG := ["Charge and shout", "Break and run for the trees", "Hold the middle and hope"]
const PIECES := ["a plough blade", "a sword", "a set of hinges", "a helm", "a billhook", "a pair of tongs"]
const TIER_NAMES := ["rough", "fine", "masterwork"]

var mastery_ref: RefCounted = null
var bio_ref: RefCounted = null
var gold_ref := -1
var sync_life := true
var homestead_ref: RefCounted = null
var flags_extra: Dictionary = {}       # tests and sims inject property flags (owns_workshop, owns_cart...)
var sponsor_ref := -1                  # tests inject; otherwise Life.career_sponsor_tier
var at_war_ref := false

var pending_gold := 0
var ranks: Dictionary = {}             # career -> rank id
var since: Dictionary = {}             # career -> day the rank began
var stats: Dictionary = {}             # career -> {stat: n}
var tenancy: Dictionary = {}           # {plot, since, weeks}: the lease taken through take_tenancy (homestead owns the rent)
var estate: Dictionary = {}            # {tenants, weeks}
var squad: Dictionary = {"men": 0, "lost": 0}
var task: Dictionary = {}
var hours_used: Dictionary = {}
var log_lines: Array = []
var _day := 0
var _counter := 0


# ---------------------------------------------------------------- helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _mod(name: String) -> RefCounted:
	return hub.mod(name) if hub != null else null


func _mastery() -> RefCounted:
	if mastery_ref != null:
		return mastery_ref
	return Life.mastery if Life != null else null


func _bio() -> RefCounted:
	if bio_ref != null:
		return bio_ref
	return Life.biography if Life != null else null


func _gold() -> int:
	if gold_ref >= 0:
		return gold_ref
	return int(Game.gold) if Game != null else 0


func _homestead() -> RefCounted:
	if homestead_ref != null:
		return homestead_ref
	return Life.homestead if Life != null else null


func _say(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 20:
		log_lines.pop_front()


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func level(career: String) -> int:
	var m := _mastery()
	return int(m.call("level", String(DISCIPLINE[career]))) if m != null else 1


func _gain(career: String, amount: float, day: int) -> void:
	var m := _mastery()
	if m != null:
		m.call("gain", String(DISCIPLINE[career]), amount, day)


func _rep(career: String, delta: float) -> void:
	var b := _bio()
	if b != null:
		b.call("change_rep", String(SPHERE[career]), delta)


func bump(career: String, stat: String, n := 1) -> void:
	var d: Dictionary = stats.get(career, {})
	d[stat] = int(d.get(stat, 0)) + n
	stats[career] = d


func stat(career: String, name: String) -> int:
	return int((stats.get(career, {}) as Dictionary).get(name, 0))


func hours_left(day: int) -> float:
	return MAX_HOURS - float(hours_used.get(str(day), 0.0))


# ---------------------------------------------------------------- rank, ladder

func is_member(career: String) -> bool:
	return ranks.has(career)


func rank_of(career: String) -> String:
	if sync_life and Life != null and Life.get("career_id") != null and String(Life.career_id) == career and String(Life.career_rank) != "":
		return String(Life.career_rank)
	return String(ranks.get(career, ""))


func rank_title(career: String) -> String:
	var r := rank_of(career)
	return CareerLadders.title_for(career, r) if r != "" else "-"


func join(career: String, day: int) -> Dictionary:
	if not DISCIPLINE.has(career):
		return {"ok": false, "reason": "No such trade."}
	if ranks.has(career):
		return {"ok": false, "reason": "You already follow that trade."}
	ranks[career] = CareerLadders.first_rank(career)
	since[career] = day
	if sync_life and Life != null and Life.get("career_id") != null and String(Life.career_id) != career:
		Life.career_id = career
		Life.career_rank = String(ranks[career])
		Life.career_since_day = day
		var b := _bio()
		if b != null:
			b.call("start_chapter", career, "", String(ranks[career]), "", day)
	_say("You take up %s work as %s." % [career, rank_title(career)])
	return {"ok": true, "reason": ""}


func since_day(career: String) -> int:
	if sync_life and Life != null and Life.get("career_id") != null and String(Life.career_id) == career:
		return int(Life.career_since_day)
	return int(since.get(career, 0))


func _flags() -> Dictionary:
	var f := {}
	var hs := _homestead()
	if hs != null:
		f["leased_plot"] = not (hs.get("leased") as Dictionary).is_empty()
		f["owns_plot"] = not (hs.get("owned") as Dictionary).is_empty()
	if tenancy.has("plot"):
		f["leased_plot"] = true
	var en := _mod("enterprise")
	if en != null:
		f["owns_workshop"] = not (en.get("workshops") as Array).is_empty()
	if sync_life and Life != null:
		var eco: Variant = Life.get("economy")
		if eco != null:
			f.merge((eco as RefCounted).call("ladder_ctx"))
		var prop: Variant = Life.get("property")
		if prop != null:
			f["owns_shop"] = bool(f.get("owns_shop", false)) or (prop as RefCounted).call("owned").any(func(p: Variant) -> bool: return p is Dictionary and String(p.get("kind", "")) == "trader")
	f.merge(flags_extra, true)
	return f


## Counters the ladder reads: the stored ones plus live figures from the systems behind them.
func career_stats(career: String) -> Dictionary:
	var d: Dictionary = (stats.get(career, {}) as Dictionary).duplicate()
	match career:
		"farmer":
			d["tenants"] = int(estate.get("tenants", 0))
		"soldier":
			d["commands"] = int(d.get("squad_missions", 0))
		"merchant":
			var en := _mod("enterprise")
			if en != null:
				d["caravans_run"] = maxi(int(d.get("caravans_run", 0)), (en.get("caravans") as Dictionary).size())
	return d


func ladder_ctx(career: String, day: int) -> Dictionary:
	var ctx := {"career": career, "rank": rank_of(career), "since_day": since_day(career), "day": day, "mastery": _mastery(), "biography": _bio(),
		"gold": _gold(), "at_war": at_war_ref or _at_war(), "sponsor_tier": _sponsor(), "career_stats": career_stats(career)}
	ctx.merge(_flags())
	return ctx


func _sponsor() -> int:
	if sponsor_ref >= 0:
		return sponsor_ref
	if Life != null and Life.get("career_sponsor_tier") != null:
		return int(Life.career_sponsor_tier)
	return 0


func _at_war() -> bool:
	if Life != null and Life.get("war") != null and (Life.war as Object).has_method("is_at_war"):
		return bool(Life.war.is_at_war())
	return false


func status(career: String, day: int) -> Dictionary:
	return CareerLadders.check_promotion(ladder_ctx(career, day))


## Promote when every requirement is met (the daily tick calls this too).
func promote(career: String, day: int) -> Dictionary:
	if not ranks.has(career):
		return {"ok": false, "text": "You do not follow that trade.", "missing": PackedStringArray()}
	var r := CareerLadders.promote(ladder_ctx(career, day))
	if bool(r["ok"]):
		ranks[career] = String(r["rank"])
		since[career] = day
		if sync_life and Life != null and Life.get("career_id") != null and String(Life.career_id) == career:
			Life.career_rank = String(r["rank"])
			Life.career_since_day = day
		_rep(career, 1.0)
		_say(String(r["text"]))
		if career == "soldier":
			_on_soldier_rank(day)
	return r


func _on_soldier_rank(_day_n: int) -> void:
	var cap := CareerLadders.troops_for_rank(rank_of("soldier"))
	squad["men"] = cap
	var cam := _mod("campaign")
	if cam != null and cam.has_method("set_player_rank"):
		cam.call("set_player_rank", CareerLadders.military_rank_for(rank_of("soldier")))


# ---------------------------------------------------------------- what can be done

func offers(career: String, day: int) -> Array:
	var out: Array = []
	var rk := CareerLadders.rank_index(career, rank_of(career)) if rank_of(career) != "" else -1
	var defs: Array = []
	match career:
		"farmer":
			defs = [["sow", "Sow and tend", "Choose the crop for the season, then tend it at the right moment.", 0],
				["tenant", "Settle a tenant", "Put a family on your land. They pay rent each week.", 4]]
		"soldier":
			defs = [["drill", "Drill with the squad", "Hold the beat, answer the sergeant.", 0],
				["squad", "Lead a squad mission", "Judge the enemy and give the right orders. Bad calls cost men.", 2],
				["muster", "Report to the muster", "Take a levy or a patrol from the captain. Needs soldier rank.", 2]]
		"merchant":
			defs = [["haggle", "Haggle with a customer", "Read the customer; every round counts.", 0],
				["stall", "Run the stall for a day", "Stock what the town wants today.", 0]]
		"blacksmith":
			defs = [["forge", "Forge a piece", "Heat and strike: skill decides the quality tier.", 0],
				["commission", "Take a commission", "A customer wants a minimum quality. Fail it and your name suffers.", 1]]
	for d: Array in defs:
		var why := ""
		var kind := String(d[0])
		if not ranks.has(career):
			why = "You do not follow this trade yet."
		elif rk < int(d[3]):
			why = "Needs a higher rank."
		elif hours_left(day) < float(TASK_HOURS[kind]):
			why = "You have worked enough today."
		elif kind == "tenant" and not bool(_flags().get("owns_plot", false)):
			why = "You need land of your own."
		elif kind == "tenant" and _gold() + pending_gold < TENANT_COST:
			why = "A family needs %dg to settle (roof and seed)." % TENANT_COST
		elif kind == "tenant" and int(estate.get("tenants", 0)) >= 8:
			why = "The land will bear no more families."
		elif kind == "muster" and rk < 2:
			why = "Needs soldier rank."
		out.append({"kind": kind, "label": String(d[1]), "text": String(d[2]), "hours": float(TASK_HOURS[kind]), "available": why == "", "why": why})
	return out


func _season_of(day: int) -> String:
	return ["spring", "summer", "autumn", "winter"][(day / 3) % 4]


func begin(career: String, kind: String, day: int, season := "") -> Dictionary:
	_day = maxi(_day, day)
	var off: Dictionary = {}
	for o: Dictionary in offers(career, day):
		if String(o["kind"]) == kind:
			off = o
	if off.is_empty():
		return {"ok": false, "reason": "Nothing like that to do."}
	if not bool(off["available"]):
		return {"ok": false, "reason": String(off["why"])}
	if not task.is_empty() and int(task.get("day", -1)) == day:
		return {"ok": false, "reason": "Finish the work in front of you first."}
	_counter += 1
	var r := _rng("ttask", day, "%s%s%d" % [career, kind, _counter])
	var steps: Array = []
	var meta := {}
	var lv := level(career)
	match kind:
		"sow":
			var sea := season if season != "" else _season_of(day)
			var crops: Dictionary = SEASON_CROPS[sea]
			var names: Array = crops.keys()
			var demand := String(names[r.randi() % names.size()])
			var opts: Array = []
			for c: String in names:
				var q := 0.55 * float(crops[c]) + 0.3 + (0.15 if c == demand else 0.0)
				opts.append({"text": "Sow %s%s" % [c, "  (the market is short of it)" if c == demand else ""], "q": clampf(q, 0.0, 1.0)})
			steps = [{"widget": "choice", "text": "It is %s. What do you put in the ground?" % sea, "options": opts},
				{"widget": "timing", "text": "Water and weed at the right moment.", "diff": 0.4}]
			meta = {"season": sea, "demand": demand}
		"tenant":
			steps = [{"widget": "choice", "text": "A family asks to settle on your land.", "options": [
				{"text": "Take them at a fair rent (%dg a week)" % TENANT_RENT, "q": 0.9},
				{"text": "Ask double (they may leave)", "q": 0.5}, {"text": "Let them stay rent-free this season", "q": 0.7}]}]
		"drill":
			steps = [{"widget": "timing", "text": "The sergeant beats the line. Step with it.", "diff": 0.5},
				{"widget": "choice", "text": "\"Spear!\" bellows the sergeant. \"Where does your point go?\"", "options": [
					{"text": "At the knee of the man opposite", "q": 0.4}, {"text": "Over the shield rim, at the throat", "q": 0.85}, {"text": "Into the ground", "q": 0.1}]}]
		"squad":
			var ek: Array = ENEMIES.keys()
			var enemy := String(ek[r.randi() % ek.size()])
			var def: Dictionary = ENEMIES[enemy]
			steps = [{"widget": "choice", "text": "Scouts report: %s. How do you approach?" % enemy, "options": _shuffled_opts(r, String(def["approach"]), APPROACH_WRONG)},
				{"widget": "choice", "text": "Contact. What is the stand?", "options": _shuffled_opts(r, String(def["stand"]), STAND_WRONG)}]
			meta = {"enemy": enemy, "men": maxi(int(squad.get("men", 0)), 4)}
		"muster":
			pass
		"haggle":
			var mood := String(["impatient", "fond of the goods", "a hard bargainer"][r.randi() % 3])
			var best := 1 if mood == "fond of the goods" else (0 if mood == "impatient" else 2)
			var texts := ["Name a low, fair price at once", "Ask a little over fair", "Open high and give ground slowly"]
			var rounds: Array = []
			for i in 3:
				var o2: Array = []
				for k in 3:
					o2.append({"text": texts[k], "q": 0.95 if k == best else (0.55 if absi(k - best) == 1 else 0.2)})
				rounds.append({"widget": "choice", "text": "The customer is %s. Round %d." % [mood, i + 1], "options": o2})
			steps = rounds
			meta = {"mood": mood}
		"stall":
			var hot := String(["cloth", "tools", "bread", "salt", "candles"][r.randi() % 5])
			var goods := ["cloth", "tools", "bread", "salt", "candles"]
			var opts2: Array = []
			for g: String in goods:
				opts2.append({"text": "Stock %s%s" % [g, "  (people are asking for it)" if g == hot else ""], "q": 0.9 if g == hot else 0.35 + 0.1 * float(r.randi() % 3)})
			steps = [{"widget": "choice", "text": "Market day. What goes on the stall?", "options": opts2},
				{"widget": "timing", "text": "Call the crowd at the right moment.", "diff": 0.35}]
			meta = {"hot": hot}
		"forge":
			steps = [{"widget": "timing", "text": "Read the colour of the steel. Strike at cherry red.", "diff": 0.45},
				{"widget": "timing", "text": "Draw it out with even blows.", "diff": 0.55}]
			meta = {"piece": String(PIECES[r.randi() % PIECES.size()])}
		"commission":
			var rk2 := CareerLadders.rank_index(career, rank_of(career))
			var min_tier := 0 if rk2 <= 1 else (1 if rk2 <= 3 else 2)
			steps = [{"widget": "timing", "text": "Heat the billet evenly.", "diff": 0.5}, {"widget": "timing", "text": "Strike and fold.", "diff": 0.55},
				{"widget": "timing", "text": "Quench at the right moment.", "diff": 0.6}]
			meta = {"piece": String(PIECES[r.randi() % PIECES.size()]), "min_tier": min_tier, "reward": 30 + 25 * min_tier * (1 + rk2)}
	task = {"career": career, "kind": kind, "day": day, "steps": steps, "i": 0, "qs": [], "meta": meta, "level": lv, "seed": _counter}
	return {"ok": true, "reason": "", "view": task_view()}


func _shuffled_opts(r: RandomNumberGenerator, right: String, wrong: Array) -> Array:
	var w: Array = wrong.duplicate()
	var opts: Array = [{"text": right, "q": 0.95}]
	for i in 2:
		opts.append({"text": String(w.pop_at(r.randi() % w.size())), "q": 0.15 + 0.15 * float(i)})
	var out: Array = []
	while not opts.is_empty():
		out.append(opts.pop_at(r.randi() % opts.size()))
	return out


## The open step without hidden qualities.
func task_view() -> Dictionary:
	if task.is_empty():
		return {}
	var i := int(task["i"])
	var steps: Array = task["steps"]
	if i >= steps.size():
		return {}
	var st: Dictionary = (steps[i] as Dictionary).duplicate(true)
	if st.has("options"):
		for o: Dictionary in st["options"]:
			o.erase("q")
	var career := String(task["career"])
	st["career"] = career
	st["kind"] = String(task["kind"])
	st["step"] = i
	st["of"] = steps.size()
	if String(st["widget"]) == "timing":
		var d := float(st.get("diff", 0.5))
		st["zone"] = clampf(0.34 - 0.22 * d + float(int(task["level"]) - 1) * 0.0025, 0.08, 0.42)
		st["zone_at"] = 0.3 + _rng("tzone", int(task["day"]), "%d%d" % [int(task["seed"]), i]).randf() * 0.5
	st["title"] = _title(String(task["kind"]), task["meta"])
	return st


func _title(kind: String, meta: Dictionary) -> String:
	match kind:
		"sow":
			return "Sow and tend (%s)" % String(meta.get("season", ""))
		"squad":
			return "Squad mission: %s" % String(meta.get("enemy", ""))
		"forge", "commission":
			return "Forge %s" % String(meta.get("piece", "a piece"))
		"haggle":
			return "Haggle"
		"stall":
			return "Market stall"
		"drill":
			return "Drill"
		"tenant":
			return "A new tenant"
	return kind.capitalize()


func abandon_task() -> void:
	task = {}


## value: a quality 0..1 for a timing step, an option index for a choice step.
## Returns {ok, done, next (view) | result...}.
func submit(value: float) -> Dictionary:
	if task.is_empty():
		return {"ok": false, "reason": "No work in hand."}
	var i := int(task["i"])
	var steps: Array = task["steps"]
	var st: Dictionary = steps[i]
	var q := 0.0
	if String(st["widget"]) == "choice":
		var opts: Array = st["options"]
		q = float(opts[clampi(int(value), 0, opts.size() - 1)]["q"])
	else:
		q = clampf(value, 0.0, 1.0)
	(task["qs"] as Array).append(q)
	task["i"] = i + 1
	if i + 1 < steps.size():
		return {"ok": true, "done": false, "next": task_view()}
	return _finalize()


func _spend(kind: String, day: int) -> void:
	hours_used[str(day)] = float(hours_used.get(str(day), 0.0)) + float(TASK_HOURS.get(kind, 1.0))
	if hours_used.size() > 6:
		var keys: Array = hours_used.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		hours_used.erase(keys[0])


func _finalize() -> Dictionary:
	var career := String(task["career"])
	var kind := String(task["kind"])
	var day := int(task["day"])
	var meta: Dictionary = task["meta"]
	var qs: Array = task["qs"]
	var q := 0.0
	for x: Variant in qs:
		q += float(x)
	q = q / float(maxi(qs.size(), 1))
	var res := {"ok": true, "done": true, "career": career, "kind": kind, "quality": q, "gold": 0, "texts": []}
	var texts: Array = res["texts"]
	_gain(career, XP * (0.4 + 0.6 * q), day)
	_spend(kind, day)
	var lv := int(task["level"])
	var gold := 0
	match kind:
		"sow":
			var base := 10.0 + float(lv) / 3.0
			gold = int(round(base * (0.4 + q)))
			var share := 0
			if is_tenant():
				share = int(round(float(gold) * float(_lease_share())))
				gold -= share
				texts.append("Your landlord's share of the crop: %dg." % share)
			bump(career, "sown")
			if q >= 0.4:
				bump(career, "harvests")
			else:
				texts.append("The crop is thin. Wrong seed for the season, or poor care.")
			_rep(career, 0.4 * q - (0.3 if q < 0.3 else 0.0))
			res["text"] = "%s harvest: quality %d%%, %dg." % [String(meta["season"]).capitalize(), int(q * 100.0), gold]
		"tenant":
			estate["tenants"] = int(estate.get("tenants", 0)) + (1 if q >= 0.6 else 0)
			if q >= 0.6:
				pending_gold -= TENANT_COST
				gold = -TENANT_COST
				texts.append("A family moves in. The cost of a roof and seed: %dg." % TENANT_COST)
			else:
				texts.append("The family goes elsewhere.")
			res["text"] = "Tenants on your land: %d." % int(estate.get("tenants", 0))
		"drill":
			if q >= 0.5:
				bump(career, "drills")
			_rep(career, 0.15 * q)
			res["text"] = "Drill: %d%%." % int(q * 100.0)
		"squad":
			var men := int(meta["men"])
			var lost := int(round((1.0 - q) * float(men) * 0.5))
			squad["men"] = maxi(0, int(squad.get("men", men)) - lost) if int(squad.get("men", 0)) > 0 else 0
			squad["lost"] = int(squad.get("lost", 0)) + lost
			if q >= 0.5:
				bump(career, "squad_missions")
			gold = int(round(14.0 * q))
			_rep(career, (q - 0.4) * 3.0)
			texts.append("%d of %d men lost." % [lost, men] if lost > 0 else "Not a man lost.")
			if q < 0.3:
				_say("Your squad was mauled by %s." % String(meta["enemy"]))
			res["text"] = "%s: %s." % [String(meta["enemy"]).capitalize(), "victory" if q >= 0.6 else ("a costly day" if q >= 0.35 else "a rout")]
			res["lost"] = lost
		"haggle":
			gold = int(round((8.0 + float(lv) * 0.4) * (0.3 + 1.2 * q)))
			if q >= 0.4:
				bump(career, "deals")
			_rep(career, 0.3 * q - (0.3 if q < 0.3 else 0.0))
			res["text"] = "Deal: %dg at %d%% of the best price." % [gold, int(q * 100.0)]
		"stall":
			gold = int(round((14.0 + float(lv) * 0.5) * (0.3 + 1.2 * q)))
			if q >= 0.4:
				bump(career, "stall_days")
				bump(career, "deals", 1)
			res["text"] = "Stall takings: %dg." % gold
		"forge", "commission":
			var rk := CareerLadders.rank_index(career, rank_of(career))
			var rec_level := clampi(8 + rk * 9, 1, 60)
			# Heat and strike are the roll; skill shifts the odds (crafting.gd), but a botched strike is always rough.
			var tier := 0 if q < 0.35 else Crafting.quality_for_roll(lv, rec_level, clampf(1.0 - q, 0.0, 0.999))
			res["tier"] = tier
			res["tier_name"] = String(TIER_NAMES[tier])
			bump(career, "pieces")
			if tier >= 1:
				bump(career, "good_pieces")
			if tier >= 2:
				bump(career, "fine_pieces")
			gold = int(round((9.0 + float(lv) * 0.3) * (0.7 + 0.5 * float(tier))))
			if kind == "commission":
				if tier >= int(meta["min_tier"]):
					gold += int(meta["reward"])
					bump(career, "commissions")
					_rep(career, 1.5)
					texts.append("The customer is satisfied with %s." % String(meta["piece"]))
				else:
					gold = -10
					_rep(career, -1.5)
					texts.append("The customer wanted at least %s and gets %s. He will tell others." % [TIER_NAMES[int(meta["min_tier"])], TIER_NAMES[tier]])
			else:
				_rep(career, 0.2 * float(tier))
			res["text"] = "%s %s." % [String(TIER_NAMES[tier]).capitalize(), String(meta.get("piece", "piece"))]
	pending_gold += gold if kind != "tenant" else 0
	res["gold"] = gold
	task = {}
	return res


# ---------------------------------------------------------------- tenancy, estate, muster

## True while homestead.gd holds a lease for the player and no plot is owned.
func is_tenant() -> bool:
	var hs := _homestead()
	if hs == null:
		return not tenancy.is_empty()
	return not (hs.get("leased") as Dictionary).is_empty() and (hs.get("owned") as Dictionary).is_empty()


func _lease_share() -> float:
	var hs := _homestead()
	return float(hs.get("LEASE_SHARE")) if hs != null and hs.get("LEASE_SHARE") != null else 0.25


## Lease a plot through homestead.gd (its rent and landlord share apply). Returns "" or the refusal.
func take_tenancy(plot: int, day: int) -> String:
	if not ranks.has("farmer"):
		return "You are not a farmer."
	if not tenancy.is_empty():
		return "You already hold a lease."
	var hs := _homestead()
	if hs != null:
		var why := String(hs.call("can_lease", plot))
		if why != "":
			return why
		hs.call("lease", plot)
	tenancy = {"plot": plot, "since": day, "weeks": 0}
	return ""


## Buy land through homestead.gd (it charges Game.gold). Returns "" on success or the refusal.
func buy_land(plot: int) -> String:
	var hs := _homestead()
	if hs == null:
		return "There is no land to buy."
	var why := String(hs.call("can_buy", plot))
	if why != "":
		return why
	var msg := String(hs.call("buy", plot))
	if not bool(hs.call("is_owned", plot)):
		return msg
	tenancy = {}
	return ""


## Muster for the campaign: a levy when the realm is at war, else a patrol from the captain.
func muster(day: int) -> Dictionary:
	var off := offers("soldier", day)
	for o: Dictionary in off:
		if String(o["kind"]) == "muster" and not bool(o["available"]):
			return {"ok": false, "reason": String(o["why"])}
	var cu := _mod("callups")
	if cu == null:
		return {"ok": false, "reason": "No captain has orders for you."}
	var war := at_war_ref or _at_war()
	var tid := "militia_levy" if war else "bandit_patrol"
	var offer: Dictionary = cu.call("raise_offer", tid, day, 0, "the muster")
	_spend("muster", day)
	if offer.is_empty():
		return {"ok": false, "reason": "Nothing needs you at the muster today."}
	var cam := _mod("campaign")
	if cam != null and cam.has_method("set_player_rank"):
		cam.call("set_player_rank", CareerLadders.military_rank_for(rank_of("soldier")))
	return {"ok": true, "offer": offer, "levy": war, "text": "The captain hands you a %s." % ("levy order" if war else "patrol")}


## The soldier's call-up was carried out: the campaign counts it.
func muster_done(offer_id: String, quality: float, day: int) -> Dictionary:
	var cu := _mod("callups")
	var r: Dictionary = cu.call("complete", offer_id, quality) if cu != null else {"ok": false}
	if bool(r.get("ok", false)) and quality >= 0.5:
		bump("soldier", "campaign_actions")
		_rep("soldier", 1.0 * quality)
		_gain("soldier", XP * 0.6, day)
	return r


# ---------------------------------------------------------------- ticks

func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return []


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var out: Array = []
	if not task.is_empty() and int(task.get("day", day)) < day:
		task = {}
	for c: String in CAREERS:
		if ranks.has(c) and not CareerLadders.next_rank_def(c, rank_of(c)).is_empty():
			if bool(status(c, day)["eligible"]):
				var r := promote(c, day)
				if bool(r["ok"]):
					out.append("%s: %s" % [String(TITLE[c]), String(r["text"])])
	return out


func tick_week(week: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	var day := week * 7
	if not tenancy.is_empty():
		if is_tenant():
			tenancy["weeks"] = int(tenancy["weeks"]) + 1
			bump("farmer", "rent_weeks")
		else:
			var hs2 := _homestead()
			var owns := hs2 != null and not (hs2.get("owned") as Dictionary).is_empty()
			tenancy = {}
			if not owns:
				_rep("farmer", -3.0)
				if ranks.has("farmer") and rank_of("farmer") == "tenant_farmer":
					ranks["farmer"] = "field_hand"
					since["farmer"] = day
					if sync_life and Life != null and Life.get("career_id") != null and String(Life.career_id) == "farmer":
						Life.career_rank = "field_hand"
				out.append("The landlord has taken the plot back: the rent was not paid. You are a field hand again.")
	if int(estate.get("tenants", 0)) > 0:
		pending_gold += int(estate["tenants"]) * TENANT_RENT
		estate["weeks"] = int(estate.get("weeks", 0)) + 1
	return out


func catch_up(days: int, _ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	var weeks := days / 7
	if int(estate.get("tenants", 0)) > 0:
		pending_gold += int(estate["tenants"]) * TENANT_RENT * weeks
	if not tenancy.is_empty() and is_tenant():
		tenancy["weeks"] = int(tenancy["weeks"]) + weeks
		bump("farmer", "rent_weeks", weeks)
	return []


func serialize() -> Dictionary:
	return {"pending_gold": pending_gold, "ranks": ranks.duplicate(), "since": since.duplicate(), "stats": stats.duplicate(true), "tenancy": tenancy.duplicate(),
		"estate": estate.duplicate(), "squad": squad.duplicate(), "task": task.duplicate(true), "hours_used": hours_used.duplicate(), "log": log_lines.duplicate(),
		"day": _day, "counter": _counter}


func deserialize(d: Dictionary) -> void:
	pending_gold = int(d.get("pending_gold", 0))
	ranks = (d.get("ranks", {}) as Dictionary).duplicate()
	since = {}
	for k: String in (d.get("since", {}) as Dictionary):
		since[k] = int(d["since"][k])
	stats = {}
	for c: String in (d.get("stats", {}) as Dictionary):
		var s: Dictionary = {}
		for k2: String in d["stats"][c]:
			s[k2] = int(d["stats"][c][k2])
		stats[c] = s
	tenancy = (d.get("tenancy", {}) as Dictionary).duplicate()
	for k3: String in ["plot", "weeks", "since"]:
		if tenancy.has(k3):
			tenancy[k3] = int(tenancy[k3])
	estate = (d.get("estate", {}) as Dictionary).duplicate()
	for k4: String in estate:
		estate[k4] = int(estate[k4])
	squad = {"men": int((d.get("squad", {}) as Dictionary).get("men", 0)), "lost": int((d.get("squad", {}) as Dictionary).get("lost", 0))}
	task = (d.get("task", {}) as Dictionary).duplicate(true)
	hours_used = (d.get("hours_used", {}) as Dictionary).duplicate()
	log_lines = (d.get("log", []) as Array).duplicate()
	_day = int(d.get("day", 0))
	_counter = int(d.get("counter", 0))
