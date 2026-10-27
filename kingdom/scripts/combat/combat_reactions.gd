extends RefCounted
## Hit reactions that match the blow (owner AAA bar, layer 2): direction (Front/Back/Left/Right = where the blow came from)
## x strength (small flinch / large react / stagger) x state (guarding = a block react, not a flesh hit). Clips are the
## owner's Mixamo combat set 4 (Mx4_*); their root travel is played through combat_motion.gd, so large reacts give ground
## in the hit direction. Deaths pick the fall that matches the killing blow. Pure: no scene access (tests).

const SMALL := {"Front": "Mx4_ReactSmallFront", "Back": "Mx4_ReactSmallBack", "Left": "Mx4_ReactSmallLeft", "Right": "Mx4_ReactSmallRight"}
const LARGE := {"Front": "Mx4_ReactLargeFront", "Back": "Mx4_ReactLargeBack", "Left": "Mx4_ReactLargeLeft", "Right": "Mx4_ReactLargeRight"}
const STAGGER := {"Front": ["Mx4_StaggerBigUppercut", "Mx4_ShoveReactionStanding"], "Back": ["Mx4_ReactLargeBack"],
	"Left": ["Mx4_ReactLargeLeft"], "Right": ["Mx4_ReactLargeRight"]}
const BLOCK_SMALL := "Mx_SnS_Block_2"
const BLOCK_LARGE := "Mx4_BlockReactLarge"
## A blow from the front throws the body back, from the back forward, from the left to the right side and vice versa.
const DEATH := {"Front": ["Mx4_DeathReactBackward", "Mx4_DeathFallingBack"], "Back": ["Mx4_DeathFallingForward", "Mx4_DeathFromBackOneKnee"],
	"Left": ["Mx4_DeathReactRight"], "Right": ["Mx4_DeathReactLeft"]}
const LARGE_KNOCK := 2.5       ## knockback m/s from which a flesh hit is a large react
const STAGGER_KNOCK := 4.5     ## ... and a stagger (below the ragdoll knockdown)


static func strength(knockback: float, poise_broken := false) -> String:
	if poise_broken or knockback >= STAGGER_KNOCK:
		return "stagger"
	return "large" if knockback >= LARGE_KNOCK else "small"


## The reaction clip for a hit from `side` with `knockback` (m/s). `pick` varies between alternatives.
static func react(side: String, knockback: float, guarding := false, pick := 0) -> String:
	if not SMALL.has(side):
		side = "Front"
	if guarding:
		return BLOCK_LARGE if knockback >= LARGE_KNOCK else BLOCK_SMALL
	match strength(knockback):
		"stagger":
			var a: Array = STAGGER[side]
			return String(a[absi(pick) % a.size()])
		"large":
			return String(LARGE[side])
	return String(SMALL[side])


static func death(side: String, pick := 0) -> String:
	var a: Array = DEATH.get(side, DEATH["Front"])
	return String(a[absi(pick) % a.size()])
