---
name: ashes-ci
description: Use GitHub Actions (free on this public repo) instead of local runs for the full Rising Ashes test suite, secret scan and file-size guard, and read the results cheaply through the GitHub MCP tools. Use after every push, before claiming "tests pass", or when the container is short on memory.
---

# Free CI for Rising Ashes

Workflow: `.github/workflows/tests.yml`. It runs on every push to `main` or `claude/**`, on PRs, and on manual dispatch. Public repos get unlimited Actions minutes, so the only cost is waiting.

| Job | Checks | Typical time |
|---|---|---|
| `guard` | gitleaks over the pushed commits (Meshy key, tokens) and no tracked file over 90 MB | about 1 min |
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
