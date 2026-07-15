# Office Tileset 第一批批准生成报告

日期：2026-07-14

## 生成策略

- 使用批准清单：`data/office_tileset_import/first_batch_approvals.json`
- 使用源图集：`res://assets/Office Tileset/Office Tileset All 32x32.png`
- 未输出任何单独裁剪 PNG。
- 每个逻辑家具只生成一个 `PlaceableItemData`。
- 方向变体写入同一文件的 `orientations`，不会按方向拆成多个菜单项。

## 已生成正式装修物品

| item_id | 中文名 | 文件 | 菜单分类 | 方向 |
| --- | --- | --- | --- | --- |
| `office_chair_red` | 红色办公椅 | `data/placeable_items/chairs/office_chair_red.tres` | 装饰 | south, north, west, east |
| `office_desk_wood` | 木质办公桌 | `data/placeable_items/desks/office_desk_wood.tres` | 工位 | horizontal |
| `office_potted_plant_brown` | 盆栽 | `data/placeable_items/plants/office_potted_plant_brown.tres` | 装饰 | none |
| `water_dispenser` | 饮水机 | `data/placeable_items/utilities/water_dispenser.tres` | 设施 | left, right |
| `office_long_bench` | 长椅 | `data/placeable_items/chairs/office_long_bench.tres` | 装饰 | horizontal, vertical |

## 仍需截图确认

- 红色办公椅四方向视觉是否对应玩家直觉。
- 长椅横向 region 是人工校正区域，需要在游戏里确认没有切少/多切。
- 盆栽视觉高度与地面 footprint 已分离，目前地面占 1x1。
- 饮水机左右互动点已写入方向数据，但需要调试层确认位置。
- 木质办公桌目前只批准一个横向方向，后续可继续补纵向方向。

## 注意

如果游戏已经在运行，需要重启当前场景或重新扫描 `PlaceableItemDB`，新 `.tres` 才会出现在装修菜单。
