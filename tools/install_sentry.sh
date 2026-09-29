#!/usr/bin/env bash
# Installs the Sentry Godot SDK (MIT, getsentry/sentry-godot) into kingdom/addons/sentry, keeping only the platforms we ship
# (Windows x86_64 for QA, Android arm64/arm32, iOS). The full release zip is ~123 MB unpacked; pruned it is ~43 MB, so the
# binaries are NOT committed (kingdom/addons/sentry/ is git-ignored) and release builds run this script first.
# Without a DSN the SDK is a no-op ("Automatic initialization is disabled because no DSN was provided").
# Set the DSN in Project Settings > Sentry > Options (or an override.cfg in the release pipeline; never commit a real DSN).
# Usage: tools/install_sentry.sh [version]   (default 2.2.0, verified against Godot 4.6.3 on 2026-09-29)
set -euo pipefail
VER="${1:-2.2.0}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
gh release download "$VER" -R getsentry/sentry-godot -p "sentry-godot-$VER+*.zip" -D "$TMP"
ZIP="$(ls "$TMP"/sentry-godot-$VER+*.zip | head -1)"
unzip -q "$ZIP" -d "$TMP/x"
rm -rf "$REPO/kingdom/addons/sentry"
cp -r "$TMP/x/addons/sentry" "$REPO/kingdom/addons/sentry"
cd "$REPO/kingdom/addons/sentry"
rm -rf dotnet web bin/linux bin/macos bin/web bin/windows/arm64 bin/windows/x86_32 bin/android/*x86*
echo "Sentry $VER installed ($(du -sh . | cut -f1)). Licence: LICENSE.md (MIT)."
rm -rf "$TMP"
