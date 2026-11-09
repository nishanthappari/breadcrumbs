"""Synthesise Breadcrumbs' soft two-note chime (a rising fifth, bell-like partials) to a WAV."""
import math, struct, sys, wave

SR = 44100
DUR = 1.9
OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/chime.wav"

def bell(t, f, amp):
    if t < 0:
        return 0.0
    attack = min(1.0, t / 0.012)                 # 12 ms soft attack, no click
    partials = [(1.0, 1.0, 1.6), (2.0, 0.28, 0.9), (2.76, 0.10, 0.6), (5.4, 0.03, 0.3)]
    s = 0.0
    for mult, a, decay in partials:
        s += a * math.exp(-t / (decay * 0.55)) * math.sin(2 * math.pi * f * mult * t)
    return amp * attack * s

frames = bytearray()
peak = 0.0
samples = []
for i in range(int(SR * DUR)):
    t = i / SR
    v = bell(t, 659.25, 0.42) + bell(t - 0.14, 987.77, 0.34)   # E5 then B5
    samples.append(v)
    peak = max(peak, abs(v))
gain = 0.6 / peak
fade = int(SR * 0.25)
for i, v in enumerate(samples):
    if i > len(samples) - fade:
        v *= (len(samples) - i) / fade
    frames += struct.pack("<h", int(max(-1, min(1, v * gain)) * 32767))

with wave.open(OUT, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(bytes(frames))
print(OUT)
