"""
Farketmez launcher icon generator — clockwise curl + crossbar + dot (reads as "F")
Same glyph geometry as the first character in assets/logo.svg, centered and
enlarged on a navy square for use as the Android launcher icon.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SIZES = {
    "mipmap-mdpi":    48,
    "mipmap-hdpi":    72,
    "mipmap-xhdpi":   96,
    "mipmap-xxhdpi":  144,
    "mipmap-xxxhdpi": 192,
}

NAVY = (15, 23, 42)     # #0F172A
TEAL = (6, 182, 212)    # #06B6D4

SCALE = 4   # supersample factor for smooth anti-aliasing

# ── glyph geometry (identical to the first symbol in assets/logo.svg) ─────────
HOOK_CUBICS = [
    ((134.5, 61.1),  (122.3, 46.6), (102.4, 41.2), (84.6, 47.7)),
    ((84.6, 47.7),   (66.8, 54.2),  (55, 71.1),     (55, 90)),
    ((55, 90),       (55, 108.9),   (66.8, 125.8),  (84.6, 132.3)),
    ((84.6, 132.3),  (102.4, 138.8),(122.3, 133.4), (134.5, 118.9)),
]
STEM = [(134.5, 118.9), (134.5, 170)]
CROSSBAR = [(99.5, 144), (169.5, 144)]
DOT = (134.5, 198, 11)


def cubic_pts(p0, c1, c2, p3, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt**3*p0[0] + 3*mt**2*t*c1[0] + 3*mt*t**2*c2[0] + t**3*p3[0]
        y = mt**3*p0[1] + 3*mt**2*t*c1[1] + 3*mt*t**2*c2[1] + t**3*p3[1]
        pts.append((x, y))
    return pts


def build_glyph_path():
    pts = [HOOK_CUBICS[0][0]]
    for p0, c1, c2, p3 in HOOK_CUBICS:
        pts += cubic_pts(p0, c1, c2, p3)[1:]
    pts += STEM[1:]
    return pts


def rounded_rect_mask(s, radius):
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=255)
    return m


def draw_stroke_path(draw, points, width, fill):
    r = width / 2
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=fill, width=width)
    for p in points:
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


def fit_transform(all_points, target_size, padding_frac=0.16):
    xs = [p[0] for p in all_points]
    ys = [p[1] for p in all_points]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    usable = target_size * (1 - 2 * padding_frac)
    scale = usable / max(w, h)

    def tf(p):
        return ((p[0] - cx) * scale + target_size / 2,
                 (p[1] - cy) * scale + target_size / 2)
    return tf, scale


def make_icon(final_size):
    S = final_size * SCALE

    glyph_path = build_glyph_path()
    all_pts = glyph_path + CROSSBAR + [(DOT[0], DOT[1])]
    tf, scale = fit_transform(all_pts, 512)

    def F(p):
        x, y = tf(p)
        return (x / 512 * S, y / 512 * S)

    stroke_w  = round(13 * scale / 512 * S)
    bg_radius = round(108 / 512 * S)
    dot_r     = DOT[2] * scale / 512 * S

    # 1. Navy rounded-square background
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = rounded_rect_mask(round(S), bg_radius)
    navy_layer = Image.new("RGBA", (S, S), NAVY + (255,))
    img.paste(navy_layer, mask=mask)

    # 2. Glyph on its own layer (for glow + compositing)
    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glyph)
    draw_stroke_path(gd, [F(p) for p in glyph_path], stroke_w, TEAL + (255,))
    draw_stroke_path(gd, [F(p) for p in CROSSBAR], stroke_w, TEAL + (255,))
    dc = F((DOT[0], DOT[1]))
    gd.ellipse([dc[0] - dot_r, dc[1] - dot_r, dc[0] + dot_r, dc[1] + dot_r], fill=TEAL + (255,))

    # 3. Soft glow behind the glyph
    glow_alpha = glyph.split()[3]
    glow = Image.new("RGBA", (S, S), TEAL + (140,))
    glow.putalpha(glow_alpha)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=round(S * 0.018)))
    img = Image.alpha_composite(img, glow)

    # 4. Composite the crisp glyph on top
    img = Image.alpha_composite(img, glyph)

    # 5. Downsample for clean anti-aliasing
    return img.resize((final_size, final_size), Image.LANCZOS)


# ── main ───────────────────────────────────────────────────────────────────────

base = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "android", "app", "src", "main", "res")

for folder, size in SIZES.items():
    out_dir = os.path.join(base, folder)
    os.makedirs(out_dir, exist_ok=True)
    make_icon(size).save(os.path.join(out_dir, "ic_launcher.png"), "PNG")
    print(f"  {folder}/ic_launcher.png  ({size}x{size})")

print("Done.")
