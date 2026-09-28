# Recorded NPC movement trace viewer

Open [the CSV viewer](NPC_CAPTURE_TRACE_VIEWER.html) locally in a browser. It accepts a short real-game trace and lets the reviewer select an actor and scrub samples against a speed chart and state table. It starts empty; its optional synthetic demo is explicitly labeled and supplies no gameplay evidence. No network requests, game modification, or external libraries are needed.

Claude should add export instrumentation only in the implementation branch, using the existing QA harness where appropriate. This documentation branch supplies the review tool and format, not that instrumentation.

Required CSV header: `time_s,actor_id,body_speed_mps,anim_speed_mps,state`. Optional columns: `request_speed_mps,gap_m,owner,lod,clip`. Use seconds from capture start, stable actor IDs, and nonnegative speed magnitudes; record strictly increasing times per actor. Interleaved actor rows are supported. Quote commas, embedded newlines, and quotes according to CSV conventions. Empty optional numeric cells are shown as unavailable rather than zero.

`anim_speed_mps` is the actual scalar speed input used by the animator, not clip ground speed, playback scale, or a measured foot velocity. Export body speed from resolved movement using the convention selected in the [locomotion contract](LOCOMOTION_START_STOP_TURN_CONTRACT.md). State/owner/LOD/clip should refer to the same sample. Export after movement and animation-input computation, and describe sampling cadence and phase so a one-tick timing offset cannot masquerade as a response defect.

Beside the CSV retain branch commit, dirty-source status, date, actor/rig scale, render/physics rate, quality tier, route/seed, input events, speed convention, and synchronized normal/debug video. Exclude discontinuities such as teleports or flag them in a separate event record. A chart cannot prove wall penetration, human motion, planted-foot slip, or collision correctness; use it to locate frames in the paired capture.

Start with one travelling villager at 30 and 60 render FPS, one player start/stop/wall-contact sequence, and one promotion/demotion sequence. Inspect idle states during nonzero body motion, animation input lag, repeated state changes, catch-up bursts, owner changes, and body/data gap. Save the raw trace and the associated video rather than treating the viewer's synthetic example as an accepted tune.

The importer rejects missing or duplicate required headers, malformed quotes, wrong field counts, invalid numeric values, and non-increasing time for a given actor. It limits each input file to 8 MB for a short desktop review. Errors retain the prior loaded view and label that fact. Filenames and state strings are displayed as text; they are not executed.

Selected-sample markers make a one-row capture visible even when no line segment exists. JavaScript syntax, importer cases, and synthetic-demo/control execution can be checked independently of the browser. Browser rendering remains unverified: the available browser automation rejected the local file URL under its protocol policy. That source-level validation does not establish canvas appearance or successful browser file upload.
