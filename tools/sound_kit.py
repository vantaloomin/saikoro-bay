"""Shared synth parts for the ambience and stinger scripts (M6 audio).

Everything here is numpy only, so the scripts run anywhere with numpy and
ffmpeg (with libvorbis), like tools/make_town_loop.py. Filters work in the
frequency domain: a whole-signal FFT for a fixed filter, or short
overlapping frames (stft_filter) for one that moves over time. With
circular=True both treat the signal as a loop, so a bed filtered that way
wraps with no seam.
"""

import subprocess
import tempfile
import wave

import numpy as np

RATE = 32000


def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def times(count):
    return np.arange(count) / RATE


def lowpass(freq, cutoff, order=2):
    """Butterworth-shaped magnitude: flat below `cutoff`, falling above."""
    return 1.0 / np.sqrt(1.0 + (np.asarray(freq) / cutoff) ** (2 * order))


def highpass(freq, cutoff, order=2):
    f = np.maximum(np.asarray(freq), 1.0)
    return 1.0 / np.sqrt(1.0 + (cutoff / f) ** (2 * order))


def peak(freq, centre, width):
    """A resonance: 1 at `centre`, half power `width` Hz either side."""
    return 1.0 / np.sqrt(1.0 + ((np.asarray(freq) - centre) / width) ** 2)


def fft_filter(signal, gain, circular=False):
    """Filters with a fixed magnitude response, gain(freqs) -> array. A
    circular filter treats the signal as one loop of a repeating sound."""
    count = len(signal)
    size = count if circular else count * 2
    freqs = np.fft.rfftfreq(size, 1.0 / RATE)
    out = np.fft.irfft(np.fft.rfft(signal, size) * gain(freqs), size)
    return out[:count]


def stft_filter(signal, gain, frame=1024, circular=False):
    """Filters with a response that moves: gain(freqs, seconds) returns a
    (frames, bins) array, one row per frame centre. Frames overlap by half
    under a root-Hann window, so an unchanging gain gives the input back."""
    hop = frame // 2
    window = np.sqrt(0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(frame) / frame))
    count = len(signal)
    if circular:
        if count % hop:
            raise ValueError("a circular signal must be a whole number of hops long")
        source = signal
        starts = np.arange(0, count, hop)
        index = (starts[:, None] + np.arange(frame)[None, :]) % count
        centres = (starts + frame / 2) / RATE
        length = count
    else:
        source = np.concatenate([np.zeros(frame), signal, np.zeros(frame + hop)])
        starts = np.arange(0, len(source) - frame + 1, hop)
        index = starts[:, None] + np.arange(frame)[None, :]
        centres = (starts - frame / 2) / RATE
        length = len(source)
    freqs = np.fft.rfftfreq(frame, 1.0 / RATE)
    spectrum = np.fft.rfft(source[index] * window, axis=1) * gain(freqs, centres)
    pieces = np.fft.irfft(spectrum, frame, axis=1) * window
    out = np.bincount(index.ravel(), weights=pieces.ravel(), minlength=length)
    return out if circular else out[frame: frame + count]


def noise(count, rng):
    return rng.uniform(-1.0, 1.0, count)


def pink(count, rng, circular=False):
    """Noise falling 3 dB an octave: softer and fuller than white."""
    return normalise(fft_filter(rng.normal(size=count), lambda f: 1.0 / np.sqrt(np.maximum(f, 20.0)), circular))


def normalise(signal, top=1.0):
    biggest = np.max(np.abs(signal))
    return signal * (top / biggest) if biggest > 0 else signal


def envelope(count, attack, release, curve=4.0):
    """Linear rise over `attack` seconds, exponential fall over the rest
    (`release` is roughly the time to fall to a fiftieth)."""
    t = times(count)
    rise = np.minimum(1.0, t / max(attack, 1e-4))
    fall = np.exp(-np.maximum(t - attack, 0.0) * curve / max(release, 1e-4))
    return rise * fall


def fade_ends(signal, seconds=0.01):
    n = min(int(seconds * RATE), len(signal) // 2)
    ramp = np.linspace(0.0, 1.0, n)
    out = signal.copy()
    out[:n] *= ramp
    out[len(out) - n:] *= ramp[::-1]
    return out


def place(track, sound, at, pan=0.0, wrap=False):
    """Adds `sound` at `at` seconds. A stereo track takes a pan from -1
    (left) to 1 (right). With wrap, what runs past the end comes back
    round to the start, for loops."""
    start = int(at * RATE)
    count = len(track)
    if wrap:
        index = (start + np.arange(len(sound))) % count
    else:
        end = min(count, start + len(sound))
        if end <= start:
            return
        index = np.arange(start, end)
        sound = sound[: end - start]
    if track.ndim == 1:
        np.add.at(track, index, sound)
    else:
        angle = (pan + 1.0) * np.pi / 4.0
        np.add.at(track[:, 0], index, sound * np.cos(angle) * np.sqrt(2.0))
        np.add.at(track[:, 1], index, sound * np.sin(angle) * np.sqrt(2.0))


def reverb(signal, seconds, decay, rng, circular=False):
    """A soft room: convolution with a decaying noise tail. Returns the wet
    signal (same length when circular, longer by the tail otherwise)."""
    t = times(int(RATE * seconds))
    impulse = rng.uniform(-1.0, 1.0, len(t)) * np.exp(-t * decay) * 0.06
    impulse[0] = 1.0
    if circular:
        size = len(signal)
        return np.fft.irfft(np.fft.rfft(signal, size) * np.fft.rfft(impulse, size), size)
    size = len(signal) + len(impulse)
    return np.fft.irfft(np.fft.rfft(signal, size) * np.fft.rfft(impulse, size), size)


def partials(freq, seconds, ratios, decays, amounts, click=0.0, rng=None):
    """A struck object as a sum of decaying sines: bells, chimes, coins,
    wood. `decays` are per-partial rates (bigger is shorter)."""
    t = times(int(RATE * seconds))
    out = np.zeros(len(t))
    for ratio, decay, amount in zip(ratios, decays, amounts):
        out += amount * np.sin(2.0 * np.pi * freq * ratio * t + (rng.uniform(0, 6.28) if rng is not None else 0.0)) \
            * np.exp(-t * decay)
    out *= np.minimum(1.0, t * 2000.0)
    if click and rng is not None:
        n = min(len(t), int(RATE * 0.004))
        out[:n] += click * rng.uniform(-1.0, 1.0, n) * np.linspace(1.0, 0.0, n)
    return out


def chime(freq, seconds, rng):
    """A hanging metal tube: the free-bar overtones, long ring."""
    return partials(freq, seconds, [1.0, 2.756, 5.404, 8.933], [1.1, 2.6, 6.0, 11.0], [1.0, 0.45, 0.2, 0.08],
                    click=0.15, rng=rng)


def bell(freq, seconds, rng, bright=1.0):
    """A small glass-and-steel bell, the palace's glitter."""
    return partials(freq, seconds, [1.0, 2.0, 3.01, 4.16, 5.43], [2.2, 3.5, 6.0, 9.0, 14.0],
                    [1.0, 0.5 * bright, 0.28 * bright, 0.16 * bright, 0.08 * bright], click=0.05, rng=rng)


def coin(rng, freq=None, seconds=0.5):
    """One gold coin's ting: high, close, inharmonic."""
    f = freq if freq is not None else rng.uniform(2600.0, 4200.0)
    return partials(f, seconds, [1.0, 1.47, 2.09, 2.76], [9.0, 12.0, 16.0, 22.0], [1.0, 0.6, 0.35, 0.2],
                    click=0.4, rng=rng)


def chip_click(rng, bright=1.0):
    """A clay chip landing on another: a short, dry clack."""
    n = int(RATE * 0.03)
    t = times(n)
    burst = rng.uniform(-1.0, 1.0, n) * np.exp(-t * 260.0)
    centre = rng.uniform(1800.0, 2800.0) * bright
    body = fft_filter(burst, lambda f: peak(f, centre, 700.0))
    tone = 0.4 * np.sin(2.0 * np.pi * centre * 0.62 * t) * np.exp(-t * 180.0)
    return body + tone


def knock(freq, rng, seconds=0.6, hollow=1.0):
    """Wood struck: a few low modes that die fast, plus the hit."""
    return partials(freq, seconds, [1.0, 1.58, 2.24, 3.45, 5.3], [9.0, 13.0, 18.0, 28.0, 40.0],
                    [1.0, 0.7 * hollow, 0.5 * hollow, 0.25, 0.12], click=0.6, rng=rng)


def bubble(rng, freq=None, seconds=None):
    """One bubble: a short sine that glides up as it closes (Minnaert)."""
    f0 = freq if freq is not None else rng.uniform(350.0, 1100.0)
    d = seconds if seconds is not None else rng.uniform(0.03, 0.08)
    t = times(int(RATE * d * 3))
    f = f0 * (1.0 + 2.2 * t / d)
    phase = 2.0 * np.pi * np.cumsum(f) / RATE
    return np.sin(phase) * np.exp(-t * 4.0 / d) * np.minimum(1.0, t * 3000.0)


def gull(rng, pitch=1.0):
    """A herring gull's 'kyow': a quick rise, then a long rough fall."""
    d = rng.uniform(0.32, 0.5)
    t = times(int(RATE * d))
    u = t / d
    contour = np.where(u < 0.18, 1300.0 + (2150.0 - 1300.0) * u / 0.18,
                       2150.0 - (2150.0 - 1150.0) * (np.maximum(u - 0.18, 0.0) / 0.82) ** 0.8) * pitch
    phase = 2.0 * np.pi * np.cumsum(contour) / RATE
    tone = sum(np.sin(k * phase) / k ** 1.3 for k in range(1, 6))
    tone *= 1.0 + 0.45 * np.sin(2.0 * np.pi * 48.0 * t)
    shape = np.minimum(1.0, t / 0.02) * np.minimum(1.0, (d - t) / 0.06) * (1.0 - 0.4 * u)
    return fft_filter(tone * shape, lambda f: highpass(f, 700.0) * lowpass(f, 4200.0))


def write_ogg(path, samples, quality=4):
    """Writes mono (n,) or stereo (n, 2) samples in -1..1 as Ogg Vorbis."""
    data = np.clip(np.asarray(samples), -1.0, 1.0)
    channels = 1 if data.ndim == 1 else data.shape[1]
    with tempfile.NamedTemporaryFile(suffix=".wav") as raw:
        with wave.open(raw.name, "wb") as wav:
            wav.setnchannels(channels)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes((data * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw.name, "-c:a", "libvorbis",
                        "-q:a", str(quality), path], check=True)
