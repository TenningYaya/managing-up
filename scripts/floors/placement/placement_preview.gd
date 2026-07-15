class_name PlacementPreview
extends Node2D
# 放置预览:半透明幽灵 + 格子反馈染色。
# 状态色:绿=合法 / 红=重叠越界或规则不满足 / 黄=有风险但可放(如贴着入口)。
# 绘制坐标全部经 DecoratableFloor(→TileMapLayer)换算。

enum Status { OK, WARN, BAD }

const COL_FILL := {
	Status.OK: Color(0.2, 1.0, 0.3, 0.30),
	Status.WARN: Color(1.0, 0.85, 0.2, 0.35),
	Status.BAD: Color(1.0, 0.2, 0.15, 0.35),
}
const COL_GHOST := {
	Status.OK: Color(1, 1, 1, 0.55),
	Status.WARN: Color(1, 0.95, 0.6, 0.55),
	Status.BAD: Color(1, 0.45, 0.4, 0.55),
}
const COL_ANCHOR := Color(1, 1, 1, 0.9)

var floor_node: DecoratableFloor = null
var _ghost: Node = null            # 半透明的物品副本(仅新放置时创建;移动模式直接挪原件)
var _data: PlaceableItemData = null
var _cells: Array[Vector2i] = []   # 当前预览占用的世界格
var _status: int = Status.BAD
var _origin_cell := Vector2i.ZERO
var _active := false
var _orientation_id: StringName = &""


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = 960
	z_as_relative = false


# 开始预览一个新物品(创建幽灵副本);移动已放置物件时 ghost_scene 传 null
func begin(data: PlaceableItemData, with_ghost: bool, orientation_id: StringName = &"") -> void:
	clear()
	_active = true
	_data = data
	_orientation_id = data.normalize_orientation_id(orientation_id) if data != null else &""
	if with_ghost and data != null and data.scene != null:
		_ghost = data.scene.instantiate()
		add_child(_ghost)
		_neutralize(_ghost)  # 必须在入树后:group 是各脚本 _ready 里加的
		_apply_orientation_to_ghost()


func set_variant(v: int) -> void:
	if _data != null and _data.has_orientations():
		var orientation := _data.get_orientation_by_index(v)
		if orientation != null:
			set_orientation_id(orientation.orientation_id)
		return
	if _ghost != null and _ghost.has_method("set_variant"):
		_ghost.set_variant(v)


func set_orientation_id(orientation_id: StringName) -> void:
	_orientation_id = _data.normalize_orientation_id(orientation_id) if _data != null else &""
	_apply_orientation_to_ghost()


func get_variant_count() -> int:
	if _data != null and _data.has_orientations():
		return _data.get_orientation_count()
	if _ghost != null and _ghost.has_method("get_variant_count"):
		return _ghost.get_variant_count()
	return 1


func update_preview(origin_cell: Vector2i, cells: Array[Vector2i], status: int) -> void:
	_origin_cell = origin_cell
	_cells = cells
	_status = status
	if _ghost != null and (_ghost is Node2D or _ghost is Control):
		# 与 PlacedFloorItem 相同的对齐补偿:把素材"有效边界"的左上角贴到格角,
		# 否则预览和实际落位差一个内边距(placement_offset)
		var comp := _data.get_visual_offset(_orientation_id) if _data != null else Vector2.ZERO
		var placement_adjust := _data.placement_offset if _data != null and _data.has_orientations() else Vector2.ZERO
		_ghost.global_position = _cell_corner(origin_cell) + placement_adjust - comp
		_ghost.modulate = COL_GHOST[status]
	queue_redraw()


func clear() -> void:
	_active = false
	_cells = []
	_data = null
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_orientation_id = &""
	queue_redraw()


func _draw() -> void:
	if not _active or floor_node == null:
		return
	var half: Vector2 = floor_node._half_cell()
	for cell in _cells:
		draw_rect(Rect2(_cell_corner(cell), half * 2.0), COL_FILL[_status], true)
		draw_rect(Rect2(_cell_corner(cell), half * 2.0), Color(1, 1, 1, 0.25), false, 1.0)
	# 锚点格角标
	var a := _cell_corner(_origin_cell)
	draw_line(a, a + Vector2(half.x * 0.6, 0), COL_ANCHOR, 2.0)
	draw_line(a, a + Vector2(0, half.y * 0.6), COL_ANCHOR, 2.0)


func get_debug_info() -> Dictionary:
	var orientation: PlaceableOrientationData = null
	if _data != null:
		orientation = _data.get_orientation(_orientation_id)
	return {
		"item_id": String(_data.item_id) if _data != null else "",
		"orientation_id": String(_orientation_id),
		"atlas_region": orientation.get_region() if orientation != null else Rect2i(),
		"placement_anchor": orientation.placement_anchor if orientation != null else Vector2.ZERO,
		"visual_bounds": Rect2(_cell_corner(_origin_cell), orientation.get_visual_size()) if orientation != null else Rect2(),
		"footprint": _data.get_footprint(_orientation_id) if _data != null else Vector2i.ZERO,
		"occupied_cells": _cells,
		"blocked_cells": _data.get_blocked_cells(_orientation_id) if _data != null else [],
		"interaction_points": _data.get_interaction_points(_orientation_id) if _data != null else [],
		"origin_cell": _origin_cell,
		"is_valid": _status != Status.BAD,
		"illegal_reason": "" if _status != Status.BAD else "当前位置不可放置",
	}


func _cell_corner(cell: Vector2i) -> Vector2:
	return floor_node.cell_to_global(cell) - floor_node._half_cell()


# 幽灵不参与任何游戏逻辑(同 FootprintEstimator 的假人化)
static func _neutralize(node: Node) -> void:
	for g in node.get_groups():
		if not String(g).begins_with("_"):
			node.remove_from_group(g)
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_neutralize(c)


func _apply_orientation_to_ghost() -> void:
	if _ghost == null or _data == null:
		return
	if _ghost.has_method("configure_from_item_data"):
		_ghost.configure_from_item_data(_data, _orientation_id)
	elif _ghost.has_method("set_orientation_id"):
		_ghost.set_orientation_id(_orientation_id)
