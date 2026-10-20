#!/usr/bin/env python3
"""Measurement helpers for the aidrun-visual-verdict skill.

The verdict itself comes from looking at the images. This script only
supplies numbers that a person cannot read off a picture reliably:
where the two images differ, the WCAG contrast of two pixel colours,
and a magnified crop for close inspection.

Usage:
  vv.py pair REF IMPL OUTDIR        side-by-side + diff heatmap + hotspots
  vv.py contrast IMG X Y W H        contrast of the text or icon inside a box on its fill
  vv.py crop IMG X Y W H OUT        3x magnified crop
  vv.py selftest                    check the maths above

Coordinates are in IMPL pixels. In a crop output, divide by 3 and add
the crop origin to get back to IMPL pixels. Divide by the screen scale to get pt
(iPhone screenshot width in px / screen width in pt, e.g. 1206/402 = 3).
"""
import os
import sys
import tempfile
from collections import Counter

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# A channel difference below this is JPEG noise or anti-aliasing, not a change.
PIXEL_DIFF_THRESHOLD = 32
# Hotspot grid. 12 x 24 cells keep one cell near one row of an iPhone list.
GRID_COLS, GRID_ROWS = 12, 24
# Report a cell when this share of its pixels changed.
HOTSPOT_MIN_SHARE = 0.02
# Aspect ratios that differ more than this mean the two images are not the same screen class.
ASPECT_TOLERANCE = 0.03
# Contrast: a pixel is stroke core when its luminance distance from the
# background is at least this share of the largest distance in the box.
FG_CORE_SHARE = 0.9
# Fewer stroke-core pixels than this means the box probably holds no text.
MIN_CORE_PIXELS = 4


def load(path):
    return Image.open(path).convert("RGB")


def align(ref, impl):
    """Scale REF to IMPL width, then pad or cut it to IMPL height."""
    w, h = impl.size
    scaled = ref.resize((w, round(ref.height * w / ref.width)), Image.LANCZOS)
    canvas = Image.new("RGB", (w, h), (255, 0, 255))
    canvas.paste(scaled.crop((0, 0, w, min(h, scaled.height))), (0, 0))
    return canvas


def diff_mask(a, b, upscale=1.0):
    """Changed pixels, without the thin edge lines that resampling leaves.

    A reference saved at half size and scaled back up has soft edges.
    Blur both sides by the scale factor, then erode the mask once,
    so only areas wider than an edge count as changed.
    """
    radius = max(1.0, upscale)
    d = ImageChops.difference(a.filter(ImageFilter.GaussianBlur(radius)),
                              b.filter(ImageFilter.GaussianBlur(radius))).convert("L")
    mask = d.point(lambda v: 255 if v > PIXEL_DIFF_THRESHOLD else 0)
    return mask.filter(ImageFilter.MinFilter(3))


def hotspots(mask):
    w, h = mask.size
    cw, ch = w / GRID_COLS, h / GRID_ROWS
    out = []
    for r in range(GRID_ROWS):
        for c in range(GRID_COLS):
            box = (round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch))
            cell = mask.crop(box)
            share = sum(cell.histogram()[255:]) / (cell.width * cell.height)
            if share >= HOTSPOT_MIN_SHARE:
                out.append((share, box))
    return merge_boxes([b for _, b in out])


def merge_boxes(boxes):
    """Join touching cells so one changed element is one hotspot."""
    merged = []
    for b in boxes:
        for i, m in enumerate(merged):
            if b[0] <= m[2] and b[2] >= m[0] and b[1] <= m[3] and b[3] >= m[1]:
                merged[i] = (min(b[0], m[0]), min(b[1], m[1]), max(b[2], m[2]), max(b[3], m[3]))
                break
        else:
            merged.append(b)
    if len(merged) == len(boxes):
        return merged
    return merge_boxes(merged)


def pair(ref_path, impl_path, outdir):
    ref, impl = load(ref_path), load(impl_path)
    os.makedirs(outdir, exist_ok=True)
    ref_aspect, impl_aspect = ref.height / ref.width, impl.height / impl.width
    aligned = align(ref, impl)
    mask = diff_mask(aligned, impl, impl.width / ref.width)
    changed = sum(mask.histogram()[255:]) / (mask.width * mask.height)
    spots = hotspots(mask)

    heat = impl.copy().convert("L").convert("RGB")
    red = Image.new("RGB", impl.size, (255, 0, 0))
    heat.paste(red, (0, 0), mask.filter(ImageFilter.MaxFilter(5)))
    draw = ImageDraw.Draw(heat)
    for i, b in enumerate(spots, 1):
        draw.rectangle(b, outline=(0, 160, 255), width=4)
        draw.text((b[0] + 6, b[1] + 4), str(i), fill=(0, 160, 255))

    w, h = impl.size
    sbs = Image.new("RGB", (w * 3 + 40, h), (128, 128, 128))
    for i, img in enumerate((aligned, impl, heat)):
        sbs.paste(img, (i * (w + 20), 0))
    sbs_path = os.path.join(outdir, "side-by-side.png")
    sbs.save(sbs_path)

    print(f"ref  {ref.width}x{ref.height}  aspect {ref_aspect:.3f}")
    print(f"impl {impl.width}x{impl.height}  aspect {impl_aspect:.3f}")
    if abs(ref_aspect - impl_aspect) / impl_aspect > ASPECT_TOLERANCE:
        print("WARN aspect differs: not the same screen class; pixel diff is only a rough guide")
    print(f"changed pixels {changed:.2%}")
    print(f"hotspots {len(spots)} (impl px, left top right bottom):")
    for i, b in enumerate(spots, 1):
        print(f"  #{i} {b}")
    print(f"wrote {sbs_path}  (left = reference, middle = implementation, right = diff)")
    return changed, spots


def luminance(rgb):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(fg, bg):
    hi, lo = sorted((luminance(fg), luminance(bg)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def region_colours(img, x, y, w, h):
    """Background and foreground colour of a box that holds text or an icon on a plain fill.

    Background = the most common colour. Foreground = median of the pixels
    furthest from it in luminance. Anti-aliased edge pixels sit between the
    two, so they never decide either colour. A point sample does not work:
    on a half-size screenshot a stroke is 2 px wide and any 3x3 patch is
    mostly background (2026-10-20 trial gave 2.27:1 for a true 6.27:1).
    """
    pixels = list(img.crop((x, y, x + w, y + h)).getdata())
    bg = Counter(pixels).most_common(1)[0][0]
    bg_lum = luminance(bg)
    dist = [abs(luminance(p) - bg_lum) for p in pixels]
    far = max(dist)
    if far == 0:
        return bg, bg, 0
    core = [p for p, d in zip(pixels, dist) if d >= FG_CORE_SHARE * far]
    fg = tuple(sorted(c[i] for c in core)[len(core) // 2] for i in range(3))
    return fg, bg, len(core)


def contrast(img_path, x, y, w, h):
    fg, bg, n = region_colours(load(img_path), x, y, w, h)
    r = ratio(fg, bg)
    if n < MIN_CORE_PIXELS:
        print(f"WARN only {n} foreground pixels: box may hold no text; widen it or pick another box")
    print(f"fg #{fg[0]:02X}{fg[1]:02X}{fg[2]:02X}  bg #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}  ratio {r:.2f}:1")
    print(f"  text >=4.5 {'ok' if r >= 4.5 else 'FAIL'} | large text / icon / control edge >=3 {'ok' if r >= 3 else 'FAIL'}")
    return r


def crop(img_path, x, y, w, h, out):
    img = load(img_path).crop((x, y, x + w, y + h))
    img.resize((w * 3, h * 3), Image.NEAREST).save(out)
    print(f"wrote {out}")


def selftest():
    failures = []
    checks = [0]

    def check(name, ok):
        checks[0] += 1
        print(f"{'ok  ' if ok else 'FAIL'} {name}")
        if not ok:
            failures.append(name)

    check("black on white is 21:1", round(ratio((0, 0, 0), (255, 255, 255)), 2) == 21.0)
    # #767676 is the lightest grey that passes 4.5:1 on white; #777777 fails.
    check("#767676 on white passes 4.5", ratio((0x76,) * 3, (255,) * 3) >= 4.5)
    check("#777777 on white fails 4.5", ratio((0x77,) * 3, (255,) * 3) < 4.5)

    with tempfile.TemporaryDirectory() as tmp:
        # Thin anti-aliased strokes, like text on a half-size screenshot:
        # draw 6 px strokes at 4x, off the pixel grid, then shrink to 1.5 px.
        big = Image.new("RGB", (160, 80), (0, 88, 199))
        d = ImageDraw.Draw(big)
        for x0 in range(10, 150, 22):
            d.rectangle((x0, 10, x0 + 5, 70), fill=(255, 255, 255))
        thin = os.path.join(tmp, "thin.png")
        big.resize((40, 20), Image.BOX).save(thin)
        expected = ratio((255, 255, 255), (0, 88, 199))
        got = contrast(thin, 0, 0, 40, 20)
        check(f"thin strokes measure the true ratio ({expected:.2f})", abs(got - expected) < 0.15)

    with tempfile.TemporaryDirectory() as tmp:
        base = Image.new("RGB", (402, 874), (255, 255, 255))
        ImageDraw.Draw(base).rectangle((20, 700, 382, 764), fill=(0, 90, 200))
        a, b = os.path.join(tmp, "a.png"), os.path.join(tmp, "b.png")
        base.save(a)
        changed_img = base.copy()
        ImageDraw.Draw(changed_img).rectangle((20, 100, 120, 140), fill=(0, 0, 0))
        changed_img.save(b)

        same, same_spots = pair(a, a, os.path.join(tmp, "same"))
        check("identical pair has 0 changed pixels and no hotspot", same == 0 and not same_spots)

        _, spots = pair(a, b, os.path.join(tmp, "diff"))
        hit = len(spots) == 1 and spots[0][0] <= 20 and spots[0][1] <= 100 and spots[0][2] >= 120 and spots[0][3] >= 140
        check("one painted box gives exactly one hotspot that covers it", hit)

        # Same screen at half resolution must still align with no hotspot.
        half = os.path.join(tmp, "half.png")
        base.resize((201, 437), Image.LANCZOS).save(half)
        _, half_spots = pair(half, a, os.path.join(tmp, "half"))
        check("downscaled copy of the same screen gives no hotspot", not half_spots)

    print(f"selftest {'FAILED' if failures else 'passed'}: {checks[0] - len(failures)}/{checks[0]} ok")
    return 1 if failures else 0


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, args = argv[1], argv[2:]
    if cmd == "pair" and len(args) == 3:
        pair(*args)
        return 0
    if cmd == "contrast" and len(args) == 5:
        contrast(args[0], *map(int, args[1:5]))
        return 0
    if cmd == "crop" and len(args) == 6:
        crop(args[0], *map(int, args[1:5]), args[5])
        return 0
    if cmd == "selftest":
        return selftest()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
