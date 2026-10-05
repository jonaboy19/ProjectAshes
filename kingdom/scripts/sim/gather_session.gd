extends RefCounted
## A short gathering session for ore veins, herb patches, trees and fishing spots (3-6 taps):
##   prospect (1 tap: read the node) -> extract (1-3 taps) -> care (optional, 1 tap: cancels the NEXT hazard)
##   -> take (1 tap: collect). Pure logic, no nodes; the UI (scripts/ui/gather_panel.gd) only calls these verbs.
##
## Hazards (cave-in chip, thorns, snapped line, ...) strike an extract with a chance that FALLS with
## skill minus node level. Yield and quality come from skill, tool tier and the node's own quality (0..100).
## Patterns from docs/research/MINING_COMBAT_WORLD.md section 5, re-implemented clean-room.
##
## var s := GatherSession.new()
## s.start({"kind": "ore", "item": "iron_ore", "level": 2, "qty": 6, "quality": 50}, skill_level, tool_tier, seed)
## s.prospect(); s.extract(); s.care(); s.extract(); var res := s.take()
## res: {ok, item, count, grade (0..100), tier (0..2), xp, skill, damage, hazards:[ids], taps, consumed}

enum Phase { IDLE, PROSPECTED, EXTRACTING, DONE }

const MAX_EXTRACT := 3
const MAX_TAPS := 6
## Seconds a UI should allow at most for the whole session.
const MAX_SECONDS := 10.0

## kind -> skill, the hazard it can throw, and the verbs the UI shows.
const KINDS := {
	"ore": {"skill": "mining", "hazard": "cave_in", "extract": "Strike the vein", "care": "Brace the roof", "take": "Gather the ore"},
	"herb": {"skill": "foraging", "hazard": "thorns", "extract": "Pick carefully", "care": "Part the thorns", "take": "Bundle the herbs"},
	"tree": {"skill": "woodcutting", "hazard": "kickback", "extract": "Swing the axe", "care": "Check the lean", "take": "Gather the wood"},
	"fish": {"skill": "fishing", "hazard": "snapped_line", "extract": "Work the line", "care": "Ease the tension", "take": "Land the catch"},
}
## hazard -> {damage: base hp lost (+ node level), yield: units lost, grade: grade lost, text}.
const HAZARDS := {
	"cave_in": {"damage": 3, "yield": 1, "grade": 0, "text": "Rock chips fall from the ceiling!"},
	"thorns": {"damage": 1, "yield": 0, "grade": 12, "text": "Thorns tear at your hands!"},
	"kickback": {"damage": 2, "yield": 1, "grade": 0, "text": "The branch kicks back!"},
	"snapped_line": {"damage": 0, "yield": 1, "grade": 6, "text": "The line snaps!"},
}

var phase := Phase.IDLE
var kind := "ore"
var item := ""
var node_level := 1
var skill_level := 1
var tool_tier := 0
var node_quality := 50
## Units still in the node when the session began / now.
var node_qty := 0
var taps := 0
var extracts := 0
var care_armed := false
var care_used := false
var picked := 0
var grade_sum := 0.0
var damage := 0
var hazards: Array = []
var log_lines: Array = []
var rng := RandomNumberGenerator.new()


## node: {kind, item, level, qty (units left), quality (0..100)}. Returns false for an unusable node.
func start(node: Dictionary, p_skill_level: int, p_tool_tier := 0, seed_value := 1) -> bool:
	kind = String(node.get("kind", "ore"))
	if not KINDS.has(kind) or int(node.get("qty", 0)) <= 0 or String(node.get("item", "")) == "":
		phase = Phase.DONE
		return false
	item = String(node["item"])
	node_level = maxi(1, int(node.get("level", 1)))
	node_qty = int(node["qty"])
	node_quality = clampi(int(node.get("quality", 50)), 0, 100)
	skill_level = maxi(1, p_skill_level)
	tool_tier = maxi(0, p_tool_tier)
	taps = 0
	extracts = 0
	care_armed = false
	care_used = false
	picked = 0
	grade_sum = 0.0
	damage = 0
	hazards = []
	log_lines = []
	rng.seed = seed_value
	phase = Phase.IDLE
	return true


func skill_name() -> String:
	return String(KINDS[kind]["skill"])


## Skill minus node level (negative = the node is above you).
func delta() -> int:
	return skill_level - node_level


## Chance one extract throws the node's hazard: 40% at equal level, 7% less per level of skill advantage.
static func hazard_chance(skill: int, level: int) -> float:
	return clampf(0.40 - 0.07 * float(skill - level), 0.04, 0.70)


## Expected grade (0..100) of one extract before noise and hazards.
static func base_grade(node_q: int, skill: int, level: int, tool_t: int, prospected: bool) -> float:
	return clampf(float(node_q) * 0.6 + 25.0 + 4.0 * float(skill - level) + 6.0 * float(tool_t) + (5.0 if prospected else 0.0), 1.0, 100.0)


## 0 rough / 1 fine / 2 masterwork (same tiers as Crafting.Quality) for a grade.
static func tier_for_grade(grade: float) -> int:
	if grade >= 80.0:
		return 2
	if grade >= 35.0:
		return 1
	return 0


func taps_left() -> int:
	return MAX_TAPS - taps


func can_extract() -> bool:
	return (phase == Phase.PROSPECTED or phase == Phase.EXTRACTING) and extracts < MAX_EXTRACT \
		and picked < node_qty and taps < MAX_TAPS - 1      # leave one tap for take()


func can_care() -> bool:
	return (phase == Phase.PROSPECTED or phase == Phase.EXTRACTING) and not care_armed and not care_used and extracts < MAX_EXTRACT \
		and picked < node_qty and taps < MAX_TAPS - 2      # leave a tap for one more extract and take()


func can_take() -> bool:
	return phase == Phase.EXTRACTING and extracts > 0


## Tap 1: read the node. Returns {risk, grade, qty, hard (node above skill)}.
func prospect() -> Dictionary:
	if phase != Phase.IDLE:
		return {}
	phase = Phase.PROSPECTED
	taps += 1
	return {"risk": hazard_chance(skill_level, node_level),
		"grade": base_grade(node_quality, skill_level, node_level, tool_tier, true),
		"qty": node_qty, "hard": node_level > skill_level + 2}


## Tap: one extraction. Returns {ok, units, hazard ("" if none), cancelled (care absorbed one), damage, text}.
func extract() -> Dictionary:
	if not can_extract():
		return {"ok": false}
	taps += 1
	extracts += 1
	phase = Phase.EXTRACTING
	var out := {"ok": true, "units": 0, "hazard": "", "cancelled": false, "damage": 0, "text": ""}
	var hz := String(KINDS[kind]["hazard"])
	var units := 1
	if rng.randf() < clampf(0.10 * float(maxi(0, delta())) + 0.12 * float(tool_tier), 0.0, 0.6):
		units += 1
	var g := base_grade(node_quality, skill_level, node_level, tool_tier, true) + rng.randf_range(-5.0, 5.0)
	if rng.randf() < hazard_chance(skill_level, node_level):
		if care_armed:
			care_armed = false
			out["cancelled"] = true
			out["text"] = "Your care averts it."
		else:
			var h: Dictionary = HAZARDS[hz]
			var dmg := int(h["damage"]) + (node_level / 3 if int(h["damage"]) > 0 else 0)
			damage += dmg
			units = maxi(0, units - int(h["yield"]))
			g -= float(h["grade"])
			hazards.append(hz)
			out["hazard"] = hz
			out["damage"] = dmg
			out["text"] = String(h["text"])
	units = mini(units, node_qty - picked)
	picked += units
	grade_sum += g * float(units)
	out["units"] = units
	log_lines.append(out)
	return out


## Optional tap: the next hazard this session is cancelled. One use per session.
func care() -> bool:
	if not can_care():
		return false
	taps += 1
	care_armed = true
	care_used = true
	return true


## Final tap: collect. Safe to call from any started phase (before any extract it yields nothing).
func take() -> Dictionary:
	if phase == Phase.DONE:
		return {"ok": false, "count": 0}
	if phase != Phase.EXTRACTING:
		phase = Phase.DONE
		return {"ok": false, "count": 0, "item": item, "damage": 0}
	taps += 1
	phase = Phase.DONE
	var grade := (grade_sum / float(picked)) if picked > 0 else 0.0
	grade = clampf(grade, 0.0, 100.0)
	var xp := 2 + node_level + extracts + (1 if picked > 0 else 0)
	return {"ok": picked > 0, "item": item, "count": picked, "grade": int(round(grade)),
		"tier": tier_for_grade(grade), "xp": xp, "skill": skill_name(), "damage": damage,
		"hazards": hazards.duplicate(), "taps": taps, "consumed": picked, "care_wasted": care_armed}


## Whole session with a fixed plan, for tests, NPC gatherers and the "quick gather" button:
## prospect, care once when `careful`, extract `n` times, take.
func run(n := MAX_EXTRACT, careful := false) -> Dictionary:
	prospect()
	if careful and can_extract():
		extract()
		care()
	for i in n:
		if not can_extract():
			break
		extract()
	return take()
