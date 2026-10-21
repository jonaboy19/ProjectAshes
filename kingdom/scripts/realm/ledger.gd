extends "res://scripts/realm/realm_module.gd"
## MW-19 / MW-20 / MW-21: ONE scheduled realm ledger (docs/design/LIVING_WORLD_MASTER_PLAN.md section G).
##
## What it is. A table of OBLIGATIONS (wage, tax, rent, upkeep, loan, contract), each "payer pays payee `amt` every `period` days",
## posted on its due day. It does not keep a purse of its own: the player's and every character's money is the organizations.gd
## purse (the pending-gold ledger Life already drains through take_pending_gold), an org's money is its treasury, a business's is its
## account `bal`, and settlement / household / other accounts ("tr:<sid>", "hh:n", ...) are plain balances in `_acct` below. Every payment
## is a transfer from one such record to another; nothing is ever deleted, so total() is constant across any amount of settling
## (the conservation test). Existing payers (recruitment wages, armies upkeep, homes rent ...) keep their own paths; they can log a flow
## into the weekly summary with note(), and new payers use post_*.
##
## Shortage ladder (MW-20). A payer that cannot cover a due payment pays what it can; the rest is kept as arrears and the payee reacts
## by its persona (loyalty, honesty from persona.gd; a hash stand-in without a record): accept the delay (patience 1..5 missed
## periods by loyalty), demand a raise (once), embezzle (a dishonest treasurer takes the arrears from the till), resign, desert (an
## army contract) and mutiny (a disloyal army). Departures are queued for the owning module (take_departures()).
##
## Delegation (MW-21). delegate(account, steward, weekly_budget, per_payment_limit) lets a steward or treasurer spend an account within
## limits. A dishonest one skims some of what passes through (money moves to their purse, hidden in `_skim`); audit() finds it, takes it
## back as far as they can pay and removes them. Warnings are rate limited (one per key per WARN_DAYS, WARN_CAP a day).
##
## Cost: day tick O(obligations due that day) in chunks of CHUNK; catch_up is closed form per obligation (periods elapsed = integer
## division, never a loop over days). Saves: ~11 small numbers per live obligation plus an interned id table.

const Codec := preload("res://scripts/realm/save_codec.gd")

const KINDS := ["wage", "tax", "rent", "upkeep", "loan", "contract"]
const CHUNK := 40
const WARN_DAYS := 14
const WARN_CAP := 3
const HIST_WEEKS := 4
const OB_CAP := 4000
const SKIM_CHANCE := 25         # percent of passing payments a dishonest steward skims
const SKIM_SHARE := 15          # percent of such a payment
const AUDIT_FEE := 10
const RAISE_PCT := 15
const DEPART_CAP := 64
# state
const S_LIVE := 0
const S_ENDED := 1
const S_PAID := 2               # a loan repaid in full
# row fields
const K := 0
const PAYER := 1
const PAYEE := 2
const AMT := 3
const PER := 4
const NEXT := 5
const MISS := 6
const ARR := 7
const REM := 8                  # loan balance still owed (0 for other kinds)
const ST := 9
const FLAGS := 10               # bit 0: raise already demanded, bit 1: interest percent per period stored in RATE
const TAG := 11
const RATE := 12                # loan interest, percent per period

var _ob: Dictionary = {}        # int id -> row (Array, fields above)
var _next_id := 1
var _by_day: Dictionary = {}    # due day -> [ids] (derived, rebuilt on load)
var _acct: Dictionary = {}      # non-purse account id -> gold
var _stew: Dictionary = {}      # account -> {ch, budget, limit, spent, week}
var _skim: Dictionary = {}      # account -> gold taken by its steward and not yet found
var _claims: Dictionary = {}    # payee -> gold of arrears left behind by a payee who resigned or deserted
var _wi: Dictionary = {}        # account -> {kind: gold in this week}
var _wx: Dictionary = {}        # account -> {kind: gold out this week}
var _hist: Dictionary = {}      # account -> ring of past weekly summaries
var _warn_at: Dictionary = {}   # warning key -> day
var _depart: Array = []         # [{id, payee, payer, kind, why, day}] for the owning module
var _day := 0
var _seq := 0                   # deterministic counter for skim rolls
var _out: Array = []
var _warned_today := 0
var stats := {"paid": 0, "late": 0, "resigned": 0, "deserted": 0, "mutiny": 0, "embezzled": 0, "recovered": 0, "audits": 0, "refused": 0}


func _om() -> Variant:
	return hub.mod("organizations") if hub != null else null


func _bm() -> Variant:
	return hub.mod("businesses") if hub != null else null


func set_day(d: int) -> void:
	_day = d


# ------------------------------------------------------------------ money records

func _kind(id: String) -> String:
	var i := id.find(":")
	return id.substr(0, i) if i > 0 else ""


## What `who` holds right now.
func balance(who: String) -> int:
	match _kind(who):
		"ch":
			var om: Variant = _om()
			return int(om.purse(who)) if om != null else 0
		"org":
			var o: Variant = _om()
			return int(o.org(who).get("treasury", 0)) if o != null else 0
		"bz":
			var bm: Variant = _bm()
			return int(float(bm.biz(who).get("bal", 0.0))) if bm != null else 0
		_:
			if who == "player":
				var o2: Variant = _om()
				return int(o2.purse(who)) if o2 != null else 0
			return int(_acct.get(who, 0))


func _take(who: String, amt: int) -> bool:
	if amt <= 0:
		return true
	if balance(who) < amt:
		return false
	match _kind(who):
		"ch", "org":
			return bool(_om().pay_from(who, amt))
		"bz":
			var b: Dictionary = _bm().biz(who)
			b["bal"] = float(b["bal"]) - amt
		_:
			if who == "player":
				return bool(_om().pay(who, amt))
			_acct[who] = int(_acct.get(who, 0)) - amt
	return true


func _give(who: String, amt: int) -> void:
	if amt <= 0:
		return
	match _kind(who):
		"ch", "org":
			_om().pay_to(who, amt)
		"bz":
			var bm: Variant = _bm()
			var b: Dictionary = bm.biz(who)
			if b.is_empty():
				_acct[who] = int(_acct.get(who, 0)) + amt        # a closed business: the money stays on a record, never vanishes
			else:
				b["bal"] = float(b["bal"]) + amt
		_:
			if who == "player":
				_om().earn(who, amt)
			else:
				_acct[who] = int(_acct.get(who, 0)) + amt


## Every gold piece in the listed records plus every plain account the ledger holds that is not listed (so money parked on a
## closed business or a settlement is never lost from the count).
func total(who_list: Array) -> int:
	var t := 0
	for w: String in who_list:
		t += balance(w)
	for k: String in _acct:
		if not (k in who_list):
			t += int(_acct[k])
	return t


## Moves gold from a record to a record (a gift, a deposit, a refund) and logs it in the weekly summary. {ok, paid}.
func transfer(from: String, to: String, amt: int, kind := "contract") -> Dictionary:
	if amt <= 0 or not _take(from, amt):
		return {"ok": false, "paid": 0}
	_deposit(to, amt, kind, from)
	_log_out(from, kind, amt)
	return {"ok": true, "paid": amt}


## Money arriving at an account: a steward of that account may skim it, the rest lands.
func _deposit(to: String, amt: int, kind: String, _from: String) -> void:
	var got := amt
	var s: Dictionary = _stew.get(to, {})
	if not s.is_empty() and _dishonest(String(s["ch"])):
		_seq += 1
		if absi(hash([WorldSim.SEED, "skim", to, _day, _seq])) % 100 < SKIM_CHANCE:
			var cut := maxi(1, amt * SKIM_SHARE / 100)
			_give(String(s["ch"]), cut)
			_skim[to] = int(_skim.get(to, 0)) + cut
			stats["embezzled"] = int(stats["embezzled"]) + cut
			got = amt - cut
	_give(to, got)
	_log_in(to, kind, amt)


# ------------------------------------------------------------------ persona

## {loyalty, honesty} 0..1 for a character: persona.gd when the character has a record, a stable hash otherwise.
func traits(ch: String) -> Dictionary:
	var pm: Variant = hub.mod("persona") if hub != null else null
	if pm != null:
		var v: Dictionary = pm.view(ch)
		if not v.is_empty():
			return {"loyalty": float(v["loyalty"]) / 255.0, "honesty": float(v["honesty"]) / 255.0}
	return {"loyalty": float(absi(hash([WorldSim.SEED, "lloy", ch])) % 100) / 100.0, "honesty": float(absi(hash([WorldSim.SEED, "lhon", ch])) % 100) / 100.0}


func _dishonest(ch: String) -> bool:
	return float(traits(ch)["honesty"]) < 0.35


## Which rung a payee is on after `missed` unpaid periods. Pure function of persona and count.
## "wait" < "demand" < "embezzle" (only a dishonest treasurer) < "resign" / "desert" < "mutiny" (a disloyal army).
static func rung(loyalty: float, honesty: float, missed: int, kind: String, treasurer: bool, raised: bool) -> String:
	if missed <= 0:
		return "ok"
	var patience := 1 + int(loyalty * 4.0)
	if missed <= patience:
		return "wait"
	if missed <= patience + 2:
		return "wait" if raised else "demand"
	if treasurer and honesty < 0.35 and missed <= patience + 3:
		return "embezzle"
	if kind == "upkeep" and loyalty < 0.2:
		return "mutiny"
	if kind == "upkeep" and loyalty < 0.5:
		return "desert"
	return "resign"


# ------------------------------------------------------------------ posting

## Posts a standing obligation. first_due is the day of the first payment (default: one period from today).
## Returns the obligation id (int, 0 when refused).
func post(kind: String, payer: String, payee: String, amt: int, period := 7, first_due := -1, tag := "") -> int:
	if not (kind in KINDS) or amt <= 0 or period < 1 or _ob.size() >= OB_CAP or payer == "" or payee == "" or payer == payee:
		return 0
	var id := _next_id
	_next_id += 1
	var nd := first_due if first_due >= 0 else _day + period
	_ob[id] = [KINDS.find(kind), payer, payee, amt, period, nd, 0, 0, 0, S_LIVE, 0, tag, 0]
	_index(id, nd)
	return id


func post_wage(payer: String, payee: String, amt: int, period := 7, first_due := -1, tag := "") -> int:
	return post("wage", payer, payee, amt, period, first_due, tag)


func post_tax(payer: String, treasury: String, amt: int, period := 7, first_due := -1) -> int:
	return post("tax", payer, treasury, amt, period, first_due)


func post_rent(tenant: String, landlord: String, amt: int, period := 7, first_due := -1) -> int:
	return post("rent", tenant, landlord, amt, period, first_due)


## Upkeep of an army or garrison: tag "army" arms the desert / mutiny rungs.
func post_upkeep(payer: String, payee: String, amt: int, period := 7, first_due := -1, tag := "army") -> int:
	return post("upkeep", payer, payee, amt, period, first_due, tag)


## A loan: the principal moves now; weekly payment `pay` clears principal plus interest (rate percent per period).
func post_loan(lender: String, borrower: String, principal: int, pay: int, rate_pct := 2, period := 7) -> int:
	if principal <= 0 or pay <= 0 or not _take(lender, principal):
		return 0
	var id := post("loan", borrower, lender, pay, period)
	if id == 0:
		_give(lender, principal)
		return 0
	var r: Array = _ob[id]
	r[REM] = principal
	r[RATE] = rate_pct
	_give(borrower, principal)
	_log_out(lender, "loan", principal)
	_log_in(borrower, "loan", principal)
	return id


## A contract payment (recruitment / LW `ct:n` terms): same shape as a wage with its own summary line.
func post_contract(payer: String, payee: String, amt: int, period := 7, first_due := -1, tag := "") -> int:
	return post("contract", payer, payee, amt, period, first_due, tag)


func cancel(id: int) -> bool:
	if not _ob.has(id):
		return false
	var r: Array = _ob[id]
	r[ST] = S_ENDED
	return true


func obligation(id: int) -> Dictionary:
	if not _ob.has(id):
		return {}
	var r: Array = _ob[id]
	return {"kind": KINDS[int(r[K])], "payer": r[PAYER], "payee": r[PAYEE], "amt": r[AMT], "period": r[PER], "next": r[NEXT], "missed": r[MISS],
		"arrears": r[ARR], "rem": r[REM], "state": ["live", "ended", "paid"][int(r[ST])], "tag": r[TAG]}


func live_count() -> int:
	var n := 0
	for id: int in _ob:
		if int((_ob[id] as Array)[ST]) == S_LIVE:
			n += 1
	return n


func _index(id: int, day: int) -> void:
	if not _by_day.has(day):
		_by_day[day] = []
	(_by_day[day] as Array).append(id)


# ------------------------------------------------------------------ settling

## Settles every period of one obligation that is due by `upto` in one step (closed form), then the shortage ladder.
func _settle(id: int, upto: int) -> void:
	var r: Array = _ob[id]
	if int(r[ST]) != S_LIVE or int(r[NEXT]) > upto:
		return
	var per := int(r[PER])
	var n := (upto - int(r[NEXT])) / per + 1
	var amt := int(r[AMT])
	var is_loan := int(r[K]) == KINDS.find("loan")
	var due := 0
	var rem_after := 0
	var grown := 0
	if is_loan:
		# n periods in closed form: balance grows by g each period and `amt` comes off (an annuity), never a loop over periods
		var g := 1.0 + float(r[RATE]) / 100.0
		var gn := pow(g, float(n))
		var s_n := (gn - 1.0) / (g - 1.0) if g > 1.0 else float(n)
		grown = int(ceil(float(r[REM]) * gn))
		due = int(r[ARR]) + n * amt
		rem_after = int(ceil(float(int(r[REM]) - int(r[ARR])) * gn - float(amt) * s_n))
		if rem_after <= 0:
			due = int(r[ARR]) + _payoff(float(int(r[REM]) - int(r[ARR])), amt, g)      # the loan ends inside this span: pay exactly what clears it
	else:
		due = int(r[ARR]) + n * amt
	var payer := String(r[PAYER])
	var pay := mini(due, maxi(0, balance(payer)))
	if pay > 0 and _take(payer, pay):
		_deposit(String(r[PAYEE]), pay, KINDS[int(r[K])], payer)
		_log_out(payer, KINDS[int(r[K])], pay)
		stats["paid"] = int(stats["paid"]) + pay
		_district_pay(payer, String(r[PAYEE]), KINDS[int(r[K])], pay)
		if is_loan:
			r[REM] = maxi(0, rem_after) if pay >= due else maxi(0, grown - pay)
	else:
		pay = 0
		if is_loan:
			r[REM] = grown
	r[NEXT] = int(r[NEXT]) + n * per
	if is_loan and int(r[REM]) <= 0:
		r[ST] = S_PAID
		r[ARR] = 0
		r[MISS] = 0
		return
	if pay >= due:
		r[ARR] = 0
		r[MISS] = 0
	else:
		r[ARR] = due - pay
		_district_pay(payer, String(r[PAYEE]), KINDS[int(r[K])], -(due - pay))
		var short_periods := (due - pay + amt - 1) / amt
		r[MISS] = mini(int(r[MISS]) + maxi(1, mini(n, short_periods)), 9999) if pay < due else 0
		stats["late"] = int(stats["late"]) + 1
		_ladder(id, upto)
	if int(r[ST]) == S_LIVE:
		_index(id, int(r[NEXT]))


## Total paid to clear a loan of `bal` at `amt` a period with growth g per period (closed form: k payments, the last one partial).
static func _payoff(bal: float, amt: int, g: float) -> int:
	var k := 1
	if g > 1.0:
		var x := 1.0 - bal * (g - 1.0) / float(amt)
		k = 1 if x <= 0.0 else maxi(1, int(ceil(-log(x) / log(g))))
	else:
		k = maxi(1, int(ceil(bal / float(amt))))
	var gk := pow(g, float(k - 1))
	var s_k := (gk - 1.0) / (g - 1.0) if g > 1.0 else float(k - 1)
	var left := bal * gk - float(amt) * s_k
	return amt * (k - 1) + int(ceil(maxf(0.0, left) * g))


func _ladder(id: int, day: int) -> void:
	var r: Array = _ob[id]
	var payee := String(r[PAYEE])
	var payer := String(r[PAYER])
	var kind: String = KINDS[int(r[K])]
	if _kind(payee) != "ch" and _kind(payee) != "fo":          # "fo:<fid>" is a follower (recruitment acts on its departures)
		_warn("short:%d" % id, "%s cannot pay %s %d gold of %s." % [payer, payee, int(r[ARR]), kind])
		return
	var t := traits(payee)
	var treasurer := String((_stew.get(payer, {}) as Dictionary).get("ch", "")) == payee
	var step := rung(float(t["loyalty"]), float(t["honesty"]), int(r[MISS]), kind, treasurer, (int(r[FLAGS]) & 1) == 1)
	match step:
		"wait":
			if int(r[MISS]) == 1:
				_warn("late:%d" % id, "%s is paid late (%d gold owed). They wait." % [payee, int(r[ARR])])
		"demand":
			r[FLAGS] = int(r[FLAGS]) | 1
			r[AMT] = int(ceil(float(r[AMT]) * (100 + RAISE_PCT) / 100.0))
			_warn("raise:%d" % id, "%s demands a raise to %d gold for %s." % [payee, int(r[AMT]), kind])
		"embezzle":
			var take := mini(int(r[ARR]), maxi(0, balance(payer)))
			if take > 0 and _take(payer, take):
				_give(payee, take)
				_skim[payer] = int(_skim.get(payer, 0)) + take
				stats["embezzled"] = int(stats["embezzled"]) + take
				r[ARR] = int(r[ARR]) - take
		"resign", "desert", "mutiny":
			r[ST] = S_ENDED
			if int(r[ARR]) > 0:
				_claims[payee] = int(_claims.get(payee, 0)) + int(r[ARR])      # owed, never moved: a claim, not a deletion
			var key: String = {"resign": "resigned", "desert": "deserted", "mutiny": "mutiny"}[step]
			stats[key] = int(stats[key]) + 1
			if _depart.size() < DEPART_CAP:
				_depart.append({"id": id, "payee": payee, "payer": payer, "kind": kind, "why": step, "day": day})
			_warn("gone:%d" % id, "%s %s: unpaid %s (%d gold owed)." % [payee, {"resign": "resigns", "desert": "deserts", "mutiny": "mutinies"}[step], kind, int(r[ARR])])


## Departures since the last call; the owning module (recruitment, armies) acts on them.
## `mine` (optional Callable(dep) -> bool) takes only the departures the caller owns; the others stay queued for their module.
func take_departures(mine := Callable()) -> Array:
	if not mine.is_valid():
		var d := _depart
		_depart = []
		return d
	var got: Array = []
	var rest: Array = []
	for dep: Dictionary in _depart:
		if bool(mine.call(dep)):
			got.append(dep)
		else:
			rest.append(dep)
	_depart = rest
	return got


## A payer that keeps its own books (recruitment wages) tells the ledger it could not pay: the payee climbs the same shortage ladder
## as for a posted obligation. Moves no gold. Returns the rung ("wait", "demand", "resign", ...); a departure is queued for take_departures().
func report_arrears(payer: String, payee: String, kind: String, arrears: int, missed: int, day := -1) -> String:
	if arrears <= 0 or missed <= 0:
		return "ok"
	var d := day if day >= 0 else _day
	var t := traits(payee)
	var step := rung(float(t["loyalty"]), float(t["honesty"]), missed, kind, false, false)
	stats["late"] = int(stats["late"]) + 1
	match step:
		"wait":
			if missed == 1:
				_warn("late:%s" % payee, "%s is paid late (%d gold owed). They wait." % [payee, arrears])
		"resign", "desert", "mutiny":
			var key: String = {"resign": "resigned", "desert": "deserted", "mutiny": "mutiny"}[step]
			stats[key] = int(stats[key]) + 1
			_claims[payee] = int(_claims.get(payee, 0)) + arrears
			if _depart.size() < DEPART_CAP:
				_depart.append({"id": 0, "payee": payee, "payer": payer, "kind": kind, "why": step, "day": d})
	return step


## Accounts a steward runs.
func accounts_of(steward: String) -> Array:
	var out: Array = []
	for a: String in _stew:
		if String((_stew[a] as Dictionary)["ch"]) == steward:
			out.append(a)
	out.sort()
	return out


## Settlement id behind an account/record id ("tr:3", "ss:3", a business), -1 when none.
func _sid_of(acct: String) -> int:
	match _kind(acct):
		"tr", "ss", "st":
			return int(acct.get_slice(":", 1))
		"bz":
			var bm: Variant = _bm()
			var b: Dictionary = bm.biz(acct) if bm != null else {}
			return int(b.get("sid", -1)) if not b.is_empty() else -1
	return -1


## Feeds a payment (or a default, amt < 0) into the hidden district values of the settlement it lands in.
func _district_pay(payer: String, payee: String, kind: String, amt: int) -> void:
	if hub == null or kind == "loan":
		return
	var dv: Variant = hub.mod("districts")
	if dv == null:
		return
	var sid := _sid_of(payer)
	if sid < 0:
		sid = _sid_of(payee)
	if sid < 0:
		return
	var bm: Variant = _bm()
	var b: Dictionary = bm.biz(payer) if (bm != null and _kind(payer) == "bz") else {}
	var q := "other"
	if not b.is_empty():
		q = String(dv.BIZ_QUARTER.get(String(b["kind"]), "other"))
	dv.on_payment(sid, q, kind, amt)


func claims_of(who: String) -> int:
	return int(_claims.get(who, 0))


# ------------------------------------------------------------------ delegation and audit (MW-21)

func delegate(account: String, steward: String, weekly_budget: int, per_payment_limit: int) -> void:
	_stew[account] = {"ch": steward, "budget": weekly_budget, "limit": per_payment_limit, "spent": 0, "week": _day / 7}


func steward_of(account: String) -> String:
	return String((_stew.get(account, {}) as Dictionary).get("ch", ""))


func relieve(account: String) -> void:
	_stew.erase(account)


## The steward spends from the account within the budget and the per-payment limit. {ok, reason}.
func steward_pay(account: String, payee: String, amt: int, kind := "contract") -> Dictionary:
	var s: Dictionary = _stew.get(account, {})
	if s.is_empty():
		return {"ok": false, "reason": "no steward"}
	if int(s["week"]) != _day / 7:
		s["week"] = _day / 7
		s["spent"] = 0
	if amt > int(s["limit"]):
		stats["refused"] = int(stats["refused"]) + 1
		_warn("lim:%s" % account, "%s may not spend %d gold at once (limit %d)." % [s["ch"], amt, int(s["limit"])])
		return {"ok": false, "reason": "over the limit"}
	if int(s["spent"]) + amt > int(s["budget"]):
		stats["refused"] = int(stats["refused"]) + 1
		_warn("bud:%s" % account, "%s has spent this week's budget of %s." % [s["ch"], account])
		return {"ok": false, "reason": "over the budget"}
	if not _take(account, amt):
		return {"ok": false, "reason": "account is short"}
	s["spent"] = int(s["spent"]) + amt
	var got := amt
	if _dishonest(String(s["ch"])):
		_seq += 1
		if absi(hash([WorldSim.SEED, "skimx", account, _day, _seq])) % 100 < SKIM_CHANCE * 2:
			var cut := maxi(1, amt * SKIM_SHARE / 100)
			_give(String(s["ch"]), cut)
			_skim[account] = int(_skim.get(account, 0)) + cut
			stats["embezzled"] = int(stats["embezzled"]) + cut
			got = amt - cut
	_give(payee, got)
	_log_out(account, kind, amt)
	_log_in(payee, kind, got)
	return {"ok": true, "reason": ""}


## The owner pays a small fee and has the books checked: finds what the steward skimmed (or took as arrears), takes back what they can
## pay, and removes them. {found, recovered, owed, steward}. Cost AUDIT_FEE gold from `owner`, moved to the treasury of the audit (the
## account itself).
func audit(account: String, owner: String, _from_will := false) -> Dictionary:
	var s: Dictionary = _stew.get(account, {})
	if s.is_empty():
		return {"found": 0, "recovered": 0, "owed": 0, "steward": ""}
	var res := _audit_books(account, owner, s)
	# A follower steward (id "fo:<fid>"): follower_will reads the same audit, so both modules report one result.
	var ch := String(res["steward"])
	if not _from_will and ch.begins_with("fo:") and hub != null:
		var wm: Variant = hub.mod("will")
		if wm != null:
			res["will"] = wm.audit(ch.substr(3), true)
	return res


func _audit_books(account: String, owner: String, s: Dictionary) -> Dictionary:
	stats["audits"] = int(stats["audits"]) + 1
	if AUDIT_FEE > 0 and _take(owner, AUDIT_FEE):
		_give(account, AUDIT_FEE)
	var found := int(_skim.get(account, 0))
	var ch := String(s["ch"])
	var back := mini(found, maxi(0, balance(ch)))
	if back > 0 and _take(ch, back):
		_give(account, back)
		stats["recovered"] = int(stats["recovered"]) + back
	else:
		back = 0
	_skim.erase(account)
	if found > 0:
		_stew.erase(account)
		_warn("aud:%s" % account, "The audit of %s found %d gold taken by %s; %d recovered." % [account, found, ch, back])
	return {"found": found, "recovered": back, "owed": found - back, "steward": ch}


# ------------------------------------------------------------------ summary

func _log_in(acct: String, kind: String, amt: int) -> void:
	if not _wi.has(acct):
		_wi[acct] = {}
	(_wi[acct] as Dictionary)[kind] = int((_wi[acct] as Dictionary).get(kind, 0)) + amt


func _log_out(acct: String, kind: String, amt: int) -> void:
	if not _wx.has(acct):
		_wx[acct] = {}
	(_wx[acct] as Dictionary)[kind] = int((_wx[acct] as Dictionary).get(kind, 0)) + amt


## Lets another module log a flow it moved itself (recruitment wages, armies upkeep ...) into the weekly summary.
func note(payer: String, payee: String, kind: String, amt: int) -> void:
	if amt <= 0:
		return
	if payer != "":
		_log_out(payer, kind, amt)
	if payee != "":
		_log_in(payee, kind, amt)


func _scheduled(acct: String) -> Dictionary:
	var inc := 0
	var out := 0
	var lines: Array = []
	for id: int in _ob:
		var r: Array = _ob[id]
		if int(r[ST]) != S_LIVE:
			continue
		var wk := float(r[AMT]) * 7.0 / float(r[PER])
		if String(r[PAYER]) == acct:
			out += int(round(wk))
			lines.append({"id": id, "kind": KINDS[int(r[K])], "to": r[PAYEE], "amt": r[AMT], "next": r[NEXT], "dir": "out"})
		elif String(r[PAYEE]) == acct:
			inc += int(round(wk))
			lines.append({"id": id, "kind": KINDS[int(r[K])], "from": r[PAYER], "amt": r[AMT], "next": r[NEXT], "dir": "in"})
	return {"in": inc, "out": out, "lines": lines}


## Accounting for one account, for the UI: this week so far, past weeks, scheduled lines and the projected weekly change.
func summary(acct: String) -> Dictionary:
	var sc := _scheduled(acct)
	var wi: Dictionary = _wi.get(acct, {})
	var wx: Dictionary = _wx.get(acct, {})
	var si := 0
	var sx := 0
	for k: String in wi:
		si += int(wi[k])
	for k: String in wx:
		sx += int(wx[k])
	return {"account": acct, "balance": balance(acct), "income": wi.duplicate(), "expense": wx.duplicate(), "net": si - sx,
		"scheduled": sc["lines"], "projected_week": int(sc["in"]) - int(sc["out"]), "projected_in": sc["in"], "projected_out": sc["out"],
		"history": (_hist.get(acct, []) as Array).duplicate(true), "steward": steward_of(acct), "claims": claims_of(acct)}


func _roll_week(week: int) -> void:
	var seen: Dictionary = {}
	for a: String in _wi:
		seen[a] = true
	for a: String in _wx:
		seen[a] = true
	for a: String in seen:
		var wi: Dictionary = _wi.get(a, {})
		var wx: Dictionary = _wx.get(a, {})
		var si := 0
		var sx := 0
		for k: String in wi:
			si += int(wi[k])
		for k: String in wx:
			sx += int(wx[k])
		var h: Array = _hist.get(a, [])
		h.append({"w": week, "in": si, "out": sx, "net": si - sx})
		while h.size() > HIST_WEEKS:
			h.pop_front()
		_hist[a] = h
	_wi.clear()
	_wx.clear()


# ------------------------------------------------------------------ warnings

func _warn(key: String, text: String) -> void:
	if _warned_today >= WARN_CAP:
		return
	if _warn_at.has(key) and _day - int(_warn_at[key]) < WARN_DAYS:
		return
	_warn_at[key] = _day
	_warned_today += 1
	_out.append(text)


# ------------------------------------------------------------------ ticks

func _due_ids(day: int) -> Array:
	var ids: Array = []
	var gone: Array = []
	for d: int in _by_day:
		if d <= day:
			ids.append_array(_by_day[d])
			gone.append(d)
	for d: int in gone:
		_by_day.erase(d)
	ids.sort()
	return ids


func _chunk(day: int, ids: Array, part: int) -> Array:
	_day = day
	_out = []
	for k in range(part * CHUNK, mini(ids.size(), (part + 1) * CHUNK)):
		var id: int = ids[k]
		if _ob.has(id):
			_settle(id, day)
	return _out


func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	_day = day
	_warned_today = 0
	var ids := _due_ids(day)
	var jobs: Array = []
	for p in maxi(1, (ids.size() + CHUNK - 1) / CHUNK):
		jobs.append(_chunk.bind(day, ids, p))
	return jobs


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_week(week: int, _ctx: Dictionary) -> Array:
	_roll_week(week)
	_prune()
	return []


## Finished obligations leave the table after a week (their history is in the summaries).
func _prune() -> void:
	var dead: Array = []
	for id: int in _ob:
		if int((_ob[id] as Array)[ST]) != S_LIVE and int((_ob[id] as Array)[NEXT]) < _day - 7:
			dead.append(id)
	for id: int in dead:
		_ob.erase(id)


## `days` passed unobserved: every obligation settles all its due periods in one step (O(obligations)).
func catch_up(days: int, _ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	var target := _day + days
	_warned_today = 0
	_out = []
	for id: int in _due_ids(target):
		if _ob.has(id):
			_settle(id, target)
	_day = target
	var out := _out
	_out = []
	return out


# ------------------------------------------------------------------ save

func _enc(id: String) -> Variant:
	for i in 3:
		var v: Variant = Codec.enc_id(id, ["ch", "org", "bz"][i])
		if v is int:
			return [i, v]
	return id


func _dec(v: Variant) -> String:
	if v is Array:
		return Codec.dec_id(int((v as Array)[1]), ["ch", "org", "bz"][int((v as Array)[0])])
	return String(v)


func serialize() -> Dictionary:
	var rows: Array = []
	var ids: Array = _ob.keys()
	ids.sort()
	for id: int in ids:
		var r: Array = _ob[id]
		rows.append([id, r[K], _enc(String(r[PAYER])), _enc(String(r[PAYEE])), r[AMT], r[PER], r[NEXT], r[MISS], r[ARR], r[REM], r[ST], r[FLAGS], r[TAG], r[RATE]])
	var st := {}
	for a: String in _stew:
		var s: Dictionary = _stew[a]
		st[a] = [s["ch"], s["budget"], s["limit"], s["spent"], s["week"]]
	return {"v": 1, "day": _day, "n": _next_id, "seq": _seq, "ob": rows, "acct": _acct.duplicate(), "stew": st, "skim": _skim.duplicate(), "claims": _claims.duplicate(),
		"wi": _wi.duplicate(true), "wx": _wx.duplicate(true), "hist": _hist.duplicate(true), "warn": _warn_at.duplicate(), "dep": _depart.duplicate(true), "stats": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_ob.clear()
	_by_day.clear()
	_day = int(d.get("day", 0))
	_next_id = int(d.get("n", 1))
	_seq = int(d.get("seq", 0))
	for x: Variant in d.get("ob", []):
		var a: Array = x
		var id := int(a[0])
		_ob[id] = [int(a[1]), _dec(a[2]), _dec(a[3]), int(a[4]), int(a[5]), int(a[6]), int(a[7]), int(a[8]), int(a[9]), int(a[10]), int(a[11]), String(a[12]), int(a[13])]
		if int(a[10]) == S_LIVE:
			_index(id, int(a[6]))
	_acct.clear()
	for k: String in d.get("acct", {}):
		_acct[k] = int(d["acct"][k])
	_stew.clear()
	for k: String in d.get("stew", {}):
		var s: Array = d["stew"][k]
		_stew[k] = {"ch": String(s[0]), "budget": int(s[1]), "limit": int(s[2]), "spent": int(s[3]), "week": int(s[4])}
	_skim.clear()
	for k: String in d.get("skim", {}):
		_skim[k] = int(d["skim"][k])
	_claims.clear()
	for k: String in d.get("claims", {}):
		_claims[k] = int(d["claims"][k])
	_wi = _ints2(d.get("wi", {}))
	_wx = _ints2(d.get("wx", {}))
	_hist.clear()
	for a: String in d.get("hist", {}):
		var ring: Array = []
		for w: Dictionary in d["hist"][a]:
			ring.append({"w": int(w["w"]), "in": int(w["in"]), "out": int(w["out"]), "net": int(w["net"])})
		_hist[a] = ring
	_warn_at.clear()
	for k: String in d.get("warn", {}):
		_warn_at[k] = int(d["warn"][k])
	_depart.clear()
	for x: Dictionary in d.get("dep", []):
		_depart.append({"id": int(x["id"]), "payee": String(x["payee"]), "payer": String(x["payer"]), "kind": String(x["kind"]), "why": String(x["why"]), "day": int(x["day"])})
	var sd: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(sd.get(k, 0))


func _ints2(src: Dictionary) -> Dictionary:
	var out := {}
	for a: String in src:
		out[a] = {}
		for k: String in src[a]:
			out[a][k] = int(src[a][k])
	return out
