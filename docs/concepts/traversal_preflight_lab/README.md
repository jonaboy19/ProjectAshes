# Budgeted traversal pose preflight — lab only

These source files are a reviewable lab snapshot, not installed game code. The local Godot 4.6.3 fixture passes actual Vault_Low collision rejection at frame 18, clear translated path, four-attempt step budgets, cancellation, malformed coordinates and invalid-radius rejection.

The previous begin() constructed up to 2,880 capsule queries synchronously. It now checks sample/probe headers only; each segment validation and shape construction happens within step()'s 1–32 attempt budget. Failed validation consumes one attempt, returns invalid_pose and cannot approve traversal. queries counts actual physics queries; queries_this_step counts attempted segment validations, including failures. Deep-copying the bounded input remains synchronous; this is not a measured millisecond guarantee.

To reproduce outside the game, copy the three .gd files into a small Godot project, with traversal_roots.json in its parent directory. Run Godot --headless --path <project> --script verify_traversal_preflight.gd. The res:// preloads and fixture data path assume that layout.

IMPORTANT: The actual authored vault still penetrates the standard obstacle. This change preserves that rejection. sampled_clear is only sampled pose clearance: it is not commit authorization. Full sweep coverage, standing-capsule restoration, contact trajectory correction and world/support revalidation remain required. No production Player traversal hook or collision bypass is included.
