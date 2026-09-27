#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MSCORE="${MSCORE:-/Applications/MuseScore 4.app/Contents/MacOS/mscore}"
MUSE_KEYS_DIR="${MUSE_KEYS_DIR:-${HOME}/Library/Application Support/Muse Hub/Downloads/Instruments/Muse Keys}"
NAME_PREFIX="boris-reitman-"
OUTPUT_DIR=""
QUALITY=2

usage() {
  cat <<EOF
Usage: $0 [-d output-dir] [-q quality] score.ly

Compile LilyPond, render the MIDI with Muse Keys (MuseScore's MuseSounds
engine), and encode an MP3. Nothing is played.

The MP3 is always named ${NAME_PREFIX}<title>-<YYYY-MM-DD-HHMM>.mp3, where
<title> comes from the score's \\header { title = "..." } (or the .ly file
name if there is none) and the timestamp is the export time.

Requires:
  - MuseScore 4 Studio
  - Muse Keys installed in Muse Hub
  - ffmpeg (brew install ffmpeg)

Options:
  -d, --dir DIR       Write the MP3 into DIR (default: next to the .ly file)
  -q, --quality N     LAME VBR quality, 0 (best) to 9 (smallest); default 2

Examples:
  $0 score/waltz.ly             # -> score/${NAME_PREFIX}teen-waltz-2026-09-24-0215.mp3
  $0 -d output score/waltz.ly   # -> output/${NAME_PREFIX}teen-waltz-2026-09-24-0215.mp3
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d | --dir)
      if [[ $# -lt 2 ]]; then
        echo "error: $1 requires a directory" >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -q | --quality)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]$ ]]; then
        echo "error: $1 requires a number from 0 to 9" >&2
        exit 1
      fi
      QUALITY="$2"
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

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

ly_file="$1"
if [[ ! -f "$ly_file" ]]; then
  echo "error: file not found: $ly_file" >&2
  exit 1
fi

for tool in lilypond ffmpeg; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not found. Install with: brew install $tool" >&2
    exit 1
  fi
done

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

base="${ly_file%.ly}"

# Name from the header title (first title = "..." in the file), else the file name.
title="$(sed -n 's/^[[:space:]]*title[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ly_file" | head -n 1)"
if [[ -z "$title" ]]; then
  title="$(basename "$base")"
fi
slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
out_dir="${OUTPUT_DIR:-$(dirname "$ly_file")}"
mkdir -p "$out_dir"
mp3_file="${out_dir}/${NAME_PREFIX}${slug}-$(date +%Y-%m-%d-%H%M).mp3"
wav_file="$(mktemp /tmp/muse-keys-XXXXXX).wav"
trap 'rm -f "$wav_file"' EXIT

echo "Compiling $ly_file ..."
lilypond -I "${ROOT_DIR}/includes" -o "$base" "$ly_file"

if [[ -f "${base}.midi" ]]; then
  midi_file="${base}.midi"
elif [[ -f "${base}.mid" ]]; then
  midi_file="${base}.mid"
else
  echo "error: no MIDI output for $ly_file" >&2
  echo "Add a \\midi { } block inside \\score { } in the .ly file." >&2
  exit 1
fi

echo "Rendering with Muse Keys (MuseSounds) ..."
"$MSCORE" -o "$wav_file" --sound-profile MuseSounds "$midi_file"

echo "Encoding $mp3_file ..."
ffmpeg -hide_banner -loglevel error -y -i "$wav_file" \
  -codec:a libmp3lame -qscale:a "$QUALITY" "$mp3_file"

echo "Wrote $mp3_file"
