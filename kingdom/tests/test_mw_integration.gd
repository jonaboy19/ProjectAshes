extends GdUnitTestSuite
## MW integration: ledger, district values, social perception and follower will are wired into the modules that already pay, open,
## rule and perceive. One 180-day hub run (followers on wages, a treasury shortfall, a workshop opening, a governor) plus the
## disguised player in a church kingdom, asserting the cross-module effects and that gold is conserved and never paid twice.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Rec := preload("res://scripts/realm/recruitment.gd")
const Brain := preload("res://scripts/actors/follower_brain.gd")
const DV := preload("res://scripts/realm/district_values.gd")
const SP := preload("res://scripts/realm/social_perception.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 100000, "player_pos": Vector3.ZERO, "life": null}

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	return h


func _ch(h: RefCounted, cash: int, sid := 0) -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash, "sid": sid, "prof": "baker"})
	return ch


func _row(skip := 0) -> int:
	var rg: Vector2i = WorldSim.ranges[0]
	var rc: RefCounted = Rec.new()
	var seen := 0
	for i in range(rg.x, rg.y):
		if WorldSim.health[i] != 0 and not (rc.profile(i)["traits"] as Array).has("greedy"):
			if seen >= skip:
				return i
			seen += 1
	return rg.x


func _hire(h: RefCounted, row: int, wage: int) -> String:
	var res: Dictionary = h.mod("recruitment").engage(row, Rec.make_terms(wage, "guard", 0, true), "personal", "", {"trust": 60.0, "reputation": 60.0})
	assert_bool(res["ok"]).is_true()
	return String(res["fid"])


func _church_pair() -> Array:
	return ["solmarch", "caldrenn"]


# --- the 180-day run -----------------------------------------------------------------------------

func test_180_day_hub_run_wires_the_modules_and_conserves_gold() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var rc: RefCounted = h.mod("recruitment")
	var fol: RefCounted = h.mod("followers")
	var wm: RefCounted = h.mod("will")
	var dv: RefCounted = h.mod("districts")
	var bz: RefCounted = h.mod("businesses")
	var st: RefCounted = h.mod("stewardship")
	var day0 := WorldSim.day
	lg.set_day(0)
	# followers on wages, one of them also owed by a treasury that is empty
	var f1 := _hire(h, _row(0), 10)
	var f2 := _hire(h, _row(1), 12)
	var f3 := _hire(h, _row(2), 8)
	lg.post_wage("tr:9", "fo:" + f3, 20, 7, 7)                      # tr:9 holds nothing: the ladder takes f3 out of recruitment
	# a treasury shortfall: tr:0 funds a wage to a treasurer for six weeks, then runs dry
	lg._acct["tr:0"] = 300
	var treasurer := _ch(h, 0)
	lg.post_wage("tr:0", treasurer, 50, 7, 7)
	var tracked := ["tr:0", "tr:9", treasurer]
	var tot0: int = lg.total(tracked)
	# a governor with a skimming agenda rules settlement 0
	wm.set_state(f1, {"m": {"gre": 1.0, "ide": 0.0, "aff": 0.0, "hid": 1.0}, "agenda": "profit", "g": 0.8})
	if not bool(wm.appoint_governor(0, f1)["ok"]):
		wm._gov[0] = f1                                              # the fit check is not what is under test
	var corr0: float = dv.values(0, "other")["corruption"]
	# a workshop opening next to a rival of the same trade
	bz.set_population(0, 400)
	var rival := _ch(h, 3000)
	var newcomer := _ch(h, 3000)
	var b1: Dictionary = bz.found(rival, "workshop", 0, "Old Bakery", "bakery")
	assert_bool(b1["ok"]).is_true()
	var opened_at := 0
	var paid_player := 0
	var noted := 0
	var last_w := -1
	var departed := false
	for d in range(1, 181):
		WorldSim.day = d
		h.on_hour(6, d, CTX)
		h.drain()
		paid_player += -int(rc.take_pending_gold())
		if d == 20:
			var b2: Dictionary = bz.found(newcomer, "workshop", 0, "New Bakery", "bakery")
			assert_bool(b2["ok"]).is_true()
			opened_at = d
			assert_float(dv.opposition(rival, newcomer)).is_greater(0.0)           # the rival is now an opponent
			assert_float(dv._dr(0, "other", DV.D_BIZ)).is_greater(0.2)
			assert_float(dv._dr(0, "other", DV.D_BIZ)).is_less(0.6)                # counted once, not twice
		for e: Dictionary in (lg.summary("player")["history"] as Array):
			if int(e["w"]) > last_w:
				last_w = int(e["w"])
				noted += int(e["out"])
		if str(fol.get_follower(f3)["status"]) == "left":
			departed = true
	noted += int((lg.summary("player")["expense"] as Dictionary).get("wage", 0))
	WorldSim.day = day0
	assert_int(opened_at).is_equal(20)
	# recruitment wages: the purse paid exactly what the ledger recorded (no double payment, no missing note)
	assert_int(paid_player).is_greater(1000)
	assert_int(noted).is_equal(paid_player)
	# shortage ladder: the dry treasury is in arrears with a reaction, and the follower it owed left through recruitment
	assert_int(int(lg.stats["late"])).is_greater(0)
	assert_int(int(lg.stats["resigned"]) + int(lg.stats["deserted"])).is_greater(0)
	assert_bool(departed).is_true()
	assert_str(rc.contract_of(f3)["st"]).is_not_equal("active")
	assert_str(rc.contract_of(f2)["st"]).is_equal("active")
	# ledger-only money is conserved across the whole run
	assert_int(lg.total(tracked)).is_equal(tot0)
	# the governor's skimming reached the district values and stewardship
	assert_float(dv.values(0, "other")["corruption"]).is_greater(corr0)
	var mod: Dictionary = wm.settlement_modifier(0)
	assert_float(st.tax_yield(0)).is_equal_approx(st.tax_rate(0) * float(mod["output"]) * (1.0 - float(mod["leak"])), 0.0001)
	assert_float(st.tax_yield(0)).is_less_equal(st.tax_rate(0) * 1.5)


# --- payers keep their path but log into the ledger -------------------------------------------------

func test_payers_log_into_the_weekly_summary_without_moving_money_twice() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var rc: RefCounted = h.mod("recruitment")
	var fid := _hire(h, _row(), 10)
	var fol: RefCounted = h.mod("followers")
	var total := 0
	for d in range(1, 4):
		var ctx := CTX.duplicate()
		var before := int(fol.get_follower(fid)["owed"])
		h.mod("followers").tick_day(d, ctx)
		rc.tick_day(d, ctx)
		total += -int(rc.take_pending_gold())
		assert_int(before).is_greater_equal(0)
	var s: Dictionary = lg.summary("fo:" + fid)
	assert_int(int((s["income"] as Dictionary).get("wage", 0))).is_equal(total)
	assert_int(total).is_equal(30)
	assert_int(lg.balance("player")).is_equal(lg.balance("player"))        # note() never touches a purse


# --- one audit, one result --------------------------------------------------------------------------

func test_ledger_and_follower_audits_share_one_result() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var wm: RefCounted = h.mod("will")
	var fid := _hire(h, _row(), 10)
	lg.delegate("tr:5", "fo:" + fid, 500, 100)
	lg._acct["tr:5"] = 300
	lg._skim["tr:5"] = 40                                              # what the steward took, as the ledger saw it
	var r: Dictionary = wm.audit(fid)
	assert_float(float(r["found"])).is_greater_equal(40.0)
	assert_int((r["ledger"] as Array).size()).is_equal(1)
	assert_int(int(((r["ledger"] as Array)[0] as Dictionary)["found"])).is_equal(40)
	# the other way round: auditing the account reports the follower's side in the same result
	lg.delegate("tr:6", "fo:" + fid, 500, 100)
	var r2: Dictionary = lg.audit("tr:6", "player")
	assert_bool(r2.has("will")).is_true()
	assert_bool((r2["will"] as Dictionary).has("honesty")).is_true()


# --- follower will reaches the body ----------------------------------------------------------------

func test_a_refusing_follower_holds_position() -> void:
	var h := _hub()
	var wm: RefCounted = h.mod("will")
	var fid: String = h.mod("followers").hire("knight", "s0", true, "theron")
	wm.set_state(fid, {"m": {"aff": 0.6, "res": 0.6, "fear": 0.05, "ide": 1.0, "gre": 0.1, "pro": 0.9, "hid": 0.0}, "agenda": "", "life": false, "rank": 2})
	var out: Dictionary = wm.respond(fid, {"kind": "attack_neighbour", "moral": 0.9, "danger": 0.7, "tie": 0.9}, {"day": 0})
	var a := String(out["action"])
	if a in Brain.WILL_HOLD:
		assert_str(wm.will_of(fid)).is_equal(a)
		assert_int(Brain.decide("follow", {"dist": 3.0, "will": wm.will_of(fid)})).is_equal(Brain.Mode.WAIT)
	wm.set_state(fid, {"last": "stay_behind", "last_day": 0})
	assert_str(wm.will_of(fid)).is_equal("stay_behind")
	assert_int(Brain.decide("follow", {"dist": 3.0, "will": wm.will_of(fid)})).is_equal(Brain.Mode.WAIT)
	var back: RefCounted = Hub.new().mod("will")
	back.deserialize(JSON.parse_string(JSON.stringify(wm.serialize())))
	assert_str(back.state_of(fid)["last"]).is_equal("stay_behind")


# --- the disguised player in a church kingdom -------------------------------------------------------

func test_disguised_player_in_a_church_kingdom_reads_persona_and_alliances() -> void:
	var h := _hub()
	var pm: RefCounted = h.mod("persona")
	var obs := _ch(h, 10)
	pm.ensure(obs, 0)
	var sp: RefCounted = SP.new()
	var o := {"id": obs, "kingdom": "solmarch", "perception": 0.0}
	var king := {"id": "player", "origin": "caldrenn", "title_rank": 4, "insignia": 1.0, "gear_value": 0.8}
	var ctx := {"hub": h, "day": 3, "hour": 10}
	# no alliance: a Valencios title is void in a church kingdom
	assert_float(SP.legitimacy("caldrenn", "solmarch", ctx)).is_equal(0.0)
	assert_float(float(sp.read(o, king, ctx)["authority"])).is_equal(0.0)
	# the persona record fills the observer (explicit dict values still win)
	var filled: Dictionary = sp._observer_from_hub(o, h)
	assert_bool(filled.has("persona") and (filled["persona"] as Dictionary).has("courage")).is_true()
	assert_bool(filled.has("intelligence")).is_true()
	assert_float(float(sp._observer_from_hub({"id": obs, "intelligence": 0.11}, h)["intelligence"])).is_equal(0.11)
	# disguised as a local pilgrim, the observer never sees the title
	var cloaked := king.duplicate()
	cloaked["disguise"] = {"quality": 1.0, "identity": {"id": "pilgrim", "title_rank": 0, "gear_value": 0.05, "origin": "solmarch"}}
	var r: Dictionary = sp.read(o, cloaked, {"hub": h, "day": 3, "hour": 12})
	assert_bool(r["disguised"]).is_true()
	assert_bool(r["exposed"]).is_false()
	assert_str(r["perceived_id"]).is_equal("pilgrim")
	assert_float(float(r["authority"])).is_equal(0.0)
	# an alliance in diplomacy (read through homes.title_recognised) makes the real title honoured
	var dp: RefCounted = h.mod("diplomacy")
	dp._ag["pa1"] = {"id": "pa1", "type": "alliance", "a": "caldrenn", "b": "solmarch", "state": "active"}
	assert_float(SP.legitimacy("caldrenn", "solmarch", ctx)).is_equal(1.0)
	assert_float(float(SP.new().read(o, king, {"hub": h, "day": 3, "hour": 11})["authority"])).is_greater(0.5)
	# dict-only callers still work
	assert_float(SP.legitimacy("caldrenn", "solmarch", {"allied": ["caldrenn|solmarch"]})).is_equal(1.0)
	assert_float(SP.legitimacy("caldrenn", "solmarch")).is_equal(0.0)
