#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="${ROOT_DIR}/.venv/bin/python"
TRANSCRIBE="${ROOT_DIR}/scripts/wav_to_midi_bytedance.py"

usage() {
  cat <<EOF
Usage: $0 recording.wav [recording2.wav ...]

Transcribe solo piano audio to MIDI using ByteDance's piano model.

Output: one .mid file per input, next to the source audio
        (e.g. my-piano-take.wav → my-piano-take.mid).

Setup (once):
  brew install python@3.12 ffmpeg
  python3.12 -m venv .venv
  .venv/bin/pip install -r requirements.txt

The model checkpoint (~165 MB) downloads on first run.

Example:
  $0 my-piano-take.wav
  ./scripts/wav-to-ly.sh my-piano-take.wav
  ./scripts/play-midi.sh my-piano-take.mid
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

if [[ ! -f "$TRANSCRIBE" ]]; then
  echo "error: transcriber not found: $TRANSCRIBE" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found. Install with: brew install ffmpeg" >&2
  exit 1
fi

for audio in "$@"; do
  if [[ ! -f "$audio" ]]; then
    echo "error: file not found: $audio" >&2
    exit 1
  fi

  echo "Transcribing $audio ..."
  "$PYTHON" "$TRANSCRIBE" "$audio"
done
