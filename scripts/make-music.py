# Synthesizes a soft ambient/electronic bed for the demo video. Pure numpy, no samples, no license.
# Run: python3 scripts/make-music.py  -> build/music.wav
import numpy as np, wave, os
SR = 44100; DUR = 43.0; BPM = 88
t = np.arange(int(SR * DUR)) / SR
beat = 60 / BPM
def note(midi): return 440 * 2 ** ((midi - 69) / 12)
def env(x, a, r):  # attack/release
    return np.minimum(1, x / a) * np.minimum(1, np.maximum(0, (1 - x)) / r)

# chords: Am9 - Fmaj7 - Cmaj9 - G6, 2 bars each (8 beats)
chords = [[57,64,67,71,76],[53,60,64,69,72],[48,55,64,67,74],[55,59,62,64,69]]
bar = beat * 8
mix = np.zeros_like(t)
# pad
for i in range(int(np.ceil(DUR / bar))):
    ch = chords[i % 4]
    s = i * bar; seg = (t >= s) & (t < s + bar); x = (t[seg] - s) / bar
    for m in ch:
        f = note(m)
        w = np.zeros(seg.sum())
        for d in (-0.4, 0, 0.4):  # detune
            fd = f * 2 ** (d / 1200)
            w += np.sin(2 * np.pi * fd * t[seg]) + 0.3 * np.sin(2 * np.pi * fd * 2 * t[seg])
        mix[seg] += w * env(x, 0.25, 0.25) * 0.045
# bass
for i in range(int(np.ceil(DUR / bar))):
    root = chords[i % 4][0] - 12
    for b in range(8):
        s = i * bar + b * beat
        seg = (t >= s) & (t < s + beat); x = (t[seg] - s) / beat
        if b % 2 == 0:
            mix[seg] += np.sin(2 * np.pi * note(root) * t[seg]) * env(x, 0.02, 0.4) * 0.12
# soft kick + hat
for b in range(int(DUR / beat)):
    s = b * beat
    seg = (t >= s) & (t < s + 0.25); x = t[seg] - s
    mix[seg] += np.sin(2 * np.pi * (55 + 80 * np.exp(-x * 30)) * x) * np.exp(-x * 14) * 0.25
    for h in (0.5,):
        sh = s + beat * h; seg = (t >= sh) & (t < sh + 0.08); x = t[seg] - sh
        mix[seg] += np.random.uniform(-1, 1, seg.sum()) * np.exp(-x * 90) * 0.035
# arpeggio sparkle
rng = np.random.default_rng(3)
for i in range(int(np.ceil(DUR / bar))):
    ch = chords[i % 4]
    for k in range(16):
        s = i * bar + k * beat / 2
        m = ch[(k * 3) % len(ch)] + 12
        seg = (t >= s) & (t < s + 0.5); x = t[seg] - s
        mix[seg] += np.sin(2 * np.pi * note(m) * x) * np.exp(-x * 7) * 0.05
# gentle lowpass (one-pole) and master fade
y = np.zeros_like(mix); a = 0.15
for i in range(1, len(mix)): pass
from numpy.lib.stride_tricks import sliding_window_view
k = 24; y = np.convolve(mix, np.ones(k) / k, mode="same")
fade = np.minimum(1, t / 2.0) * np.minimum(1, np.maximum(0, DUR - t) / 3.0)
y = y * fade
y = y / np.max(np.abs(y)) * 0.6
os.makedirs("build", exist_ok=True)
with wave.open("build/music.wav", "w") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((y * 32767).astype(np.int16).tobytes())
print("build/music.wav", len(y) / SR, "s")
