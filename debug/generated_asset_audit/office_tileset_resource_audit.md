# Office Tileset 真实资源结构审计

审计日期：2026-07-14

## PNG 结构

- 根目录：`res://assets/Office Tileset/`
- 所有 PNG 都带 Alpha 通道。
- 存在完整 atlas：
  - `Office Tileset All 16x16.png`，256x512，shadow
  - `Office Tileset All 16x16 no shadow.png`，256x512，shadowless
  - `Office Tileset All 32x32.png`，512x1024，shadow
  - `Office Tileset All 32x32 no shadow.png`，512x1024，shadowless
  - `Office Tileset All 48x48.png`，768x1536，shadow
  - `Office Tileset All 48x48 no shadow.png`，768x1536，shadowless
- 存在 VX Ace 分页 atlas：
  - `Office VX Ace/A2 Office Floors.png`
  - `Office VX Ace/A4 Office Walls.png`
  - `Office VX Ace/A5 Office Floors & Walls.png`
  - `Office VX Ace/B-C-D-E Office 1.png`
  - `Office VX Ace/B-C-D-E Office 1 No Shadows.png`
  - `Office VX Ace/B-C-D-E Office 2.png`
  - `Office VX Ace/B-C-D-E Office 2 No Shadows.png`
- 存在示例设计整图：
  - `Office Designs/Office Level 1.png`
  - `Office Designs/Office Level 2.png`
  - `Office Designs/Office Level 3.png`
  - `Office Designs/Office Level 3.5.png`
  - `Office Designs/Office Level 4.png`
- 存在 Palette 小图，不是家具拆分资源。
- 未发现按单独家具拆好的独立对象 PNG，因此需要从完整 atlas 做候选识别。

完整 CSV：`debug/generated_asset_audit/office_tileset_png_audit.csv`

## TileSet / AtlasTexture 状态

- `scenes/main.tscn` 中存在 `TileSetAtlasSource`，引用 `Office VX Ace/A5 Office Floors & Walls.png`，用于现有地面/墙面。
- `scenes/office/office.tscn` 中存在 `TileSetAtlasSource`，同样引用 VX Ace 地面墙面。
- `Office Tileset All 32x32.png` 当前没有已确认的家具 `TileSetAtlasSource` 或逐对象 `.tres/.res`。
- 上一轮错误生成的第一批 `PlaceableItemData` 已删除，避免被装修菜单扫描。

## 自动检测结论

- 本轮优先检测：`res://assets/Office Tileset/Office Tileset All 32x32.png`
- 图集尺寸：512x1024
- 基础网格：32x32
- Alpha 阈值：8
- 像素级 8 方向连通组件：150
- Tile 占用分组：1
- 自动合并候选：101
- 高置信度候选：74
- 需要人工复核：27
- 低置信度：10

Tile 占用分组只有 1 个，说明整张图集在 tile 层面会连成大片，不能只靠 32x32 tile 或 tile group 自动切家具。正式资源必须从 candidate Manifest 中人工确认后生成。

Machine-readable stats: pixel_components=150; tile_groups=1; candidates=101; high_confidence=74; needs_manual_review=27; low_confidence=10.
