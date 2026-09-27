# lilypond-toolkit

Shared scripts and LilyPond include files for composing with LilyPond —
compiling, playback (Muse Keys), MP3 export, MuseScore round-tripping, and
audio-to-notation transcription. Meant to be shared across score projects
rather than copied into each one: one Python venv here serves every project,
and a single `lilypond-toolkit` command installed once on `PATH` forwards to
it from any project's root.

## Layout

```
scripts/                             compile, play, export, and transcription scripts
includes/                            .ly snippets meant to be \include'd from score files
doc/lilypond-toolkit.sample.sh       template entrypoint for a score project to copy in
doc/.env.example                     template config for that entrypoint
doc/lilypond-toolkit-completion.bash bash tab-completion for the entrypoint's subcommands
.venv/                               shared Python environment (created once, see below)
```

## Setup

**Once per machine** — install the entrypoint globally:

```bash
cp doc/lilypond-toolkit.sample.sh ~/bin/lilypond-toolkit
chmod +x ~/bin/lilypond-toolkit
```

(`~/bin` must be on `PATH`; use any other directory that already is if you
don't use `~/bin`.) This is the only thing every project shares — one copy
of the entrypoint, forwarding to this repo's `scripts/` and `.venv/`.

**Once per score project** — only if that project needs something other
than the entrypoint's built-in default (`TOOLKIT_HOME` at
`~/Documents/my-music-scores/lilypond-toolkit`, and MuseScore/Muse Keys at
their standard install paths). Copy the template and edit what differs:

```bash
cd ~/Documents/my-music-scores/lilypond-scores
cp ~/Documents/my-music-scores/lilypond-toolkit/doc/.env.example .env
```

`lilypond-toolkit` sources `./.env` from the current directory (the score
project's root) if present, and exports whatever it sets — `TOOLKIT_HOME`,
`MSCORE`, `MUSESCORE_APP`, `MUSE_KEYS_DIR` — so nothing needs to be edited
in the entrypoint script itself, and different projects can point at
different toolkit checkouts if needed. Keep `.env` out of git (it's
machine-specific); anything you leave out of it falls back to the
entrypoint's or the toolkit scripts' own defaults.

**Then, from any score project's root:**

```bash
lilypond-toolkit compile hello.ly
lilypond-toolkit play score/waltz.ly --from-bar 21 --to-bar 24
lilypond-toolkit --help                # full command list
```

No symlinks or per-project venv needed. `.ly` files can `\include` snippets
from `includes/` by bare filename — `compile`, `play`, `mp3`, and
`musescore` all pass `-I` pointing at this repo's `includes/` folder to
`lilypond`, e.g. from `score/waltz.ly`:

```
\include "play-from-bar-mark.ly"
```

**Optional — bash tab-completion** for the subcommand name only (`compile`,
`play`, `mp3`, ...). Filename arguments after that fall through to bash's
normal filename completion instead of a hand-rolled one, so directories,
spaces, and quoting all behave exactly like they do everywhere else:

```bash
# if ~/.bashrc already auto-sources ~/.bash_completion.d/*:
cp doc/lilypond-toolkit-completion.bash ~/.bash_completion.d/lilypond-toolkit

# otherwise, add this line to ~/.bashrc:
source ~/Documents/my-music-scores/lilypond-toolkit/doc/lilypond-toolkit-completion.bash
```

Open a new shell (or `source` the file directly) to pick it up.

## Requirements

- **LilyPond 2.26.0** (installed via Homebrew)
- **macOS** (Apple Silicon)

MacTeX is **not** required for standalone `.ly` files.

```bash
brew install lilypond
lilypond --version
which lilypond   # /opt/homebrew/bin/lilypond
```

## Scripts

The examples below use `lilypond-toolkit <command>`, run from a score
project's root (see **Setup** above). Output files land next to your score
files; the scripts themselves and the shared `.venv` stay in this repo.

### Compile

```bash
lilypond-toolkit compile hello.ly              # → hello.pdf
lilypond-toolkit compile --open hello.ly       # compile and open in Preview
lilypond hello.ly                       # same, directly
lilypond -o my-output hello.ly          # custom output basename
```

### Play MIDI (Muse Keys)

Play a `.mid`/`.midi` file using **MuseScore Studio** and the MuseSounds
profile (Grand Piano from Muse Keys):

```bash
lilypond-toolkit play-midi hello.midi
lilypond-toolkit play-midi -o playback/hello-muse.wav hello.midi   # save wav
lilypond-toolkit play-midi --keep piece.mid                        # save next to .mid
```

From a `.ly` file (compile, then play with Muse Keys):

```bash
lilypond-toolkit play hello.ly
lilypond-toolkit play --keep hello.ly       # keep hello.muse.wav
lilypond-toolkit play --from-bar 21 --to-bar 24 score/waltz.ly             # bars as printed
lilypond-toolkit play --offset 14 --from-bar 53 --to-bar 54 score/waltz.ly # after a 14-bar repeat
```

Export an MP3 (compile, render with Muse Keys, encode with ffmpeg; no
playback):

```bash
lilypond-toolkit mp3 score/waltz.ly            # -> score/<name>-<timestamp>.mp3
lilypond-toolkit mp3 -d output score/waltz.ly  # -> output/<name>-<timestamp>.mp3
```

The output name is `<name-prefix><title>-<YYYY-MM-DD-HHMM>.mp3`, with the
title taken from the score's `\header`. See `scripts/ly-to-mp3.sh` for the
prefix.

`--offset K` adds K to positive `--from-bar`/`--to-bar` values so you can
keep the bar numbers printed in the sheet when earlier repeats are unfolded
in the MIDI. Pass it once per repeated section (offsets are summed).

Requires Muse Keys installed from [Muse Hub](https://www.musehub.com/).

#### How the scripts find MuseScore and Muse Keys

`play-ly.sh`, `play-midi.sh`, and `ly-to-mp3.sh` check two things before
rendering:

1. **MuseScore 4 Studio** — the CLI must exist at:

   ```
   /Applications/MuseScore 4.app/Contents/MacOS/mscore
   ```

   Install with `brew install --cask musescore` or from
   [musescore.org](https://musescore.org). Muse Sounds playback requires
   **MuseScore Studio** (not the free MuseScore 3).

2. **Muse Keys** — the scripts verify that Muse Hub has downloaded the
   instrument pack to:

   ```
   ~/Library/Application Support/Muse Hub/Downloads/Instruments/Muse Keys/
   ```

   After installing **Muse Keys** from Muse Hub, that folder should contain
   instrument subfolders (e.g. `Piano/`, `Harpsichord/`). If the directory is
   missing, the script exits with an install reminder.

Rendering uses MuseScore's **MuseSounds** profile — the scripts do not point
at individual `.sf2` files:

```bash
mscore -o output.wav --sound-profile MuseSounds input.mid
```

Verify on your machine:

```bash
test -x "/Applications/MuseScore 4.app/Contents/MacOS/mscore" && echo "MuseScore OK"
test -d "$HOME/Library/Application Support/Muse Hub/Downloads/Instruments/Muse Keys" && echo "Muse Keys OK"
```

For interactive playback in the app (no WAV render step), open a MIDI file
in MuseScore and press **Space**. Set **Home → Playback setup → Sound
profile** to **MuseSounds**.

### Export MIDI and open in MuseScore

```bash
lilypond hello.ly
open -a "MuseScore 4" hello.midi
```

Or use the helper command (compile + open in one step):

```bash
lilypond-toolkit musescore hello.ly
lilypond-toolkit musescore score1.ly score2.ly
```

In MuseScore: **Space** to play, **File → Save As** to save as `.mscz`.

### Transcribe audio to LilyPond (ByteDance)

Turn a piano recording (`.wav`, `.mp3`, etc.) into a **draft** `.ly` file:

```
recording.wav  →  MIDI (ByteDance)  →  .ly (midi_to_ly.py)  →  lilypond  →  PDF
```

Best for **solo piano**, clean recordings, steady tempo. Expect to edit the
`.ly` file — rhythms, key, and hand split are approximate.

Install once, in this repo (the venv is shared by every score project):

```bash
cd ~/Documents/my-music-scores/lilypond-toolkit
brew install python@3.12 ffmpeg
python3.12 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

The ByteDance model checkpoint (~165 MB) downloads on first run to
`~/piano_transcription_inference_data/`.

Audio → LilyPond in one step:

```bash
lilypond-toolkit wav-to-ly my-piano-take.wav
lilypond my-piano-take.ly && open my-piano-take.pdf
```

Or step by step:

```bash
lilypond-toolkit wav-to-midi my-piano-take.wav     # → my-piano-take.mid
lilypond-toolkit midi-to-ly my-piano-take.mid      # → my-piano-take.ly
lilypond my-piano-take.ly && open my-piano-take.pdf
lilypond-toolkit play-midi my-piano-take.mid       # listen with Muse Keys
```

Convert an existing MIDI file (skip transcription):

```bash
lilypond-toolkit midi-to-ly some-tune.mid
```

Tune hand split or quantization (the `midi-to-ly` command doesn't forward
extra flags, so call the converter directly):

```bash
TOOLKIT_HOME=~/Documents/my-music-scores/lilypond-toolkit
"$TOOLKIT_HOME/.venv/bin/python" "$TOOLKIT_HOME/scripts/midi_to_ly.py" tune.mid --split 64 --quant 8
```

### Remove background hum from audio

```bash
lilypond-toolkit remove-hum noisy.wav   # → noisy.cleaned.wav
```

### Simplify MusicXML

```bash
lilypond-toolkit simplify-musicxml input.musicxml output.musicxml
```

### Install optional tools

```bash
brew install python@3.12 ffmpeg     # audio → MIDI transcription (ByteDance)
brew install --cask frescobaldi     # GUI editor with live PDF preview
brew install --cask musescore       # playback (Muse Keys) and score editing
```

## Includes

`.ly` snippets in `includes/` are meant to be `\include`'d from a score
file by bare filename — `lilypond-toolkit compile`/`play`/`mp3`/`musescore`
pass `-I "$TOOLKIT_HOME/includes"` to `lilypond` (see **Setup** above).

- `play-from-bar-mark.ly` — defines `\playBarMark`; insert it in a section
  macro to print a bar-number marker (e.g. `▶ 21`) at that point in the PDF,
  useful for finding where `--from-bar` should start when using
  `lilypond-toolkit play`.

## Documentation

- [Learning manual](https://lilypond.org/doc/v2.26/Documentation/learning/index.html)
- [Notation reference](https://lilypond.org/doc/v2.26/Documentation/notation/index.html)
