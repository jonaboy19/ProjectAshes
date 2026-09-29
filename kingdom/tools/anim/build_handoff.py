# Builds the clip tables of docs/anim/free_library/HANDOFF_CODEX.md (clip -> gameplay state, blend times,
# root motion, hit / release / VFX frames, ElementFX pairing) from the JSON files written by
# tools/anim/measure_events.gd (one per library, see MEASURE below) and the review verdicts.
#
#   python tools/anim/build_handoff.py <dir with the measure_events json files> [out.md]
#
# Frame numbers are 30 fps frames from the start of the clip (seconds = frame / 30). The events come from the
# actual bone motion: `hit` = the frame of maximum reach within 6 frames after a hand / foot speed peak (see the
# header of measure_events.gd). Everything else (state names, blend times, VFX pairing) is the recommendation of the
# review, the gameplay code owner (Codex) can change it freely.
import json, os, re, sys

D = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(D, "handoff_tables.md")
FPS = 30.0

# json file -> (title, glb path relative to res://assets/incoming/)
MEASURE = [
    ("ma", "animations_free/martial_arts_unarmed", "UAL_Free_MartialArtsUnarmed.glb"),
    ("combos", "animations_free/combos", "UAL_Free_Combos.glb"),
    ("kicks", "animations_free/kicks", "UAL_Free_Kicks.glb"),
    ("defense", "animations_free/defense", "UAL_Free_Defense.glb"),
    ("acro", "animations_free/acrobatics", "UAL_Free_Acrobatics.glb"),
    ("reactions", "animations_free/reactions", "UAL_Free_Reactions.glb"),
    ("casting", "animations_free/casting", "UAL_Free_Casting.glb"),
    ("castingkk", "animations_free/casting", "UAL_Free_CastingKaykit.glb"),
    ("weapons", "animations_free/weapons", "UAL_Free_Weapons.glb"),
    ("kk_react", "animations_free2/kaykit_combat_reactions", "UAL_Kay_combat_reactions.glb"),
    ("kk_life", "animations_free2/kaykit_life_sim", "UAL_Kay_life_sim.glb"),
    ("kk_move", "animations_free2/kaykit_movement_ext", "UAL_Kay_movement_ext.glb"),
    ("kk_ranged", "animations_free2/kaykit_ranged", "UAL_Kay_ranged.glb"),
    ("kk_undead", "animations_free2/kaykit_undead", "UAL_Kay_undead.glb"),
    ("trav", "animations_free2/traversal_authored", "UAL_Authored_Traversal.glb"),
]

FX_FIST = "`slash(elem, hand_pos, yaw, 0, 1.2, true)` @f{s}; `hit_sparks(elem, target_pos, dir)` @f{h}"
FX_SWORD = "`slash(elem, weapon_pos, yaw, tilt, 1.6)` @f{s}; `hit_sparks(elem, target_pos, dir)` @f{h}"
FX_KICK = "`slash(elem, foot_pos, yaw, 0, 1.4, true)` @f{s}; `hit_sparks(elem, target_pos, dir)` @f{h}"
FX_DASH = "`dash(elem, character, dir)` @f0"
FX_NONE = "-"

# (regex on the in-game name, gameplay state, blend in s, blend out s, fx template or key)
RULES = [
    # --- unarmed / combos
    (r"^MA_Punch_Jab_", "light attack 1 (jab)", 0.05, 0.12, FX_FIST),
    (r"^MA_Punch_Cross_", "light attack 2 (cross)", 0.06, 0.15, FX_FIST),
    (r"^MA_Punch_Hook_", "heavy attack (hook)", 0.08, 0.18, FX_FIST),
    (r"^MA_Combo_", "combo chain (n hits, cancel window after each hit + 0.10 s)", 0.08, 0.20, FX_FIST),
    (r"^MA_Kick_Jump", "leap / flying kick (root motion)", 0.10, 0.20, FX_KICK),
    (r"^MA_Kick_Swing", "sweeping kick", 0.08, 0.18, FX_KICK),
    (r"^MA_Kick_Front_R_Quick", "knee strike", 0.06, 0.15, FX_KICK),
    (r"^MA_Kick_", "kick attack", 0.08, 0.16, FX_KICK),
    (r"^MA_Block_", "block / parry stance change", 0.05, 0.15, "`hit_sparks(elem, block_pos, dir, 0.7)` on a successful block"),
    (r"^MA_Guard_Boxing", "combat idle (boxing guard)", 0.20, 0.20, FX_NONE),
    (r"^MA_Dodge_Duck", "dodge / duck under projectile", 0.08, 0.20, FX_NONE),
    (r"^MA_Evade_", "evade / cover", 0.08, 0.20, FX_DASH),
    (r"^MA_Acro_Cartwheel", "sidestep evade (cartwheel), flourish emote (root motion)", 0.10, 0.15, FX_DASH),
    (r"^MA_Acro_(Backflip|Somersault|BackflipBack|MonkeyBackflip)", "back evade / acrobatic flourish (root motion)", 0.10, 0.15, FX_DASH),
    (r"^MA_Acro_", "acrobatic flourish / traversal show-off (root motion)", 0.10, 0.15, FX_DASH),
    (r"^Fall_", "knockdown (play GetUp_* afterwards)", 0.06, 0.10, "`hit_sparks(elem, chest_pos, dir)` @f0"),
    (r"^GetUp_", "get up after knockdown", 0.10, 0.20, FX_NONE),
    # --- casting
    (r"^Cast_Slam_Overhead", "cast: ground slam / earth AOE", 0.12, 0.25, "`attach(&\"earth\", &\"charge\", hand_node)` @f0 .. hit; `aoe(&\"earth\", ground_pos, 3.0)` @f{h}"),
    (r"^Cast_Push_Palm", "cast: force push / wind blast", 0.10, 0.20, "`attach(&\"wind\", &\"charge\", hand_node)` @f0 .. hit; `play(&\"wind\", &\"impact\", palm_pos, forward)` or `projectile(&\"wind\", palm_pos, target, 22.0)` @f{h}"),
    (r"^Cast_Throw", "cast: projectile throw (fireball)", 0.10, 0.20, "`attach(&\"fire\", &\"charge\", hand_node)` @f0 .. release; `projectile(&\"fire\", hand_pos, target, 18.0)` @f{h}"),
    (r"^Cast_Aura", "cast: buff / aura channel", 0.15, 0.30, "`attach(&\"light\", &\"aura\", character)` @f{h}; `stop(fx)` at the end of the clip"),
    (r"^Cast_Raise_Charge", "cast: charge / channel start (lightning)", 0.12, 0.20, "`attach(&\"lightning\", &\"charge\", hand_node)` @f0; hold, then `chain(&\"lightning\", points)` @f{h}"),
    (r"^Cast_Shoot", "cast: one-hand projectile", 0.06, 0.15, "`projectile(elem, hand_pos, target, 20.0)` @f{h}"),
    (r"^Cast_Spell_Short", "cast: quick spell", 0.06, 0.15, "`play(elem, &\"impact\", target_pos)` @f{h}"),
    (r"^Cast_Spell_Long", "cast: long incantation (beam / big spell)", 0.10, 0.25, "`attach(elem, &\"charge\", hand_node)` @f0; `beam(elem, hand_pos, target, 1.0, 1.5)` @f{h}"),
    (r"^Cast_Summon", "cast: summon / raise earth", 0.12, 0.25, "`aoe(&\"earth\", ground_pos, 3.0)` @f{h}"),
    # --- KayKit weapons / general
    (r"^Weapon_1H_Chop_Jump", "plunge / jump attack 1H (root motion 0.1 m)", 0.08, 0.15, FX_SWORD),
    (r"^Weapon_1H_", "light attack 1H sword", 0.06, 0.15, FX_SWORD),
    (r"^Weapon_2H_Spin", "spin attack 2H (area)", 0.10, 0.20, FX_SWORD),
    (r"^Weapon_2H_", "heavy attack 2H / staff / spear", 0.08, 0.18, FX_SWORD),
    (r"^Weapon_DW_", "attack dual wield", 0.06, 0.15, FX_SWORD),
    (r"^Weapon_Block_Attack", "shield bash / counter after block", 0.05, 0.15, FX_FIST),
    (r"^Weapon_Block_Hit", "block reaction (hit while blocking)", 0.03, 0.12, "`hit_sparks(elem, block_pos, dir, 0.8)` @f{rc}"),
    (r"^Weapon_Block", "block raise", 0.05, 0.15, FX_NONE),
    (r"^MA_KK_Punch", "stylised punch", 0.05, 0.12, FX_FIST),
    (r"^MA_KK_Kick", "stylised kick", 0.06, 0.15, FX_KICK),
    (r"^MA_KK_Idle", "unarmed combat idle", 0.20, 0.20, FX_NONE),
    (r"^Hit_KK_", "hit reaction (flinch)", 0.03, 0.10, "`hit_sparks(elem, chest_pos, dir)` @f0"),
    # --- free2 combat reactions
    (r"^Kay_Hit_React", "hit reaction / stagger", 0.03, 0.12, "`hit_sparks(elem, chest_pos, dir)` @f0"),
    (r"^Kay_Death_Fall", "death (fall, stay on last frame or hand over to ragdoll at the down frame)", 0.08, 0.0, "`hit_sparks(elem, chest_pos, dir)` @f0; `play(&\"dark\", &\"status\", pos)` optional @down"),
    (r"^Kay_Block_Raise", "block start", 0.05, 0.10, FX_NONE),
    (r"^Kay_Block_Hold", "block hold", 0.10, 0.12, FX_NONE),
    (r"^Kay_Block_Impact", "block impact reaction", 0.03, 0.10, "`hit_sparks(elem, block_pos, dir, 0.8)` @f{rc}"),
    (r"^Kay_Block_Counter", "counter attack after block", 0.05, 0.15, FX_FIST),
    (r"^Kay_Stance_", "combat idle (2H / fists)", 0.20, 0.20, FX_NONE),
    (r"^Kay_Dodge_", "dodge (0.4 s burst, blend out to idle over 0.15 s)", 0.02, 0.15, FX_DASH),
    (r"^Kay_Attack_2H_Spin", "spin attack 2H (area)", 0.10, 0.20, FX_SWORD),
    # --- life sim
    (r"^Kay_Work_Chop", "job: chop tree", 0.15, 0.20, "`hit_sparks(&\"earth\", axe_tip, dir, 0.6)` on each hit frame"),
    (r"^Kay_Work_Dig", "job: dig", 0.15, 0.20, "`hit_sparks(&\"earth\", spade_tip, dir, 0.6)` on each hit frame"),
    (r"^Kay_Work_Mine", "job: mine ore", 0.15, 0.20, "`hit_sparks(&\"earth\", pick_tip, dir, 0.7)` on each hit frame"),
    (r"^Kay_Work_Hammer", "job: hammer / smith", 0.15, 0.20, "`hit_sparks(&\"fire\", hammer_head, dir, 0.6)` on each hit frame"),
    (r"^Kay_Work_Saw", "job: saw", 0.15, 0.20, FX_NONE),
    (r"^Kay_Lockpick", "interaction: lockpick", 0.15, 0.20, FX_NONE),
    (r"^Kay_Work_Bench", "job: workbench / craft", 0.15, 0.20, FX_NONE),
    (r"^Kay_Hold_Item", "hold item idle (upper body)", 0.15, 0.15, FX_NONE),
    (r"^Kay_Fishing_Cast", "fishing: cast (release the bobber at the hit frame)", 0.10, 0.15, "`projectile(&\"water\", rod_tip, bobber_pos, 12.0, 0.5)` @f{h}"),
    (r"^Kay_Fishing_Idle", "fishing: wait", 0.20, 0.20, FX_NONE),
    (r"^Kay_Fishing_Bite", "fishing: bite", 0.05, 0.10, "`play(&\"water\", &\"impact\", bobber_pos, Vector3.UP, 0.5)`"),
    (r"^Kay_Fishing_Tug", "fishing: tug", 0.08, 0.10, FX_NONE),
    (r"^Kay_Fishing_Reel", "fishing: reel loop", 0.15, 0.15, FX_NONE),
    (r"^Kay_Fishing_Struggle", "fishing: fight the fish", 0.10, 0.15, FX_NONE),
    (r"^Kay_Fishing_Catch", "fishing: catch reveal", 0.10, 0.20, "`level_up(pos, &\"water\", 0.6)` optional"),
    (r"^Kay_Emote_", "emote", 0.20, 0.20, FX_NONE),
    (r"^Kay_Interact_Reach|^Kay_Pick_Up|^Kay_Use_Item", "interaction (pick up / use item / reach)", 0.10, 0.15, FX_NONE),
    # --- movement ext
    (r"^Kay_Crouch_Idle|^Kay_Sneak", "crouch / sneak locomotion", 0.20, 0.20, FX_NONE),
    (r"^Kay_Walk_Back", "walk backwards", 0.15, 0.15, FX_NONE),
    (r"^Kay_Run_Strafe", "strafe run (lock-on)", 0.15, 0.15, FX_NONE),
    (r"^Kay_Walk_|^Kay_Run_Kay", "locomotion (alt walk / run set)", 0.20, 0.20, FX_NONE),
    (r"^Kay_Jump_", "jump (start / air / land / short / long)", 0.06, 0.10, "`dash(&\"wind\", character, dir, 0)` on land (dust)"),
    (r"^Kay_Idle_", "idle variant", 0.25, 0.25, FX_NONE),
    # --- ranged
    (r"^Kay_Bow_(Draw|Release)", "bow: draw / release (release = arrow spawn frame)", 0.08, 0.15, "`projectile(&\"wind\", nock_pos, target, 30.0, 0.6)` @f{h} (release clips)"),
    (r"^Kay_Bow_", "bow: idle / aim", 0.15, 0.15, FX_NONE),
    (r"^Kay_Run_Holding", "run holding ranged weapon", 0.15, 0.15, FX_NONE),
    (r"^Kay_(Pistol|Rifle)_Shoot", "gun: shoot (muzzle flash at the recoil frame)", 0.03, 0.10, "`hit_sparks(&\"fire\", muzzle_pos, dir, 0.5)` @f{rc}"),
    (r"^Kay_(Pistol|Rifle)_Reload", "gun: reload", 0.10, 0.15, FX_NONE),
    (r"^Kay_(Pistol|Rifle)_Aim", "gun: aim", 0.12, 0.12, FX_NONE),
    # --- undead
    (r"^Kay_Undead_Idle", "undead: idle", 0.25, 0.25, FX_NONE),
    (r"^Kay_Undead_Walk", "undead: walk", 0.20, 0.20, FX_NONE),
    (r"^Kay_Undead_Taunt", "undead: taunt / aggro", 0.10, 0.20, FX_NONE),
    (r"^Kay_Undead_(Awaken|Resurrect|Rise)", "undead: awaken / resurrect (needs a ground clamp, big root travel)", 0.05, 0.20, "`play(&\"dark\", &\"aura\", pos)` @f0"),
    (r"^Kay_Undead_Collapse", "undead: collapse (death)", 0.08, 0.0, "`play(&\"dark\", &\"impact\", pos)` @f0"),
    # --- traversal
    (r"^Ladder_Climb", "climb ladder (loop while the input is held)", 0.15, 0.15, FX_NONE),
    (r"^Wall_Climb", "climb wall (loop)", 0.15, 0.15, FX_NONE),
    (r"^Ledge_Hang", "hang from ledge", 0.10, 0.15, FX_NONE),
    (r"^Ledge_Shimmy", "shimmy along ledge (loop)", 0.10, 0.10, FX_NONE),
    (r"^Vault_Low", "vault over a low obstacle (root motion)", 0.10, 0.15, "`dash(&\"wind\", character, dir, 0)` on landing (dust)"),
    (r"^Ride_Idle", "riding: idle", 0.20, 0.20, FX_NONE),
    (r"^Ride_(Walk|Trot|Gallop)", "riding: gait", 0.20, 0.20, FX_NONE),
    (r"^Ride_Lean", "riding: lean pose (additive-style hold, blend by steering)", 0.20, 0.20, FX_NONE),
]
DEFAULT = ("(unmapped)", 0.15, 0.15, FX_NONE)
# clips whose main event is a strike / release: the table lists hit frames for these
EVENT_STATES = re.compile(r"attack|combo|kick|cast|punch|shoot|throw|release|draw|slam|push|job|cast|counter|hit|block impact|fishing: cast|flying")


def rule_for(name):
    for rx, st, bi, bo, fx in RULES:
        if re.search(rx, name):
            return st, bi, bo, fx
    return DEFAULT


def fmt_frames(fs):
    return ", ".join("f%d (%.2f s)" % (f, f / FPS) for f in fs)


def row(name, e):
    ig = re.sub(r"_Loop$", "", name)
    st, bi, bo, fx = rule_for(ig)
    loop = e.get("loop") or name.endswith("_Loop")
    tr = e["travel_m"]
    dist = (tr[0] ** 2 + tr[1] ** 2 + tr[2] ** 2) ** 0.5
    if dist >= 0.30:
        rm = "**yes**, %.1f m" % dist
    elif dist >= 0.06:
        rm = "no (%.2f m drift)" % dist
    else:
        rm = "no"
    # events
    hits = [h for h in e["hits"]]
    top = max([h["speed"] for h in hits], default=0)
    multi = st.startswith("combo") or st.startswith("job") or "spin" in st or "dual wield" in st
    if multi:                       # every strong hit of the clip
        hits = [h for h in hits if h["speed"] >= 0.7 * top and h["speed"] >= 3.0]
    else:                           # a single strike: the fastest one (other peaks are wind-up / recovery)
        hits = [h for h in hits if h["speed"] == top and h["speed"] >= 2.0]
    hf = [h["hit"] for h in hits][:6]
    ev = "-"
    is_event = bool(re.search(EVENT_STATES, st)) or "{h}" in fx or "{s}" in fx
    if hf and is_event:
        ev = "hit " + fmt_frames(hf)
    elif "{rc}" in fx:
        ev = "recoil peak f%d (%.2f s)" % (e["recoil_frame"], e["recoil_frame"] / FPS)
    elif e.get("down_frame", -1) >= 0 and "death" in st or "knockdown" in st:
        ev = "hit f0; on ground from f%d (%.2f s)" % (e["down_frame"], e["down_frame"] / FPS) if e.get("down_frame", -1) >= 0 else "hit f0"
    elif "reaction" in st or "stagger" in st or "flinch" in st:
        ev = "recoil peak f%d (%.2f s)" % (e["recoil_frame"], e["recoil_frame"] / FPS)
    h0 = hf[0] if hf else e["peak_frame"]
    fxs = fx.replace("{h}", str(h0)).replace("{s}", str(max(h0 - 3, 0))).replace("{rc}", str(e.get("recoil_frame", 0)))
    if "{h}" in fx and len(hf) > 1 and fx.startswith("`slash"):
        fxs = fx.split(";")[0].replace("@f{s}", "@f" + "/".join(str(max(x - 3, 0)) for x in hf)) + "; `hit_sparks(elem, target_pos, dir)` @f" + "/".join(str(x) for x in hf)
    elif len(hf) > 1 and "{s}" in fx:
        fxs = fx.replace("{s}", "/".join(str(max(x - 3, 0)) for x in hf)).replace("{h}", "/".join(str(x) for x in hf))
    return "| `%s`%s | %.2f | %s | %.2f / %.2f | %s | %s | %s |" % (ig, " (loop)" if loop else "", e["len_s"], st, bi, bo, rm, ev, fxs)


def main():
    lines = []
    total = 0
    for key, folder, glb in MEASURE:
        p = os.path.join(D, key + ".json")
        if not os.path.exists(p):
            continue
        d = json.load(open(p))
        ov = os.path.join(D, key + "_override.json")      # clips measured again with other limbs (e.g. the knee strike with --limbs=feet)
        if os.path.exists(ov):
            d.update(json.load(open(ov)))
        lines.append("### %s  (`res://assets/incoming/%s/%s`)\n" % (folder.split("/")[-1], folder, glb))
        lines.append("| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&\"fire\"`) |")
        lines.append("|---|---:|---|---|---|---|---|")
        for n, e in d.items():
            lines.append(row(n, e))
            total += 1
        lines.append("")
    lines.append("Total: %d clips.\n" % total)
    open(OUT, "w", encoding="utf-8").write("\n".join(lines))
    print("wrote", OUT, total, "clips")


main()
