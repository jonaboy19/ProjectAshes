extends RefCounted
## "Where you spend the most time shapes your elements" (owner vision). Each in-game hour the player spends somewhere
## nudges the element that place is steeped in: water by rivers and lakes, fire by forges and campfires, earth up on rock
## and high ground, wind on open heights, lightning in storms, qi in deep forest. Before the Blessing it leans the roll
## (tendencies.elements is what awakening.gd weighs); after it, the same affinities keep growing.
## Pure maths in weights(); Life calls tick() from its exposure update (about once a real second).

const ELEMENTS := ["fire", "water", "wind", "earth", "lightning", "qi"]
## Affinity gained per in-game hour fully steeped in a place (tendencies.elements runs 0..1; 0.4 is neutral).
const RATE := 0.0025
## Total hours in one element that earn a message (and how it reads).
const MILESTONES := [6.0, 24.0, 72.0, 200.0]
const WORDS := {"water": "The river has seeped into you", "fire": "The fire's heat stays in your hands", "earth": "The stone feels kin to you",
	"wind": "The high winds have learned your name", "lightning": "Storms raise the hair on your arms", "qi": "The old forest breathes with you"}

var hours: Dictionary = {}   # element -> in-game hours spent steeped in it


## 0..1 strength of each element at a spot, from plain facts about it.
static func weights(shore_dist: float, water_depth: float, near_fire: bool, height: float, slope: float, forest: float,
		storm: bool, wind: float) -> Dictionary:
	var w := {}
	w["water"] = 1.0 if water_depth > 0.3 else clampf(1.0 - shore_dist / 25.0, 0.0, 1.0) * 0.8
	w["fire"] = 1.0 if near_fire else 0.0
	w["earth"] = clampf((height - 60.0) / 60.0, 0.0, 1.0) * 0.7 + clampf((slope - 0.35) / 0.4, 0.0, 1.0) * 0.5
	w["wind"] = clampf((height - 80.0) / 60.0, 0.0, 1.0) * (1.0 - forest) * clampf(wind, 0.5, 2.0) * 0.6
	w["lightning"] = 1.0 if storm else 0.0
	w["qi"] = clampf((forest - 0.5) / 0.4, 0.0, 1.0) * 0.7
	for k: String in w:
		w[k] = clampf(float(w[k]), 0.0, 1.0)
	return w


## Adds `dh` in-game hours at a place with `w` weights; nudges `tendencies` (tendencies.gd) and returns milestone lines.
func tick(dh: float, w: Dictionary, tendencies: Object) -> Array:
	var out: Array = []
	for e: String in w:
		var k := float(w[e])
		if k <= 0.05:
			continue
		var before := float(hours.get(e, 0.0))
		var after := before + dh * k
		hours[e] = after
		if tendencies != null:
			tendencies.call("nudge", e, RATE * dh * k)
		for m: float in MILESTONES:
			if before < m and after >= m:
				out.append("%s: your %s affinity grows." % [String(WORDS.get(e, e)), e])
	return out


## The element you have lingered in most ("" if none yet).
func leading() -> String:
	var best := ""
	var bh := 0.0
	for e: String in hours:
		if float(hours[e]) > bh:
			bh = float(hours[e])
			best = e
	return best


func serialize() -> Dictionary:
	return {"hours": hours.duplicate()}


func deserialize(d: Dictionary) -> void:
	hours = (d.get("hours", {}) as Dictionary).duplicate()
