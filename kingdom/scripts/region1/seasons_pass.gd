extends RefCounted
## READY_V1 C3: the "seasons pass" card. Some story steps wait on time: the years (an `age` objective) or a festival date.
## A player used to see nothing of this and the headless bot cheated both with [HOOK]s. Now, when the player sleeps while such a
## gate is the active step's open objective, a card offers to let the seasons turn: the character ages to the gate's age, or
## the calendar runs on to the festival evening. Everything else (the ageing body, Kindling Night) then happens through the
## ordinary signals (Life.life_path, Seasons.festival_started).
##   var g := SeasonsPass.gate(story, ctx)          # {} or {kind: "age"|"festival", step, min | festival}
##   LifeEventPopup.present(hud, SeasonsPass.card(g, on_done))
##   SeasonsPass.apply(g, player)                    # what the card's choice calls

const FESTIVAL_IDS := {"kindling_night": "Kindling Night"}
const WAKE_HOUR := 7.4
const EVENING_HOUR := 18.5


## The first active step whose open objective waits on the years or on a festival. `story` = Region1StoryQuest, `ctx` its condition ctx.
static func gate(story: RefCounted, ctx: Dictionary) -> Dictionary:
	if story == null:
		return {}
	var age := int(ctx.get("age", 0))
	for sid: String in story.active_steps():
		var o: Dictionary = story.current_objective(sid)
		match String(o.get("type", "")):
			"age":
				if age < int(o.get("min", 0)):
					return {"kind": "age", "step": sid, "min": int(o["min"]), "from": age}
			"festival":
				return {"kind": "festival", "step": sid, "festival": String(o["festival"])}
	return {}


static func card(g: Dictionary, on_done := Callable()) -> Dictionary:
	var apply_cb := func() -> void:
		var p: Node3D = Life.player if Life.player != null and is_instance_valid(Life.player) else null
		apply(g, p)
		if on_done.is_valid():
			on_done.call()
	if String(g["kind"]) == "age":
		return {"title": "The seasons pass",
			"body": "You sleep, and the seasons turn. Years go by in the Vale: you wake taller, at the age of %d." % int(g["min"]),
			"choices": [["Let the years pass.", apply_cb], ["Not yet.", Callable()]]}
	var nm := String(FESTIVAL_IDS.get(String(g["festival"]), "the festival"))
	return {"title": "The seasons pass",
		"body": "You sleep through the days until %s. The lanterns are being hung when you wake." % nm,
		"choices": [["Wake for %s." % nm, apply_cb], ["Not yet.", Callable()]]}


## Ages the character / runs the calendar to the festival. `player` may be null (tests).
static func apply(g: Dictionary, player: Node3D = null) -> void:
	match String(g.get("kind", "")):
		"age":
			WorldSim.time_of_day = WAKE_HOUR
			Life.life_path.set_age(int(g["min"]), WorldSim.day, WorldSim.time_of_day)
			if player != null and player.has_method("apply_age"):
				player.apply_age()
			WorldSim.advance_hours(0.1)
			if Life.realm != null:
				Life.realm.drain()
		"festival":
			var se = WorldSim.seasons
			if se == null:
				return
			var want := String(g["festival"])
			var f: Dictionary = se.festival_today()
			if String(f.get("id", "")) != want:
				f = {}
				for k in se.DAYS_PER_YEAR:
					var cand: Dictionary = se.festival_on(se.current_day() + k)
					if String(cand.get("id", "")) == want:
						se.day_offset += k
						f = cand
						break
			if f.is_empty():
				return
			WorldSim.time_of_day = EVENING_HOUR
			se.deserialize({"offset": se.day_offset})   # re-syncs the calendar so the day change is not announced twice
			se.festival_started.emit(f)
