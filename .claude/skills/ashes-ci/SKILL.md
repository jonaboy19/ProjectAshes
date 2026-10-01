---
name: ashes-ci
description: Use GitHub Actions (free on this public repo) instead of local runs for the full Rising Ashes test suite, secret scan and file-size guard, and read the results cheaply through the GitHub MCP tools. Use after every push, before claiming "tests pass", or when the container is short on memory.
---

# Free CI for Rising Ashes

Workflow: `.github/workflows/tests.yml`. It runs on every push to `main` or `claude/**`, on PRs, and on manual dispatch. Public repos get unlimited Actions minutes, so the only cost is waiting.

| Job | Checks | Typical time |
|---|---|---|
| `guard` | gitleaks over the pushed commits (Meshy key, tokens) and no tracked file over 90 MB | about 1 min |
| `lint` | gdtoolkit `gdlint` with `kingdom/.gdlintrc` plus duplicate-name check (`tools/qa/lint.sh`), no Godot | about 3 min |
| `gdunit` | Godot 4.6.2 headless `--import`, then the whole gdUnit4 suite; exit 101 (orphans only) counts as a pass | 20-90 min on a cold cache, faster warm |

## Reading results with few tokens
1. `mcp__github__actions_list` (method `list_workflow_runs`, repo `jonaboy19/projectashes`, `per_page: 3`). Check `conclusion`.
2. If it's red, `mcp__github__get_job_logs` with `failed_only: true` and `tail_lines: 80`. The step prints only the summary line plus the FAILED and SCRIPT ERROR lines.
3. The job summary (the `## gdUnit4` block) has the same text. The full log and gdUnit HTML are in the `gdunit-report` artifact, kept 7 days.

## Rules
- Push first, then run other work while CI runs. Don't also run the full suite locally unless you need the result within minutes.
- Locally, run only the test files you touched: `--add res://tests/test_x.gd`.
- Perf and timing tests (`*_perf`, `test_tick_cost_*`) can flake on shared runners. Fix the budget or the code; never delete the test.
- A red `guard` means a secret or a huge file was pushed. Rotate the secret; don't just delete the line (history is public).
- Never add a workflow step that needs a paid service or an account token.

## Linting (free, no Godot, no import)
`bash tools/qa/lint.sh` runs gdtoolkit's `gdlint` (MIT, PyPI) with the project config `kingdom/.gdlintrc`, plus `tools/qa/gd_extra_lint.py` (duplicate members and duplicate locals in one scope). Local venv: `C:\Users\Jonna\Tools\gdtoolkit`; CI job `lint` in `tests.yml` pip-installs `gdtoolkit==4.5.0` and runs the same script (about 3 minutes).
- Run it after editing `.gd` files, before pushing. Pass file paths (`bash tools/qa/lint.sh kingdom/scripts/realm/war.gd`) to check only those files.
- `--strict` also lists unused locals and unused arguments. They are advisory (many are intentional signature-compatible callbacks), so they never fail the run.
- The config turns off the style rules the code base breaks on purpose (line length, definition order, file length, table-name shorthand such as `T` / `SPEED_T`). Do not reformat code to satisfy them and do not turn those rules back on. Do not run `gdformat` over the tree.
- Two files (`rune_gesture.gd`, `village_services.gd`) are valid Godot but the gdtoolkit grammar cannot parse them; they are listed in `SKIP` inside `lint.sh`.
- gdlint finds style and structure, not type errors. Wrong calls, missing members and type mistakes still only show up in gdUnit (the `gdunit` job).
- Findings and what was checked: `docs/qa/LINT.md`.
- GitHub Actions is currently blocked by an account billing lock (owner must fix it), so none of these jobs run until then: run `bash tools/qa/lint.sh` locally, it needs no Godot and no tokens.
