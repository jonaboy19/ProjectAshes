extends RefCounted
## Legal status of ground (Living World §6, LW-5.1). Pure static rules over WorldGen plus an optional list of zones.
##
## Owning the land, having permission to build on it and the right to govern it are three separate things:
##   own    the title is yours (bought, granted or staked by occupation)
##   build  nobody with authority will stop you raising a structure
##   govern you make the local law (only recognition by a realm gives it, see founding.gd petition stub)
## `rights_of(status)` is what a stranger holds on that kind of ground; founding.gd adds what the founder has earned
## (lease, grant, purchase, occupation, submission, recognition).
##
##   LandLaw.status_at(Vector2(x, z), zones, land_mod) -> {status, holder, near, dist, words}
##   LandLaw.rights_of("frontier") -> {own, build, govern, auth, titles}
##
## Zones are [x, z, radius, status, holder] rows written by founding.gd when ground is leased, granted, disputed ...; the newest
## zone that contains the point wins. Cost: one pass over the settlements, no allocation worth measuring; never per frame.

const Hv := preload("res://scripts/world/hidden_valley.gd")

const STATUSES := ["private", "leased", "granted", "town", "royal_domain", "religious", "disputed", "wilderness", "frontier", "enemy", "protected"]
const FRONTIER_REACH := 1400.0          # farther than this from every settlement the ground is wilderness, nearer it is the crown's frontier
const DISTRICT_FACTOR := 1.6            # a settlement's lands reach this many gaps out (LandClaim gaps: 350 villages, 600 towns)
const RIFT_BAN := 450.0                 # no building near a rift: the ward-lines are the Crown's
const ZONE_MAX := 64

## own, build, govern: what a stranger holds. auth: how hard the holder presses an illegal build (escalation speed).
## titles: how a founder can regularise it (lease, purchase, grant); empty means no legal road at all.
const RIGHTS := {
	"private": {"own": false, "build": false, "govern": false, "auth": 0.8, "titles": ["lease", "purchase"]},
	"leased": {"own": false, "build": true, "govern": false, "auth": 0.6, "titles": []},
	"granted": {"own": true, "build": true, "govern": false, "auth": 0.5, "titles": []},
	"town": {"own": false, "build": false, "govern": false, "auth": 1.5, "titles": ["lease"]},
	"royal_domain": {"own": false, "build": false, "govern": false, "auth": 1.3, "titles": ["lease", "grant"]},
	"religious": {"own": false, "build": false, "govern": false, "auth": 1.0, "titles": ["lease", "grant"]},
	"disputed": {"own": false, "build": false, "govern": false, "auth": 0.4, "titles": []},
	"wilderness": {"own": true, "build": true, "govern": false, "auth": 0.15, "titles": ["grant"]},
	"frontier": {"own": false, "build": false, "govern": false, "auth": 0.6, "titles": ["lease", "grant"]},
	"enemy": {"own": false, "build": false, "govern": false, "auth": 2.0, "titles": []},
	"protected": {"own": false, "build": false, "govern": false, "auth": 1.2, "titles": []},
}

const WORDS := {
	"private": "Private land. A household holds it: you may not build until you lease or buy it.",
	"leased": "Leased land. You may build, and you owe dues to the landholder.",
	"granted": "Granted land. The title is yours and you may build. You still do not make the law here.",
	"town": "Town land. The town's council rules it; building without leave will be stopped.",
	"royal_domain": "Royal domain. The Crown holds it; build only with a lease or a grant.",
	"religious": "Church land. The temple holds it; build only with its leave.",
	"disputed": "Disputed land. Two claimants, no clear law: nothing you build is safe and no title can be had.",
	"wilderness": "Wilderness. Nobody holds it. You may stake a claim and build, but you make no law.",
	"frontier": "Frontier. The Crown claims it but seldom patrols it. Building is unlawful and may be noticed.",
	"enemy": "Enemy ground. Anything you build here will be burned.",
	"protected": "Protected ground (ward-line, rift edge or sacred place). No building is allowed.",
}


static func rights_of(status: String) -> Dictionary:
	return (RIGHTS.get(status, RIGHTS["frontier"]) as Dictionary).duplicate(true)


static func words(status: String) -> String:
	return String(WORDS.get(status, ""))


## Nearest settlement: {sid, dist, name, kind, radius}; sid -1 when there are none.
static func nearest_settlement(p: Vector2) -> Dictionary:
	var best := {"sid": -1, "dist": INF, "name": "", "kind": "village", "radius": 0.0}
	for s: Dictionary in WorldGen.settlements:
		var d: float = p.distance_to(s["pos"])
		if d < float(best["dist"]):
			best = {"sid": int(s["id"]), "dist": d, "name": String(s["name"]), "kind": String(s.get("kind", "village")), "radius": float(s.get("radius", 60.0))}
	return best


static func near_rift(p: Vector2) -> float:
	var best := INF
	for s: Dictionary in WorldGen.sites:
		var k := String(s.get("kind", ""))
		if k == "rift" or k == "rift_outpost":
			best = minf(best, p.distance_to(s["pos"]))
	return best


## The legal status of the ground at p. `zones` are founding.gd's rows; `land` is the realm land module (deeds) or null.
static func status_at(p: Vector2, zones: Array = [], land: Variant = null) -> Dictionary:
	var ns := nearest_settlement(p)
	var out := {"status": "wilderness", "holder": "", "near": String(ns["name"]), "dist": float(ns["dist"]), "sid": int(ns["sid"])}
	for i in range(zones.size() - 1, -1, -1):
		var z: Array = zones[i]
		if p.distance_to(Vector2(float(z[0]), float(z[1]))) <= float(z[2]):
			out["status"] = String(z[3])
			out["holder"] = String(z[4])
			out["words"] = words(String(z[3]))
			return out
	var st := "wilderness"
	var holder := ""
	var sid := int(ns["sid"])
	var d := float(ns["dist"])
	var kind := String(ns["kind"])
	var gap := 600.0 if kind in ["town", "castle", "capital", "frontier_town"] else 350.0
	if near_rift(p) < RIFT_BAN:
		st = "protected"
		holder = "the Wardlines"
	elif Hv.protected_ground(p):
		st = "wilderness"          # the vale: unclaimed and secret
	elif sid >= 0 and d < maxf(float(ns["radius"]) * 1.3, 80.0):
		st = "royal_domain" if kind in ["castle", "capital"] else "town"
		holder = String(ns["name"])
	elif sid >= 0 and d < gap * DISTRICT_FACTOR:
		var dk := "royal"
		if land != null and land.has_method("deed"):
			var deed: Dictionary = land.call("deed", sid)
			dk = String(deed.get("kind", "royal"))
			holder = String(deed.get("holder", ""))
		match dk:
			"royal": st = "royal_domain"
			"church", "sect": st = "religious"
			"noble_estate", "commons": st = "private"
			"contested", "tribal": st = "disputed"
			"rift": st = "protected"
			"abandoned", "unclaimed": st = "frontier"
			_: st = "royal_domain"
	elif sid >= 0 and d < FRONTIER_REACH:
		st = "frontier"
		holder = "the Crown"
	out["status"] = st
	out["holder"] = holder
	out["words"] = words(st)
	return out
