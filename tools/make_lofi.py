"""Render original lo-fi hip hop background tracks for Happy Pets.

Everything is synthesised from scratch (electric piano, bass, boom-bap drums,
vinyl crackle, tape wobble), so the music is free to upload to Roblox.

Usage:  python3 tools/make_lofi.py [output_dir]
Needs numpy and ffmpeg (with libvorbis). Writes one .ogg per track.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np

SR = 44100


def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def fft_filter(x, low=None, high=None):
    """Zero-phase band filter with soft (raised-cosine) edges."""
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    gain = np.ones_like(f)
    if high:
        gain *= np.clip(1 - (f - high) / (high * 0.5), 0, 1) ** 2
    if low:
        gain *= np.clip((f - low * 0.5) / (low * 0.5), 0, 1) ** 2
    return np.fft.irfft(spec * gain, n)


def env(n, attack, decay):
    t = np.arange(n) / SR
    a = np.minimum(1, t / max(attack, 1e-4))
    return a * np.exp(-t / decay)


def epiano(freq, dur, vel, rng):
    """FM-style electric piano note with a soft bell attack."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    detune = 1 + rng.uniform(-0.0015, 0.0015)
    index = 1.6 * np.exp(-t / 0.35) + 0.25
    mod = np.sin(2 * np.pi * freq * detune * t)
    tone = np.sin(2 * np.pi * freq * detune * t + index * mod)
    tone += 0.15 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t / 0.08)
    return tone * env(n, 0.006, 1.6) * vel


def kick(rng):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 45 + 85 * np.exp(-t / 0.045)
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * np.exp(-t / 0.22)
    click = rng.normal(0, 1, n) * np.exp(-t / 0.004) * 0.15
    return np.tanh((body + click) * 1.6) * 0.9


def snare(rng):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    noise = fft_filter(rng.normal(0, 1, n), low=900, high=7000) * np.exp(-t / 0.11)
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.06)
    return (noise * 0.55 + body * 0.5) * 0.75


def hat(rng, open_=False):
    n = int((0.25 if open_ else 0.07) * SR)
    t = np.arange(n) / SR
    noise = fft_filter(rng.normal(0, 1, n), low=6500)
    return noise * np.exp(-t / (0.09 if open_ else 0.018)) * 0.14


def add(buf, sig, start, gain=1.0, pan=0.0):
    s = int(start)
    if s >= buf.shape[1]:
        return
    e = min(buf.shape[1], s + len(sig))
    seg = sig[: e - s] * gain
    buf[0, s:e] += seg * (1 - max(0, pan))
    buf[1, s:e] += seg * (1 + min(0, pan))


def render(title, bpm, chords, bass_roots, melody_scale, seed, bars, out_dir):
    rng = np.random.default_rng(seed)
    beat = 60 / bpm
    bar = beat * 4
    total = int(bars * bar * SR)
    music = np.zeros((2, total + SR * 3))
    drums = np.zeros_like(music)

    # Song map: which parts play in each bar. The ending matches the start so
    # the track loops smoothly in-game.
    def section(b):
        if b < 4 or b >= bars - 2:
            return "intro"
        if (b - 4) % 16 >= 12:
            return "break"
        return "full" if (b - 4) % 16 >= 4 else "groove"

    swing = beat * 0.5 * 0.16  # late 8th-note offbeats
    for b in range(bars):
        part = section(b)
        t0 = b * bar
        chord = chords[b % len(chords)]
        root = bass_roots[b % len(bass_roots)]

        # Electric piano: chord on beat 1 (slightly strummed) and a softer
        # re-hit on the "and" of 3.
        for hit_time, vel in ((0.0, 0.33), (beat * 2.5 + swing, 0.2)):
            for i, note in enumerate(chord):
                start = t0 + hit_time + i * 0.012 + rng.uniform(0, 0.006)
                pan = (i / max(1, len(chord) - 1) - 0.5) * 0.6
                add(music, epiano(midi_hz(note), bar * 0.95, vel * rng.uniform(0.85, 1.0), rng), start * SR, 1.0, pan)

        # Bass.
        if part in ("groove", "full"):
            for pos, length, note in ((0, 1.5, root), (beat * 1.5 + swing, 0.5, root), (beat * 2.5 + swing, 1.4, root + 7 if b % 2 else root + 12)):
                n = int(length * beat * SR)
                tt = np.arange(n) / SR
                f = midi_hz(note - 24)
                sig = np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)
                sig = np.tanh(sig * 1.4) * env(n, 0.01, length * beat * 0.8) * 0.42
                add(music, sig, (t0 + pos) * SR)

        # Drums: a lazy boom-bap with swung hats.
        if part in ("groove", "full"):
            kicks = [0, beat * 1.5 + swing, beat * 2.25] if b % 2 == 0 else [0, beat * 2.5 + swing, beat * 2.75 + swing * 0.5]
            for k in kicks:
                add(drums, kick(rng), (t0 + k) * SR, 0.95)
            for s in (beat, beat * 3):
                add(drums, snare(rng), (t0 + s + rng.uniform(0.004, 0.014)) * SR, 0.8, 0.05)
            for i in range(8):
                pos = i * beat / 2 + (swing if i % 2 else 0)
                open_ = i == 7 and b % 4 == 3
                add(drums, hat(rng, open_), (t0 + pos) * SR, rng.uniform(0.6, 1.0) * (0.9 if i % 2 else 1.1), 0.3)
        elif part == "break":
            add(drums, hat(rng, True), (t0 + beat * 3.5) * SR, 0.5, 0.3)

        # A sparse, dreamy melody in the "full" sections.
        if part == "full":
            for step in range(8):
                if rng.random() < 0.38:
                    note = melody_scale[rng.integers(len(melody_scale))] + 12
                    start = t0 + step * beat / 2 + (swing if step % 2 else 0)
                    tone = epiano(midi_hz(note), beat * 1.5, 0.2, rng)
                    add(music, tone, start * SR, 1.0, rng.uniform(-0.4, 0.4))

    # Tape wobble on the melodic parts (gentle pitch drift).
    n = music.shape[1]
    t = np.arange(n) / SR
    drift = 0.0035 * np.sin(2 * np.pi * 0.45 * t) + 0.0012 * np.sin(2 * np.pi * 5.1 * t)
    idx = np.clip(np.arange(n) + np.cumsum(drift), 0, n - 1)
    music = np.stack([np.interp(idx, np.arange(n), ch) for ch in music])

    # Sidechain-style pump from the kick, then glue everything together.
    kick_env = np.abs(drums).mean(axis=0)
    kick_env = np.convolve(kick_env, np.ones(int(0.08 * SR)) / int(0.08 * SR), mode="same")
    music *= 1 - 0.35 * np.clip(kick_env / (kick_env.max() + 1e-9) * 3, 0, 1)
    mix = music + drums * 0.85

    # Vinyl: hiss plus random crackles.
    hiss = np.stack([fft_filter(rng.normal(0, 1, n), low=2000, high=9000) for _ in range(2)]) * 0.004
    crackle = np.zeros((2, n))
    pops = rng.integers(0, n - 200, size=int(n / SR * 9))
    for p in pops:
        amp = rng.uniform(0.02, 0.12) * rng.choice([-1, 1])
        crackle[rng.integers(2), p : p + 40] += amp * np.exp(-np.arange(40) / 6)
    mix += hiss + crackle

    # Warm, dusty top end and soft saturation.
    mix = np.stack([fft_filter(ch, low=35, high=4800) for ch in mix])
    mix = np.tanh(mix * 0.9)
    mix = mix[:, :total]
    # Short fades so the loop point doesn't click.
    fade = int(0.05 * SR)
    mix[:, :fade] *= np.linspace(0, 1, fade)
    mix[:, -fade:] *= np.linspace(1, 0, fade)
    mix /= np.abs(mix).max() + 1e-9
    mix *= 0.7

    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{title}.ogg"
    pcm = (mix.T * 32767).astype("<i2").tobytes()
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "5", str(out)],
        input=pcm,
        check=True,
    )
    print(f"Wrote {out} ({total / SR:.0f} s)")


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "assets" / "audio"
    # C major 9 – A minor 9 – D minor 9 – G13: sunny and lazy.
    render(
        "lofi_sunny_window",
        bpm=76,
        chords=[[48, 52, 55, 59, 62], [45, 52, 55, 59, 60], [50, 53, 57, 60, 64], [43, 53, 57, 59, 64]],
        bass_roots=[48, 45, 50, 43],
        melody_scale=[60, 62, 64, 67, 69, 72],
        seed=11,
        bars=42,
        out_dir=out_dir,
    )
    # F major 7 – E minor 7 – A minor 7 – D minor 9: a rainy-day nap.
    render(
        "lofi_rainy_nap",
        bpm=70,
        chords=[[41, 52, 57, 60, 64], [40, 50, 55, 59, 62], [45, 52, 55, 60, 64], [38, 53, 57, 60, 64]],
        bass_roots=[41, 40, 45, 38],
        melody_scale=[57, 60, 62, 64, 67, 69],
        seed=23,
        bars=38,
        out_dir=out_dir,
    )


if __name__ == "__main__":
    main()
