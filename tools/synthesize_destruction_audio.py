#!/usr/bin/env python3
"""Synthesises content/audio/explosion.ogg and glass_break.ogg offline (no samples).

Needs numpy and soundfile (libsndfile writes the Ogg Vorbis files):
    python3 -m venv /tmp/v && /tmp/v/bin/pip install numpy soundfile
    /tmp/v/bin/python tools/synthesize_destruction_audio.py
"""
import sys
from pathlib import Path
import numpy as np
import soundfile as sf

RATE = 44100
ROOT = Path(__file__).resolve().parents[1]


def spectrum_filter(x, low=None, high=None):
    """Brick-wall band limit through the FFT, with a short taper at each edge."""
    f = np.fft.rfft(x)
    freq = np.fft.rfftfreq(len(x), 1 / RATE)
    gain = np.ones_like(freq)
    if low:
        gain *= np.clip((freq - low * .6) / (low * .4), 0, 1)
    if high:
        gain *= np.clip((high * 1.4 - freq) / (high * .4), 0, 1)
    return np.fft.irfft(f * gain, len(x))


def explosion(rng):
    n = int(RATE * 3.2)
    t = np.arange(n) / RATE
    # Sub boom: a falling sine, the pressure wave.
    freq = 28 + 90 * np.exp(-t * 7)
    boom = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t * 2.2)
    # Blast crack: wide noise, fast decay, with a rounded attack.
    noise = rng.standard_normal(n)
    crack = spectrum_filter(noise, 60, 7000) * np.exp(-t * 9) * np.minimum(t / .004, 1)
    body = spectrum_filter(rng.standard_normal(n), 40, 900) * np.exp(-t * 3.4) * np.minimum(t / .01, 1)
    # Rolling rumble and debris pattering on the ground afterwards.
    rumble = spectrum_filter(rng.standard_normal(n), 25, 220) * np.exp(-t * 1.3) * np.minimum(t / .08, 1)
    debris = np.zeros(n)
    for _ in range(90):
        at = int(RATE * rng.uniform(.25, 2.6))
        length = int(RATE * rng.uniform(.01, .04))
        if at + length < n:
            tick = rng.standard_normal(length) * np.exp(-np.arange(length) / (length * .25))
            debris[at:at + length] += tick * rng.uniform(.05, .3) * np.exp(-at / RATE * 1.2)
    debris = spectrum_filter(debris, 800, 6000)
    mix = boom * 1.0 + crack * .9 + body * .8 + rumble * .6 + debris * .5
    mix = np.tanh(mix * 1.6) * .9
    mix[-int(RATE * .15):] *= np.linspace(1, 0, int(RATE * .15))
    return mix.astype(np.float32)


def glass(rng):
    n = int(RATE * 1.6)
    t = np.arange(n) / RATE
    crack = spectrum_filter(rng.standard_normal(n), 2500, 11000) * np.exp(-t * 28) * np.minimum(t / .001, 1)
    out = crack * .9
    # Shards: pitched pings and short tinkles falling after the break.
    for _ in range(70):
        at = int(RATE * min(rng.exponential(.18), 1.3))
        pitch = rng.uniform(2200, 9000)
        ring = rng.uniform(25, 90)
        length = int(RATE * .35)
        if at + length >= n:
            continue
        s = np.arange(length) / RATE
        out[at:at + length] += np.sin(2 * np.pi * pitch * s) * np.exp(-s * ring) * rng.uniform(.03, .14)
    out += spectrum_filter(rng.standard_normal(n), 900, 4500) * np.exp(-t * 14) * .25
    out = np.tanh(out * 1.3) * .85
    out[-int(RATE * .1):] *= np.linspace(1, 0, int(RATE * .1))
    return out.astype(np.float32)


def main():
    out = ROOT / "content/audio"
    sf.write(str(out / "explosion.ogg"), explosion(np.random.default_rng(401)), RATE, format="OGG", subtype="VORBIS")
    sf.write(str(out / "glass_break.ogg"), glass(np.random.default_rng(402)), RATE, format="OGG", subtype="VORBIS")
    print("wrote", out / "explosion.ogg", out / "glass_break.ogg")


if __name__ == "__main__":
    sys.exit(main())
