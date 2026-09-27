#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PYTHON="${ROOT_DIR}/.venv/bin/python3"
REMOVE_HUM="${ROOT_DIR}/scripts/remove_hum.py"
INPUT_DIR="${ROOT_DIR}/input"
OUTPUT_DIR="${ROOT_DIR}/output"

usage() {
  cat <<EOF
Usage: $0 [audio-file ...]
       $0                    # process all audio in input/

Remove mains hum (50/60 Hz and harmonics) from recordings and write WAV
files to output/.

If no files are given, every .m4a, .wav, .mp3, .flac, and .aac file in
input/ is processed.

Setup (once):
  python3.12 -m venv .venv
  .venv/bin/pip install -r requirements.txt

Options (passed to remove_hum.py):
  --hum-hz 50|60     Force mains frequency (default: auto-detect)
  --q N              Notch width; higher = narrower (default: 35)
  --max-notch-hz N   Highest harmonic to notch (default: 1000)
  --highpass-hz N    High-pass after notching; 0 to disable (default: 40)

Examples:
  $0 "input/Teen Waltz - June 5, 2026.m4a"
  $0 --hum-hz 60 input/my-take.wav
  $0
EOF
}

collect_inputs() {
  if [[ $# -gt 0 ]]; then
    printf '%s\n' "$@"
    return
  fi
  shopt -s nullglob
  local files=(
    "$INPUT_DIR"/*.m4a "$INPUT_DIR"/*.M4A
    "$INPUT_DIR"/*.wav "$INPUT_DIR"/*.WAV
    "$INPUT_DIR"/*.mp3 "$INPUT_DIR"/*.MP3
    "$INPUT_DIR"/*.flac "$INPUT_DIR"/*.FLAC
    "$INPUT_DIR"/*.aac "$INPUT_DIR"/*.AAC
  )
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "error: no audio files in $INPUT_DIR" >&2
    exit 1
  fi
  printf '%s\n' "${files[@]}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -x "$VENV_PYTHON" ]]; then
  echo "error: Python venv not found. Run:" >&2
  echo "  python3.12 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2
  exit 1
fi

if [[ ! -f "$REMOVE_HUM" ]]; then
  echo "error: remove_hum.py not found: $REMOVE_HUM" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

py_args=()
inputs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hum-hz|--q|--max-notch-hz|--highpass-hz)
      py_args+=("$1" "${2:?missing value for $1}")
      shift 2
      ;;
    --hum-hz=*|--q=*|--max-notch-hz=*|--highpass-hz=*)
      py_args+=("$1")
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      inputs+=("$1")
      shift
      ;;
  esac
done

files=()
while IFS= read -r line; do
  files+=("$line")
done < <(collect_inputs ${inputs[@]+"${inputs[@]}"})

for audio in "${files[@]}"; do
  if [[ ! -f "$audio" ]]; then
    echo "error: file not found: $audio" >&2
    exit 1
  fi

  base="$(basename "$audio")"
  stem="${base%.*}"
  out="${OUTPUT_DIR}/${stem}.wav"

  echo "Processing $audio ..."
  "$VENV_PYTHON" "$REMOVE_HUM" "$audio" -o "$out" ${py_args[@]+"${py_args[@]}"}
done
