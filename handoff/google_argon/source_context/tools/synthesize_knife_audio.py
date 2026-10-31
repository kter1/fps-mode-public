#!/usr/bin/env python3
"""Synthesises the knife sounds offline (no samples), standard library only:
content/audio/knife_0-3.wav (blade swish) and knife_hit_0-3.wav (strike).
    python3 tools/synthesize_knife_audio.py
"""
import math, random, struct, wave
from pathlib import Path

RATE = 22050
ROOT = Path(__file__).resolve().parents[1]


def lowpass(signal, cutoff):
    """One-pole low-pass; `cutoff` may be a per-sample list."""
    out, y = [], 0.0
    for i, x in enumerate(signal):
        c = cutoff[i] if isinstance(cutoff, list) else cutoff
        a = 1 - math.exp(-2 * math.pi * c / RATE)
        y += a * (x - y)
        out.append(y)
    return out


def highpass(signal, cutoff):
    low = lowpass(signal, cutoff)
    return [x - l for x, l in zip(signal, low)]


def swish(rng):
    # Air torn by the blade: band-limited noise whose band sweeps up then down, a fast swell
    # and a soft tail.
    n = int(RATE * rng.uniform(.30, .36))
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    peak = rng.uniform(.38, .46)
    sweep = [600 + 3400 * math.exp(-((i / n - peak) / .16) ** 2) for i in range(n)]
    band = highpass(lowpass(noise, sweep), 350)
    env = [math.exp(-((i / n - peak) / .17) ** 2) for i in range(n)]
    return [b * e * 2.4 for b, e in zip(band, env)]


def strike(rng):
    # Blade into cloth and body: a dull low thump and a short cloth tear.
    n = int(RATE * .32)
    thump_freq = rng.uniform(85, 105)
    out = []
    for i in range(n):
        t = i / RATE
        out.append(math.sin(2 * math.pi * thump_freq * t * (1 - t * .8)) * math.exp(-t * 22) * min(t / .002, 1))
    tear = lowpass([rng.uniform(-1, 1) for _ in range(n)], 2600)
    tear = highpass(tear, 500)
    for i in range(n):
        t = i / RATE
        out[i] = out[i] * .9 + tear[i] * math.exp(-t * 30) * min(t / .004, 1) * 2.2
    return out


def write(path, signal):
    peak = max(abs(x) for x in signal) or 1
    scale = .8 / peak
    fade = int(RATE * .01)
    data = bytearray()
    for i, x in enumerate(signal):
        if i >= len(signal) - fade:
            x *= (len(signal) - i) / fade
        data += struct.pack("<h", int(max(-1, min(1, x * scale)) * 32767))
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE); out.writeframes(bytes(data))


def main():
    for i in range(4):
        rng = random.Random(4100 + i)
        write(ROOT / f"content/audio/knife_{i}.wav", swish(rng))
        write(ROOT / f"content/audio/knife_hit_{i}.wav", strike(random.Random(4200 + i)))
    print("KNIFE AUDIO PASS")


if __name__ == "__main__":
    main()
