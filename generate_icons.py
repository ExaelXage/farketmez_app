"""
Farketmez launcher icon generator — Map Pin + Question Mark
Design matches assets/logo.svg exactly.
"""
import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SIZES = {
    "mipmap-mdpi":    48,
    "mipmap-hdpi":    72,
    "mipmap-xhdpi":   96,
    "mipmap-xxhdpi":  144,
    "mipmap-xxxhdpi": 192,
}

PURPLE   = (124,  58, 237)   # #7C3AED
TEAL     = (  6, 182, 212)   # #06B6D4
PURPLE2  = (109,  40, 217)   # #6D28D9  (inner gradient dark)
TEAL2    = (  8, 145, 178)   # #0891B2  (inner gradient light)
WHITE    = (255, 255, 255, 255)

SCALE = 4   # supersample factor for smooth anti-aliasing


# ── helpers ────────────────────────────────────────────────────────────────────

def lerp_color(c1, c2, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(len(c1)))


def diag_grad_img(w, h, c1, c2):
    """Diagonal TL→BR gradient, returns RGBA Image."""
    data = []
    d = max(w + h - 2, 1)
    for y in range(h):
        for x in range(w):
            r, g, b = lerp_color(c1, c2, (x + y) / d)
            data.append((r, g, b, 255))
    img = Image.new("RGBA", (w, h))
    img.putdata(data)
    return img


def rounded_rect_mask(s, radius):
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, s-1, s-1], radius=radius, fill=255)
    return m


def bezier_pts(p0, p1, p2, steps=64):
    """Quadratic bezier from p0 via p1 to p2, returns list of (x,y)."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1-t)**2 * p0[0] + 2*t*(1-t)*p1[0] + t**2 * p2[0]
        y = (1-t)**2 * p0[1] + 2*t*(1-t)*p1[1] + t**2 * p2[1]
        pts.append((x, y))
    return pts


# ── icon builder ───────────────────────────────────────────────────────────────

def make_icon(final_size):
    S = final_size * SCALE   # work at higher resolution

    # All geometry proportional to S (derived from 512×512 SVG design)
    cx         = S // 2
    circle_cy  = round(S * 0.3906)   # 200/512
    circle_r   = round(S * 0.2500)   # 128/512
    tail_y0    = round(S * 0.5078)   # 260/512 — tail shoulder y
    tail_xl    = round(S * 0.2734)   # 140/512 — left shoulder x
    tail_xr    = round(S * 0.7266)   # 372/512 — right shoulder x
    ctrl_xl    = round(S * 0.3750)   # 192/512 — left bezier control x
    ctrl_xr    = round(S * 0.6250)   # 320/512 — right bezier control x
    ctrl_y     = round(S * 0.8496)   # 435/512 — bezier control y
    tip_y      = round(S * 0.8789)   # 450/512 — pin tip
    inner_r    = round(S * 0.1563)   # 80/512
    bg_radius  = round(S * 0.2109)   # 108/512
    font_size  = round(S * 0.2305)   # 118/512

    # 1. Gradient background
    grad = diag_grad_img(S, S, PURPLE, TEAL)
    mask = rounded_rect_mask(S, bg_radius)
    img  = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.paste(grad, mask=mask)

    # 2. Build pin shape (circle head + teardrop tail) on a separate layer
    pin_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pin_layer)

    # 2a. Circle head
    pd.ellipse([cx - circle_r, circle_cy - circle_r,
                cx + circle_r, circle_cy + circle_r], fill=WHITE)

    # 2b. Teardrop tail: bezier polygon (left side down → right side up)
    left_side  = bezier_pts((tail_xl, tail_y0), (ctrl_xl, ctrl_y), (cx, tip_y), steps=80)
    right_side = bezier_pts((cx, tip_y), (ctrl_xr, ctrl_y), (tail_xr, tail_y0), steps=80)
    pd.polygon(left_side + right_side, fill=WHITE)

    # 3. Drop shadow: recolor pin dark, shift down, blur
    pin_alpha   = pin_layer.split()[3]
    shadow_dark = Image.new("RGBA", (S, S), (0, 0, 0, 75))
    shadow_dark.putalpha(pin_alpha)
    shadow_off  = round(S * 0.020)
    shadow_img  = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_img.paste(shadow_dark, (0, shadow_off), mask=shadow_dark.split()[3])
    shadow_img  = shadow_img.filter(ImageFilter.GaussianBlur(radius=round(S * 0.038)))
    img = Image.alpha_composite(img, shadow_img)

    # 4. Composite white pin
    img = Image.alpha_composite(img, pin_layer)

    # 5. Inner gradient circle (depth effect)
    inner_grad = diag_grad_img(S, S, PURPLE2, TEAL2)
    inner_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(inner_mask).ellipse([
        cx - inner_r, circle_cy - inner_r,
        cx + inner_r, circle_cy + inner_r,
    ], fill=255)
    inner_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    inner_layer.paste(inner_grad, mask=inner_mask)
    img = Image.alpha_composite(img, inner_layer)

    # 6. White "?" centered in inner circle
    font = None
    for path in [
        "C:/Windows/Fonts/ariblk.ttf",   # Arial Black — bold, matches SVG
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]:
        if os.path.exists(path):
            try:
                font = ImageFont.truetype(path, font_size)
                break
            except Exception:
                pass
    if font is None:
        font = ImageFont.load_default()

    q_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    q_draw  = ImageDraw.Draw(q_layer)
    bb = q_draw.textbbox((0, 0), "?", font=font)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    tx = cx         - tw // 2 - bb[0]
    ty = circle_cy  - th // 2 - bb[1]
    q_draw.text((tx, ty), "?", font=font, fill=WHITE)
    img = Image.alpha_composite(img, q_layer)

    # 7. Downsample for clean anti-aliasing
    return img.resize((final_size, final_size), Image.LANCZOS)


# ── main ───────────────────────────────────────────────────────────────────────

base = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "android", "app", "src", "main", "res")

for folder, size in SIZES.items():
    out_dir = os.path.join(base, folder)
    os.makedirs(out_dir, exist_ok=True)
    make_icon(size).save(os.path.join(out_dir, "ic_launcher.png"), "PNG")
    print(f"  {folder}/ic_launcher.png  ({size}×{size})")

print("Done.")
