#!/usr/bin/env python3
"""App Store posterleri: ekran görüntülerini başlıklı, çerçeveli posterlere yerleştirir.

    python3 tool/make_posters.py

Girdi : app_store_ekran_goruntuleri/<cihaz>/N_*.png
Çıktı : app_store_posterler/<cihaz>/N_*.png (aynı App Store boyutları, RGB)
Metinlerde yalnızca uygulamanın gerçekten yaptığı şeyler yazılır.
"""
import glob
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

INK = (30, 27, 24)
PAPER = (244, 238, 223)
RED = (214, 92, 76)  # koyu zeminde okunur baskı kırmızısı
SOFT = (200, 192, 176)

TEXTS = {
    1: ("Gazetenin bulmaca keyfi,\ndijitalin rahatlığı", "Her sayfada iki bulmaca"),
    2: ("Sayfayı gerçekten\nçevirin", "Köşeden kıvrılan kâğıt hissi"),
    3: ("Yazdıkça anında\ngeri bildirim", "Yanlış harf kırmızı, doğru kelime yeşil"),
    4: ("Sudoku, üç zorlukta", "Notlar, ipuçları ve geri alma"),
    5: ("Çengel, kare ve klasik", "Her türde 100 özgün bulmaca, çevrimdışı"),
}


def font(path, size, axes=None):
    f = ImageFont.truetype(path, size)
    if axes:
        try:
            f.set_variation_by_axes(axes)
        except Exception:
            pass
    return f


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m


def poster(src, out, num, W, H, phone):
    landscape = W > H
    shot = Image.open(src).convert("RGB")
    bg = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(bg)

    # Gazete çizgileri (başlığın üstünde ve altında çift çizgi).
    mx = int(W * 0.09)
    top = int(H * 0.045)
    d.rectangle([mx, top, W - mx, top + 6], fill=PAPER)
    d.rectangle([mx, top + 14, W - mx, top + 16], fill=PAPER)

    head, sub = TEXTS[num]
    hs = int(W * (0.088 if phone else (0.040 if landscape else 0.062)))
    hf = font("assets/fonts/PlayfairDisplay.ttf", hs, [800])
    # Başlık satırları kenar boşlukları içinde kalana dek küçült.
    limit = W - 2 * mx
    while max(d.textlength(l, font=hf) for l in head.split("\n")) > limit and hs > 20:
        hs -= 4
        hf = font("assets/fonts/PlayfairDisplay.ttf", hs, [800])
    sf = font("assets/fonts/SourceSans3.ttf", int(hs * 0.42), [600])
    y = top + int(H * 0.035)
    for line in head.split("\n"):
        w = d.textlength(line, font=hf)
        d.text(((W - w) / 2, y), line, font=hf, fill=PAPER)
        y += int(hs * 1.18)
    y += int(hs * 0.12)
    w = d.textlength(sub, font=sf)
    d.text(((W - w) / 2, y), sub, font=sf, fill=RED)
    y += int(hs * 0.42 * 1.6)

    # Cihaz: ekran görüntüsü yuvarlak köşeli, siyah çerçeveli, gölgeli.
    if landscape:
        # Yatay tablet: cihaz tamamen görünür, yüksekliğe göre sığdırılır.
        sh = int(H - y - H * 0.05)
        sw = int(shot.width * sh / shot.height)
    else:
        sw = int(W * 0.80)
        sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    rad = int(sw * (0.095 if phone else 0.030))
    bez = int(sw * 0.018)
    x0 = (W - sw) // 2
    y0 = y + int(H * 0.012)
    frame = Image.new("RGBA", (sw + 2 * bez, sh + 2 * bez), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        [0, 0, frame.width - 1, frame.height - 1], rad + bez, fill=(8, 8, 8, 255)
    )
    frame.paste(shot, (bez, bez), rounded_mask(shot.size, rad))
    # Gölge
    shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        [x0 - bez, y0 - bez + 30, x0 + sw + bez, y0 + sh + bez + 30], rad + bez, fill=(0, 0, 0, 170)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(36))
    bg = Image.alpha_composite(bg.convert("RGBA"), shadow)
    bg.paste(frame, (x0 - bez, y0 - bez), frame)
    bg = bg.convert("RGB")  # saydamlık yok
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bg.save(out, "PNG", optimize=True)


def ensure_raw_63():
    """iPhone 6.3" (1206x2622) ham ekran görüntüleri: 6.9" görüntülerden ölçeklenir
    (en-boy oranları neredeyse aynı: 0.4603 / 0.4599)."""
    out = "app_store_ekran_goruntuleri/iPhone_6.3_inc_1206x2622"
    os.makedirs(out, exist_ok=True)
    for src in sorted(glob.glob("app_store_ekran_goruntuleri/iPhone_6.9_inc_1320x2868/*.png")):
        im = Image.open(src).convert("RGB").resize((1206, 2622), Image.LANCZOS)
        im.save(os.path.join(out, os.path.basename(src)), "PNG", optimize=True)


def main():
    ensure_raw_63()
    # (poster genişliği, yüksekliği, telefon mu, kaynak ekran görüntüsü klasörü)
    sets = {
        "iPhone_6.9_inc_1320x2868": (1320, 2868, True, "iPhone_6.9_inc_1320x2868"),
        "iPhone_6.3_inc_1206x2622": (1206, 2622, True, "iPhone_6.9_inc_1320x2868"),
        "iPad_13_inc_yatay_2752x2064": (2752, 2064, False, "iPad_13_inc_yatay_2752x2064"),
    }
    for folder, (W, H, phone, srcfolder) in sets.items():
        for src in sorted(glob.glob(f"app_store_ekran_goruntuleri/{srcfolder}/*.png")):
            num = int(os.path.basename(src).split("_")[0])
            out = f"app_store_posterler/{folder}/{os.path.basename(src)}"
            poster(src, out, num, W, H, phone)
            print(out)


if __name__ == "__main__":
    main()
