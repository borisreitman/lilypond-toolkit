#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MSCORE="${MSCORE:-/Applications/MuseScore 4.app/Contents/MacOS/mscore}"
MUSE_KEYS_DIR="${MUSE_KEYS_DIR:-${HOME}/Library/Application Support/Muse Hub/Downloads/Instruments/Muse Keys}"
PYTHON="${ROOT_DIR}/.venv/bin/python"
TRIM_MIDI="${ROOT_DIR}/scripts/trim_midi_bars.py"
KEEP_WAV=0
OUTPUT_WAV=""
FROM_BAR=""
TO_BAR=""
TRIMMED_MIDI=""

usage() {
  cat <<EOF
Usage: $0 [-o wav-file | --keep] [--from-bar N [--to-bar M]] midi-file [midi-file ...]

Render and play MIDI using Muse Keys (MuseScore MuseSounds profile).

Requires:
  - MuseScore 4 Studio
  - Muse Keys installed in Muse Hub

Options:
  -o, --output FILE   Save rendered audio to FILE (kept after playback)
                      Only valid with a single MIDI input file.
  --keep              Save rendered .wav next to each MIDI file (kept after playback)
  --from-bar N        Play from bar N (1-based; negative counts from end, -1 = last)
  --to-bar M          Stop after bar M (1-based; negative counts from end).
                      With --to-bar alone, playback starts at bar 1.

Bar numbers follow the MIDI file's time signature meta events.
Negative bars count from the end (-1 = last bar, -2 = second-to-last).

Without -o or --keep, audio is written to a temp file in /tmp and deleted after play.

Note: MuseScore CLI cannot stream audio — it must render Muse Keys to a file first.
      For interactive playback without a render step, open in MuseScore GUI (Space to play):
        open -a "MuseScore 4" piece.mid

Examples:
  $0 hello.midi
  $0 --from-bar -4 --to-bar -1 score/waltz.midi
  $0 -o playback/hello-muse.wav hello.midi
  $0 --keep piece.mid
EOF
}

resolve_midi() {
  local base="$1"
  if [[ -f "$base" ]]; then
    printf '%s\n' "$base"
    return
  fi
  if [[ -f "${base%.midi}.mid" ]]; then
    printf '%s\n' "${base%.midi}.mid"
    return
  fi
  if [[ -f "${base%.mid}.midi" ]]; then
    printf '%s\n' "${base%.mid}.midi"
    return
  fi
  echo "error: MIDI file not found: $1" >&2
  exit 1
}

wav_path_for_midi() {
  local midi="$1"
  if [[ -n "$OUTPUT_WAV" ]]; then
    printf '%s\n' "$OUTPUT_WAV"
    return
  fi
  if [[ "$KEEP_WAV" == "1" ]]; then
    printf '%s\n' "${midi%.*}.muse.wav"
    return
  fi
  printf '%s\n' "$(mktemp /tmp/muse-keys-XXXXXX).wav"
}

should_keep_wav() {
  [[ -n "$OUTPUT_WAV" || "$KEEP_WAV" == "1" ]]
}

trim_midi_by_bars() {
  local midi_file="$1"
  if [[ ! -x "$PYTHON" ]]; then
    PYTHON="$(command -v python3)"
  fi
  if [[ ! -f "$TRIM_MIDI" ]]; then
    echo "error: trim script not found: $TRIM_MIDI" >&2
    exit 1
  fi
  TRIMMED_MIDI="$(mktemp /tmp/trimmed-XXXXXX).midi"
  local trim_args=(--from-bar "$FROM_BAR")
  if [[ -n "$TO_BAR" ]]; then
    trim_args+=(--to-bar "$TO_BAR")
  fi
  echo "Trimming MIDI to bars ${FROM_BAR}${TO_BAR:+-$TO_BAR} ..." >&2
  "$PYTHON" "$TRIM_MIDI" "$midi_file" "$TRIMMED_MIDI" "${trim_args[@]}"
  printf '%s\n' "$TRIMMED_MIDI"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o | --output)
      if [[ $# -lt 2 ]]; then
        echo "error: $1 requires a file path" >&2
        exit 1
      fi
      OUTPUT_WAV="$2"
      shift 2
      ;;
    --keep)
      KEEP_WAV=1
      shift
      ;;
    --from-bar)
      if [[ $# -lt 2 ]]; then
        echo "error: $1 requires a bar number" >&2
        exit 1
      fi
      FROM_BAR="$2"
      shift 2
      ;;
    --to-bar)
      if [[ $# -lt 2 ]]; then
        echo "error: $1 requires a bar number" >&2
        exit 1
      fi
      TO_BAR="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ -n "$OUTPUT_WAV" && "$KEEP_WAV" == "1" ]]; then
  echo "error: use either -o or --keep, not both" >&2
  exit 1
fi

if [[ -n "$OUTPUT_WAV" && $# -gt 1 ]]; then
  echo "error: -o can only be used with a single MIDI file" >&2
  exit 1
fi

if [[ -n "$FROM_BAR" && ! "$FROM_BAR" =~ ^-?[1-9][0-9]*$ ]]; then
  echo "error: --from-bar must be a non-zero integer" >&2
  exit 1
fi

if [[ -n "$TO_BAR" && ! "$TO_BAR" =~ ^-?[1-9][0-9]*$ ]]; then
  echo "error: --to-bar must be a non-zero integer" >&2
  exit 1
fi

if [[ -n "$TO_BAR" && -z "$FROM_BAR" ]]; then
  FROM_BAR=1
fi

if [[ ! -x "$MSCORE" ]]; then
  echo "error: MuseScore 4 not found at $MSCORE" >&2
  exit 1
fi

if [[ ! -d "$MUSE_KEYS_DIR" ]]; then
  echo "error: Muse Keys not found at:" >&2
  echo "  $MUSE_KEYS_DIR" >&2
  echo "Install Muse Keys from Muse Hub, then try again." >&2
  exit 1
fi

for arg in "$@"; do
  midi_file="$(resolve_midi "$arg")"
  if [[ -n "$FROM_BAR" || -n "$TO_BAR" ]]; then
    midi_file="$(trim_midi_by_bars "$midi_file")"
  fi
  wav_file="$(wav_path_for_midi "$midi_file")"

  if [[ -n "$OUTPUT_WAV" ]]; then
    out_dir="$(dirname "$OUTPUT_WAV")"
    if [[ "$out_dir" != "." && "$out_dir" != "$OUTPUT_WAV" ]]; then
      mkdir -p "$out_dir"
    fi
  fi

  echo "Rendering $midi_file with Muse Keys ..."
  "$MSCORE" -o "$wav_file" --sound-profile MuseSounds "$midi_file"

  echo "Playing $wav_file ..."
  afplay "$wav_file"

  if should_keep_wav; then
    echo "Saved $wav_file"
  else
    rm -f "$wav_file"
  fi
  if [[ -n "$TRIMMED_MIDI" ]]; then
    rm -f "$TRIMMED_MIDI"
    TRIMMED_MIDI=""
  fi
done
