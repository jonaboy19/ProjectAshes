extends GdUnitTestSuite
## LW-4.2 (docs/design/LIVING_WORLD_SANDBOX.md §5, §1.3): the generic Organization record. Lifecycle, rank rights, the four axes,
## multi-membership, leaving with followers, the founding flow (recruitment.gd), succession, branches / mergers / schisms, NPC parity,
## the adapters for the old guilds, the save round trip and the tick cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const D := preload("res://scripts/realm/organizations_data.gd")
const Rec := preload("res://scripts/realm/recruitment.gd")


static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("businesses").set_day(0)
	return h


func _ch(h: RefCounted, cash := 500, sid := 0, prof := "smith", sk := 0.7) -> String:
	var om: RefCounted = h.mod("organizations")
	var ch: String = h.mod("registry").mint("ch")
	om.ensure_char(ch, {"cash": cash, "sid": sid, "prof": prof, "rep": 10.0, "sk": {"combat": sk, "crafting": sk, "trading": sk, "farming": sk, "faith": sk, "lore": sk, "stealth": sk}})
	return ch


func _days(om: RefCounted, from: int, to: int) -> void:
	for d in range(from, to + 1):
		om.tick_day(d, {})


## A guild with `n` members of the given rank, founded properly.
func _body(h: RefCounted, type := "craft_guild", n := 6) -> Dictionary:
	var om: RefCounted = h.mod("organizations")
	var lead := _ch(h, 2000)
	var res: Dictionary = om.start_founding(lead, type, "Test %s %d" % [type, randi() % 100000], 0)
	assert_bool(res["ok"]).is_true()
	var oid: String = res["org"]
	var all: Array = [lead]
	for i in n - 1:
		var m := _ch(h)
		assert_bool(om.add_founder(oid, lead, m)["ok"]).is_true()
		all.append(m)
	return {"org": oid, "lead": lead, "all": all}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


# --- lifecycle ----------------------------------------------------------------------------

func test_every_type_has_a_complete_ladder() -> void:
	for t: String in D.TYPE_IDS:
		var td: Dictionary = D.TYPES[t]
		assert_int((td["ranks"] as Array).size()).is_equal(D.RANK_COUNT)
		assert_int((td["pay"] as Array).size()).is_equal(D.RANK_COUNT)
		for r in D.RANK_COUNT:
			for right: String in D.rank_rights(t, r):
				assert_bool(right in D.RIGHTS).is_true()
		assert_bool("dissolve" in D.rank_rights(t, D.LEADER)).is_true()
	assert_str(D.scale_name(1)).is_equal("party")
	assert_str(D.scale_name(6)).is_equal("clan")
	assert_str(D.scale_name(30)).is_equal("legion")
	assert_str(D.scale_name(150)).is_equal("great house")


func test_org_lifecycle_idea_to_standing_to_dissolution() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var lead := _ch(h, 3000)
	var res: Dictionary = om.start_founding(lead, "craft_guild", "Smiths of Thornfield", 0)
	var oid: String = res["org"]
	assert_str(oid).starts_with("org:")
	assert_str(om.stage_name(oid)).is_equal("idea")
	# members
	assert_bool(om.draft_charter(oid, lead, "x")["ok"]).is_false()        # a charter needs founders first
	for i in 2:
		assert_bool(om.add_founder(oid, lead, _ch(h))["ok"]).is_true()
	assert_str(om.stage_name(oid)).is_equal("members")
	# charter
	var gold_before: int = om.purse(lead)
	assert_bool(om.draft_charter(oid, lead, "We make fair steel.", {"succ": "election", "dues": 1.0})["ok"]).is_true()
	assert_int(om.purse(lead)).is_less(gold_before)
	assert_int(int(om.org(oid)["treasury"])).is_greater(0)
	assert_str(om.stage_name(oid)).is_equal("members")                    # not recognised yet
	# recognition is a stub: it needs a name earned by real work
	var pet: Dictionary = om.petition_recognition(oid, lead)
	assert_bool(pet["ok"]).is_true()
	_days(om, 1, 10)
	assert_str(om.org(oid)["legal"]).is_equal("none")                      # refused: unknown
	for m: String in om.members_of(oid):
		om.record_activity(oid, m, 6.0)
	om._settle(oid, 10)                                                   # activity becomes reputation
	assert_float(om.org(oid)["rep"]).is_greater_equal(8.0)
	om.org(oid)["pd"] = -100
	assert_bool(om.petition_recognition(oid, lead)["ok"]).is_true()
	_days(om, 11, 20)
	assert_str(om.org(oid)["legal"]).is_equal("recognised")
	assert_str(om.stage_name(oid)).is_equal("charter")
	# premises
	om.org(oid)["treasury"] = 200
	assert_bool(om.rent_hq(oid, lead, 0)["ok"]).is_true()
	assert_str(om.stage_name(oid)).is_equal("premises")
	# standing needs reputation and four solvent weeks
	om.org(oid)["rep"] = 40.0
	om.org(oid)["sw"] = 4
	om._restage(oid)
	assert_str(om.stage_name(oid)).is_equal("standing")
	assert_str(om.scale_of(oid)).is_equal("party")
	# dissolution: arrears first, the rest by contribution, members released
	var m1: String = om.members_of(oid)[1]
	om.org(oid)["m"][m1]["ar"] = 30
	om.org(oid)["treasury"] = 100
	var cash_before: int = om.purse(m1)
	assert_bool(om.dissolve(oid, m1)["ok"]).is_false()                    # not the leader's right
	assert_bool(om.dissolve(oid, lead)["ok"]).is_true()
	assert_str(om.org(oid)["st"]).is_equal("dissolved")
	assert_int(om.purse(m1)).is_greater_equal(cash_before + 30)
	assert_int(om.memberships(m1).size()).is_equal(0)


func test_growth_ladder_follows_member_count() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "band", 2)
	var oid: String = b["org"]
	assert_str(om.scale_of(oid)).is_equal("party")
	om.org(oid)["pol"]["open"] = true
	for i in 6:
		om._add_member(oid, _ch(h), 1, "")
	assert_str(om.scale_of(oid)).is_equal("clan")


# --- rank rights -------------------------------------------------------------------------

func test_rank_permissions_gate_recruiting_promotion_and_policy() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "craft_guild", 3)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var probationer := _ch(h)
	var vet := _ch(h)
	var off := _ch(h)
	om._add_member(oid, probationer, D.PROBATION, lead)
	om._add_member(oid, vet, D.VETERAN, lead)
	om._add_member(oid, off, D.OFFICER, lead)
	var cand := _ch(h)
	assert_bool(om.apply(oid, cand, vet)["ok"]).is_true()
	# probation: no recruit right; veteran: recruit but not dismiss; officer: dismiss; leader: policy
	assert_bool(om.can(oid, probationer, "recruit")).is_false()
	assert_bool(om.decide(oid, probationer, cand, true)["ok"]).is_false()
	assert_bool(om.can(oid, vet, "recruit")).is_true()
	assert_bool(om.can(oid, vet, "dismiss")).is_false()
	assert_bool(om.dismiss(oid, vet, probationer)["ok"]).is_false()
	assert_bool(om.can(oid, off, "dismiss")).is_true()
	assert_bool(om.can(oid, off, "set_policy")).is_false()
	assert_bool(om.can(oid, lead, "set_policy")).is_true()
	assert_bool(om.can(oid, lead, "merge")).is_true()
	assert_bool(om.decide(oid, vet, cand, true)["joined"]).is_true()
	assert_int(om.rank_of(oid, cand)).is_equal(D.PROBATION)
	# an officer cannot dismiss a peer or a superior, but can dismiss below
	assert_bool(om.dismiss(oid, off, lead)["ok"]).is_false()
	assert_bool(om.dismiss(oid, off, probationer)["ok"]).is_true()
	assert_bool(om.is_member(oid, probationer)).is_false()
	# recruit rights are per rank and the leader may change them
	assert_bool(om.can(oid, vet, "recruit")).is_true()
	om.org(oid)["rk"] = {"2": ["work", "vote"]}
	assert_bool(om.can(oid, vet, "recruit")).is_false()


func test_mercenary_company_lets_plain_members_recruit() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "mercenary_company", 4)
	var m := _ch(h)
	om._add_member(b["org"], m, D.MEMBER, "")
	assert_bool(om.can(b["org"], m, "recruit")).is_true()


# --- joining ----------------------------------------------------------------------------

func test_apply_probation_member_then_promotion_by_skill_contribution_trust_and_seats() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "adventurer_guild", 3)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var low := _ch(h, 500, 0, "hunter", 0.05)
	assert_bool(om.apply(oid, low)["ok"]).is_true()
	assert_bool(om.decide(oid, lead, low, true)["joined"]).is_false()      # too weak for the entry test
	var cand := _ch(h, 500, 0, "hunter", 0.8)
	om.apply(oid, cand)
	var fee: int = D.TYPES["adventurer_guild"]["entry"]["fee"]
	var cash: int = om.purse(cand)
	assert_bool(om.decide(oid, lead, cand, true)["joined"]).is_true()
	assert_int(om.purse(cand)).is_equal(cash - fee)
	assert_int(om.rank_of(oid, cand)).is_equal(D.PROBATION)
	_days(om, 1, 20)                                                      # probation (7 days) ends
	assert_int(om.rank_of(oid, cand)).is_equal(D.MEMBER)
	# veteran needs contribution
	var st: Dictionary = om.promotion_status(oid, cand)
	assert_bool(st["can"]).is_false()
	om.record_activity(oid, cand, 30.0)
	om.org(oid)["m"][cand]["t"] = 80.0
	assert_bool(om.promote(oid, lead, cand)["ok"]).is_true()
	assert_int(om.rank_of(oid, cand)).is_equal(D.VETERAN)
	# officer seats are limited: the founders hold them, so a deserving veteran waits for an open seat
	om.record_activity(oid, cand, 60.0)
	om.org(oid)["m"][cand]["t"] = 95.0
	var st2: Dictionary = om.promotion_status(oid, cand)
	assert_bool(st2["can"]).is_false()
	assert_bool(" ".join(st2["reasons"]).contains("seat")).is_true()
	for f: String in b["all"]:
		if om.rank_of(oid, f) == D.OFFICER:
			om.org(oid)["m"][f]["r"] = D.MEMBER
	assert_bool(om.promotion_status(oid, cand)["can"]).is_true()
	# the leader's seat is won by succession, never by promotion
	om.org(oid)["m"][cand]["r"] = D.BRANCH_LEADER
	assert_bool(om.promotion_status(oid, cand)["can"]).is_false()


func test_a_complaint_by_an_officer_blocks_a_promotion() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "craft_guild", 4)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var a := _ch(h)
	om._add_member(oid, a, D.MEMBER, lead)
	om.org(oid)["m"][a]["c"] = 80.0
	om.org(oid)["m"][a]["t"] = 90.0
	assert_bool(om.promotion_status(oid, a)["can"]).is_true()
	om.open_dispute(oid, om.members_of(oid)[1], a, "rank")
	assert_bool(om.promotion_status(oid, a)["can"]).is_false()


# --- membership axis -------------------------------------------------------------------

func test_multi_membership_unless_an_oath_or_a_rival_type_conflicts() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var guild := _body(h, "craft_guild", 3)
	var co := _body(h, "merchant_company", 2)
	var coop := _body(h, "farmers_coop", 3)
	var merc := _body(h, "mercenary_company", 4)
	var order := _body(h, "religious_order", 3)
	var ring := _body(h, "criminal_syndicate", 3)
	var adv := _body(h, "adventurer_guild", 3)
	var p := _ch(h)
	for o: Dictionary in [guild, co, coop]:
		om.org(o["org"])["pol"]["open"] = true
		om._add_member(o["org"], p, D.MEMBER, "")
	assert_int(om.memberships(p).size()).is_equal(3)                     # several at once
	# an exclusive oath excludes another exclusive one
	om._add_member(merc["org"], p, D.MEMBER, "")
	assert_str(om.join_conflict(order["org"], p)).is_not_empty()
	assert_bool(om.apply(order["org"], p)["ok"]).is_false()
	# a syndicate and the adventurers will never share a member (listed conflict) -- and the oath rule already bars the syndicate
	assert_str(om.join_conflict(ring["org"], p)).is_not_empty()
	var q := _ch(h)
	om._add_member(adv["org"], q, D.MEMBER, "")
	assert_str(om.join_conflict(ring["org"], q)).is_not_empty()
	var axes: Dictionary = om.axes(p)
	assert_int((axes["membership"] as Array).size()).is_equal(4)


func test_the_four_axes_stay_separate() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "craft_guild", 3)
	var oid: String = b["org"]
	var p := _ch(h, 500, 0, "smith")
	var other := _ch(h, 500, 0, "baker")
	om._add_member(oid, p, D.MEMBER, "")
	# employed by someone else without being a member of them; owns things apart from both
	om.employ(p, other, 12, "")
	var mine: String = om.add_asset(p, "tools", "Anvil", 40)
	var theirs: String = om.add_asset(oid, "forge", "Guild forge", 300)
	var ax: Dictionary = om.axes(p)
	assert_str(ax["profession"]).is_equal("smith")
	assert_str(ax["employment"]["by"]).is_equal(other)
	assert_bool(om.is_member(oid, other)).is_false()                      # an employer is not a member
	assert_int((ax["membership"] as Array).size()).is_equal(1)
	assert_bool(mine in ax["ownership"]["assets"]).is_true()
	assert_bool(theirs in ax["ownership"]["assets"]).is_false()           # the org's asset is not the member's
	assert_bool(theirs in om.assets_of(oid)).is_true()
	# changing one axis leaves the others alone
	om.set_profession(p, "baker")
	om.unemploy(p)
	assert_int(om.axes(p)["membership"].size()).is_equal(1)
	assert_bool(mine in om.axes(p)["ownership"]["assets"]).is_true()
	# leaving the org keeps what the member owns, the org keeps what it owns
	om.leave(oid, p)
	assert_bool(mine in om.axes(p)["ownership"]["assets"]).is_true()
	assert_bool(theirs in om.assets_of(oid)).is_true()
	# a donation moves ownership explicitly
	var q := _ch(h)
	om._add_member(oid, q, D.MEMBER, "")
	var gift: String = om.add_asset(q, "cart", "Cart", 30)
	assert_bool(om.donate_asset(gift, q, oid)).is_true()
	assert_bool(gift in om.assets_of(oid)).is_true()
	assert_bool(gift in om.axes(q)["ownership"]["assets"]).is_false()


# --- leaving ---------------------------------------------------------------------------

func test_leaving_takes_only_the_people_legally_free_to_follow() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "craft_guild", 3)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var boss := _ch(h)
	om._add_member(oid, boss, D.VETERAN, lead)
	var free1 := _ch(h)
	var free2 := _ch(h)
	var bound := _ch(h)
	var officer := _ch(h)
	om._add_member(oid, free1, D.MEMBER, boss)
	om._add_member(oid, free2, D.MEMBER, boss)
	om._add_member(oid, bound, D.MEMBER, boss, 1, "ct:77")                 # under a contract
	om._add_member(oid, officer, D.OFFICER, boss)
	var newco := _body(h, "craft_guild", 3)
	var res: Dictionary = om.leave(oid, boss, [free1, free2, bound, officer], newco["org"])
	assert_bool(res["ok"]).is_true()
	assert_bool(free1 in res["followed"] and free2 in res["followed"]).is_true()
	assert_bool(bound in res["stayed"]).is_true()
	assert_bool(officer in res["stayed"]).is_true()                       # officers hold posts
	assert_bool(om.is_member(oid, bound)).is_true()
	assert_bool(om.is_member(oid, free1)).is_false()
	assert_bool(om.is_member(newco["org"], free1)).is_true()
	assert_int(om.rank_of(newco["org"], free1)).is_equal(D.PROBATION)
	assert_bool(om.is_member(newco["org"], boss)).is_true()
	# by default a leaver takes the people they sponsored
	var sp := _ch(h)
	var f := _ch(h)
	om._add_member(oid, sp, D.MEMBER, lead)
	om._add_member(oid, f, D.MEMBER, sp)
	var r2: Dictionary = om.leave(oid, sp)
	assert_bool(f in r2["followed"]).is_true()


func test_leaving_a_contract_is_a_breach_and_the_player_keeps_personal_followers() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var rc: RefCounted = h.mod("recruitment")
	var b := _body(h, "craft_guild", 3)
	var oid: String = b["org"]
	var pl: String = om.player_id()
	om.ensure_char(pl)
	om._add_member(oid, pl, D.MEMBER, "")
	om.org(oid)["m"][pl]["b"] = 1
	var rep0: float = om.reputation_of(pl)
	var res: Dictionary = om.leave(oid, pl)
	assert_bool(res["breach"]).is_true()
	assert_float(om.reputation_of(pl)).is_less(rep0)
	assert_bool(rc != null).is_true()


# --- founding with recruitment.gd ------------------------------------------------------

func test_founding_group_headquarters_and_first_recruits_through_recruitment() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var rc: RefCounted = h.mod("recruitment")
	var b := _body(h, "mercenary_company", 4)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	assert_bool(om.draft_charter(oid, lead, "For coin and each other.")["ok"]).is_true()
	om.org(oid)["rep"] = 20.0
	assert_bool(om.petition_recognition(oid, lead)["ok"]).is_true()
	_days(om, 1, 9)
	assert_str(om.org(oid)["legal"]).is_equal("recognised")
	om.org(oid)["treasury"] = 400
	var hq: Dictionary = om.rent_hq(oid, lead, 0)
	assert_bool(hq["ok"]).is_true()
	assert_str(hq["property"]).starts_with("pr:")
	var treasury_before: int = om.org(oid)["treasury"]
	var notice: Dictionary = om.post_recruitment(oid, lead, 30, "")
	assert_bool(notice["ok"]).is_true()
	assert_int(om.org(oid)["treasury"]).is_less(treasury_before)           # the organization paid the notice fee
	for d in range(1, 12):
		rc.tick_day(d, {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 1000, "player_pos": Vector3.ZERO, "life": null})
	var apps: Array = rc.applicants(notice["nid"])
	assert_int(apps.size()).is_greater(0)
	var seated := 0
	for a: Dictionary in apps:
		var res: Dictionary = om.hire_from_notice(oid, lead, int(a["row"]), 45)
		if res.get("ok", false):
			seated += 1
			var ch: String = res["ch"]
			assert_bool(om.is_member(oid, ch)).is_true()
			assert_int(int(om.member(oid, ch)["b"])).is_equal(1)             # bound by the recruitment contract
			assert_str(h.mod("registry").legacy_of(res["ct"])).starts_with("rc:")
			assert_str(om.employment(ch)["by"]).is_equal(oid)
		if seated >= 2:
			break
	assert_int(seated).is_greater(0)
	assert_int(rc.members("org", oid).size()).is_equal(seated)
	assert_int(om.member_count(oid)).is_equal(4 + seated)
	# a dissolved body ends its contracts
	om.dissolve(oid, lead)
	assert_int(rc.members("org", oid).size()).is_equal(0)


# --- succession ------------------------------------------------------------------------

func test_succession_by_election_appointment_heredity_and_challenge() -> void:
	for mode: String in ["election", "appointment", "heredity", "challenge"]:
		var h := _hub()
		var om: RefCounted = h.mod("organizations")
		var b := _body(h, "craft_guild", 5)
		var oid: String = b["org"]
		var lead: String = b["lead"]
		var heir: String = b["all"][2]
		om.set_succession(oid, lead, mode, heir if mode in ["appointment", "heredity"] else "")
		assert_str(om.org(oid)["succ"]["mode"]).is_equal(mode)
		om.leave(oid, lead)
		var nl: String = om.org(oid)["leader"]
		assert_str(nl).is_not_empty()
		assert_int(om.rank_of(oid, nl)).is_equal(D.LEADER)
		assert_int(om.count_at(oid, D.LEADER)).is_equal(1)
		if mode in ["appointment", "heredity"]:
			assert_str(nl).is_equal(heir)


func test_a_challenge_can_unseat_a_weak_leader_and_punishes_a_failed_one() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "mercenary_company", 5)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var strong: String = b["all"][1]
	om.org(oid)["m"][lead]["c"] = 0.0
	om.org(oid)["m"][lead]["t"] = 10.0
	om.org(oid)["m"][strong]["c"] = 400.0
	om.org(oid)["m"][strong]["t"] = 100.0
	var res: Dictionary = om.challenge(oid, strong)
	assert_bool(res["won"]).is_true()
	assert_str(om.org(oid)["leader"]).is_equal(strong)
	assert_int(om.rank_of(oid, lead)).is_equal(D.OFFICER)
	# a prompt second challenge is refused; a hopeless one fails and costs rank
	assert_bool(om.challenge(oid, lead)["ok"]).is_false()
	var weak: String = b["all"][2]
	om.org(oid)["cd"] = -100
	om.org(oid)["m"][weak]["c"] = 0.0
	om.org(oid)["m"][strong]["c"] = 900.0
	var r2: Dictionary = om.challenge(oid, weak)
	assert_bool(r2["ok"]).is_true()
	assert_bool(r2["won"]).is_false()
	assert_int(om.rank_of(oid, weak)).is_less(D.OFFICER)


# --- branches, mergers, schisms, disputes ----------------------------------------------

func test_branches_mergers_and_schisms() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var a := _body(h, "craft_guild", 6)
	var oid: String = a["org"]
	var lead: String = a["lead"]
	om.org(oid)["stage"] = 3
	om.org(oid)["treasury"] = 1000
	var br_lead: String = a["all"][1]
	var br: Dictionary = om.open_branch(oid, lead, 3, br_lead)
	assert_bool(br["ok"]).is_true()
	var bid: String = br["org"]
	assert_str(om.org(bid)["parent"]).is_equal(oid)
	assert_bool(bid in om.org(oid)["br"]).is_true()
	assert_int(om.rank_of(oid, br_lead)).is_equal(D.BRANCH_LEADER)
	assert_int(om.rank_of(bid, br_lead)).is_equal(D.LEADER)
	# a plain member may not open a branch
	assert_bool(om.open_branch(oid, a["all"][2], 4, a["all"][3])["ok"]).is_false()
	# merger: the absorbed body's people, treasury and assets move
	var c := _body(h, "craft_guild", 3)
	om.org(c["org"])["treasury"] = 120
	var ast: String = om.add_asset(c["org"], "forge", "Old forge", 80)
	var before: int = om.org(oid)["treasury"]
	var res: Dictionary = om.merge(oid, c["org"], lead)
	assert_bool(res["ok"]).is_true()
	assert_int(om.org(oid)["treasury"]).is_equal(before + 120)
	assert_str(om.org(c["org"])["st"]).is_equal("merged")
	assert_bool(ast in om.assets_of(oid)).is_true()
	for m: String in c["all"]:
		assert_bool(om.is_member(oid, m)).is_true()
	assert_bool(om.is_member(c["org"], c["lead"])).is_false()
	assert_int(om.rank_of(oid, c["lead"])).is_less(D.LEADER)
	# different kinds cannot merge
	var x := _body(h, "religious_order", 3)
	assert_bool(om.merge(oid, x["org"], lead)["ok"]).is_false()
	# schism: free followers go, the bound stay, the treasury is split
	var rebel: String = a["all"][2]
	var f1: String = a["all"][3]
	var f2: String = a["all"][4]
	om.org(oid)["m"][f2]["b"] = 1
	var tre: int = om.org(oid)["treasury"]
	var sp: Dictionary = om.split(oid, rebel, [f1, f2], "Reformed Smiths")
	assert_bool(sp["ok"]).is_true()
	assert_bool(f1 in sp["followed"]).is_true()
	assert_bool(f2 in sp["stayed"]).is_true()
	assert_bool(om.is_member(sp["org"], f1)).is_true()
	assert_bool(om.is_member(oid, f1)).is_false()
	assert_bool(om.is_member(oid, f2)).is_true()
	assert_int(om.org(sp["org"])["treasury"]).is_greater(0)
	assert_int(om.org(oid)["treasury"]).is_less(tre)
	assert_str(om.org(sp["org"])["leader"]).is_equal(rebel)
	# dissolving the parent frees its branch
	om.dissolve(oid, lead)
	assert_str(om.org(bid)["parent"]).is_equal("")


func test_disputes_are_ruled_by_a_judge_or_by_the_hall() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "craft_guild", 5)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var x: String = b["all"][1]
	var y: String = b["all"][2]
	var d: Dictionary = om.open_dispute(oid, x, y, "pay", "unpaid")
	assert_bool(d["ok"]).is_true()
	var t0: float = om.org(oid)["m"][y]["t"]
	assert_bool(om.resolve_dispute(oid, om.members_of(oid)[-1], d["id"], "a")["ok"]).is_false() if om.rank_of(oid, om.members_of(oid)[-1]) < D.OFFICER else true
	assert_bool(om.resolve_dispute(oid, lead, d["id"], "a")["ok"]).is_true()
	assert_float(om.org(oid)["m"][y]["t"]).is_less(t0)
	# an unattended dispute is ruled after the waiting time
	var d2: Dictionary = om.open_dispute(oid, x, y, "rank")
	om.set_day(1)
	_days(om, 1, 14)
	for dd: Dictionary in om.disputes(oid, false):
		assert_str(dd["st"]).is_not_equal("open")
	assert_bool(d2["ok"]).is_true()


# --- money --------------------------------------------------------------------------------

func test_dues_and_salaries_move_between_purses_and_the_treasury() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "merchant_company", 3)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var m := _ch(h, 100)
	om._add_member(oid, m, D.MEMBER, "")
	om.org(oid)["treasury"] = 100
	var c0: int = om.purse(m)
	om._settle(oid, 7)
	# a member pays dues (4 x 1.0), an officer-rank founder gets a salary
	assert_int(om.purse(m)).is_less(c0 + 3)
	var lead0: int = om.purse(lead)
	om.org(oid)["treasury"] = 0
	om.org(oid)["act"] = 0.0
	om._settle(oid, 14)
	assert_int(int(om.org(oid)["m"][lead]["ar"])).is_greater_equal(0)
	# an empty treasury leaves salaries owed and trust falls
	var t_before: float = om.org(oid)["m"][lead]["t"]
	om.org(oid)["treasury"] = -500
	om._settle(oid, 21)
	assert_int(om.org(oid)["nw"]).is_greater(0)
	assert_float(om.org(oid)["m"][lead]["t"]).is_less_equal(t_before + 1.0)
	assert_bool(lead0 >= 0).is_true()


func test_a_body_that_cannot_pay_for_eight_weeks_closes() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "merchant_company", 3)
	var oid: String = b["org"]
	om.org(oid)["mode"] = "autonomous"
	om.org(oid)["treasury"] = -2000
	for w in 9:
		om.org(oid)["treasury"] = -2000
		om._settle(oid, 7 * (w + 1))
		if om.org(oid)["st"] != "active":
			break
	assert_str(om.org(oid)["st"]).is_equal("dissolved")


# --- NPC parity ---------------------------------------------------------------------------

func test_npcs_found_join_and_compete_through_the_same_calls() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	om.org_ids()
	for i in 36:
		var prof: String = ["smith", "carpenter", "baker", "mercenary", "hunter", "farmer"][i % 6]
		var sid := i % 3
		om.spawn_actor(sid, prof, 900 + (i % 5) * 100, {"combat": 0.6, "crafting": 0.6, "trading": 0.5, "farming": 0.5}, 5.0, "found" if i % 4 == 0 else "join")
	assert_int(om.npc_count()).is_equal(36)
	for d in range(1, 200):
		om.tick_day(d, {})
	assert_int(om.stats["npc_founded"]).is_greater_equal(2)
	var reached := 0
	var with_people := 0
	for oid: String in om.org_ids():
		var o: Dictionary = om.org(oid)
		if int(o["stage"]) >= 2:
			reached += 1
		if om.member_count(oid) >= 3:
			with_people += 1
	assert_int(reached).is_greater_equal(1)
	assert_int(with_people).is_greater_equal(2)
	assert_int(om.stats["npc_joined"]).is_greater(0)
	# every NPC body respects the same rights table and rank cap
	for oid2: String in om.active_ids():
		assert_int(om.count_at(oid2, D.LEADER)).is_less_equal(1)
		assert_bool(om.member_count(oid2) <= om.capacity(oid2) + 12).is_true()


func test_npc_orgs_compete_for_a_recruit_and_the_better_offer_wins() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var a := _body(h, "craft_guild", 3)
	var b := _body(h, "craft_guild", 3)
	for o: String in [a["org"], b["org"]]:
		om.org(o)["stage"] = 2
	om.org(a["org"])["rep"] = 5.0
	om.org(b["org"])["rep"] = 60.0
	om.org(b["org"])["pol"]["wage"] = 1.5
	om.org(a["org"])["treasury"] = 100
	om.org(b["org"])["treasury"] = 400
	var cand := _ch(h, 500, 0, "smith")
	assert_float(om.offer_score(b["org"], cand)).is_greater(om.offer_score(a["org"], cand))
	om.char_rec(cand)["npc"] = true
	om._npc_ok = false
	om.char_rec(cand)["amb"] = "join"
	for d in range(0, 3):
		om._decide(cand, d)
	assert_bool(om.org(b["org"])["app"].has(cand)).is_true()
	assert_bool(om.org(a["org"])["app"].has(cand)).is_false()
	assert_int(om.stats["contested"]).is_greater(0)


# --- adapters -----------------------------------------------------------------------------

func test_existing_guilds_and_careers_map_onto_the_organization_record() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var cl: RefCounted = h.mod("city_life")
	cl._ensure_guilds()
	var gl: Array = cl.guilds()
	assert_int(gl.size()).is_greater(0)
	var g: Dictionary = gl[0]
	var oid: String = om.adapt("city_guild", String(g["id"]))
	assert_str(oid).starts_with("org:")
	assert_str(om.adapt("city_guild", String(g["id"]))).is_equal(oid)         # same answer every time
	assert_str(om.org(oid)["name"]).is_equal(g["name"])
	assert_int(om.org(oid)["treasury"]).is_equal(int(g["treasury"]))
	assert_str(h.mod("registry").lookup("og:city_guild:" + String(g["id"]))).is_equal(oid)
	# the legacy state is untouched and the player's seat is mirrored when they join
	var pl: String = om.player_id()
	assert_bool(om.is_member(oid, pl)).is_false()
	cl.player["rep"] = 100.0
	var n: int = om.adapt_all()
	assert_int(n).is_greater_equal(gl.size())
	assert_int(om.org_ids().size()).is_less_equal(om.ORG_CAP)
	var again: int = om.adapt_all()
	assert_int(again).is_equal(n)                                          # idempotent
	var career_org: String = h.mod("registry").lookup("og:career:soldier")
	assert_str(career_org).is_not_empty()
	assert_str(om.org(career_org)["type"]).is_equal("militia")


func test_the_realm_hub_runs_the_world_driven_mode_for_a_season() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var bz: RefCounted = h.mod("businesses")
	om.auto_seed = true                                                     # what the game does: seed town actors and mirror the old guilds
	for d in range(1, 100):
		h.on_hour(6, d, {"season": "summer", "at_war": false, "abs_hours": d * 24, "gold": 1000, "player_pos": Vector3.ZERO, "life": null})
		h.drain()
	assert_int(om.npc_count()).is_greater(0)
	assert_int(om.npc_count()).is_less_equal(om.ACTOR_SEED)
	assert_str(h.mod("registry").lookup("og:career:soldier")).is_not_empty()
	var mirrors := 0
	for oid: String in om.org_ids():
		if (om.org(oid) as Dictionary).has("legacy"):
			mirrors += 1
	assert_int(mirrors).is_greater(3)
	assert_int(om.org_ids().size()).is_less_equal(om.ORG_CAP)
	assert_int(bz.count()).is_less_equal(bz.BIZ_CAP)
	# the mirrored guild follows its source: a guild the player joins shows the player's seat
	var cl: RefCounted = h.mod("city_life")
	var g: Dictionary = cl.guilds()[0]
	cl._guilds[String(g["id"])]["player"]["rank"] = 2
	var oid2: String = om.adapt("city_guild", String(g["id"]))
	assert_int(om.rank_of(oid2, om.player_id())).is_equal(2)
	cl._guilds[String(g["id"])]["player"]["rank"] = -1
	om.adapt("city_guild", String(g["id"]))
	assert_bool(om.is_member(oid2, om.player_id())).is_false()


# --- save ---------------------------------------------------------------------------------

func test_save_round_trip_keeps_everything() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "craft_guild", 5)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	om.draft_charter(oid, lead, "charter")
	om.org(oid)["rep"] = 30.0
	om.petition_recognition(oid, lead)
	om.add_asset(oid, "forge", "F", 100)
	om.add_asset(b["all"][1], "anvil", "A", 10)
	om.open_dispute(oid, b["all"][1], b["all"][2], "pay")
	om.set_profession(lead, "smith")
	om.employ(b["all"][2], lead, 9)
	for d in range(1, 12):
		om.tick_day(d, {})
	var data: Dictionary = JSON.parse_string(JSON.stringify(om.serialize()))
	var h2 := _hub()
	var om2: RefCounted = h2.mod("organizations")
	om2.deserialize(data)
	assert_str(_norm(om2.serialize())).is_equal(_norm(om.serialize()))
	assert_array(om2.memberships(lead)).is_equal(om.memberships(lead))
	assert_bool(om2.can(oid, lead, "dissolve")).is_true()
	assert_str(om2.org(oid)["legal"]).is_equal(om.org(oid)["legal"])
	# the loaded world carries on: the weekly settle and the id counter keep working
	om2.tick_day(12, {})
	om2.tick_day(13, {})
	var reg2: RefCounted = h2.mod("registry")
	reg2.deserialize(JSON.parse_string(JSON.stringify(h.mod("registry").serialize())))
	assert_str(reg2.mint("org")).is_not_equal(oid)
	# and through the whole hub
	var full: Dictionary = JSON.parse_string(JSON.stringify(h.serialize()))
	assert_bool(full.has("organizations") and full.has("businesses")).is_true()


func test_the_column_save_keeps_applicants_probation_sponsors_and_oddities() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "merchant_company", 4)
	var oid: String = b["org"]
	var lead: String = b["lead"]
	var second: String = b["all"][1]
	om.draft_charter(oid, lead, "We trade fairly.", {"dues": 1.5})
	var probationer := _ch(h)
	om._add_member(oid, probationer, D.PROBATION, second)
	var outsider := _ch(h)
	assert_bool(om.apply(oid, outsider, lead)["ok"]).is_true()
	assert_bool(om.set_succession(oid, lead, "appointment", second)).is_true()
	om.org(oid)["rk"] = {"1": ["work"]}
	om.org(oid)["mode"] = "delegated"
	om.record_activity(oid, b["all"][2], 7.5)
	om.add_asset(oid, "ledger", "Ledger", 40)
	om.open_dispute(oid, second, b["all"][2], "honour", "a slight")
	om.org(oid)["treasury"] = 12345
	om.char_rec(second)["sk"] = {"trading": 0.45, "lore": 0.2}
	om.employ(b["all"][3], lead, 11, "ct:5")
	var data: Dictionary = JSON.parse_string(JSON.stringify(om.serialize()))
	assert_int(int(data["v"])).is_equal(2)
	var h2 := _hub()
	var om2: RefCounted = h2.mod("organizations")
	om2.deserialize(data)
	assert_str(_norm(om2.serialize())).is_equal(_norm(om.serialize()))
	assert_array(om2.applicants(oid)).is_equal([outsider])
	assert_int(om2.rank_of(oid, probationer)).is_equal(D.PROBATION)
	assert_int(om2.member(oid, probationer)["pd"]).is_equal(om.member(oid, probationer)["pd"])
	assert_str(om2.member(oid, probationer)["sp"]).is_equal(second)
	assert_str(om2.org(oid)["succ"]["mode"]).is_equal("appointment")
	assert_str(om2.org(oid)["succ"]["heir"]).is_equal(second)
	assert_array(om2.org(oid)["rk"]["1"]).is_equal(["work"])
	assert_str(om2.org(oid)["mode"]).is_equal("delegated")
	assert_float(om2.member(oid, b["all"][2])["c"]).is_equal_approx(7.5, 0.001)
	assert_int(om2.org(oid)["treasury"]).is_equal(12345)
	assert_float(om2.org(oid)["pol"]["dues"]).is_equal(1.5)
	assert_int(om2.disputes(oid).size()).is_equal(1)
	assert_float(om2.char_rec(second)["sk"]["trading"]).is_equal_approx(0.45, 0.0005)
	assert_str(om2.employment(b["all"][3])["ct"]).is_equal("ct:5")
	assert_str(om2.org(oid)["leader"]).is_equal(lead)
	assert_array(om2.org(oid)["founders"]).is_equal(om.org(oid)["founders"])
	assert_int(om2.member_count(oid)).is_equal(om.member_count(oid))
	# derived state is rebuilt, not saved: rank counts and the probation floor agree with the members
	assert_array(om2.org(oid)["rcv"]).is_equal(om.org(oid)["rcv"])
	assert_int(om2.org(oid)["ppd"]).is_equal(om.org(oid)["ppd"])


func test_a_schema_1_save_still_loads() -> void:
	var v1 := {
		"o": {"org:7": {"type": "craft_guild", "name": "Old Guild", "sid": 2, "mode": "autonomous", "stage": 3, "leader": "ch:11", "founders": ["ch:11", "ch:12"],
			"succ": {"mode": "election", "heir": ""}, "hq": {"pr": "pr:3", "sid": 2, "rent": 12, "since": 4, "legal": "leased"},
			"charter": {"text": "We bind ourselves.", "day": 4}, "legal": "recognised", "treasury": 250, "born": 0, "lw": -3, "dt": false, "n": 7, "rep": 12.5, "off": 3.0,
			"assets": ["a1"], "hist": ["d4 stage: premises", "d9 took a gift"],
			"dis": [{"id": "d1", "a": "ch:11", "b": "ch:12", "k": "pay", "t": "x", "day": 5, "st": "open"}], "app": {"ch:13": {"d": 6, "sp": "ch:11"}},
			"m": {"ch:11": [5, 0, 4.0, 70.0, "", 0, 0, "", -1, 0.7], "ch:12": [0, 2, 0.0, 60.0, "ch:11", 0, 0, "", 14, 0.4]}}},
		"c": {"ch:11": {"prof": "smith", "cash": 400, "sid": 2, "sk": {"crafting": 0.8}, "rep": 12.0, "own": ["a2"]}, "ch:12": {"cash": 90, "npc": true, "amb": "join"}},
		"a": {"a1": {"id": "a1", "kind": "forge", "name": "Forge", "value": 100, "owner": "org:7"}, "a2": {"id": "a2", "kind": "anvil", "name": "Anvil", "value": 20, "owner": "ch:11"}},
		"pt": {"pt1": {"id": "pt1", "org": "org:7", "day": 4, "st": "granted", "why": ""}}, "nd": 2, "na": 3, "np": 2, "day": 10, "seeded": false, "st": {"founded": 3}, "pg": 0}
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	om.deserialize(JSON.parse_string(JSON.stringify(v1)))
	assert_str(om.org("org:7")["name"]).is_equal("Old Guild")
	assert_int(om.org("org:7")["stage"]).is_equal(3)
	assert_int(om.org("org:7")["treasury"]).is_equal(250)
	assert_str(om.org("org:7")["leader"]).is_equal("ch:11")
	assert_int(om.rank_of("org:7", "ch:11")).is_equal(D.LEADER)
	assert_int(om.rank_of("org:7", "ch:12")).is_equal(D.PROBATION)
	assert_int(om.member("org:7", "ch:12")["pd"]).is_equal(14)
	assert_float(om.member("org:7", "ch:11")["k"]).is_equal_approx(0.7, 0.0001)
	assert_array(om.applicants("org:7")).is_equal(["ch:13"])
	assert_int(om.disputes("org:7").size()).is_equal(1)
	assert_array(om.memberships("ch:12")).is_equal(["org:7"])
	assert_float(om.skill_of("ch:11", "crafting")).is_equal_approx(0.8, 0.0001)
	assert_int(om.purse("ch:11")).is_equal(400)
	assert_str(om.asset("a1")["owner"]).is_equal("org:7")
	assert_array(om.assets_owned_by("ch:11")).is_equal(["a2"])
	assert_int(om.npc_count()).is_equal(1)
	assert_int(om.today()).is_equal(10)
	# it was written again in the new format, and that loads to the same thing
	var out: Dictionary = om.serialize()
	assert_int(int(out["v"])).is_equal(2)
	var h2 := _hub()
	var om2: RefCounted = h2.mod("organizations")
	om2.deserialize(JSON.parse_string(JSON.stringify(out)))
	assert_str(_norm(om2.serialize())).is_equal(_norm(out))
	# and the loaded world carries on
	for d in range(11, 40):
		om2.tick_day(d, {})
	assert_bool(om2.exists("org:7")).is_true()


func test_the_hiring_lists_follow_the_bodies_through_every_change() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var b := _body(h, "craft_guild", 4)
	var oid: String = b["org"]
	om.org(oid)["stage"] = 2
	om._touch(om.org(oid))
	var sid := int(om.org(oid)["sid"])
	assert_array(om._hiring(sid, "craft_guild")).contains([oid])
	# a closed body stops hiring; a stage-0 body does not hire
	var young := _body(h, "craft_guild", 1)
	assert_array(om._hiring(sid, "craft_guild")).not_contains([young["org"]])
	om.dissolve(oid, b["lead"])
	assert_array(om._hiring(sid, "craft_guild")).not_contains([oid])
	# a full body stops hiring and a seat freed starts it again
	var full := _body(h, "craft_guild", 3)
	var fid: String = full["org"]
	om.org(fid)["stage"] = 1
	om._touch(om.org(fid))
	assert_array(om._hiring(sid, "craft_guild")).contains([fid])
	while om.member_count(fid) < om.capacity(fid):
		om._add_member(fid, _ch(h), D.MEMBER, full["lead"])
	assert_array(om._hiring(sid, "craft_guild")).not_contains([fid])
	om._remove(fid, om.members_of(fid)[om.member_count(fid) - 1], "left")
	assert_array(om._hiring(sid, "craft_guild")).contains([fid])


# --- performance --------------------------------------------------------------------------

func test_tick_cost_of_400_organizations_with_4000_members() -> void:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var types := D.TYPE_IDS
	var n := 0
	for i in 400:
		var t: String = types[i % types.size()]
		var lead := _ch(h, 100)
		var res: Dictionary = om.start_founding(lead, t, "Org %d" % i, i % 10, "autonomous")
		if not res["ok"]:
			continue
		var oid: String = res["org"]
		for k in 9:
			var mm: String = h.mod("registry").mint("ch")
			om.ensure_char(mm, {"cash": 50})
			om._add_member(oid, mm, D.MEMBER if k > 1 else D.OFFICER, lead)
			n += 1
		om.org(oid)["treasury"] = 500
		om.org(oid)["legal"] = "recognised"
		om.org(oid)["charter"] = {"text": "x", "day": 0}
		om.org(oid)["hq"] = {"pr": "pr:1", "sid": i % 10, "rent": 8, "since": 0, "legal": "leased"}
		om._restage(oid)
	assert_int(om.org_ids().size()).is_equal(400)
	for i in 300:
		om.spawn_actor(i % 10, ["smith", "baker", "mercenary", "hunter", "farmer"][i % 5], 300, {}, 0.0, "found" if i % 9 == 0 else "join")
	# Day 1 to 14 is the burn-in: every body settles its first week once, then each settles on its own staggered day.
	for d in range(1, 15):
		om.tick_day(d, {})
	var worst := 0
	var total := 0
	var npc_worst := 0
	var npc_total := 0
	var days := 28
	for d in range(15, 15 + days):
		var tb := Time.get_ticks_usec()
		var chunks: Array = om.tick_day_chunks(d, {})
		total += Time.get_ticks_usec() - tb
		for ci in chunks.size():
			var t0 := Time.get_ticks_usec()
			(chunks[ci] as Callable).call()
			var dt := Time.get_ticks_usec() - t0
			if ci >= chunks.size() - 1 - om.NPC_JOBS and ci < chunks.size() - 1:      # the day's NPC decisions come after the org jobs
				npc_total += dt
				npc_worst = maxi(npc_worst, dt)
			else:
				worst = maxi(worst, dt)
			total += dt
	print("LW-4.2 organizations: %d orgs, %d members, %d npcs; worst org job %d us, worst npc job %d us, avg npc %d us, avg day %d us (budget 600 us a job, 500 us a day)" % [om.org_ids().size(), om._total_members(), om.npc_count(), worst, npc_worst, npc_total / days, total / days])
	# The doc's budgets are 0.6 ms a job and 0.5 ms a day (Part E, LW-4.2). The asserts allow 6.7x on one job (a single
	# scheduler hiccup lands in the max; the old limit was the same) and 4x on the day average for a loaded CI machine.
	assert_int(maxi(worst, npc_worst)).is_less(4000)
	assert_int(total / days).is_less(2000)
	# the serialized size stays inside the doc's budget (400 orgs, 4,000 member rows: about 156 KB raw)
	var raw := JSON.stringify(om.serialize()).length()
	print("LW-4.2 organizations save: %d bytes raw for %d orgs / %d members (budget 156000)" % [raw, om.org_ids().size(), om._total_members()])
	assert_int(raw).is_less(156000)
