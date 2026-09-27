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
BAR_OFFSET=0
TRIMMED_MIDI=""

usage() {
  cat <<EOF
Usage: $0 [-o wav-file | --keep] [--from-bar N [--to-bar M]] score.ly [score2.ly ...]

Compile LilyPond and play using Muse Keys (via MuseScore's MuseSounds engine).

Requires:
  - MuseScore 4 Studio
  - Muse Keys installed in Muse Hub

Options:
  -o, --output FILE   Save rendered audio to FILE (kept after playback)
                      Only valid with a single .ly input file.
  --keep              Save rendered .wav next to each .ly file (kept after playback)
  --from-bar N        Play from bar N (1-based; negative counts from end, -1 = last)
  --to-bar M          Stop after bar M (1-based; negative counts from end).
                      With --to-bar alone, playback starts at bar 1.
  --offset K          Add K bars to positive --from-bar/--to-bar values.
                      Repeatable; offsets are summed. Use it to skip unfolded
                      repeats: pass the length of each repeated section so
                      bar numbers stay as printed in the sheet.

Bar numbers follow the score's time signature and \\midi { \\tempo ... } output.
Use LilyPond bar numbers as shown in the PDF (first full bar is 1).
Negative bars count from the end (-1 = last bar, -2 = second-to-last).

Without -o or --keep, audio is written to a temp file in /tmp and deleted after play.

Examples:
  $0 hello.ly
  $0 --from-bar 12 score/waltz.ly
  $0 --to-bar 24 score/waltz.ly
  $0 --from-bar -4 --to-bar -1 score/waltz.ly
  $0 --offset 14 --from-bar 53 --to-bar 54 score/waltz.ly   # after a 14-bar repeat
  $0 -o playback/hello-muse.wav hello.ly
  $0 --keep piece.ly
EOF
}

find_midi() {
  local base="$1"
  if [[ -f "${base}.midi" ]]; then
    printf '%s\n' "${base}.midi"
    return
  fi
  if [[ -f "${base}.mid" ]]; then
    printf '%s\n' "${base}.mid"
    return
  fi
  echo "error: no MIDI output for ${base}.ly" >&2
  echo "Add a \\midi { } block inside \\score { } in the .ly file." >&2
  exit 1
}

wav_path_for_ly() {
  local ly_file="$1"
  local base="${ly_file%.ly}"
  if [[ -n "$OUTPUT_WAV" ]]; then
    printf '%s\n' "$OUTPUT_WAV"
    return
  fi
  if [[ "$KEEP_WAV" == "1" ]]; then
    printf '%s\n' "${base}.muse.wav"
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
    --offset)
      if [[ $# -lt 2 ]]; then
        echo "error: $1 requires a bar count" >&2
        exit 1
      fi
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "error: --offset must be a non-negative integer" >&2
        exit 1
      fi
      BAR_OFFSET=$((BAR_OFFSET + $2))
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
  echo "error: -o can only be used with a single .ly file" >&2
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

# Offsets shift sheet bar numbers to playback bar numbers (after unfolded
# repeats). Negative bars count from the end, so they are left unchanged.
if [[ "$BAR_OFFSET" -gt 0 ]]; then
  if [[ -z "$FROM_BAR" ]]; then
    echo "error: --offset requires --from-bar or --to-bar" >&2
    exit 1
  fi
  if [[ "$FROM_BAR" -gt 0 ]]; then
    FROM_BAR=$((FROM_BAR + BAR_OFFSET))
  fi
  if [[ -n "$TO_BAR" && "$TO_BAR" -gt 0 ]]; then
    TO_BAR=$((TO_BAR + BAR_OFFSET))
  fi
fi

if ! command -v lilypond >/dev/null 2>&1; then
  echo "error: lilypond not found. Install with: brew install lilypond" >&2
  exit 1
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

for ly_file in "$@"; do
  if [[ ! -f "$ly_file" ]]; then
    echo "error: file not found: $ly_file" >&2
    exit 1
  fi

  base="${ly_file%.ly}"
  wav_file="$(wav_path_for_ly "$ly_file")"

  if [[ -n "$OUTPUT_WAV" ]]; then
    out_dir="$(dirname "$OUTPUT_WAV")"
    if [[ "$out_dir" != "." && "$out_dir" != "$OUTPUT_WAV" ]]; then
      mkdir -p "$out_dir"
    fi
  fi

  echo "Compiling $ly_file ..."
  lilypond -I "${ROOT_DIR}/includes" -o "$base" "$ly_file"

  midi_file="$(find_midi "$base")"
  if [[ -n "$FROM_BAR" || -n "$TO_BAR" ]]; then
    midi_file="$(trim_midi_by_bars "$midi_file")"
  fi
  echo "Rendering with Muse Keys (MuseSounds) ..."
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
