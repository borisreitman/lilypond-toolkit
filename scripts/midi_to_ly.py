#!/usr/bin/env python3
"""Convert a piano MIDI file to a draft LilyPond score."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import pretty_midi

LILYPOND_VERSION = "2.26.0"
NOTE_NAMES = ("c", "d", "e", "f", "g", "a", "b")
MIN_REST_BEATS = 0.25
MIN_NOTE_BEATS = 0.125


@dataclass(frozen=True)
class Event:
    start: float
    duration: float
    pitches: tuple[int, ...]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("midi_file", type=Path, help="input MIDI file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="output .ly file (default: <midi-stem>.ly next to input)",
    )
    parser.add_argument(
        "--title",
        help="score title (default: derived from filename)",
    )
    parser.add_argument(
        "--split",
        type=int,
        default=60,
        metavar="PITCH",
        help="notes at or above this MIDI pitch go to the right hand (default: 60)",
    )
    parser.add_argument(
        "--quant",
        type=int,
        default=8,
        metavar="DIV",
        help="quantize rhythms to 1/DIV of a quarter note (default: 8 = eighth)",
    )
    parser.add_argument(
        "--time",
        default="",
        help="time signature (default: read from MIDI, else 4/4)",
    )
    parser.add_argument(
        "--key",
        default="c \\major",
        help='LilyPond key command (default: "c \\\\major")',
    )
    return parser.parse_args()


def collect_notes(midi: pretty_midi.PrettyMIDI) -> list[pretty_midi.Note]:
    notes: list[pretty_midi.Note] = []
    for instrument in midi.instruments:
        if instrument.is_drum:
            continue
        notes.extend(instrument.notes)
    return sorted(notes, key=lambda note: (note.start, note.pitch))


def estimate_bpm(midi: pretty_midi.PrettyMIDI) -> float:
    _, tempo = midi.get_tempo_changes()
    if len(tempo) > 0 and tempo[0] > 0:
        return float(tempo[0])
    estimated = midi.estimate_tempo()
    if estimated:
        return float(estimated)
    return 120.0


def time_signature(midi: pretty_midi.PrettyMIDI, override: str) -> str:
    if override:
        return override
    if midi.time_signature_changes:
        ts = midi.time_signature_changes[0]
        return f"{ts.numerator}/{ts.denominator}"
    return "4/4"


def quantize_time(value: float, bpm: float, divisions: int) -> float:
    step = 60.0 / (bpm * divisions)
    return round(value / step) * step


def beats(duration_seconds: float, bpm: float) -> float:
    return duration_seconds * bpm / 60.0


def quantize_duration(duration_seconds: float, bpm: float, divisions: int) -> float:
    step_beats = 1.0 / divisions
    duration_beats = beats(duration_seconds, bpm)
    if duration_beats <= 0:
        return step_beats
    quantized = max(step_beats, round(duration_beats / step_beats) * step_beats)
    return max(quantized, MIN_NOTE_BEATS)


def midi_pitch_to_lily(pitch: int) -> str:
    name = pretty_midi.note_number_to_name(pitch)
    match = re.fullmatch(r"([A-G])(#|b)?(\d+)", name)
    if not match:
        raise ValueError(f"unexpected pitch name: {name}")

    letter, accidental, octave = match.groups()
    lily = NOTE_NAMES["CDEFGAB".index(letter)]
    if accidental == "#":
        lily += "is"
    elif accidental == "b":
        lily += "es"

    markers = int(octave) - 3
    if markers > 0:
        lily += "'" * markers
    elif markers < 0:
        lily += "," * (-markers)
    return lily


def duration_to_lily(duration_beats: float) -> str:
    duration_beats = max(duration_beats, MIN_NOTE_BEATS)
    candidates: list[tuple[float, str]] = []
    for denom in (1, 2, 4, 8, 16, 32):
        for dotted in (False, True):
            length = (4.0 / denom) * (1.5 if dotted else 1.0)
            suffix = "." if dotted else ""
            candidates.append((abs(duration_beats - length), f"{denom}{suffix}"))
    return min(candidates, key=lambda item: (item[0], item[1]))[1]


def dedupe_pitch_classes(notes: list[pretty_midi.Note]) -> list[pretty_midi.Note]:
    best: dict[int, pretty_midi.Note] = {}
    for note in notes:
        pc = note.pitch % 12
        current = best.get(pc)
        if current is None or (note.end - note.start) > (current.end - current.start):
            best[pc] = note
    return sorted(best.values(), key=lambda note: note.pitch)


def filter_short_notes(
    notes: list[pretty_midi.Note], bpm: float, min_beats: float = MIN_NOTE_BEATS
) -> list[pretty_midi.Note]:
    min_seconds = min_beats * 60.0 / bpm
    return [note for note in notes if note.end - note.start >= min_seconds]


def group_staff_events(
    notes: list[pretty_midi.Note],
    bpm: float,
    divisions: int,
) -> list[Event]:
    if not notes:
        return []

    grouped: dict[float, list[pretty_midi.Note]] = {}
    for note in notes:
        start = quantize_time(note.start, bpm, divisions)
        grouped.setdefault(start, []).append(note)

    events: list[Event] = []
    for start, matching in sorted(grouped.items()):
        deduped = dedupe_pitch_classes(matching)
        pitches = tuple(note.pitch for note in deduped)
        end = max(note.end for note in deduped)
        duration = quantize_duration(end - start, bpm, divisions)
        events.append(Event(start=start, duration=duration, pitches=pitches))
    return events


def split_notes(
    notes: list[pretty_midi.Note], split_pitch: int
) -> tuple[list[pretty_midi.Note], list[pretty_midi.Note]]:
    right = [note for note in notes if note.pitch >= split_pitch]
    left = [note for note in notes if note.pitch < split_pitch]
    return right, left


def render_staff(events: list[Event], bpm: float, beats_per_bar: float) -> str:
    if not events:
        return "r1"

    parts: list[str] = []
    cursor = 0.0
    bars_done = 0

    def maybe_bars(end_seconds: float) -> None:
        nonlocal bars_done
        end_beats = beats(end_seconds, bpm)
        target_bars = int(end_beats / beats_per_bar + 0.001)
        while bars_done < target_bars:
            parts.append("|")
            bars_done += 1

    for event in events:
        gap_beats = beats(event.start - cursor, bpm)
        if gap_beats >= MIN_REST_BEATS:
            parts.append(f"r{duration_to_lily(gap_beats)}")
            cursor += gap_beats * 60.0 / bpm
            maybe_bars(cursor)

        chord = " ".join(midi_pitch_to_lily(pitch) for pitch in event.pitches)
        dur = duration_to_lily(event.duration)
        if len(event.pitches) > 1:
            parts.append(f"<{chord}>{dur}")
        else:
            parts.append(f"{chord}{dur}")

        cursor = event.start + event.duration
        maybe_bars(cursor)

    while parts and parts[-1] == "|":
        parts.pop()

    music = " ".join(parts)
    while "| |" in music:
        music = music.replace("| |", "|")
    return music


def beats_per_bar(time_signature: str) -> float:
    num, den = time_signature.split("/")
    return float(num) * (4.0 / float(den))


def escape_lily_string(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def default_title(path: Path) -> str:
    stem = path.stem
    stem = re.sub(r"_basic_pitch$", "", stem, flags=re.IGNORECASE)
    return stem.replace("_", " ").replace("-", " ").title()


def build_score(
    midi_path: Path,
    title: str,
    split_pitch: int,
    divisions: int,
    time_signature_str: str,
    key: str,
) -> str:
    midi = pretty_midi.PrettyMIDI(str(midi_path))
    bpm = round(estimate_bpm(midi))
    notes = filter_short_notes(collect_notes(midi), bpm)
    right_notes, left_notes = split_notes(notes, split_pitch)
    right_events = group_staff_events(right_notes, bpm, divisions)
    left_events = group_staff_events(left_notes, bpm, divisions)
    bar_beats = beats_per_bar(time_signature_str)
    title_escaped = escape_lily_string(title)

    right_music = render_staff(right_events, bpm, bar_beats)
    left_music = render_staff(left_events, bpm, bar_beats)

    return f"""\\version "{LILYPOND_VERSION}"

\\header {{
  title = "{title_escaped}"
  composer = "Transcribed (draft)"
}}

\\score {{
  \\new PianoStaff <<
    \\new Staff = "RH" {{
      \\clef treble
      \\key {key}
      \\time {time_signature_str}
      \\absolute {{
        {right_music}
      }}
    }}
    \\new Staff = "LH" {{
      \\clef bass
      \\absolute {{
        {left_music}
      }}
    }}
  >>
  \\layout {{ }}
  \\midi {{
    \\tempo 4 = {bpm}
  }}
}}
"""


def main() -> int:
    args = parse_args()
    midi_path = args.midi_file
    if not midi_path.is_file():
        print(f"error: MIDI file not found: {midi_path}", file=sys.stderr)
        return 1

    output_path = args.output
    if output_path is None:
        stem = re.sub(r"\.midi?$", "", midi_path.name, flags=re.IGNORECASE)
        stem = re.sub(r"_basic_pitch$", "", stem, flags=re.IGNORECASE)
        output_path = midi_path.with_name(f"{stem}.ly")

    midi = pretty_midi.PrettyMIDI(str(midi_path))
    title = args.title or default_title(midi_path)
    content = build_score(
        midi_path=midi_path,
        title=title,
        split_pitch=args.split,
        divisions=args.quant,
        time_signature_str=time_signature(midi, args.time),
        key=args.key,
    )
    output_path.write_text(content, encoding="utf-8")
    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
