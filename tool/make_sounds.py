#!/usr/bin/env python3
"""Özgün ses efektleri (sentez). Telifli ses kullanılmaz.

    python3 tool/make_sounds.py

Çıktı: assets/sounds/*.wav (mono, 16 bit, 32 kHz). Gürültü + süzgeç + zarf ile
kalem hışırtısı, silgi ve gazete sayfası çevirme sesi üretilir.
"""
import wave
import numpy as np

SR = 32000


def band(noise, lo, hi):
    spec = np.fft.rfft(noise)
    f = np.fft.rfftfreq(len(noise), 1 / SR)
    mask = np.clip((f - lo) / (lo * 0.3 + 1), 0, 1) * np.clip((hi - f) / (hi * 0.3 + 1), 0, 1)
    return np.fft.irfft(spec * mask, len(noise))


def env_strokes(n, rng, strokes):
    e = np.zeros(n)
    for _ in range(strokes):
        c = rng.integers(int(n * 0.05), int(n * 0.85))
        w = rng.integers(int(SR * 0.012), int(SR * 0.035))
        a = rng.uniform(0.5, 1.0)
        x = np.arange(n)
        e += a * np.exp(-0.5 * ((x - c) / w) ** 2)
    return np.clip(e, 0, 1)


def thump(n, at, freq, dur, amp):
    t = np.arange(n)
    x = np.zeros(n)
    k = np.arange(int(SR * dur))
    seg = np.sin(2 * np.pi * freq * k / SR) * np.exp(-k / (SR * dur * 0.25))
    end = min(n, at + len(seg))
    x[at:end] += amp * seg[: end - at]
    return x


def save(name, x, peak=0.75):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = int(SR * 0.004)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(f"assets/sounds/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(name, len(x) / SR, "s")


def pen(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * rng.uniform(0.10, 0.15))
    noise = rng.standard_normal(n)
    body = band(noise, 1800, 7500) * env_strokes(n, rng, rng.integers(3, 6))
    tap = thump(n, 0, rng.uniform(220, 380), 0.012, 0.9)
    return body * 0.8 + tap * 0.35 + band(rng.standard_normal(n), 300, 900) * env_strokes(n, rng, 2) * 0.08


def erase(seed):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.30)
    noise = rng.standard_normal(n)
    rub = 0.55 + 0.45 * np.sin(2 * np.pi * 7.5 * np.arange(n) / SR)
    shape = np.sin(np.linspace(0, np.pi, n)) ** 0.7
    return band(noise, 700, 3800) * rub * shape


def page(seed, rev=False):
    rng = np.random.default_rng(seed)
    n = int(SR * 0.95)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    swish = band(noise, 900, 6500)
    # Yavaş yükselen, sonra hızlı sönen zarf + kağıt çıtırtısı titreşimi.
    rise = np.where(t < 0.42, (t / 0.42) ** 1.6, np.exp(-(t - 0.42) / 0.11))
    flutter = 0.65 + 0.35 * np.sin(2 * np.pi * rng.uniform(26, 46) * t + rng.uniform(0, 6))
    x = swish * rise * flutter
    # Çıtırtılar.
    for _ in range(rng.integers(26, 40)):
        c = int(rng.uniform(0.05, 0.75) * n)
        w = int(SR * rng.uniform(0.0008, 0.003))
        k = np.arange(-w * 4, w * 4)
        click = np.exp(-0.5 * (k / w) ** 2) * rng.choice([-1, 1]) * rng.uniform(0.2, 0.9)
        lo, hi = max(0, c - w * 4), min(n, c + w * 4)
        x[lo:hi] += band(rng.standard_normal(n), 2500, 9000)[lo:hi] * 0 + click[: hi - lo] * 0.5
    x += thump(n, int(SR * 0.50), 150, 0.05, 0.45)
    if rev:
        x = x[::-1].copy()
    return x


if __name__ == "__main__":
    for i, s in enumerate([11, 23, 37], 1):
        save(f"pen{i}", pen(s), 0.7)
    save("erase", erase(5), 0.6)
    save("page_forward", page(3), 0.8)
    save("page_back", page(9, rev=True), 0.8)
