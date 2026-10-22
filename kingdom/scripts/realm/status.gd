extends RefCounted
## MN-6 Status: how much standing a SUBJECT has in the eyes of an OBSERVER (a town's culture), derived and never stored.
##   title, wealth, reputation (trust mix), faith standing, guild rank, fame, infamy, and the company kept (companions and named
##   monsters) which each culture reads differently. Weights are data (data/world/status_weights.json); attitudes are data
##   (data/world/culture_attitudes.json). Title honour is scaled by SocialPerception.legitimacy for the observer's kingdom.
## subject: {title_rank 0..5, origin (kingdom), wealth 0..1, rep {trust, reliability, legitimacy, cruelty -100..100} (empty = unknown),
##           faith_standing -1..1, guild_rank 0..1, fame 0..100, infamy 0..100, church_seal bool, guild_sponsored bool,
##           companions [{kind, species, speech 0..4, civility 0..1, named bool, power}]}
## observer: {culture (id, kingdom or Array of tags), kingdom, sid}
## Status.of(subject, observer, ctx) -> {value, band, parts, company, lines}

const Data := preload("res://scripts/realm/mn_data.gd")
const SP := preload("res://scripts/realm/social_perception.gd")


static func band_of(v: float) -> String:
	for b: Array in Data.table("status_weights").get("bands", [["common", 1.01]]):
		if v < float(b[1]):
			return String(b[0])
	return "exalted"


static func attitude(culture: String, c: Dictionary, subject: Dictionary = {}) -> int:
	var row: Dictionary = (Data.table("culture_attitudes").get("cultures", {}) as Dictionary).get(culture, {})
	if row.is_empty():
		return 0
	var sp := String(c.get("species", ""))
	var kind := String(c.get("kind", "monster"))
	var a: int = int((row.get("species", {}) as Dictionary).get(sp, (row.get("kinds", {}) as Dictionary).get(kind, row.get("default", 0))))
	if bool(subject.get("guild_sponsored", false)):
		a += int((row.get("guild_sponsored_bonus", {}) as Dictionary).get(sp, 0))
	if bool(subject.get("church_seal", false)) and a < 0:
		a += int(Data.table("status_weights").get("church_seal_flip", 1))
	return clampi(a, -3, 3)


## Delta one companion adds to the owner's status in `culture` (doc 3.2).
static func company_delta(culture: String, c: Dictionary, subject: Dictionary = {}) -> float:
	var scale := float(Data.table("status_weights").get("company_scale", 0.06))
	var civ := clampf(float(c.get("civility", 0.5)), 0.0, 1.0)
	return float(attitude(culture, c, subject)) * (1.0 + 0.3 * float(c.get("speech", 0))) * (0.5 + 0.5 * civ) * scale


static func company_total(culture: String, subject: Dictionary) -> float:
	var cl := float(Data.table("status_weights").get("company_clamp", 0.25))
	var t := 0.0
	for c: Variant in subject.get("companions", []):
		if c is Dictionary:
			t += company_delta(culture, c, subject)
	return clampf(t, -cl, cl)


static func _trust01(rep: Dictionary) -> float:
	if rep.is_empty():
		return 0.5
	var mix := (float(rep.get("reliability", 0.0)) + float(rep.get("legitimacy", 0.0)) + float(rep.get("trust", 0.0))) / 300.0 \
		- float(rep.get("cruelty", 0.0)) / 200.0
	return clampf((mix + 1.0) * 0.5, 0.0, 1.0)


static func of(subject: Dictionary, observer: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var W: Dictionary = Data.table("status_weights")
	var w: Dictionary = W.get("weights", {})
	var cult := Data.culture_of(observer.get("culture", observer.get("kingdom", "folk")))
	var kingdom := String(observer.get("kingdom", ""))
	var leg := SP.legitimacy(String(subject.get("origin", kingdom)), kingdom, ctx)
	var title := clampf(float(subject.get("title_rank", 0)) / 5.0, 0.0, 1.0) * leg
	var wealth := clampf(float(subject.get("wealth", 0.2)), 0.0, 1.0)
	var trust := _trust01(subject.get("rep", {}))
	var companions: Array = subject.get("companions", [])
	var named := 0
	for c: Variant in companions:
		if c is Dictionary and bool((c as Dictionary).get("named", false)) and String((c as Dictionary).get("kind", "")) != "human":
			named += 1
	var faith_s := clampf(float(subject.get("faith_standing", 0.0)), -1.0, 1.0)
	var doctrine := String(((Data.table("culture_attitudes").get("cultures", {}) as Dictionary).get(cult, {}) as Dictionary).get("doctrine", ""))
	if doctrine == "unclean" and named > 0 and not bool(subject.get("church_seal", false)):
		faith_s = clampf(faith_s - minf(float(W.get("named_monster_faith_penalty_max", 0.6)), named * float(W.get("named_monster_faith_penalty", 0.2))), -1.0, 1.0)
	var faith01 := (faith_s + 1.0) * 0.5
	var guild := clampf(float(subject.get("guild_rank", 0.0)), 0.0, 1.0)
	var fame := clampf(float(subject.get("fame", 0.0)) / 100.0, 0.0, 1.0)
	var infamy := clampf(float(subject.get("infamy", 0.0)) / 100.0, 0.0, 1.0)
	var parts := {"title": title, "wealth": wealth, "trust": trust, "faith": faith01, "guild": guild, "fame": fame, "infamy": infamy}
	var base := 0.0
	for k: String in parts:
		var sign_ := -1.0 if k == "infamy" else 1.0
		base += sign_ * float(w.get(k, 0.0)) * float(parts[k])
	var comp := company_total(cult, subject)
	if cult == "monster_town" and named == 0:
		comp -= float(W.get("monster_town_unnamed_penalty", 0.1))
	var v := clampf(base + comp, 0.0, 1.0)
	return {"value": v, "band": band_of(v), "parts": parts, "company": comp, "culture": cult, "legitimacy": leg, "named_monsters": named,
		"lines": [standing_line(String(observer.get("name", cult)), v)]}


static func standing_line(place: String, v: float) -> String:
	var word := {"outcast": "Outcast", "low": "Wary", "common": "Known", "respected": "Respected", "noble": "Honoured", "exalted": "Exalted"}
	return "%s in %s" % [word.get(band_of(v), "Known"), place]


## Subject dict gathered from a RealmHub for the player or an NPC at settlement `sid` (every module optional).
static func gather(hub: Variant, subject_id: String, sid: int, extra: Dictionary = {}) -> Dictionary:
	var s := extra.duplicate(true)
	if hub == null:
		return s
	var aud: Variant = hub.mod("audiences")
	if aud != null and not s.has("title_rank"):
		s["title_rank"] = int(aud.title_rank(subject_id))
	var rp: Variant = hub.mod("reputation")
	if rp != null and not s.has("rep"):
		s["rep"] = rp.view("i:" + subject_id, "t:%d" % sid)
		if (s["rep"] as Dictionary).is_empty():
			var st: Dictionary = rp.standing("i:" + subject_id, sid)
			if bool(st.get("known", false)):
				s["rep"] = {"trust": st["trust"], "reliability": st["reliability"], "legitimacy": st["legitimacy"], "cruelty": st["cruelty"]}
	var ms: Variant = hub.mod("monster_society")
	if ms != null:
		s["fame"] = float(s.get("fame", ms.fame_of(subject_id, sid)))
		s["infamy"] = float(s.get("infamy", ms.infamy_of(subject_id, sid)))
	var mb: Variant = hub.mod("monster_bonds")
	if mb != null and not s.has("companions"):
		s["companions"] = mb.companions_of(subject_id)
	return s
