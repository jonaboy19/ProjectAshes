# P14c — ambient horses: HorseRig visuals + distant herds (critter.gd / ambient_life.gd / population LOD)

Owner: Codex (critter.gd) and cloud (ambient_life / population_lod). Standalone pieces already in the repo:
HorseRig (`scripts/horses/horse_rig.gd`), the horse VAT assets `assets/generated/vat/vat_horse_{bay,chestnut,grey,black,dappled}.res`
(shared textures `vat_horse_pos.res` / `vat_horse_nrm.res`), CrowdAnimLOD + VatCrowd from the living world (P13).

## 1. critter.gd: horse kinds use HorseRig instead of the Quaternius model

In the kind table replace the three horse rows' model with a HorseRig factory (coat per kind):
```gdscript
const HORSE_COATS := {"horse": ["bay", "chestnut", "black"], "horse_grey": ["grey", "dappled"], "horse_draft": ["chestnut"]}
...
if HORSE_COATS.has(kind):
	var rig := HorseRig.new()
	rig.name = "HorseRig"
	rig.coat = HORSE_COATS[kind][absi(hash(get_instance_id())) % HORSE_COATS[kind].size()]
	var t: Array[String] = ["bridle"]
	if kind == "horse_draft": t = ["cart_harness"]
	rig.tack = t
	rig.quality = Quality.tier
	add_child(rig)
	_model = rig
```
Wander logic: replace `_play(gait, rate)` for horses by `rig.drive(speed, yaw_rate, delta)`; grazing spots → `rig.set_mode("graze")`,
troughs/rivers → `set_mode("drink")`, resting at night → `set_mode("rest")`. Fleeing → speed 8–11 (gallop) with `play_action("Spook_L/R")`
first (side = where the threat is). `play_action("Hit_L/R")` instead of the current untouchable flinch if they ever take hits.
When the player mounts, `MountController.take()` copies `kind`; the HorseRig travels with the Critter (P14a uses `_rig()`).

## 2. Horse LOD (NEAR / MID / FAR-VAT) with CrowdAnimLOD

Register every ambient horse with the scene's CrowdAnimLOD (the same one villagers use after P13):
```gdscript
lod.register(id, critter, rig.model, rig.anim, null, "horse_" + rig.coat)
```
and load the looks once: `vat.load_looks(["horse_bay", "horse_chestnut", "horse_grey", "horse_black", "horse_dappled"])`.
The VAT clip keys are the HorseRig player names (`horse/Walk`, `horse/Trot`, `horse/Canter_L`, `horse/Gallop_L`, `horse/Graze`,
`horse/Idle`, `horse/Cart_Pull_Walk`, `horse/Idle_RestHind`, `horse/Drink`) plus plain aliases, so the skeleton <-> VAT hand-off keeps
the exact clip time. Unbaked clips (actions) fall back to Idle/Walk in the VAT tier (they only run near the player anyway).
Per-tier cost: HANDOFF.md "Performance".

## 3. Carts

`horse_cart.glb` (static, origin on the ground under the axle): place it at `horse.global_transform.translated_local(Vector3(0, 0, -2.05))`
and yaw-follow the horse with a trailer constraint (hitch = the shaft tips at the tugs, `rig.socket("tug_L")`/`"tug_R"`). Use
`rig.set_mode("cart")` so walk/trot become Cart_Pull_Walk / Cart_Pull_Trot (leaning into the collar, 1.25 / 3.0 m/s).
