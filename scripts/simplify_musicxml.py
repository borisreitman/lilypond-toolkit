#!/usr/bin/env python3
"""Simplify a piano MusicXML transcription to a clean melody + waltz LH."""

from __future__ import annotations

import argparse
import copy
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

STEP_TO_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
PC_TO_STEP = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
MAJOR_THIRD = 4
PERFECT_FIFTH = 7


@dataclass(frozen=True)
class Pitch:
    step: str
    octave: int
    alter: int = 0

    @property
    def midi(self) -> int:
        return (self.octave + 1) * 12 + STEP_TO_PC[self.step] + self.alter

    @property
    def pitch_class(self) -> int:
        return self.midi % 12

    def with_octave(self, octave: int) -> Pitch:
        return Pitch(self.step, octave, self.alter)


@dataclass
class Event:
    onset: int
    duration: int
    pitch: Pitch | None
    staff: int
    voice: int


def parse_pitch(note: ET.Element) -> Pitch | None:
    if note.find("rest") is not None:
        return None
    pitch = note.find("pitch")
    if pitch is None:
        return None
    alter_el = pitch.find("alter")
    alter = int(float(alter_el.text)) if alter_el is not None else 0
    return Pitch(pitch.find("step").text, int(pitch.find("octave").text), alter)


def measure_events(measure: ET.Element, divisions: int) -> list[Event]:
    events: list[Event] = []
    voices: dict[int, int] = {}
    for child in measure:
        if child.tag != "note":
            continue
        voice = int(child.find("voice").text)
        staff = int(child.find("staff").text)
        duration = int(child.find("duration").text)
        if child.find("chord") is None:
            voices[voice] = voices.get(voice, 0)
            onset = voices[voice]
            voices[voice] += duration
        else:
            onset = voices[voice] - duration
        events.append(Event(onset, duration, parse_pitch(child), staff, voice))
    return events


def active_pitch_at(events: list[Event], time: int) -> Pitch | None:
    active = [
        e
        for e in events
        if e.pitch is not None
        and e.pitch.midi >= 60
        and e.onset <= time < e.onset + e.duration
    ]
    if not active:
        return None
    return max(active, key=lambda e: e.pitch.midi).pitch


def melody_events(events: list[Event], divisions: int) -> list[Event]:
    measure_len = divisions * 3
    quarter = divisions
    melody: list[Event] = []

    for beat in range(3):
        onset = beat * quarter
        pitch = active_pitch_at(events, onset)
        if pitch is None and beat == 0:
            pitch = active_pitch_at(events, onset + quarter // 2)
        if pitch is None:
            melody.append(Event(onset, quarter, None, 1, 1))
        else:
            melody.append(Event(onset, quarter, pitch, 1, 1))
    return melody


def infer_root(events: list[Event]) -> int:
    staff2 = [e for e in events if e.staff == 2 and e.pitch is not None]
    if not staff2:
        return 0

    bass = [e for e in staff2 if e.pitch.midi < 55]
    if bass:
        weighted = Counter()
        for event in bass:
            weighted[event.pitch.pitch_class] += event.duration
        return weighted.most_common(1)[0][0]

    weighted = Counter()
    for event in staff2:
        weighted[event.pitch.pitch_class] += event.duration
    return weighted.most_common(1)[0][0]


def triad_pitches(root_pc: int, octave: int) -> list[Pitch]:
    root_midi = (octave + 1) * 12 + root_pc
    third_midi = root_midi + MAJOR_THIRD
    fifth_midi = root_midi + PERFECT_FIFTH
    out = []
    for midi in (root_midi, third_midi, fifth_midi):
        pc = midi % 12
        oct = midi // 12 - 1
        alter = 0
        step = PC_TO_STEP[pc]
        if pc in {1, 3, 6, 8, 10}:
            step = PC_TO_STEP[pc - 1]
            alter = 1
        out.append(Pitch(step, oct, alter))
    return out


def append_note(
    parent: ET.Element,
    pitch: Pitch | None,
    duration: int,
    note_type: str,
    voice: int,
    staff: int,
    *,
    rest: bool = False,
    chord: bool = False,
) -> None:
    note = ET.SubElement(parent, "note")
    if chord:
        ET.SubElement(note, "chord")
    if rest:
        ET.SubElement(note, "rest")
    else:
        pitch_el = ET.SubElement(note, "pitch")
        ET.SubElement(pitch_el, "step").text = pitch.step
        if pitch.alter:
            ET.SubElement(pitch_el, "alter").text = str(pitch.alter)
        ET.SubElement(pitch_el, "octave").text = str(pitch.octave)
    ET.SubElement(note, "duration").text = str(duration)
    ET.SubElement(note, "voice").text = str(voice)
    ET.SubElement(note, "type").text = note_type
    ET.SubElement(note, "staff").text = str(staff)


def rebuild_measure(
    template: ET.Element,
    divisions: int,
    melody: list[Event],
    root_pc: int,
) -> ET.Element:
    measure_len = divisions * 3
    measure = ET.Element("measure", number=template.attrib.get("number", "1"))

    for child in template:
        if child.tag in {"note", "backup", "forward"}:
            continue
        measure.append(copy.deepcopy(child))

    quarter = divisions
    beat_type = "quarter"

    # Right hand: one quarter note per beat (simple waltz melody).
    for event in melody:
        if event.pitch is None:
            append_note(
                measure,
                None,
                event.duration,
                "quarter",
                1,
                1,
                rest=True,
            )
        else:
            append_note(measure, event.pitch, event.duration, "quarter", 1, 1)

    backup = ET.SubElement(measure, "backup")
    ET.SubElement(backup, "duration").text = str(measure_len)

    # Left hand waltz: root, chord, chord (voices 5/6, staff 2)
    root_pitch = triad_pitches(root_pc, 2)[0]
    chord = triad_pitches(root_pc, 4)
    append_note(measure, root_pitch, quarter, beat_type, 5, 2)
    for idx, pitch in enumerate(chord):
        append_note(
            measure,
            pitch,
            quarter,
            beat_type,
            5,
            2,
            chord=idx > 0,
        )
    backup = ET.SubElement(measure, "backup")
    ET.SubElement(backup, "duration").text = str(quarter)
    for idx, pitch in enumerate(chord):
        append_note(
            measure,
            pitch,
            quarter,
            beat_type,
            6,
            2,
            chord=idx > 0,
        )

    return measure


def simplify_part(part: ET.Element) -> None:
    measures = part.findall("measure")
    if not measures:
        return

    divisions = 96
    for measure in measures:
        attrs = measure.find("attributes")
        if attrs is not None:
            div_el = attrs.find("divisions")
            if div_el is not None:
                divisions = int(div_el.text)
                break

    measure_len = divisions * 3
    new_measures = []
    for measure in measures:
        events = measure_events(measure, divisions)
        melody = melody_events(events, divisions)
        root_pc = infer_root(events)
        new_measures.append(rebuild_measure(measure, divisions, melody, root_pc))

    for child in list(part):
        if child.tag == "measure":
            part.remove(child)
    for measure in new_measures:
        part.append(measure)


def simplify_file(input_path: Path, output_path: Path) -> None:
    tree = ET.parse(input_path)
    root = tree.getroot()
    for part in root.findall("part"):
        simplify_part(part)
    tree.write(output_path, encoding="UTF-8", xml_declaration=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("-o", "--output", type=Path)
    args = parser.parse_args()
    output = args.output or args.input.with_suffix(".simple.musicxml")
    simplify_file(args.input, output)
    print(f"Wrote {output}")


if __name__ == "__main__":
    main()
