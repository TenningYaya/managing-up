from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
from collections import defaultdict, deque
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont


@dataclass
class Component:
    component_id: int
    pixel_bounds: tuple[int, int, int, int]
    pixel_count: int
    alpha_range: tuple[int, int]
    centroid: tuple[float, float]
    touched_tile_cells: list[tuple[int, int]]
    mean_alpha: float
    mean_luma: float


@dataclass
class Candidate:
    candidate_id: str
    source_texture_path: str
    source_region: tuple[int, int, int, int]
    tight_visual_bounds: tuple[int, int, int, int]
    pixel_size: tuple[int, int]
    tile_span: tuple[int, int]
    connected_component_ids: list[int]
    detected_shadow_components: list[int]
    confidence_score: float
    needs_manual_review: bool
    suggested_category: str
    suggested_group_id: str
    suggested_orientation: str
    suggested_item_id: str
    suggested_ground_footprint: tuple[int, int]
    touched_tile_cells: list[tuple[int, int]]
    includes_shadow: bool
    review_state: str = "pending"


class UnionFind:
    def __init__(self, items: Iterable[int]) -> None:
        self.parent = {i: i for i in items}

    def find(self, x: int) -> int:
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a: int, b: int) -> None:
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def classify_png(path: Path, image: Image.Image) -> dict:
    name = path.name.lower()
    size = image.size
    if "16x16" in name:
        version = "16x16"
        base = (16, 16)
    elif "32x32" in name:
        version = "32x32"
        base = (32, 32)
    elif "48x48" in name:
        version = "48x48"
        base = (48, 48)
    else:
        version = "unknown"
        base = (32, 32)
    return {
        "path": str(path),
        "size": size,
        "has_alpha": "A" in image.getbands(),
        "version": version,
        "base_tile_size": base,
        "shadow_style": "shadowless" if "no shadow" in name or "no shadows" in name else "shadow",
        "is_complete_atlas": size[0] >= base[0] * 8 or size[1] >= base[1] * 8,
        "is_single_object_png": size[0] <= base[0] * 4 and size[1] <= base[1] * 4 and "all" not in name,
    }


def make_mask(image: Image.Image, alpha_threshold: int) -> tuple[list[bytearray], list[list[int]]]:
    rgba = image.convert("RGBA")
    w, h = rgba.size
    alpha = [[0] * w for _ in range(h)]
    mask = [bytearray(w) for _ in range(h)]
    data = rgba.load()
    for y in range(h):
        for x in range(w):
            a = data[x, y][3]
            alpha[y][x] = a
            if a > alpha_threshold:
                mask[y][x] = 1
    return mask, alpha


def connected_components(image: Image.Image, mask: list[bytearray], alpha: list[list[int]], base_tile: tuple[int, int]) -> tuple[list[Component], list[list[int]]]:
    rgba = image.convert("RGBA")
    pix = rgba.load()
    w, h = rgba.size
    seen = [bytearray(w) for _ in range(h)]
    labels = [[0] * w for _ in range(h)]
    comps: list[Component] = []
    cid = 1
    dirs = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
    for sy in range(h):
        for sx in range(w):
            if not mask[sy][sx] or seen[sy][sx]:
                continue
            q = deque([(sx, sy)])
            seen[sy][sx] = 1
            xs: list[int] = []
            ys: list[int] = []
            alphas: list[int] = []
            lumas: list[float] = []
            while q:
                x, y = q.popleft()
                labels[y][x] = cid
                xs.append(x)
                ys.append(y)
                r, g, b, a = pix[x, y]
                alphas.append(a)
                lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
                for dx, dy in dirs:
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and mask[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = 1
                        q.append((nx, ny))
            x0, y0, x1, y1 = min(xs), min(ys), max(xs) + 1, max(ys) + 1
            touched = sorted({(x // base_tile[0], y // base_tile[1]) for x, y in zip(xs, ys)})
            comps.append(Component(
                component_id=cid,
                pixel_bounds=(x0, y0, x1 - x0, y1 - y0),
                pixel_count=len(xs),
                alpha_range=(min(alphas), max(alphas)),
                centroid=(sum(xs) / len(xs), sum(ys) / len(ys)),
                touched_tile_cells=touched,
                mean_alpha=sum(alphas) / len(alphas),
                mean_luma=sum(lumas) / len(lumas),
            ))
            cid += 1
    return comps, labels


def rect_distance(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    dx = max(bx - (ax + aw), ax - (bx + bw), 0)
    dy = max(by - (ay + ah), ay - (by + bh), 0)
    return math.hypot(dx, dy)


def rect_union(rects: Iterable[tuple[int, int, int, int]]) -> tuple[int, int, int, int]:
    rects = list(rects)
    x0 = min(r[0] for r in rects)
    y0 = min(r[1] for r in rects)
    x1 = max(r[0] + r[2] for r in rects)
    y1 = max(r[1] + r[3] for r in rects)
    return (x0, y0, x1 - x0, y1 - y0)


def expand_rect(rect: tuple[int, int, int, int], pad: int, image_size: tuple[int, int]) -> tuple[int, int, int, int]:
    x, y, w, h = rect
    x0 = max(0, x - pad)
    y0 = max(0, y - pad)
    x1 = min(image_size[0], x + w + pad)
    y1 = min(image_size[1], y + h + pad)
    return (x0, y0, x1 - x0, y1 - y0)


def tile_stats(mask: list[bytearray], alpha: list[list[int]], base_tile: tuple[int, int], minimum_pixels: int) -> tuple[dict, list[set[tuple[int, int]]]]:
    h = len(mask)
    w = len(mask[0]) if h else 0
    cols = math.ceil(w / base_tile[0])
    rows = math.ceil(h / base_tile[1])
    stats = {}
    occupied: set[tuple[int, int]] = set()
    for ty in range(rows):
        for tx in range(cols):
            x0, y0 = tx * base_tile[0], ty * base_tile[1]
            x1, y1 = min(w, x0 + base_tile[0]), min(h, y0 + base_tile[1])
            xs: list[int] = []
            ys: list[int] = []
            alphas: list[int] = []
            for y in range(y0, y1):
                for x in range(x0, x1):
                    if mask[y][x]:
                        xs.append(x)
                        ys.append(y)
                        alphas.append(alpha[y][x])
            count = len(xs)
            if count:
                bounds = (min(xs), min(ys), max(xs) + 1 - min(xs), max(ys) + 1 - min(ys))
            else:
                bounds = (0, 0, 0, 0)
            ratio = count / max(1, (x1 - x0) * (y1 - y0))
            only_shadow = bool(count and max(alphas) < 96)
            stats[(tx, ty)] = {
                "visible_pixels": count,
                "visible_ratio": ratio,
                "visible_bounds": bounds,
                "only_shadow": only_shadow,
            }
            if count >= minimum_pixels:
                occupied.add((tx, ty))
    groups = []
    remaining = set(occupied)
    dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
    while remaining:
        start = remaining.pop()
        group = {start}
        q = deque([start])
        while q:
            x, y = q.popleft()
            for dx, dy in dirs:
                n = (x + dx, y + dy)
                if n in remaining:
                    remaining.remove(n)
                    group.add(n)
                    q.append(n)
        groups.append(group)
    return stats, groups


def looks_like_shadow(comp: Component, subject: Component) -> bool:
    cx, cy = comp.centroid
    sx, sy = subject.centroid
    cb = comp.pixel_bounds
    sb = subject.pixel_bounds
    below = cy >= sy or cb[1] >= sb[1] + sb[3] * 0.4
    close_x = not (cb[0] + cb[2] < sb[0] - 8 or cb[0] > sb[0] + sb[2] + 8)
    dim = comp.mean_alpha < subject.mean_alpha * 0.85 or comp.mean_luma < subject.mean_luma * 0.75
    return below and close_x and dim


def projection_overlap_ratio(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x_overlap = max(0, min(ax + aw, bx + bw) - max(ax, bx))
    y_overlap = max(0, min(ay + ah, by + bh) - max(ay, by))
    rx = x_overlap / max(1, min(aw, bw))
    ry = y_overlap / max(1, min(ah, bh))
    return max(rx, ry)


def tile_span_for_rect(rect: tuple[int, int, int, int], base_tile: tuple[int, int]) -> tuple[int, int]:
    x, y, w, h = rect
    tx0, ty0 = x // base_tile[0], y // base_tile[1]
    tx1 = math.ceil((x + w) / base_tile[0])
    ty1 = math.ceil((y + h) / base_tile[1])
    return (tx1 - tx0, ty1 - ty0)


def can_auto_merge_pair(
    a: Component,
    b: Component,
    distance_px: int,
    base_tile: tuple[int, int],
    maximum_auto_region_size_tiles: tuple[int, int],
) -> bool:
    if rect_distance(a.pixel_bounds, b.pixel_bounds) > distance_px:
        return False
    combined = rect_union([a.pixel_bounds, b.pixel_bounds])
    span = tile_span_for_rect(combined, base_tile)
    if span[0] > maximum_auto_region_size_tiles[0] or span[1] > maximum_auto_region_size_tiles[1]:
        return False
    # Keep ordinary gap bridging conservative. This avoids chain-merging neighboring atlas slots.
    if projection_overlap_ratio(a.pixel_bounds, b.pixel_bounds) < 0.35:
        return False
    combined_area = combined[2] * combined[3]
    visible_area = a.pixel_count + b.pixel_count
    if visible_area / max(1, combined_area) < 0.08:
        return False
    return True


def build_candidates(
    source_texture_path: str,
    image_size: tuple[int, int],
    comps: list[Component],
    tile_groups: list[set[tuple[int, int]]],
    base_tile: tuple[int, int],
    component_merge_distance_px: int,
    shadow_merge_distance_px: int,
    maximum_auto_region_size_tiles: tuple[int, int],
    crop_padding_px: int,
) -> list[Candidate]:
    uf = UnionFind([c.component_id for c in comps])
    by_id = {c.component_id: c for c in comps}
    for i, a in enumerate(comps):
        for b in comps[i + 1:]:
            dist = rect_distance(a.pixel_bounds, b.pixel_bounds)
            shadow_pair = looks_like_shadow(a, b) or looks_like_shadow(b, a)
            if can_auto_merge_pair(a, b, component_merge_distance_px, base_tile, maximum_auto_region_size_tiles):
                uf.union(a.component_id, b.component_id)
            elif shadow_pair and can_auto_merge_pair(a, b, shadow_merge_distance_px, base_tile, maximum_auto_region_size_tiles):
                uf.union(a.component_id, b.component_id)

    groups: dict[int, list[Component]] = defaultdict(list)
    for c in comps:
        groups[uf.find(c.component_id)].append(c)

    candidates: list[Candidate] = []
    for idx, members in enumerate(sorted(groups.values(), key=lambda group: rect_union(c.pixel_bounds for c in group)[1:2] + rect_union(c.pixel_bounds for c in group)[0:1]), start=1):
        tight = rect_union(c.pixel_bounds for c in members)
        source = expand_rect(tight, crop_padding_px, image_size)
        x, y, w, h = source
        tx0, ty0 = x // base_tile[0], y // base_tile[1]
        tx1 = math.ceil((x + w) / base_tile[0])
        ty1 = math.ceil((y + h) / base_tile[1])
        tile_span = (tx1 - tx0, ty1 - ty0)
        component_ids = [c.component_id for c in members]
        largest = max(members, key=lambda c: c.pixel_count)
        shadow_ids = [c.component_id for c in members if c.component_id != largest.component_id and looks_like_shadow(c, largest)]
        edge_touch = x == 0 or y == 0 or x + w == image_size[0] or y + h == image_size[1]
        too_large = tile_span[0] > maximum_auto_region_size_tiles[0] or tile_span[1] > maximum_auto_region_size_tiles[1]
        aspect = max(w / max(1, h), h / max(1, w))
        multi_part = len(members) > 1
        confidence = 0.92
        if multi_part:
            confidence -= 0.12
        if shadow_ids:
            confidence -= 0.04
        if edge_touch:
            confidence -= 0.12
        if too_large:
            confidence -= 0.35
        if aspect > 5.0:
            confidence -= 0.18
        confidence = max(0.05, min(0.99, confidence))
        touched = sorted({cell for c in members for cell in c.touched_tile_cells})
        footprint = (max(1, min(8, math.ceil(w / base_tile[0]))), max(1, min(8, math.ceil(h / base_tile[1]))))
        needs_review = confidence < 0.75 or multi_part or too_large
        candidates.append(Candidate(
            candidate_id=f"cand_{idx:04d}",
            source_texture_path=source_texture_path,
            source_region=source,
            tight_visual_bounds=tight,
            pixel_size=(w, h),
            tile_span=tile_span,
            connected_component_ids=component_ids,
            detected_shadow_components=shadow_ids,
            confidence_score=round(confidence, 3),
            needs_manual_review=needs_review,
            suggested_category="",
            suggested_group_id="",
            suggested_orientation="",
            suggested_item_id="",
            suggested_ground_footprint=footprint,
            touched_tile_cells=touched,
            includes_shadow=bool(shadow_ids),
        ))
    return candidates


def draw_alpha_mask(mask: list[bytearray], out: Path) -> None:
    h = len(mask)
    w = len(mask[0]) if h else 0
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    pix = img.load()
    for y in range(h):
        for x in range(w):
            if mask[y][x]:
                pix[x, y] = (255, 255, 255, 255)
    img.save(out)


def color_for(i: int) -> tuple[int, int, int, int]:
    return ((37 * i) % 220 + 30, (91 * i) % 220 + 30, (151 * i) % 220 + 30, 255)


def draw_component_map(image_size: tuple[int, int], comps: list[Component], labels: list[list[int]], out: Path) -> None:
    img = Image.new("RGBA", image_size, (20, 20, 20, 255))
    pix = img.load()
    for y, row in enumerate(labels):
        for x, cid in enumerate(row):
            if cid:
                pix[x, y] = color_for(cid)
    draw = ImageDraw.Draw(img)
    for c in comps:
        x, y, w, h = c.pixel_bounds
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline=color_for(c.component_id), width=1)
        draw.text((x, y), str(c.component_id), fill=(255, 255, 255, 255))
    img.save(out)


def candidate_id_list(candidates: list[Candidate], limit: int = 30) -> str:
    if not candidates:
        return "无"
    ids = [c.candidate_id for c in candidates[:limit]]
    if len(candidates) > limit:
        ids.append("...")
    return ", ".join(ids)


def draw_tile_groups(image: Image.Image, groups: list[set[tuple[int, int]]], base_tile: tuple[int, int], out: Path) -> None:
    canvas = image.convert("RGBA")
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for i, group in enumerate(groups, start=1):
        col = color_for(i)
        fill = (col[0], col[1], col[2], 60)
        for tx, ty in group:
            x, y = tx * base_tile[0], ty * base_tile[1]
            draw.rectangle((x, y, x + base_tile[0] - 1, y + base_tile[1] - 1), fill=fill, outline=col, width=1)
    canvas.alpha_composite(overlay)
    canvas.save(out)


def draw_candidate_regions(image: Image.Image, candidates: list[Candidate], out: Path) -> None:
    scale = 2
    canvas = image.convert("RGBA").resize((image.size[0] * scale, image.size[1] * scale), Image.Resampling.NEAREST)
    draw = ImageDraw.Draw(canvas)
    for i, c in enumerate(candidates, start=1):
        x, y, w, h = c.source_region
        col = color_for(i)
        rect = (x * scale, y * scale, (x + w) * scale - 1, (y + h) * scale - 1)
        draw.rectangle(rect, outline=col, width=2)
        label = f"{c.candidate_id} {w}x{h} t{c.tile_span[0]}x{c.tile_span[1]} c{c.confidence_score}"
        if c.needs_manual_review:
            label += " REVIEW"
        lx, ly = rect[0] + 2, rect[1] + 2
        draw.rectangle((lx - 1, ly - 1, lx + len(label) * 6, ly + 11), fill=(0, 0, 0, 180))
        draw.text((lx, ly), label, fill=(255, 255, 255, 255))
    canvas.save(out)


def draw_contact_sheet(image: Image.Image, candidates: list[Candidate], out: Path) -> None:
    thumb_scale = 4
    cell_w, cell_h = 220, 180
    cols = 4
    rows = math.ceil(len(candidates) / cols)
    sheet = Image.new("RGBA", (cols * cell_w, max(1, rows) * cell_h), (28, 28, 28, 255))
    draw = ImageDraw.Draw(sheet)
    for idx, c in enumerate(candidates):
        col = idx % cols
        row = idx // cols
        ox, oy = col * cell_w, row * cell_h
        x, y, w, h = c.source_region
        crop = image.crop((x, y, x + w, y + h)).convert("RGBA")
        max_w, max_h = 96, 96
        s = min(max_w / max(1, w), max_h / max(1, h), thumb_scale)
        crop = crop.resize((max(1, int(w * s)), max(1, int(h * s))), Image.Resampling.NEAREST)
        sheet.alpha_composite(crop, (ox + 8, oy + 8))
        lines = [
            c.candidate_id,
            f"region {x},{y},{w},{h}",
            f"size {c.pixel_size[0]}x{c.pixel_size[1]} tile {c.tile_span[0]}x{c.tile_span[1]}",
            f"conf {c.confidence_score} {'REVIEW' if c.needs_manual_review else 'ok'}",
            f"shadow {'yes' if c.includes_shadow else 'no'}",
            f"comps {','.join(map(str, c.connected_component_ids[:6]))}",
        ]
        ty = oy + 110
        for line in lines:
            draw.text((ox + 8, ty), line, fill=(235, 235, 235, 255))
            ty += 12
    sheet.save(out)


def write_manifest_tres(path: Path, data: dict) -> None:
    def rect2i(r: tuple[int, int, int, int]) -> str:
        return f"Rect2i({r[0]}, {r[1]}, {r[2]}, {r[3]})"

    def vec2i(v: tuple[int, int]) -> str:
        return f"Vector2i({v[0]}, {v[1]})"

    def vec2i_array(values: list[tuple[int, int]]) -> str:
        return "Array[Vector2i]([" + ", ".join(vec2i(v) for v in values) + "])"

    def int_array(values: list[int]) -> str:
        return "Array[int]([" + ", ".join(str(v) for v in values) + "])"

    lines = [
        f"[gd_resource type=\"Resource\" script_class=\"OfficeTilesetManifest\" load_steps={3 + len(data['candidates'])} format=3]",
        "",
        "[ext_resource type=\"Script\" path=\"res://scripts/floors/placement/import/office_tileset_manifest.gd\" id=\"1_manifest\"]",
        "[ext_resource type=\"Script\" path=\"res://scripts/floors/placement/import/candidate_asset_data.gd\" id=\"2_candidate\"]",
        "",
    ]
    candidate_refs = []
    for candidate in data["candidates"]:
        sid = "Candidate_" + candidate["candidate_id"]
        candidate_refs.append(f"SubResource(\"{sid}\")")
        lines.extend([
            f"[sub_resource type=\"Resource\" id=\"{sid}\"]",
            "script = ExtResource(\"2_candidate\")",
            f"candidate_id = &\"{candidate['candidate_id']}\"",
            f"source_texture_path = \"{candidate['source_texture_path']}\"",
            f"source_region = {rect2i(tuple(candidate['source_region']))}",
            f"tight_visual_bounds = {rect2i(tuple(candidate['tight_visual_bounds']))}",
            f"pixel_size = {vec2i(tuple(candidate['pixel_size']))}",
            f"tile_span = {vec2i(tuple(candidate['tile_span']))}",
            f"touched_tile_cells = {vec2i_array([tuple(v) for v in candidate['touched_tile_cells']])}",
            f"connected_component_ids = {int_array(candidate['connected_component_ids'])}",
            f"detected_shadow_components = {int_array(candidate['detected_shadow_components'])}",
            f"confidence_score = {candidate['confidence_score']}",
            f"needs_manual_review = {str(candidate['needs_manual_review']).lower()}",
            "review_state = 0",
            f"suggested_category = &\"{candidate['suggested_category']}\"",
            f"suggested_group_id = &\"{candidate['suggested_group_id']}\"",
            f"suggested_orientation = &\"{candidate['suggested_orientation']}\"",
            f"suggested_item_id = &\"{candidate['suggested_item_id']}\"",
            f"suggested_ground_footprint = {vec2i(tuple(candidate['suggested_ground_footprint']))}",
            f"includes_shadow = {str(candidate['includes_shadow']).lower()}",
            "",
        ])
    lines.extend([
        "[resource]",
        "script = ExtResource(\"1_manifest\")",
        f"source_texture_path = \"{data['source_texture_path']}\"",
        f"source_texture_hash = \"{data['source_texture_hash']}\"",
        f"source_image_size = Vector2i({data['source_image_size'][0]}, {data['source_image_size'][1]})",
        f"base_tile_size = Vector2i({data['base_tile_size'][0]}, {data['base_tile_size'][1]})",
        f"alpha_threshold = {data['alpha_threshold']}",
        f"minimum_visible_pixels_per_tile = {data['minimum_visible_pixels_per_tile']}",
        f"component_merge_distance_px = {data['component_merge_distance_px']}",
        f"shadow_merge_distance_px = {data['shadow_merge_distance_px']}",
        f"maximum_auto_region_size_tiles = Vector2i({data['maximum_auto_region_size_tiles'][0]}, {data['maximum_auto_region_size_tiles'][1]})",
        f"crop_padding_px = {data['crop_padding_px']}",
        "candidates = [" + ", ".join(candidate_refs) + "]",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--texture", default="assets/Office Tileset/Office Tileset All 32x32.png")
    parser.add_argument("--out-dir", default="debug/generated_asset_audit")
    parser.add_argument("--alpha-threshold", type=int, default=8)
    parser.add_argument("--minimum-visible-pixels-per-tile", type=int, default=2)
    parser.add_argument("--base-tile-size", type=int, nargs=2, default=(32, 32))
    parser.add_argument("--component-merge-distance-px", type=int, default=4)
    parser.add_argument("--shadow-merge-distance-px", type=int, default=8)
    parser.add_argument("--maximum-auto-region-size-tiles", type=int, nargs=2, default=(8, 8))
    parser.add_argument("--crop-padding-px", type=int, default=1)
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    source = (root / args.texture).resolve()
    out_dir = (root / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    data_dir = root / "data" / "office_tileset_import"
    data_dir.mkdir(parents=True, exist_ok=True)

    png_audit = []
    for png in sorted((root / "assets" / "Office Tileset").rglob("*.png")):
        with Image.open(png) as im:
            png_audit.append(classify_png(png.relative_to(root), im.convert("RGBA")))

    image = Image.open(source).convert("RGBA")
    mask, alpha = make_mask(image, args.alpha_threshold)
    comps, labels = connected_components(image, mask, alpha, tuple(args.base_tile_size))
    tile_stat, tile_groups = tile_stats(mask, alpha, tuple(args.base_tile_size), args.minimum_visible_pixels_per_tile)
    candidates = build_candidates(
        "res://" + str(source.relative_to(root)).replace("\\", "/"),
        image.size,
        comps,
        tile_groups,
        tuple(args.base_tile_size),
        args.component_merge_distance_px,
        args.shadow_merge_distance_px,
        tuple(args.maximum_auto_region_size_tiles),
        args.crop_padding_px,
    )

    draw_alpha_mask(mask, out_dir / "office_tileset_32_alpha_mask.png")
    draw_component_map(image.size, comps, labels, out_dir / "office_tileset_32_components.png")
    draw_tile_groups(image, tile_groups, tuple(args.base_tile_size), out_dir / "office_tileset_32_tile_groups.png")
    draw_candidate_regions(image, candidates, out_dir / "office_tileset_32_candidate_regions.png")
    draw_contact_sheet(image, candidates, out_dir / "office_tileset_32_contact_sheet.png")

    low_conf = [asdict(c) for c in candidates if c.confidence_score < 0.75]
    suspected_merge_candidates = [c for c in candidates if c.needs_manual_review and len(c.connected_component_ids) > 1]
    suspected_split_candidates = [c for c in candidates if c.pixel_size[0] < 10 or c.pixel_size[1] < 10]
    suspected_merges = [asdict(c) for c in suspected_merge_candidates]
    suspected_splits = [asdict(c) for c in suspected_split_candidates]
    low_conf_candidates = [c for c in candidates if c.confidence_score < 0.75]
    manifest = {
        "source_texture_path": "res://" + str(source.relative_to(root)).replace("\\", "/"),
        "source_texture_hash": file_sha256(source),
        "source_image_size": image.size,
        "base_tile_size": tuple(args.base_tile_size),
        "alpha_threshold": args.alpha_threshold,
        "minimum_visible_pixels_per_tile": args.minimum_visible_pixels_per_tile,
        "component_merge_distance_px": args.component_merge_distance_px,
        "shadow_merge_distance_px": args.shadow_merge_distance_px,
        "maximum_auto_region_size_tiles": tuple(args.maximum_auto_region_size_tiles),
        "crop_padding_px": args.crop_padding_px,
        "png_audit": png_audit,
        "components": [asdict(c) for c in comps],
        "tile_group_count": len(tile_groups),
        "candidates": [asdict(c) for c in candidates],
        "low_confidence_candidates": low_conf,
        "suspected_error_merges": suspected_merges,
        "suspected_split_furniture": suspected_splits,
        "suggested_direction_groups": [
            {
                "note": "未自动确认方向组。当前图集中存在大候选合并和相邻对象接触风险，方向分组必须人工确认后写入 Manifest。",
                "examples_to_review": ["red_chair", "office_desk", "potted_plant", "water_dispenser", "long_bench"],
            }
        ],
    }
    manifest_json = data_dir / "office_tileset_manifest.json"
    manifest_json.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    write_manifest_tres(data_dir / "office_tileset_manifest.tres", manifest)

    with (out_dir / "office_tileset_png_audit.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(png_audit[0].keys()))
        writer.writeheader()
        writer.writerows(png_audit)
    report = [
        "# Office Tileset 自动检测报告",
        "",
        f"- source: `{manifest['source_texture_path']}`",
        f"- source_image_size: {image.size[0]}x{image.size[1]}",
        f"- source_texture_hash: `{manifest['source_texture_hash']}`",
        f"- alpha_threshold: {args.alpha_threshold}",
        f"- pixel_components: {len(comps)}",
        f"- tile_groups: {len(tile_groups)}",
        f"- merged_candidates: {len(candidates)}",
        f"- high_confidence: {sum(1 for c in candidates if not c.needs_manual_review)}",
        f"- needs_manual_review: {sum(1 for c in candidates if c.needs_manual_review)}",
        f"- low_confidence: {len(low_conf)}",
        f"- tile_group_warning: {'occupied tiles collapsed into one large group; tile-only detection is unreliable' if len(tile_groups) == 1 else 'none'}",
        "",
        "## 输出文件",
        "",
        "- `debug/generated_asset_audit/office_tileset_32_alpha_mask.png`",
        "- `debug/generated_asset_audit/office_tileset_32_components.png`",
        "- `debug/generated_asset_audit/office_tileset_32_tile_groups.png`",
        "- `debug/generated_asset_audit/office_tileset_32_candidate_regions.png`",
        "- `debug/generated_asset_audit/office_tileset_32_contact_sheet.png`",
        "- `data/office_tileset_import/office_tileset_manifest.json`",
        "- `data/office_tileset_import/office_tileset_manifest.tres`",
        "",
        "## 低置信度 candidate",
        "",
        candidate_id_list(low_conf_candidates),
        "",
        "## 疑似错误合并",
        "",
        candidate_id_list(suspected_merge_candidates),
        "",
        "## 疑似被拆开的家具/碎片",
        "",
        candidate_id_list(suspected_split_candidates),
        "",
        "## 建议方向分组",
        "",
        "本轮不自动确认方向组。请在 contact sheet 中人工确认红色椅子、办公桌、盆栽、饮水机、长椅后，再把候选加入同一 group 并设置 orientation。",
        "",
        "## 对象接触风险",
        "",
        "Tile 级 occupied cells 连成 1 个大组，说明图集中相邻物品在 tile 层面非常容易接触或连续，不能仅依赖 tile group 自动拆分。",
        "",
        "## 注意",
        "",
        "自动检测只生成 Candidate，不生成正式 PlaceableItemData。所有正式家具必须在 Manifest 中 approved 后再生成。",
    ]
    (out_dir / "office_tileset_detection_report.md").write_text("\n".join(report), encoding="utf-8")
    print("\n".join(report[:12]))


if __name__ == "__main__":
    main()
