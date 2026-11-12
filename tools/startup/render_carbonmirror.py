#!/usr/bin/env python3
# SPDX-License-Identifier: PolyForm-Shield-1.0.0
# Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
"""
CarbonMirror startup animation renderer (no rounded icon, OLED black background).

Usage:
  python3 render_carbonmirror.py <input.svg> <output_dir> [slide|pixel|both] [fps]

Defaults: mode=both, fps=120. Output: 1024x1024 H.264 MP4, 3.0 s.
Requires: Python 3, Pillow, numpy, ffmpeg on PATH.
  pip3 install pillow numpy
"""
import multiprocessing
import os
import random
import re
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

W = H = 1024
S = 2                 # supersampling factor (anti-aliasing)
DURATION = 3.0        # seconds
BG_COLOR = (0, 0, 0)  # OLED black


# ---------- geometry from the SVG ----------
def pts(d):
    return [(float(x), float(y)) for x, y in re.findall(r'(-?[\d.]+),(-?[\d.]+)', d)]


def fill_of(attrs):
    m = re.search(r'fill="(#[0-9A-Fa-f]{6})"', attrs)
    if not m:
        raise SystemExit("Tile without a solid fill colour in the SVG")
    return m.group(1)


def bbox(p):
    xs = [a for a, _ in p]
    ys = [b for _, b in p]
    return min(xs), min(ys), max(xs), max(ys)


def hex2rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def load_geometry(svg_path):
    txt = open(svg_path, encoding="utf-8").read()
    found = re.findall(r'<path d="([^"]+)"([^>]*?)/>', txt)
    if len(found) != 23:
        raise SystemExit(f"Unexpected SVG structure: {len(found)} paths, expected 23")
    tiles = [(pts(d), fill_of(a)) for d, a in found[6:22]]
    return {
        "card": pts(found[4][0]),      # yellow back card
        "glass": pts(found[5][0]),     # translucent front phone
        "outline": pts(found[22][0]),  # white phone outline
        "tiles": tiles,                # 16 app tiles (shape, colour)
        "tile_final": [bbox(p)[:2] for p, _ in tiles],
    }


# ---------- layer helpers (supersampled) ----------
def layer_blank():
    return Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))


def poly_mask(points, dx, dy):
    m = Image.new("L", (W * S, H * S), 0)
    ImageDraw.Draw(m).polygon([((x + dx) * S, (y + dy) * S) for x, y in points], fill=255)
    return m


def scale_alpha(img, k):
    if k >= 1:
        return img
    img.putalpha(img.getchannel("A").point(lambda v: int(v * k)))
    return img


def solid(points, dx, dy, color, alpha):
    L = layer_blank()
    ImageDraw.Draw(L).polygon(
        [((x + dx) * S, (y + dy) * S) for x, y in points],
        fill=hex2rgb(color) + (int(round(255 * alpha)),))
    return L


def grad(points, dx, dy, c1, c2, a1, a2, diag):
    x0, y0, x1, y1 = bbox(points)
    w, h = x1 - x0, y1 - y0
    X = (np.arange(W * S) / S - (x0 + dx)) / w
    Y = (np.arange(H * S) / S - (y0 + dy)) / h
    if diag:
        t = (X[None, :] + Y[:, None]) / 2
    else:
        t = np.broadcast_to(Y[:, None], (H * S, W * S))
    t = np.clip(t, 0, 1)
    c1 = np.array(hex2rgb(c1), np.float32)
    c2 = np.array(hex2rgb(c2), np.float32)
    rgb = c1 + (c2 - c1) * t[..., None]
    a = (a1 + (a2 - a1) * t) * 255
    arr = np.concatenate([rgb, a[..., None]], axis=2).astype(np.uint8)
    L = Image.fromarray(arr, "RGBA")
    L.putalpha(ImageChops.multiply(L.getchannel("A"), poly_mask(points, dx, dy)))
    return L


def shadow(points, dx, dy, blur, alpha):
    m = poly_mask(points, dx, dy).filter(ImageFilter.GaussianBlur(blur * S))
    m = m.point(lambda v: int(v * alpha))
    L = layer_blank()
    L.putalpha(m)
    return L


def stroke(points, dx, dy, width, color, alpha):
    L = layer_blank()
    p = [((x + dx) * S, (y + dy) * S) for x, y in points]
    ImageDraw.Draw(L).line(p + [p[0]], fill=hex2rgb(color) + (int(round(255 * alpha)),),
                           width=int(round(width * S)), joint="curve")
    return L


def over(base, layer):
    return Image.alpha_composite(base, layer)


# ---------- easing ----------
def prog(t, start, dur):
    return min(1.0, max(0.0, (t - start) / dur))


def ease_out_cubic(p):
    return 1 - (1 - p) ** 3


def ease_back(p, c):
    return 1 + (c + 1) * (p - 1) ** 3 + c * (p - 1) ** 2


# ---------- motion 1: slide and settle ----------
def pose_slide(geo):
    n = len(geo["tiles"])

    def pose(t):
        cdy = (1 - ease_back(prog(t, 0.00, 0.90), 0.6)) * 860    # card rises from below
        pdy = (1 - ease_back(prog(t, 0.15, 0.95), 0.6)) * -900   # phone drops from top
        tiles = []
        for k in range(n):
            p = prog(t, 0.75 + k * 0.045, 0.80)                  # row-major cascade
            dx = (1 - ease_back(p, 0.8)) * 420                   # fly in from right of phone
            tiles.append((dx, pdy, min(1.0, p * 4)))
        return 0, cdy, 1.0, 0, pdy, 1.0, tiles

    return pose


# ---------- motion 2: pixel assemble ----------
def pose_pixel(geo, seed=7):
    rng = random.Random(seed)
    starts = []
    for fx, fy in geo["tile_final"]:
        sx = rng.uniform(60, 900)
        sy = rng.uniform(60, 900)
        delay = rng.uniform(0.10, 0.80)
        starts.append((fx, fy, sx, sy, delay))

    def pose(t):
        tiles = []
        for fx, fy, sx, sy, delay in starts:
            p = prog(t, delay, 1.10)
            e = ease_out_cubic(p)
            tiles.append(((sx - fx) * (1 - e), (sy - fy) * (1 - e), min(1.0, p * 3)))
        op = prog(t, 0.0, 0.30)
        return 0, 0, op, 0, 0, op, tiles

    return pose


# ---------- rendering ----------
def render(t, pose, geo):
    base = Image.new("RGBA", (W * S, H * S), BG_COLOR + (255,))
    cdx, cdy, cop, pdx, pdy, pop, tiles = pose(t)

    base = over(base, scale_alpha(grad(geo["card"], cdx, cdy, "#FFE14D", "#F5B800", 1, 1, True), cop))
    base = over(base, scale_alpha(shadow(geo["glass"], pdx - 4, pdy + 8, 10, 0.5), pop))
    base = over(base, scale_alpha(grad(geo["glass"], pdx, pdy, "#FFFFFF", "#FFFFFF", 0.62, 0.38, True), pop))
    for (tp, col), (tdx, tdy, top) in zip(geo["tiles"], tiles):
        if top > 0:
            base = over(base, solid(tp, tdx, tdy, col, top))
    base = over(base, scale_alpha(stroke(geo["outline"], pdx, pdy, 5, "#FFFFFF", 0.95), pop))

    return base.convert("RGB").resize((W, H), Image.LANCZOS)


_job = None  # (pose, geo, fps), inherited by forked workers


def _frame(f):
    pose, geo, fps = _job
    return np.asarray(render(f / fps, pose, geo)).tobytes()


def write(path, pose, geo, fps):
    global _job
    _job = (pose, geo, fps)
    n = round(DURATION * fps)
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(fps), "-i", "-",
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-preset", "slow",
           "-movflags", "+faststart", "-r", str(fps), path]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    with multiprocessing.get_context("fork").Pool() as pool:  # one worker per core, frames in order
        for frame in pool.imap(_frame, range(n), chunksize=2):
            proc.stdin.write(frame)
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit("ffmpeg failed")
    print(f"wrote {path} ({n} frames at {fps} fps)")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        raise SystemExit(1)
    svg, outdir = sys.argv[1], sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "both"
    fps = int(sys.argv[4]) if len(sys.argv) > 4 else 120
    if mode not in ("slide", "pixel", "both"):
        raise SystemExit("mode must be slide, pixel or both")
    if shutil.which("ffmpeg") is None:
        raise SystemExit("ffmpeg not found on PATH")

    os.makedirs(outdir, exist_ok=True)
    geo = load_geometry(svg)

    jobs = []
    if mode in ("slide", "both"):
        jobs.append(("carbonmirror_slide_settle", pose_slide(geo)))
    if mode in ("pixel", "both"):
        jobs.append(("carbonmirror_pixel_assemble", pose_pixel(geo)))

    for name, pose in jobs:
        write(os.path.join(outdir, f"{name}_{fps}fps.mp4"), pose, geo, fps)


if __name__ == "__main__":
    main()
