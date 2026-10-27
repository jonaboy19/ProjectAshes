extends RefCounted
## Conversation circles (NPC_MOTION_RULES G1, GroupMotion): one speaker token per group spot ("group": true in the type), kept in
## the spot record. Members are the spot's holders in slot order; turns last 3-7 s by hash and rotate fairly. Villagers ask
## `turn()` each session update and play a talk clip when they hold the token, a listen / nod clip otherwise, and look at the
## speaker (the speaker at the listener _GM.gaze_listener names).
##   const ConversationGroup := preload("res://scripts/living_world/conversation_group.gd")


## {members: Array[int] person ids in slot order, slots: Array[int], speaker: index into members, listener: index the speaker
## looks at, turn: int} for the group at `spot` now; {} when fewer than two people hold it.
const _GM := preload("res://scripts/living_world/group_motion.gd")   # by path: no dependency on the global class cache
static func turn(so: SmartObjects, spot: int, now: float) -> Dictionary:
	var sp: Dictionary = so.spots[spot]
	var holders: Array = sp["holders"]
	var members: Array[int] = []
	var slots: Array[int] = []
	for k in holders.size():
		if int(holders[k]) >= 0:
			members.append(int(holders[k]))
			slots.append(k)
	var n := members.size()
	if n < 2:
		sp.erase("conv")
		return {}
	var st: Dictionary = sp.get("conv", {})
	if st.is_empty():
		var tk := _GM.Token.new()
		tk.reset(spot, n, now)
		st = {"token": tk, "n": n}
		sp["conv"] = st
	var token: _GM.Token = st["token"]
	if int(st["n"]) != n:
		token.set_members(n)
		st["n"] = n
	token.advance(now)
	var spk := token.speaker % n
	var lis := _GM.gaze_listener(spot, token.turn, n, spk, now - token.started) % n
	return {"members": members, "slots": slots, "speaker": spk, "listener": lis, "turn": token.turn}
