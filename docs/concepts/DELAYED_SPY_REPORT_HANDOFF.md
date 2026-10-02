# Delayed spy observations

The existing Campaign `report_sighting` reads live army position and numbers at delivery. Keep it for immediate observations; delayed couriers, scouts and spies must use the new `report_observation` path.

The caller supplies the observed army ID, observed faction, witness/source ID, observed position, observation hour and estimated strength range. Campaign supplies receipt hour. No live army position, strength, composition or survival lookup is performed. This preserves legitimate stale reports even after the observed force disappears.

Reports retain their observation hour, so the existing war-table age and uncertainty calculation continues to age them. Older or equal-time deliveries cannot replace newer knowledge. New entries are bounded at 128 sight records. Invalid/future/expired observations are rejected. Composition is explicitly unknown rather than copied from another observation.

## Verification and remaining work

The pure payload fixture passes position/time retention and rejection of future, expired, nonfinite-position and invalid-strength reports. A second fixture runs exact copies of Campaign's acceptance and display methods: a six-hour delay retains the observed position, produces age six and a 540 m uncertainty radius, rejects an older replacement, preserves the sight payload through JSON, and hides future/expired entries. This does not exercise the full Campaign serializer, autoloads or actual map Control; those still require a full-project check.

Campaign now skips expired entries during display rather than waiting for its next daily cleanup. Receipt hour is normalized alongside other integers during save restoration, with older saves remaining compatible when that field is absent.

This API is not a completed spying feature. The host must authenticate the witness, prove perception, store the observation at acquisition, and deliver it through an actual communication channel. Town spying still needs assignments, travel, observation targets, detection, report delivery and UI. Existing strategic spy missions have not been replaced.

Do not use this path to inject all enemy positions into the map. A visible marker represents received evidence, not global truth.

## Report delivery queue

`queue_observation` accepts the same observation plus communication travel hours. It validates the snapshot before placing it in a bounded 64-entry pending queue, rejects duplicate witness/army/time observations, and exposes nothing to the map before arrival. Campaign's hourly tick delivers due records through `report_observation`. If newer knowledge arrived first, the older courier report is discarded. Successful delivery emits one notification.

Pending reports are included in Campaign serialization and restored after its clock, including compatibility with saves without this field. Restore work examines at most 64 records. The focused fixture exercises exact queue/delivery/restore methods and verifies hidden-before-arrival behavior, pending JSON restoration, age and position retention, exactly one delivery and queue capacity. Full Campaign save and startup remain unverified.

This queue is a data delivery mechanism. It does not prove a physical courier travelled safely or that a witness saw the target. Assignment/travel systems must validate those facts, compute travel hours, and enqueue only legitimate observations. Interception, courier loss and town espionage tasks remain pending.

## First existing producer connected

Enterprise caravan leaders now capture the observed position, Campaign hour and rough strength range when the existing town-stop observation rule succeeds. Distant observations enter the delivery queue, using a minimum one-hour straight-line communication estimate to the caravan's home at 540 m/hour. A nearby leader can deliver immediately. The early army-news notification was removed; queued reports notify upon actual data delivery.

The pre-existing 1100 m observation rule and curious-leader probability are retained. This is strategic observation, not physical line-of-sight verification. The communication estimate is not a navigated courier and does not model interception. A future route-aware courier must replace that estimate without changing the stored observation. Enterprise runtime and the full-project startup are still being checked.
