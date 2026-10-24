"""Decode us-atlas TopoJSON (quantized, delta-encoded arcs) into plain polygons.

Pure Python, no dependencies. Coordinates stay in the file's projected frame
(975x610 Albers for states-albers-10m.json, y down).
"""

import json


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def decode_arcs(topo):
    """Every arc as a list of (x, y) points in the projected frame."""
    t = topo.get("transform")
    out = []
    for arc in topo["arcs"]:
        pts = []
        x = y = 0
        for p in arc:
            if t:
                x += p[0]
                y += p[1]
                pts.append((x * t["scale"][0] + t["translate"][0], y * t["scale"][1] + t["translate"][1]))
            else:
                pts.append((p[0], p[1]))
        out.append(pts)
    return out


def ring_points(arcs, ring):
    """One ring (a list of arc indices; ~i is arc i reversed) as a closed point list."""
    pts = []
    for index in ring:
        arc = arcs[index] if index >= 0 else list(reversed(arcs[~index]))
        if pts:
            arc = arc[1:]  # the shared point
        pts.extend(arc)
    return pts


def polygons(arcs, geometry):
    """A Polygon or MultiPolygon geometry as [[outer, hole, ...], ...]."""
    kind = geometry["type"]
    if kind == "Polygon":
        groups = [geometry["arcs"]]
    elif kind == "MultiPolygon":
        groups = geometry["arcs"]
    else:
        return []
    return [[ring_points(arcs, ring) for ring in group] for group in groups]


def shared_arcs(topo, name):
    """Arc indices used by two different geometries of objects[name] (inner borders)."""
    seen = {}
    for g in topo["objects"][name]["geometries"]:
        kind = g["type"]
        groups = [g["arcs"]] if kind == "Polygon" else g["arcs"] if kind == "MultiPolygon" else []
        for group in groups:
            for ring in group:
                for index in ring:
                    i = index if index >= 0 else ~index
                    seen.setdefault(i, set()).add(g.get("id"))
    return sorted(i for i, owners in seen.items() if len(owners) > 1)
