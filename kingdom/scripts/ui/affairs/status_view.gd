extends RefCounted
## STATUS breakdown for the character sheet (scripts/realm/status.gd via monster_society.status_of): your standing in the nearest town's
## culture as a band word, and what builds it (title, wealth, reputation, faith, guild, fame, infamy, the company you keep) in words.
##   StatusView.fill(box, hub, sid)  -> true when something was drawn. Read-only; call from a refresh, never per frame.

const AF := preload("res://scripts/ui/ashes_frame.gd")
const Kit := preload("res://scripts/ui/gamemenu/gm_kit.gd")
const Base := preload("res://scripts/ui/affairs/affairs_base.gd")

const PARTS := [["title", "Title"], ["wealth", "Wealth"], ["trust", "Reputation"], ["faith", "Faith"], ["guild", "Guild standing"],
	["fame", "Fame"], ["infamy", "Infamy"]]
const WORDS := ["none", "slight", "modest", "good", "great"]
const BAND := {"outcast": "Outcast", "low": "Wary looks", "common": "Known", "respected": "Respected", "noble": "Honoured", "exalted": "Exalted"}


static func fill(box: VBoxContainer, hub: Variant, sid: int, subject := "player") -> bool:
	Kit.clear(box)
	if hub == null:
		return false
	var ms: Variant = hub.call("mod", "monster_society")
	if ms == null:
		return false
	var st: Dictionary = ms.call("status_of", subject, sid)
	if st.is_empty():
		return false
	var band := String(st["band"])
	box.add_child(Kit.lbl(String(BAND.get(band, band.capitalize())), 18, AF.GOLD_BRIGHT, false, "title"))
	for l: Variant in st.get("lines", []):
		box.add_child(Kit.lbl(String(l), 15, AF.TEXT_DIM, true, "italic"))
	var parts: Dictionary = st["parts"]
	for p: Array in PARTS:
		var k := String(p[0])
		var v := float(parts.get(k, 0.0))
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 24
		row.add_child(Kit.lbl(String(p[1]), 15, AF.TEXT_DIM))
		row.add_child(Kit.hspacer())
		row.add_child(Kit.lbl(Base.fuzzy(v, WORDS), 15, Kit.BAD if k == "infamy" and v > 0.25 else AF.TEXT))
		box.add_child(row)
	var comp := float(st.get("company", 0.0))
	var crow := HBoxContainer.new()
	crow.custom_minimum_size.y = 24
	crow.add_child(Kit.lbl("Company you keep", 15, AF.TEXT_DIM))
	crow.add_child(Kit.hspacer())
	crow.add_child(Kit.lbl("no effect" if absf(comp) < 0.02 else ("raises it" if comp > 0.0 else "lowers it"), 15,
		Kit.GREEN if comp > 0.02 else (Kit.BAD if comp < -0.02 else AF.TEXT)))
	box.add_child(crow)
	return true
