#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OPEN_PDF=0

usage() {
  cat <<EOF
Usage: $0 [--open] score.ly [score2.ly ...]

Compile LilyPond files to PDF (and MIDI if \\midi { } is present).

Options:
  --open   Open each PDF in Preview after compiling

Example:
  $0 hello.ly
  $0 --open output/my-piece.ly
  lilypond -o custom-name hello.ly   # custom basename via lilypond directly
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_PDF=1
      shift
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

if ! command -v lilypond >/dev/null 2>&1; then
  echo "error: lilypond not found. Install with: brew install lilypond" >&2
  exit 1
fi

for ly_file in "$@"; do
  if [[ ! -f "$ly_file" ]]; then
    echo "error: file not found: $ly_file" >&2
    exit 1
  fi
  if [[ "${ly_file##*.}" != "ly" ]]; then
    echo "error: not a LilyPond file: $ly_file" >&2
    exit 1
  fi

  base="${ly_file%.ly}"
  echo "Compiling $ly_file ..."
  # LilyPond writes PDF/MIDI to cwd unless -o sets the output basename (with path).
  lilypond -I "${ROOT_DIR}/includes" -o "$base" "$ly_file"

  pdf_file="${base}.pdf"
  if [[ "$OPEN_PDF" == "1" ]]; then
    echo "Opening $pdf_file ..."
    open "$pdf_file"
  else
    echo "Wrote $pdf_file"
  fi
done
