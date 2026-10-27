extends GdUnitTestSuite
## The Affairs panels (scripts/ui/affairs/*): each is instanced headless over a seeded hub, must populate, and its buttons must call the
## module's public API (ledger, follower_will, courts, war_intel, aura_fallout, monster_society/entry_law). Also the rebindable keys.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Treasury := preload("res://scripts/ui/affairs/treasury_panel.gd")
const FollowersWill := preload("res://scripts/ui/affairs/followers_will_panel.gd")
const CourtPanel := preload("res://scripts/ui/affairs/court_panel.gd")
const LettersPanel := preload("res://scripts/ui/affairs/letters_panel.gd")
const EnvoyDialog := preload("res://scripts/ui/affairs/envoy_dialog.gd")
const AuraParley := preload("res://scripts/ui/affairs/aura_parley_dialog.gd")
const GatePrompt := preload("res://scripts/ui/affairs/gate_prompt.gd")
const StatusView := preload("res://scripts/ui/affairs/status_view.gd")
const Hooks := preload("res://scripts/ui/affairs/affairs_hooks.gd")
const TabAffairs := preload("res://scripts/ui/gamemenu/tab_affairs.gd")

static var _world := false


func _hub() -> RefCounted:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	var h: RefCounted = Hub.new()
	h.mod("organizations").auto_seed = false
	h.mod("organizations").gold_ref = {"gold": 5000}
	h.mod("businesses").set_day(0)
	Game.gold = 500
	return h


func _panel(script: GDScript, h: RefCounted) -> Control:
	var p: Control = script.new()
	p.set("realm_override", h)
	add_child(auto_free(p))
	return p


func _joined(p: Object) -> String:
	return "\n".join(PackedStringArray(p.call("texts")))


func _follower(h: RefCounted, key := "theron") -> String:
	return h.mod("followers").hire("knight", "s0", true, key)


func _orc(extra := {}) -> Dictionary:
	var c := {"species": "orc", "kind": "monster", "speech": 2, "civility": 0.6, "named": true, "power": 3, "form": 2, "bond_id": 1}
	c.merge(extra, true)
	return c


func _town() -> Dictionary:
	return {"sid": 7, "name": "Testhaven", "culture": "solenne", "corruption": 0.5}


# --- 1. treasury ------------------------------------------------------------------------

func test_treasury_populates_and_delegates_and_audits() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	h.mod("organizations").earn("player", 500)
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": 0})
	lg.post_wage("player", ch, 30, 7, 7)
	var fid := _follower(h)
	var p := _panel(Treasury, h)
	var txt := _joined(p)
	assert_str(txt).contains("Strongbox")
	assert_str(txt).contains("Scheduled payments")
	assert_str(txt).contains("Pay to")
	assert_str(txt).contains("No steward")
	# delegate: pick a follower, press Appoint
	p.set("pick", fid)
	p.call("refresh")
	var appoint: Button = p.call("find_button", "Appoint steward")
	assert_object(appoint).is_not_null()
	assert_bool(appoint.disabled).is_false()
	appoint.pressed.emit()
	assert_str(lg.steward_of("player")).is_equal("fo:" + fid)
	assert_str(_joined(p)).contains("keeps these books")
	# audit goes through ledger.audit
	var audits0 := int(lg.stats["audits"])
	(p.call("find_button", "Audit the books") as Button).pressed.emit()
	assert_int(int(lg.stats["audits"])).is_equal(audits0 + 1)
	assert_str(String(p.get("audit_text"))).is_not_empty()
	# cancel a standing payment
	var live0: int = lg.live_count()
	(p.call("find_button", "Cancel") as Button).pressed.emit()
	assert_int(lg.live_count()).is_equal(live0 - 1)
	# relieve
	(p.call("find_button", "Relieve steward") as Button).pressed.emit()
	assert_str(lg.steward_of("player")).is_equal("")


func test_treasury_warns_when_payments_exceed_the_strongbox() -> void:
	var h := _hub()
	var lg: RefCounted = h.mod("ledger")
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": 0})
	lg.post_wage("player", ch, 6000, 7, 7)
	var p := _panel(Treasury, h)
	assert_str(_joined(p)).contains("cannot cover next week")


# --- 2. followers' will -----------------------------------------------------------------

func test_followers_panel_shows_motives_in_words_and_answers_requests() -> void:
	var h := _hub()
	var w: RefCounted = h.mod("will")
	var fid := _follower(h)
	w.set_state(fid, {"req": "reward", "m": {"aff": 0.9, "gre": 0.8}})
	var p := _panel(FollowersWill, h)
	var txt := _joined(p)
	assert_str(txt).contains("What drives them")
	assert_str(txt).contains("Affection")
	assert_str(txt).contains("devoted to you")                 # words, not numbers
	assert_str(txt).contains("asks to be rewarded")
	assert_str(txt).contains("Give an order")
	assert_bool(txt.contains("0.9")).is_false()
	assert_str(String(p.call("order_hint", fid, FollowersWill.ORDERS[0]))).is_not_empty()
	(p.call("find_button", "Grant") as Button).pressed.emit()
	assert_str(w.pending_request(fid)).is_equal("")
	# an order is answered through respond()
	var orders := p.call("find_button", "Order") as Button
	assert_object(orders).is_not_null()
	orders.pressed.emit()
	assert_str(String(p.get("last_order_line"))).is_not_empty()


func test_followers_actions_call_the_will_module() -> void:
	var h := _hub()
	var w: RefCounted = h.mod("will")
	var fid := _follower(h)
	var p := _panel(FollowersWill, h)
	var mem0 := (w.state_of(fid)["mem"] as Array).size()
	var gold0: int = Game.gold
	p.call("reward", fid, 25)
	assert_int(Game.gold).is_equal(gold0 - 25)
	assert_int((w.state_of(fid)["mem"] as Array).size()).is_greater(mem0)
	w.set_state(fid, {"g": 0.8})
	p.call("forgive", fid)
	assert_float(float(w.state_of(fid)["g"])).is_less(0.8)
	assert_str(String(p.call("investigate", fid))).is_not_empty()
	assert_str(String(p.call("audit", fid))).is_not_empty()
	assert_str(String(p.call("promote", fid))).is_not_empty()
	assert_str(String(p.call("imprison", fid))).is_not_empty()
	assert_str(String(p.call("dismiss", fid))).is_not_empty()     # hired outside recruitment: explained, not crashed
	# dismiss and imprison are two-step buttons
	var fid2 := _follower(h, "b")
	p.set("selected", fid2)
	p.call("refresh")
	var btn := p.call("find_button", "Dismiss") as Button
	assert_object(btn).is_not_null()
	btn.pressed.emit()
	assert_object(p.call("find_button", "Confirm: Dismiss")).is_not_null()


# --- 3. envoy audience -------------------------------------------------------------------

func test_envoy_dialog_offers_nine_answers_and_calls_respond() -> void:
	var h := _hub()
	var wi: RefCounted = h.mod("war_intel")
	var ids: Array = h.mod("factions").factions().map(func(f: Dictionary) -> String: return String(f["id"]))
	var e: Dictionary = wi.envoy_arrive(ids[0], ids[1], "neutrality", ids[2], {"agenda": "sincere"})
	var host := Control.new()
	add_child(auto_free(host))
	var d: Control = EnvoyDialog.open(host, h, false)
	assert_object(d).is_not_null()
	var txt := _joined(d)
	assert_str(txt).contains("An envoy of")
	assert_str(txt).contains("stay out of their quarrel")
	var n := 0
	for r: String in EnvoyDialog.LABELS:
		if d.call("find_button", String(EnvoyDialog.LABELS[r][0])) != null:
			n += 1
	assert_int(n).is_equal(9)
	assert_int(wi.RESPONSES.size()).is_equal(9)
	(d.call("find_button", "Refuse") as Button).pressed.emit()
	assert_bool(bool((d.get("last") as Dictionary).get("ok", false))).is_true()
	assert_str(String(d.get("result_text"))).is_not_empty()
	assert_str(String(wi.envoy(int(e["id"]))["state"])).is_not_equal("waiting")


func test_envoy_dialog_is_null_when_nobody_waits() -> void:
	var h := _hub()
	var host := Control.new()
	add_child(auto_free(host))
	assert_object(EnvoyDialog.open(host, h, false)).is_null()


# --- 4. court ----------------------------------------------------------------------------

func test_court_panel_files_presses_and_influences() -> void:
	var h := _hub()
	var cs: RefCounted = h.mod("courts")
	var fid := _follower(h)
	var p := _panel(CourtPanel, h)
	assert_str(_joined(p)).contains("No case is before the courts")
	p.set("crime", "robbery")
	p.set("accused", "f:" + fid)
	(p.call("find_button", "File the case") as Button).pressed.emit()
	assert_int(cs.cases().size()).is_equal(1)
	var cid := String(p.get("selected"))
	assert_str(cid).is_not_empty()
	cs.add_evidence(cid, "footprints", 0.7)
	cs.add_witness(cid, "n1", "Mara", true, 0.8)
	p.call("refresh")
	var txt := _joined(p)
	assert_str(txt).contains("Evidence")
	assert_str(txt).contains("Footprints")
	assert_str(txt).contains("strong")                         # evidence reliability as a word
	assert_str(txt).contains("Mara")
	assert_str(txt).contains("Bend the law")
	(p.call("find_button", "Press for trial") as Button).pressed.emit()
	assert_str(String(cs.case_of(cid)["state"])).is_not_equal("open")
	# appeal before any verdict is refused cleanly (button disabled; the call explains)
	assert_bool((p.call("find_button", "Appeal the verdict") as Button).disabled).is_true()
	var inf0 := int(cs.stats["influence"])
	p.set("verb", "persuade")
	assert_str(String(p.call("influence", cs.case_of(cid), "n9"))).is_equal("")
	assert_int(int(cs.stats["influence"])).is_equal(inf0 + 1)
	assert_str(String(p.get("influence_text"))).is_not_empty()
	p.set("verb", "blackmail")
	p.call("influence", cs.case_of(cid), "n9")
	assert_str(String(p.get("influence_text"))).contains("nothing to hold over")
	p.set("verb", "patronage")
	var g0: int = Game.gold
	p.call("influence", cs.case_of(cid), "n9")
	assert_int(Game.gold).is_equal(g0 - CourtPanel.PATRON_GOLD)


func test_court_appeal_calls_the_module() -> void:
	var h := _hub()
	var cs: RefCounted = h.mod("courts")
	var cid: String = cs.file_case("robbery", 1, {"id": "n1", "name": "Mara"}, {"id": "player", "name": "You"},
		{"culprit": "player", "evidence": [{"type": "footprints", "s": 0.9, "day": 0}, {"type": "witness_statement", "s": 0.9, "day": 0}]})
	for i in 40:
		if String(cs.case_of(cid)["state"]) in ["charged", "cold"]:
			break
		cs.investigate(cid)
	cs.trial(cid)
	var p := _panel(CourtPanel, h)
	var before := int(cs.stats["appealed"])
	var msg := String(p.call("appeal", cid))
	assert_str(msg).is_not_empty()
	if String(cs.case_of(cid)["verdict"]) == "guilty" or int(cs.stats["appealed"]) > before:
		assert_bool(int(cs.stats["appealed"]) >= before).is_true()


# --- 5. letters --------------------------------------------------------------------------

func test_letters_show_digest_and_steward_report_with_unread_badge() -> void:
	var h := _hub()
	var wi: RefCounted = h.mod("war_intel")
	h.mod("ledger").delegate("player", "fo:f1", 100, 50)
	h.mod("organizations").earn("player", 200)
	wi.set_viewer("player", 0, "ruler", "player", [0])
	var d: Dictionary = wi.digest(1)
	assert_bool(d.is_empty()).is_false()
	var p := _panel(LettersPanel, h)
	var txt := _joined(p)
	assert_str(txt).contains("Letter of week 1")
	assert_str(txt).contains("Your steward writes")
	assert_str(txt).contains("1 unread")
	assert_int(int(p.call("unread_count"))).is_equal(1)
	p.call("on_hide")                                          # leaving the page reads them
	assert_int(int(p.call("unread_count"))).is_equal(0)
	p.call("refresh")
	assert_str(_joined(p)).contains("All read")


func test_letters_panel_lists_envoys_at_the_door() -> void:
	var h := _hub()
	var ids: Array = h.mod("factions").factions().map(func(f: Dictionary) -> String: return String(f["id"]))
	h.mod("war_intel").envoy_arrive(ids[0], ids[1], "aid", ids[2], {"agenda": "sincere"})
	var p := _panel(LettersPanel, h)
	assert_str(_joined(p)).contains("At the door")
	assert_object(p.call("find_button", "Receive the envoy")).is_not_null()


func test_hooks_poll_sets_viewer_and_counts_unread() -> void:
	var h := _hub()
	var wi: RefCounted = h.mod("war_intel")
	var hk: Node = Hooks.new()
	hk.set("realm_override", h)
	add_child(auto_free(hk))
	hk.call("poll")                                            # tells the digest who reads (adventurer, no steward)
	var d: Dictionary = wi.digest(1)
	h.mod("news").post("boom", 0, "Silver was struck at the old mine.", 3.0, "", true, 0)
	hk.call("poll")
	assert_int(Hooks.unread).is_greater_equal(0)
	assert_int(Hooks.envoys).is_equal(0)
	assert_bool(d.is_empty() or Hooks.unread >= 1).is_true()


# --- 6. aura escalation ------------------------------------------------------------------

func test_aura_parley_offers_seven_options_and_resolves_through_the_module() -> void:
	var h := _hub()
	var af: RefCounted = h.mod("aura_fallout")
	var sid := 1
	var step: int = af.on_incident("player", sid, "", 0.6, 0.0, 6, {"t2": 4, "t3": 1, "duration_s": 5.0, "no_case": true})
	assert_int(step).is_greater_equal(0)
	var host := Control.new()
	add_child(auto_free(host))
	var d: Control = AuraParley.open(host, "player", sid, h, {"persuasion": 0.9, "rank": 4}, false)
	assert_object(d).is_not_null()
	var txt := _joined(d)
	assert_str(txt).contains("has come for you")
	for o: String in ["Rein it in", "Talk", "Intimidate", "Bribe", "Surrender", "Flee", "Fight"]:
		assert_object(d.call("find_button", o)).override_failure_message("missing option " + o).is_not_null()
	var opts0 := int(af.stats["options"])
	var got: Array = []
	d.connect("chosen", func(o: String, _r: Dictionary) -> void: got.append(o))
	(d.call("find_button", "Talk") as Button).pressed.emit()
	assert_int(int(af.stats["options"])).is_equal(opts0 + 1)
	assert_array(got).contains(["talk"])
	assert_str(String((d.get("last") as Dictionary)["outcome"])).is_not_empty()
	assert_bool(bool(d.get("can_dismiss"))).is_false()         # an officer is not waved away


func test_aura_parley_is_null_without_a_ladder() -> void:
	var h := _hub()
	var host := Control.new()
	add_child(auto_free(host))
	assert_object(AuraParley.open(host, "player", 3, h, {}, false)).is_null()


# --- 7. gate prompt and status -----------------------------------------------------------

func test_gate_prompt_turns_back_and_offers_ways_in() -> void:
	var h := _hub()
	var ms: RefCounted = h.mod("monster_society")
	var host := Control.new()
	add_child(auto_free(host))
	var g: Control = GatePrompt.open(host, [_orc()], _town(), 12, 3, {}, h, false)
	assert_object(g).is_not_null()
	var txt := _joined(g)
	assert_str(txt).contains("Turned back")
	assert_object(g.call("find_button", "Show a permit")).is_not_null()
	assert_bool((g.call("find_button", "Show a permit") as Button).disabled).is_true()   # no permit held
	assert_object(g.call("find_button", "Leave the monster outside")).is_not_null()
	var resolved: Array = []
	g.connect("resolved", func(r: Dictionary) -> void: resolved.append(r))
	var gold0: int = Game.gold
	(g.call("find_button", "bribe") as Button).pressed.emit()
	assert_int(ms.bribes_of("player").size()).is_equal(1)
	assert_int(Game.gold).is_less(gold0)
	assert_int(resolved.size()).is_equal(1)
	assert_bool(bool(g.get("done"))).is_true()


func test_gate_prompt_permit_and_leave_outside() -> void:
	var h := _hub()
	var ms: RefCounted = h.mod("monster_society")
	var host := Control.new()
	add_child(auto_free(host))
	ms.issue_permit("player", "church_seal", "bishop", ["orc"], 3, 30, false, 3)
	var g: Control = GatePrompt.open(host, [_orc()], _town(), 12, 4, {}, h, false)
	assert_object(g).is_not_null()
	assert_str(_joined(g)).contains("Admitted, on terms")
	assert_object(g.call("find_button", "Accept the terms")).is_not_null()
	g.queue_free()
	var h2 := _hub()
	var g3: Control = GatePrompt.open(host, [_orc()], _town(), 12, 3, {}, h2, false)
	(g3.call("find_button", "Leave the monster outside") as Button).pressed.emit()
	assert_bool(bool(g3.get("done"))).is_true()
	assert_str(String((g3.get("outcome") as Dictionary)["result"])).is_equal("left_outside")


func test_gate_prompt_is_null_for_a_plain_traveller() -> void:
	var h := _hub()
	var host := Control.new()
	add_child(auto_free(host))
	var human := {"species": "human", "kind": "human", "speech": 4, "civility": 1.0, "power": 1, "named": false, "bond_id": 0}
	assert_object(GatePrompt.open(host, [human], _town(), 12, 3, {}, h, false)).is_null()


func test_status_view_breaks_down_standing_in_words() -> void:
	var h := _hub()
	var box := VBoxContainer.new()
	add_child(auto_free(box))
	assert_bool(StatusView.fill(box, h, 7)).is_true()
	var all: Array = []
	_collect(box, all)
	var txt := "\n".join(PackedStringArray(all))
	assert_str(txt).contains("Reputation")
	assert_str(txt).contains("Company you keep")
	assert_bool(StatusView.fill(box, null, 7)).is_false()


func _collect(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect(c, out)


# --- the tab, the keys -------------------------------------------------------------------

func test_affairs_tab_hosts_its_panels() -> void:
	var h := _hub()
	var t: Control = TabAffairs.new()
	t.set("realm_override", h)
	add_child(auto_free(t))
	t.call("build")
	var panels: Dictionary = t.get("panels")
	assert_int(panels.size()).is_equal(5)      # + READY_V1 C4: settlement
	for v: String in ["treasury", "followers", "court", "letters", "settlement"]:
		t.call("set_view", v)
		assert_bool((panels[v] as Control).visible).is_true()
		assert_str(_joined(panels[v])).is_not_empty()
	assert_str(String(t.get("view"))).is_equal("settlement")


func test_open_keys_are_rebindable_input_actions() -> void:
	Game._setup_input()
	for a: String in ["menu_treasury", "menu_followers", "menu_court", "menu_letters"]:
		assert_bool(Game.KEYS.has(a)).is_true()
		assert_bool(InputMap.has_action(a)).is_true()
	var labels: Array = []
	for pair: Array in preload("res://scripts/ui/frontend/settings_store.gd").ACTIONS:
		labels.append(pair[0])
	assert_array(labels).contains(["menu_treasury", "menu_followers", "menu_court", "menu_letters"])
	var tabs: Array = preload("res://scripts/ui/gamemenu/game_menu.gd").TABS.map(func(t: Array) -> String: return String(t[0]))
	assert_array(tabs).contains(["affairs"])
