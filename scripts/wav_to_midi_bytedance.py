#!/usr/bin/env python3
"""Transcribe solo piano audio to MIDI using ByteDance's piano model."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import librosa
import torch
from piano_transcription_inference import PianoTranscription, sample_rate

CHECKPOINT_DIR = Path.home() / "piano_transcription_inference_data"
CHECKPOINT_PATH = CHECKPOINT_DIR / "note_F1=0.9677_pedal_F1=0.9186.pth"
CHECKPOINT_URL = (
    "https://zenodo.org/record/4034264/files/"
    "CRNN_note_F1%3D0.9677_pedal_F1%3D0.9186.pth?download=1"
)
MIN_CHECKPOINT_BYTES = int(1.6e8)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("audio_file", type=Path, help="input .wav, .mp3, etc.")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="output .mid file (default: <audio-stem>.mid next to input)",
    )
    parser.add_argument(
        "--device",
        choices=("auto", "cpu", "mps", "cuda"),
        default="auto",
        help="inference device (default: auto)",
    )
    return parser.parse_args()


def pick_device(choice: str) -> torch.device:
    if choice == "cpu":
        return torch.device("cpu")
    if choice == "cuda":
        return torch.device("cuda")
    if choice == "mps":
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def ensure_checkpoint() -> Path:
    CHECKPOINT_DIR.mkdir(parents=True, exist_ok=True)
    if CHECKPOINT_PATH.exists() and CHECKPOINT_PATH.stat().st_size >= MIN_CHECKPOINT_BYTES:
        return CHECKPOINT_PATH

    print(f"Downloading model checkpoint (~165 MB) to {CHECKPOINT_PATH} ...")
    try:
        import urllib.request

        urllib.request.urlretrieve(CHECKPOINT_URL, CHECKPOINT_PATH)
    except Exception as exc:
        if CHECKPOINT_PATH.exists():
            CHECKPOINT_PATH.unlink()
        print(f"error: failed to download checkpoint: {exc}", file=sys.stderr)
        sys.exit(1)

    if CHECKPOINT_PATH.stat().st_size < MIN_CHECKPOINT_BYTES:
        CHECKPOINT_PATH.unlink(missing_ok=True)
        print("error: downloaded checkpoint looks incomplete", file=sys.stderr)
        sys.exit(1)

    return CHECKPOINT_PATH


def default_output_path(audio_path: Path) -> Path:
    return audio_path.with_suffix(".mid")


def main() -> int:
    args = parse_args()
    audio_path = args.audio_file
    if not audio_path.is_file():
        print(f"error: audio file not found: {audio_path}", file=sys.stderr)
        return 1

    output_path = args.output or default_output_path(audio_path)
    if output_path.exists():
        print(f"error: output already exists: {output_path}", file=sys.stderr)
        return 1

    device = pick_device(args.device)
    checkpoint = ensure_checkpoint()

    print(f"Loading audio: {audio_path}")
    audio, _ = librosa.load(str(audio_path), sr=sample_rate, mono=True)

    print(f"Transcribing with ByteDance piano model on {device} ...")
    transcriptor = PianoTranscription(
        checkpoint_path=str(checkpoint),
        device=device,
    )
    transcriptor.transcribe(audio, str(output_path))

    print(f"Wrote {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
