extends "res://scripts/ui/affairs/affairs_base.gd"
## TREASURY: one account of the scheduled realm ledger (scripts/realm/ledger.gd): this week's lines, what is scheduled,
## warnings, and steward delegation (delegate / relieve / audit). Public API only: ledger.summary, cancel, delegate, relieve, audit.

const BUDGET_STEP := 25
const LIMIT_STEP := 10

var account := "player"
var budget := 100
var limit := 40
var pick := ""                 # follower id chosen as steward
var audit_text := ""
var last_audit: Dictionary = {}


func _fill(b: VBoxContainer) -> void:
	var lg: Variant = mod("ledger")
	if lg == null:
		_dim(b, EMPTY)
		return
	var accts := _accounts()
	if not accts.has(account):
		account = "player"
	if accts.size() > 1:
		var fl := _flow(b)
		for a: String in accts:
			_chip(fl, "Your purse" if a == "player" else "Town " + nice(a), a == account, func() -> void: account = a)
	var s: Dictionary = lg.call("summary", account)
	_sec("Strongbox")
	var top := _card(b)
	_txt(top, "%s holds %d gold." % ["Your strongbox" if account == "player" else nice(account), int(s["balance"])], AF.TEXT, 19, "title")
	if account == "player":
		_dim(top, "Coin in your hand: %d." % int(Game.gold))
	_txt(top, "This week so far: %s." % _net_words(int(s["net"])), AF.TEXT)
	_txt(top, "The coming week looks like %s (in %d, out %d)." % [_net_words(int(s["projected_week"])), int(s["projected_in"]),
		int(s["projected_out"])], AF.TEXT_DIM)
	_flows(top, "Came in", s["income"])
	_flows(top, "Went out", s["expense"])
	var hist: Array = s["history"]
	if not hist.is_empty():
		var parts: Array = []
		for h: Dictionary in hist.slice(maxi(0, hist.size() - 4)):
			parts.append("week %d: %+d" % [int(h["w"]), int(h["net"])])
		_dim(top, "Recent weeks: " + ", ".join(PackedStringArray(parts)) + ".")
	_sec("Warnings")
	var warns := warnings(s)
	if warns.is_empty():
		_dim(b, "Nothing alarming in the books.")
	for w: String in warns:
		_txt(b, w, Kit.BAD)
	_sec("Scheduled payments")
	var lines: Array = s["scheduled"]
	if lines.is_empty():
		_dim(b, "No standing payments.")
	for l: Dictionary in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		b.add_child(row)
		var out := String(l["dir"]) == "out"
		var who := nice(String(l.get("to", l.get("from", "")))) 
		var text := "%s %s %d gold (%s), next on day %d" % ["Pay" if out else "Receive", ("to " if out else "from ") + who, int(l["amt"]),
			String(l["kind"]), int(l["next"])]
		row.add_child(Kit.lbl(text, 16, AF.TEXT, true))
		if out:
			var id := int(l["id"])
			var cb := Kit.button("Cancel", false, 40, 14)
			cb.pressed.connect(func() -> void:
				cancel_payment(id)
				_redraw())
			row.add_child(cb)
	_sec("Steward")
	_steward_block(b, s)


## Derived from the summary only (ledger warnings are one-shot messages; these stay visible while true).
func warnings(s: Dictionary) -> Array:
	var out: Array = []
	var bal := int(s["balance"])
	var pw := int(s["projected_week"])
	if int(s["projected_out"]) > bal:
		out.append("The strongbox cannot cover next week's payments (%d due, %d held)." % [int(s["projected_out"]), bal])
	elif pw < 0:
		out.append("At this rate the strongbox empties in about %d weeks." % maxi(1, int(ceil(float(bal) / float(-pw)))))
	if int(s["claims"]) > 0:
		out.append("Unpaid claims stand against this account: %d gold." % int(s["claims"]))
	if String(s["steward"]) != "" and audit_text == "":
		out.append("%s has handled this money and has not been audited." % nice(String(s["steward"])))
	return out


func _net_words(n: int) -> String:
	if n == 0:
		return "even"
	return "%d gold %s" % [absi(n), "ahead" if n > 0 else "behind"]


func _flows(c: Container, label: String, d: Dictionary) -> void:
	if d.is_empty():
		return
	var parts: Array = []
	for k: String in d:
		parts.append("%s %d" % [k, int(d[k])])
	parts.sort()
	_dim(c, "%s: %s." % [label, ", ".join(PackedStringArray(parts))])


func _accounts() -> Array:
	var out: Array = ["player"]
	var w: Variant = mod("will")
	if w != null:
		for sid: Variant in w.call("governed"):
			out.append("tr:%d" % int(sid))
	return out


func _steward_block(b: VBoxContainer, s: Dictionary) -> void:
	var card := _card(b)
	var cur := String(s["steward"])
	if cur == "":
		_txt(card, "No steward keeps these books. You spend and receive everything yourself.", AF.TEXT_DIM)
	else:
		_txt(card, "%s keeps these books." % (follower_name(cur.substr(3)) if cur.begins_with("fo:") else nice(cur)), AF.TEXT, 17, "title")
	var fo: Variant = mod("followers")
	var list: Array = fo.call("list") if fo != null else []
	if not list.is_empty():
		_dim(card, "Choose someone you trust with the key:")
		var fl := _flow(card)
		for f: Dictionary in list:
			var fid := String(f["id"])
			_chip(fl, String(f["name"]), pick == fid, func() -> void: pick = fid)
	else:
		_dim(card, "You have no followers to name steward.")
	var spin := _flow(card)
	_txt(spin, "Weekly budget: %d" % budget, AF.TEXT)
	_btn(spin, "-", func() -> void: budget = maxi(BUDGET_STEP, budget - BUDGET_STEP))
	_btn(spin, "+", func() -> void: budget += BUDGET_STEP)
	_txt(spin, "Per payment: %d" % limit, AF.TEXT)
	_btn(spin, "-", func() -> void: limit = maxi(LIMIT_STEP, limit - LIMIT_STEP))
	_btn(spin, "+", func() -> void: limit += LIMIT_STEP)
	var acts := _flow(card)
	_btn(acts, "Appoint steward", appoint, true, pick == "")
	_btn(acts, "Relieve steward", relieve, false, cur == "")
	_btn(acts, "Audit the books", audit_now, false, cur == "")
	if audit_text != "":
		_txt(card, audit_text, AF.GOLD_BRIGHT, 16, "italic")


# ------------------------------------------------------------------ actions (each calls the module API)

func appoint() -> String:
	var lg: Variant = mod("ledger")
	if lg == null or pick == "":
		return ""
	lg.call("delegate", account, "fo:" + pick, budget, limit)
	audit_text = ""
	return "%s now keeps the books, up to %d a week and %d a payment." % [follower_name(pick), budget, limit]


func relieve() -> String:
	var lg: Variant = mod("ledger")
	if lg == null:
		return ""
	lg.call("relieve", account)
	return "The steward is relieved of the key."


func audit_now() -> String:
	var lg: Variant = mod("ledger")
	if lg == null:
		return ""
	last_audit = lg.call("audit", account, "player")
	var found := int(last_audit.get("found", 0))
	if String(last_audit.get("steward", "")) == "":
		audit_text = "There was no steward to audit."
	elif found > 0:
		audit_text = "The books are short by %d gold. %d was recovered%s. The steward is dismissed from the post." % [found,
			int(last_audit.get("recovered", 0)), "" if int(last_audit.get("owed", 0)) == 0 else ", %d is still owed" % int(last_audit["owed"])]
	else:
		audit_text = "The books balance. Nothing was taken."
	return audit_text


func cancel_payment(id: int) -> String:
	var lg: Variant = mod("ledger")
	if lg != null and bool(lg.call("cancel", id)):
		return "The standing payment is cancelled."
	return ""
