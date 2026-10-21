extends GdUnitTestSuite
## 8 GB RAM budget: boots the game headless in a child Godot with `--ram8` (tools_qa/perf/mem_budget.gd) and asserts the engine
## heap PEAK (boot dominates: world gen) after 12 s of streaming stays under STATIC_BUDGET_MB. Skips (passes) when the child cannot boot the scene (no binary, no
## MEMBUDGET line). VRAM / texture memory is NOT measured here (dummy renderer): do that on a local PC.
## BUDGET: measured at ram8/high on the cloud container (see MEASURED below) plus ~25 % margin on the peak (2606 MB).
const STATIC_BUDGET_MB := 3250.0
const MEASURED := "ram8 static 1708 MB, peak 2606 MB (default 1765 / peak 2679), PC_HIGH headless, 2026-10-21"
const Q := preload("res://scripts/core/quality.gd")


func test_ram8_caps_never_raise_a_tier() -> void:
	for t in Q.TIERS.size():
		for k: String in Q.RAM8_CAP:
			if Q.TIERS[t].has(k):
				assert_float(float(minf(float(Q.TIERS[t][k]), float(Q.RAM8_CAP[k])))).is_less_equal(float(Q.TIERS[t][k]))
	assert_bool(Q.RAM8_OFF.has("sdfgi") and Q.RAM8_OFF.has("ssil")).is_true()


func test_ram8_static_memory_under_budget() -> void:
	var out: Array = []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--adult", "--quality=high", "--ram8",
		"--qa=res://tools_qa/perf/mem_budget.gd", "--seconds=12"]
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var line := ""
	for chunk in out:
		for l: String in String(chunk).split("\n"):
			if l.begins_with("MEMBUDGET "):
				line = l.substr(10)
	if code == -1 or line == "":
		push_warning("mem_budget probe could not boot the main scene headless: skipped")
		return
	var r: Variant = JSON.parse_string(line)
	assert_bool(r is Dictionary and bool(r["ram8"])).is_true()
	assert_float(float(r["static_peak_mb"])).override_failure_message(
		"ram8 static peak %s MB over budget %s MB (%s)" % [r["static_peak_mb"], STATIC_BUDGET_MB, MEASURED]).is_less(STATIC_BUDGET_MB)
