extends "res://scripts/ui/affairs/affairs_base.gd"
## LETTERS: the weekly digest and the urgent word (scripts/realm/war_intel.gd inbox) shown as letters: the steward's report, riders'
## news, rumours. war_intel already throttles them (one digest a week, one urgent word a day); this panel only shows them, marks them
## read when you leave the page, and exposes unread_count() for a badge. Envoys waiting at the door open the audience dialog.
## "Read" ids persist in Life.life_path.flags (or a local dictionary when a hub is injected).

const EnvoyDialog := preload("res://scripts/ui/affairs/envoy_dialog.gd")
const FLAG := "letters_read"
const KEEP := 60
const KIND_LABEL := {"steward": "From your steward", "intel": "By rider", "rumour": "Rumour", "threat": "Urgent word"}

var _local_read: Array = []


## The persistent "read" list (an Array of letter ids) for a hub-less default, or the local one when a hub is injected.
func _read_ids() -> Array:
	if realm_override == null and Life != null and Life.get("life_path") != null:
		var fl: Dictionary = Life.life_path.flags
		if not fl.has(FLAG):
			fl[FLAG] = []
		return fl[FLAG]
	return _local_read


static func unread_in(inbox: Array, read: Array) -> Array:
	return inbox.filter(func(d: Dictionary) -> bool: return not read.has(int(d["id"])))


func inbox() -> Array:
	var wi: Variant = mod("war_intel")
	return wi.call("inbox") if wi != null else []


func unread_count() -> int:
	return unread_in(inbox(), _read_ids()).size()


func mark_all_read() -> void:
	var read := _read_ids()
	for d: Dictionary in inbox():
		if not read.has(int(d["id"])):
			read.append(int(d["id"]))
	while read.size() > KEEP:
		read.pop_front()


func on_hide() -> void:
	mark_all_read()


func _fill(b: VBoxContainer) -> void:
	var wi: Variant = mod("war_intel")
	if wi == null:
		_dim(b, EMPTY)
		return
	var envoys: Array = wi.call("envoys", "waiting")
	if not envoys.is_empty():
		_sec("At the door")
		var card := _card(b)
		for e: Dictionary in envoys:
			_txt(card, "An envoy of %s asks for %s." % [nice(String(e["from"])), String(e["ask"])], AF.TEXT, 17)
		_btn(card, "Receive the envoy", open_envoy, true)
	var mail := inbox()
	var read := _read_ids()
	_sec("Letters")
	var head := _flow(b)
	var n := unread_in(mail, read).size()
	_txt(head, ("%d unread" % n) if n > 0 else "All read", AF.GOLD if n > 0 else AF.TEXT_DIM, 16, "title")
	if n > 0:
		_btn(head, "Mark all read", func() -> void: mark_all_read())
	if mail.is_empty():
		_dim(b, "No letter has come yet. A steward, a scout or the tavern may write once a week.")
		return
	var rev := mail.duplicate()
	rev.reverse()
	for d: Dictionary in rev:
		_letter(b, d, not read.has(int(d["id"])))


func _letter(b: VBoxContainer, d: Dictionary, fresh: bool) -> void:
	var card := _card(b)
	var title := "Urgent word, day %d" % int(d["day"]) if bool(d.get("urgent", false)) else "Letter of week %d" % int(d["week"])
	_txt(card, title + ("   (new)" if fresh else ""), AF.GOLD_BRIGHT if fresh else AF.TEXT, 17, "title")
	var last := ""
	for it: Dictionary in d["items"]:
		var kind := String(it.get("kind", ""))
		if kind != last:
			_dim(card, String(KIND_LABEL.get(kind, nice(kind))))
			last = kind
		_txt(card, String(it["text"]), AF.TEXT, 16)


func open_envoy() -> String:
	var host: Node = self
	if menu != null and menu.get("hud") != null:
		host = menu.get("hud")
	EnvoyDialog.open(host, realm_override)
	return ""
