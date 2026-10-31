#!/usr/bin/env python3
"""Uygulama ikonu üretimi (özgün tasarım, PIL ile çizilir).

    python3 tool/make_icon.py

Tasarım: mürekkep siyahı zemin, kâğıt rengi harf kutuları; yatayda BULMA,
dikeyde KALEM bulmaca gibi kesişir, kesişim hücresi baskı kırmızısıdır.
Çıktı: assets/icon/*, iOS AppIcon seti, Android mipmap ve adaptive ikon.
"""
import os
from PIL import Image, ImageDraw, ImageFont

INK = (30, 27, 24)
PAPER = (244, 238, 223)
RED = (142, 43, 33)
FONT = "assets/fonts/PlayfairDisplay.ttf"
S = 1024


def font(size):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([800])  # ExtraBold
    except Exception:
        pass
    return f


def draw_grid(img, scale=1.0, bg=True):
    """5x5 çarpı biçimli bulmaca. scale<1: Android adaptive güvenli alan."""
    d = ImageDraw.Draw(img)
    cell = int(150 * scale)
    gap = int(8 * scale)
    total = cell * 5 + gap * 4
    x0 = (S - total) // 2
    y0 = (S - total) // 2
    across = "BULMA"  # satır 3
    down = "KALEM"  # sütun 3
    cells = {}
    for i, ch in enumerate(across):
        cells[(2, i)] = ch
    for i, ch in enumerate(down):
        cells[(i, 2)] = ch
    f = font(int(cell * 0.78))
    for (r, c), ch in cells.items():
        x = x0 + c * (cell + gap)
        y = y0 + r * (cell + gap)
        fill = RED if (r, c) == (2, 2) else PAPER
        ink = PAPER if (r, c) == (2, 2) else INK
        d.rectangle([x, y, x + cell, y + cell], fill=fill)
        bbox = d.textbbox((0, 0), ch, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text((x + (cell - tw) / 2 - bbox[0], y + (cell - th) / 2 - bbox[1] - cell * 0.02),
               ch, font=f, fill=ink)
        if (r, c) in [(0, 2), (2, 0)]:  # küçük soru numarası
            nf = font(int(cell * 0.2))
            d.text((x + cell * 0.07, y + cell * 0.03), "1" if r == 0 else "2", font=nf, fill=(90, 84, 75))
    return img


def master():
    img = Image.new("RGB", (S, S), INK)
    d = ImageDraw.Draw(img)
    # Gazete başlığı çizgileri: üstte ve altta çift ince çizgi.
    for y in (62, 74):
        d.rectangle([110, y, S - 110, y + (6 if y == 62 else 2)], fill=PAPER)
    for y in (S - 82, S - 70):
        d.rectangle([110, y, S - 110, y + (2 if y == S - 82 else 6)], fill=PAPER)
    return draw_grid(img, 1.0)


def save(img, path, size, rgba=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = img.resize((size, size), Image.LANCZOS)
    if not rgba:
        out = out.convert("RGB")  # iOS: alfa kanalı olmamalı
    out.save(path, "PNG", optimize=True)


def main():
    m = master()
    save(m, "assets/icon/icon_1024.png", 1024)

    # iOS
    ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    sizes = {
        "Icon-App-20x20@1x": 20, "Icon-App-20x20@2x": 40, "Icon-App-20x20@3x": 60,
        "Icon-App-29x29@1x": 29, "Icon-App-29x29@2x": 58, "Icon-App-29x29@3x": 87,
        "Icon-App-40x40@1x": 40, "Icon-App-40x40@2x": 80, "Icon-App-40x40@3x": 120,
        "Icon-App-60x60@2x": 120, "Icon-App-60x60@3x": 180,
        "Icon-App-76x76@1x": 76, "Icon-App-76x76@2x": 152,
        "Icon-App-83.5x83.5@2x": 167, "Icon-App-1024x1024@1x": 1024,
    }
    for name, px in sizes.items():
        save(m, f"{ios}/{name}.png", px)

    # Android eski (kare) ikonlar
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for k, px in legacy.items():
        save(m, f"android/app/src/main/res/mipmap-{k}/ic_launcher.png", px)

    # Android adaptive: ön plan (şeffaf, güvenli alanda) + arka plan rengi
    fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_grid(fg, 0.62)
    ad = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for k, px in ad.items():
        save(fg, f"android/app/src/main/res/mipmap-{k}/ic_launcher_foreground.png", px, rgba=True)
    os.makedirs("android/app/src/main/res/mipmap-anydpi-v26", exist_ok=True)
    open("android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')
    open("android/app/src/main/res/values/ic_launcher_background.xml", "w").write(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#1E1B18</color>\n</resources>\n')
    print("İkonlar yazıldı.")


if __name__ == "__main__":
    main()
