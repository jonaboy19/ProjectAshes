#!/usr/bin/env bash
# ONE COMMAND (Git Bash / Linux): video_to_clip.sh <video.mp4> <ClipName> [--loop] [--fps 30] [...]  -> see video_to_clip.py
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
py="${VIDEO_MOCAP_PY:-}"
[ -z "$py" ] && [ -x "$here/.venv/Scripts/python.exe" ] && py="$here/.venv/Scripts/python.exe"
[ -z "$py" ] && [ -x "$here/.venv/bin/python" ] && py="$here/.venv/bin/python"
if [ -z "$py" ]; then   # git worktree: reuse the main checkout venv
  common="$(git -C "$here" rev-parse --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] && cand="$(cd "$here" && cd "$common/.." && pwd)/kingdom/tools/anim/video_mocap/.venv/Scripts/python.exe" && [ -x "$cand" ] && py="$cand"
fi
[ -z "$py" ] && { echo "No venv: run 'powershell -File $here/setup.ps1' or set VIDEO_MOCAP_PY" >&2; exit 2; }
exec "$py" "$here/video_to_clip.py" "$@"
