"""Makes the M6 stingers (plan section 7): the tide transition both ways,
Koban's vault (opening, her win, her loss) and the barrel wash-up gag in
three variants.

    python3 tools/make_stingers.py content/sfw/sfx

The tide sounds are shared by both halves. Koban's are the palace's
family (glass bells, coins, chips, lounge bass); the barrel plays as the
town comes back, so it's the town's (wood, water, a gull). Fixed seeds,
so running it again makes the same files. Needs numpy and ffmpeg (with
libvorbis).
"""

import os
import sys

import numpy as np

from sound_kit import (RATE, bell, bubble, chip_click, coin, envelope, fade_ends, fft_filter, gull, highpass, hz,
                       knock, lowpass, normalise, peak, place, reverb, stft_filter, times)
from sound_kit import write_ogg

# The tide covers the screen in 0.7 s, the scene swaps, then it clears in
# 0.7 s (game/transition/tide_transition.gd).
COVER = 0.7


def finish(sound, rng, room=0.25, top=0.8):
    """A touch of room, gentle ends, and a common peak level."""
    wet = reverb(sound, 1.2, 4.5, rng)[: len(sound)]
    return fade_ends(normalise(sound + wet * room, top), 0.005)


def bass_pluck(start, end, seconds, glide=0.08):
    """A lounge upright bass note that slides from one pitch to another."""
    t = times(int(RATE * seconds))
    f = end + (start - end) * np.exp(-t / glide)
    phase = 2.0 * np.pi * np.cumsum(f) / RATE
    tone = np.sin(phase) + 0.45 * np.sin(2 * phase) + 0.18 * np.sin(3 * phase)
    return tone * envelope(len(t), 0.006, seconds * 0.9, 3.5)


# --- The tide -----------------------------------------------------------------------


def tide_down():
    """Town -> palace: the sea rushes up over the screen, you go under
    with a thump, and the world goes muffled and bubbly."""
    rng = np.random.default_rng(101)
    seconds = 2.4
    count = int(RATE * seconds)
    plunge = COVER

    def gain(f, t):
        t = t[:, None]
        f = f[None, :]
        rise = np.clip(t / plunge, 0.0, 1.0)
        cutoff = np.where(t < plunge, 250.0 + 3800.0 * rise ** 2, 380.0 + 3700.0 * np.exp(-(t - plunge) * 9.0))
        level = np.where(t < plunge, 0.1 + 0.9 * rise ** 2, 0.55 * np.exp(-(t - plunge) * 1.6) + 0.05)
        return lowpass(f, cutoff, 2) * highpass(f, 40.0) * level

    out = stft_filter(rng.normal(size=count), gain) * 0.35
    thump = bass_pluck(95.0, 48.0, 0.6, glide=0.05) * 0.9
    place(out, thump, plunge - 0.02)
    # The bubbles you went under with, rising and fading.
    for k in range(26):
        at = plunge + 0.02 + (k / 26.0) ** 1.4 * 1.4 + rng.uniform(0.0, 0.05)
        loud = np.exp(-(at - plunge) * 1.8)
        place(out, bubble(rng, rng.uniform(260.0, 650.0)) * 0.5 * loud, at)
    out = fft_filter(out, lambda f: lowpass(f, 6000.0))
    return finish(out, rng, room=0.3)


def tide_up():
    """Palace -> town: muffled bubbles climbing, the water opens, and a
    bright wash of surf and air as the town comes back."""
    rng = np.random.default_rng(102)
    seconds = 2.4
    count = int(RATE * seconds)
    surface = COVER + 0.15

    def gain(f, t):
        t = t[:, None]
        f = f[None, :]
        rise = np.clip(t / surface, 0.0, 1.0)
        after = np.maximum(t - surface, 0.0)
        cutoff = np.where(t < surface, 300.0 + 500.0 * rise, 800.0 + 3000.0 * np.minimum(1.0, after / 0.12))
        level = np.where(t < surface, 0.2 + 0.4 * rise, np.exp(-after * 2.6) * np.minimum(1.0, 0.6 + after / 0.08))
        return lowpass(f, cutoff, 3) * highpass(f, 50.0) * level

    out = stft_filter(rng.normal(size=count), gain) * 0.4
    for k in range(18):
        at = (k / 18.0) * (surface - 0.05) + rng.uniform(0.0, 0.03)
        lift = 1.0 + 1.5 * at / surface
        place(out, bubble(rng, rng.uniform(300.0, 600.0) * lift) * 0.4 * (0.4 + 0.6 * at / surface), at)
    out[: int(surface * RATE)] = fft_filter(out[: int(surface * RATE)], lambda f: lowpass(f, 1200.0))
    # The surface breaking: a short bright splash.
    n = int(RATE * 0.5)
    splash = fft_filter(rng.normal(size=n), lambda f: highpass(f, 900.0) * lowpass(f, 5000.0, 3)) \
        * envelope(n, 0.01, 0.45, 5.0) * 0.45
    place(out, splash, surface)
    return finish(out, rng, room=0.2)


# --- Koban ---------------------------------------------------------------------------


def coin_spin(rng, seconds=1.3):
    """A koban spun on the table: a rattle that speeds up as it settles,
    then one flat clack."""
    out = np.zeros(int(RATE * (seconds + 0.5)))
    at = 0.0
    gap = 0.13
    ring = rng.uniform(3000.0, 3400.0)
    while at < seconds:
        loud = 0.35 + 0.65 * at / seconds
        place(out, coin(rng, ring * rng.uniform(0.98, 1.02), 0.12) * 0.35 * loud, at)
        at += gap
        gap = max(0.014, gap * 0.86)
    place(out, coin(rng, ring * 0.92, 0.5) * 0.7, at + 0.02)
    return out


def koban_vault():
    """Her table opens: a sly bass slide up, a Dorian shimmer on the bells,
    and a gold koban spun down for the stakes."""
    rng = np.random.default_rng(201)
    out = np.zeros(int(RATE * 3.4))
    place(out, bass_pluck(hz(38) * 0.8, hz(38), 0.9) * 0.6, 0.0)
    place(out, bass_pluck(hz(45) * 0.85, hz(45), 0.9, glide=0.1) * 0.55, 0.32)
    # D F A C E: a minor ninth, glittering upward.
    for i, note in enumerate([74, 77, 81, 84, 88]):
        place(out, bell(hz(note), 2.2, rng) * 0.32, 0.36 + i * 0.075)
    place(out, coin_spin(rng) * 0.9, 1.15)
    return finish(out, rng, room=0.35)


def koban_wins():
    """You lost the vault: the bells sink, the bass drops, and your chips
    are raked across the felt to her side."""
    rng = np.random.default_rng(202)
    out = np.zeros(int(RATE * 3.0))
    for i, note in enumerate([88, 84, 81, 77]):
        place(out, bell(hz(note), 2.0, rng, bright=0.8) * 0.3, i * 0.11)
    place(out, bass_pluck(hz(45), hz(38) * 0.94, 1.4, glide=0.35) * 0.65, 0.42)
    # The rake: a run of chip clacks thinning out, over a felt hush.
    n = int(RATE * 0.9)
    felt = fft_filter(rng.normal(size=n), lambda f: peak(f, 1800.0, 1400.0)) * np.sin(np.pi * np.arange(n) / n) * 0.05
    place(out, felt, 0.7)
    at = 0.72
    for k in range(22):
        place(out, chip_click(rng) * rng.uniform(0.25, 0.6) * (1.0 - k / 30.0), at)
        at += rng.uniform(0.015, 0.05) * (1.0 + k / 10.0)
    place(out, chip_click(rng, bright=0.85) * 0.8, at + 0.12)
    return finish(out, rng, room=0.3)


def koban_beaten():
    """You beat the house: bells climb and turn bright (the Dorian lifts
    to major), and a pile of koban pours out."""
    rng = np.random.default_rng(203)
    out = np.zeros(int(RATE * 3.4))
    for i, note in enumerate([74, 78, 81, 86, 90]):
        place(out, bell(hz(note), 2.4, rng) * 0.3, i * 0.08)
    place(out, bass_pluck(hz(38) * 0.9, hz(38), 1.0) * 0.5, 0.0)
    place(out, bass_pluck(hz(45) * 0.9, hz(50), 1.2, glide=0.06) * 0.5, 0.34)
    # The pour: dense at first, then the last few coins bounce and settle.
    for k in range(60):
        at = 0.45 + rng.gamma(2.0, 0.22)
        place(out, coin(rng, seconds=0.35) * rng.uniform(0.08, 0.28), at)
    for k, at in enumerate([1.9, 2.15, 2.32, 2.43]):
        place(out, coin(rng, 3600.0, 0.3) * 0.25 * (0.8 ** k), at)
    return finish(out, rng, room=0.3)


# --- The barrel -------------------------------------------------------------------


def splash(rng, seconds=0.7, bright=1.0):
    n = int(RATE * seconds)
    body = fft_filter(rng.normal(size=n), lambda f: highpass(f, 250.0) * lowpass(f, 3500.0 * bright))
    out = body * envelope(n, 0.008, seconds, 5.0) * 0.6
    for k in range(10):
        place(out, bubble(rng, rng.uniform(900.0, 2200.0) * bright, rng.uniform(0.01, 0.03)) * 0.25,
              rng.uniform(0.08, seconds * 0.8))
    return out


def barrel_bonk(rng, size=1.0):
    """A hollow, half-full barrel landing on wet sand."""
    out = knock(125.0 / size, rng, 0.7, hollow=1.2)
    place(out, 0.5 * knock(210.0 / size, rng, 0.4), 0.0)
    slosh = fft_filter(rng.normal(size=len(out)), lambda f: peak(f, 500.0, 300.0)) * envelope(len(out), 0.04, 0.5, 4)
    return out + slosh * 0.3


def slide_whistle(rng, start, end, seconds):
    t = times(int(RATE * seconds))
    f = start * (end / start) ** (t / seconds) * (1.0 + 0.012 * np.sin(2.0 * np.pi * 6.0 * t))
    phase = 2.0 * np.pi * np.cumsum(f) / RATE
    breath = fft_filter(rng.normal(size=len(t)), lambda fr: peak(fr, 2500.0, 1500.0)) * 0.04
    tone = np.sin(phase) + 0.08 * np.sin(2 * phase)
    return (tone + breath) * np.minimum(1.0, t / 0.03) * np.minimum(1.0, (seconds - t) / 0.05)


def cork_pop(rng):
    t = times(int(RATE * 0.08))
    f = 1100.0 * np.exp(-t * 30.0) + 350.0
    pop = np.sin(2.0 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 45.0)
    pop[:60] += rng.uniform(-1.0, 1.0, 60) * np.linspace(1.0, 0.0, 60)
    return pop


def barrel(variant):
    """The wash-up gag, three ways (the writing has 2-3 variants of the
    line; the sound changes with it so it stays funny on repeat)."""
    rng = np.random.default_rng(300 + variant)
    out = np.zeros(int(RATE * 2.8))
    if variant == 1:
        # Washed in on a wave: splash, BONK, a smaller bounce, slosh.
        place(out, splash(rng, 0.6) * 0.6, 0.0)
        place(out, barrel_bonk(rng) * 0.9, 0.22)
        place(out, barrel_bonk(rng, 0.9) * 0.45, 0.58)
        place(out, barrel_bonk(rng, 0.85) * 0.2, 0.78)
        place(out, gull(rng, 1.05) * 0.18, 1.35)
    elif variant == 2:
        # Dropped from a height: a falling whistle, then the thud.
        place(out, slide_whistle(rng, 1900.0, 520.0, 0.75) * 0.35, 0.0)
        place(out, barrel_bonk(rng, 1.1) * 1.0, 0.78)
        place(out, splash(rng, 0.5, bright=0.8) * 0.4, 0.8)
        place(out, barrel_bonk(rng, 1.05) * 0.35, 1.12)
    else:
        # Rolled up the beach: a wooden rumble, a bump, and the lid pops.
        n = int(RATE * 0.9)
        roll = np.zeros(n)
        at = 0.0
        while at < 0.85:
            place(roll, knock(rng.uniform(150.0, 190.0), rng, 0.12) * rng.uniform(0.2, 0.4), at)
            at += rng.uniform(0.05, 0.09)
        place(out, roll * np.linspace(0.6, 1.0, n), 0.0)
        place(out, barrel_bonk(rng) * 0.9, 0.9)
        place(out, cork_pop(rng) * 0.5, 1.28)
        for k in range(8):
            place(out, bubble(rng, rng.uniform(1100.0, 1900.0), 0.02) * 0.12, 1.36 + k * rng.uniform(0.05, 0.1))
    return finish(out, rng, room=0.18)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make_stingers.py <out_dir>")
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    sounds = {
        "tide_down": tide_down(),
        "tide_up": tide_up(),
        "koban_vault": koban_vault(),
        "koban_wins": koban_wins(),
        "koban_beaten": koban_beaten(),
        "barrel_1": barrel(1),
        "barrel_2": barrel(2),
        "barrel_3": barrel(3),
    }
    for name, sound in sounds.items():
        write_ogg(os.path.join(out_dir, name + ".ogg"), sound)


if __name__ == "__main__":
    main()
