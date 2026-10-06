extends "res://scripts/realm/realm_module.gd"
## Education (docs/design/CHILDHOOD_ACADEMIES.md C§3-31 and C§44-49, ACADEMY_PLAN.md P1).
##
## Pure data, deterministic (seed = hash([WorldSim.SEED, tag, day, id])), JSON-safe.
## Nothing here plays a cutscene: every event is data plus Array[String] messages
## that an in-world NPC or the notify stack delivers.
##
## Flow: Scout Season at age 9 (orgs that visit depend on region wealth, war and
## politics; multi-axis tests; corruption; being overlooked opens late routes)
## -> admission (scout, exam, sponsorship, tutor, military entry, tournament)
## -> student life (schedule blocks with time_scale, interrupts, truancy ladder,
## five performance dimensions, rankings, ~30 classmates whose careers keep
## running, class, expenses, sponsors, factions, clubs, rivals, teachers and
## mentors, tournaments, field exercises) -> graduation offers (refusable) or
## dropping out. "Everyone learns to fight": training_options() is always non-empty.
##
## Money rule (like society / city_life): this module never touches the purse. It
## adds to a signed ledger; Life calls take_pending_gold(). Stat gains for the
## player are queued for take_pending_gains().
##
## Cross-module (all guarded): society (learn, add_rep, add_rumour, bounty,
## fame_at), factions (church_influence), settlements, land, household
## (support_student), ctx["life"] (age(), tendencies, scouts).

const SCOUT_AGE := 9
const SEASON_DAYS := 21
const YEAR_DAYS := 360
const COHORT_SIZE := 30
const COHORTS_KEPT := 3
const PathTeachers := preload("res://scripts/abilities/path_teachers.gd")
const REGION := "caldrenn"
const ATTEND_GAIN := 0.05
const INTERRUPT_CHANCE := 0.05
const INTERRUPT_TIMEOUT_H := 2
const NONPAY_WEEKS := 5

const AXES := ["potential", "discipline", "intelligence", "condition", "magic_sensitivity", "resonance", "reflexes",
	"courage", "memory", "leadership", "constitution"]
const PERF := ["combat", "theory", "practical", "leadership", "discipline"]
const RANK_CATS := ["combat", "academic", "practical", "leadership", "discipline", "contribution", "overall"]
const CLASS_NAMES := ["commoner", "artisan", "merchant", "gentry", "noble"]
const CLASS_PREP := [0.0, 4.0, 9.0, 14.0, 20.0]
const LADDER := ["good_standing", "warning", "detention", "privileges_lost", "suspended", "expelled"]
const LADDER_AT := [0.0, 3.0, 6.0, 9.0, 13.0, 18.0]

const CAMPUS := ["dormitories", "classrooms", "training fields", "library", "cafeteria", "workshops", "arena", "gardens",
	"medical building", "teacher residences", "restricted building", "underground vaults", "storage rooms", "administrative offices"]

## Institution kinds (C§6-10). weights = what scouts test; focus = what the school trains.
const KINDS := {
	"magic_academy": {"label": "Magic Academy", "scout": "Academy Examiner", "names": ["Emberhold Royal Academy", "Silverquill College", "The Lantern Collegium"],
		"weights": {"intelligence": 1.0, "magic_sensitivity": 1.3, "memory": 0.9, "potential": 0.6, "discipline": 0.4},
		"focus": {"combat": 0.5, "theory": 1.5, "practical": 1.0, "leadership": 0.6, "discipline": 0.8},
		"tuition": 40, "prestige": [0.6, 0.9], "years": 6, "visit": 0.55, "wealth_bias": 1.0, "war_mod": -0.3, "church": 0.5, "culture": "courtly",
		"hosts": ["castle", "town"], "ranks": true, "path": "magic", "rival": "knight_academy", "specialist": false,
		"careers": {"mage": 0.7, "teacher": 0.1, "merchant": 0.08, "politician": 0.07, "rift_explorer": 0.05}, "orgs": ["research", "noble_house", "government", "guild", "rift_expedition", "school"]},
	"bending_school": {"label": "Bending School", "scout": "Stance Master", "names": ["Windrest Forms", "The Tidal Stance", "Cinder Root School"],
		"weights": {"resonance": 1.4, "condition": 0.8, "reflexes": 0.9, "discipline": 0.7, "constitution": 0.4},
		"focus": {"combat": 0.9, "theory": 0.5, "practical": 1.4, "leadership": 0.4, "discipline": 1.2},
		"tuition": 25, "prestige": [0.5, 0.85], "years": 6, "visit": 0.4, "wealth_bias": 0.6, "war_mod": 0.0, "church": 0.1, "culture": "pious",
		"hosts": ["village", "town"], "ranks": false, "path": "bending", "rival": "martial_sect", "specialist": false,
		"careers": {"bender": 0.7, "teacher": 0.12, "hunter": 0.06, "guild": 0.06, "soldier": 0.06}, "orgs": ["guild", "noble_house", "school", "army"]},
	"martial_sect": {"label": "Martial Sect", "scout": "Wandering Elder", "names": ["Azure Peak Sect", "Ashen Fist Hall", "Thornwolf Branch"],
		"weights": {"constitution": 1.3, "discipline": 1.0, "courage": 0.9, "reflexes": 0.9, "potential": 0.5},
		"focus": {"combat": 1.5, "theory": 0.3, "practical": 1.0, "leadership": 0.5, "discipline": 1.4},
		"tuition": 12, "prestige": [0.45, 0.85], "years": 7, "visit": 0.5, "wealth_bias": 0.3, "war_mod": 0.1, "church": 0.0, "culture": "martial",
		"hosts": ["village", "frontier_town"], "ranks": true, "path": "sect", "rival": "bending_school", "specialist": false,
		"careers": {"sect_disciple": 0.55, "soldier": 0.1, "criminal": 0.08, "guild": 0.1, "teacher": 0.12, "hunter": 0.05}, "orgs": ["sect", "guild", "army", "school"]},
	"knight_academy": {"label": "Knight Academy", "scout": "Recruiting Officer", "names": ["Ironvale Military Academy", "The Ember Lancers' School", "Kingsreach Cadet College"],
		"weights": {"condition": 1.0, "courage": 1.0, "leadership": 1.1, "discipline": 1.0, "constitution": 0.8},
		"focus": {"combat": 1.2, "theory": 0.7, "practical": 0.9, "leadership": 1.3, "discipline": 1.2},
		"tuition": 55, "prestige": [0.6, 0.9], "years": 6, "visit": 0.55, "wealth_bias": 1.2, "war_mod": 0.7, "church": 0.6, "culture": "martial",
		"hosts": ["castle", "frontier_town", "town"], "ranks": true, "path": "knight", "rival": "magic_academy", "specialist": false,
		"careers": {"soldier": 0.6, "politician": 0.1, "noble": 0.08, "merchant": 0.07, "teacher": 0.07, "criminal": 0.03, "priest": 0.05}, "orgs": ["army", "noble_house", "government", "school"]},
	"monster_lodge": {"label": "Monster-Hunting Lodge", "scout": "Lodge Warden", "names": ["Greyfang Lodge", "The Bramble Watch"],
		"weights": {"courage": 1.2, "reflexes": 1.0, "condition": 0.9, "constitution": 0.7, "memory": 0.4},
		"focus": {"combat": 1.2, "theory": 0.6, "practical": 1.4, "leadership": 0.5, "discipline": 0.8},
		"tuition": 10, "prestige": [0.3, 0.6], "years": 4, "visit": 0.3, "wealth_bias": 0.2, "war_mod": 0.1, "church": 0.1, "culture": "martial",
		"hosts": ["frontier_town", "village"], "ranks": false, "path": "hunter", "rival": "", "specialist": true,
		"careers": {"hunter": 0.6, "guild": 0.15, "soldier": 0.1, "rift_explorer": 0.15}, "orgs": ["guild", "rift_expedition", "army"]},
	"healer_monastery": {"label": "Healer Monastery", "scout": "Almoner", "names": ["Monastery of the Pale Lamp", "The Quiet Hands"],
		"weights": {"memory": 0.9, "discipline": 0.9, "intelligence": 0.7, "constitution": 0.5, "potential": 0.5},
		"focus": {"combat": 0.2, "theory": 1.2, "practical": 1.3, "leadership": 0.6, "discipline": 1.3},
		"tuition": 6, "prestige": [0.35, 0.7], "years": 5, "visit": 0.3, "wealth_bias": 0.3, "war_mod": 0.2, "church": 1.0, "culture": "pious",
		"hosts": ["town", "village"], "ranks": false, "path": "healer", "rival": "", "specialist": true,
		"careers": {"healer": 0.55, "priest": 0.25, "teacher": 0.1, "politician": 0.1}, "orgs": ["church", "guild", "army", "school"]},
	"archery_clan": {"label": "Archery Clan", "scout": "Clan Speaker", "names": ["Longshadow Clan", "The Reed Bows"],
		"weights": {"reflexes": 1.1, "discipline": 0.9, "condition": 0.8, "memory": 0.4, "courage": 0.5},
		"focus": {"combat": 1.2, "theory": 0.4, "practical": 1.3, "leadership": 0.5, "discipline": 1.1},
		"tuition": 8, "prestige": [0.3, 0.65], "years": 4, "visit": 0.25, "wealth_bias": 0.2, "war_mod": 0.2, "church": 0.0, "culture": "martial",
		"hosts": ["village"], "ranks": true, "path": "hunter", "rival": "", "specialist": true,
		"careers": {"hunter": 0.4, "soldier": 0.3, "guild": 0.15, "criminal": 0.05, "teacher": 0.1}, "orgs": ["army", "guild", "school"]},
	"rune_school": {"label": "Rune Engineering School", "scout": "Rune Warden", "names": ["The Stonekeepers' Hall", "Wardline Workshop"],
		"weights": {"intelligence": 1.1, "memory": 1.0, "magic_sensitivity": 0.7, "discipline": 0.6, "potential": 0.5},
		"focus": {"combat": 0.3, "theory": 1.3, "practical": 1.3, "leadership": 0.4, "discipline": 0.9},
		"tuition": 30, "prestige": [0.4, 0.75], "years": 5, "visit": 0.3, "wealth_bias": 0.7, "war_mod": 0.0, "church": 0.2, "culture": "mercantile",
		"hosts": ["castle", "town"], "ranks": true, "path": "magic", "rival": "", "specialist": true,
		"careers": {"mage": 0.3, "merchant": 0.25, "teacher": 0.15, "guild": 0.2, "rift_explorer": 0.1}, "orgs": ["government", "guild", "research", "school"]},
	"rift_college": {"label": "Rift Exploration College", "scout": "Rift Surveyor", "names": ["Deepsurvey College"],
		"weights": {"courage": 1.0, "intelligence": 0.9, "magic_sensitivity": 0.9, "constitution": 0.6, "memory": 0.6},
		"focus": {"combat": 0.8, "theory": 1.0, "practical": 1.2, "leadership": 0.7, "discipline": 0.8},
		"tuition": 45, "prestige": [0.55, 0.85], "years": 5, "visit": 0.1, "wealth_bias": 1.0, "war_mod": -0.2, "church": 0.1, "culture": "courtly",
		"hosts": ["castle", "frontier_town"], "ranks": true, "path": "magic", "rival": "", "specialist": true,
		"careers": {"rift_explorer": 0.6, "mage": 0.2, "soldier": 0.1, "criminal": 0.1}, "orgs": ["rift_expedition", "research", "government"]},
}
## Illegal teacher, never scouts a child; reachable only through late routes.
const HIDDEN_SCHOOL := {"label": "Back-Alley Blade School", "scout": "Stranger", "names": ["The Quiet Knife"],
	"weights": {"reflexes": 1.0, "courage": 0.8, "discipline": 0.5}, "focus": {"combat": 1.3, "theory": 0.2, "practical": 1.3, "leadership": 0.3, "discipline": 0.6},
	"tuition": 0, "prestige": [0.2, 0.3], "years": 3, "visit": 0.0, "wealth_bias": 0.0, "war_mod": 0.0, "church": 0.0, "culture": "martial",
	"hosts": ["town"], "ranks": false, "path": "sect", "rival": "", "specialist": true, "careers": {"criminal": 0.7, "soldier": 0.15, "guild": 0.15}, "orgs": ["guild"]}

const CAREERS := {
	"soldier": ["cadet", "lieutenant", "captain", "commander", "general"],
	"mage": ["apprentice mage", "adept", "battle mage", "court mage", "archmage"],
	"bender": ["initiate", "adept bender", "master bender", "temple warden", "grand bender"],
	"sect_disciple": ["outer disciple", "inner disciple", "senior disciple", "elder", "sect master"],
	"hunter": ["tracker", "hunter", "lodge captain", "warden", "hunt master"],
	"healer": ["novice healer", "healer", "physician", "chief physician", "abbot healer"],
	"priest": ["acolyte", "priest", "prelate", "bishop", "high priest"],
	"merchant": ["clerk", "factor", "trader", "merchant lord", "merchant prince"],
	"politician": ["page", "aide", "magistrate", "councillor", "chancellor"],
	"guild": ["member", "journeyman", "officer", "guild master", "guild chief"],
	"criminal": ["thug", "smuggler", "fixer", "gang boss", "crime lord"],
	"rift_explorer": ["porter", "surveyor", "expedition lead", "rift master", "deep marshal"],
	"teacher": ["assistant teacher", "teacher", "senior master", "head of house", "headmaster"],
	"noble": ["heir", "steward", "baron", "count", "duke"],
	"farmer": ["farmhand", "tenant", "freeholder", "landowner", "reeve"],
}
const RANK_MERIT := [1.0, 2.6, 4.8, 7.6, 11.0]

const BLOCKS := [
	{"id": "morning_training", "from": 6, "to": 8, "label": "Morning training", "kind": "training", "time_scale": 5.0, "dim": "combat"},
	{"id": "breakfast", "from": 8, "to": 9, "label": "Breakfast", "kind": "meal", "time_scale": 5.0, "dim": ""},
	{"id": "lessons", "from": 9, "to": 13, "label": "Lessons", "kind": "lesson", "time_scale": 5.0, "dim": "theory"},
	{"id": "practical", "from": 13, "to": 16, "label": "Practical training", "kind": "practical", "time_scale": 3.0, "dim": "practical"},
	{"id": "free_period", "from": 16, "to": 18, "label": "Free period", "kind": "free", "time_scale": 1.0, "dim": ""},
	{"id": "evening", "from": 18, "to": 22, "label": "Evening", "kind": "evening", "time_scale": 3.0, "dim": "discipline"},
	{"id": "night", "from": 22, "to": 30, "label": "Night", "kind": "rest", "time_scale": 1.0, "dim": ""},
]
const ATTEND_KINDS := ["training", "lesson", "practical"]
const SKIP_WEIGHT := {"training": 0.7, "lesson": 1.0, "practical": 1.2}

const INTERRUPTS := {
	"teacher_question": {"text": "The teacher stops and asks you to explain the point in front of everyone.", "blocks": ["lesson", "practical"],
		"choices": [{"id": "answer", "label": "Answer carefully", "fx": {"theory": 1.5, "regard": 3.0}}, {"id": "bluff", "label": "Bluff", "fx": {"discipline": -0.5, "regard": -2.0}},
			{"id": "deflect", "label": "Point at a classmate", "fx": {"regard": -1.0, "affinity_random": -4.0}}]},
	"duel_breaks_out": {"text": "Two students square up in the training yard and the class forms a ring.", "blocks": ["training", "practical"],
		"choices": [{"id": "fight", "label": "Step in and fight", "fx": {"combat": 2.0, "courage": 1.0, "fame": 1.0, "rival": "defeated"}}, {"id": "stop", "label": "Stop it", "fx": {"leadership": 1.5, "discipline": 0.5}},
			{"id": "watch", "label": "Watch", "fx": {}}]},
	"magic_loses_control": {"text": "Someone loses control of their power and the room fills with light.", "blocks": ["lesson", "practical"],
		"choices": [{"id": "shield", "label": "Shield the others", "fx": {"courage": 2.0, "practical": 1.5, "fame": 1.0}}, {"id": "run", "label": "Run", "fx": {"courage": -1.0}}, {"id": "calm", "label": "Talk them down", "fx": {"leadership": 2.0, "compassion": 1.0}}]},
	"important_npc": {"text": "The door opens: a stranger in fine travelling clothes is shown in and studies the room.", "blocks": ["lesson", "practical", "training"],
		"choices": [{"id": "impress", "label": "Give your best", "fx": {"contribution": 1.0, "regard": 1.0, "fame": 1.0}}, {"id": "ignore", "label": "Ignore them", "fx": {}}]},
	"creature_escapes": {"text": "A creature from the menagerie breaks loose and bolts across the yard.", "blocks": ["practical", "training"],
		"choices": [{"id": "catch", "label": "Chase it down", "fx": {"combat": 1.0, "practical": 1.5, "courage": 1.0}}, {"id": "warn", "label": "Raise the alarm", "fx": {"discipline": 1.0}}, {"id": "hide", "label": "Get clear", "fx": {}}]},
	"strange_discovery": {"text": "You notice something strange in a corner nobody is supposed to be in.", "blocks": ["lesson", "practical", "evening", "free"],
		"choices": [{"id": "investigate", "label": "Look closer", "fx": {"theory": 1.0, "lead": "campus_secret"}}, {"id": "report", "label": "Tell a teacher", "fx": {"discipline": 1.0, "regard": 2.0}}, {"id": "leave", "label": "Leave it", "fx": {}}]},
}

const TEACHER_TRAITS := {
	"exceptional": {"quality": 1.0, "corrupt": false, "text": "a genuinely brilliant teacher"},
	"mediocre": {"quality": 0.55, "corrupt": false, "text": "a mediocre teacher going through the motions"},
	"corrupt": {"quality": 0.6, "corrupt": true, "text": "a teacher who sells favours"},
	"caring": {"quality": 0.85, "corrupt": false, "text": "a teacher who truly cares about students"},
	"political": {"quality": 0.65, "corrupt": false, "text": "a teacher who is here for the politics"},
}
const SUBJECT_DEMAND := {"combat": {"stat": "discipline", "min": 45.0, "text": "a martial master demands discipline"},
	"theory": {"stat": "theory", "min": 50.0, "text": "a mage demands intellectual ability"},
	"leadership": {"stat": "courage", "min": 45.0, "text": "a knight commander demands courage"},
	"practical": {"stat": "practical", "min": 45.0, "text": "a master demands proven hands"},
	"discipline": {"stat": "discipline", "min": 50.0, "text": "a master demands discipline"}}

const EXPENSE_ONCE := {"uniform": {"cost": 25, "kit": 0.25, "text": "Uniform"}, "books": {"cost": 30, "kit": 0.2, "text": "Books"},
	"equipment": {"cost": 45, "kit": 0.35, "text": "Training equipment"}}
const EXPENSE_WEEKLY := {"food_supplements": 3, "materials": 2, "weapon_maintenance": 2, "medicine": 1, "personal": 2}
const BUDGETS := {"minimal": {"mult": 0.5, "kit": -0.02}, "standard": {"mult": 1.0, "kit": 0.0}, "full": {"mult": 1.8, "kit": 0.02}}

const SPONSOR_KINDS := {
	"academy": {"pays": 0.7, "stipend": 2, "names": ["the Academy Board"], "obl": ["report_grades"]},
	"guild": {"pays": 0.6, "stipend": 3, "names": ["the Guild of Masons", "the Merchants' Guild"], "obl": ["service_years", "report_grades"]},
	"noble": {"pays": 1.0, "stipend": 5, "names": ["House Aldane", "House Varrick", "House Corvane"], "obl": ["loyalty", "service_years"]},
	"military": {"pays": 1.0, "stipend": 4, "names": ["the Royal Army"], "obl": ["service_years"]},
	"merchant": {"pays": 0.8, "stipend": 4, "names": ["House Calder Trading Company"], "obl": ["favours", "service_years"]},
	"church": {"pays": 1.0, "stipend": 2, "names": ["the Church of the Dawn"], "obl": ["loyalty", "rites"]},
	"individual": {"pays": 0.5, "stipend": 3, "names": ["a retired adventurer"], "obl": ["favours"]},
}
const OBLIGATION_TEXT := {"report_grades": "Keep your grades above the sponsor's line.", "service_years": "Serve the sponsor for %d years after graduation.",
	"loyalty": "Stand with the sponsor when they call.", "favours": "Do the sponsor a favour when asked.", "rites": "Attend the sponsor's rites and lectures."}

const FACTIONS := {
	"nobles": {"label": "The Gilded", "opposed": "commoners", "need_class": 3},
	"commoners": {"label": "The Ash Bench", "opposed": "nobles", "need_class": -1},
	"foreign": {"label": "The Strangers' Table", "opposed": "", "need_class": -1},
	"combat": {"label": "The Yard Crowd", "opposed": "researchers", "need_class": -1},
	"researchers": {"label": "The Lamp Society", "opposed": "combat", "need_class": -1},
	"religious": {"label": "The Dawn Circle", "opposed": "", "need_class": -1},
}
const CLUBS := {
	"dueling": {"dim": "combat", "text": "Dueling Club"}, "alchemy": {"dim": "practical", "text": "Alchemy Circle"}, "magic_research": {"dim": "theory", "text": "Magic Research Group"},
	"weapons": {"dim": "combat", "text": "Weapons Society"}, "exploration": {"dim": "practical", "text": "Exploration Club"}, "beast_care": {"dim": "practical", "text": "Beast Care"},
	"strategy": {"dim": "leadership", "text": "Strategy Club"}, "theater": {"dim": "leadership", "text": "Theatre Troupe"}, "music": {"dim": "discipline", "text": "Music Circle"},
	"history": {"dim": "theory", "text": "History Society"}, "cooking": {"dim": "discipline", "text": "Cooking Club"}, "student_council": {"dim": "leadership", "text": "Student Council"},
}
const RIVAL_REASONS := ["defeated", "teacher_praise", "embarrassed", "same_love", "family_history", "opposing_faction"]
const TOURNAMENT_KINDS := {
	"internal": {"every": 60, "field": 16, "fame": 3.0, "text": "internal tournament"},
	"inter_school": {"every": 120, "field": 16, "fame": 9.0, "text": "inter-school tournament"},
	"regional": {"every": 240, "field": 32, "fame": 22.0, "text": "regional tournament"},
	"team": {"every": 150, "field": 8, "fame": 7.0, "text": "team competition"},
	"elemental": {"every": 200, "field": 16, "fame": 8.0, "text": "elemental competition"},
	"weapon": {"every": 180, "field": 16, "fame": 8.0, "text": "weapon competition"},
}
const EXERCISES := {
	"forest": {"danger": 0.18, "text": "a forest survival march"}, "ruins": {"danger": 0.28, "text": "an old ruin survey"},
	"village": {"danger": 0.08, "text": "helping a farming village"}, "rift_edge": {"danger": 0.42, "text": "a patrol at the edge of a rift"},
	"military_camp": {"danger": 0.14, "text": "a week at a military camp"}, "monster_territory": {"danger": 0.5, "text": "a sweep of monster territory"},
}
const LATE_ROUTES := {
	"private_teacher": {"text": "Find a private teacher and pay for lessons.", "gold": 60},
	"tuition_saving": {"text": "Save enough gold to sit the entrance exam and pay tuition.", "gold": 80},
	"sponsorship": {"text": "Win a sponsor: a guild, a noble or a merchant who sees your worth."},
	"smaller_school": {"text": "Join a smaller school that takes what the great ones overlook."},
	"learn_illegally": {"text": "Learn from a teacher the law does not approve of."},
	"old_manual": {"text": "Find an old manual and teach yourself from it."},
	"apprentice": {"text": "Become a master's apprentice."},
	"save_instructor": {"text": "Save an instructor's life and earn their gratitude."},
	"local_tournament": {"text": "Win a local tournament and make them notice you."},
	"military_service": {"text": "Enter through military service at sixteen."},
	"late_talent": {"text": "Discover your talent later in life."},
}
const GRAD_ORGS := {
	"army": {"role": "Officer Candidate", "wage": 14}, "guild": {"role": "Guild Journeyman", "wage": 11}, "noble_house": {"role": "House Retainer", "wage": 15},
	"research": {"role": "Research Fellow", "wage": 10}, "rift_expedition": {"role": "Expedition Surveyor", "wage": 16}, "school": {"role": "Assistant Teacher", "wage": 9},
	"government": {"role": "Clerk of the Crown", "wage": 12}, "sect": {"role": "Inner Disciple", "wage": 6}, "church": {"role": "Almoner's Aide", "wage": 7},
}
const SYL_A := ["Al", "Bre", "Cor", "Dar", "El", "Fen", "Gil", "Har", "Ise", "Jor", "Kel", "Lor", "Mar", "Nor", "Ori", "Pel", "Ren", "Sel", "Tor", "Ulf"]
const SYL_B := ["ric", "na", "dan", "wen", "mund", "la", "gar", "ith", "os", "ra", "vin", "el", "bert", "ly"]
const SURN := ["Ashby", "Brook", "Crane", "Dunn", "Ember", "Fallow", "Gray", "Hale", "Ironside", "Marsh", "Nettle", "Oakes", "Pike", "Reed", "Stone", "Thorne"]
const SCOUT_NAMES := ["Aldric Venn", "Mei Lan", "Oswin Harrow", "Sera Quill", "Tobias Rook", "Lin Yue", "Hadrin Cole", "Yara Sol", "Kest Marrow", "Rui Feng"]

var player: Dictionary = {"age": 4, "class": 0, "gold": 0, "home_sid": 0, "sid": 0, "fame": 0.0, "combat": 0.0, "on_campus": true}
var pending_gold: int = 0
var _pending_gains: Dictionary = {}
var _insts: Dictionary = {}
var _built := false
var season: Dictionary = {}
var late: Dictionary = {"overlooked": false, "prep": 0.0, "tutor": false, "flags": {}}
var student: Dictionary = {}
var cohorts: Dictionary = {}
var sponsors_list: Array = []
var rivals_list: Array = []
var tournaments_list: Array = []
var exercise: Dictionary = {}
var grad_offers: Array = []
var history: Array = []
var school_rep: Dictionary = {}
var combat_training: Dictionary = {"xp": 0.0, "sessions": 0, "by": {}, "last_day": -99}
var _interrupt: Dictionary = {}
var _skipped: Dictionary = {}
var _next_id := 1
var _day := 0
var _hour := 8
var _now := 0.0
var _at_war := false
var _game_season := "spring"


# ---------------------------------------------------------------- helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[r.randi() % arr.size()]


func _new_id(prefix: String) -> String:
	var s := "%s%d" % [prefix, _next_id]
	_next_id += 1
	return s


func _soc() -> RefCounted:
	if hub != null:
		return hub.mod("society")
	return null


func _hh() -> RefCounted:
	if hub != null:
		return hub.mod("household")
	return null


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return WorldGen.display_name(String(WorldGen.settlements[sid]["name"]))
	return "the road"


func _skind(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["kind"])
	return "village"


func _person_name(r: RandomNumberGenerator) -> String:
	return "%s%s %s" % [_pick(r, SYL_A), _pick(r, SYL_B), _pick(r, SURN)]


func _log(text: String) -> void:
	history.append({"day": _day, "text": text})
	if history.size() > 60:
		history.pop_front()


func set_player(d: Dictionary) -> void:
	for k: String in d:
		player[k] = d[k]
	if d.has("home_sid"):
		player["_home_set"] = true


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


## Stat gains earned here that Life should apply to the character: {"combat": 0.4, ...}.
func take_pending_gains() -> Dictionary:
	var g := _pending_gains.duplicate()
	_pending_gains.clear()
	return g


func _gain(key: String, amount: float) -> void:
	_pending_gains[key] = float(_pending_gains.get(key, 0.0)) + amount


func _gold() -> int:
	return int(player.get("gold", 0)) + pending_gold


func _sync(ctx: Dictionary) -> void:
	_now = float(ctx.get("abs_hours", _now))
	_at_war = bool(ctx.get("at_war", false))
	_game_season = String(ctx.get("season", _game_season))
	if ctx.has("gold"):
		player["gold"] = int(ctx["gold"])
	if ctx.get("stats") is Dictionary:
		for k: String in ctx["stats"]:
			player[k] = ctx["stats"][k]
	if ctx.has("age"):
		player["age"] = int(ctx["age"])
	var life: Variant = ctx.get("life")
	if life != null and life is Object:
		if ctx.has("age") == false and (life as Object).has_method("age"):
			player["age"] = int((life as Object).call("age"))
		var lp: Variant = (life as Object).get("life_path")
		if lp != null and lp is Object:
			var hs: Variant = (lp as Object).get("home_settlement")
			if hs != null and not player.get("_home_set", false):
				player["home_sid"] = int(hs)
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2 or pp is Vector3:
		var p2: Vector2 = Vector2(pp.x, pp.z) if pp is Vector3 else pp
		var n := _nearest(p2)
		if n >= 0:
			player["sid"] = n


func _nearest(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var d: float = (s["pos"] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = int(s["id"])
	if best >= 0 and bd > pow(float(WorldGen.settlements[best].get("radius", 100.0)) * 2.5, 2.0):
		return -1
	return best


func _church() -> float:
	if hub != null:
		var f: RefCounted = hub.mod("factions")
		if f != null and f.has_method("church_influence"):
			return float((f.call("church_influence", REGION) as Dictionary).get("influence", 0.2))
	return 0.2


func _dist(a: int, b: int) -> float:
	if a < 0 or b < 0 or a >= WorldGen.settlements.size() or b >= WorldGen.settlements.size():
		return 2000.0
	return (WorldGen.settlements[a]["pos"] as Vector2).distance_to(WorldGen.settlements[b]["pos"])


## 0..1 wealth of a settlement's region: kind, then famine and unrest pull it down.
func region_wealth(sid: int) -> float:
	var base: float = {"castle": 0.9, "town": 0.62, "frontier_town": 0.36, "village": 0.2}.get(_skind(sid), 0.2)
	var r := _rng("wealth", 0, sid)
	var w := base + (r.randf() - 0.5) * 0.16
	if hub != null:
		var sm: RefCounted = hub.mod("settlements")
		if sm != null and sm.has_method("emergencies"):
			for e: Dictionary in sm.call("emergencies", sid):
				if String(e.get("kind", "")) in ["famine", "plague", "raid"]:
					w -= 0.1
	return clampf(w, 0.02, 1.0)


func _unrest(sid: int) -> float:
	if hub != null:
		var l: RefCounted = hub.mod("land")
		if l != null and l.has_method("unrest"):
			return float(l.call("unrest", sid))
	return 0.0


# ---------------------------------------------------------------- institutions (C§6-11, C§46-48)

func _ensure() -> void:
	if _built:
		return
	_built = true
	var plan: Array = []
	for k: String in ["magic_academy", "bending_school", "martial_sect", "knight_academy"]:
		plan.append([k, false])
	if WorldGen.settlements.size() >= 8:
		for k: String in ["magic_academy", "bending_school", "martial_sect", "knight_academy"]:
			plan.append([k, true])
	for k: String in ["monster_lodge", "healer_monastery", "archery_clan", "rune_school", "rift_college"]:
		plan.append([k, false])
	plan.append(["hidden", false])
	var church := _church()
	var i := 0
	for p: Array in plan:
		var kind: String = p[0]
		var minor: bool = p[1]
		var def: Dictionary = HIDDEN_SCHOOL if kind == "hidden" else KINDS[kind]
		var r := _rng("inst", 0, i)
		var hosts: Array = []
		for s: Dictionary in WorldGen.settlements:
			var want: Array = ["village", "frontier_town"] if minor else def["hosts"]
			if String(s["kind"]) in want:
				hosts.append(int(s["id"]))
		if hosts.is_empty():
			for s: Dictionary in WorldGen.settlements:
				hosts.append(int(s["id"]))
		var sid: int = int(hosts[r.randi() % maxi(1, hosts.size())]) if not hosts.is_empty() else 0
		var pr: Array = def["prestige"]
		var prestige := snappedf(r.randf_range(0.25, 0.45) if minor else r.randf_range(float(pr[0]), float(pr[1])), 0.01)
		var nm: String = String(_pick(r, def["names"]))
		if minor:
			nm = "%s Hall of %s" % [String(def["label"]).split(" ")[0], _sname(sid)]
		var id := "inst_%d" % i
		_insts[id] = {"id": id, "kind": kind, "name": nm, "sid": sid, "minor": minor, "specialist": bool(def["specialist"]),
			"prestige": prestige, "tuition": int(round(float(def["tuition"]) * (0.5 if minor else 1.0))), "years": int(def["years"]),
			"church_funded": kind != "hidden" and r.randf() < clampf(church * float(def["church"]) * 1.6, 0.0, 0.9),
			"culture": String(def["culture"]), "ranks": bool(def["ranks"]) and not minor, "rival": "", "campus": "campus:%d" % sid,
			"hidden": kind == "hidden", "inflation": 1.0}
		i += 1
	# Rivals: each school hates the kind its philosophy opposes.
	for id: String in _insts:
		var rk: String = String((KINDS.get(_insts[id]["kind"], {}) as Dictionary).get("rival", ""))
		if rk == "" or bool(_insts[id]["minor"]):
			continue
		for oid: String in _insts:
			if String(_insts[oid]["kind"]) == rk and not bool(_insts[oid]["minor"]):
				_insts[id]["rival"] = oid
				break


func _def(inst: Dictionary) -> Dictionary:
	return HIDDEN_SCHOOL if String(inst["kind"]) == "hidden" else KINDS[String(inst["kind"])]


func institutions(include_hidden := false) -> Array:
	_ensure()
	var out: Array = []
	for id: String in _insts:
		if include_hidden or not bool(_insts[id]["hidden"]):
			out.append(_insts[id].duplicate(true))
	return out


func institution(id: String) -> Dictionary:
	_ensure()
	return (_insts.get(id, {}) as Dictionary).duplicate(true)


func campus_buildings(_id: String = "") -> Array:
	return CAMPUS.duplicate()


func church_schools() -> Array:
	return institutions().filter(func(x: Dictionary) -> bool: return bool(x["church_funded"]))


## C§48: church-funded schools and independent ones clash ideologically.
func ideology_clash(a_id: String, b_id: String) -> float:
	_ensure()
	if not _insts.has(a_id) or not _insts.has(b_id):
		return 0.0
	var a: bool = bool(_insts[a_id]["church_funded"])
	var b: bool = bool(_insts[b_id]["church_funded"])
	return 0.0 if a == b else 0.35 + 0.4 * _church()


# ---------------------------------------------------------------- Scout Season (C§3-5)

## Visit weight per institution for a village: geography, wealth, war, politics, church.
func visit_weights(sid: int, at_war := false, unrest := -1.0) -> Dictionary:
	_ensure()
	var wealth := region_wealth(sid)
	var un := _unrest(sid) if unrest < 0.0 else unrest
	var w := {}
	for id: String in _insts:
		var inst: Dictionary = _insts[id]
		if bool(inst["hidden"]):
			continue
		var def: Dictionary = _def(inst)
		var v := float(def["visit"])
		v *= clampf(1.25 - _dist(int(inst["sid"]), sid) / 2400.0, 0.1, 1.25)
		v *= 0.45 + wealth * float(def["wealth_bias"])
		if at_war:
			v *= maxf(0.1, 1.0 + float(def["war_mod"]))
		v *= 1.0 - 0.5 * un
		if bool(inst["church_funded"]):
			v *= 0.6 + _church() * 1.5
		if bool(inst["minor"]):
			v *= 0.6
		w[id] = snappedf(v, 0.0001)
	return w


func _child_axes() -> Dictionary:
	if player.get("axes") is Dictionary:
		return (player["axes"] as Dictionary).duplicate()
	var r := _rng("axes", 0, int(player.get("home_sid", 0)))
	var axes := {}
	for a: String in AXES:
		axes[a] = 28.0 + r.randf() * 44.0
	return axes


func _tendency_nudge(axes: Dictionary, ctx: Dictionary) -> Dictionary:
	var life: Variant = ctx.get("life")
	if life == null or not (life is Object):
		return axes
	var t: Variant = (life as Object).get("tendencies")
	if t == null or not (t is Object) or not (t as Object).has_method("value"):
		return axes
	var o := axes.duplicate()
	var m: float = float((t as Object).call("value", "martial")) - 0.35
	var s: float = float((t as Object).call("value", "scholarship")) - 0.35
	var f: float = float((t as Object).call("value", "faith")) - 0.35
	var ld: float = float((t as Object).call("value", "leadership")) - 0.35
	var w: float = float((t as Object).call("value", "wilderness")) - 0.35
	o["courage"] = float(o["courage"]) + m * 25.0
	o["constitution"] = float(o["constitution"]) + m * 20.0
	o["reflexes"] = float(o["reflexes"]) + m * 15.0
	o["intelligence"] = float(o["intelligence"]) + s * 25.0
	o["memory"] = float(o["memory"]) + s * 20.0
	o["discipline"] = float(o["discipline"]) + f * 20.0
	o["leadership"] = float(o["leadership"]) + ld * 30.0
	o["condition"] = float(o["condition"]) + w * 20.0
	var el: Variant = (t as Object).get("elements")
	if el is Dictionary:
		var top := 0.0
		for e: Variant in el:
			top = maxf(top, float(el[e]))
		o["magic_sensitivity"] = float(o["magic_sensitivity"]) + (top - 0.4) * 40.0
		o["resonance"] = float(o["resonance"]) + (top - 0.4) * 40.0
	return o


func child_prep() -> float:
	var cls := clampi(int(player.get("class", 0)), 0, 4)
	return CLASS_PREP[cls] + float(late.get("prep", 0.0)) + minf(8.0, float(combat_training["xp"]) / 25.0)


func scout_season() -> Dictionary:
	return season.duplicate(true)


func _maybe_start_season(day: int, ctx: Dictionary, out: Array[String]) -> void:
	if not season.is_empty() or int(player["age"]) < SCOUT_AGE:
		return
	_ensure()
	var sid := int(player["home_sid"])
	if int(player["age"]) > SCOUT_AGE + 1:
		season = {"status": "closed", "start_day": day, "end_day": day, "sid": sid, "scouts": [], "results": {}, "nobody": true, "missed": true}
		_mark_overlooked("The scouts came and went years ago; you were too young or nobody thought of you.", out)
		return
	var wealth := region_wealth(sid)
	var wv := visit_weights(sid, _at_war)
	var r := _rng("season", day, sid)
	var p_none := clampf(0.14 + (1.0 - wealth) * 0.35 + (0.12 if _at_war and _skind(sid) == "village" else 0.0), 0.05, 0.75)
	var n := 0
	if r.randf() >= p_none:
		n = 1 + (1 if r.randf() < 0.2 + wealth * 0.5 else 0) + (1 if r.randf() < wealth * 0.35 else 0)
	var scouts: Array = []
	var pool := wv.duplicate()
	for k in n:
		var total := 0.0
		for id: String in pool:
			total += float(pool[id])
		if total <= 0.0:
			break
		var roll := r.randf() * total
		var chosen := ""
		for id: String in pool:
			roll -= float(pool[id])
			if roll <= 0.0:
				chosen = id
				break
		if chosen == "":
			chosen = pool.keys()[pool.size() - 1]
		pool.erase(chosen)
		var inst: Dictionary = _insts[chosen]
		var def: Dictionary = _def(inst)
		var arrive := r.randi_range(0, 9)
		scouts.append({"id": "sc_%d_%d" % [day, k], "inst": chosen, "name": String(_pick(r, SCOUT_NAMES)), "title": String(def["scout"]),
			"corrupt": r.randf() < 0.12 + float(inst["prestige"]) * 0.3, "price": int(40 + 90 * float(inst["prestige"])),
			"bias": snappedf(r.randf_range(0.3, 1.0), 0.01), "noble_pressure": snappedf(r.randf() * (0.2 + 0.7 * wealth) if r.randf() < 0.35 else 0.0, 0.01),
			"seats": 1 + (1 if r.randf() < 0.4 else 0), "arrive": day + arrive, "leave": day + arrive + r.randi_range(3, 8), "attended": false, "arrived_told": false})
	var axes := _tendency_nudge(_child_axes(), ctx)
	for a: String in axes:
		axes[a] = clampf(float(axes[a]), 5.0, 98.0)
	season = {"status": "open", "start_day": day, "end_day": day + SEASON_DAYS, "sid": sid, "wealth": snappedf(wealth, 0.01), "war": _at_war,
		"scouts": scouts, "results": {}, "nobody": scouts.is_empty(), "axes": axes, "weights": wv}
	out.append("Word spreads through %s: the scouts are coming for this year's nine-year-olds." % _sname(sid))
	if scouts.is_empty():
		out.append("As the season wears on it becomes clear that nobody important is coming to %s this year." % _sname(sid))
	var soc := _soc()
	if soc != null:
		soc.learn("topic:scout_season", "This year's scout season: families talk of little else.")


func scouts_present(day := -1) -> Array:
	var d := _day if day < 0 else day
	var out: Array = []
	for s: Dictionary in season.get("scouts", []):
		if d >= int(s["arrive"]) and d <= int(s["leave"]) and not bool(s["attended"]):
			out.append(s.duplicate(true))
	return out


func _scout(id: String) -> Dictionary:
	for s: Dictionary in season.get("scouts", []):
		if String(s["id"]) == id:
			return s
	return {}


## Score of a child on the axes an institution tests (0..100), with prep and prejudice.
func _test_score(inst: Dictionary, sc: Dictionary, bribed: bool) -> Dictionary:
	var def: Dictionary = _def(inst)
	var axes: Dictionary = season.get("axes", _child_axes())
	var weights: Dictionary = def["weights"]
	var prep := child_prep()
	var total := 0.0
	var wsum := 0.0
	var shown: Array = []
	var r := _rng("test", int(season.get("start_day", 0)), String(sc["id"]))
	for a: String in weights:
		var v := float(axes.get(a, 40.0)) + prep * 0.6 + (r.randf() - 0.5) * 12.0
		total += v * float(weights[a])
		wsum += float(weights[a])
		shown.append({"axis": a, "value": int(clampf(v, 0.0, 100.0))})
	var score := total / maxf(0.01, wsum)
	var pen := 0.0
	if int(player.get("class", 0)) == 0:
		pen += 9.0 * float(sc["bias"])
	pen += float(sc["noble_pressure"]) * 18.0
	if bribed:
		pen -= 20.0
	return {"score": snappedf(score - pen, 0.1), "raw": snappedf(score, 0.1), "shown": shown, "penalty": snappedf(pen, 0.1)}


func admission_threshold(inst: Dictionary) -> float:
	return 45.0 + float(inst["prestige"]) * 30.0


## Sit the test in front of a visiting scout. `bribe` only works on a corrupt scout.
func attend(scout_id: String, bribe := 0) -> Dictionary:
	var sc := _scout(scout_id)
	if sc.is_empty() or String(season.get("status", "")) != "open":
		return {"ok": false, "reason": "No such scout."}
	if _day < int(sc["arrive"]) or _day > int(sc["leave"]):
		return {"ok": false, "reason": "%s is not in the village today." % sc["name"]}
	if bool(sc["attended"]):
		return {"ok": false, "reason": "You have already been tested."}
	var inst: Dictionary = _insts[String(sc["inst"])]
	var bribed := false
	var msgs: Array = []
	if bribe > 0:
		if not bool(sc["corrupt"]):
			return {"ok": false, "reason": "%s stiffens at the offer. Some scouts cannot be bought." % sc["name"]}
		if bribe < int(sc["price"]) or _gold() < bribe:
			return {"ok": false, "reason": "%s wants at least %d gold." % [sc["name"], int(sc["price"])]}
		pending_gold -= bribe
		bribed = true
		msgs.append("%s pockets the coins and does not meet your eye." % sc["name"])
	sc["attended"] = true
	var t := _test_score(inst, sc, bribed)
	var thr := admission_threshold(inst)
	var verdict := "overlooked"
	var unfair := false
	if float(t["score"]) >= thr:
		verdict = "selected"
	elif float(t["score"]) >= thr - 6.0:
		verdict = "waitlist"
	if verdict != "selected" and float(t["raw"]) >= thr + 4.0 and (float(sc["noble_pressure"]) > 0.15 or (int(player.get("class", 0)) == 0 and float(sc["bias"]) > 0.6)):
		unfair = true
	var res := {"scout": scout_id, "inst": String(sc["inst"]), "score": t["score"], "threshold": snappedf(thr, 0.1), "verdict": verdict,
		"unfair": unfair, "bribed": bribed, "shown": t["shown"], "day": _day,
		"waived": verdict == "selected" and (float(t["score"]) - thr >= 8.0 or bool(inst["church_funded"]))}
	(season["results"] as Dictionary)[scout_id] = res
	if bribed and _rng("caught", _day, scout_id).randf() < 0.12:
		res["scandal"] = true
		_school_rep_add(String(sc["inst"]), -8.0)
		msgs.append("Someone saw the coins change hands. It will not stay quiet.")
	var soc := _soc()
	if unfair and soc != null:
		soc.learn("secret:seat_sold_%s" % String(sc["inst"]), "You tested better than the child they took: the seat went to family connections.")
	res["messages"] = msgs
	return {"ok": true, "result": res, "reason": ""}


func admission_offers() -> Array:
	var out: Array = []
	for k: String in season.get("results", {}):
		var r: Dictionary = season["results"][k]
		if String(r["verdict"]) == "selected" and not bool(r.get("taken", false)):
			out.append(r.duplicate(true))
	return out


func _close_season(out: Array[String]) -> void:
	if String(season.get("status", "")) != "open":
		return
	season["status"] = "closed"
	for s: Dictionary in season["scouts"]:
		if not bool(s["attended"]):
			out.append("%s from %s left without ever seeing you." % [s["name"], _insts[String(s["inst"])]["name"]])
	if admission_offers().is_empty() and student.is_empty():
		_mark_overlooked("The scout season is over and no door opened for you. The easy route is closed, not the road.", out)
	else:
		out.append("The scout season ends. There is an offer waiting for you.")


func _mark_overlooked(text: String, out: Array[String]) -> void:
	late["overlooked"] = true
	out.append(text)
	var soc := _soc()
	if soc != null:
		soc.learn("topic:late_routes", "Being overlooked is not the end: private teachers, sponsors, smaller schools, old manuals and the army all take late starters.")
		soc.learn("lead:old_manual", "People in the village say an old manual is kept in a chest somewhere.")


func is_overlooked() -> bool:
	return bool(late["overlooked"])


## C§5: routes that stay open after being overlooked. Each has availability and a reason.
func late_routes(ctx := {}) -> Array:
	_ensure()
	var out: Array = []
	var age := int(player["age"])
	var soc := _soc()
	var gold := _gold()
	var fame := float(player.get("fame", 0.0)) + float(student.get("fame", 0.0))
	for id: String in LATE_ROUTES:
		var def: Dictionary = LATE_ROUTES[id]
		var ok := true
		var why := ""
		match id:
			"private_teacher":
				ok = gold >= int(def["gold"]) and not bool(late["tutor"])
				why = "Costs %d gold." % int(def["gold"]) if gold < int(def["gold"]) else ("You already have one." if bool(late["tutor"]) else "")
			"tuition_saving":
				ok = gold >= int(def["gold"])
				why = "You need %d gold saved." % int(def["gold"]) if not ok else ""
			"sponsorship":
				ok = fame >= 4.0 or _has_active_sponsor() or not sponsor_offers().is_empty()
				why = "Nobody has noticed you yet." if not ok else ""
			"smaller_school":
				ok = age >= 10
				why = "Too young for the smaller schools." if not ok else ""
			"learn_illegally":
				ok = age >= 11
				why = "Nobody will teach a child that." if not ok else ""
			"old_manual":
				ok = soc != null and soc.knows("lead:old_manual")
				why = "You have not heard of a manual." if not ok else ""
			"apprentice":
				ok = age >= 11
				why = "Masters take apprentices from eleven." if not ok else ""
			"save_instructor":
				ok = bool((late["flags"] as Dictionary).get("saved_instructor", false))
				why = "Nobody's life needs saving yet." if not ok else ""
			"local_tournament":
				ok = int((late["flags"] as Dictionary).get("local_wins", 0)) > 0 or fame >= 10.0
				why = "You have not won anything yet." if not ok else ""
			"military_service":
				ok = age >= 16
				why = "The army takes recruits at sixteen." if not ok else ""
			"late_talent":
				ok = age >= 14
				why = "Talent shows itself later." if not ok else ""
		out.append({"id": id, "text": String(def["text"]), "available": ok, "reason": why})
	return out


func take_late_route(route_id: String, ctx := {}) -> Dictionary:
	if not LATE_ROUTES.has(route_id):
		return {"ok": false, "reason": "Unknown route."}
	for r: Dictionary in late_routes(ctx):
		if String(r["id"]) == route_id and not bool(r["available"]):
			return {"ok": false, "reason": String(r["reason"])}
	var flags: Dictionary = late["flags"]
	match route_id:
		"private_teacher":
			pending_gold -= int(LATE_ROUTES[route_id]["gold"])
			late["tutor"] = true
			late["prep"] = float(late["prep"]) + 6.0
			return {"ok": true, "reason": "A retired teacher agrees to take you on. Your preparation improves.", "next": "exam"}
		"tuition_saving":
			return {"ok": true, "reason": "You have the fee for an entrance exam.", "next": "exam"}
		"smaller_school":
			return {"ok": true, "reason": "A smaller school will look at you.", "next": "exam", "minor_only": true}
		"learn_illegally":
			_enroll_hidden(ctx)
			return {"ok": true, "reason": "A stranger shows you a door with no sign.", "next": "enrolled"}
		"old_manual":
			late["prep"] = float(late["prep"]) + 4.0
			flags["manual"] = true
			return {"ok": true, "reason": "You teach yourself from the manual. It is slow and it works.", "next": "exam"}
		"apprentice":
			late["prep"] = float(late["prep"]) + 5.0
			flags["apprenticed"] = true
			return {"ok": true, "reason": "You start as a master's apprentice.", "next": "exam"}
		"military_service":
			return {"ok": true, "reason": "You can apply to the knight academy through military entry.", "next": "military_entry"}
		"sponsorship":
			return {"ok": true, "reason": "A sponsor is watching you.", "next": "sponsorship"}
		"save_instructor", "local_tournament", "late_talent":
			return {"ok": true, "reason": "Your deed opens a door.", "next": "tournament"}
	return {"ok": false, "reason": ""}


func note_late_flag(flag: String, value: Variant = true) -> void:
	(late["flags"] as Dictionary)[flag] = value


# ---------------------------------------------------------------- admission (C§3, C§5)

func admission_options(inst_id: String, _ctx := {}) -> Array:
	_ensure()
	var out: Array = []
	if not _insts.has(inst_id):
		return out
	var inst: Dictionary = _insts[inst_id]
	var age := int(player["age"])
	var offered := false
	for r: Dictionary in admission_offers():
		if String(r["inst"]) == inst_id:
			offered = true
	out.append({"route": "scout", "available": offered, "reason": "" if offered else "No scout has offered you a place here."})
	out.append({"route": "exam", "available": age >= 10 and _gold() >= 10, "reason": "Entrance exam, 10 gold, from age ten." if age < 10 or _gold() < 10 else ""})
	var sp := _has_active_sponsor()
	out.append({"route": "sponsorship", "available": sp, "reason": "" if sp else "You need a sponsor."})
	out.append({"route": "private_teacher", "available": bool(late["tutor"]) and age >= 10, "reason": "" if bool(late["tutor"]) else "You have no private teacher."})
	var mil := age >= 16 and String(inst["kind"]) in ["knight_academy", "martial_sect", "monster_lodge", "archery_clan"]
	out.append({"route": "military_entry", "available": mil, "reason": "" if mil else "Military entry: sixteen and a military school."})
	var tw := int((late["flags"] as Dictionary).get("local_wins", 0)) > 0 or float(player.get("fame", 0.0)) >= 20.0
	out.append({"route": "tournament", "available": tw, "reason": "" if tw else "Win a tournament first."})
	return out


## Apply by a non-scout route. Returns {ok, verdict, reason}. On success the player is enrolled.
func apply(inst_id: String, route: String, ctx := {}) -> Dictionary:
	_ensure()
	if not student.is_empty() and String(student["status"]) in ["enrolled", "suspended", "on_leave"]:
		return {"ok": false, "verdict": "no", "reason": "You are already a student."}
	if not _insts.has(inst_id):
		return {"ok": false, "verdict": "no", "reason": "No such school."}
	var inst: Dictionary = _insts[inst_id]
	for o: Dictionary in admission_options(inst_id, ctx):
		if String(o["route"]) == route and not bool(o["available"]):
			return {"ok": false, "verdict": "no", "reason": String(o["reason"])}
	var thr := admission_threshold(inst)
	var sponsor := {}
	match route:
		"scout":
			var enrolled := _enroll(inst_id, "scout", ctx)
			for k: String in season.get("results", {}):
				var rr: Dictionary = season["results"][k]
				if String(rr["inst"]) == inst_id and String(rr["verdict"]) == "selected":
					rr["taken"] = true
			return {"ok": true, "verdict": "selected", "reason": "You take the place.", "student": enrolled}
		"exam":
			pending_gold -= 10
			thr += 6.0
		"private_teacher":
			thr += 2.0
		"sponsorship":
			for sp: Dictionary in sponsors_list:
				if String(sp["status"]) == "active":
					sponsor = sp
			thr -= 6.0
		"military_entry":
			thr -= 8.0
		"tournament":
			thr -= 10.0
	var axes := _child_axes()
	var def: Dictionary = _def(inst)
	var total := 0.0
	var wsum := 0.0
	for a: String in def["weights"]:
		total += float(axes.get(a, 40.0)) * float(def["weights"][a])
		wsum += float(def["weights"][a])
	var mean := total / maxf(0.01, wsum)
	var age_bonus := clampf(float(int(player["age"]) - 9) * 1.5, 0.0, 12.0)
	var score := mean + child_prep() * 0.6 + age_bonus + (_rng("apply", _day, inst_id + route).randf() - 0.5) * 10.0
	if int(player.get("class", 0)) == 0 and route == "exam":
		score -= 3.0
	if score < thr:
		return {"ok": false, "verdict": "rejected", "reason": "The examiners thank you and send you away. (%d of %d)" % [int(score), int(thr)]}
	return {"ok": true, "verdict": "admitted", "reason": "You are admitted.", "student": _enroll(inst_id, route, ctx, sponsor)}


# ---------------------------------------------------------------- enrolment and cohort (C§11, C§16, C§49)

func _enroll_hidden(ctx: Dictionary) -> void:
	_ensure()
	for id: String in _insts:
		if bool(_insts[id]["hidden"]):
			_enroll(id, "illegal", ctx)
			return


func _enroll(inst_id: String, route: String, ctx: Dictionary, sponsor := {}) -> Dictionary:
	var inst: Dictionary = _insts[inst_id]
	var def: Dictionary = _def(inst)
	var axes := _tendency_nudge(_child_axes(), ctx)
	var perf := {}
	perf["combat"] = 12.0 + 0.16 * (float(axes["reflexes"]) + float(axes["constitution"]) + float(axes["courage"]))
	perf["theory"] = 12.0 + 0.2 * (float(axes["intelligence"]) + float(axes["memory"]))
	perf["practical"] = 12.0 + 0.2 * (float(axes["potential"]) + float(axes["magic_sensitivity"]))
	perf["leadership"] = 10.0 + 0.3 * float(axes["leadership"])
	perf["discipline"] = 10.0 + 0.3 * float(axes["discipline"])
	for k: String in perf:
		perf[k] = snappedf(float(perf[k]) + child_prep() * 0.3, 0.1)
	var waived := false
	for r: Dictionary in admission_offers():
		if String(r["inst"]) == inst_id and bool(r.get("waived", false)):
			waived = true
	if bool(inst["church_funded"]) and int(player.get("class", 0)) == 0:
		waived = true
	var cid := _new_id("co")
	student = {"inst": inst_id, "route": route, "since": _day, "status": "enrolled", "cohort": cid, "perf": perf,
		"traits": {"courage": snappedf(float(axes["courage"]), 0.1), "compassion": 40.0}, "contribution": 0.0, "fame": 0.0, "regard": 0.0,
		"truancy": 0.0, "stage": 0, "detention_days": 0, "privileges": true, "suspended_until": -1, "kit": 0.15, "budget": "standard",
		"arrears": 0.0, "arrears_weeks": 0, "waived": waived, "club": "", "faction": "", "mentor": {}, "strikes": 0,
		"teachers": _gen_teachers(inst, cid), "church_loyalty": 0.0, "tournament_wins": 0, "recruited": [], "skips": 0, "attended_h": 0,
		"injured_until": -1, "price_index": 1.0, "rank_flags": {}}
	cohorts[cid] = _gen_cohort(cid, inst, axes)
	while cohorts.size() > COHORTS_KEPT:
		cohorts.erase(cohorts.keys()[0])
	if not sponsor.is_empty():
		student["sponsor"] = String(sponsor["id"])
	school_rep[inst_id] = float(school_rep.get(inst_id, 0.0))
	_log("Enrolled at %s by route %s." % [inst["name"], route])
	var soc := _soc()
	if soc != null:
		soc.learn("place:%d:%s" % [int(inst["sid"]), "academy"], "%s stands in %s." % [inst["name"], _sname(int(inst["sid"]))])
	return {"inst": inst_id, "cohort": cid}


func is_student() -> bool:
	return not student.is_empty() and String(student["status"]) in ["enrolled", "suspended", "on_leave"]


func student_state() -> Dictionary:
	return student.duplicate(true)


func alma_mater() -> Dictionary:
	if student.is_empty():
		return {}
	return institution(String(student["inst"]))


## Named path teachers seated at an institution (scripts/abilities/path_teachers.gd): the sect elders and palm
## masters of a martial sect, the magisters of an academy, drill sergeants and knight-captains of a knight academy,
## stance masters, beastwardens (the lodge). The person's name is rolled from the institution id, so it never changes.
## -> [{id, name, title, path, blurb, ways, lessons: [technique ids], taught: bool, institution}]
func path_teachers(inst_id: String) -> Array:
	_ensure()
	var inst: Dictionary = _insts.get(inst_id, {})
	var out: Array = []
	if inst.is_empty() or bool(inst["hidden"]):
		return out
	var pp: Variant = hub.mod("power_paths") if hub != null and (hub.mods as Dictionary).has("power_paths") else null
	var taught: Array = pp.teachers() if pp != null else []
	for tid: String in PathTeachers.at_venue(String(inst["kind"])):
		if bool(inst["minor"]) and tid in ["knight_captain", "second_path_examiner", "palm_master"]:
			continue                   # village halls keep only the first teachers
		var p := PathTeachers.person(tid, String(inst["id"]) + String(inst["name"]))
		p["lessons"] = PathTeachers.lessons(tid)
		p["taught"] = taught.has(tid)
		p["institution"] = inst_id
		out.append(p)
	return out


## Standing at an institution for teacher terms: students of it count 3, plus anything the caller reports.
func path_favour(inst_id: String, extra := 0.0) -> float:
	var f := extra
	if is_student() and String(alma_mater().get("id", "")) == inst_id:
		f += 3.0
	return f


## Study under one of the institution's teachers. ctx: favour, quests, profile_extra. Gold goes through the ledger.
## -> PathTeachers.learn_from result plus {"name"}
func learn_from_path_teacher(inst_id: String, teacher_id: String, ctx := {}) -> Dictionary:
	var roster := path_teachers(inst_id)
	var who: Dictionary = {}
	for p: Dictionary in roster:
		if p["id"] == teacher_id:
			who = p
	if who.is_empty():
		return {"ok": false, "text": "Nobody of that kind teaches here.", "fee": 0, "reasons": ["absent"]}
	var pp: Variant = hub.mod("power_paths") if hub != null and (hub.mods as Dictionary).has("power_paths") else null
	var c := ctx.duplicate()
	c["gold"] = _gold()
	c["favour"] = path_favour(inst_id, float(ctx.get("favour", 0.0)))
	var r: Dictionary = PathTeachers.learn_from(teacher_id, pp, c)
	r["name"] = who["name"]
	if bool(r["ok"]):
		pending_gold -= int(r["fee"])
		_log("%s teaches you at %s." % [who["name"], _insts[inst_id]["name"]])
	return r


func _gen_teachers(inst: Dictionary, cid: String) -> Array:
	var out: Array = []
	var subjects := ["combat", "theory", "practical", "leadership", "discipline", "theory"]
	var traits := TEACHER_TRAITS.keys()
	for i in subjects.size():
		var r := _rng("teacher", i, cid + String(inst["id"]))
		var tr: String = traits[r.randi() % traits.size()]
		out.append({"id": "%s_t%d" % [cid, i], "name": _person_name(r), "subject": subjects[i], "trait": tr, "regard": 0.0,
			"temper": snappedf(r.randf(), 0.01), "lenient": r.randf() < 0.3, "independence_fan": r.randf() < 0.25,
			"quality": snappedf(float(TEACHER_TRAITS[tr]["quality"]) * (0.85 + 0.3 * r.randf()) * float(inst.get("staff", 1.0)), 0.01)})
	return out


func _class_roll(prestige: float, church_free: bool, r: RandomNumberGenerator) -> int:
	var x := r.randf()
	if church_free and x < 0.35:
		return 0
	var elite := prestige
	if x < 0.30 - 0.15 * elite:
		return 0
	if x < 0.55 - 0.05 * elite:
		return 1
	if x < 0.78:
		return 2
	if x < 0.93:
		return 3
	return 4


func _gen_cohort(cid: String, inst: Dictionary, _axes: Dictionary) -> Dictionary:
	var def: Dictionary = _def(inst)
	var members: Array = []
	var age0 := int(player["age"])
	for i in COHORT_SIZE:
		var r := _rng("classmate", i, cid)
		var cls := _class_roll(float(inst["prestige"]), bool(inst["church_funded"]), r)
		var prep: float = CLASS_PREP[cls] * 0.3
		var perf := {}
		for d: String in PERF:
			perf[d] = snappedf(clampf(12.0 + r.randf() * 34.0 + prep + float(def["focus"][d]) * 4.0, 5.0, 90.0), 0.1)
		var pers := {"ambition": snappedf(r.randf(), 0.01), "honor": snappedf(r.randf(), 0.01), "snobbery": snappedf(clampf(r.randf() * 0.7 + cls * 0.08, 0.0, 1.0), 0.01),
			"jealousy": snappedf(r.randf(), 0.01), "kindness": snappedf(r.randf(), 0.01)}
		var fac := "commoners" if cls == 0 else ("nobles" if cls >= 3 else "")
		if fac == "":
			var options: Array = ["foreign", "combat", "researchers", "religious"]
			fac = String(options[r.randi() % options.size()])
		if r.randf() < 0.1:
			fac = "foreign"
		members.append({"id": "%s_m%d" % [cid, i], "name": _person_name(r), "sex": "f" if r.randf() < 0.5 else "m", "class": cls, "sid": int(r.randi() % maxi(1, WorldGen.settlements.size())),
			"age": age0, "perf": perf, "pers": pers, "faction": fac, "club": "", "kit": snappedf(clampf(0.25 + cls * 0.18 + (r.randf() - 0.5) * 0.2, 0.0, 1.0), 0.01),
			"affinity": 0.0, "familiarity": 0.0, "roommate": i < 3, "status": "student", "career": {}, "announced": false, "contribution": snappedf(r.randf() * 20.0, 0.1)})
	return {"id": cid, "inst": String(inst["id"]), "start_day": _day, "start_age": age0, "years": int(inst["years"]), "graduated": false, "members": members}


func cohort(cid := "") -> Dictionary:
	if cid == "" and not student.is_empty():
		cid = String(student["cohort"])
	return (cohorts.get(cid, {}) as Dictionary).duplicate(true)


## Direct (mutable) roster for internal use.
func _members(cid := "") -> Array:
	if cid == "" and not student.is_empty():
		cid = String(student["cohort"])
	return (cohorts.get(cid, {}) as Dictionary).get("members", [])


## Public copy of the roster (~30 named classmates).
func classmates(cid := "") -> Array:
	return _members(cid).duplicate(true)


func _member(mid: String) -> Dictionary:
	for cid: String in cohorts:
		for m: Dictionary in cohorts[cid]["members"]:
			if String(m["id"]) == mid:
				return m
	return {}


func classmate(mid: String) -> Dictionary:
	return _member(mid).duplicate(true)


## C§16/49: interact with a classmate. kinds: talk help spar study gift snub embarrass defeat
func interact(mid: String, kind: String) -> Dictionary:
	var m := _member(mid)
	if m.is_empty():
		return {"ok": false, "reason": "No such classmate."}
	var d := {"talk": 2.0, "help": 5.0, "spar": 3.0, "study": 3.5, "gift": 4.0, "snub": -5.0, "embarrass": -9.0, "defeat": -3.0}
	if not d.has(kind):
		return {"ok": false, "reason": "Unknown interaction."}
	var delta := float(d[kind])
	if delta > 0.0 and float((m["pers"] as Dictionary)["snobbery"]) > 0.6 and int(player.get("class", 0)) == 0:
		delta *= 0.4
	m["affinity"] = clampf(float(m["affinity"]) + delta, -100.0, 100.0)
	m["familiarity"] = clampf(float(m["familiarity"]) + 2.0, 0.0, 100.0)
	if kind in ["embarrass", "defeat"]:
		_consider_rival(mid, kind if kind == "embarrass" else "defeated")
	if kind == "study" and not student.is_empty():
		(student["perf"] as Dictionary)["theory"] = minf(100.0, float(student["perf"]["theory"]) + 0.3)
	if kind == "spar" and not student.is_empty():
		(student["perf"] as Dictionary)["combat"] = minf(100.0, float(student["perf"]["combat"]) + 0.3)
	return {"ok": true, "affinity": m["affinity"], "reason": ""}


# ---------------------------------------------------------------- schedule and time acceleration (C§12)

func schedule() -> Array:
	var out: Array = []
	for b: Dictionary in BLOCKS:
		out.append((b as Dictionary).duplicate())
	return out


func block_at(hour: int) -> Dictionary:
	var h := hour % 24
	for b: Dictionary in BLOCKS:
		var f: int = b["from"]
		var t: int = b["to"]
		if (h >= f and h < t) or (h + 24 >= f and h + 24 < t):
			return (b as Dictionary).duplicate()
	return {}


## Time acceleration for the current block: 5 for routine lessons, 1 when an
## interrupt is live or the player is not a student on campus.
func time_scale(hour := -1) -> float:
	if not is_student() or String(student["status"]) != "enrolled" or not _interrupt.is_empty() or not bool(player.get("on_campus", true)):
		return 1.0
	var b := block_at(_hour if hour < 0 else hour)
	if b.is_empty():
		return 1.0
	return float(b["time_scale"])


func current_interrupt() -> Dictionary:
	return _interrupt.duplicate(true)


func skip_block(block_id: String) -> Dictionary:
	if not is_student() or String(student["status"]) != "enrolled":
		return {"ok": false, "reason": "You are not attending classes."}
	var b := {}
	for x: Dictionary in BLOCKS:
		if String(x["id"]) == block_id:
			b = x
	if b.is_empty() or not (String(b["kind"]) in ATTEND_KINDS):
		return {"ok": false, "reason": "That block cannot be skipped."}
	if _skipped.has(block_id):
		return {"ok": true, "reason": "Already skipping."}
	_mark_skip(b)
	return {"ok": true, "reason": "You slip away.", "stage": LADDER[int(student["stage"])]}


func _mark_skip(b: Dictionary) -> void:
	_skipped[String(b["id"])] = true
	student["skips"] = int(student["skips"]) + 1
	var w := float(SKIP_WEIGHT.get(String(b["kind"]), 1.0))
	# Teachers who admire independence forgive a student who is training elsewhere.
	var trained := _day - int(combat_training["last_day"]) <= 3
	for t: Dictionary in student["teachers"]:
		if trained and bool(t["independence_fan"]):
			w *= 0.5
			t["regard"] = float(t["regard"]) + 0.5
		elif bool(t["lenient"]):
			w *= 0.9
		elif float(t["temper"]) > 0.7:
			t["regard"] = float(t["regard"]) - 0.8
	student["truancy"] = float(student["truancy"]) + w
	var perf: Dictionary = student["perf"]
	var dim: String = String(b["dim"])
	if dim != "":
		perf[dim] = maxf(0.0, float(perf[dim]) - 0.15)


func set_on_campus(on: bool) -> void:
	player["on_campus"] = on


func truancy_stage() -> String:
	return LADDER[int(student.get("stage", 0))] if not student.is_empty() else LADDER[0]


func _update_stage(out: Array[String]) -> void:
	if student.is_empty() or String(student["status"]) == "expelled":
		return
	var tr := float(student["truancy"])
	var stage := 0
	for i in LADDER_AT.size():
		if tr >= LADDER_AT[i]:
			stage = i
	var old := int(student["stage"])
	if stage <= old:
		return
	student["stage"] = stage
	match stage:
		1:
			out.append("A teacher takes you aside about your absences. This is a warning.")
		2:
			student["detention_days"] = 2
			out.append("Detention: two days confined to the study hall.")
		3:
			student["privileges"] = false
			out.append("Your privileges are revoked: no clubs, no off-campus work, no leave.")
		4:
			student["suspensions"] = int(student.get("suspensions", 0)) + 1
			if int(student["suspensions"]) >= 2:
				student["stage"] = 5
				student["status"] = "expelled"
				_school_rep_add(String(student["inst"]), -6.0)
				out.append("A second suspension is one too many: you are expelled from %s." % _insts[String(student["inst"])]["name"])
				_log("Expelled for truancy.")
				_end_student_state()
				return
			student["status"] = "suspended"
			student["suspended_until"] = _day + 10
			out.append("You are suspended for ten days.")
		5:
			student["status"] = "expelled"
			_school_rep_add(String(student["inst"]), -6.0)
			out.append("You are expelled from %s." % _insts[String(student["inst"])]["name"])
			_log("Expelled for truancy.")
			_end_student_state()


# ---------------------------------------------------------------- interrupts

func _roll_interrupt(hour: int, b: Dictionary, out: Array[String]) -> void:
	var r := _rng("interrupt", _day * 24 + hour, "x")
	if r.randf() >= INTERRUPT_CHANCE:
		return
	var options: Array = []
	for k: String in INTERRUPTS:
		if String(b["kind"]) in INTERRUPTS[k]["blocks"]:
			options.append(k)
	if options.is_empty():
		return
	var kind: String = options[r.randi() % options.size()]
	_interrupt = {"kind": kind, "text": String(INTERRUPTS[kind]["text"]), "day": _day, "hour": hour, "block": String(b["id"]),
		"choices": (INTERRUPTS[kind]["choices"] as Array).duplicate(true)}
	out.append("%s" % _interrupt["text"])


func resolve_interrupt(choice_id := "") -> Dictionary:
	if _interrupt.is_empty():
		return {"ok": false, "reason": "Nothing is happening."}
	var kind: String = _interrupt["kind"]
	var fx := {}
	for c: Dictionary in INTERRUPTS[kind]["choices"]:
		if String(c["id"]) == choice_id:
			fx = (c["fx"] as Dictionary).duplicate()
	_interrupt = {}
	if not student.is_empty():
		_apply_effects(fx)
	return {"ok": true, "kind": kind, "effects": fx}


func _apply_effects(fx: Dictionary) -> void:
	var perf: Dictionary = student["perf"]
	for k: String in fx:
		var v: Variant = fx[k]
		if perf.has(k):
			perf[k] = clampf(float(perf[k]) + float(v), 0.0, 100.0)
			_gain(k, float(v) * 0.1)
		elif k == "courage" or k == "compassion":
			(student["traits"] as Dictionary)[k] = float(student["traits"][k]) + float(v) * 3.0
		elif k == "fame":
			student["fame"] = float(student["fame"]) + float(v)
		elif k == "regard":
			for t: Dictionary in student["teachers"]:
				t["regard"] = float(t["regard"]) + float(v)
		elif k == "contribution":
			student["contribution"] = float(student["contribution"]) + float(v)
		elif k == "rival" and v is String:
			var ms: Array = _members()
			if not ms.is_empty():
				var m: Dictionary = ms[_rng("rv", _day, "duel").randi() % ms.size()]
				_consider_rival(String(m["id"]), String(v))
		elif k == "lead" and v is String:
			var soc := _soc()
			if soc != null:
				soc.learn("lead:%s" % String(v), "Something hidden lies in the restricted part of the campus.")
		elif k == "affinity_random":
			var ms2: Array = _members()
			if not ms2.is_empty():
				var m2: Dictionary = _member(String(ms2[_rng("aff", _day, "x").randi() % ms2.size()]["id"]))
				m2["affinity"] = float(m2["affinity"]) + float(v)


# ---------------------------------------------------------------- performance and rankings (C§14, C§15)

func performance(dim := "") -> Variant:
	if student.is_empty():
		return {} if dim == "" else 0.0
	if dim == "":
		return (student["perf"] as Dictionary).duplicate()
	return float(student["perf"].get(dim, 0.0))


static func letter(v: float) -> String:
	if v >= 85.0:
		return "S"
	if v >= 70.0:
		return "A"
	if v >= 55.0:
		return "B"
	if v >= 40.0:
		return "C"
	if v >= 25.0:
		return "D"
	return "E"


## Report card: no single score, one letter per dimension plus strengths and weaknesses.
func report_card() -> Dictionary:
	if student.is_empty():
		return {}
	var grades := {}
	var best := ""
	var worst := ""
	for d: String in PERF:
		var v: float = float(student["perf"][d])
		grades[d] = letter(v)
		if best == "" or v > float(student["perf"][best]):
			best = d
		if worst == "" or v < float(student["perf"][worst]):
			worst = d
	return {"grades": grades, "strength": best, "weakness": worst, "truancy": LADDER[int(student["stage"])], "fame": student["fame"]}


func _cat_score(perf_d: Dictionary, contribution: float, cat: String) -> float:
	match cat:
		"combat":
			return float(perf_d["combat"])
		"academic":
			return float(perf_d["theory"])
		"practical":
			return float(perf_d["practical"])
		"leadership":
			return float(perf_d["leadership"])
		"discipline":
			return float(perf_d["discipline"])
		"contribution":
			return contribution
	return (float(perf_d["combat"]) + float(perf_d["theory"]) + float(perf_d["practical"]) + float(perf_d["leadership"]) + float(perf_d["discipline"])) / 5.0


func rankings(cat := "overall") -> Dictionary:
	if student.is_empty():
		return {}
	var inst: Dictionary = _insts[String(student["inst"])]
	if not bool(inst["ranks"]):
		return {"published": false, "rows": [], "note": "%s considers rankings harmful and publishes none." % inst["name"]}
	var rows: Array = [{"id": "player", "name": "You", "score": snappedf(_cat_score(student["perf"], float(student["contribution"]), cat), 0.1), "player": true}]
	for m: Dictionary in _members():
		if String(m["status"]) == "student":
			rows.append({"id": String(m["id"]), "name": String(m["name"]), "score": snappedf(_cat_score(m["perf"], float(m["contribution"]), cat), 0.1), "player": false})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]) or (float(a["score"]) == float(b["score"]) and String(a["id"]) < String(b["id"])))
	for i in rows.size():
		rows[i]["rank"] = i + 1
	return {"published": true, "cat": cat, "rows": rows}


func player_rank(cat := "overall") -> int:
	var r := rankings(cat)
	if not bool(r.get("published", false)):
		return -1
	for row: Dictionary in r["rows"]:
		if bool(row["player"]):
			return int(row["rank"])
	return -1


func _recruiter_watch(out: Array[String]) -> void:
	if student.is_empty() or not bool(_insts[String(student["inst"])]["ranks"]):
		return
	var best := 99
	for c: String in RANK_CATS:
		var rk := player_rank(c)
		if rk > 0:
			best = mini(best, rk)
	if best > 3:
		return
	var r := _rng("recruit", _day, "x")
	if r.randf() < 0.35 and student["recruited"].size() < 6:
		var kinds := ["noble", "guild", "military", "merchant"]
		var k: String = kinds[r.randi() % kinds.size()]
		if k != "" and sponsor_offers().size() < 3 and not _has_active_sponsor():
			var sp := _make_sponsor(k, r)
			sponsors_list.append(sp)
			(student["recruited"] as Array).append(String(sp["id"]))
			out.append("A recruiter from %s has been watching you and has an offer." % sp["name"])
	if r.randf() < 0.3:
		var ms := _members()
		if not ms.is_empty():
			var m: Dictionary = ms[r.randi() % ms.size()]
			if float(m["perf"]["combat"]) > 35.0:
				_consider_rival(String(m["id"]), "opposing_faction")
				out.append("%s challenges you in front of the yard." % m["name"])


# ---------------------------------------------------------------- social class and expenses (C§17, C§18)

func kit_gap() -> float:
	if student.is_empty():
		return 0.0
	var tot := 0.0
	var n := 0
	for m: Dictionary in _members():
		tot += float(m["kit"])
		n += 1
	return snappedf(tot / maxf(1.0, float(n)) - float(student["kit"]), 0.01)


func regard_of(mid: String) -> float:
	var m := _member(mid)
	if m.is_empty() or student.is_empty():
		return 0.0
	var mine := _cat_score(student["perf"], float(student["contribution"]), "overall")
	var theirs := _cat_score(m["perf"], float(m["contribution"]), "overall")
	var v := 50.0 + float(m["affinity"]) * 0.5 + (mine - theirs) * 0.4
	var gap := int(m["class"]) - int(player.get("class", 0))
	if gap > 0:
		v -= gap * 8.0 * float((m["pers"] as Dictionary)["snobbery"])
	v -= maxf(0.0, kit_gap()) * 12.0 * float((m["pers"] as Dictionary)["snobbery"])
	if String(m["faction"]) == String(student["faction"]) and String(m["faction"]) != "":
		v += 8.0
	return snappedf(clampf(v, 0.0, 100.0), 0.1)


func treatment() -> Dictionary:
	if student.is_empty():
		return {}
	var snubs: Array = []
	var friends: Array = []
	for m: Dictionary in _members():
		var rg := regard_of(String(m["id"]))
		if rg < 35.0:
			snubs.append(String(m["id"]))
		elif rg > 65.0:
			friends.append(String(m["id"]))
	return {"class": CLASS_NAMES[clampi(int(player.get("class", 0)), 0, 4)], "kit_gap": kit_gap(), "snubbed_by": snubs, "respected_by": friends,
		"sponsored": _has_active_sponsor()}


func expenses() -> Array:
	var out: Array = []
	if student.is_empty():
		return out
	var pi := float(student["price_index"])
	for k: String in EXPENSE_ONCE:
		out.append({"id": k, "kind": "once", "cost": int(round(float(EXPENSE_ONCE[k]["cost"]) * pi)), "text": EXPENSE_ONCE[k]["text"], "owned": (student.get("owned", []) as Array).has(k)})
	for k: String in EXPENSE_WEEKLY:
		out.append({"id": k, "kind": "weekly", "cost": int(round(float(EXPENSE_WEEKLY[k]) * float(BUDGETS[String(student["budget"])]["mult"]) * pi)), "text": k.replace("_", " ")})
	return out


func tuition_weekly() -> int:
	if student.is_empty() or bool(student["waived"]):
		return 0
	var inst: Dictionary = _insts[String(student["inst"])]
	var base := float(inst["tuition"]) / 4.0 * float(student["price_index"])
	var covered := 0.0
	var sp := _sponsor_of_student()
	if not sp.is_empty():
		covered = float(sp["pays"])
	return int(round(base * (1.0 - covered)))


func weekly_cost() -> int:
	if student.is_empty():
		return 0
	var c := tuition_weekly()
	for e: Dictionary in expenses():
		if String(e["kind"]) == "weekly":
			c += int(e["cost"])
	return c


func buy(item: String) -> Dictionary:
	if student.is_empty() or not EXPENSE_ONCE.has(item):
		return {"ok": false, "reason": "Nothing to buy."}
	var owned: Array = student.get("owned", [])
	if owned.has(item):
		return {"ok": false, "reason": "You already have it."}
	var cost := int(round(float(EXPENSE_ONCE[item]["cost"]) * float(student["price_index"])))
	if _gold() < cost:
		return {"ok": false, "reason": "%d gold needed." % cost}
	pending_gold -= cost
	owned.append(item)
	student["owned"] = owned
	student["kit"] = clampf(float(student["kit"]) + float(EXPENSE_ONCE[item]["kit"]), 0.0, 1.0)
	return {"ok": true, "reason": ""}


func set_budget(level: String) -> bool:
	if student.is_empty() or not BUDGETS.has(level):
		return false
	student["budget"] = level
	return true


## Weekly bill: player purse first, then household support, else arrears.
func _charge_week(weeks: float, out: Array[String]) -> void:
	if student.is_empty() or String(student["status"]) in ["expelled", "graduated", "dropped"]:
		return
	var sp := _sponsor_of_student()
	var due := float(weekly_cost()) * weeks
	if not sp.is_empty():
		pending_gold += int(float(sp["stipend"]) * weeks)
	var pay := mini(int(due), maxi(0, _gold()))
	pending_gold -= pay
	var short := due - float(pay)
	if short > 0.0:
		var hh := _hh()
		if hh != null and hh.has_method("support_student"):
			short -= float(hh.call("support_student", short))
	if short > 0.5:
		student["arrears"] = float(student["arrears"]) + short
		student["arrears_weeks"] = int(student["arrears_weeks"]) + int(ceil(weeks))
		if int(student["arrears_weeks"]) == 2:
			out.append("The bursar reminds you that %d gold is owed." % int(student["arrears"]))
		if int(student["arrears_weeks"]) >= NONPAY_WEEKS and String(student["status"]) == "enrolled":
			student["status"] = "suspended"
			student["suspended_until"] = _day + 14
			out.append("The bursar suspends you until the arrears are paid.")
	else:
		student["arrears_weeks"] = maxi(0, int(student["arrears_weeks"]) - 1)
		var pay_off := minf(float(student["arrears"]), float(maxi(0, _gold())))
		if pay_off > 0.0:
			pending_gold -= int(pay_off)
			student["arrears"] = float(student["arrears"]) - pay_off
	student["kit"] = clampf(float(student["kit"]) + float(BUDGETS[String(student["budget"])]["kit"]) * weeks, 0.0, 1.0)


func pay_arrears(amount: int) -> Dictionary:
	if student.is_empty() or float(student["arrears"]) <= 0.0:
		return {"ok": false, "reason": "Nothing is owed."}
	var a := mini(amount, mini(int(student["arrears"]), _gold()))
	if a <= 0:
		return {"ok": false, "reason": "No gold."}
	pending_gold -= a
	student["arrears"] = float(student["arrears"]) - a
	if float(student["arrears"]) <= 0.5:
		student["arrears_weeks"] = 0
		if String(student["status"]) == "suspended" and int(student["stage"]) < 4:
			student["status"] = "enrolled"
			student["suspended_until"] = -1
	return {"ok": true, "reason": ""}


# ---------------------------------------------------------------- sponsors (C§22)

func _make_sponsor(kind: String, r: RandomNumberGenerator) -> Dictionary:
	var def: Dictionary = SPONSOR_KINDS[kind]
	var obls: Array = []
	for o: String in def["obl"]:
		var txt: String = OBLIGATION_TEXT[o]
		var yrs := 2 + r.randi() % 3
		if o == "service_years":
			txt = txt % yrs
		obls.append({"id": _new_id("ob"), "kind": o, "text": txt, "years": yrs if o == "service_years" else 0, "due": _day + 60 + r.randi_range(0, 90), "done": false})
	return {"id": _new_id("sp"), "kind": kind, "name": String(_pick(r, def["names"])), "pays": float(def["pays"]), "stipend": int(def["stipend"]),
		"status": "offered", "since": _day, "obligations": obls, "strikes": 0, "min_grade": 32.0 + r.randf() * 10.0}


func sponsor_offers() -> Array:
	return sponsors_list.filter(func(s: Dictionary) -> bool: return String(s["status"]) == "offered")


func sponsors() -> Array:
	return sponsors_list.filter(func(s: Dictionary) -> bool: return String(s["status"]) == "active")


func _has_active_sponsor() -> bool:
	for s: Dictionary in sponsors_list:
		if String(s["status"]) == "active":
			return true
	return false


func _sponsor_of_student() -> Dictionary:
	for s: Dictionary in sponsors_list:
		if String(s["status"]) == "active":
			return s
	return {}


## Seek a sponsor of a given kind. Needs fame, rank or a scholar's grades.
func seek_sponsor(kind: String) -> Dictionary:
	if not SPONSOR_KINDS.has(kind):
		return {"ok": false, "reason": "Unknown sponsor kind."}
	var merit := float(player.get("fame", 0.0)) + float(student.get("fame", 0.0))
	if not student.is_empty():
		merit += _cat_score(student["perf"], float(student["contribution"]), "overall") * 0.4
	var r := _rng("seek", _day, kind)
	if r.randf() * 30.0 > merit:
		return {"ok": false, "reason": "They are not interested yet."}
	var sp := _make_sponsor(kind, r)
	sponsors_list.append(sp)
	return {"ok": true, "sponsor": sp["id"], "reason": "%s will hear terms." % sp["name"]}


func accept_sponsor(sid: String) -> Dictionary:
	for s: Dictionary in sponsors_list:
		if String(s["id"]) == sid and String(s["status"]) == "offered":
			if _has_active_sponsor():
				return {"ok": false, "reason": "You already have a sponsor."}
			s["status"] = "active"
			s["since"] = _day
			if not student.is_empty():
				student["sponsor"] = sid
			return {"ok": true, "reason": "Money rarely comes free: read the terms.", "obligations": (s["obligations"] as Array).duplicate(true)}
	return {"ok": false, "reason": "No such offer."}


func decline_sponsor(sid: String) -> void:
	for s: Dictionary in sponsors_list:
		if String(s["id"]) == sid and String(s["status"]) == "offered":
			s["status"] = "declined"


func fulfil_obligation(obl_id: String) -> bool:
	for s: Dictionary in sponsors_list:
		for o: Dictionary in s["obligations"]:
			if String(o["id"]) == obl_id and not bool(o["done"]):
				o["done"] = true
				return true
	return false


## Obligations that outlive school: service years owed after graduation.
func obligations_after_school() -> Array:
	var out: Array = []
	for s: Dictionary in sponsors_list:
		if String(s["status"]) in ["active", "graduated"]:
			for o: Dictionary in s["obligations"]:
				if String(o["kind"]) == "service_years" and not bool(o["done"]):
					out.append({"sponsor": s["name"], "kind": s["kind"], "years": o["years"], "id": o["id"]})
	return out


func _sponsor_week(out: Array[String]) -> void:
	if student.is_empty():
		return
	var avg := _cat_score(student["perf"], 0.0, "overall")
	for s: Dictionary in sponsors_list:
		if String(s["status"]) != "active":
			continue
		for o: Dictionary in s["obligations"]:
			if bool(o["done"]) or _day < int(o["due"]):
				continue
			if String(o["kind"]) == "report_grades":
				if avg >= float(s["min_grade"]):
					o["done"] = true
				else:
					s["strikes"] = int(s["strikes"]) + 1
					o["due"] = _day + 30
					out.append("%s is unhappy with your grades." % s["name"])
			elif String(o["kind"]) in ["loyalty", "favours", "rites"]:
				if String(o["kind"]) == "rites" and bool(_insts[String(student["inst"])]["church_funded"]):
					o["done"] = true
				else:
					s["strikes"] = int(s["strikes"]) + 1
					o["due"] = _day + 45
					out.append("%s reminds you what you owe: %s" % [s["name"], String(o["text"])])
		if int(s["strikes"]) >= 3:
			s["status"] = "withdrawn"
			student.erase("sponsor")
			out.append("%s withdraws sponsorship." % s["name"])


# ---------------------------------------------------------------- factions and clubs (C§23, C§24)

func student_factions() -> Array:
	var out: Array = []
	var counts := {}
	for m: Dictionary in _members():
		counts[String(m["faction"])] = int(counts.get(String(m["faction"]), 0)) + 1
	for id: String in FACTIONS:
		var def: Dictionary = FACTIONS[id]
		out.append({"id": id, "label": def["label"], "opposed": def["opposed"], "members": int(counts.get(id, 0)), "joined": not student.is_empty() and String(student["faction"]) == id})
	return out


func join_faction(fid: String) -> Dictionary:
	if student.is_empty() or not FACTIONS.has(fid):
		return {"ok": false, "reason": "No such group."}
	var need: int = int(FACTIONS[fid]["need_class"])
	var eff := maxi(int(player.get("class", 0)), 3 if _sponsor_kind() == "noble" else 0)
	if need >= 0 and eff < need:
		return {"ok": false, "reason": "They do not admit your kind."}
	if fid == "religious" and not bool(_insts[String(student["inst"])]["church_funded"]) and float((student["traits"] as Dictionary).get("compassion", 0.0)) < 40.0:
		return {"ok": false, "reason": "The circle sees no devotion in you."}
	student["faction"] = fid
	for m: Dictionary in _members():
		if String(m["faction"]) == fid:
			m["affinity"] = clampf(float(m["affinity"]) + 6.0, -100.0, 100.0)
		elif String(m["faction"]) == String(FACTIONS[fid]["opposed"]):
			m["affinity"] = clampf(float(m["affinity"]) - 6.0, -100.0, 100.0)
	return {"ok": true, "reason": "You sit with them."}


func leave_faction() -> void:
	if not student.is_empty():
		student["faction"] = ""


func _sponsor_kind() -> String:
	return String(_sponsor_of_student().get("kind", ""))


func clubs() -> Array:
	var out: Array = []
	for id: String in CLUBS:
		out.append({"id": id, "text": CLUBS[id]["text"], "joined": not student.is_empty() and String(student["club"]) == id})
	return out


func join_club(cid: String) -> Dictionary:
	if student.is_empty() or not CLUBS.has(cid):
		return {"ok": false, "reason": "No such club."}
	if not bool(student["privileges"]):
		return {"ok": false, "reason": "You have lost your privileges."}
	student["club"] = cid
	var r := _rng("club", 0, cid + String(student["cohort"]))
	var ms := _members()
	for i in 4:
		if ms.is_empty():
			break
		var m: Dictionary = _member(String(ms[r.randi() % ms.size()]["id"]))
		m["club"] = cid
		m["affinity"] = clampf(float(m["affinity"]) + 4.0, -100.0, 100.0)
	return {"ok": true, "reason": "You join the %s." % CLUBS[cid]["text"]}


func leave_club() -> void:
	if not student.is_empty():
		student["club"] = ""


# ---------------------------------------------------------------- rivals (C§25)

func _consider_rival(mid: String, reason: String) -> void:
	if not (reason in RIVAL_REASONS) and reason != "embarrass":
		return
	for rv: Dictionary in rivals_list:
		if String(rv["member"]) == mid:
			rv["heat"] = minf(100.0, float(rv["heat"]) + 12.0)
			return
	var m := _member(mid)
	if m.is_empty():
		return
	rivals_list.append({"member": mid, "name": String(m["name"]), "reason": reason, "heat": 40.0, "since": _day, "status": "rival",
		"grace": snappedf(float((m["pers"] as Dictionary)["honor"]) * 0.5 + float((m["pers"] as Dictionary)["kindness"]) * 0.5, 0.01)})
	m["affinity"] = clampf(float(m["affinity"]) - 15.0, -100.0, 100.0)


func rivals() -> Array:
	return rivals_list.filter(func(r: Dictionary) -> bool: return String(r["status"]) == "rival")


func reconcile(mid: String) -> Dictionary:
	for rv: Dictionary in rivals_list:
		if String(rv["member"]) == mid and String(rv["status"]) == "rival":
			if float(rv["grace"]) + _rng("rec", _day, mid).randf() * 0.6 < 0.55:
				return {"ok": false, "reason": "%s will not hear it yet." % rv["name"]}
			rv["heat"] = maxf(0.0, float(rv["heat"]) - 40.0)
			return {"ok": true, "reason": "The edge goes out of it."}
	return {"ok": false, "reason": "No rivalry."}


func _rival_week(out: Array[String]) -> void:
	for rv: Dictionary in rivals_list:
		if String(rv["status"]) != "rival":
			continue
		rv["heat"] = float(rv["heat"]) * 0.96
		if float(rv["heat"]) < 15.0:
			rv["status"] = "ally"
			var m := _member(String(rv["member"]))
			if not m.is_empty():
				m["affinity"] = clampf(float(m["affinity"]) + 45.0, -100.0, 100.0)
			out.append("%s and you have stopped fighting. Somewhere along the way it turned into respect." % rv["name"])
			var soc := _soc()
			if soc != null:
				soc.learn("contact:rival_ally_%s" % String(rv["member"]), "%s, once your rival, would stand with you." % rv["name"])


# ---------------------------------------------------------------- teachers and mentorship (C§26-27)

func teachers() -> Array:
	return (student.get("teachers", []) as Array).duplicate(true)


func _teacher(tid: String) -> Dictionary:
	for t: Dictionary in student.get("teachers", []):
		if String(t["id"]) == tid:
			return t
	return {}


func bribe_teacher(tid: String, gold: int) -> Dictionary:
	var t := _teacher(tid)
	if t.is_empty() or String(t["trait"]) != "corrupt":
		return {"ok": false, "reason": "This teacher cannot be bought."}
	if gold < 20 or _gold() < gold:
		return {"ok": false, "reason": "It is not enough."}
	pending_gold -= gold
	(student["perf"] as Dictionary)[String(t["subject"])] = minf(100.0, float(student["perf"][String(t["subject"])]) + 1.0)
	t["regard"] = float(t["regard"]) + 4.0
	student["fame"] = float(student["fame"]) - 0.5
	return {"ok": true, "reason": "A grade is quietly improved."}


func mentor_candidates() -> Array:
	var out: Array = []
	for t: Dictionary in student.get("teachers", []):
		if float(t["regard"]) >= 3.0 and float(student["perf"][String(t["subject"])]) >= 40.0 and String(t["trait"]) != "mediocre":
			var dm: Dictionary = SUBJECT_DEMAND[String(t["subject"])]
			out.append({"teacher": t["id"], "name": t["name"], "subject": t["subject"], "demand": dm["text"]})
	return out


func _demand_value(stat: String) -> float:
	if stat == "courage":
		return float((student["traits"] as Dictionary)["courage"])
	return float(student["perf"].get(stat, 0.0))


func request_mentorship(tid: String) -> Dictionary:
	if student.is_empty() or not (student["mentor"] as Dictionary).is_empty():
		return {"ok": false, "reason": "You already have a mentor." if not student.is_empty() else "You are not a student."}
	var t := _teacher(tid)
	if t.is_empty():
		return {"ok": false, "reason": "No such teacher."}
	var ok_c := false
	for c: Dictionary in mentor_candidates():
		if String(c["teacher"]) == tid:
			ok_c = true
	if not ok_c:
		return {"ok": false, "reason": "%s does not see it in you yet." % t["name"]}
	var dm: Dictionary = SUBJECT_DEMAND[String(t["subject"])]
	if _demand_value(String(dm["stat"])) < float(dm["min"]):
		return {"ok": false, "reason": "%s: %s." % [t["name"], dm["text"]]}
	student["mentor"] = {"teacher": tid, "since": _day, "stat": dm["stat"], "min": dm["min"], "strikes": 0}
	return {"ok": true, "reason": "%s takes you as a personal student. %s." % [t["name"], String(dm["text"]).capitalize()]}


func mentor() -> Dictionary:
	return (student.get("mentor", {}) as Dictionary).duplicate(true)


func _mentor_week(out: Array[String]) -> void:
	if student.is_empty() or (student["mentor"] as Dictionary).is_empty():
		return
	var mn: Dictionary = student["mentor"]
	if _demand_value(String(mn["stat"])) < float(mn["min"]) - 5.0:
		mn["strikes"] = int(mn["strikes"]) + 1
		out.append("Your mentor notes that you are falling short of what they asked for.")
	else:
		mn["strikes"] = maxi(0, int(mn["strikes"]) - 1)
	if int(mn["strikes"]) >= 3:
		student["mentor"] = {}
		out.append("Your mentor ends the arrangement. It is not personal; you did not meet the terms.")


# ---------------------------------------------------------------- tournaments (C§28) and field exercises (C§29)

func tournaments() -> Array:
	return tournaments_list.filter(func(t: Dictionary) -> bool: return String(t["status"]) == "open")


func _schedule_tournaments(out: Array[String]) -> void:
	if student.is_empty() or String(student["status"]) != "enrolled":
		return
	var inst: Dictionary = _insts[String(student["inst"])]
	for kind: String in TOURNAMENT_KINDS:
		var def: Dictionary = TOURNAMENT_KINDS[kind]
		if kind == "elemental" and not (String(inst["kind"]) in ["magic_academy", "bending_school"]):
			continue
		if kind == "weapon" and not (String(inst["kind"]) in ["knight_academy", "martial_sect", "archery_clan"]):
			continue
		var offset := int(absi(hash([kind, inst["id"]])) % int(def["every"]))
		if _day > 0 and (_day + offset) % int(def["every"]) == 0:
			var dup := false
			for t: Dictionary in tournaments_list:
				if String(t["kind"]) == kind and String(t["status"]) == "open":
					dup = true
			if not dup:
				tournaments_list.append({"id": _new_id("tn"), "kind": kind, "inst": String(inst["id"]), "day": _day, "close": _day + 4, "status": "open"})
				out.append("The %s has been announced." % def["text"])


func enter_tournament(tid: String, ctx := {}) -> Dictionary:
	for t: Dictionary in tournaments_list:
		if String(t["id"]) != tid or String(t["status"]) != "open":
			continue
		if student.is_empty() or String(student["status"]) != "enrolled":
			return {"ok": false, "reason": "You cannot compete now."}
		if int(student["injured_until"]) > _day:
			return {"ok": false, "reason": "You are still injured."}
		var def: Dictionary = TOURNAMENT_KINDS[String(t["kind"])]
		var n := int(def["field"])
		var p: Dictionary = student["perf"]
		var me := float(p["combat"]) * 0.55 + float(p["practical"]) * 0.25 + float(p["discipline"]) * 0.2 + float(student["kit"]) * 6.0 + float(player.get("combat", 0.0)) * 0.3
		var r := _rng("tourney", _day, tid)
		var field: Array = []
		var ms := _members()
		for i in n - 1:
			if i < ms.size() and i < n / 2:
				var m: Dictionary = ms[i]
				field.append({"id": String(m["id"]), "power": float(m["perf"]["combat"]) * 0.55 + float(m["perf"]["practical"]) * 0.25 + float(m["perf"]["discipline"]) * 0.2})
			else:
				field.append({"id": "", "power": 20.0 + r.randf() * 30.0 + (10.0 if String(t["kind"]) in ["regional", "inter_school"] else 0.0)})
		var wins := 0
		var blog: Array = []
		var beaten := ""
		var rounds := int(ceil(log(float(n)) / log(2.0)))
		var alive := true
		for rd in rounds:
			var opp: Dictionary = field[r.randi() % field.size()]
			var roll := me + (r.randf() - 0.5) * 30.0
			var orl: float = float(opp["power"]) + (r.randf() - 0.5) * 30.0
			if roll >= orl:
				wins += 1
				if String(opp["id"]) != "":
					beaten = String(opp["id"])
				blog.append("Round %d: you win." % (rd + 1))
			else:
				blog.append("Round %d: you lose." % (rd + 1))
				alive = false
				break
		t["status"] = "done"
		var placing := "champion" if alive else ("finalist" if wins >= rounds - 1 else ("semifinal" if wins >= rounds - 2 else "early exit"))
		var fame := float(def["fame"]) * (0.2 + float(wins) / float(maxi(1, rounds)) * 1.2)
		student["fame"] = float(student["fame"]) + fame
		student["contribution"] = float(student["contribution"]) + 1.0
		var pf: Dictionary = student["perf"]
		pf["combat"] = minf(100.0, float(pf["combat"]) + 0.8 + wins * 0.3)
		_gain("combat", 0.1 + 0.05 * wins)
		var msgs: Array[String] = []
		if alive:
			student["tournament_wins"] = int(student["tournament_wins"]) + 1
			player["fame"] = float(player.get("fame", 0.0)) + fame * 0.5
			(late["flags"] as Dictionary)["local_wins"] = int((late["flags"] as Dictionary).get("local_wins", 0)) + 1
			msgs.append("You win the %s. People begin to learn your name." % def["text"])
			_school_rep_add(String(student["inst"]), 2.0 + fame * 0.2)
			var soc := _soc()
			if soc != null:
				soc.add_rumour("duel_won", int(_insts[String(student["inst"])]["sid"]), 0.5 + fame / 20.0)
			var sm := _scouts_scenario(ctx)
			if sm != "":
				msgs.append(sm)
		if beaten != "" and wins >= 1:
			_consider_rival(beaten, "defeated")
		if r.randf() < 0.12:
			student["injured_until"] = _day + 5
			msgs.append("You take a bad knock in the bouts.")
		return {"ok": true, "placing": placing, "wins": wins, "fame": snappedf(fame, 0.1), "log": blog, "messages": msgs}
	return {"ok": false, "reason": "No such tournament."}


func _scouts_scenario(ctx: Dictionary) -> String:
	var life: Variant = ctx.get("life")
	if life == null or not (life is Object):
		return ""
	var sc: Variant = (life as Object).get("scouts")
	if sc == null or not (sc is Object) or not (sc as Object).has_method("on_scenario"):
		return ""
	var prof := {"id": 0, "name": "You", "age": int(player["age"]), "titles": [], "feats": [], "reputation": clampf(float(student.get("fame", 0.0)), 0.0, 100.0)}
	var e: Variant = (sc as Object).call("on_scenario", prof, "tournament", _day)
	if e is Dictionary and not (e as Dictionary).is_empty():
		return "Someone in the crowd asks to speak with you after your bout."
	return ""


func pending_exercise() -> Dictionary:
	return exercise.duplicate(true)


func _schedule_exercise(out: Array[String]) -> void:
	if student.is_empty() or String(student["status"]) != "enrolled" or not exercise.is_empty():
		return
	if _day <= 0 or _day % 30 != 12:
		return
	var r := _rng("exercise", _day, String(student["cohort"]))
	var kinds := EXERCISES.keys()
	var kind: String = kinds[r.randi() % kinds.size()]
	var danger := float(EXERCISES[kind]["danger"])
	if _at_war:
		danger += 0.1
	exercise = {"id": _new_id("fx"), "kind": kind, "text": String(EXERCISES[kind]["text"]), "danger": snappedf(danger, 0.01), "day": _day, "close": _day + 3,
		"choices": ["lead", "scout_ahead", "stay_with_group", "withdraw"]}
	out.append("The school is sending your group on %s." % exercise["text"])


## Resolve the pending exercise. It can go wrong: injuries, deaths, and a rescue that is left to you.
func resolve_exercise(choice := "stay_with_group") -> Dictionary:
	if exercise.is_empty() or student.is_empty():
		return {"ok": false, "reason": "No exercise pending."}
	var ex: Dictionary = exercise
	exercise = {}
	if choice == "withdraw":
		_mark_skip({"id": "exercise", "kind": "lesson", "dim": ""})
		return {"ok": true, "outcome": "withdrew", "messages": ["You stay behind. Your absence is noted."]}
	var r := _rng("exres", int(ex["day"]), String(ex["id"]))
	var teacher_q := 0.0
	for t: Dictionary in student["teachers"]:
		teacher_q = maxf(teacher_q, float(t["quality"]))
	var prep := (_cat_score(student["perf"], 0.0, "overall") / 100.0) * 0.4 + teacher_q * 0.3
	var risk := float(ex["danger"]) * (1.15 - prep) * (1.25 if choice == "lead" else (0.85 if choice == "stay_with_group" else 1.05))
	var roll := r.randf()
	var outcome := "clean"
	var msgs: Array[String] = []
	var ms := _members()
	var effects := {}
	if roll < risk * 0.35:
		outcome = "disaster"
		var lost := ""
		if not ms.is_empty():
			var m: Dictionary = _member(String(ms[r.randi() % ms.size()]["id"]))
			if r.randf() < 0.55:
				m["status"] = "dead"
				m["career"] = {"status": "dead"}
				lost = "%s did not come back." % m["name"]
			else:
				m["status"] = "injured"
				lost = "%s is carried home with terrible wounds." % m["name"]
		student["injured_until"] = _day + 12
		_school_rep_add(String(student["inst"]), -3.0)
		msgs.append("The exercise goes disastrously wrong. %s" % lost)
		var soc := _soc()
		if soc != null:
			soc.learn("lead:exercise_disaster_%s" % String(ex["id"]), "There was a disaster on a field exercise. Not everything was reported truthfully.")
		effects = {"courage": 2.0 if choice != "withdraw" else 0.0, "combat": 1.0}
	elif roll < risk:
		outcome = "complications"
		student["injured_until"] = _day + 3
		msgs.append("Things go badly for a while, but the group brings itself home.")
		effects = {"practical": 1.2, "courage": 1.0}
	else:
		msgs.append("The exercise goes to plan.")
		effects = {"practical": 0.8, "leadership": 0.6 if choice == "lead" else 0.2}
	_apply_effects(effects)
	if choice == "lead" and outcome != "disaster":
		student["contribution"] = float(student["contribution"]) + 1.5
	return {"ok": true, "outcome": outcome, "messages": msgs}


# ---------------------------------------------------------------- graduation, dropping out, reputation (C§30-31, C§45)

func graduation_ready() -> bool:
	if student.is_empty() or String(student["status"]) != "enrolled":
		return false
	var inst: Dictionary = _insts[String(student["inst"])]
	return _day - int(student["since"]) >= int(inst["years"]) * YEAR_DAYS


func graduate(force := false) -> Dictionary:
	if student.is_empty() or not (String(student["status"]) in ["enrolled", "suspended"]):
		return {"ok": false, "reason": "You are not a student."}
	if not force and not graduation_ready():
		return {"ok": false, "reason": "You have not finished your years."}
	var inst: Dictionary = _insts[String(student["inst"])]
	student["status"] = "graduated"
	_school_rep_add(String(inst["id"]), 1.5 + float(inst["prestige"]) * 2.0)
	grad_offers = _make_offers(inst)
	if _has_active_sponsor():
		for s: Dictionary in sponsors_list:
			if String(s["status"]) == "active":
				s["status"] = "graduated"
	var msgs: Array[String] = ["You graduate from %s. Organisations begin to recruit you; you are never required to accept." % inst["name"]]
	_log("Graduated from %s." % inst["name"])
	return {"ok": true, "offers": grad_offers.size(), "messages": msgs}


func _make_offers(inst: Dictionary) -> Array:
	var def: Dictionary = _def(inst)
	var out: Array = []
	var score := _cat_score(student["perf"], float(student["contribution"]), "overall")
	var r := _rng("offers", _day, String(student["cohort"]))
	for org: String in def["orgs"]:
		var p := 0.25 + score / 160.0 + float(student["fame"]) / 80.0 + float(inst["prestige"]) * 0.3
		if org == "army" and _at_war:
			p += 0.3
		if org == "church" and bool(inst["church_funded"]):
			p += 0.3
		if r.randf() < clampf(p, 0.1, 0.95):
			var g: Dictionary = GRAD_ORGS[org]
			out.append({"id": _new_id("go"), "org": org, "role": String(g["role"]), "wage": int(round(float(g["wage"]) * (0.8 + score / 100.0))),
				"sid": int(inst["sid"]), "expires": _day + 60, "status": "open"})
	return out


func graduation_offers() -> Array:
	return grad_offers.filter(func(o: Dictionary) -> bool: return String(o["status"]) == "open")


func accept_graduation_offer(oid: String) -> Dictionary:
	for o: Dictionary in grad_offers:
		if String(o["id"]) == oid and String(o["status"]) == "open" and _day <= int(o["expires"]):
			o["status"] = "accepted"
			return {"ok": true, "offer": o.duplicate(true), "reason": "You accept the post of %s." % o["role"]}
	return {"ok": false, "reason": "That offer is gone."}


func refuse_graduation_offer(oid: String) -> bool:
	for o: Dictionary in grad_offers:
		if String(o["id"]) == oid and String(o["status"]) == "open":
			o["status"] = "refused"
			return true
	return false


## C§30: you can graduate and become a farmer if you want.
func refuse_all_offers() -> String:
	for o: Dictionary in grad_offers:
		if String(o["status"]) == "open":
			o["status"] = "refused"
	return "You turn down every offer. Your education and your network are yours to keep."


func drop_out(reason := "family_needs") -> Dictionary:
	if not is_student():
		return {"ok": false, "reason": "You are not a student."}
	var retained := (student["perf"] as Dictionary).duplicate()
	student["status"] = "dropped"
	student["drop_reason"] = reason
	_school_rep_add(String(student["inst"]), -1.0 if reason != "hate_institution" else -3.0)
	for s: Dictionary in sponsors_list:
		if String(s["status"]) == "active":
			s["status"] = "withdrawn"
	_log("Left school early: %s." % reason)
	var r := {"ok": true, "retained": retained, "reason": "The knowledge you gained stays with you. You simply continue your life differently.",
		"arrears": student["arrears"]}
	_end_student_state()
	return r


func _end_student_state() -> void:
	_interrupt = {}
	exercise = {}
	student["club"] = ""


## Household hook: a raid took the player far away. The plan for school lapses.
func on_displaced(_loc: int) -> void:
	player["on_campus"] = false
	if is_student() and String(student["status"]) == "enrolled":
		student["status"] = "on_leave"
		student["leave_until"] = 999999
	if String(season.get("status", "")) == "open":
		season["status"] = "closed"
		late["overlooked"] = true
	_log("Taken far from home; school is out of reach.")


func on_returned() -> void:
	player["on_campus"] = true
	if not student.is_empty() and String(student["status"]) == "on_leave" and int(student.get("leave_until", 0)) >= 999999:
		student["status"] = "enrolled"
		student["leave_until"] = _day


func take_leave(days: int) -> bool:
	if not is_student() or not bool(student["privileges"]):
		return false
	student["status"] = "on_leave"
	student["leave_until"] = _day + days
	return true


func return_to_campus() -> bool:
	if not student.is_empty() and String(student["status"]) == "on_leave":
		student["status"] = "enrolled"
		return true
	return false


func _school_rep_add(inst_id: String, d: float) -> void:
	school_rep[inst_id] = clampf(float(school_rep.get(inst_id, 0.0)) + d, -50.0, 100.0)
	var soc := _soc()
	if soc != null:
		soc.add_rep("school:%s" % inst_id, d, "school")


## CIV-B hook (notables.gd): reputation and staff drift of a school. `staff` (0.5..1.0) scales newly generated teacher quality.
func adjust_school(inst_id: String, rep_delta: float, staff_delta := 0.0) -> void:
	_ensure()
	if not _insts.has(inst_id):
		return
	_school_rep_add(inst_id, rep_delta)
	var inst: Dictionary = _insts[inst_id]
	inst["staff"] = snappedf(clampf(float(inst.get("staff", 1.0)) + staff_delta, 0.5, 1.0), 0.001)


func school_reputation(inst_id := "") -> float:
	if inst_id == "" and not student.is_empty():
		inst_id = String(student["inst"])
	return float(school_rep.get(inst_id, 0.0))


## C§45: how a person tied to `viewer` (school id, "church", "crown") sees your alma mater.
func reception(viewer := "") -> Dictionary:
	if student.is_empty():
		return {"modifier": 0.0, "text": "You have no school behind you."}
	_ensure()
	var inst: Dictionary = _insts[String(student["inst"])]
	var mod := float(inst["prestige"]) * 0.5 + school_reputation() / 100.0
	var text := "They know %s." % inst["name"]
	if _insts.has(viewer):
		if String(_insts[viewer]["id"]) == String(inst["id"]):
			mod += 0.4
			text = "Old school ties."
		elif String(_insts[viewer]["rival"]) == String(inst["id"]) or String(inst["rival"]) == viewer:
			mod -= 0.6
			text = "Their school and yours are rivals."
		mod -= ideology_clash(String(inst["id"]), viewer)
	elif viewer == "church":
		mod += (0.3 if bool(inst["church_funded"]) else -0.15) * (0.5 + _church())
	return {"modifier": snappedf(clampf(mod, -1.0, 1.5), 0.01), "text": text}


func church_loyalty() -> float:
	return float(student.get("church_loyalty", 0.0)) if not student.is_empty() else 0.0


# ---------------------------------------------------------------- classmates' careers (C§16, C§49)

func _assign_paths(co: Dictionary) -> void:
	var inst: Dictionary = _insts.get(String(co["inst"]), {})
	if inst.is_empty():
		return
	var careers: Dictionary = _def(inst)["careers"]
	for m: Dictionary in co["members"]:
		if String(m["status"]) in ["dead"]:
			continue
		var r := _rng("path", 0, String(m["id"]))
		var w := {}
		var tot := 0.0
		for c: String in careers:
			var x := float(careers[c])
			var p: Dictionary = m["pers"]
			if c == "criminal":
				x *= 0.4 + (1.0 - float(p["honor"])) * 1.4
			if c == "noble" and int(m["class"]) < 3:
				x = 0.0
			if c in ["politician", "merchant"] and int(m["class"]) >= 2:
				x *= 1.5
			if c == "farmer":
				x *= 0.5
			w[c] = x
			tot += x
		if int(m["class"]) >= 4 and not w.has("noble"):
			w["noble"] = 0.4
			tot += 0.4
		var roll := r.randf() * tot
		var path := "farmer"
		for c: String in w:
			roll -= float(w[c])
			if roll <= 0.0:
				path = c
				break
		if float(m["perf"]["combat"]) + float(m["perf"]["theory"]) < 40.0 and r.randf() < 0.4:
			path = "farmer"
		m["status"] = "graduate"
		m["career"] = {"path": path, "rank": 0, "merit": 0.0, "status": "active", "sid": int(m["sid"])}


func _career_advance(m: Dictionary, weeks: float, r: RandomNumberGenerator) -> void:
	var c: Dictionary = m["career"]
	if String(c.get("status", "")) != "active":
		return
	var p: Dictionary = m["pers"]
	var mean := (float(m["perf"]["combat"]) + float(m["perf"]["theory"]) + float(m["perf"]["practical"]) + float(m["perf"]["leadership"])) / 4.0
	var rate := 0.03 + float(p["ambition"]) * 0.03 + mean / 3000.0 + (0.01 if int(m["class"]) >= 2 else 0.0)
	c["merit"] = float(c["merit"]) + rate * weeks * (0.7 + r.randf() * 0.6)
	var path: String = String(c["path"])
	var ladder: Array = CAREERS[path]
	var rk := int(c["rank"])
	while rk < ladder.size() - 1 and float(c["merit"]) >= RANK_MERIT[rk]:
		rk += 1
	c["rank"] = rk
	var pd := 0.0004 + (0.002 if (_at_war and path == "soldier") else 0.0) + (0.0012 if path in ["criminal", "hunter", "rift_explorer"] else 0.0)
	if r.randf() < 1.0 - pow(1.0 - pd, weeks):
		c["status"] = "dead"
		m["status"] = "dead"
		return
	if rk <= 1 and r.randf() < 1.0 - pow(1.0 - 0.004, weeks):
		var alt: Array = ["merchant", "criminal", "farmer", "guild"]
		var np: String = alt[r.randi() % alt.size()]
		if np == "criminal" and float(p["honor"]) > 0.7:
			np = "guild"
		c["path"] = np
		c["merit"] = float(c["merit"]) * 0.4
		c["rank"] = 0


func _careers_week(weeks: float) -> void:
	var soc := _soc()
	for cid: String in cohorts:
		var co: Dictionary = cohorts[cid]
		if not bool(co["graduated"]):
			if _day - int(co["start_day"]) >= int(co["years"]) * YEAR_DAYS:
				co["graduated"] = true
				_assign_paths(co)
			continue
		var i := 0
		for m: Dictionary in co["members"]:
			if String(m["status"]) == "graduate":
				var r := _rng("career", _day + i, String(m["id"]))
				_career_advance(m, weeks, r)
				if soc != null and not bool(m["announced"]) and String(m["career"].get("status", "")) == "active" and int(m["career"].get("rank", 0)) >= 3:
					m["announced"] = true
					var ladder: Array = CAREERS[String(m["career"]["path"])]
					soc.learn("contact:classmate_%s" % String(m["id"]), "%s, who studied with you, is now %s." % [m["name"], ladder[int(m["career"]["rank"])]])
			i += 1


## Classmates as they are now (after graduation their careers run on their own).
func alumni(min_rank := 0) -> Array:
	var out: Array = []
	for cid: String in cohorts:
		for m: Dictionary in cohorts[cid]["members"]:
			var c: Dictionary = m.get("career", {})
			if c.is_empty() or String(c.get("status", "")) != "active" or int(c.get("rank", 0)) < min_rank:
				continue
			var ladder: Array = CAREERS[String(c["path"])]
			out.append({"id": m["id"], "name": m["name"], "path": c["path"], "rank": int(c["rank"]), "title": ladder[int(c["rank"])], "class": m["class"], "affinity": m["affinity"]})
	return out


func find_contact(path: String, min_rank := 0) -> Dictionary:
	var best := {}
	for a: Dictionary in alumni(min_rank):
		if String(a["path"]) == path and (best.is_empty() or int(a["rank"]) > int(best["rank"])):
			best = a
	return best


# ---------------------------------------------------------------- combat training for everyone (ACADEMY_PLAN "Everyone learns to fight")

const TRAINING := {
	"drill_yard": {"label": "Village drill yard", "cost": 0, "gain": 0.30, "quality": 0.8, "tags": ["sparred"], "min_age": 7},
	"guard_sparring": {"label": "Sparring with the guards", "cost": 2, "gain": 0.45, "quality": 1.0, "tags": ["sparred", "trained_sword"], "min_age": 9},
	"hunter": {"label": "Following the hunters", "cost": 0, "gain": 0.28, "quality": 0.7, "tags": ["hunted"], "min_age": 8},
	"self_taught": {"label": "Practising on your own", "cost": 0, "gain": 0.16, "quality": 0.5, "tags": ["trained_sword"], "min_age": 5},
	"academy_arena": {"label": "The academy training fields", "cost": 0, "gain": 0.6, "quality": 1.2, "tags": ["sparred"], "min_age": 9},
}


## Combat is never locked behind a career: this list is never empty and self_taught is always available.
func training_options(ctx := {}) -> Array:
	var age := int(ctx.get("age", player["age"]))   # live age from the caller: the daily sync can lag a birthday
	var sid := int(player.get("sid", player.get("home_sid", 0)))
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2 or pp is Vector3:
		var p2: Vector2 = Vector2(pp.x, pp.z) if pp is Vector3 else pp
		var n := _nearest(p2)
		if n >= 0:
			sid = n
	var kind := _skind(sid)
	var soc := _soc()
	var wanted := soc != null and soc.has_method("bounty") and int(soc.call("bounty", sid)) > 0
	var war := bool(ctx.get("at_war", _at_war))
	var out: Array = []
	for id: String in TRAINING:
		var def: Dictionary = TRAINING[id]
		var ok := age >= int(def["min_age"])
		var why := "Too young." if not ok else ""
		var quality := float(def["quality"])
		var where := _sname(sid)
		match id:
			"drill_yard":
				if war:
					quality += 0.2
			"guard_sparring":
				if wanted:
					ok = false
					why = "The guards know your face from the wanted lists."
				elif kind == "village" and not war:
					quality -= 0.2
			"hunter":
				if kind == "castle":
					ok = false
					why = "There are no hunters to follow inside a castle town."
			"academy_arena":
				var can := is_student() and String(student["status"]) == "enrolled"
				ok = ok and can
				why = "" if ok else "You are not a student on campus."
				if not can:
					continue
		out.append({"id": id, "label": def["label"], "where": where, "cost": int(def["cost"]), "available": ok, "reason": why,
			"quality": snappedf(quality, 0.01), "gain": {"combat": snappedf(float(def["gain"]) * quality, 0.01)}})
	return out


func train(option_id: String, hours := 2, ctx := {}) -> Dictionary:
	var opt := {}
	for o: Dictionary in training_options(ctx):
		if String(o["id"]) == option_id:
			opt = o
	if opt.is_empty():
		return {"ok": false, "reason": "No such training."}
	if not bool(opt["available"]):
		return {"ok": false, "reason": String(opt["reason"])}
	var h := clampi(hours, 1, 8)
	var cost := int(opt["cost"]) * h
	if cost > _gold():
		return {"ok": false, "reason": "You cannot afford it."}
	pending_gold -= cost
	var xp := float(combat_training["xp"])
	var g := float(opt["gain"]["combat"]) * h / (1.0 + xp / 300.0)
	combat_training["xp"] = xp + g * 10.0
	combat_training["sessions"] = int(combat_training["sessions"]) + 1
	combat_training["last_day"] = _day
	(combat_training["by"] as Dictionary)[option_id] = int((combat_training["by"] as Dictionary).get(option_id, 0)) + 1
	_gain("combat", g)
	var life: Variant = ctx.get("life")
	if life != null and life is Object:
		var t: Variant = (life as Object).get("tendencies")
		if t != null and t is Object and (t as Object).has_method("record"):
			for tag: String in TRAINING[option_id]["tags"]:
				(t as Object).call("record", tag, float(h) * 0.5)
	if not student.is_empty() and String(student["status"]) == "enrolled":
		student["perf"]["combat"] = minf(100.0, float(student["perf"]["combat"]) + g * 0.6)
	return {"ok": true, "gain": {"combat": snappedf(g, 0.001)}, "reason": ""}


## Real ability 0..100: own practice plus school and stat.
func fighting_ability() -> float:
	var a := float(player.get("combat", 0.0)) + float(combat_training["xp"]) * 0.5
	if not student.is_empty():
		a = maxf(a, float(student["perf"]["combat"]))
	return clampf(a, 0.0, 100.0)


## What other people believe: real ability capped by how much of it they have seen.
func known_ability(sid := -1) -> float:
	var soc := _soc()
	var seen := 12.0 + float(student.get("fame", 0.0)) * 1.2 + float(player.get("fame", 0.0))
	if soc != null and soc.has_method("fame_at"):
		seen += float(soc.call("fame_at", sid if sid >= 0 else int(player.get("sid", 0)))) * 0.8
	seen += minf(20.0, float(combat_training["sessions"]) * 1.5)
	return snappedf(minf(fighting_ability(), seen), 0.1)


# ---------------------------------------------------------------- ticks

func tick_hour(hour: int, ctx: Dictionary) -> Array:
	var out: Array[String] = []
	_hour = hour
	if student.is_empty() or String(student["status"]) != "enrolled" or not bool(player.get("on_campus", true)):
		if not student.is_empty() and String(student["status"]) == "enrolled" and not bool(player.get("on_campus", true)):
			_sync(ctx)
			var b0 := block_at(hour)
			if not b0.is_empty() and String(b0["kind"]) in ATTEND_KINDS and not _skipped.has(String(b0["id"])):
				_mark_skip(b0)
		return out
	var b := block_at(hour)
	if b.is_empty():
		return out
	if not _interrupt.is_empty() and ((hour - int(_interrupt["hour"]) + 24) % 24 >= INTERRUPT_TIMEOUT_H or int(_interrupt["day"]) != _day):
		resolve_interrupt("")
	if not (String(b["kind"]) in ATTEND_KINDS) or _skipped.has(String(b["id"])) or int(student["detention_days"]) > 0:
		if String(b["kind"]) in ["evening", "free"] and _interrupt.is_empty():
			_roll_interrupt(hour, b, out)
		return out
	_attend_hour(b)
	if _interrupt.is_empty():
		_roll_interrupt(hour, b, out)
	return out


func _attend_hour(b: Dictionary) -> void:
	var inst: Dictionary = _insts[String(student["inst"])]
	var focus: Dictionary = _def(inst)["focus"]
	var perf: Dictionary = student["perf"]
	var dim: String = String(b["dim"])
	student["attended_h"] = int(student["attended_h"]) + 1
	if dim == "":
		return
	var tq := 0.0
	for t: Dictionary in student["teachers"]:
		if String(t["subject"]) == dim:
			tq = maxf(tq, float(t["quality"]))
	tq = maxf(tq, 0.5)
	var mult := float(focus[dim]) * (0.5 + tq * 0.6)
	if not (student["mentor"] as Dictionary).is_empty():
		mult *= 1.6
	if String(student["club"]) != "" and CLUBS[String(student["club"])]["dim"] == dim:
		mult *= 1.15
	perf[dim] = minf(100.0, float(perf[dim]) + ATTEND_GAIN * mult * (1.0 - float(perf[dim]) / 130.0))


func tick_day(day: int, ctx: Dictionary) -> Array:
	_ensure()
	_sync(ctx)
	_day = day
	var out: Array[String] = []
	_maybe_start_season(day, ctx, out)
	if String(season.get("status", "")) == "open":
		for s: Dictionary in season["scouts"]:
			if day >= int(s["arrive"]) and day <= int(s["leave"]) and not bool(s["arrived_told"]):
				s["arrived_told"] = true
				out.append("%s, a %s from %s, has arrived in %s and is testing children." % [s["name"], String(s["title"]).to_lower(), _insts[String(s["inst"])]["name"], _sname(int(season["sid"]))])
		if day > int(season["end_day"]):
			_close_season(out)
	_skipped.clear()
	if not student.is_empty():
		_student_day(day, out)
	for o: Dictionary in grad_offers:
		if String(o["status"]) == "open" and day > int(o["expires"]):
			o["status"] = "expired"
	for t: Dictionary in tournaments_list:
		if String(t["status"]) == "open" and day > int(t["close"]):
			t["status"] = "missed"
	if not exercise.is_empty() and day > int(exercise["close"]):
		out.append("You did not join the field exercise.")
		resolve_exercise("withdraw")
	while tournaments_list.size() > 12:
		tournaments_list.pop_front()
	for sp: Dictionary in sponsors_list:
		if String(sp["status"]) == "offered" and day > int(sp["since"]) + 30:
			sp["status"] = "expired"
	return out


func _student_day(day: int, out: Array[String]) -> void:
	var st := String(student["status"])
	if st in ["expelled", "graduated", "dropped"]:
		return
	if int(student["detention_days"]) > 0:
		student["detention_days"] = int(student["detention_days"]) - 1
	if st == "suspended" and int(student["suspended_until"]) >= 0 and day >= int(student["suspended_until"]) and (float(student["arrears"]) <= 0.5 or int(student["stage"]) >= 4):
		student["status"] = "enrolled"
		student["stage"] = 3
		student["truancy"] = LADDER_AT[3]
		student["suspended_until"] = -1
		out.append("Your suspension ends. You are on notice.")
	if st == "on_leave" and day >= int(student.get("leave_until", 0)):
		student["status"] = "enrolled"
		out.append("Your leave is over.")
	_update_stage(out)
	if String(student["status"]) == "expelled":
		return
	# The outside world does not stop (C§44): the home village can be hit while you study.
	if hub != null and day % 5 == 0:
		var sm: RefCounted = hub.mod("settlements")
		if sm != null and sm.has_method("emergencies"):
			for e: Dictionary in sm.call("emergencies", int(player["home_sid"])):
				if String(e.get("kind", "")) in ["raid", "plague", "famine"] and not bool(student.get("home_news_" + String(e["kind"]), false)):
					student["home_news_" + String(e["kind"])] = true
					out.append("A letter reaches you: %s in %s. You can go home if you want to." % [String(e["kind"]), _sname(int(player["home_sid"]))])
	if int(student["price_index"]) < 3 and day % 30 == 0:
		student["price_index"] = snappedf(float(student["price_index"]) * (1.012 if not _at_war else 1.03), 0.001)
	if graduation_ready():
		out.append("You have completed your years. The graduation ceremony awaits.")
	_schedule_tournaments(out)
	_schedule_exercise(out)
	var inst: Dictionary = _insts[String(student["inst"])]
	if bool(inst["church_funded"]) and String(student["status"]) == "enrolled":
		student["church_loyalty"] = clampf(float(student["church_loyalty"]) + 0.004, 0.0, 1.0)


func tick_week(_week: int, ctx: Dictionary) -> Array:
	_ensure()
	_sync(ctx)
	var out: Array[String] = []
	if not student.is_empty() and String(student["status"]) in ["enrolled", "suspended", "on_leave"]:
		_charge_week(1.0, out)
		student["truancy"] = maxf(0.0, float(student["truancy"]) - 1.5)
		if String(student["status"]) == "enrolled" and int(student["stage"]) > 0 and float(student["truancy"]) < LADDER_AT[int(student["stage"])] - 3.0:
			student["stage"] = int(student["stage"]) - 1
			if int(student["stage"]) < 3:
				student["privileges"] = true
		_weekly_club()
		_recruiter_watch(out)
		_sponsor_week(out)
		_mentor_week(out)
		_rival_week(out)
		_teacher_regard_week()
	_careers_week(1.0)
	return out


func _weekly_club() -> void:
	if student.is_empty() or String(student["club"]) == "" or not bool(student["privileges"]):
		return
	var dim: String = String(CLUBS[String(student["club"])]["dim"])
	student["perf"][dim] = minf(100.0, float(student["perf"][dim]) + 0.25)
	for m: Dictionary in _members():
		if String(m["club"]) == String(student["club"]):
			m["familiarity"] = clampf(float(m["familiarity"]) + 1.0, 0.0, 100.0)


func _teacher_regard_week() -> void:
	for t: Dictionary in student["teachers"]:
		var v: float = float(student["perf"][String(t["subject"])])
		t["regard"] = clampf(float(t["regard"]) + (v - 35.0) / 40.0 - float(student["truancy"]) * 0.05, -20.0, 30.0)


## Sleep/travel/load: statistical resolution. O(cohort + institutions), never O(days * entities).
func catch_up(days: int, ctx: Dictionary) -> Array:
	_ensure()
	_sync(ctx)
	var out: Array[String] = []
	if days < 1:
		return out
	var day := _day + days
	_day = day
	_maybe_start_season(day, ctx, out)
	if String(season.get("status", "")) == "open":
		if day > int(season["end_day"]):
			_close_season(out)
	if not student.is_empty() and String(student["status"]) in ["enrolled", "suspended", "on_leave"]:
		var weeks := float(days) / 7.0
		var frac := clampf(1.0 - float(student["truancy"]) / 25.0, 0.3, 1.0)
		if String(student["status"]) == "enrolled":
			var inst: Dictionary = _insts[String(student["inst"])]
			var focus: Dictionary = _def(inst)["focus"]
			for b: Dictionary in BLOCKS:
				if String(b["dim"]) != "" and String(b["kind"]) in ATTEND_KINDS:
					var d: String = String(b["dim"])
					var hrs := float(int(b["to"]) - int(b["from"]))
					var g := ATTEND_GAIN * float(focus[d]) * 0.75 * hrs * float(days) * frac
					var cur: float = float(student["perf"][d])
					student["perf"][d] = minf(100.0, cur + g * (1.0 - cur / 130.0) * 0.6)
		_charge_week(weeks, out)
		student["truancy"] = maxf(0.0, float(student["truancy"]) - 1.5 * weeks)
		student["stage"] = mini(int(student["stage"]), 1)
		if String(student["status"]) == "suspended" and float(student["arrears"]) <= 0.5:
			student["status"] = "enrolled"
		if String(student["status"]) == "on_leave":
			student["status"] = "enrolled"
		_interrupt = {}
		if not exercise.is_empty():
			resolve_exercise("withdraw")
		for t: Dictionary in tournaments_list:
			if String(t["status"]) == "open":
				t["status"] = "missed"
		if graduation_ready():
			out.append("You have completed your years at %s." % _insts[String(student["inst"])]["name"])
		if bool(_insts[String(student["inst"])]["church_funded"]):
			student["church_loyalty"] = clampf(float(student["church_loyalty"]) + 0.004 * days, 0.0, 1.0)
		student["price_index"] = snappedf(float(student["price_index"]) * pow(1.012, float(days) / 30.0), 0.001)
		_sponsor_week(out)
		for rv: Dictionary in rivals_list:
			if String(rv["status"]) == "rival":
				rv["heat"] = float(rv["heat"]) * pow(0.96, weeks)
				if float(rv["heat"]) < 15.0:
					rv["status"] = "ally"
	_careers_week(float(days) / 7.0)
	for o: Dictionary in grad_offers:
		if String(o["status"]) == "open" and day > int(o["expires"]):
			o["status"] = "expired"
	if out.size() > 6:
		out.resize(6)
	return out


# ---------------------------------------------------------------- save

func serialize() -> Dictionary:
	return {"player": player.duplicate(true), "pending_gold": pending_gold, "gains": _pending_gains.duplicate(), "insts": _insts.duplicate(true), "built": _built,
		"season": season.duplicate(true), "late": late.duplicate(true), "student": student.duplicate(true), "cohorts": cohorts.duplicate(true),
		"sponsors": sponsors_list.duplicate(true), "rivals": rivals_list.duplicate(true), "tournaments": tournaments_list.duplicate(true),
		"exercise": exercise.duplicate(true), "grad_offers": grad_offers.duplicate(true), "history": history.duplicate(true),
		"school_rep": school_rep.duplicate(), "training": combat_training.duplicate(true), "interrupt": _interrupt.duplicate(true),
		"skipped": _skipped.duplicate(), "next_id": _next_id, "day": _day, "hour": _hour}


func deserialize(d: Dictionary) -> void:
	player = (d.get("player", player) as Dictionary).duplicate(true)
	pending_gold = int(d.get("pending_gold", 0))
	_pending_gains = (d.get("gains", {}) as Dictionary).duplicate()
	_insts = (d.get("insts", {}) as Dictionary).duplicate(true)
	_built = bool(d.get("built", false))
	season = (d.get("season", {}) as Dictionary).duplicate(true)
	late = (d.get("late", {"overlooked": false, "prep": 0.0, "tutor": false, "flags": {}}) as Dictionary).duplicate(true)
	student = (d.get("student", {}) as Dictionary).duplicate(true)
	cohorts = (d.get("cohorts", {}) as Dictionary).duplicate(true)
	sponsors_list = (d.get("sponsors", []) as Array).duplicate(true)
	rivals_list = (d.get("rivals", []) as Array).duplicate(true)
	tournaments_list = (d.get("tournaments", []) as Array).duplicate(true)
	exercise = (d.get("exercise", {}) as Dictionary).duplicate(true)
	grad_offers = (d.get("grad_offers", []) as Array).duplicate(true)
	history = (d.get("history", []) as Array).duplicate(true)
	school_rep = (d.get("school_rep", {}) as Dictionary).duplicate()
	combat_training = (d.get("training", combat_training) as Dictionary).duplicate(true)
	_interrupt = (d.get("interrupt", {}) as Dictionary).duplicate(true)
	_skipped = (d.get("skipped", {}) as Dictionary).duplicate()
	_next_id = int(d.get("next_id", 1))
	_day = int(d.get("day", 0))
	_hour = int(d.get("hour", 8))
