#!/usr/bin/env python3
"""Remove mains hum (50/60 Hz and harmonics) from an audio recording."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import librosa
import numpy as np
import soundfile as sf
from scipy import signal


def detect_hum_frequency(y: np.ndarray, sr: int) -> float:
    """Pick 50 or 60 Hz based on harmonic energy below 500 Hz."""
    nperseg = min(len(y), sr * 8)
    freqs, power = signal.welch(y, sr, nperseg=nperseg)

    def harmonic_energy(base: float, max_harmonic: int = 8) -> float:
        total = 0.0
        for h in range(1, max_harmonic + 1):
            target = base * h
            if target >= 500:
                break
            idx = int(np.argmin(np.abs(freqs - target)))
            total += power[idx]
        return total

    energy_50 = harmonic_energy(50.0)
    energy_60 = harmonic_energy(60.0)
    return 60.0 if energy_60 >= energy_50 else 50.0


def build_notch_filters(
    hum_hz: float, sr: int, q: float, max_freq: float
) -> list[np.ndarray]:
    """Return SOS notch filters for hum fundamentals and harmonics."""
    filters: list[np.ndarray] = []
    harmonic = 1
    while True:
        freq = hum_hz * harmonic
        if freq >= max_freq or freq >= sr / 2 - 1:
            break
        w0 = freq / (sr / 2)
        b, a = signal.iirnotch(w0, q)
        filters.append(signal.tf2sos(b, a))
        harmonic += 1
    return filters


def remove_hum(
    y: np.ndarray,
    sr: int,
    *,
    hum_hz: float | None = None,
    q: float = 35.0,
    max_notch_hz: float = 1000.0,
    highpass_hz: float = 40.0,
) -> tuple[np.ndarray, float]:
    if y.ndim > 1:
        y = np.mean(y, axis=0)

    if hum_hz is None:
        hum_hz = detect_hum_frequency(y, sr)

    out = y.astype(np.float64, copy=True)
    for sos in build_notch_filters(hum_hz, sr, q, max_notch_hz):
        out = signal.sosfiltfilt(sos, out)

    if highpass_hz > 0:
        sos_hp = signal.butter(2, highpass_hz, btype="highpass", fs=sr, output="sos")
        out = signal.sosfiltfilt(sos_hp, out)

    peak = np.max(np.abs(out)) or 1.0
    out = (out / peak) * 0.98
    return out.astype(np.float32), hum_hz


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="Input audio file (e.g. .m4a, .wav)")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Output WAV path (default: output/<input-stem>.wav)",
    )
    parser.add_argument(
        "--hum-hz",
        type=float,
        choices=[50.0, 60.0],
        help="Mains frequency in Hz (default: auto-detect 50 vs 60)",
    )
    parser.add_argument(
        "--q",
        type=float,
        default=35.0,
        help="Notch filter Q factor; higher = narrower notch (default: 35)",
    )
    parser.add_argument(
        "--max-notch-hz",
        type=float,
        default=1000.0,
        help="Remove hum harmonics up to this frequency (default: 1000)",
    )
    parser.add_argument(
        "--highpass-hz",
        type=float,
        default=40.0,
        help="High-pass cutoff after notching; 0 to disable (default: 40)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.input.is_file():
        print(f"error: file not found: {args.input}", file=sys.stderr)
        return 1

    output = args.output
    if output is None:
        root = Path(__file__).resolve().parent.parent
        output = root / "output" / f"{args.input.stem}.wav"
    output.parent.mkdir(parents=True, exist_ok=True)

    print(f"Loading {args.input} ...")
    y, sr = librosa.load(str(args.input), sr=None, mono=False)

    hum_hz = args.hum_hz
    print(f"Removing hum ({hum_hz or 'auto-detect'} Hz mains) ...")
    cleaned, detected_hz = remove_hum(
        y,
        sr,
        hum_hz=hum_hz,
        q=args.q,
        max_notch_hz=args.max_notch_hz,
        highpass_hz=args.highpass_hz,
    )
    if hum_hz is None:
        print(f"Detected {detected_hz:.0f} Hz mains hum")

    sf.write(str(output), cleaned, sr, subtype="PCM_16")
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
