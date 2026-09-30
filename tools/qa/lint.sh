#!/usr/bin/env bash
# Free GDScript lint (no Claude tokens, no Godot, no import): gdtoolkit's gdlint + tools/qa/gd_extra_lint.py.
#
#   bash tools/qa/lint.sh              # kingdom/scripts + kingdom/tests, project config kingdom/.gdlintrc
#   bash tools/qa/lint.sh <files...>   # only these files (paths relative to the repo root), fast
#   bash tools/qa/lint.sh --strict     # also list unused arguments and unused locals (informational, exit 0)
#
# Install once:  python -m venv C:/Users/Jonna/Tools/gdtoolkit && C:/Users/Jonna/Tools/gdtoolkit/Scripts/pip install gdtoolkit
# CI installs it with pip. Override the venv with GDTOOLKIT=<dir>. Exit 1 on any real finding.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/kingdom" || exit 2
STRICT=0; FILES=()
for a in "$@"; do
  if [ "$a" = "--strict" ]; then STRICT=1; else FILES+=("${a#kingdom/}"); fi
done
[ ${#FILES[@]} -eq 0 ] && FILES=(scripts tests)

VENV="${GDTOOLKIT:-C:/Users/Jonna/Tools/gdtoolkit}"
if [ -x "$VENV/Scripts/gdlint.exe" ]; then GDLINT="$VENV/Scripts/gdlint"; PY="$VENV/Scripts/python"
elif [ -x "$VENV/bin/gdlint" ]; then GDLINT="$VENV/bin/gdlint"; PY="$VENV/bin/python"
else GDLINT="gdlint"; PY="python3"; fi

# Valid GDScript the gdtoolkit grammar cannot parse yet (soft keyword `set` as a name; multi-line "string").
# Remove an entry once gdtoolkit handles it.
SKIP="scripts/region1/rune_gesture.gd scripts/world/village_services.gd"

LIST=()
while IFS= read -r f; do
  skip=0; for s in $SKIP; do [ "$f" = "$s" ] && skip=1; done
  [ $skip -eq 0 ] && LIST+=("$f")
done < <(find "${FILES[@]}" -name '*.gd' 2>/dev/null | sed 's#^\./##')

rc=0
echo "== gdlint ($(printf '%s\n' "${LIST[@]}" | wc -l) files, config kingdom/.gdlintrc)"
"$GDLINT" "${LIST[@]}" || rc=1

echo "== gd_extra_lint (duplicate members / duplicate locals)"
EXTRA_OUT="$("$PY" "$ROOT/tools/qa/gd_extra_lint.py" "${LIST[@]}")"
echo "$EXTRA_OUT" | grep -E 'duplicate-|gd_extra_lint:' || true
echo "$EXTRA_OUT" | grep -q 'duplicate-' && rc=1

if [ $STRICT -eq 1 ]; then
  echo "== strict (informational)"
  echo "$EXTRA_OUT" | grep 'unused-local' || true
  ( cp .gdlintrc /tmp/.gdlintrc.bak; sed -i '/unused-argument/d' .gdlintrc; "$GDLINT" "${LIST[@]}" | grep unused-argument; cp /tmp/.gdlintrc.bak .gdlintrc ) || true
fi
[ $rc -eq 0 ] && echo "LINT OK" || echo "LINT FAILED"
exit $rc
