# Existing start clips: integration boundary

5 October 2026. Source review only.

P5 supplies `Loco_WalkStart_F` and `Loco_RunStart_F` plus contact/root sidecars. It recommends matching playback rate to exit speed. However the authored walk starts at 0.7 m/s and run starts at 2.1 m/s before playback scaling. Current player steering begins at zero with speed-dependent acceleration (`lerpf(ACCEL_START, ACCEL_TOP, run_t)`), direction alignment and control modifiers. Matching exit speed alone therefore does not match the initial planted-foot travel.

Do not implement these starts as an unconditional overlay on the current zero-speed acceleration. Reuse the clips and existing single movement owner, with an explicit approach:

1. Inspect the loaded clip's early root/contact curves and handoff phase rather than rely only on summary entry/exit speeds.
2. Either use collision-resolved authored displacement for the committed start, or select/blend a clip interval that matches the existing acceleration. Both need a documented interrupt path for released/reversed input, combat, jump, water, mount and obstruction.
3. Movement resolves through the capsule once. Disabling animation root travel while sampling its curve avoids double movement. Never repay blocked displacement later.
4. Derive clip time from actual graph evaluation, as current pivots do; blend exit gait with the sidecar phase. Walk and run starts have different durations and target phases.
5. Preserve analog input and short touch taps: an immediately released stick must not force the full authored 1.56/1.87 m travel. Use the existing braking/stop state when interrupted.
6. Review full-body hand/weapon blends and real phone timing. Clip-only foot-slide measurements do not establish gameplay acceptance.

No new animation assets or external downloads are required. Existing starts are available for integration, while current player source does not select them. Existing run stops and pivots must remain intact.
