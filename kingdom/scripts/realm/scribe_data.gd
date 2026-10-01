extends RefCounted
## Static data and pure generators for the Scribe career (scripts/realm/scribe.gd).
## Everything here is a pure function of a RandomNumberGenerator and plain numbers, so tests can
## drive the mini-tasks without a hub: copying (accuracy), forgery (clues), old script
## (glyph knowledge), tax ledgers (errors noticed), secrets, exams, envoy missions.

const NAMES := ["Aldric Vane", "Brenna Hale", "Corin Dunn", "Dessa Marsh", "Edmar Crane", "Fenna Reed", "Gorm Ashby", "Hilda Stone",
	"Ivo Thorne", "Jorun Pike", "Kessa Oakes", "Lorn Nettle", "Mira Fallow", "Nils Ember", "Orla Gray", "Pell Brook"]
const HOUSES := ["House Varrick", "House Aldane", "House Corvane", "House Thessaly", "House Morrow"]
const PLACES := ["Thornfield", "Ashford", "Millbrook", "Greywater", "Highmoor", "the Salt Gate", "Ravenscar", "Dunmere"]
const GOODS := ["barley", "wool", "iron bars", "salt", "tallow", "oak planks", "cloth", "hides"]

## Document kinds for copying: each line is a template; crit lines carry a sum, a name or a date
## whose slip an inspector would notice.
const DOCS := {
	"contract": {"title": "Guild contract", "lines": [
		["{n} of {p} binds to deliver {q} {g} by day {d}.", true],
		["The price is fixed at {s} gold, half upon sealing.", true],
		["Forfeit for delay is one tenth of the sum for each week.", false],
		["Witnessed before the hall of {p}.", false],
		["Neither party may assign this bond without the other's consent.", false],
		["Borne in good faith under the law of the realm.", false]]},
	"deed": {"title": "Deed of land", "lines": [
		["Know all that {h} grants to {n} the meadow at {p}.", true],
		["To hold it for the yearly rent of {s} gold.", true],
		["The bounds run from the ash tree to the old well.", false],
		["No wood may be felled without the steward's leave.", false],
		["Sealed on day {d} in the presence of three men.", true],
		["Let none disturb this holding while the rent is paid.", false]]},
	"letter": {"title": "Steward's letter", "lines": [
		["To {n}, greetings from the steward of {p}.", true],
		["The harvest of {g} came to {q} measures.", true],
		["Send word if the road at {p} is held by wolves.", false],
		["I expect the rents by day {d}, no later.", true],
		["Keep this letter close and tell no one its contents.", false],
		["Written in haste, with respect.", false]]},
	"census": {"title": "Census roll", "lines": [
		["{n}, head of a household of {q} souls.", true],
		["Hearth of {p}, taxed {s} gold.", true],
		["One cow, no horse, a plot of {q} rods.", false],
		["Listed again on day {d}, no change.", true],
		["The family keeps no servants.", false],
		["Counted by the hand of the registrar.", false]]},
}

## Old script: glyph -> meaning. A glyph is read for free once society.knowledge has "glyph:<id>".
const GLYPHS := {
	"ashk": "ash", "vael": "stone", "orun": "oath", "thess": "king", "kirr": "dead", "mael": "water", "dran": "gate", "sul": "light",
	"varn": "blood", "eth": "seal", "korr": "keep", "ilu": "star", "nahr": "road", "tul": "under", "bael": "fire", "senn": "sleep",
	"orr": "ward", "hesh": "river", "amar": "name", "dul": "hidden",
}
## Old texts: glyph sequence, plain meaning, the knowledge fact a good reading adds, and the level it suits.
const OLD_TEXTS := [
	{"id": "warding_verse", "title": "The Warding Verse", "glyphs": ["orr", "vael", "sul", "kirr", "senn"], "meaning": "Ward-stone light, the dead sleep.", "fact": "topic:ward_verse", "fact_text": "The ward-stones hold the dead asleep by light.", "level": 0},
	{"id": "king_oath", "title": "A King's Oath", "glyphs": ["thess", "orun", "eth", "korr", "amar"], "meaning": "The king's oath, sealed, keeps the name.", "fact": "topic:kings_oath", "fact_text": "An old king sealed an oath to keep a name.", "level": 5},
	{"id": "river_gate", "title": "The Gate on the River", "glyphs": ["dran", "hesh", "mael", "tul", "nahr"], "meaning": "Gate at the river water, the road under.", "fact": "lead:river_gate", "fact_text": "A road runs under the river gate.", "level": 10},
	{"id": "hidden_star", "title": "Star-Lore", "glyphs": ["ilu", "dul", "bael", "ashk", "sul"], "meaning": "The hidden star's fire is ash and light.", "fact": "topic:star_lore", "fact_text": "The old ones named a hidden star of ash and light.", "level": 15},
	{"id": "blood_seal", "title": "The Blood Seal", "glyphs": ["varn", "eth", "dul", "tul", "vael", "kirr"], "meaning": "Blood seals the hidden under-stone dead.", "fact": "secret:blood_seal", "fact_text": "Something is sealed with blood beneath a stone.", "level": 22},
	{"id": "name_road", "title": "The Name Road", "glyphs": ["amar", "nahr", "orr", "ilu", "korr", "senn"], "meaning": "The name road is warded by stars; keep sleep.", "fact": "lead:name_road", "fact_text": "A warded road is named by the stars.", "level": 30},
]

## Secrets a registrar can find in sealed archives: kind -> {text with %s house, sev}.
const SECRETS := {
	"skim": {"text": "%s's steward has been skimming the tithe for years.", "sev": 2},
	"bastard": {"text": "The heir of %s is not the lord's own blood.", "sev": 3},
	"forged_title": {"text": "%s holds its mill by a forged deed.", "sev": 3},
	"debt": {"text": "%s owes the trading companies more than its lands are worth.", "sev": 2},
	"treason": {"text": "%s has written to an enemy court.", "sev": 4},
}

## Exams: id -> {title, pass, questions [{q, o [4], a}]}.
const EXAMS := {
	"registrar_exam": {"title": "The Registrar's Examination", "pass": 0.7, "questions": [
		{"q": "A deed names a grantor who died before its date. You...", "o": ["File it", "Refuse it and note why", "Correct the date", "Burn it"], "a": 1},
		{"q": "Two copies of a will disagree on a sum. Which governs?", "o": ["The longer", "The one sealed by the testator", "The newer copy", "The cheaper"], "a": 1},
		{"q": "A tax roll is amended. The proper way is to...", "o": ["Scrape and rewrite", "Strike through, initial and date", "Start a new roll", "Leave it"], "a": 1},
		{"q": "Who may open a sealed archive volume?", "o": ["Any clerk", "The registrar with a witness", "Anyone with coin", "A passing noble"], "a": 1},
		{"q": "A seal's wax is cracked but the impression is clean. It is...", "o": ["Forged", "Probably old but genuine", "Void", "Impossible"], "a": 1},
		{"q": "A debt is paid in part. The roll should show...", "o": ["Nothing yet", "Paid in full", "The part paid and the balance", "Only the balance"], "a": 2}]},
	"steward_exam": {"title": "The Steward's Accounts", "pass": 0.75, "questions": [
		{"q": "Rents are late and the harvest was poor. A wise steward...", "o": ["Doubles the rent", "Defers part and records it", "Evicts first", "Hides it"], "a": 1},
		{"q": "The granary holds 200 measures; 80 are seed. How much may be sold?", "o": ["200", "120", "80", "40"], "a": 1},
		{"q": "A tenant's roof falls in. Estate funds should...", "o": ["Wait for spring", "Repair it at once", "Be saved for the lord", "Go to the steward"], "a": 1},
		{"q": "The lord asks you to hide a loss. You...", "o": ["Comply", "Record it truly and tell him so", "Burn the book", "Blame the tenants"], "a": 1},
		{"q": "Which is the surest sign of a skimming bailiff?", "o": ["Fat hens", "Receipts that exceed the roll", "Late rain", "A quiet manner"], "a": 1}]},
}

const MISSIONS := {
	"open trade talks": {"trade": 6.0, "trust": 2.0, "diff": 0.3, "pay": 70},
	"sign a border pact": {"trade": 1.0, "trust": 5.0, "diff": 0.5, "pay": 110},
	"swear a mutual-aid oath": {"trade": 0.0, "trust": 8.0, "diff": 0.7, "pay": 160},
	"exchange hostages of honour": {"trade": 0.0, "trust": 10.0, "diff": 0.85, "pay": 220},
}


static func pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[r.randi() % arr.size()]


static func shuffle3(r: RandomNumberGenerator) -> Array:
	var order := [0, 1, 2]
	for a in range(2, 0, -1):
		var b := r.randi() % (a + 1)
		var t: int = order[a]
		order[a] = order[b]
		order[b] = t
	return order


# ------------------------------------------------------------------ copying

static func _fill(t: String, r: RandomNumberGenerator, house: String) -> String:
	var s := t
	s = s.replace("{n}", String(pick(r, NAMES))).replace("{p}", String(pick(r, PLACES))).replace("{g}", String(pick(r, GOODS)))
	s = s.replace("{h}", house).replace("{q}", str(r.randi_range(12, 96))).replace("{s}", str(r.randi_range(24, 880)))
	s = s.replace("{d}", str(r.randi_range(110, 940)))
	return s


## One plausible slip of the pen: a wrong digit, or a dropped, doubled or swapped letter.
static func slip(s: String, r: RandomNumberGenerator) -> String:
	var digits: Array = []
	for i in s.length():
		if s[i] >= "0" and s[i] <= "9":
			digits.append(i)
	if not digits.is_empty() and r.randf() < 0.7:
		var i2: int = int(pick(r, digits))
		var d := (int(s[i2]) + r.randi_range(1, 8)) % 10
		return s.substr(0, i2) + str(d) + s.substr(i2 + 1)
	var letters: Array = []
	for j in s.length() - 1:
		if s[j] != " " and s[j + 1] != " " and s[j] != s[j + 1] and s[j] != "." and s[j + 1] != ".":
			letters.append(j)
	if letters.is_empty():
		return s + "."
	var j2: int = int(pick(r, letters))
	match r.randi() % 3:
		0:
			return s.substr(0, j2) + s.substr(j2 + 1)
		1:
			return s.substr(0, j2 + 1) + s[j2] + s.substr(j2 + 1)
		_:
			return s.substr(0, j2) + s[j2 + 1] + s[j2] + s.substr(j2 + 2)


## {kind, title, lines [{src, crit, options [3 strings], correct}]}. `level` (mastery) lengthens it.
static func gen_copy(r: RandomNumberGenerator, level: int, kind := "") -> Dictionary:
	var kinds: Array = DOCS.keys()
	var k := kind if kind != "" else String(pick(r, kinds))
	var def: Dictionary = DOCS[k]
	var house := String(pick(r, HOUSES))
	var tpl: Array = def["lines"]
	var n := clampi(3 + level / 25, 3, tpl.size())
	var lines: Array = []
	for i in n:
		var src := _fill(String(tpl[i][0]), r, house)
		var opts: Array = [src]
		var guard := 0
		while opts.size() < 3 and guard < 20:
			guard += 1
			var w := slip(src, r)
			if not opts.has(w):
				opts.append(w)
		while opts.size() < 3:
			opts.append(src + " " + str(opts.size()))
		var order := shuffle3(r)
		var shuffled: Array = []
		var correct := 0
		for pos in 3:
			shuffled.append(opts[order[pos]])
			if order[pos] == 0:
				correct = pos
		lines.append({"src": src, "crit": bool(tpl[i][1]), "options": shuffled, "correct": correct})
	return {"kind": k, "title": String(def["title"]), "lines": lines}


## picks: option index chosen per line. steady 0..1 is the pen-steadiness reading; below 0.45 the
## pen blots line `blot_line`. Returns {quality, errors [line idx], crit_errors, blot}.
static func score_copy(doc: Dictionary, picks: Array, steady: float, blot_line := 0) -> Dictionary:
	var lines: Array = doc["lines"]
	var errors: Array = []
	var crit := 0
	var got := 0.0
	var tot := 0.0
	for i in lines.size():
		var l: Dictionary = lines[i]
		var w := 2.0 if bool(l["crit"]) else 1.0
		tot += w
		var ok := i < picks.size() and int(picks[i]) == int(l["correct"])
		if steady < 0.45 and i == clampi(blot_line, 0, lines.size() - 1):
			ok = false
		if ok:
			got += w
		else:
			errors.append(i)
			if bool(l["crit"]):
				crit += 1
	var q := (got / maxf(tot, 1.0)) * (0.85 + 0.15 * clampf(steady, 0.0, 1.0))
	return {"quality": clampf(q, 0.0, 1.0), "errors": errors, "crit_errors": crit, "blot": steady < 0.45}


# ------------------------------------------------------------------ forgery

const SEAL_MOTIFS := ["crowned stag", "three wheat-sheaves", "tower and key", "wolf's head", "ash tree", "twin hammers"]
const WAX := ["red wax", "green wax", "black wax", "natural wax"]
const HANDS := ["upright, tight capitals", "leaning right, long tails", "round and even, no flourish", "narrow with looped ascenders"]
const INKS := ["brown iron-gall", "faded sepia", "deep black", "greenish"]
const CHANNELS := ["seal", "hand", "date", "ink"]


static func _other(arr: Array, not_this: String, r: RandomNumberGenerator) -> String:
	var pool: Array = arr.filter(func(m: String) -> bool: return m != not_this)
	return String(pick(r, pool))


## A document with a hidden truth. flaws {channel: subtlety 0..1}; empty = genuine.
## specimen = what the archive holds for the same issuer (the comparison).
static func gen_forgery(r: RandomNumberGenerator, level: int, day: int, forged_chance := 0.55) -> Dictionary:
	var house := String(pick(r, HOUSES))
	var issuer := String(pick(r, NAMES))
	var kind := String(pick(r, ["deed", "writ of safe passage", "letter of credit", "grant of tithe"]))
	var spec := {"motif": String(pick(r, SEAL_MOTIFS)), "wax": String(pick(r, WAX)), "hand": String(pick(r, HANDS)), "ink": String(pick(r, INKS)),
		"ring_broken": day - r.randi_range(40, 160)}   # the issuer's old sealing ring went out of use on this day
	var doc_day := day - r.randi_range(2, 30)
	var flaws := {}
	if r.randf() < forged_chance:
		var n := 1 + (1 if r.randf() < 0.45 else 0) + (1 if r.randf() < 0.15 else 0)
		var chans: Array = CHANNELS.duplicate()
		for i in n:
			var c: String = chans.pop_at(r.randi() % chans.size())
			flaws[c] = snappedf(clampf(0.2 + 0.65 * r.randf() - float(level) * 0.001, 0.12, 0.9), 0.01)
	var doc := {"kind": kind, "issuer": issuer, "house": house, "day": doc_day, "specimen": spec, "flaws": flaws,
		"seal": spec["motif"], "wax": spec["wax"], "hand": spec["hand"], "ink": spec["ink"]}
	if flaws.has("seal"):
		doc["seal"] = _other(SEAL_MOTIFS, String(spec["motif"]), r)
		if r.randf() < 0.4:
			doc["wax"] = _other(WAX, String(spec["wax"]), r)
	if flaws.has("hand"):
		doc["hand"] = _other(HANDS, String(spec["hand"]), r)
	if flaws.has("ink"):
		doc["ink"] = _other(INKS, String(spec["ink"]), r)
	if flaws.has("date"):
		doc["day"] = int(spec["ring_broken"]) + r.randi_range(6, 40)   # sealed with a ring already broken
	elif r.randf() < 0.6:
		doc["day"] = int(spec["ring_broken"]) - r.randi_range(10, 80)
	# A genuine document can still look odd; this noise is why a mismatch must be weighed.
	doc["worn"] = not flaws.has("seal") and r.randf() < 0.35
	return doc


## How sharp the eye is, 0..1: mastery plus a lens (costs an hour).
static func perception(level: int, lens: bool) -> float:
	return clampf(0.3 + float(level) * 0.009 + (0.2 if lens else 0.0), 0.0, 1.0)


## What the player sees examining one channel: {channel, text, seen_flaw}.
static func examine(doc: Dictionary, channel: String, level: int, lens: bool) -> Dictionary:
	var flaws: Dictionary = doc["flaws"]
	var spec: Dictionary = doc["specimen"]
	var flawed := flaws.has(channel)
	var seen := flawed and perception(level, lens) >= float(flaws[channel])
	var text := ""
	match channel:
		"seal":
			if seen:
				text = "Seal: %s in %s. The archive specimen shows %s in %s." % [doc["seal"], doc["wax"], spec["motif"], spec["wax"]]
			else:
				var motif := String(spec["motif"]) if flawed else String(doc["seal"])
				var wax := String(spec["wax"]) if flawed else String(doc["wax"])
				text = "Seal: %s in %s. It looks like the specimen%s." % [motif, wax, ", though the wax is cracked with age" if bool(doc.get("worn", false)) else ""]
		"hand":
			if seen:
				text = "Hand: %s. The specimen is %s." % [doc["hand"], spec["hand"]]
			else:
				text = "Hand: %s. A close match to the specimen." % (spec["hand"] if flawed else doc["hand"])
		"date":
			var dd := int(doc["day"])
			var rb := int(spec["ring_broken"])
			if seen:
				text = "Dated day %d. The issuer's sealing ring was broken on day %d: this seal could not have been made after it." % [dd, rb]
			elif dd < rb:
				text = "Dated day %d, before the issuer's ring broke on day %d. Plausible." % [dd, rb]
			else:
				text = "Dated day %d. Nothing in the archive contradicts it." % dd
		"ink":
			if seen:
				text = "Ink: %s. The specimen from that year is %s." % [doc["ink"], spec["ink"]]
			else:
				text = "Ink: %s. It has the colour you would expect." % (spec["ink"] if flawed else doc["ink"])
	return {"channel": channel, "text": text, "seen_flaw": seen}


## verdict: "forged" or "genuine"; named: channels the player points at.
## Returns {quality, outcome ("caught"|"missed"|"false_alarm"|"cleared"), flaws_named, flaws}
static func judge_forgery(doc: Dictionary, verdict: String, named: Array) -> Dictionary:
	var flaws: Dictionary = doc["flaws"]
	var forged := not flaws.is_empty()
	if forged and verdict == "forged":
		var hit := 0
		for c: Variant in named:
			if flaws.has(String(c)):
				hit += 1
		var wrong := named.size() - hit
		var q := 0.7 + 0.3 * float(hit) / float(flaws.size()) - 0.1 * float(wrong)
		return {"quality": clampf(q, 0.55, 1.0), "outcome": "caught", "flaws_named": hit, "flaws": flaws.size()}
	if forged:
		return {"quality": 0.0, "outcome": "missed", "flaws_named": 0, "flaws": flaws.size()}
	if verdict == "forged":
		return {"quality": 0.15, "outcome": "false_alarm", "flaws_named": 0, "flaws": 0}
	return {"quality": 0.85, "outcome": "cleared", "flaws_named": 0, "flaws": 0}


# ------------------------------------------------------------------ old script

## Picks an old text suited to the level. Returns the OLD_TEXTS entry plus `choices` per glyph
## ({glyph, options [3 meanings], correct}).
static func gen_translation(r: RandomNumberGenerator, level: int) -> Dictionary:
	var pool: Array = []
	for t0: Dictionary in OLD_TEXTS:
		if int(t0["level"]) <= level + 3:
			pool.append(t0)
	if pool.is_empty():
		pool.append(OLD_TEXTS[0])
	var t: Dictionary = (pick(r, pool) as Dictionary).duplicate(true)
	var all_meanings: Array = GLYPHS.values()
	var choices: Array = []
	for g: String in t["glyphs"]:
		var truth := String(GLYPHS[g])
		var opts: Array = [truth]
		while opts.size() < 3:
			var m := String(pick(r, all_meanings))
			if not opts.has(m):
				opts.append(m)
		var order := shuffle3(r)
		var shuf: Array = []
		var correct := 0
		for pos in 3:
			shuf.append(opts[order[pos]])
			if order[pos] == 0:
				correct = pos
		choices.append({"glyph": g, "options": shuf, "correct": correct})
	t["choices"] = choices
	return t


## known: glyph ids already read. guesses: option index per glyph (ignored for known ones).
## Returns {quality, learned [glyph], correct, unknown, wrong}.
static func score_translation(t: Dictionary, known: Array, guesses: Array) -> Dictionary:
	var choices: Array = t["choices"]
	var right := 0.0
	var unknown := 0
	var wrong := 0
	var learned: Array = []
	for i in choices.size():
		var c: Dictionary = choices[i]
		if known.has(c["glyph"]):
			right += 1.0
			continue
		unknown += 1
		if i < guesses.size() and int(guesses[i]) == int(c["correct"]):
			right += 0.9
			learned.append(c["glyph"])
		else:
			wrong += 1
	return {"quality": clampf(right / float(maxi(choices.size(), 1)), 0.0, 1.0), "learned": learned, "unknown": unknown, "wrong": wrong,
		"correct": choices.size() - wrong}


# ------------------------------------------------------------------ tax ledgers

const TRADES := {"baker": 30, "weaver": 26, "smith": 44, "carter": 28, "innkeeper": 52, "miller": 38, "tanner": 34, "fisher": 20, "cooper": 29, "chandler": 24}


## Ledger rows: {house, trade, usual, income, due, receipt, ledger, err ("" | "slip" | "skim" | "under")}.
## greed 0..1 of the settlement's leader raises how often the collector skims.
static func gen_tax(r: RandomNumberGenerator, rate: float, greed: float, level: int) -> Dictionary:
	var trades: Array = TRADES.keys()
	var rows: Array = []
	var used: Array = []
	var n := 6
	for i in n:
		var tr := String(pick(r, trades))
		while used.has(tr):
			tr = String(pick(r, trades))
		used.append(tr)
		var usual := int(TRADES[tr])
		var income := int(round(float(usual) * r.randf_range(0.8, 1.25)))
		var due := int(round(float(income) * rate))
		rows.append({"house": "%s the %s" % [String(pick(r, NAMES)).get_slice(" ", 0), tr], "trade": tr, "usual": usual, "income": income, "due": due,
			"receipt": due, "ledger": due, "err": ""})
	var errors := clampi(1 + (1 if r.randf() < 0.4 + 0.4 * greed else 0) + (1 if level < 20 and r.randf() < 0.25 else 0), 1, 3)
	var skims := 0
	var idx: Array = range(n)
	for e in errors:
		var row: Dictionary = rows[idx.pop_at(r.randi() % idx.size())]
		var roll := r.randf()
		var kind := "skim" if roll < 0.35 + 0.5 * greed else ("slip" if roll < 0.8 else "under")
		if kind == "under":
			row["income"] = maxi(2, int(round(float(row["usual"]) * r.randf_range(0.15, 0.4))))
			row["due"] = int(round(float(row["income"]) * rate))
			row["receipt"] = row["due"]
			row["ledger"] = row["due"]
		elif kind == "skim":
			skims += 1
			row["ledger"] = maxi(0, int(row["due"]) - maxi(1, int(round(float(row["due"]) * r.randf_range(0.3, 0.6)))))
		else:
			var d := int(row["due"])
			row["ledger"] = (d + r.randi_range(1, 4) * (1 if r.randf() < 0.5 else -1)) if d > 4 else d + 3
		row["err"] = kind
	return {"rate": rate, "rows": rows, "errors": errors, "skims": skims}


## marked: row indices the player flagged. Returns {quality, found, false_flags, missed, skim_found, causes}.
static func score_tax(led: Dictionary, marked: Array) -> Dictionary:
	var rows: Array = led["rows"]
	var found := 0
	var false_flags := 0
	var skim_found := 0
	var causes: Array = []
	for i in rows.size():
		var e := String(rows[i]["err"])
		if marked.has(i):
			if e == "":
				false_flags += 1
			else:
				found += 1
				causes.append({"row": i, "err": e})
				if e == "skim":
					skim_found += 1
	var total := int(led["errors"])
	var q := (float(found) - 0.5 * float(false_flags)) / float(maxi(total, 1))
	return {"quality": clampf(q, 0.0, 1.0), "found": found, "false_flags": false_flags, "missed": total - found, "skim_found": skim_found, "causes": causes}


# ------------------------------------------------------------------ exams

static func exam_questions(exam: String, seed_value: int) -> Array:
	var def: Dictionary = EXAMS.get(exam, {})
	var out: Array = []
	if def.is_empty():
		return out
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	for q: Dictionary in def["questions"]:
		var order := [0, 1, 2, 3]
		for a in range(3, 0, -1):
			var b := r.randi() % (a + 1)
			var x: int = order[a]
			order[a] = order[b]
			order[b] = x
		var opts: Array = []
		var ans := 0
		for pos in 4:
			opts.append(q["o"][order[pos]])
			if order[pos] == int(q["a"]):
				ans = pos
		out.append({"q": q["q"], "o": opts, "a": ans})
	return out
