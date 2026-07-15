# Office Tileset 自动检测报告

- source: `res://assets/Office Tileset/Office Tileset All 32x32.png`
- source_image_size: 512x1024
- source_texture_hash: `b9d999505c4f7447c9fa7dc1f638570c9847c0f2586463425d6afa5d67c6e0e5`
- alpha_threshold: 8
- pixel_components: 150
- tile_groups: 1
- merged_candidates: 101
- high_confidence: 74
- needs_manual_review: 27
- low_confidence: 10
- tile_group_warning: occupied tiles collapsed into one large group; tile-only detection is unreliable

## 输出文件

- `debug/generated_asset_audit/office_tileset_32_alpha_mask.png`
- `debug/generated_asset_audit/office_tileset_32_components.png`
- `debug/generated_asset_audit/office_tileset_32_tile_groups.png`
- `debug/generated_asset_audit/office_tileset_32_candidate_regions.png`
- `debug/generated_asset_audit/office_tileset_32_contact_sheet.png`
- `data/office_tileset_import/office_tileset_manifest.json`
- `data/office_tileset_import/office_tileset_manifest.tres`

## 低置信度 candidate

cand_0005, cand_0006, cand_0008, cand_0009, cand_0021, cand_0022, cand_0025, cand_0026, cand_0050, cand_0071

## 疑似错误合并

cand_0006, cand_0009, cand_0019, cand_0029, cand_0036, cand_0037, cand_0040, cand_0045, cand_0046, cand_0050, cand_0053, cand_0060, cand_0061, cand_0062, cand_0063, cand_0071, cand_0077, cand_0082, cand_0083, cand_0088, cand_0098

## 疑似被拆开的家具/碎片

无

## 建议方向分组

本轮不自动确认方向组。请在 contact sheet 中人工确认红色椅子、办公桌、盆栽、饮水机、长椅后，再把候选加入同一 group 并设置 orientation。

## 对象接触风险

Tile 级 occupied cells 连成 1 个大组，说明图集中相邻物品在 tile 层面非常容易接触或连续，不能仅依赖 tile group 自动拆分。

## 注意

自动检测只生成 Candidate，不生成正式 PlaceableItemData。所有正式家具必须在 Manifest 中 approved 后再生成。