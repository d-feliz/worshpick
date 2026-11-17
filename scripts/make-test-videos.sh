#!/bin/zsh
# Generates the lyric video fixtures used by the WorshpickCore tests. Needs ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."
output="Packages/WorshpickCore/Tests/WorshpickCoreTests/Fixtures/videos"
mkdir -p "$output"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

make_video() {
  local name="$1"; shift
  local frames="$work/$name"
  mkdir -p "$frames"
  swift scripts/render-lyric-screens.swift "$frames" "$@"
  # Each screen stays 3 seconds, like a real lyric video.
  ffmpeg -loglevel error -y -framerate 1/3 -i "$frames/screen-%02d.png" \
    -c:v libx264 -r 10 -pix_fmt yuv420p -tune stillimage "$output/$name.mp4"
}

make_video cancion-es \
  "Nada Nos Separa|Coro Esperanza" \
  "Ni lo alto ni lo profundo|nada me apartará" \
  "Tu amor me sostiene|en la tormenta" \
  "Ni lo alto ni lo profundo|nada me apartará"

make_video song-en \
  "Grace Upon Grace|Northfield Worship" \
  "From your fullness we receive|grace upon grace" \
  "The Word made flesh|dwelt among us"

make_video sin-texto "" ""

ls -la "$output"
