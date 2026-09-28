#!/usr/bin/env python3
"""Trim a MIDI file to a bar range (1-based, inclusive)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import mido


def ticks_per_bar(ticks_per_beat: int, numerator: int, denominator: int) -> int:
    # MIDI denominator is the note value that gets one beat (e.g. 4 = quarter).
    return int(ticks_per_beat * numerator * 4 / denominator)


def first_time_signature(mid: mido.MidiFile) -> tuple[int, int]:
    for track in mid.tracks:
        for msg in track:
            if msg.type == "time_signature":
                return msg.numerator, msg.denominator
    return 4, 4


def max_tick(mid: mido.MidiFile) -> int:
    highest = 0
    for track in mid.tracks:
        abs_tick = 0
        for msg in track:
            abs_tick += msg.time
            highest = max(highest, abs_tick)
    return highest


def total_bars(mid: mido.MidiFile) -> int:
    numerator, denominator = first_time_signature(mid)
    bar_ticks = ticks_per_bar(mid.ticks_per_beat, numerator, denominator)
    if bar_ticks <= 0:
        raise ValueError("invalid time signature in MIDI file")
    last_tick = max_tick(mid)
    if last_tick == 0:
        return 0
    return (last_tick - 1) // bar_ticks + 1


def resolve_bar(bar: int, total: int, label: str) -> int:
    if bar == 0:
        raise ValueError(f"{label} cannot be 0")
    if total <= 0:
        raise ValueError("MIDI file has no bars to trim")
    if bar < 0:
        bar = total + bar + 1
    if bar < 1 or bar > total:
        raise ValueError(
            f"{label} {bar} out of range; piece has {total} bars "
            f"(use 1..{total} or -1 for last bar)"
        )
    return bar


def is_note_on(msg: mido.Message | mido.MetaMessage) -> bool:
    return msg.type == "note_on" and msg.velocity > 0


def is_note_off(msg: mido.Message | mido.MetaMessage) -> bool:
    return msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0)


def trim_track(
    track: mido.MidiTrack,
    start_tick: int,
    end_tick: int | None,
) -> mido.MidiTrack:
    out = mido.MidiTrack()
    abs_tick = 0
    kept_abs = 0
    pending_meta_before_start: list[mido.Message | mido.MetaMessage] = []
    # Sounding notes, keyed by (channel, note), valued by their note_on message.
    sounding: dict[tuple[int, int], mido.Message] = {}
    started = False

    for msg in track:
        abs_tick += msg.time
        # Note-offs landing exactly on the start belong to notes that ended before it.
        if abs_tick < start_tick or (abs_tick == start_tick and is_note_off(msg)):
            if msg.is_meta and msg.type in ("time_signature", "set_tempo", "key_signature"):
                pending_meta_before_start = [m for m in pending_meta_before_start if m.type != msg.type]
                pending_meta_before_start.append(msg.copy())
            elif is_note_on(msg):
                sounding[(msg.channel, msg.note)] = msg
            elif is_note_off(msg):
                sounding.pop((msg.channel, msg.note), None)
            continue
        if end_tick is not None and abs_tick >= end_tick:
            break

        if not started:
            # Re-strike notes held across the start (e.g. tied chords).
            for held in sounding.values():
                out.append(held.copy(time=0))
            started = True

        if is_note_on(msg):
            sounding[(msg.channel, msg.note)] = msg
        elif is_note_off(msg):
            sounding.pop((msg.channel, msg.note), None)

        shifted = abs_tick - start_tick
        delta = shifted - kept_abs
        kept_abs = shifted
        out.append(msg.copy(time=delta))

    # A note held through the whole range has no events inside it.
    if not started and sounding and abs_tick >= start_tick:
        for held in sounding.values():
            out.append(held.copy(time=0))
        started = True

    # Release notes still held at the end of the range, which would otherwise
    # have no note_off and be played as a short blip.
    if started and end_tick is not None:
        for index, (channel, note) in enumerate(sounding):
            delta = end_tick - start_tick - kept_abs if index == 0 else 0
            out.append(mido.Message("note_off", channel=channel, note=note, velocity=0, time=delta))

    if not out and not pending_meta_before_start:
        return out

    # Preserve tempo/meter at the start of the trimmed region, even if this
    # track otherwise has no events in range (e.g. a tempo-only meta track
    # when trimming to a range that doesn't include any other meta changes).
    if pending_meta_before_start:
        rebuilt = mido.MidiTrack()
        for meta in pending_meta_before_start:
            rebuilt.append(meta.copy(time=0))
        for msg in out:
            rebuilt.append(msg.copy(time=msg.time))
        return rebuilt

    return out


def trim_midi(
    mid: mido.MidiFile,
    from_bar: int,
    to_bar: int | None,
) -> mido.MidiFile:
    total = total_bars(mid)
    from_bar = resolve_bar(from_bar, total, "from-bar")
    if to_bar is not None:
        to_bar = resolve_bar(to_bar, total, "to-bar")
    if to_bar is not None and to_bar < from_bar:
        raise ValueError(f"to-bar ({to_bar}) must be >= from-bar ({from_bar})")

    numerator, denominator = first_time_signature(mid)
    bar_ticks = ticks_per_bar(mid.ticks_per_beat, numerator, denominator)
    start_tick = (from_bar - 1) * bar_ticks
    end_tick = None if to_bar is None else to_bar * bar_ticks

    out = mido.MidiFile(type=mid.type, ticks_per_beat=mid.ticks_per_beat)
    out.tracks = [trim_track(track, start_tick, end_tick) for track in mid.tracks]
    return out


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a MIDI file containing only the requested bar range."
    )
    parser.add_argument("input", type=Path, help="input MIDI file")
    parser.add_argument(
        "output",
        type=Path,
        nargs="?",
        help="output MIDI file (not used with --resolve-bar)",
    )
    parser.add_argument(
        "--resolve-bar",
        type=int,
        metavar="N",
        help="print resolved bar number for N and exit (supports negative bars)",
    )
    parser.add_argument(
        "--from-bar",
        type=int,
        help="first bar to keep (1-based; negative counts from end, -1 = last bar)",
    )
    parser.add_argument(
        "--to-bar",
        type=int,
        help="last bar to keep (1-based; negative counts from end); default: through end",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.input.is_file():
        print(f"error: input not found: {args.input}", file=sys.stderr)
        return 1

    mid = mido.MidiFile(args.input)

    if args.resolve_bar is not None:
        try:
            resolved = resolve_bar(args.resolve_bar, total_bars(mid), "bar")
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        print(resolved)
        return 0

    if args.from_bar is None:
        print("error: --from-bar is required unless --resolve-bar is used", file=sys.stderr)
        return 1
    if args.output is None:
        print("error: output MIDI path is required unless --resolve-bar is used", file=sys.stderr)
        return 1

    try:
        trimmed = trim_midi(mid, args.from_bar, args.to_bar)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    trimmed.save(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
