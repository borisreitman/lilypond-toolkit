#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${ROOT_DIR}/.venv/bin/python"
MIDI_TO_LY="${ROOT_DIR}/scripts/midi_to_ly.py"

usage() {
  cat <<EOF
Usage: $0 midi-file [midi-file ...]

Convert piano MIDI to a draft LilyPond file.

Output: one .ly file per input (e.g. take.mid → take.ly).

Options are passed to midi_to_ly.py; run "$PYTHON $MIDI_TO_LY -h" for details.

Example:
  $0 my-piano-take.mid
  lilypond my-piano-take.ly && open my-piano-take.pdf
EOF
}

if [[ $# -lt 1 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x "$PYTHON" ]]; then
  echo "error: Python venv not found. Run:" >&2
  echo "  python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
  exit 1
fi

for midi in "$@"; do
  if [[ ! -f "$midi" ]]; then
    echo "error: file not found: $midi" >&2
    exit 1
  fi
  echo "Converting $midi ..."
  "$PYTHON" "$MIDI_TO_LY" "$midi"
done
