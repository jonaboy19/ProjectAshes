extends RefCounted
## TalkBark: a friendly one-liner floated by an NPC who thinks well of the player when the player walks near
## without talking (docs/design/FOUNDATION_PLAN.md F4). The bubble itself is villager.gd's existing _say();
## this only decides WHO may speak and WHAT, so it is rate limited three ways:
##   per person  (PERSON_GAP_MS), globally (GLOBAL_GAP_MS, shared across all villagers), and at most
##   MAX_VISIBLE bubbles on screen (NpcWorld.bubbles_shown).

const MIN_OPINION := 12          # relationships opinion needed (Friendly or better)
const RANGE := 5.5               # metres
const PERSON_GAP_MS := 240000
const GLOBAL_GAP_MS := 20000
const MAX_VISIBLE := 1
const SECONDS := 3.0

const WARM := ["Good to see you again!", "There you are! Well met.", "Always a pleasure.", "Stay safe out there, friend.",
	"Come by later, we'll talk.", "Ah, a friendly face."]
const FOND := ["My favourite traveller!", "Light of the day, there you are!", "Tell me everything later, friend!",
	"You are always welcome here."]
const FOND_OPINION := 40

static var last_global_ms := -1000000


static func reset() -> void:
	last_global_ms = -1000000


## May this villager bark now? `last_person_ms` is its own last bark.
static func eligible(opinion: int, distance: float, now_ms: int, last_person_ms: int, bubbles_shown: int) -> bool:
	if opinion < MIN_OPINION or distance > RANGE:
		return false
	if bubbles_shown >= MAX_VISIBLE:
		return false
	if now_ms - last_person_ms < PERSON_GAP_MS or now_ms - last_global_ms < GLOBAL_GAP_MS:
		return false
	return true


static func line(person: int, opinion: int, salt := 0) -> String:
	var list: Array = FOND if opinion >= FOND_OPINION else WARM
	return String(list[absi(hash(person * 7919 + salt * 131)) % list.size()])


## Records that a bark was spoken (starts the global cooldown).
static func spoke(now_ms: int) -> void:
	last_global_ms = now_ms
