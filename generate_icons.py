"""
Farketmez launcher icon generator — lowercase "f" whose foot curls into "?"
Cropped/centered version of the "f" glyph used in assets/logo.svg's wordmark.
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


# ── helpers ────────────────────────────────────────────────────────────────────

def quad_bezier_pts(p0, p1, p2, steps=48):
    """Quadratic bezier from p0 via control p1 to p2."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * p1[1] + t ** 2 * p2[1]
        pts.append((x, y))
    return pts


def rounded_rect_mask(s, radius):
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, s - 1, s - 1], radius=radius, fill=255)
    return m


def draw_stroke_path(draw, points, width, fill):
    """Draw a polyline as stamped round segments — avoids PIL's joint
    artifacts on tight curves by circle-capping every sampled point."""
    r = width / 2
    for i in range(len(points) - 1):
        draw.line([points[i], points[i + 1]], fill=fill, width=width)
    for p in points:
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=fill)


# ── icon builder ───────────────────────────────────────────────────────────────

def make_icon(final_size):
    S = final_size * SCALE   # work at higher resolution
    f = lambda v: v / 512 * S   # scale a 512-design coordinate into S-space

    bg_radius = f(108)
    stroke_w  = round(f(35))

    stem_top  = (f(224), f(139))
    hook_start = (f(276), f(100))
    top_ctrl  = (f(227), f(86))
    stem_bot  = (f(224), f(244))
    seg1_ctrl = (f(341), f(251))
    seg1_end  = (f(320), f(314))
    seg2_ctrl = (f(292), f(363))
    seg2_end  = (f(222), f(380))
    cross     = [(f(171), f(160)), (f(267), f(160))]
    dot_c, dot_r = (f(222), f(301)), f(16)

    glyph_path = (quad_bezier_pts(hook_start, top_ctrl, stem_top) +
                  [stem_bot] +
                  quad_bezier_pts(stem_bot, seg1_ctrl, seg1_end)[1:] +
                  quad_bezier_pts(seg1_end, seg2_ctrl, seg2_end)[1:])

    # 1. Navy rounded-square background
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = rounded_rect_mask(round(S), round(bg_radius))
    navy_layer = Image.new("RGBA", (S, S), NAVY + (255,))
    img.paste(navy_layer, mask=mask)

    # 2. Build the glyph stroke on its own layer (for glow + compositing)
    glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glyph)
    draw_stroke_path(gd, glyph_path, stroke_w, TEAL + (255,))
    draw_stroke_path(gd, cross, stroke_w, TEAL + (255,))
    gd.ellipse([dot_c[0] - dot_r, dot_c[1] - dot_r, dot_c[0] + dot_r, dot_c[1] + dot_r], fill=TEAL + (255,))

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
