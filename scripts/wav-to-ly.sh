#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAV_TO_MIDI="${ROOT_DIR}/scripts/wav-to-midi.sh"
PYTHON="${ROOT_DIR}/.venv/bin/python"
MIDI_TO_LY="${ROOT_DIR}/scripts/midi_to_ly.py"

usage() {
  cat <<EOF
Usage: $0 recording.wav [recording2.wav ...]

Transcribe piano audio to a draft LilyPond file:
  WAV → MIDI (ByteDance) → .ly

Output: one .ly file per input (e.g. my-piano-take.wav → my-piano-take.ly).

Setup (once):
  brew install lilypond python@3.12 ffmpeg
  python3.12 -m venv .venv
  .venv/bin/pip install -r requirements.txt

Example:
  $0 my-piano-take.wav
  lilypond my-piano-take.ly && open my-piano-take.pdf
EOF
}

find_midi() {
  local base="$1"
  if [[ -f "${base}.mid" ]]; then
    printf '%s\n' "${base}.mid"
    return
  fi
  if [[ -f "${base}.midi" ]]; then
    printf '%s\n' "${base}.midi"
    return
  fi
  if [[ -f "${base}_basic_pitch.mid" ]]; then
    printf '%s\n' "${base}_basic_pitch.mid"
    return
  fi
  echo "error: expected MIDI output for $base (wav-to-midi)" >&2
  exit 1
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

if [[ ! -f "$MIDI_TO_LY" ]]; then
  echo "error: converter not found: $MIDI_TO_LY" >&2
  exit 1
fi

for audio in "$@"; do
  if [[ ! -f "$audio" ]]; then
    echo "error: file not found: $audio" >&2
    exit 1
  fi

  out_dir="$(cd "$(dirname "$audio")" && pwd)"
  base="${out_dir}/$(basename "${audio%.*}")"

  echo "=== Transcribing $audio ==="
  "$WAV_TO_MIDI" "$audio"

  midi_file="$(find_midi "$base")"
  echo "=== Converting $midi_file to LilyPond ==="
  "$PYTHON" "$MIDI_TO_LY" "$midi_file"
done
