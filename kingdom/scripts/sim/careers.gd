class_name RACareers
extends RefCounted
## Careers with real vacancies. An organisation (the Ashford Guard, the smithy,
## the inn...) has a fixed number of seats per rank. Seats are held by real
## WorldSim people or by the player; you can only join where a seat is open.
## Seats open when holders retire, die or are promoted, and close again when
## local applicants take them. Rank is a seat, not a level: a strong fighter
## is still a Guard until a Sergeant's seat opens and they have the merit.
##
## Pure data (serializable); the Life autoload drives it once per day.

signal vacancy_opened(org: Dictionary, seat: Dictionary)
signal seat_filled(org: Dictionary, seat: Dictionary, holder: int)
signal player_changed(text: String)

const PLAYER := -1
## Share of the shift the player must attend to be paid.
const ATTENDANCE_TO_PAY := 0.6
const STRIKES_TO_DISMISS := 3

## Org: {id, name, settlement, recruiter, post {x,y,r}, shift [start, end), job,
##       seats: [{title, wage, count, command, merit, holders: Array[int]}]}
## Seats are ordered from most to least senior.
var orgs: Array[Dictionary] = []
## The player's employment: {org, seat, attended (hours), strikes, since (day)} or empty.
var player := {}
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 1066) -> void:
	_rng.seed = seed_value


func add_org(id: String, org_name: String, settlement: int, recruiter: String, post: Vector3,
		shift: Vector2, job: int, seats: Array) -> Dictionary:
	var org := {"id": id, "name": org_name, "settlement": settlement, "recruiter": recruiter,
		"post": post, "shift": shift, "job": job, "seats": []}
	for s: Dictionary in seats:
		org["seats"].append({"title": s["title"], "wage": s["wage"], "count": s["count"],
			"command": s.get("command", 0), "merit": s.get("merit", 0), "holders": []})
	orgs.append(org)
	return org


func org(id: String) -> Dictionary:
	for o in orgs:
		if o["id"] == id:
			return o
	return {}


func seat(org_id: String, title: String) -> Dictionary:
	for s: Dictionary in org(org_id).get("seats", []):
		if s["title"] == title:
			return s
	return {}


func open_count(s: Dictionary) -> int:
	return int(s["count"]) - s["holders"].size()


## Open seats of an org as [{seat, open}], most senior first.
func vacancies(org_id: String) -> Array:
	var out := []
	for s: Dictionary in org(org_id).get("seats", []):
		if open_count(s) > 0:
			out.append({"seat": s, "open": open_count(s)})
	return out


func is_employed() -> bool:
	return not player.is_empty()


func player_seat() -> Dictionary:
	return seat(player["org"], player["seat"]) if is_employed() else {}


func player_org() -> Dictionary:
	return org(player["org"]) if is_employed() else {}


## Why the player can't take a seat, or "" if they can.
func check_application(org_id: String, title: String, merit: int) -> String:
	var s := seat(org_id, title)
	if s.is_empty():
		return "There is no such post."
	if is_employed() and player["org"] == org_id and player["seat"] == title:
		return "You already hold that post."
	if open_count(s) <= 0:
		return "No %s seat is open. All %d are taken." % [s["title"], s["count"]]
	if merit < int(s["merit"]):
		return "A %s needs %d merit; you have %d." % [s["title"], s["merit"], merit]
	return ""


## Player takes an open seat (leaving any current one). Returns "" or the refusal.
func apply(org_id: String, title: String, merit: int, day: int) -> String:
	var why := check_application(org_id, title, merit)
	if why != "":
		return why
	if is_employed():
		_vacate(player_seat(), PLAYER)
	var s := seat(org_id, title)
	s["holders"].append(PLAYER)
	player = {"org": org_id, "seat": title, "attended": 0.0, "strikes": 0, "since": day}
	var o := org(org_id)
	seat_filled.emit(o, s, PLAYER)
	player_changed.emit("You are now a %s of %s." % [title, o["name"]])
	return ""


func resign() -> void:
	if not is_employed():
		return
	var o := player_org()
	_vacate(player_seat(), PLAYER)
	player = {}
	player_changed.emit("You leave %s." % o["name"])


func is_on_shift(hour: float) -> bool:
	if not is_employed():
		return false
	var sh: Vector2 = player_org()["shift"]
	return hour >= sh.x and hour < sh.y


## Is p inside the player's duty post?
func at_post(p: Vector2) -> bool:
	if not is_employed():
		return false
	var post: Vector3 = player_org()["post"]
	return p.distance_to(Vector2(post.x, post.y)) <= post.z


## Called with the in-game hours that passed while the player was at their post on shift.
func log_attendance(hours: float) -> void:
	if is_employed():
		player["attended"] = float(player["attended"]) + hours


## End of the working day: pays the player if they attended, otherwise a strike.
## Returns {paid, text}.
func pay_day() -> Dictionary:
	if not is_employed():
		return {"paid": 0, "text": ""}
	var s := player_seat()
	var sh: Vector2 = player_org()["shift"]
	var ratio: float = float(player["attended"]) / maxf(sh.y - sh.x, 0.01)
	player["attended"] = 0.0
	if ratio >= ATTENDANCE_TO_PAY:
		return {"paid": int(s["wage"]), "text": "Wages: %d gold as %s." % [s["wage"], s["title"]]}
	player["strikes"] = int(player["strikes"]) + 1
	if int(player["strikes"]) >= STRIKES_TO_DISMISS:
		var name := String(player_org()["name"])
		_vacate(s, PLAYER)
		player = {}
		return {"paid": 0, "text": "Dismissed from %s for missing duty." % name}
	return {"paid": 0, "text": "You missed your shift (%d%% attended). Strike %d of %d." % [
		int(ratio * 100), player["strikes"], STRIKES_TO_DISMISS]}


## Promotion into the next more senior seat, if one is open and merit allows.
func promotion_for_player(merit: int) -> Dictionary:
	if not is_employed():
		return {}
	var seats: Array = player_org()["seats"]
	for i in seats.size():
		if seats[i]["title"] == player["seat"]:
			if i == 0:
				return {}
			var up: Dictionary = seats[i - 1]
			if open_count(up) > 0 and merit >= int(up["merit"]):
				return up
			return {}
	return {}


## Seed seats with local people, deliberately leaving some open.
## `candidates(settlement) -> PackedInt32Array` returns people who could work there.
## `fill_ratio` per org id (default 0.75) sets how full it starts.
func staff(candidates: Callable, fill_ratio: Dictionary = {}) -> void:
	var taken := {}
	for o in orgs:
		var pool: PackedInt32Array = candidates.call(o["settlement"], o["job"])
		var k := 0
		for s: Dictionary in o["seats"]:
			var want := int(round(float(s["count"]) * float(fill_ratio.get(o["id"], 0.75))))
			if int(s["count"]) == 1:
				want = 1
			while s["holders"].size() < want and k < pool.size():
				var who := pool[k]
				k += 1
				if taken.has(who):
					continue
				taken[who] = true
				s["holders"].append(who)


## One day passes: some NPC holders leave (retire, move, die), senior seats are
## back-filled from below, and local applicants take some open seats.
## `hire(org) -> int` supplies a new local person id or -2 if nobody applies.
func tick_day(hire: Callable, leave_chance := 0.015, apply_chance := 0.2) -> void:
	for o in orgs:
		var seats: Array = o["seats"]
		for s: Dictionary in seats:
			for who: int in s["holders"].duplicate():
				if who != PLAYER and _rng.randf() < leave_chance:
					_vacate(s, who)
					vacancy_opened.emit(o, s)
		# Seniority: the longest-serving NPC below moves up into an open seat.
		for i in range(seats.size() - 1):
			var up: Dictionary = seats[i]
			var down: Dictionary = seats[i + 1]
			while open_count(up) > 0:
				var moved := -2
				for who: int in down["holders"]:
					if who != PLAYER:
						moved = who
						break
				if moved == -2:
					break
				down["holders"].erase(moved)
				up["holders"].append(moved)
				seat_filled.emit(o, up, moved)
				vacancy_opened.emit(o, down)
		# Only the most junior seat hires from outside.
		var junior: Dictionary = seats[seats.size() - 1]
		if open_count(junior) > 0 and _rng.randf() < apply_chance:
			var who: int = hire.call(o)
			if who >= 0:
				junior["holders"].append(who)
				seat_filled.emit(o, junior, who)


## Seats a person from outside the normal hire pool (e.g. a life_courses.gd
## notable) into an open seat. `who` only needs to not collide with a real
## WorldSim index or PLAYER (-1); life_courses.gd encodes its own ids well
## below either. Returns false if the seat doesn't exist or has no room.
func fill_vacancy_with(org_id: String, title: String, who: int) -> bool:
	var s := seat(org_id, title)
	if s.is_empty() or open_count(s) <= 0:
		return false
	s["holders"].append(who)
	seat_filled.emit(org(org_id), s, who)
	return true


## A holder died or left for reasons outside the sim (killed by wolves...).
func remove_person(who: int) -> void:
	for o in orgs:
		for s: Dictionary in o["seats"]:
			if who in s["holders"]:
				_vacate(s, who)
				vacancy_opened.emit(o, s)


func holder_of(who: int) -> Dictionary:
	for o in orgs:
		for s: Dictionary in o["seats"]:
			if who in s["holders"]:
				return {"org": o, "seat": s}
	return {}


func _vacate(s: Dictionary, who: int) -> void:
	s["holders"].erase(who)


func serialize() -> Dictionary:
	var seats := {}
	for o in orgs:
		for s: Dictionary in o["seats"]:
			seats["%s/%s" % [o["id"], s["title"]]] = Array(s["holders"])
	return {"seats": seats, "player": player.duplicate()}


func deserialize(data: Dictionary) -> void:
	var seats: Dictionary = data.get("seats", {})
	for o in orgs:
		for s: Dictionary in o["seats"]:
			var key := "%s/%s" % [o["id"], s["title"]]
			if seats.has(key):
				s["holders"].clear()
				for who in seats[key]:
					s["holders"].append(int(who))
	player = (data.get("player", {}) as Dictionary).duplicate()
	if player.has("strikes"):
		player["strikes"] = int(player["strikes"])
