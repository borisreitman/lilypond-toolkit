#!/usr/bin/env bash
# Entrypoint for lilypond-toolkit.
#
# Install once, globally:
#
#   cp doc/lilypond-toolkit.sample.sh ~/bin/lilypond-toolkit
#   chmod +x ~/bin/lilypond-toolkit
#
# (make sure ~/bin is on PATH). Then, per score project that needs
# non-default config (a different TOOLKIT_HOME, or MuseScore/Muse Keys at a
# non-default install path), copy doc/.env.example to that project's root
# as ./.env and edit it — it's loaded from the current directory, not from
# wherever this script lives, so each project can override independently.
#
# Run tools from a score project's root, e.g.:
#
#   lilypond-toolkit compile hello.ly
#   lilypond-toolkit play score/waltz.ly --from-bar 21 --to-bar 24
#
# No symlinks or per-project venv needed: this just forwards to the
# scripts in TOOLKIT_HOME, which use TOOLKIT_HOME's own .venv for anything
# that needs Python.
set -euo pipefail

# Load ./.env from the current directory (the score project's root), if
# present. Anything it sets (TOOLKIT_HOME, MSCORE, MUSESCORE_APP,
# MUSE_KEYS_DIR, ...) is exported so it also reaches the scripts this
# dispatches to. See doc/.env.example in lilypond-toolkit.
if [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source ".env"
  set +a
fi

TOOLKIT_HOME="${TOOLKIT_HOME:-$HOME/Documents/my-music-scores/lilypond-toolkit}"

SCRIPTS="${TOOLKIT_HOME}/scripts"
PYTHON="${TOOLKIT_HOME}/.venv/bin/python"

usage() {
  cat <<EOF
Usage: $0 <command> [args...]

Commands:
  compile <score.ly...>          Compile to PDF (and MIDI if \\midi{} present)
  play <score.ly...>              Compile and play with Muse Keys
  play-midi <file.mid|.midi>      Play a MIDI file with Muse Keys
  mp3 <score.ly>                  Render an MP3 (no playback)
  musescore <score.ly...>         Compile and open in MuseScore
  wav-to-ly <recording.wav...>    Transcribe audio to a draft .ly
  wav-to-midi <recording.wav...>  Transcribe audio to MIDI only
  midi-to-ly <file.mid...>        Convert MIDI to a draft .ly
  remove-hum <recording.wav>      Strip background hum from audio
  simplify-musicxml <in> <out>    Simplify a MusicXML transcription
  trim-midi <in.mid> <out.mid>    Trim a MIDI file to a bar range

Run "$0 <command> --help" for a command's own options.
EOF
}

if [[ ! -d "$TOOLKIT_HOME" ]]; then
  echo "error: TOOLKIT_HOME not found: $TOOLKIT_HOME" >&2
  echo "Edit TOOLKIT_HOME at the top of this script." >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

cmd="$1"
shift

case "$cmd" in
  compile)             exec "${SCRIPTS}/compile-ly.sh" "$@" ;;
  play)                exec "${SCRIPTS}/play-ly.sh" "$@" ;;
  play-midi)           exec "${SCRIPTS}/play-midi.sh" "$@" ;;
  mp3)                 exec "${SCRIPTS}/ly-to-mp3.sh" "$@" ;;
  musescore)           exec "${SCRIPTS}/to-musescore.sh" "$@" ;;
  wav-to-ly)           exec "${SCRIPTS}/wav-to-ly.sh" "$@" ;;
  wav-to-midi)         exec "${SCRIPTS}/wav-to-midi.sh" "$@" ;;
  midi-to-ly)          exec "${SCRIPTS}/midi-to-ly.sh" "$@" ;;
  remove-hum)          exec "${SCRIPTS}/remove-hum.sh" "$@" ;;
  simplify-musicxml)   exec python3 "${SCRIPTS}/simplify_musicxml.py" "$@" ;;
  trim-midi)           exec "${PYTHON}" "${SCRIPTS}/trim_midi_bars.py" "$@" ;;
  -h | --help)         usage; exit 0 ;;
  *)
    echo "error: unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
