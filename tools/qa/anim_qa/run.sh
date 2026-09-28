#!/usr/bin/env bash
# Animation QA for Rising Ashes: metrics report + 8-frame strips + contact sheets.
#
#   bash tools/qa/anim_qa/run.sh                 # everything (needs a GPU window, ~5 min)
#   bash tools/qa/anim_qa/run.sh --no-strips     # metrics + report only, headless (~2 min)
#   bash tools/qa/anim_qa/run.sh --only=guard    # one character / creature (substring of the id)
#   bash tools/qa/anim_qa/run.sh --import        # first run on a fresh checkout: import assets first
#
# Outputs: docs/qa/anim_qa_report.md, docs/qa/anim_qa_results.csv,
#          docs/qa/anim_strips/<id>__<clip>.jpg, docs/qa/anim_sheet_<group>.jpg
# Exit code: 0 if the run completed (not "no FAILs"; read the report).
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64.exe}"
SCRIPT="$REPO/tools/qa/anim_qa/anim_qa.gd"
command -v cygpath >/dev/null 2>&1 && SCRIPT="$(cygpath -m "$SCRIPT")"
LOG="${TMPDIR:-/tmp}/anim_qa_$$.log"

HEADLESS=""
PASS_ARGS=()
DO_IMPORT=0
for a in "$@"; do
  case "$a" in
    --no-strips) HEADLESS="--headless"; PASS_ARGS+=("$a") ;;
    --import) DO_IMPORT=1 ;;
    *) PASS_ARGS+=("$a") ;;
  esac
done

cd "$REPO" || exit 1
# Godot 4.6 rewrites older .import files (new default keys) when it imports. Remember
# which ones were already modified so we only revert what this run touched.
BEFORE="$(git diff --name-only -- '*.import' | sort)"

if [ "$DO_IMPORT" = 1 ]; then
  echo "== importing assets (one-off, several minutes)"
  "$GODOT" --headless --path kingdom --import >"$LOG.import" 2>&1
fi

echo "== running animation QA"
"$GODOT" $HEADLESS --path kingdom -s "$SCRIPT" -- "${PASS_ARGS[@]}" >"$LOG" 2>&1
grep -E "^(analysed|strips|SKIP|ANIM_QA_DONE)|SCRIPT ERROR" "$LOG" | tail -n 400

AFTER="$(git diff --name-only -- '*.import' | sort)"
# files this run touched, plus any .import diff that only ADDS lines (Godot 4.6 default keys)
PURE_ADD="$(git diff --numstat -- '*.import' | awk -F'\t' '$2 == 0 {print $3}' | sort)"
REVERT="$( (comm -13 <(echo "$BEFORE") <(echo "$AFTER"); echo "$PURE_ADD") | sort -u | sed "/^$/d")"
if [ -n "$REVERT" ]; then
  echo "== reverting $(echo "$REVERT" | wc -l) .import file(s) rewritten by this Godot run"
  echo "$REVERT" | tr '\n' '\0' | xargs -0 git checkout --
fi

if grep -q "ANIM_QA_DONE" "$LOG"; then
  echo "== done: docs/qa/anim_qa_report.md"
  R=docs/qa/anim_qa_report.md; for a in "$@"; do case "$a" in --only=*) R="docs/qa/anim_qa_report_only_${a#--only=}.md";; esac; done
  echo "== report: $R"; sed -n "5,6p" "$R"
  exit 0
fi
echo "!! the QA run did not finish; full log: $LOG"
exit 1
