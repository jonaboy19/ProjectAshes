class_name VillageServices
extends Node3D
## The starting village's places to live a life: the market stall, the inn,
## the notice board (jobs with real vacancies) and the Captain's office.
## Each is a Station whose menu reads and drives the Life autoload.

const MEGAKIT := "res://assets/incoming/quaternius/fantasy-props-megakit/Exports/glTF/"
const BOARD := "res://assets/generated/notice_board.glb"
const BED_PRICE := 3

var hud: HUD
var guild_station: Station
var captain: Captain
var soldiers: Callable      # () -> int, current company size
var recruit: Callable       # (count) -> void


func setup(p_hud: HUD, p_captain: Captain, p_soldiers: Callable, p_recruit: Callable) -> void:
	hud = p_hud
	captain = p_captain
	soldiers = p_soldiers
	recruit = p_recruit


func _ready() -> void:
	var home: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = home["pos"]
	var plan: Dictionary = home["plan"]
	var pr: float = plan["plaza_r"]
	# Merchant in front of the first plaza stall (see SettlementBuilder).
	var ang := 0.2
	var stall := c + Vector2(cos(ang), sin(ang)) * (pr - 4.6)
	_person("Market Trader", "Trade", merchant_menu, stall, c, "Rogue")
	_prop("Barrel_Apples", stall + Vector2(-sin(ang), cos(ang)) * 1.6, 1.0)
	_prop("FarmCrate_Apple", stall + Vector2(sin(ang), -cos(ang)) * 1.5, 1.0)
	# Innkeeper at the inn's door.
	for lot: Dictionary in plan["lots"]:
		if lot["asset"] == "inn":
			var yaw: float = lot["yaw"]
			var door: Vector2 = lot["pos"] + Vector2(sin(yaw), cos(yaw)) * 5.2
			_person("%s Inn" % home["name"], "Enter", inn_menu, door, door + Vector2(sin(yaw), cos(yaw)), "Mage")
			break
	# Adventurer Guild desk and the village herbalist on the plaza's far side.
	var guild_at := c + Vector2(-4.0, -9.0)
	guild_station = _person("Adventurer Guild", "Guild", guild_menu, guild_at, c, "Rogue_Hooded")
	var herb_at := c + Vector2(9.0, -7.5)
	_person("Herbalist", "Healer", healer_menu, herb_at, c, "Mage")
	_prop("Barrel", herb_at + Vector2(1.2, -0.8), 1.0)
	# Notice board beside the well, facing the spawn road.
	var board_pos := c + Vector2(3.5, -3.0)
	var board := Station.new("Notice Board", "Read", notice_menu)
	add_child(board)
	board.global_position = _ground(board_pos)
	var model: Node3D = (load(BOARD) as PackedScene).instantiate()
	board.add_child(model)
	board.look_at(_ground(board_pos + Vector2(-1.0, 3.0)), Vector3.UP, true)
	board.rotate_y(PI)


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _person(title: String, verb: String, menu: Callable, at: Vector2, face: Vector2, look: String) -> Station:
	var st := Station.new(title, verb, menu)
	add_child(st)
	st.global_position = _ground(at)
	var body := Assets.character(look, 1.74, [])
	st.add_child(body)
	var anim := Assets.animation_player(body)
	if anim:
		anim.play("Idle" if anim.has_animation("Idle") else anim.get_animation_list()[0])
	var to := face - at
	st.rotation.y = atan2(to.x, to.y)
	return st


func _prop(item: String, at: Vector2, scale_by: float) -> void:
	var path := MEGAKIT + item + ".gltf"
	if not ResourceLoader.exists(path):
		return
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.scale = Vector3.ONE * scale_by
	add_child(n)
	n.global_position = _ground(at)
	n.rotation.y = randf() * TAU


# --- menus ---------------------------------------------------------------------

func merchant_menu() -> Dictionary:
	var m := Life.market
	var opts: Array = []
	for item: String in ["bread", "apple", "cheese", "bandage", "firewood"]:
		opts.append(["Buy %s  —  %dg  (%d in stock)" % [Life.item_name(item), m.price(item), m.stock[item]],
			Life.buy.bind(item), m.can_buy(item, Game.gold) == ""])
	for item: String in ["wolf_pelt", "wolf_meat", "firewood"]:
		var n := Life.count(item)
		if n > 0:
			opts.append(["Sell %s ×%d  —  %dg each" % [Life.item_name(item), n, m.sell_price(item)],
				Life.sell.bind(item), m.purse >= m.sell_price(item)])
	return {"title": "Market Trader",
		"body": "\"Fresh from the farms. Pelts wanted: the tanner's short.\"\nYou carry %d gold. Trader's purse: %d gold." % [Game.gold, m.purse],
		"options": opts}


func inn_menu() -> Dictionary:
	var n := Life.needs
	var opts: Array = [
		["Hot stew  —  %dg" % Life.market.price("stew"), _buy_stew, Life.market.can_buy("stew", Game.gold) == ""],
		["Rent a bed and sleep  —  %dg" % BED_PRICE, _rent_bed, Game.gold >= BED_PRICE and n.rest < 90.0],
	]
	var server := Life.careers.seat("inn", "Server")
	if not Life.careers.is_employed() and Life.careers.open_count(server) > 0:
		opts.append(["Ask for work as a Server (%dg/day)" % server["wage"], _apply.bind("inn", "Server")])
	return {"title": "%s Inn" % WorldGen.settlements[0]["name"],
		"body": "The common room smells of smoke and onions.\nYou are %s and %s. It is %02d:00." % [
			n.hunger_label().to_lower(), n.rest_label().to_lower(), int(WorldSim.time_of_day)],
		"options": opts}


func _buy_stew() -> String:
	var msg := Life.buy("stew")
	return Life.use_item("stew") if msg.begins_with("Bought") else msg


func _rent_bed() -> String:
	Game.add_gold(-BED_PRICE)
	hud.close_menu()
	return Life.sleep(1.0)


func notice_menu() -> Dictionary:
	var lines := PackedStringArray()
	var opts: Array = []
	for o in Life.careers.orgs:
		var sh: Vector2 = o["shift"]
		var parts := PackedStringArray()
		for s: Dictionary in o["seats"]:
			parts.append("%s %d/%d" % [s["title"], s["holders"].size(), s["count"]])
		lines.append("%s  (%02d:00–%02d:00):  %s" % [String(o["name"]).capitalize(), int(sh.x), int(sh.y), ", ".join(parts)])
		for v: Dictionary in Life.careers.vacancies(o["id"]):
			var s: Dictionary = v["seat"]
			if o["id"] == "guard":
				continue
			var why := Life.careers.check_application(o["id"], s["title"], Game.merit)
			opts.append(["Apply: %s, %s  —  %dg/day  (%d open)" % [s["title"], o["name"], s["wage"], v["open"]],
				_apply.bind(o["id"], s["title"]), why == ""])
	var guard := Life.careers.seat("guard", "Guard")
	if Life.careers.open_count(guard) > 0:
		lines.append("\nThe Guard is hiring: %d posts open. See the Captain of the Guard." % Life.careers.open_count(guard))
	return {"title": "Notice Board", "body": "\n".join(lines), "options": opts}


func _apply(org_id: String, title: String) -> String:
	if not Life.is_adult() and org_id != "inn":
		return "\"Come back when you're grown, little one.\" (age %d of %d)" % [Life.age(), Life.ADULT_AGE]
	var why := Life.careers.apply(org_id, title, Game.merit, WorldSim.day)
	return why


func captain_menu() -> Dictionary:
	var c := Life.careers
	var o := c.org("guard")
	var parts := PackedStringArray()
	for s: Dictionary in o["seats"]:
		parts.append("%s %d/%d (%dg)" % [s["title"], s["holders"].size(), s["count"], s["wage"]])
	var in_guard: bool = c.is_employed() and c.player["org"] == "guard"
	var opts: Array = []
	if not in_guard:
		var why := c.check_application("guard", "Guard", Game.merit)
		opts.append(["Enlist as a Guard" if why == "" else "Enlist (no post open)", _enlist, why == ""])
	else:
		var up := c.promotion_for_player(Game.merit)
		if not up.is_empty():
			opts.append(["Take the open %s's seat" % up["title"], _apply.bind("guard", up["title"])])
		var room := Game.max_soldiers() - int(soldiers.call())
		opts.append(["Hire soldiers (%dg each)" % Game.RECRUIT_COST, _hire.bind(room), room > 0])
		opts.append(["Resign from the Guard", _resign])
	var body := "%s: %s.\nWatch from %02d:00 to %02d:00 on the walls and ring stones. Miss %d shifts and you're out." % [
		String(o["name"]).capitalize(), ", ".join(parts), int(o["shift"].x), int(o["shift"].y), RACareers.STRIKES_TO_DISMISS]
	if in_guard:
		body += "\nYou: %s, %d merit, %d strike(s)." % [c.player["seat"], Game.merit, c.player["strikes"]]
	return {"title": "Captain of the Guard", "body": body, "options": opts}


func _hire(room: int) -> String:
	var k := mini(room, mini(6, Game.gold / Game.RECRUIT_COST))
	if k <= 0:
		return "No room in your company or no coin."
	Game.add_gold(-k * Game.RECRUIT_COST)
	recruit.call(k)
	return "%d recruits join your company." % k


func _resign() -> String:
	Life.careers.resign()
	return ""


func _enlist() -> String:
	if not Life.is_adult():
		return "\"The Guard takes no children. Grow strong, and come back at %d.\"" % Life.ADULT_AGE
	var why := Life.careers.apply("guard", "Guard", Game.merit, WorldSim.day)
	if why != "":
		return why
	if Game.rank == 0:
		Game.promote()
		recruit.call(Game.max_soldiers())
	hud.close_menu()
	return "\"Welcome to the Guard. Take a patrol of twelve. Raiders camp in the eastern woods, wolves in the pines.\""


func pack_menu() -> Dictionary:
	var c := Life.careers
	var n := Life.needs
	var lines := PackedStringArray()
	if c.is_employed():
		var sh: Vector2 = c.player_org()["shift"]
		lines.append("%s, %s. Shift %02d–%02d. Today %.1f h on duty. Strikes %d/%d." % [c.player["seat"], c.player_org()["name"],
			int(sh.x), int(sh.y), c.player["attended"], c.player["strikes"], RACareers.STRIKES_TO_DISMISS])
	else:
		lines.append("No employment. The notice board lists open posts.")
	lines.append("%s, age %d (%s).  Build: %s" % [Life.life_path.full_name(), Life.age(),
		Life.life_path.stage_name(WorldSim.day, WorldSim.time_of_day), Life.build_summary()])
	var shown := PackedStringArray()
	for t: Dictionary in Life.titles.earned_list():
		shown.append(String(t.get("name", t.get("id", ""))))
	if not shown.is_empty():
		lines.append("Titles: " + ", ".join(shown))
	lines.append("Food %d  ·  Rest %d  ·  Gold %d  ·  Merit %d" % [int(n.food), int(n.rest), Game.gold, Game.merit])
	var items := PackedStringArray()
	var opts: Array = []
	var seen := {}
	for it in Life.inventory.get_items():
		var id := it.get_prototype().get_prototype_id()
		if seen.has(id):
			continue
		seen[id] = true
		items.append("%s ×%d" % [Life.item_name(id), Life.count(id)])
		if float(it.get_property("nutrition", 0.0)) > 0.0 or int(it.get_property("heal", 0)) > 0:
			opts.append(["Use %s" % Life.item_name(id), Life.use_item.bind(id)])
	lines.append("Pack: " + (", ".join(items) if not items.is_empty() else "empty"))
	for e: Dictionary in Life.pending_offers:
		var eid := int(e["id"])
		var offer: Dictionary = e.get("offer", {})
		lines.append("Offer: %s (%s) wants you as %s." % [e["scout"].get("name", "?"), e["org"].get("name", "?"), offer.get("role", "recruit")])
		opts.append(["Accept offer from %s" % e["org"].get("name", "?"), Life.answer_offer.bind(eid, true)])
		opts.append(["Decline offer from %s" % e["org"].get("name", "?"), Life.answer_offer.bind(eid, false)])
	var inj := PackedStringArray()
	for i: Dictionary in Life.injuries.active:
		inj.append(Life.injuries.label(i))
	if not inj.is_empty():
		lines.append("Injuries: " + ", ".join(inj))
	lines.append("Magicules %d / %d" % [int(Life.magicules.current), int(Life.magicules.effective_max())])
	opts.append(["Sleep rough here", _sleep_rough, n.rest < 80.0])
	opts.append(["Save game", _save])
	opts.append(["Load game", _load, Life.has_save()])
	return {"title": "Pack & Journal", "body": "\n".join(lines), "options": opts}


func _sleep_rough() -> String:
	hud.close_menu()
	return Life.sleep(0.55)


func _save() -> String:
	return "Game saved." if Life.save_game() else "Could not save."


func _load() -> String:
	hud.close_menu()
	return "Game loaded." if Life.load_game() else "No save found."


# --- guild & healer ---------------------------------------------------------------

func guild_menu() -> Dictionary:
	var g := Life.guild
	var me := RAAdventurerGuild.PLAYER
	var opts: Array = []
	var body := ""
	if not g.is_member(me):
		body = "\"Welcome to the %s. Membership is %d gold; every adventurer starts at F rank. Commissions pay by rank.\"" % [
			g.branch(0).get("name", "Guild Hall"), RAAdventurerGuild.MEMBERSHIP_FEE]
		opts.append(["Register as an adventurer (%dg)" % RAAdventurerGuild.MEMBERSHIP_FEE, Life.join_guild,
			Game.gold >= RAAdventurerGuild.MEMBERSHIP_FEE])
	else:
		var m := g.member(me)
		var rank := int(m.get("rank", 0))
		var next_pts: int = RAAdventurerGuild.RANK_POINTS[mini(rank + 1, 6)]
		body = "%s-rank adventurer · %d / %d points" % [RAAdventurerGuild.rank_name(rank), int(m.get("points", 0)), next_pts]
		if int(m.get("debt", 0)) > 0:
			body += " · debt %dg" % int(m["debt"])
			opts.append(["Pay guild debt", func() -> String:
				var paid := g.settle_debt(me, Game.gold)
				Game.add_gold(-paid)
				return "Paid %d gold." % paid, Game.gold > 0])
		for c: Dictionary in g.active_for(me):
			var cid := int(c["id"])
			if g.is_ready(cid):
				opts.append(["✔ Turn in: %s  (+%dg)" % [c["title"], c["reward"]], Life.turn_in.bind(cid)])
			else:
				opts.append(["Abandon: %s  (%d/%d)" % [c["title"], c["progress"], c["required"]], func() -> String:
					return String(g.fail(me, cid, WorldSim.day).get("text", ""))])
		for c: Dictionary in g.available_for(me, 0):
			var cid2 := int(c["id"])
			opts.append(["[%s] %s  —  %dg · %d pts · %d days" % [RAAdventurerGuild.rank_name(int(c["rank"])), c["title"],
				c["reward"], c["points"], int(c["deadline"]) - WorldSim.day], func() -> String:
				var why := g.accept(me, cid2, WorldSim.day)
				return why if why != "" else "Commission accepted."])
	var open_board := 0
	for c: Dictionary in g.board(0):
		if c["state"] == "open":
			open_board += 1
	body += "\n%d commissions on the board." % open_board
	return {"title": "Adventurer Guild", "body": body, "options": opts}


func healer_menu() -> Dictionary:
	var opts: Array = []
	var menu := Life.injuries.healer_menu("herbalist")
	for q: Dictionary in menu:
		opts.append(["Treat %s  —  %s" % [q["name"], ("%dg, %dh" % [q["cost"], int(ceil(float(q["hours"])))]) if q["ok"] else "beyond my skill"],
			Life.treat.bind(int(q["uid"]), "herbalist"), bool(q["ok"]) and Game.gold >= int(q["cost"])])
	opts.append(["Buy a linen bandage (%dg)" % Life.market.price("bandage"), Life.buy.bind("bandage"),
		Life.market.can_buy("bandage", Game.gold) == ""])
	var body := "\"Cuts, bites, fevers, I can mend. A cracked soul-core needs a temple, child.\""
	if menu.is_empty():
		body += "\nYou are unhurt."
	return {"title": "Herbalist", "body": body, "options": opts}
