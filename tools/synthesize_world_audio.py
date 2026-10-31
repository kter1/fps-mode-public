#!/usr/bin/env python3
"""Build the original environmental, movement, combat and interface WAV palette.

Standard library only; deterministic seeds, mono PCM16 at 22.05 kHz. Existing
weapon recordings are deliberately outside this generator. Ambiences are cyclic
filtered noise and periodic oscillators, so they can loop without a fade or gap.

    python3 tools/synthesize_world_audio.py
    python3 tools/synthesize_world_audio.py --check
"""
import argparse
from array import array
import math
from pathlib import Path
import random
import sys
import wave

RATE = 22050
TAU = math.tau
ROOT = Path(__file__).resolve().parents[1]
LOOP_SECONDS = 12.0


def noise(rng, size):
    return [rng.uniform(-1.0, 1.0) for _ in range(size)]


def lowpass(signal, cutoff, cyclic=False):
    """One-pole filter; a pre-pass establishes the cyclic steady state."""
    blend = 1.0 - math.exp(-TAU * cutoff / RATE)
    state = 0.0
    if cyclic:
        for value in signal:
            state += blend * (value - state)
    result = []
    for value in signal:
        state += blend * (value - state)
        result.append(state)
    return result


def band(signal, low, high, cyclic=False):
    smooth = lowpass(signal, high, cyclic)
    bottom = lowpass(smooth, low, cyclic)
    return [upper - lower for upper, lower in zip(smooth, bottom)]


def add(target, source, at=0.0, gain=1.0):
    offset = int(at * RATE)
    for index, value in enumerate(source):
        if offset + index >= len(target):
            break
        target[offset + index] += value * gain


def pulse(rng, duration, low, high, decay, attack=.002):
    signal = band(noise(rng, int(duration * RATE)), low, high)
    return [value * (1.0 - math.exp(-index / RATE / attack)) *
            math.exp(-index / RATE * decay) for index, value in enumerate(signal)]


def tone(duration, frequency, decay, gain=1.0, attack=.002, fall=0.0):
    phase = 0.0
    result = []
    for index in range(int(duration * RATE)):
        time = index / RATE
        phase += TAU * (frequency + fall * time) / RATE
        result.append(math.sin(phase) * gain * math.exp(-time * decay) *
                      (1.0 - math.exp(-time / attack)))
    return result


def movement(kind, rng):
    duration = {"gear": .26, "jump": .34, "land": .46}[kind]
    result = [0.0] * int(duration * RATE)
    # The cloth layer has separated folds instead of continuous white noise.
    folds = {"gear": [(.0, .6), (.065, .45), (.14, .25)],
             "jump": [(.0, .6), (.06, .7), (.15, .25)],
             "land": [(.0, .8), (.045, .45), (.12, .25)]}[kind]
    for at, gain in folds:
        add(result, pulse(rng, duration - at, 320, 2700, 28, .009), at, gain)
    if kind == "gear":
        for at in [.025, .085, .16]:
            add(result, tone(.075, rng.uniform(1900, 2600), 85, .045), at)
    elif kind == "jump":
        add(result, tone(.2, rng.uniform(95, 115), 30, .16, fall=-80))
        add(result, pulse(rng, .16, 80, 700, 30), gain=.65)
    else:
        add(result, tone(.35, rng.uniform(65, 82), 17, .47, .002, -45))
        add(result, pulse(rng, .31, 45, 1200, 19), gain=1.2)
        add(result, pulse(rng, .19, 900, 5500, 29, .004), .035, .23)
    return result


def impact(kind, rng):
    duration = {"concrete": .22, "metal": .30, "earth": .22,
                "wood": .24, "flesh": .18}[kind]
    result = [0.0] * int(duration * RATE)
    if kind == "metal":
        add(result, pulse(rng, .12, 900, 7500, 64), gain=.85)
        for frequency, gain in [(1480, .16), (2323, .13), (3891, .08)]:
            add(result, tone(duration, frequency * rng.uniform(.96, 1.04), 22, gain))
        add(result, tone(.18, 215, 33, .13))
    elif kind == "concrete":
        add(result, pulse(rng, duration, 600, 6800, 48), gain=1.4)
        add(result, pulse(rng, duration, 80, 1300, 29), gain=.65)
        for at in [.035, .075, .105]:
            add(result, pulse(rng, .04, 1200, 7000, 110), at, .15)
    elif kind == "wood":
        add(result, pulse(rng, duration, 260, 4800, 42), gain=1.3)
        for frequency in [181, 347, 615]:
            add(result, tone(duration, frequency * rng.uniform(.9, 1.1), 32, .14))
    elif kind == "earth":
        add(result, pulse(rng, duration, 55, 1600, 28), gain=1.5)
        add(result, pulse(rng, .13, 1400, 4800, 42), .02, .32)
    else:
        add(result, pulse(rng, duration, 90, 1800, 39), gain=1.15)
        add(result, tone(duration, rng.uniform(95, 125), 35, .27))
        add(result, pulse(rng, duration, 1000, 3700, 65), gain=.18)
    return result


def near_miss(rng):
    duration = .21
    result = band(noise(rng, int(duration * RATE)), 750, 8500)
    phase = 0.0
    for index in range(len(result)):
        time = index / RATE
        swell = math.exp(-((time - .065) / .024) ** 2)
        tail = math.exp(-((time - .09) / .048) ** 2)
        phase += TAU * (1750 + 1850 * math.exp(-time * 27)) / RATE
        result[index] = result[index] * swell * 1.1 + math.sin(phase) * tail * .035
    return result


def ricochet(rng):
    duration = .44
    result = pulse(rng, duration, 1500, 8500, 80, .001)
    base = rng.uniform(3100, 3800)
    phase = 0.0
    for index in range(len(result)):
        time = index / RATE
        phase += TAU * (base * math.exp(-time * 3) + 600) / RATE
        envelope = (1.0 - math.exp(-time * 700)) * math.exp(-time * 13)
        result[index] += (math.sin(phase) + .2 * math.sin(phase * 1.47)) * envelope * .15
    return result


def hurt(rng):
    result = [0.0] * int(.33 * RATE)
    add(result, tone(.33, rng.uniform(63, 80), 14, .5, fall=-30))
    add(result, pulse(rng, .25, 80, 1800, 22), gain=1.15)
    add(result, pulse(rng, .24, 500, 3700, 31, .008), .035, .35)
    return result


def grenade(kind, rng):
    duration = {"pin": .28, "throw": .32, "bounce": .25}[kind]
    result = [0.0] * int(duration * RATE)
    if kind == "pin":
        add(result, pulse(rng, .075, 1200, 7000, 95), gain=.6)
        add(result, tone(.16, rng.uniform(2350, 2650), 38, .10), .025)
        add(result, tone(.14, rng.uniform(3400, 3800), 45, .055), .03)
        add(result, pulse(rng, .16, 250, 2200, 35, .006), .07, .4)
        add(result, pulse(rng, .09, 700, 5000, 70), .17, .35)
    elif kind == "throw":
        air = band(noise(rng, len(result)), 280, 2900)
        for index, value in enumerate(air):
            time = index / RATE
            result[index] = value * math.exp(-((time - .13) / .065) ** 2)
        add(result, pulse(rng, .17, 120, 1200, 29, .01), gain=.45)
        add(result, tone(.09, 1800, 65, .018), .17)
    else:
        add(result, pulse(rng, .16, 200, 5000, 50), gain=1.0)
        for frequency, gain in [(185, .38), (510, .14), (1270, .08)]:
            add(result, tone(duration, frequency * rng.uniform(.94, 1.06), 30, gain))
        add(result, pulse(rng, .09, 1500, 7000, 75), .045, .2)
    return result


def smoke_hiss(rng):
    duration = 5.0
    result = band(noise(rng, int(duration * RATE)), 650, 6500)
    low = band(noise(rng, len(result)), 150, 1300)
    for index, value in enumerate(result):
        time = index / RATE
        envelope = (1.0 - math.exp(-time * 75)) * (1.0 - time / duration) ** 1.5
        result[index] = (value * (.45 + .55 * math.exp(-time * .8)) + low[index] * .4) * envelope
    return result


def heartbeat(rng):
    result = [0.0] * RATE
    # A dull, unvoiced pair of body pulses; the quiet interval joins exactly.
    add(result, tone(.32, 61, 24, .55, .006, -42), .035)
    add(result, pulse(rng, .18, 25, 150, 30, .009), .04, .65)
    add(result, tone(.28, 54, 26, .36, .006, -35), .23)
    add(result, pulse(rng, .15, 25, 130, 33, .009), .235, .45)
    return result


def cue(kind, rng):
    duration = {"hit_confirm": .085, "kill_confirm": .28, "spawn": .6,
                "match_win": 1.25, "match_loss": 1.25,
                "ui_focus": .07, "ui_accept": .15}[kind]
    result = [0.0] * int(duration * RATE)
    if kind in ["hit_confirm", "ui_focus", "ui_accept"]:
        pitches = {"hit_confirm": (1750, 2220), "ui_focus": (800, 1200),
                   "ui_accept": (880, 1320)}[kind]
        add(result, pulse(rng, duration, 700, 5500, 95), gain=.35)
        for pitch in pitches:
            add(result, tone(duration, pitch, 85 if kind != "ui_accept" else 48, .12))
        if kind == "ui_accept":
            add(result, tone(.09, 1760, 52, .08), .045)
    elif kind == "kill_confirm":
        add(result, pulse(rng, .09, 350, 3800, 70), gain=.3)
        add(result, tone(.2, 1245, 32, .1))
        add(result, tone(.19, 1865, 35, .1), .06)
        add(result, tone(.19, 2490, 40, .035), .06)
    elif kind == "spawn":
        air = band(noise(rng, len(result)), 450, 2400)
        for index, value in enumerate(air):
            time = index / RATE
            result[index] += value * math.exp(-((time - .15) / .09) ** 2) * .3
        add(result, tone(.42, 196, 8, .16, .018), .10)
        add(result, tone(.34, 392, 10, .09, .012), .19)
        add(result, pulse(rng, .12, 800, 4000, 50), .26, .25)
    else:
        # Short, restrained resolution stings with a felt mallet attack.
        pitches = [(196, 0), (246.94, .11), (293.66, .22)] if kind == "match_win" else [(196, 0), (174.61, .13), (146.83, .26)]
        for pitch, at in pitches:
            add(result, tone(duration - at, pitch, 5, .14, .008), at)
            add(result, tone(duration - at, pitch * 2, 9, .035, .006), at)
        add(result, pulse(rng, .25, 250, 1600, 24, .02), gain=.15)
    return result


def ambience(kind, rng):
    size = int(LOOP_SECONDS * RATE)
    air = band(noise(rng, size), 100, 2500, True)
    rumble = band(noise(rng, size), 30, 230, True)
    if kind == "wind":
        # Two extra poles soften the air bed into wind, without a bright static hiss.
        air = lowpass(lowpass(air, 950, True), 950, True)
    result = [0.0] * size
    for index in range(size):
        time = index / RATE
        # All modulation frequencies are integer multiples of 1 / loop length.
        swell = .64 + .23 * math.sin(TAU * time / LOOP_SECONDS) + .13 * math.sin(TAU * 3 * time / LOOP_SECONDS + .7)
        if kind == "wind":
            result[index] = air[index] * swell * .8 + rumble[index] * .7
        elif kind == "industrial":
            hum = math.sin(TAU * 58 * time) * .11 + math.sin(TAU * 116 * time + .4) * .026
            motor = math.sin(TAU * 174 * time + .2 * math.sin(TAU * time / LOOP_SECONDS)) * .018
            result[index] = hum * (.94 + .06 * swell) + motor + air[index] * .12 + rumble[index] * .5
    if kind == "birds":
        # Sparse, soft two-part calls; no calls cross the loop boundary.
        for at, base in [(1.4, 2420), (5.0, 2850), (9.2, 2230)]:
            for call in range(rng.randint(2, 4)):
                duration = rng.uniform(.095, .16)
                size_call = int(duration * RATE)
                phase = 0.0
                chirp = []
                for index in range(size_call):
                    time = index / RATE
                    progress = time / duration
                    frequency = base + 420 * math.sin(progress * math.pi) - 250 * progress + 65 * math.sin(TAU * time * 31)
                    phase += TAU * frequency / RATE
                    envelope = math.sin(math.pi * progress) ** 2
                    chirp.append((math.sin(phase) + .13 * math.sin(phase * 2)) * envelope * .24)
                add(result, chirp, at + call * .19, rng.uniform(.6, 1.0))
    return result


def normalized(signal, peak, loop=False):
    assert signal and all(math.isfinite(value) for value in signal)
    mean = sum(signal) / len(signal)
    signal = [value - mean for value in signal]
    if not loop:
        # Edges at exact digital zero prevent clicks even when interrupted.
        fade_in = int(.0015 * RATE)
        fade_out = int(.012 * RATE)
        for index in range(fade_in):
            signal[index] *= index / fade_in
        for index in range(fade_out):
            signal[-index - 1] *= index / fade_out
    gain = peak / max(max(abs(value) for value in signal), 1e-10)
    return [value * gain for value in signal]


def write(path, signal, peak, loop=False):
    values = array("h", (round(value * 32767) for value in normalized(signal, peak, loop)))
    if sys.byteorder != "little":
        values.byteswap()
    with wave.open(str(path), "wb") as stream:
        stream.setnchannels(1)
        stream.setsampwidth(2)
        stream.setframerate(RATE)
        stream.writeframes(values.tobytes())


def definitions():
    for index, kind in enumerate(["gear", "jump", "land", "near_miss", "ricochet", "hurt"]):
        for variant in range(4):
            seed = 5100 + index * 100 + variant
            generator = (lambda rng, key=kind: movement(key, rng)) if kind in ["gear", "jump", "land"] else globals()[kind]
            yield f"{kind}_{variant}", generator, seed, .72, False
    for index, kind in enumerate(["concrete", "metal", "earth", "wood", "flesh"]):
        for variant in range(4):
            yield f"impact_{kind}_{variant}", lambda rng, key=kind: impact(key, rng), 6100 + index * 100 + variant, .72, False
    for index, kind in enumerate(["pin", "throw", "bounce"]):
        for variant in range(4):
            yield f"grenade_{kind}_{variant}", lambda rng, key=kind: grenade(key, rng), 9100 + index * 100 + variant, .64, False
    for index, kind in enumerate(["hit_confirm", "kill_confirm", "spawn", "match_win", "match_loss", "ui_focus", "ui_accept"]):
        yield kind, lambda rng, key=kind: cue(key, rng), 7100 + index, .55, False
    for index, kind in enumerate(["wind", "industrial", "birds"]):
        yield f"ambience_{kind}", lambda rng, key=kind: ambience(key, rng), 8100 + index, .32, True
    yield "smoke_hiss", smoke_hiss, 9500, .5, False
    yield "heartbeat", heartbeat, 9501, .6, True


def check(output):
    largest_peak = 0.0
    worst_seam = 0.0
    count = 0
    for name, _, _, _, loop in definitions():
        with wave.open(str(output / f"{name}.wav"), "rb") as stream:
            assert (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) == (1, 2, RATE), name
            signal = array("h", stream.readframes(stream.getnframes()))
        if sys.byteorder != "little":
            signal.byteswap()
        assert len(signal) > 0 and max(signal) < 32767 and min(signal) > -32768, name
        largest_peak = max(largest_peak, max(abs(value) for value in signal) / 32767)
        assert sum(value * value for value in signal) > 0, name
        if loop:
            assert len(signal) == int((1.0 if name == "heartbeat" else LOOP_SECONDS) * RATE), name
            seam = abs(signal[0] - signal[-1])
            max_delta = max(abs(right - left) for left, right in zip(signal, signal[1:]))
            # The wrap must be no greater than an ordinary adjacent-sample change.
            assert seam <= max_delta, f"{name}: discontinuous loop"
            worst_seam = max(worst_seam, seam / 32767)
        else:
            assert signal[0] == 0 and signal[-1] == 0, name
        count += 1
    print(f"WORLD AUDIO PASS: {count} WAVs; PCM16 mono/{RATE} Hz; max peak {largest_peak:.4f}; "
          f"3 seamless {LOOP_SECONDS:g}s ambiences + 1s heartbeat loop; "
          f"max boundary delta {worst_seam:.5f}; no clipped samples")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate the generated palette without rewriting")
    parser.add_argument("--output", type=Path, default=ROOT / "content/audio")
    args = parser.parse_args()
    if not args.check:
        args.output.mkdir(parents=True, exist_ok=True)
        for name, generator, seed, peak, loop in definitions():
            write(args.output / f"{name}.wav", generator(random.Random(seed)), peak, loop)
    check(args.output)


if __name__ == "__main__":
    main()
