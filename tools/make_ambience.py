"""Makes the two ambience beds (M6, plan section 7: "waves, gulls, wind
chimes above; muffled water and casino murmur below").

    python3 tools/make_ambience.py content/sfw/ambience

writes town_bed.ogg and palace_bed.ogg there. Both are stereo, seamless
loops that sit under the music: everything is either filtered as a loop
or placed so that what runs past the end wraps back to the start. Fixed
seeds, so running it again makes the same files. Needs numpy and ffmpeg
(with libvorbis).
"""

import os
import sys

import numpy as np

from sound_kit import (RATE, bell, bubble, chime, chip_click, envelope, fft_filter, gull, highpass, hz, lowpass,
                       normalise, peak, pink, place, reverb, stft_filter, times, write_ogg)

HOP = 512
TOWN_SECONDS = 48.0
PALACE_SECONDS = 40.0
# D major pentatonic, the town's key, two octaves up for the chimes.
CHIME_NOTES = [86, 88, 90, 93, 95, 98]
# D Dorian for the palace's far-off glitter.
DORIAN = [74, 76, 77, 79, 81, 83, 84, 86]


def loop_length(seconds):
    return int(seconds * RATE) // HOP * HOP


# --- Above: the town ---------------------------------------------------------------


def wave_wash(rng, seconds):
    """One wave: a low swell, the break, then foam hissing back down the
    sand. Its own noise for each ear, so it's wide."""
    count = int(seconds * RATE)
    crash = seconds * rng.uniform(0.3, 0.38)
    out = np.zeros((count, 2))
    for side in range(2):
        source = rng.normal(size=count)

        def gain(f, t):
            t = t[:, None]
            before = np.clip(t / crash, 0.0, 1.0)
            after = np.clip((t - crash) / (seconds - crash), 0.0, 1.0)
            cutoff = np.where(t < crash, 250.0 + 1700.0 * before ** 2, 1950.0 * (1.0 - after) + 500.0)
            level = np.where(t < crash, before ** 1.5, (1.0 - after) ** 1.6)
            body = lowpass(f[None, :], cutoff, 2)
            # The foam fizzes in over a quarter second, not as a click.
            since = np.maximum(t - crash, 0.0)
            foam = peak(f[None, :], 3200.0, 1800.0) * 0.35 * np.minimum(1.0, since / 0.25) * np.exp(-since * 1.3)
            return (body + foam) * level * lowpass(f[None, :], 7000.0, 2)

        out[:, side] = stft_filter(source, gain)
    return normalise(out) * rng.uniform(0.6, 1.0)


def gull_bout(rng):
    """Two to four calls from one bird, a little lower each time."""
    calls = int(rng.integers(2, 5))
    pitch = rng.uniform(0.9, 1.12)
    gap = rng.uniform(0.42, 0.62)
    out = np.zeros(int(RATE * (gap * calls + 0.6)))
    for i in range(calls):
        place(out, gull(rng, pitch * (1.0 - 0.025 * i)), i * gap * rng.uniform(0.9, 1.1))
    return out


def gust(rng, seconds):
    """A breath of wind: soft noise that rises and falls."""
    count = int(seconds * RATE)
    shape = np.sin(np.pi * np.arange(count) / count) ** 2
    out = np.zeros((count, 2))
    for side in range(2):
        out[:, side] = fft_filter(rng.normal(size=count), lambda f: peak(f, 600.0, 500.0) * highpass(f, 150.0)) * shape
    return out / np.max(np.abs(out))


def town_bed():
    rng = np.random.default_rng(31)
    count = loop_length(TOWN_SECONDS)
    track = np.zeros((count, 2))

    # A constant, soft shore under everything, filtered as one loop.
    for side in range(2):
        track[:, side] += fft_filter(pink(count, rng, circular=True), lambda f: lowpass(f, 900.0) * highpass(f, 60.0),
                                     circular=True) * 0.05

    # Waves break every six to nine seconds.
    at = 0.0
    while at < TOWN_SECONDS:
        length = rng.uniform(6.5, 9.0)
        wash = wave_wash(rng, length)
        pan = rng.uniform(-0.3, 0.3)
        index = (int(at * RATE) + np.arange(len(wash))) % count
        np.add.at(track[:, 0], index, wash[:, 0] * 0.32 * (1.0 - pan * 0.5))
        np.add.at(track[:, 1], index, wash[:, 1] * 0.32 * (1.0 + pan * 0.5))
        at += length * rng.uniform(0.72, 0.9)

    # Gulls, off to the sides and a little far.
    gulls = np.zeros((count, 2))
    for at in [3.5, 15.0, 27.5, 38.0]:
        bout = gull_bout(rng)
        place(gulls, bout * rng.uniform(0.5, 0.8), at + rng.uniform(-1.5, 1.5), pan=rng.choice([-0.7, 0.6]), wrap=True)
    for side in range(2):
        far = fft_filter(gulls[:, side], lambda f: lowpass(f, 3200.0), circular=True)
        track[:, side] += (far + reverb(far, 1.6, 3.0, rng, circular=True) * 0.6) * 0.09

    # Three gusts; each sets a wind chime off by the shop eave (left).
    for at in [8.0, 23.0, 40.0]:
        length = rng.uniform(4.0, 6.0)
        place(track, gust(rng, length)[:, 0] * 0.04, at, pan=-0.2, wrap=True)
        place(track, gust(rng, length)[:, 1] * 0.04, at, pan=0.2, wrap=True)
        strikes = int(rng.integers(5, 10))
        for i in range(strikes):
            when = at + length * (0.2 + 0.6 * rng.random())
            near = np.sin(np.pi * (when - at) / length)
            note = hz(int(rng.choice(CHIME_NOTES)))
            place(track, chime(note, 4.0, rng) * 0.055 * near * rng.uniform(0.5, 1.0), when,
                  pan=-0.45 + rng.uniform(-0.15, 0.15), wrap=True)

    return normalise(track, 0.5)


# --- Below: the palace -------------------------------------------------------------


# The vowels the murmur is made of: first, second and third formants.
VOWELS = [(730, 1090, 2440), (530, 1840, 2480), (270, 2290, 3010), (570, 840, 2410), (300, 870, 2240),
          (660, 1720, 2410), (490, 1350, 1690)]


def voice(rng, count, frame=1024):
    """One guest talking: a buzzing voice in phrases of short syllables,
    each syllable a vowel, as one loop."""
    t = times(count)
    pitch = rng.uniform(95.0, 230.0)
    drift = 1.0 + 0.08 * np.sin(2.0 * np.pi * t * rng.integers(1, 4) / (count / RATE) + rng.uniform(0, 6.28))
    wobble = 1.0 + 0.04 * normalise(fft_filter(rng.normal(size=count), lambda f: lowpass(f, 4.0, 2), circular=True))
    phase = np.cumsum(pitch * drift * wobble) / RATE
    buzz = 2.0 * (phase % 1.0) - 1.0
    hop = frame // 2
    centres = (np.arange(0, count, hop) + frame / 2) / RATE
    # Phrases: talking for a few seconds, then quiet for a few.
    syllables = []
    at = rng.uniform(0.0, 2.0)
    total = count / RATE
    while at < total:
        talk = rng.uniform(1.2, 4.0)
        end = at + talk
        while at < end:
            length = rng.uniform(0.11, 0.26)
            syllables.append((at, length, VOWELS[int(rng.integers(len(VOWELS)))], rng.uniform(0.6, 1.0)))
            at += length + rng.uniform(0.0, 0.05)
        at += rng.uniform(0.6, 3.5)
    # Per-frame level and formants. Syllables wrap round the loop.
    levels = np.zeros(len(centres))
    formants = np.tile(np.array(VOWELS[0], dtype=float), (len(centres), 1))
    for start, length, vowel, level in syllables:
        for shift in (0.0, -total):
            u = (centres - (start + shift)) / length
            inside = (u >= 0.0) & (u <= 1.0)
            levels[inside] = np.maximum(levels[inside], level * np.sin(np.pi * u[inside]) ** 0.7)
            formants[inside] = vowel

    def gain(f, _t):
        f = f[None, :]
        shape = peak(f, formants[:, :1], 90.0) + 0.6 * peak(f, formants[:, 1:2], 130.0) \
            + 0.25 * peak(f, formants[:, 2:3], 180.0)
        return shape * levels[:, None]

    return stft_filter(buzz, gain, frame=frame, circular=True)


def palace_bed():
    rng = np.random.default_rng(47)
    count = loop_length(PALACE_SECONDS)
    seconds = count / RATE
    t = times(count)
    track = np.zeros((count, 2))

    # The water over the palace: a deep, slowly breathing rumble.
    for side in range(2):
        rumble = fft_filter(pink(count, rng, circular=True), lambda f: lowpass(f, 160.0, 3) * highpass(f, 25.0),
                            circular=True)
        breathe = 0.75 + 0.25 * np.sin(2.0 * np.pi * t * 3 / seconds + side * 1.3)
        track[:, side] += normalise(rumble) * breathe * 0.5
        swirl = fft_filter(pink(count, rng, circular=True), lambda f: peak(f, 380.0, 160.0), circular=True)
        track[:, side] += normalise(swirl) * (0.6 + 0.4 * np.sin(2.0 * np.pi * t * 5 / seconds + side)) * 0.08

    # The casino murmur, through the walls and the water.
    murmur = np.zeros((count, 2))
    for i in range(14):
        talk = normalise(voice(rng, count)) * rng.uniform(0.5, 1.0)
        pan = rng.uniform(-0.8, 0.8)
        murmur[:, 0] += talk * (1.0 - pan) * 0.5
        murmur[:, 1] += talk * (1.0 + pan) * 0.5

    # Chips stacking at far tables: little runs of clacks.
    for _ in range(int(rng.integers(9, 13))):
        at = rng.uniform(0.0, seconds)
        pan = rng.uniform(-0.8, 0.8)
        gap = rng.uniform(0.04, 0.08)
        for k in range(int(rng.integers(2, 6))):
            place(murmur, chip_click(rng) * rng.uniform(0.25, 0.5), at + k * gap * rng.uniform(0.8, 1.2), pan=pan,
                  wrap=True)

    # Now and then, a payout's bells somewhere across the floor.
    for at in [11.0, 29.0]:
        pan = rng.uniform(-0.6, 0.6)
        start = int(rng.integers(0, 3))
        for k in range(5):
            note = hz(DORIAN[min(start + k * 2 - (k // 3), len(DORIAN) - 1)])
            place(murmur, bell(note, 2.0, rng, bright=0.6) * 0.18, at + k * 0.09, pan=pan, wrap=True)

    for side in range(2):
        heard = fft_filter(murmur[:, side], lambda f: lowpass(f, 700.0, 3) * highpass(f, 90.0), circular=True)
        heard += reverb(heard, 2.2, 2.2, rng, circular=True) * 0.5
        track[:, side] += normalise(heard) * 0.32

    # Bubbles rising past the window, in short strings.
    bubbles = np.zeros((count, 2))
    for _ in range(int(rng.integers(10, 15))):
        at = rng.uniform(0.0, seconds)
        pan = rng.uniform(-0.9, 0.9)
        base = rng.uniform(300.0, 700.0)
        for k in range(int(rng.integers(3, 12))):
            place(bubbles, bubble(rng, base * rng.uniform(0.8, 1.6)) * rng.uniform(0.3, 1.0),
                  at + k * rng.uniform(0.03, 0.16), pan=pan, wrap=True)
    for side in range(2):
        track[:, side] += fft_filter(bubbles[:, side], lambda f: lowpass(f, 1400.0), circular=True) * 0.12

    return normalise(track, 0.5)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make_ambience.py <out_dir>")
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    write_ogg(os.path.join(out_dir, "town_bed.ogg"), town_bed(), quality=3)
    write_ogg(os.path.join(out_dir, "palace_bed.ogg"), palace_bed(), quality=3)


if __name__ == "__main__":
    main()
