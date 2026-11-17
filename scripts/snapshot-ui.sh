#!/bin/zsh
# Renders a Debug build window to PNG with a throwaway library (no screen-recording permission needed).
# usage: scripts/snapshot-ui.sh <name> [WORSHPICK_DEMO_*=value ...]
# Known limit: Liquid Glass surfaces (sidebar, toolbar, inspector) do not render; use WORSHPICK_DEMO_PANEL_ONLY=1 for the setlist panel.
set -euo pipefail
cd "$(dirname "$0")/.."
name=$1; shift
work="${TMPDIR:-/tmp}/worshpick-snapshots"
rm -rf "$work/library-$name" "$work/$name.png"; mkdir -p "$work/library-$name"
environment=(--env WORSHPICK_LIBRARY_FOLDER="$work/library-$name" --env WORSHPICK_LOAD_SAMPLE_CATALOG=1
             --env WORSHPICK_SNAPSHOT_FOLDER="$work" --env WORSHPICK_SNAPSHOT_NAME="$name")
for assignment in "$@"; do environment+=(--env "$assignment"); done
open -n -W --stderr "$work/$name.log" $environment DerivedData/Build/Products/Debug/Worshpick.app &
openPid=$!
for _ in $(seq 1 25); do [[ -f "$work/$name.png" ]] && break; sleep 1; done
kill $openPid 2>/dev/null || true
echo "$work/$name.png"
