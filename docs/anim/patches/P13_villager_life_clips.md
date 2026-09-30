# P13a: villager.gd — life clips, props, smart objects, ambience, animation LOD (Codex)

Villager.gd belongs to Codex. This patch uses only the new standalone modules in `kingdom/scripts/living_world/`
(`LifeLibrary`, `LifeProps`, `SmartObjects`, `LifeAmbience`, `LivingEvents`, `CrowdAnimLOD`). It changes no
behaviour code outside villager.gd, apart from the two one-line hooks in P13b (PopulationLOD).
The reference implementation of every step is `LifeActor` (`scripts/living_world/life_actor.gd`), which runs in
`tools_qa/living_world/living_world_demo.tscn`. Copy its logic, not the class.

Line numbers refer to `villager.gd` at `f547198a`. Apply the steps in order; each one ships on its own.

## 1. Install the life clips (about 190 clips, one shared library per rig)

In `_ready()`, right after `_anim = Assets.animation_player(model)`, add:

```gdscript
	LifeLibrary.install(_anim)      # idempotent; shared per skeleton path, so it costs the first villager ~40 ms, the rest 0
```

As an alternative, the cloud can append the four `LifeLibrary.LIBS` paths to `Assets.UAL_FILES` (see P13d). Then every
humanoid, including the player, gets the clips. The install call is cheaper because only villagers pay for it.

## 2. Better clips for existing acts (drop-in: `_first_clip` keeps the old names as fallbacks)

```gdscript
const ACT_CLIPS := {
	Act.SHOP: ["Life_Market_Browse", "Life_Mocap_Buy", "Idle_Talking", "Interact"],
	Act.INN: ["Life_Tavern_Lean_Bar", "Life_Tavern_Cheer", "Idle_Talking", "Cheering_Two_Hands"],
	Act.PRAY: ["Life_Pray_Kneel", "Life_Pray_Stand", "G6_pray", "Taichi_Idle"],
	Act.WATER: ["Life_Chore_Well_Crank", "G6_gathering", "Chore_Pick_Up_Box", "Interact"],
	Act.SHELTER: ["Life_Mocap_Cold", "Life_Ambient_Rub_Arms", "Shivering", "Idle_Subtle"],
	Act.FLEE: ["Shivering", "Idle_Hurt"],
	Act.WATCH: ["Life_Ambient_Shade_Eyes", "Idle_Listening", "Idle_Subtle"],
	Act.SLEEP: ["Life_Rest_Sleep_Ground", "Lie_Down_Idle", "Sitting_Idle"],
	Act.HOME: ["Life_Chore_Sweep", "Chore_Sweep", "Sitting_Idle"],
	Act.EAT: ["Life_Eat_Bread_Stand", "Consume_Item", "Sitting_Idle"],
}
const TALK_CLIPS := ["Life_Talk_Casual", "Life_Talk_Explain", "Life_Talk_Gossip", "Life_Talk_Emphatic", "Life_Mocap_Converse_A", "Idle_Talking"]
const LISTEN_CLIPS := ["Life_Talk_Listen_Nod", "Life_Talk_Listen_Hips", "Idle_Listening", "Head_Nod", "Idle_Talking"]
const ALONE_CLIPS := ["Life_Ambient_Shift_Weight", "Idle_Subtle"]
const JOB_CLIPS := [["Life_Farm_Hoe", "Life_Farm_Harvest", "Farm_Harvest"], ["Life_Smith_Hammer", "Fixing_Kneeling"],
	["Life_Market_Call_Out", "Life_Market_Arrange", "Idle_Talking"], ["Life_Guard_Lean_Spear", "Life_Guard_Attention", "Idle_Shield"],
	["Life_Carp_Saw", "Life_Chore_Sweep", "Interact"], ["Life_Wood_Chop", "TreeChopping"]]
```

`_first_clip` returns the FIRST name the rig has, so every villager in a job plays the same loop. For variety,
pick per person instead:

```gdscript
func _pick_clip(names: Array) -> String:          # stable per person, first-available fallback
	var have := names.filter(func(n: String) -> bool: return _anim and _anim.has_animation(n))
	return "" if have.is_empty() else have[person % have.size()]
```

Use it for `JOB_CLIPS`, `TALK_CLIPS` and `LISTEN_CLIPS`, and keep `_first_clip` for the rest.

Work sounds come from the clip's contact frames: replace the `WORK_SOUNDS` fraction with the sidecar events:

```gdscript
	var ev: Array = LifeLibrary.info(activity).get("events", {}).get("contact", [])   # 30 fps frames
	# fire when _anim.current_animation_position crosses f / 30.0 for any f in ev
```

## 3. Props (hoe, hammer, mug, lute ...)

```gdscript
var _props: LifeProps.Holder                                  # new member
# _ready(), after _add_head_look(model):
	_props = LifeProps.Holder.new(model.find_children("*", "Skeleton3D", true, false)[0])
# _update_activity(), where the activity clip starts (after `_anim.play(activity, 0.2)`):
		_props.show_for_clip(activity)
# _update_animation(), in the walking branch (after `_interrupt_activity()`):
	_props.clear()
```

Attachments are created once per character and then only shown or hidden.

## 4. Enter / exit transitions

Loops that change posture (kneel, sit, hoe, anvil ...) have `_Enter` and `_Exit` clips in the sidecar
(`LifeLibrary.info(clip).enter / .exit`). In `_update_activity`:

```gdscript
	if _activity_needs_start:
		var enter := String(LifeLibrary.info(activity).get("enter", ""))
		if enter != "" and _anim.has_animation(enter) and _activity_phase == 0:
			_anim.play(enter, float(LifeLibrary.info(enter).get("blend_in", 0.25)))
			_activity_phase = 1                               # new member; 1 = entering
			return
		_anim.play(activity, float(LifeLibrary.info(activity).get("blend_in", 0.2)))
		_activity_phase = 2
		...
	if _activity_phase == 1 and not _anim.is_playing():       # enter finished -> loop
		_activity_needs_start = true
```

In `_interrupt_activity()`, when the current clip has an `exit`, play it before walking. For example, set
`_yield_time = LifeLibrary.info(exit).get("seconds", 0.5)` so the body waits for it:

```gdscript
	var exit := String(LifeLibrary.info(_activity_name).get("exit", "")) if _activity_name != "" else ""
	if exit != "" and _anim.has_animation(exit):
		_anim.play(exit, 0.15)
		_wait = float(LifeLibrary.info(exit).get("seconds", 0.5))
```

## 5. Smart objects (anvil, well, bench, field rows, stalls, bar, pews, guard posts)

A single world-wide `SmartObjects` lives in WorldSim (P13c) as `WorldSim.smart`.
In `_apply_plan()`, before the brain's plain goal is used:

```gdscript
	_so_release()
	var act_name := {Act.WORK: "work", Act.SHOP: "shop", Act.INN: "inn", Act.PRAY: "pray", Act.WATER: "water",
		Act.EAT: "eat", Act.HOME: "home", Act.SOCIAL: "social"}.get(_act, "")
	if act_name != "" and WorldSim.get("smart") != null and not plan["indoors"]:
		var pick: Array = WorldSim.smart.find(global_position, {"act": act_name, "job": WorldSim.job[person],
			"hour": DailyRhythm.local_time(person)}, 70.0, person)
		if not pick.is_empty() and WorldSim.smart.claim(pick[0], pick[1], person):
			_session = WorldSim.smart.session(person, pick[0], pick[1])     # new member
			var ap: Vector3 = WorldSim.smart.approach_point(pick[0], pick[1])
			goal = Vector2(ap.x, ap.z)
			var sx: Transform3D = WorldSim.smart.stand_xform(pick[0], pick[1])
			_face_pref = Vector2(sx.basis.z.x, sx.basis.z.z)
```

When the route has arrived, `_session` drives the last metre and the clips. In `_physics_process`, where it
checks `_arrived`:

```gdscript
	if _session and _arrived:
		var out := _session.update(delta, global_position, _loop_wrapped())     # see LifeActor._track_clip
		if out["move_to"] != null: (align: move the last few cm straight to out.move_to, turn to out.face)
		if out["clip"] != "" and (out["restart"] or _anim.current_animation != out["clip"]): _anim.play(out["clip"], 0.25)
		_props.show_props(out["props"])
		if out["event"] != null: LivingEvents.emit(out["event"]["kind"], global_position, out["event"]["radius"])
		if _session.phase == SmartObjects.Session.DONE: _session = null   # the brain chooses again
```

Call `_session.interrupt()` in `_interrupt_activity()`, and `_so_release()` (`WorldSim.smart.release(person)`) in
`_exit_tree()`, in `resync()` and on every act change. This is the switch-out rule of NPC_ANIMATION_TRANSITION_DESIGN:
a reservation is never left behind.

`_loop_wrapped()` is true when `_anim.current_animation_position` goes down (a loop cycle ended) or a one-shot stopped.

## 6. Ambient variety (personality, fidgets, glances, weather, time of day)

```gdscript
var _amb: LifeAmbience                     # _ready(): _amb = LifeAmbience.new(person, is_child, age01)
# _think_tick(), after _update_facing(here):
	var d := _amb.think(THINK_INTERVAL, {"idle": _arrived and _activity_want == "", "walking": _walking,
		"pos": global_position, "fwd": Vector3(sin(_heading), 0, cos(_heading)), "hour": DailyRhythm.local_time(person),
		"weather": "rain" if UtilityBrain.is_raining(get_tree()) else "clear",
		"player_pos": _player.global_position if _player else null,
		"partner_pos": _partner_node.global_position if _partner_node else null})
	_amb_look = d["look"]; _amb_walk = d["walk"]; _amb_upper = d["upper"]
	if d["fidget"] != "" and _activity_want == "" and _anim.has_animation(d["fidget"]): _anim.play(d["fidget"], 0.25)
```

- `_walk_speed *= _amb.walk_speed` in `_ready`. Idle rate: `_idle_rate()` returns `_amb.anim_rate`. Height:
  `Assets.character(_file, 1.7 * _amb.height, _keep)`.
- Walk style: in `_update_animation`, use `_amb_walk` instead of `"Walking_A"` when the rig has it, with
  `clip_speed = LifeLibrary.info(_amb_walk).get("speed_mps", WALK_CLIP_SPEED)` so the feet do not slide.
- Rain or carrying: `clip = LifeLibrary.composite(_anim, walk_clip, _amb_upper)` when `_amb_upper != ""`.
  Legs come from the walk and spine and arms from the hunch or carry layer, in one AnimationPlayer and a cached clip.
- Head look: in `_update_head_look`, `_amb_look` (glances at events and at the player, with personality cooldowns)
  replaces the fixed `< 5 m player` rule.
- Emit events where things happen: `LivingEvents.emit("clang", pos, 14.0)` from the smithy (Session events do this),
  `LivingEvents.emit("sprint", player_pos, 8.0)` from the player when sprinting through a crowd, `"cart"` from carts.

## 7. Animation LOD: hand it to CrowdAnimLOD

**Measured finding: remove the villager's own 12 Hz stepping even without CrowdAnimLOD.**
`AnimationPlayer.advance()` in MANUAL mode costs about 320 µs per call on the MakeHuman villager rig, against
about 24 µs for the engine's own IDLE processing of the same player. That is 13x more
(`tools_qa/living_world/anim_cost_probe.tscn`, Godot 4.6.3, PC).

Villager.gd today switches every villager beyond 12 m to MANUAL and calls `advance()` at 12 Hz, i.e. every 5th
frame at 60 fps. That costs about 64 µs per villager per frame instead of 24, so the "LOD" makes distant villagers
about 2.5x MORE expensive.

Other approaches:
- Toggling `active` or `callback_mode_process` per frame never processes at all: the change lands after the frame's
  process list is built.
- What works is switching the player's `process_mode` (INHERIT on the step frame, DISABLED otherwise) with
  `speed_scale x step`. CrowdAnimLOD does exactly that and restores the controller's own speed_scale.


When the PopulationLOD hook (P13b) registers villagers:
- delete the animation half of `_apply_distance_lod` (the `_anim_lod`/`callback_mode_process` block) and the
  `_anim.advance(step)` branch in `_physics_process`: CrowdAnimLOD owns the process mode, the stepping and the
  shadows;
- add `var lod_tier := 0`, which CrowdAnimLOD writes (0 NEAR, 1 MID, 2 FAR, 3 OUT). In FAR and OUT, `_think_tick` can
  skip `_check_stuck`, `_neighbour_push` and the head look (the model is not drawn; VAT shows the same clip and phase).
- keep `_anim.play()`, `seek()` and `speed_scale` as they are. CrowdAnimLOD follows `current_animation` into the VAT twin.

Measured costs are in `docs/anim/living_world/HANDOFF.md` (Perf).
