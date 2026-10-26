#!/usr/bin/env bash
# Exports every docs/diagrams/*.drawio to a PNG next to it (the README embeds the PNGs).
#   export-diagrams.sh
# Needs the draw.io desktop app. Set DRAWIO to its executable if it is not in the usual place.
# The PNG is twice the size, with a white background, so it reads the same in light and dark mode.
set -euo pipefail

cd "$(dirname "$0")/.."

drawio="${DRAWIO:-C:/Program Files/draw.io/draw.io.exe}"
if [ ! -x "${drawio}" ]; then
  echo "draw.io not found at ${drawio}; install it or set DRAWIO to its executable" >&2
  exit 1
fi

for source in docs/diagrams/*.drawio; do
  "${drawio}" --export --format png --scale 2 --border 15 --output "${source%.drawio}.png" "${source}"
done
