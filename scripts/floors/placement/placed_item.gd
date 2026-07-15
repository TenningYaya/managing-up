class_name PlacedFloorItem
extends Node2D
# 已放置物件的包装节点(外部 PlacementComponent 方案):
# 元数据(instance_id/格坐标/旋转/归属)全在包装层,原 Scene 作为子节点原样实例化,
# 不改写 Office/DeskSlot 等原有脚本。存档只记 grid 坐标,像素位置由楼层换算恢复。

var instance_id: String = ""
var item_id: StringName = &""
var data: PlaceableItemData = null
var origin_cell := Vector2i.ZERO      # 锚点格(map 坐标)
var rotation_deg: int = 0             # 0/90/180/270
var variant: int = 0                  # 朝向/花色变体(场景实现 set_variant 时生效)
var orientation_id: StringName = &""
var parent_room_id: String = ""       # 阶段 5:Room 内家具记录所属房间
var local_grid_position := Vector2i.ZERO  # 阶段 5:相对 Room 的格偏移
var custom_state := {}
var scene_instance: Node = null


# 把 anchor 相对格偏移按旋转角变换(保持非负:旋转后重新锚定到左上)
static func rotate_offsets(cells: Array[Vector2i], footprint: Vector2i, deg: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		match posmod(deg, 360):
			90:
				out.append(Vector2i(footprint.y - 1 - c.y, c.x))
			180:
				out.append(Vector2i(footprint.x - 1 - c.x, footprint.y - 1 - c.y))
			270:
				out.append(Vector2i(c.y, footprint.x - 1 - c.x))
			_:
				out.append(c)
	return out


# 当前占用的世界格列表(origin + 旋转后的偏移)
func get_world_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells := data.get_occupied_cells(orientation_id)
	var fp := data.get_footprint(orientation_id)
	for c in PlacedFloorItem.rotate_offsets(cells, fp, rotation_deg):
		out.append(origin_cell + c)
	return out


# 由 DecoratableFloor 调用完成组装
func setup(p_data: PlaceableItemData, p_instance_id: String, floor_id: int) -> void:
	data = p_data
	item_id = p_data.item_id
	instance_id = p_instance_id
	name = p_instance_id
	set_meta("floor_id", floor_id)
	set_meta("placed_instance_id", p_instance_id)
	scene_instance = p_data.scene.instantiate()
	# 楼层标记打在原 Scene 根上:save_manager 的第一层 group 遍历靠它过滤,
	# 原有 group(offices/desk_slots/desk_seats)全部保留,不破坏原逻辑
	scene_instance.set_meta("floor_id", floor_id)
	scene_instance.set_meta("placed_instance_id", p_instance_id)
	add_child(scene_instance)
	orientation_id = p_data.normalize_orientation_id(&"")
	_configure_scene_orientation()
	z_index = p_data.z_index_offset
	_apply_rotation_visual()


func set_rotation_deg(deg: int) -> void:
	rotation_deg = posmod(deg, 360)
	_apply_rotation_visual()


func set_variant(v: int) -> void:
	variant = v
	if data != null and data.has_orientations():
		var orientation := data.get_orientation_by_index(v)
		if orientation != null:
			set_orientation_id(orientation.orientation_id)
		return
	if scene_instance != null and scene_instance.has_method("set_variant"):
		scene_instance.set_variant(v)


func set_orientation_id(p_orientation_id: StringName) -> void:
	if data == null:
		return
	orientation_id = data.normalize_orientation_id(p_orientation_id)
	var idx := data.get_orientation_index(orientation_id)
	if idx >= 0:
		variant = idx
	_configure_scene_orientation()
	_apply_rotation_visual()


func get_orientation_count() -> int:
	if data != null and data.has_orientations():
		return data.get_orientation_count()
	if scene_instance != null and scene_instance.has_method("get_variant_count"):
		return scene_instance.get_variant_count()
	return 1


# 旋转视觉:绕锚点格左上角转,再平移回正区(与 rotate_offsets 的重锚定一致)
func _apply_rotation_visual() -> void:
	if scene_instance == null or not (scene_instance is Node2D or scene_instance is Control):
		return
	scene_instance.rotation_degrees = rotation_deg if data.allow_transform_rotation else 0
	scene_instance.position = data.get_visual_offset(orientation_id) * -1.0  # 视觉对齐微调
	# 旋转把内容甩到负轴,按角度平移回 [0, footprint) 区间
	var placement_adjust := data.placement_offset if data.has_orientations() else Vector2.ZERO
	scene_instance.position = placement_adjust - data.get_visual_offset(orientation_id)
	if not data.allow_transform_rotation:
		return
	var fp_world := _footprint_world_size()
	match rotation_deg:
		90:
			scene_instance.position += Vector2(fp_world.y, 0)
		180:
			scene_instance.position += Vector2(fp_world.x, fp_world.y)
		270:
			scene_instance.position += Vector2(0, fp_world.x)


# footprint 的世界像素尺寸:由所在楼层的 TileMapLayer 推导(不读 tile_size)
func _footprint_world_size() -> Vector2:
	var floor_node := _get_floor()
	if floor_node == null:
		return Vector2.ZERO
	var cell_world: Vector2 = (floor_node.cell_to_global(Vector2i.ONE)
			- floor_node.cell_to_global(Vector2i.ZERO)).abs()
	return Vector2(data.get_footprint(orientation_id)) * cell_world


func _configure_scene_orientation() -> void:
	if scene_instance == null or data == null:
		return
	if scene_instance.has_method("configure_from_item_data"):
		scene_instance.configure_from_item_data(data, orientation_id)
	elif scene_instance.has_method("set_orientation_id"):
		scene_instance.set_orientation_id(orientation_id)


func _get_floor() -> DecoratableFloor:
	var n := get_parent()
	while n != null:
		if n is DecoratableFloor:
			return n
		n = n.get_parent()
	return null


func to_save_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"item_id": String(item_id),
		"floor_id": int(get_meta("floor_id", 1)),
		"origin_cell": [origin_cell.x, origin_cell.y],
		"orientation_id": String(orientation_id),
		"rotation": rotation_deg,
		"variant": variant,
		"parent_room_id": parent_room_id,
		"local_grid_position": [local_grid_position.x, local_grid_position.y],
		"custom_state": custom_state,
	}


func get_debug_info() -> Dictionary:
	var orientation := data.get_orientation(orientation_id) if data != null else null
	return {
		"item_id": String(item_id),
		"orientation_id": String(orientation_id),
		"atlas_region": orientation.get_region() if orientation != null else Rect2i(),
		"placement_anchor": orientation.placement_anchor if orientation != null else Vector2.ZERO,
		"visual_bounds": Rect2(global_position, orientation.get_visual_size()) if orientation != null else Rect2(),
		"footprint": data.get_footprint(orientation_id) if data != null else Vector2i.ZERO,
		"occupied_cells": get_world_cells(),
		"blocked_cells": data.get_blocked_cells(orientation_id) if data != null else [],
		"interaction_points": data.get_interaction_points(orientation_id) if data != null else [],
		"origin_cell": origin_cell,
		"is_valid": true,
		"illegal_reason": "",
	}
