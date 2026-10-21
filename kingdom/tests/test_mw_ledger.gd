extends GdUnitTestSuite
## MW-19 / MW-20 / MW-21: the scheduled realm ledger. Scheduling, conservation of money, the shortage ladder by persona,
## embezzle + audit, delegation limits, warnings, save/load (through JSON) and closed-form catch_up.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Ledger := preload("res://scripts/realm/ledger.gd")

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	var h: RefCounted = Hub.new()
	h.mod("organizations").auto_seed = false
	h.mod("organizations").gold_ref = {"gold": 0}
	return h


func _ch(h: RefCounted, cash: int) -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash})
	return ch


## A new character whose persona matches `want` ("loyal", "disloyal", "honest", "crook").
func _ch_like(h: RefCounted, lg: RefCounted, cash: int, want: String) -> String:
	for i in 400:
		var ch := _ch(h, cash)
		var t: Dictionary = lg.traits(ch)
		match want:
			"loyal":
				if float(t["loyalty"]) >= 0.8:
					return ch
			"disloyal":
				if float(t["loyalty"]) <= 0.1:
					return ch
			"crook":
				if float(t["honesty"]) < 0.3:
					return ch
			"honest":
				if float(t["honesty"]) >= 0.6:
					return ch
	return _ch(h, cash)


func _run(lg: RefCounted, from: int, to: int) -> void:
	for d in range(from, to + 1):
		lg.tick_day(d, {})
		if d % 7 == 0:
			lg.tick_week(d / 7, {})


func test_scheduling_posts_on_due_dates_only() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var boss := _ch(h, 1000)
	var smith := _ch(h, 0)
	var id: int = lg.post_wage(boss, smith, 30, 7, 7)
	assert_int(id).is_greater(0)
	_run(lg, 1, 6)
	assert_int(h.mod("organizations").purse(smith)).is_equal(0)
	_run(lg, 7, 7)
	assert_int(h.mod("organizations").purse(smith)).is_equal(30)
	_run(lg, 8, 21)
	assert_int(h.mod("organizations").purse(smith)).is_equal(90)
	assert_int(h.mod("organizations").purse(boss)).is_equal(910)
	assert_int(lg.post_wage(boss, boss, 5)).is_equal(0)      # nobody pays themselves
	assert_int(lg.post("bribe", boss, smith, 5)).is_equal(0)


func test_conservation_over_a_year_of_every_kind() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var om: RefCounted = h.mod("organizations")
	var lord := _ch(h, 600)
	var peasant := _ch(h, 120)
	var guard := _ch(h, 0)
	var landlord := _ch(h, 50)
	var banker := _ch(h, 800)
	var org: String = "org:900"
	om._o[org] = {"treasury": 300, "st": "active"}
	var tr := "tr:3"
	var all: Array = [lord, peasant, guard, landlord, banker, org, tr]
	lg.post_tax(peasant, tr, 9)
	lg.post_wage(tr, guard, 20)
	lg.post_rent(peasant, landlord, 7, 7)
	lg.post_upkeep(lord, org, 25, 7, -1, "army")
	lg.post_loan(banker, lord, 200, 40, 3)
	lg.post_contract(org, guard, 5, 14)
	var before: int = lg.total(all)
	_run(lg, 1, 365)
	assert_int(lg.total(all)).is_equal(before)
	assert_int(int(lg.stats["paid"])).is_greater(0)
	# money really arrived at recipients
	assert_int(lg.balance(tr)).is_greater(0)
	assert_int(om.purse(landlord)).is_greater(50)


func test_loan_moves_principal_and_ends_when_repaid() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var bank := _ch(h, 500)
	var bor := _ch(h, 0)
	var id: int = lg.post_loan(bank, bor, 100, 60, 0)
	assert_int(lg.balance(bor)).is_equal(100)
	assert_int(lg.balance(bank)).is_equal(400)
	lg.tick_day(7, {})
	assert_int(lg.balance(bor)).is_equal(40)
	lg.tick_day(14, {})
	assert_str(lg.obligation(id)["state"]).is_equal("paid")
	assert_int(lg.balance(bank)).is_equal(500 - 100 + 100 - 0 + 0 - 0 + 0) # principal returned, no interest at 0%
	assert_int(lg.balance(bor)).is_equal(0)


func test_rung_order_follows_persona() -> void:
	# loyal waits longest, disloyal army mutinies, an honest one never embezzles
	assert_str(Ledger.rung(0.9, 0.9, 1, "wage", false, false)).is_equal("wait")
	assert_str(Ledger.rung(0.9, 0.9, 4, "wage", false, false)).is_equal("wait")      # patience 4
	assert_str(Ledger.rung(0.9, 0.9, 6, "wage", false, false)).is_equal("demand")
	assert_str(Ledger.rung(0.9, 0.9, 6, "wage", false, true)).is_equal("wait")      # already demanded
	assert_str(Ledger.rung(0.9, 0.9, 9, "wage", true, true)).is_equal("resign")
	assert_str(Ledger.rung(0.9, 0.2, 7, "wage", true, true)).is_equal("embezzle")
	assert_str(Ledger.rung(0.4, 0.9, 5, "upkeep", false, true)).is_equal("desert")
	assert_str(Ledger.rung(0.1, 0.9, 5, "upkeep", false, true)).is_equal("mutiny")
	assert_str(Ledger.rung(0.1, 0.9, 5, "wage", false, true)).is_equal("resign")


func test_shortage_ladder_in_persona_order() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var lord := _ch(h, 0)      # broke
	var loyal := _ch_like(h, lg, 0, "loyal")
	var fickle := _ch_like(h, lg, 0, "disloyal")
	var a: int = lg.post_upkeep(lord, loyal, 10, 7, 7, "army")
	var b: int = lg.post_upkeep(lord, fickle, 10, 7, 7, "army")
	var left_fickle := -1
	var left_loyal := -1
	for w in range(1, 20):
		_run(lg, (w - 1) * 7 + 1, w * 7)
		if left_fickle < 0 and lg.obligation(b)["state"] != "live":
			left_fickle = w
		if left_loyal < 0 and lg.obligation(a)["state"] != "live":
			left_loyal = w
	assert_int(left_fickle).is_greater(0)
	assert_int(left_loyal).is_greater(0)
	assert_int(left_fickle).is_less(left_loyal)       # the disloyal leave first
	var deps: Array = lg.take_departures()
	assert_int(deps.size()).is_equal(2)
	assert_str(String(deps[0]["why"])).is_not_equal("")
	assert_int(lg.claims_of(fickle)).is_greater(0)    # the arrears stay owed
	assert_array(lg.take_departures()).is_empty()


func test_late_pay_recovers_when_money_arrives() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var lord := _ch(h, 0)
	var worker := _ch_like(h, lg, 0, "loyal")
	var id: int = lg.post_wage(lord, worker, 10, 7, 7)
	_run(lg, 1, 14)                                  # two missed weeks, a loyal worker waits
	assert_str(lg.obligation(id)["state"]).is_equal("live")
	assert_int(lg.obligation(id)["arrears"]).is_equal(20)
	h.mod("organizations").earn(lord, 100)
	_run(lg, 15, 21)
	assert_int(lg.obligation(id)["arrears"]).is_equal(0)
	assert_int(lg.obligation(id)["missed"]).is_equal(0)
	assert_int(lg.balance(worker)).is_equal(30)


func test_embezzle_and_audit() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var om: RefCounted = h.mod("organizations")
	var owner := _ch(h, 100)
	var crook := _ch_like(h, lg, 0, "crook")
	var tr := "tr:7"
	var payers: Array = []
	for i in 6:
		var p := _ch(h, 5000)
		payers.append(p)
		lg.post_tax(p, tr, 40, 7, 7)
	lg.delegate(tr, crook, 500, 200)
	var all: Array = payers + [owner, crook, tr]
	var before: int = lg.total(all)
	_run(lg, 1, 70)
	assert_int(lg.total(all)).is_equal(before)       # skimmed gold sits in the steward's purse, not nowhere
	var stolen := int(lg._skim.get(tr, 0))
	assert_int(stolen).is_greater(0)
	assert_int(om.purse(crook)).is_equal(stolen)
	var treasury_before: int = lg.balance(tr)
	var r: Dictionary = lg.audit(tr, owner)
	assert_int(r["found"]).is_equal(stolen)
	assert_int(r["recovered"]).is_equal(stolen)
	assert_int(lg.balance(tr)).is_equal(treasury_before + stolen + Ledger.AUDIT_FEE)
	assert_int(lg.total(all)).is_equal(before)
	assert_str(lg.steward_of(tr)).is_equal("")       # removed
	# an honest treasurer is clean
	var honest := _ch_like(h, lg, 0, "honest")
	var tr2 := "tr:8"
	var p2 := _ch(h, 5000)
	lg.post_tax(p2, tr2, 40, 7, 7)
	lg.delegate(tr2, honest, 500, 200)
	_run(lg, 71, 140)
	assert_int(int(lg._skim.get(tr2, 0))).is_equal(0)
	assert_int(lg.audit(tr2, owner)["found"]).is_equal(0)


func test_steward_limits_and_budget() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var honest := _ch_like(h, lg, 0, "honest")
	var acct := "tr:1"
	var vendor := _ch(h, 0)
	lg._acct[acct] = 1000
	lg.delegate(acct, honest, 100, 60)
	assert_bool(lg.steward_pay(acct, vendor, 80)["ok"]).is_false()        # over the limit
	assert_bool(lg.steward_pay(acct, vendor, 60)["ok"]).is_true()
	assert_bool(lg.steward_pay(acct, vendor, 50)["ok"]).is_false()        # 110 > budget 100
	assert_int(lg.balance(vendor)).is_equal(60)
	assert_int(lg.balance(acct)).is_equal(940)
	lg.set_day(7)                                                        # a new week resets the budget
	assert_bool(lg.steward_pay(acct, vendor, 50)["ok"]).is_true()


func test_warnings_do_not_spam() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var lord := _ch(h, 0)
	var w := _ch_like(h, lg, 0, "loyal")
	lg.post_wage(lord, w, 10, 1, 1)
	var said := 0
	for d in range(1, 11):
		said += lg.tick_day(d, {}).size()
	assert_int(said).is_less_equal(3)


func test_summary_reports_income_expense_and_projection() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var boss := _ch(h, 500)
	var staff := _ch(h, 0)
	var tenant := _ch(h, 100)
	lg.post_wage(boss, staff, 20, 7, 7)
	lg.post_rent(tenant, boss, 14, 14, 7)
	for d in range(1, 8):
		lg.tick_day(d, {})
	var s: Dictionary = lg.summary(boss)
	assert_int(s["expense"]["wage"]).is_equal(20)
	assert_int(s["income"]["rent"]).is_equal(14)
	assert_int(s["net"]).is_equal(-6)
	assert_int(s["projected_week"]).is_equal(-20 + 7)
	assert_int((s["scheduled"] as Array).size()).is_equal(2)
	lg.tick_week(1, {})
	var s2: Dictionary = lg.summary(boss)
	assert_int((s2["history"] as Array).size()).is_equal(1)
	assert_int(s2["history"][0]["net"]).is_equal(-6)


func test_save_load_round_trip_through_json() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var lord := _ch(h, 100)
	var w := _ch_like(h, lg, 0, "disloyal")
	var bank := _ch(h, 900)
	lg.post_upkeep(lord, w, 30, 7, 7, "army")
	lg.post_loan(bank, lord, 100, 30, 2)
	lg.post_tax(lord, "tr:2", 5, 7, 7)
	lg.delegate("tr:2", w, 90, 30)
	_run(lg, 1, 30)
	var d: Dictionary = JSON.parse_string(JSON.stringify(lg.serialize()))
	var lg2: RefCounted = Ledger.new()
	lg2.hub = h
	lg2.deserialize(d)
	assert_str(JSON.stringify(lg2.serialize())).is_equal(JSON.stringify(lg.serialize()))
	assert_int(lg2.live_count()).is_equal(lg.live_count())
	# both continue identically
	_run(lg, 31, 60)
	var h2 := _hub()      # separate world state is irrelevant: only the schedule matters, so compare the obligation tables
	_run(lg2, 31, 60)
	for id in [1, 2, 3]:
		assert_dict(lg2.obligation(id)).is_equal(lg.obligation(id))
	assert_object(h2).is_not_null()
	# an old save without the ledger loads empty (migration)
	var lg3: RefCounted = Ledger.new()
	lg3.deserialize({})
	assert_int(lg3.live_count()).is_equal(0)


func test_catch_up_matches_daily_ticks_and_is_closed_form() -> void:
	var hA := _hub()
	var hB := _hub()
	var res: Array = []
	for h: RefCounted in [hA, hB]:
		var lg: RefCounted = h.mod("ledger")
		var boss := "ch:9001"
		var staff := "ch:9002"
		var bank := "ch:9003"
		h.mod("organizations").ensure_char(boss, {"cash": 5000})
		h.mod("organizations").ensure_char(staff, {"cash": 1000})
		h.mod("organizations").ensure_char(bank, {"cash": 1000})
		lg.post_wage(boss, staff, 25, 7, 7)
		lg.post_rent(staff, boss, 4, 3, 3)
		lg.post_loan(bank, boss, 300, 50, 2)
		res.append(lg)
	_run(res[0], 1, 364)
	res[1].catch_up(364, {})
	for who in ["ch:9001", "ch:9002", "ch:9003"]:
		# loan interest is rounded up each period when ticked daily, once when caught up: a few gold apart at most
		assert_int(absi(int(res[1].balance(who)) - int(res[0].balance(who)))).is_less_equal(10)
	# a ten-year jump with thousands of obligations stays cheap
	var lg: RefCounted = hB.mod("ledger")
	for i in 2000:
		lg.post_wage("ch:9001", "ch:9002", 1, 7, 7)
	var t0 := Time.get_ticks_usec()
	lg.catch_up(3650, {})
	assert_int(Time.get_ticks_usec() - t0).is_less(1500000)


func test_day_tick_is_chunked_and_cheap() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var boss := _ch(h, 1000000)
	var staff := _ch(h, 0)
	for i in 400:
		lg.post_wage(boss, staff, 1, 7, 7)
	var chunks: Array = lg.tick_day_chunks(7, {})
	assert_int(chunks.size()).is_equal(10)
	var worst := 0
	for c: Callable in chunks:
		var t0 := Time.get_ticks_usec()
		c.call()
		worst = maxi(worst, Time.get_ticks_usec() - t0)
	assert_int(worst).is_less(20000)
	assert_int(lg.balance(staff)).is_equal(400)
