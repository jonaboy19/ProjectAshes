extends RefCounted
## Organization data (LW-4.2, docs/design/LIVING_WORLD_SANDBOX.md §5): the type table with its rank ladders and rights, as plain
## constants. No state. scripts/realm/organizations.gd owns the organizations.
## (The doc names data/living_world/org_types.json; the table lives here as constants so headless tests and saves never depend on file IO.)
##
## The ladder is the same seven steps for every type, only the names, fees and rights differ:
##   applicant (not a rank) -> 0 probation -> 1 member -> 2 veteran -> 3 officer -> 4 branch leader -> 5 leader

const RIGHTS := ["work", "vote", "recruit", "dismiss", "promote", "judge", "treasury", "set_policy", "charter", "found_branch", "merge", "dissolve", "appoint"]
const STAGES := ["idea", "members", "charter", "premises", "standing"]
const SCALES := ["party", "clan", "legion", "great house"]
const SCALE_AT := [0, 6, 25, 100]
const MODES := ["manual", "delegated", "autonomous"]
const SUCCESSION := ["election", "appointment", "heredity", "challenge"]
const RANK_COUNT := 6
const LEADER := 5
const BRANCH_LEADER := 4
const OFFICER := 3
const VETERAN := 2
const MEMBER := 1
const PROBATION := 0

## Default rights per rank index. A type may override single ranks (see "rights").
const BASE_RIGHTS := [
	[],
	["work", "vote"],
	["work", "vote", "recruit"],
	["work", "vote", "recruit", "dismiss", "promote", "judge"],
	["work", "vote", "recruit", "dismiss", "promote", "judge", "treasury", "found_branch"],
	["work", "vote", "recruit", "dismiss", "promote", "judge", "treasury", "set_policy", "charter", "found_branch", "merge", "dissolve", "appoint"],
]
## Seats per rank: -1 unlimited, a number is a fixed count, a negative fraction -x means one seat per 1/x members (at least 1).
const BASE_SLOTS := [-1, -1, -1, -0.15, -0.05, 1]
## Contribution a member needs before the next rank is open to them, and the weekly share of dues each rank pays.
const BASE_NEED := [0.0, 6.0, 20.0, 50.0, 90.0, 140.0]
const BASE_DUES := [0.0, 1.0, 1.0, 0.5, 0.0, 0.0]

## type -> {label, ranks[6 names], skill (stat the entry test and promotions read), entry{fee, skill, rep, sponsor}, dues (gold a member
##   week), pay [per rank, gold a week], excl (cannot be combined with another exclusive membership), succ (default), found (gold),
##   min_founders, hq_rent, rate (activity a week one active member makes), yield (gold per activity point), stand_rep, recog_rep,
##   prob (probation days), prof (professions that fit it), rights (rank -> rights override), conflicts (types never held together)}
const TYPES := {
	"adventurer_guild": {"label": "Adventurers' Guild", "ranks": ["Applicant", "Member", "Journeyman", "Master", "Guildwarden", "Guildmaster"],
		"skill": "combat", "entry": {"fee": 10, "skill": 0.3, "rep": 0, "sponsor": false}, "dues": 2, "pay": [0, 0, 2, 5, 9, 14], "excl": false,
		"succ": "election", "found": 500, "min_founders": 3, "hq_rent": 14, "rate": 1.2, "yield": 1.1, "stand_rep": 30.0, "recog_rep": 10.0,
		"prob": 7, "prof": ["adventurer", "mercenary", "hunter"], "conflicts": []},
	"craft_guild": {"label": "Craft Guild", "ranks": ["Apprentice", "Journeyman", "Craftsman", "Master", "Warden", "Guildmaster"],
		"skill": "crafting", "entry": {"fee": 20, "skill": 0.25, "rep": 5, "sponsor": true}, "dues": 3, "pay": [0, 0, 1, 4, 8, 12], "excl": false,
		"succ": "election", "found": 400, "min_founders": 3, "hq_rent": 12, "rate": 1.0, "yield": 1.2, "stand_rep": 25.0, "recog_rep": 8.0,
		"prob": 14, "prof": ["smith", "carpenter", "mason", "weaver", "baker", "brewer"], "conflicts": []},
	"merchant_company": {"label": "Merchant Company", "ranks": ["Clerk", "Factor", "Senior Factor", "Partner", "Branch Factor", "Master of the Company"],
		"skill": "trading", "entry": {"fee": 40, "skill": 0.3, "rep": 10, "sponsor": false}, "dues": 4, "pay": [1, 3, 5, 9, 14, 20], "excl": false,
		"succ": "heredity", "found": 800, "min_founders": 2, "hq_rent": 20, "rate": 1.4, "yield": 1.4, "stand_rep": 30.0, "recog_rep": 10.0,
		"prob": 14, "prof": ["merchant", "trader", "caravaneer"], "conflicts": []},
	"mercenary_company": {"label": "Mercenary Company", "ranks": ["Recruit", "Sellsword", "Veteran", "Sergeant", "Lieutenant", "Captain"],
		"skill": "combat", "entry": {"fee": 0, "skill": 0.35, "rep": 0, "sponsor": false}, "dues": 0, "pay": [1, 4, 6, 9, 13, 20], "excl": true,
		"succ": "challenge", "found": 600, "min_founders": 4, "hq_rent": 10, "rate": 1.6, "yield": 1.0, "stand_rep": 30.0, "recog_rep": 15.0,
		"prob": 7, "prof": ["mercenary", "soldier", "guard"], "conflicts": ["militia"],
		"rights": {"1": ["work", "vote", "recruit"]}},
	"farmers_coop": {"label": "Farmers' Cooperative", "ranks": ["Newcomer", "Member", "Elder Member", "Steward", "Warden", "Reeve"],
		"skill": "farming", "entry": {"fee": 5, "skill": 0.15, "rep": 0, "sponsor": false}, "dues": 1, "pay": [0, 0, 0, 2, 4, 6], "excl": false,
		"succ": "election", "found": 200, "min_founders": 3, "hq_rent": 6, "rate": 0.8, "yield": 1.0, "stand_rep": 20.0, "recog_rep": 5.0,
		"prob": 14, "prof": ["farmer", "herder", "miller"], "conflicts": [],
		"rights": {"0": ["vote"]}},
	"criminal_syndicate": {"label": "Syndicate", "ranks": ["Runner", "Thug", "Enforcer", "Lieutenant", "Boss of a Quarter", "Kingpin"],
		"skill": "stealth", "entry": {"fee": 0, "skill": 0.3, "rep": -5, "sponsor": true}, "dues": 5, "pay": [0, 1, 3, 7, 12, 20], "excl": true,
		"succ": "challenge", "found": 300, "min_founders": 3, "hq_rent": 8, "rate": 1.3, "yield": 1.3, "stand_rep": 20.0, "recog_rep": 9999.0,
		"prob": 10, "prof": ["thief", "smuggler", "fence"], "conflicts": ["militia", "religious_order", "adventurer_guild"],
		"rights": {"1": ["work", "vote", "recruit"]}},
	"religious_order": {"label": "Religious Order", "ranks": ["Postulant", "Brother", "Elder Brother", "Prior", "Abbot of a House", "Abbot General"],
		"skill": "faith", "entry": {"fee": 0, "skill": 0.2, "rep": 5, "sponsor": true}, "dues": 0, "pay": [0, 1, 2, 4, 7, 10], "excl": true,
		"succ": "appointment", "found": 600, "min_founders": 3, "hq_rent": 8, "rate": 0.7, "yield": 0.9, "stand_rep": 25.0, "recog_rep": 10.0,
		"prob": 30, "prof": ["priest", "healer", "scribe"], "conflicts": ["criminal_syndicate"],
		"rights": {"2": ["work", "vote"], "3": ["work", "vote", "recruit", "dismiss", "promote", "judge"]}},
	"academy": {"label": "Academy", "ranks": ["Pupil", "Scholar", "Fellow", "Reader", "Dean", "Rector"],
		"skill": "lore", "entry": {"fee": 30, "skill": 0.3, "rep": 5, "sponsor": false}, "dues": 4, "pay": [0, 0, 3, 6, 10, 15], "excl": false,
		"succ": "election", "found": 700, "min_founders": 3, "hq_rent": 16, "rate": 0.9, "yield": 1.2, "stand_rep": 30.0, "recog_rep": 12.0,
		"prob": 28, "prof": ["scribe", "scholar", "mage"], "conflicts": []},
	"militia": {"label": "Militia", "ranks": ["Levy", "Soldier", "Veteran", "Sergeant", "Captain", "Marshal"],
		"skill": "combat", "entry": {"fee": 0, "skill": 0.2, "rep": 0, "sponsor": false}, "dues": 0, "pay": [1, 3, 4, 6, 9, 12], "excl": true,
		"succ": "appointment", "found": 300, "min_founders": 4, "hq_rent": 8, "rate": 1.0, "yield": 0.6, "stand_rep": 25.0, "recog_rep": 5.0,
		"prob": 7, "prof": ["soldier", "guard"], "conflicts": ["mercenary_company", "criminal_syndicate"]},
	"band": {"label": "Band", "ranks": ["Hanger-on", "Follower", "Veteran", "Lieutenant", "Warband Chief", "Chieftain"],
		"skill": "combat", "entry": {"fee": 0, "skill": 0.2, "rep": 0, "sponsor": false}, "dues": 0, "pay": [0, 1, 2, 4, 6, 9], "excl": false,
		"succ": "challenge", "found": 0, "min_founders": 2, "hq_rent": 0, "rate": 0.8, "yield": 0.9, "stand_rep": 15.0, "recog_rep": 9999.0,
		"prob": 3, "prof": ["adventurer", "mercenary"], "conflicts": []},
}
const TYPE_IDS := ["adventurer_guild", "craft_guild", "merchant_company", "mercenary_company", "farmers_coop", "criminal_syndicate",
	"religious_order", "academy", "militia", "band"]

## Existing systems -> organization type (adapters, organizations.adapt).
const LEGACY_GUILD_KIND := {"adventurers": "adventurer_guild", "smiths": "craft_guild", "merchant": "merchant_company", "hunters": "adventurer_guild",
	"healers": "religious_order", "mages": "academy"}
const LEGACY_NOTABLE_KIND := {"company": "merchant_company", "guild": "craft_guild", "order": "religious_order", "band": "band", "academy": "academy"}
const LEGACY_CAREER := {"soldier": "militia", "scribe": "academy", "blacksmith": "craft_guild", "wardwright": "craft_guild", "merchant": "merchant_company",
	"farmer": "farmers_coop", "adventurer": "adventurer_guild"}

## Types that may be held with each other only when neither is exclusive and the two do not list each other as conflicts.
const COMPAT_MERGE := {"craft_guild": ["craft_guild"], "merchant_company": ["merchant_company", "craft_guild"], "mercenary_company": ["mercenary_company", "militia", "band"],
	"band": ["band", "mercenary_company"], "adventurer_guild": ["adventurer_guild", "band"], "farmers_coop": ["farmers_coop"],
	"criminal_syndicate": ["criminal_syndicate"], "religious_order": ["religious_order"], "academy": ["academy"], "militia": ["militia", "mercenary_company"]}


static func type_def(t: String) -> Dictionary:
	return TYPES.get(t, {})


static func rank_rights(t: String, rank: int) -> Array:
	var td: Dictionary = TYPES.get(t, {})
	var ov: Dictionary = td.get("rights", {})
	if ov.has(str(rank)):
		return ov[str(rank)]
	return BASE_RIGHTS[clampi(rank, 0, RANK_COUNT - 1)]


static func scale_name(members: int) -> String:
	var out: String = SCALES[0]
	for i in SCALES.size():
		if members >= int(SCALE_AT[i]):
			out = SCALES[i]
	return out
