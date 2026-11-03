"""Makes the town's placeholder music loop (M3 PR 5c).

two-halves section 1: major pentatonic, acoustic, koto and marimba plucks,
waves underneath. Everything is synthesized from a fixed seed, so running
this again makes the same file:

    python3 tools/make_town_loop.py content/sfw/music/town_loop.ogg

Needs numpy and ffmpeg (with libvorbis). The loop is seamless: whatever
rings past the end is folded back onto the start.
"""

import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 32000
BPM = 80
BEAT = 60.0 / BPM
BARS = 16
LENGTH = BARS * 4 * BEAT
# D major pentatonic: D E F# A B.
PENTATONIC = [0, 2, 4, 7, 9]
ROOT = 62  # D4
# Two bars on each chord, played twice: D, Bm, G, A.
CHORDS = [(50, [0, 4, 7]), (47, [0, 3, 7]), (43, [0, 4, 7]), (45, [0, 4, 7])]


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def koto(freq, seconds, rng):
    """A plucked string (Karplus-Strong) with a bright attack."""
    period = int(RATE / freq)
    count = int(RATE * seconds)
    buf = rng.uniform(-1.0, 1.0, period)
    # Pluck near the bridge: a thinner, brighter start.
    buf = buf - np.roll(buf, period // 5)
    out = np.zeros(count)
    for i in range(count):
        j = i % period
        out[i] = buf[j]
        buf[j] = 0.996 * 0.5 * (buf[j] + buf[(j + 1) % period])
    t = np.arange(count) / RATE
    return out * np.exp(-t * 2.2) * 0.5


def marimba(freq, seconds):
    """A struck bar: a fundamental and two quickly fading overtones."""
    t = np.arange(int(RATE * seconds)) / RATE
    tone = np.sin(2 * np.pi * freq * t) * np.exp(-t * 5.0)
    tone += 0.35 * np.sin(2 * np.pi * freq * 3.93 * t) * np.exp(-t * 18.0)
    tone += 0.12 * np.sin(2 * np.pi * freq * 9.2 * t) * np.exp(-t * 40.0)
    attack = np.minimum(1.0, t * 600.0)
    return tone * attack * 0.45


def waves(count, rng):
    """Surf: low, soft noise that swells in and out twice a loop. It's
    shaped in the frequency domain over exactly one loop, so it wraps with
    no seam."""
    spectrum = np.fft.rfft(rng.normal(size=count))
    freq = np.fft.rfftfreq(count, 1.0 / RATE)
    spectrum *= (freq > 40.0) / (1.0 + freq / 350.0) ** 2
    noise = np.fft.irfft(spectrum, count)
    noise /= np.max(np.abs(noise))
    t = np.arange(count) / RATE
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * t * 2 / LENGTH) ** 2
    return noise * swell * 0.18


def place(track, sound, at):
    start = int(at * RATE)
    end = start + len(sound)
    if end > len(track):
        sound = sound[: len(track) - start]
        end = len(track)
    track[start:end] += sound


def melody(rng):
    """Short phrases on the pentatonic, mostly stepwise, with rests."""
    notes = []
    step = 2
    for bar in range(BARS):
        rest_bar = bar % 4 == 3
        for eighth in range(8):
            if rest_bar and eighth > 2:
                continue
            if rng.random() < (0.55 if eighth % 2 == 0 else 0.25):
                step = int(np.clip(step + rng.choice([-2, -1, -1, 1, 1, 2]), 0, 9))
                octave, degree = divmod(step, 5)
                notes.append((bar * 4 * BEAT + eighth * BEAT / 2, ROOT + 12 * octave + PENTATONIC[degree]))
    return notes


def reverb(track, rng):
    """A soft room: convolve with a short decaying noise tail."""
    t = np.arange(int(RATE * 1.4)) / RATE
    impulse = rng.uniform(-1.0, 1.0, len(t)) * np.exp(-t * 4.0) * 0.05
    impulse[0] = 1.0
    size = len(track) + len(impulse)
    wet = np.fft.irfft(np.fft.rfft(track, size) * np.fft.rfft(impulse, size), size)
    return wet


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make_town_loop.py <out.ogg>")
    rng = np.random.default_rng(23)
    loop = int(LENGTH * RATE)
    track = np.zeros(loop + RATE * 3)
    for bar in range(BARS):
        bass, shape = CHORDS[(bar // 2) % 4]
        for beat in range(4):
            note = bass + (shape[[0, 2, 1, 2][beat]] if beat else 0) + (12 if beat else 0)
            place(track, marimba(hz(note), 1.2) * (1.0 if beat == 0 else 0.6), bar * 4 * BEAT + beat * BEAT)
    for at, note in melody(rng):
        place(track, koto(hz(note), 1.6, rng), at)
    track = reverb(track, rng)
    # Fold the tail back onto the start, so the loop is seamless.
    tail = track[loop:]
    out = track[:loop].copy()
    out[: len(tail)] += tail[: loop]
    out += waves(loop, rng)
    out *= 0.8 / np.max(np.abs(out))
    with tempfile.NamedTemporaryFile(suffix=".wav") as raw:
        with wave.open(raw.name, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes((out * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw.name, "-c:a", "libvorbis", "-q:a", "3",
                        sys.argv[1]], check=True)


if __name__ == "__main__":
    main()
