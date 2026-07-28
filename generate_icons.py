"""
Farketmez launcher icon generator — derives all Android mipmap icons from the
real brand PNG at assets/logo.png (square-cropped, centered on the glyph/text,
then downsampled per density bucket).
"""
import os
from PIL import Image

SIZES = {
    "mipmap-mdpi":    48,
    "mipmap-hdpi":    72,
    "mipmap-xhdpi":   96,
    "mipmap-xxhdpi":  144,
    "mipmap-xxxhdpi": 192,
}

SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "logo.png")
RES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "android", "app", "src", "main", "res")

BRIGHTNESS_THRESHOLD = 200  # white glyph/text vs teal-navy gradient background


def _content_bbox(im):
    """Bounding box of the bright (white glyph/text) pixels, sampled on a grid."""
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    step = 4
    minx, miny, maxx, maxy = w, h, 0, 0
    for y in range(0, h, step):
        for x in range(0, w, step):
            r, g, b = px[x, y]
            if r > BRIGHTNESS_THRESHOLD and g > BRIGHTNESS_THRESHOLD and b > BRIGHTNESS_THRESHOLD:
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
    return minx, miny, maxx, maxy


def _square_crop(im):
    """Crop to a square (side = shorter edge) centered on the glyph/text content."""
    w, h = im.size
    side = min(w, h)
    if w == h:
        return im

    minx, _, maxx, _ = _content_bbox(im)
    content_cx = (minx + maxx) / 2

    left = content_cx - side / 2
    left = max(0, min(left, w - side))
    return im.crop((round(left), 0, round(left) + side, side))


def main():
    src = Image.open(SOURCE).convert("RGBA")
    square = _square_crop(src)

    for folder, size in SIZES.items():
        out_dir = os.path.join(RES_DIR, folder)
        os.makedirs(out_dir, exist_ok=True)
        icon = square.resize((size, size), Image.LANCZOS)
        icon.save(os.path.join(out_dir, "ic_launcher.png"), "PNG")
        print(f"  {folder}/ic_launcher.png  ({size}x{size})")

    print("Done.")


if __name__ == "__main__":
    main()
