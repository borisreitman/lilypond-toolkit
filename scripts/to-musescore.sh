#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 score.ly [score2.ly ...]" >&2
  exit 1
fi

MUSESCORE_APP="${MUSESCORE_APP:-/Applications/MuseScore 4.app}"

for ly_file in "$@"; do
  if [[ ! -f "$ly_file" ]]; then
    echo "error: file not found: $ly_file" >&2
    exit 1
  fi

  base="${ly_file%.ly}"
  echo "Compiling $ly_file ..."
  lilypond -I "${ROOT_DIR}/includes" -o "$base" "$ly_file"

  midi_file="${base}.midi"
  if [[ ! -f "$midi_file" && -f "${base}.mid" ]]; then
    midi_file="${base}.mid"
  fi

  if [[ ! -f "$midi_file" ]]; then
    echo "error: no MIDI output for $ly_file" >&2
    echo "Add a \\midi { } block inside \\score { } in the .ly file." >&2
    exit 1
  fi

  echo "Opening $midi_file in MuseScore ..."
  open -a "$MUSESCORE_APP" "$midi_file"
done
