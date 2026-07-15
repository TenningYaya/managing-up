class_name OccupancyGrid
extends RefCounted
# 楼层占用网格(纯数据,不进场景树)。
#
# 坐标约定:一律使用所属楼层 FloorTileMap(TileMapLayer)的 map 坐标(Vector2i)。
# 本类不做任何像素换算——格子 ↔ 像素的转换只允许通过 TileMapLayer 的
# map_to_local()/local_to_map()/to_global()/to_local() 完成(见 DecoratableFloor),
# 这里绝不出现 tile 尺寸魔法数字,存档也只存 map 坐标。
#
# 阶段 2 提供固定外壳数据(可建造/固定阻挡/入口);
# 阶段 4 起 occupants 记录"格子 → 已放置实例",并扩展查询接口。

var buildable := {}       # Vector2i -> true:开放可建造格(不含墙、不含入口)
var fixed_blocked := {}   # Vector2i -> true:固定结构(外墙等),永不可建造/不可通行
var entrance := {}        # Vector2i -> true:固定入口/电梯口,可通行但不可建造
var occupants := {}       # Vector2i -> instance_id(String),阶段 4 使用

# 整层外壳范围(含外墙),map 坐标。仅作快速越界判断的辅助缓存
var bounds := Rect2i()


func is_inside(cell: Vector2i) -> bool:
	return bounds.has_point(cell)


# 该格当前是否可以放置物品(在可建造区内且没被占用)
func is_buildable(cell: Vector2i) -> bool:
	return buildable.has(cell) and not occupants.has(cell)


# 该格是否可通行(供导航/入口连通检查):开放格未被占用,或是入口格
func is_walkable(cell: Vector2i) -> bool:
	if fixed_blocked.has(cell):
		return false
	if entrance.has(cell):
		return true
	return buildable.has(cell) and not occupants.has(cell)


func is_fixed_blocked(cell: Vector2i) -> bool:
	return fixed_blocked.has(cell)


func is_entrance(cell: Vector2i) -> bool:
	return entrance.has(cell)


# 一组格子是否全部可建造(放置前的整体判定入口,阶段 4 扩展重叠细分原因)
func can_place_all(cells: Array[Vector2i]) -> bool:
	for c in cells:
		if not is_buildable(c):
			return false
	return true


func get_occupant(cell: Vector2i) -> String:
	return occupants.get(cell, "")


func occupy(cells: Array[Vector2i], instance_id: String) -> void:
	for c in cells:
		occupants[c] = instance_id


func release(instance_id: String) -> void:
	for c in occupants.keys():
		if occupants[c] == instance_id:
			occupants.erase(c)


func clear_all_occupants() -> void:
	occupants.clear()
