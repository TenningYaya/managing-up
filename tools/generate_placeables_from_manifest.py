from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path


CATEGORY_TO_DIR = {
    "room": "rooms",
    "desk": "desks",
    "utility": "utilities",
    "small_decor": "decorations",
    "floor_decor": "floor_decorations",
    "zone_prefab": "zones",
    "chair": "chairs",
    "plant": "plants",
}

CATEGORY_ENUM = {
    "room": 0,
    "desk": 1,
    "utility": 2,
    "small_decor": 3,
    "chair": 3,
    "plant": 3,
    "zone_prefab": 4,
    "floor_decor": 5,
}

DIRECTION_ENUM = {
    "none": 0,
    "north": 1,
    "east": 2,
    "south": 3,
    "west": 4,
    "horizontal": 5,
    "vertical": 6,
    "left": 7,
    "right": 8,
}


def rect2i(r: list[int]) -> str:
    return f"Rect2i({r[0]}, {r[1]}, {r[2]}, {r[3]})"


def vec2i(v: list[int] | tuple[int, int]) -> str:
    return f"Vector2i({v[0]}, {v[1]})"


def v2_array(values: list[list[int]]) -> str:
    return "Array[Vector2i]([" + ", ".join(vec2i(v) for v in values) + "])"


def safe_id(value: str) -> str:
    return "".join(ch if ch.isalnum() or ch == "_" else "_" for ch in value.strip().lower()).strip("_")


def candidate_value(c: dict, manual_key: str, suggested_key: str, default=""):
    value = c.get(manual_key)
    if value not in (None, "", [], [0, 0], [0, 0, 0, 0]):
        return value
    return c.get(suggested_key, default)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--manifest", default="data/office_tileset_import/office_tileset_manifest.json")
    parser.add_argument("--approvals", default="")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    root = Path(args.project_root).resolve()
    manifest_path = root / args.manifest
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if args.approvals:
        approvals_path = root / args.approvals
        approvals = json.loads(approvals_path.read_text(encoding="utf-8"))
        groups = {item["item_id"]: item["orientations"] for item in approvals["items"]}
        item_meta = {item["item_id"]: item for item in approvals["items"]}
        print(f"Loaded manual approvals: {len(groups)} items")
        return generate_from_approval_groups(root, data, groups, item_meta, args.dry_run)

    approved = [c for c in data["candidates"] if c.get("review_state") == "approved" or c.get("approved") is True]
    groups: dict[str, list[dict]] = defaultdict(list)
    for c in approved:
        group = safe_id(str(candidate_value(c, "manual_group_id", "suggested_group_id", "")))
        orientation = safe_id(str(candidate_value(c, "manual_orientation", "suggested_orientation", "")))
        item_id = safe_id(str(candidate_value(c, "manual_item_id", "suggested_item_id", group)))
        if not group or not orientation or not item_id:
            print(f"SKIP {c['candidate_id']}: missing item/group/orientation")
            continue
        c["_group"] = group
        c["_orientation"] = orientation
        c["_item_id"] = item_id
        groups[item_id].append(c)

    if not groups:
        print("No approved candidates found. Nothing generated.")
        return

    for item_id, candidates in sorted(groups.items()):
        first = candidates[0]
        category_name = safe_id(str(candidate_value(first, "manual_category_name", "suggested_category", "small_decor"))) or "small_decor"
        target_dir = root / "data" / "placeable_items" / CATEGORY_TO_DIR.get(category_name, "decorations")
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / f"{item_id}.tres"
        display_name = first.get("manual_display_name") or item_id
        default_orientation = candidates[0]["_orientation"]
        lines = [
            f"[gd_resource type=\"Resource\" script_class=\"PlaceableItemData\" load_steps={5 + len(candidates)} format=3]",
            "",
            "[ext_resource type=\"Script\" path=\"res://scripts/floors/placement/placeable_item_data.gd\" id=\"1_item\"]",
            "[ext_resource type=\"Script\" path=\"res://scripts/floors/placement/placeable_orientation_data.gd\" id=\"2_orientation\"]",
            f"[ext_resource type=\"Texture2D\" path=\"{data['source_texture_path']}\" id=\"3_atlas\"]",
            "[ext_resource type=\"PackedScene\" path=\"res://scenes/floors/placement/office_tileset_prop.tscn\" id=\"4_scene\"]",
            "",
        ]
        refs = []
        icon_region = candidates[0].get("manual_region") or candidates[0]["source_region"]
        lines.extend([
            "[sub_resource type=\"AtlasTexture\" id=\"AtlasTexture_icon\"]",
            "atlas = ExtResource(\"3_atlas\")",
            f"region = Rect2({icon_region[0]}, {icon_region[1]}, {icon_region[2]}, {icon_region[3]})",
            "",
        ])
        for idx, c in enumerate(candidates, start=1):
            sid = f"Orientation_{idx}_{c['_orientation']}"
            refs.append(f"SubResource(\"{sid}\")")
            region = c.get("manual_region") or c["source_region"]
            footprint = c.get("manual_ground_footprint") or c.get("suggested_ground_footprint") or [1, 1]
            if footprint == [0, 0]:
                footprint = [1, 1]
            direction = DIRECTION_ENUM.get(c["_orientation"], 0)
            lines.extend([
                f"[sub_resource type=\"Resource\" id=\"{sid}\"]",
                "script = ExtResource(\"2_orientation\")",
                f"orientation_id = &\"{c['_orientation']}\"",
                f"direction = {direction}",
                "texture = ExtResource(\"3_atlas\")",
                f"atlas_region = {rect2i(region)}",
                f"visual_size = Vector2({region[2]}, {region[3]})",
                f"footprint = {vec2i(footprint)}",
                "is_default = true" if c["_orientation"] == default_orientation else "is_default = false",
                "",
            ])
        lines.extend([
            "[resource]",
            "script = ExtResource(\"1_item\")",
            f"item_id = &\"{item_id}\"",
            f"display_name = \"{display_name}\"",
            "description = \"Approved Office Tileset atlas candidate generated from audit manifest.\"",
            f"category = {CATEGORY_ENUM.get(category_name, 3)}",
            "scene = ExtResource(\"4_scene\")",
            "icon = SubResource(\"AtlasTexture_icon\")",
            "tags = Array[StringName]([&\"office_tileset\", &\"generated_from_manifest\"])",
            "orientations = [" + ", ".join(refs) + "]",
            f"default_orientation_id = &\"{default_orientation}\"",
            "allow_mouse_wheel_rotation = true",
            "use_directional_sprites = true",
            "allow_transform_rotation = false",
            f"style_group = &\"{item_id}\"",
            "render_style = 0",
            "auto_calculate_footprint = false",
            "can_rotate = false",
            "unlock_level = 1",
        ])
        if args.dry_run:
            print(f"DRY {target}")
        else:
            target.write_text("\n".join(lines), encoding="utf-8")
            print(f"WROTE {target}")


def vec2_array(values: list[list[float]]) -> str:
    return "Array[Vector2]([" + ", ".join(f"Vector2({v[0]}, {v[1]})" for v in values) + "])"


def occupied_rect_cells(fp: list[int]) -> list[list[int]]:
    return [[x, y] for y in range(max(1, fp[1])) for x in range(max(1, fp[0]))]


def generate_from_approval_groups(root: Path, manifest: dict, groups: dict, item_meta: dict, dry_run: bool) -> None:
    for item_id, orientations in sorted(groups.items()):
        meta = item_meta[item_id]
        category_name = safe_id(meta.get("category", "small_decor")) or "small_decor"
        target_dir = root / "data" / "placeable_items" / CATEGORY_TO_DIR.get(category_name, "decorations")
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / f"{item_id}.tres"
        default_orientation = meta.get("default_orientation_id", orientations[0]["orientation_id"])
        icon_region = orientations[0]["region"]
        lines = [
            f"[gd_resource type=\"Resource\" script_class=\"PlaceableItemData\" load_steps={5 + len(orientations)} format=3]",
            "",
            "[ext_resource type=\"Script\" path=\"res://scripts/floors/placement/placeable_item_data.gd\" id=\"1_item\"]",
            "[ext_resource type=\"Script\" path=\"res://scripts/floors/placement/placeable_orientation_data.gd\" id=\"2_orientation\"]",
            f"[ext_resource type=\"Texture2D\" path=\"{manifest['source_texture_path']}\" id=\"3_atlas\"]",
            "[ext_resource type=\"PackedScene\" path=\"res://scenes/floors/placement/office_tileset_prop.tscn\" id=\"4_scene\"]",
            "",
            "[sub_resource type=\"AtlasTexture\" id=\"AtlasTexture_icon\"]",
            "atlas = ExtResource(\"3_atlas\")",
            f"region = Rect2({icon_region[0]}, {icon_region[1]}, {icon_region[2]}, {icon_region[3]})",
            "",
        ]
        refs = []
        for idx, o in enumerate(orientations, start=1):
            orientation_id = safe_id(o["orientation_id"])
            sid = f"Orientation_{idx}_{orientation_id}"
            refs.append(f"SubResource(\"{sid}\")")
            region = o["region"]
            footprint = o.get("footprint", [1, 1])
            occupied = o.get("occupied_cells", occupied_rect_cells(footprint))
            interaction = o.get("interaction_points", [])
            lines.extend([
                f"[sub_resource type=\"Resource\" id=\"{sid}\"]",
                "script = ExtResource(\"2_orientation\")",
                f"orientation_id = &\"{orientation_id}\"",
                f"direction = {DIRECTION_ENUM.get(orientation_id, 0)}",
                "texture = ExtResource(\"3_atlas\")",
                f"atlas_region = {rect2i(region)}",
                f"visual_size = Vector2({region[2]}, {region[3]})",
                f"footprint = {vec2i(footprint)}",
                f"occupied_cells = {v2_array(occupied)}",
                f"interaction_points = {vec2_array(interaction)}",
                "is_default = true" if orientation_id == default_orientation else "is_default = false",
                "",
            ])
        lines.extend([
            "[resource]",
            "script = ExtResource(\"1_item\")",
            f"item_id = &\"{item_id}\"",
            f"display_name = \"{meta.get('display_name', item_id)}\"",
            f"description = \"{meta.get('description', 'Approved Office Tileset atlas candidate generated from audit manifest.')}\"",
            f"category = {CATEGORY_ENUM.get(category_name, 3)}",
            "scene = ExtResource(\"4_scene\")",
            "icon = SubResource(\"AtlasTexture_icon\")",
            "tags = Array[StringName]([&\"office_tileset\", &\"generated_from_manifest\", &\"first_batch\"])",
            "orientations = [" + ", ".join(refs) + "]",
            f"default_orientation_id = &\"{default_orientation}\"",
            "allow_mouse_wheel_rotation = true",
            "use_directional_sprites = true",
            "allow_transform_rotation = false",
            f"style_group = &\"{meta.get('style_group', item_id)}\"",
            f"color_variant = &\"{meta.get('color_variant', '')}\"",
            "render_style = 0",
            "auto_calculate_footprint = false",
            *([f"placement_offset = Vector2({meta['placement_offset'][0]}, {meta['placement_offset'][1]})"]
              if "placement_offset" in meta else []),
            "can_be_placed_in_open_floor = true",
            "can_rotate = false",
            "blocks_navigation = true",
            f"price = {int(meta.get('price', 100))}",
            f"sell_price = {int(meta.get('sell_price', int(meta.get('price', 100)) // 2))}",
            "unlock_level = 1",
        ])
        if dry_run:
            print(f"DRY {target}")
        else:
            target.write_text("\n".join(lines), encoding="utf-8")
            print(f"WROTE {target}")


if __name__ == "__main__":
    main()
