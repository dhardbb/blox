"""Shared hand-drawn marker strokes for the whiteboard art (docs/proposals/whiteboard.md).

Imported by assets/ui/make.py, assets/icons/make.py and assets/promo/make.py.
Pure Pillow; every wobble comes from a seeded random.Random, so the same seed
always draws the same stroke.

  resample(points, step)             evenly spaced points along a polyline
  wobble(points, rng, amp, wave)     a smooth sideways wobble (a hand, not noise)
  extend(points, start, end)         run the ends on past the shape (overshoot)
  stroke(draw, points, width, fill)  a round-capped line through the points
  loop(cx, cy, rx, ry, rng, turns)   a loose hand-drawn ellipse (ends overlap)
"""

from __future__ import annotations

import math
import random

Point = tuple[float, float]


def resample(points: list[Point], step: float) -> list[Point]:
    if len(points) < 2:
        return list(points)
    out = [points[0]]
    walked = 0.0  # arc length at the start of the current segment
    target = step  # arc length of the next sample
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        seg = math.hypot(bx - ax, by - ay)
        while seg > 0 and target <= walked + seg:
            t = (target - walked) / seg
            out.append((ax + (bx - ax) * t, ay + (by - ay) * t))
            target += step
        walked += seg
    if math.hypot(out[-1][0] - points[-1][0], out[-1][1] - points[-1][1]) > 1e-6:
        out.append(points[-1])
    return out


def _noise(rng: random.Random, waves: int = 3):
    """A smooth 1D function of arc length: a few sines with seeded phases."""
    parts = [(rng.uniform(0.6, 1.6) * (k + 1), rng.uniform(0, math.tau), 1 / (k + 1)) for k in range(waves)]
    total = sum(w for _, _, w in parts)

    def f(s: float) -> float:
        return sum(w * math.sin(freq * s + phase) for freq, phase, w in parts) / total

    return f


def wobble(points: list[Point], rng: random.Random, amp: float, wave: float) -> list[Point]:
    """Moves each point sideways by a smooth seeded wobble of about `amp`, with
    bumps about `wave` apart (both in the drawing's own units)."""
    pts = resample(points, max(wave / 12, 0.5))
    if len(pts) < 3:
        return pts
    f = _noise(rng)
    out = []
    s = 0.0
    for i, (x, y) in enumerate(pts):
        if i > 0:
            s += math.hypot(x - pts[i - 1][0], y - pts[i - 1][1])
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1.0
        off = amp * f(s / wave * math.tau / 2)
        out.append((x - dy / n * off, y + dx / n * off))
    return out


def extend(points: list[Point], start: float, end: float) -> list[Point]:
    """Runs the line on past both ends along its own direction (a marker's
    overshoot at a corner)."""
    if len(points) < 2:
        return points
    (ax, ay), (bx, by) = points[0], points[1]
    n = math.hypot(bx - ax, by - ay) or 1.0
    head = (ax - (bx - ax) / n * start, ay - (by - ay) / n * start)
    (cx, cy), (dx, dy) = points[-2], points[-1]
    n = math.hypot(dx - cx, dy - cy) or 1.0
    tail = (dx + (dx - cx) / n * end, dy + (dy - cy) / n * end)
    return [head, *points, tail]


def stroke(draw, points: list[Point], width: float, fill, taper: float = 0.0) -> None:
    """A round-capped line. `taper` (0..1) thins the last and first few percent
    of the stroke, like a marker lifting off the board."""
    if not points:
        return
    if len(points) == 1:
        x, y = points[0]
        r = width / 2
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)
        return
    count = len(points)
    for i, ((ax, ay), (bx, by)) in enumerate(zip(points, points[1:])):
        w = width
        if taper > 0:
            u = i / max(count - 2, 1)
            edge = min(u, 1 - u) / 0.12
            if edge < 1:
                w = width * (1 - taper + taper * edge)
        draw.line((ax, ay, bx, by), fill=fill, width=max(1, round(w)))
        r = w / 2
        draw.ellipse((bx - r, by - r, bx + r, by + r), fill=fill)
    x, y = points[0]
    r = (width * (1 - taper) if taper else width) / 2
    draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def loop(cx: float, cy: float, rx: float, ry: float, rng: random.Random, turns: float = 1.12, tilt: float = 0.0) -> list[Point]:
    """A loose hand-drawn ellipse: a bit more than one turn, the radius drifting
    so the ends pass each other instead of closing."""
    start = rng.uniform(0, math.tau)
    drift = rng.uniform(0.04, 0.07)
    f = _noise(rng)
    n = max(48, int(turns * 120))
    out = []
    cos_t, sin_t = math.cos(tilt), math.sin(tilt)
    for i in range(n + 1):
        u = i / n
        a = start + u * turns * math.tau
        k = 1 + drift * (u - 0.5) * 2 + 0.03 * f(a * 1.5)
        x, y = math.cos(a) * rx * k, math.sin(a) * ry * k
        out.append((cx + x * cos_t - y * sin_t, cy + x * sin_t + y * cos_t))
    return out
