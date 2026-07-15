class_name PlaceableItemData
extends Resource
# 装修物品数据(数据驱动核心):每一种可放置对象对应一个 .tres 文件,
# 放在 res://data/placeable_items/ 的分类子目录下,由 PlaceableItemDB 启动时自动扫描注册。
# 新增素材 = 新增一个 .tres,不需要改任何装修菜单代码。
#
# 坐标约定:所有 *_cells 均为"相对 anchor_cell 的格偏移"(map 坐标差),
# 不含任何像素值;像素换算一律由楼层的 TileMapLayer 完成。

enum Category { ROOM, DESK, UTILITY, SMALL_DECOR, ZONE_PREFAB, FLOOR_DECOR }
enum PlacementType { GRID }  # 预留:未来可能有贴墙/贴桌等特殊放置方式
enum RenderStyle { SHADOW, SHADOWLESS }

@export_group("基础信息")
@export var item_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.SMALL_DECOR
@export var scene: PackedScene          # 直接实例化的现有 Scene(不做简化副本)
@export var icon: Texture2D
@export var tags: Array[StringName] = []

@export_group("方向变体")
@export var orientations: Array[PlaceableOrientationData] = []
@export var default_orientation_id: StringName = &""
@export var allow_mouse_wheel_rotation: bool = true
@export var use_directional_sprites: bool = true
@export var allow_transform_rotation: bool = false
@export var style_group: StringName = &""
@export var color_variant: StringName = &""
@export var functional_state_ids: Array[StringName] = []
@export var render_style: RenderStyle = RenderStyle.SHADOW

@export_group("放置数据")
# 占地来源优先级:footprint_override(双正)> calculated_footprint(工具估算)> 运行时估算
@export var auto_calculate_footprint: bool = true
@export var footprint_override: Vector2i = Vector2i.ZERO
@export var calculated_footprint: Vector2i = Vector2i.ZERO
@export var anchor_cell: Vector2i = Vector2i.ZERO       # 锚点格(相对 footprint 左上)
@export var occupied_cells: Array[Vector2i] = []        # 空 = 按 footprint 矩形全占
@export var blocked_cells: Array[Vector2i] = []         # 不可穿过(Room 的墙/柱)
@export var buildable_cells: Array[Vector2i] = []       # Room 内部可继续装修的格
@export var interaction_cells: Array[Vector2i] = []     # 互动点(保持可通行)
@export var entrance_cells: Array[Vector2i] = []        # 入口/门口格
@export var placement_offset: Vector2 = Vector2.ZERO    # 视觉对齐微调(场景原点 → 锚点格角)
@export var z_index_offset: int = 0

@export_group("放置规则")
@export var placement_type: PlacementType = PlacementType.GRID
@export var allowed_floor_types: Array[StringName] = [] # 空 = 不限楼层类型
@export var must_be_inside_room: bool = false
@export var can_be_placed_in_open_floor: bool = true
@export var can_rotate: bool = false
@export var allowed_rotations: Array[int] = [0]         # 允许的旋转角(度)
@export var blocks_navigation: bool = true
@export var requires_reachable_entrance: bool = false
@export var allow_multiple_instances: bool = true

@export_group("经营数值(第一版仅存储,逐步生效)")
@export var price: int = 0
@export var sell_price: int = 0
@export var unlock_level: int = 1
@export var comfort_value: float = 0.0
@export var efficiency_value: float = 0.0
@export var beauty_value: float = 0.0
@export var stress_relief_value: float = 0.0
@export var energy_restore_value: float = 0.0
@export var noise_value: float = 0.0


func has_orientations() -> bool:
	return not orientations.is_empty()


func get_orientation_count() -> int:
	return orientations.size()


func get_default_orientation() -> PlaceableOrientationData:
	if orientations.is_empty():
		return null
	if not String(default_orientation_id).is_empty():
		var found := get_orientation(default_orientation_id)
		if found != null:
			return found
	for o in orientations:
		if o != null and o.is_default:
			return o
	return orientations[0]


func get_orientation(orientation_id: StringName) -> PlaceableOrientationData:
	for o in orientations:
		if o != null and o.orientation_id == orientation_id:
			return o
	return null


func get_orientation_by_index(index: int) -> PlaceableOrientationData:
	if orientations.is_empty():
		return null
	return orientations[posmod(index, orientations.size())]


func get_orientation_index(orientation_id: StringName) -> int:
	for i in orientations.size():
		var o := orientations[i]
		if o != null and o.orientation_id == orientation_id:
			return i
	return -1


func normalize_orientation_id(orientation_id: StringName) -> StringName:
	if orientations.is_empty():
		return &""
	if not String(orientation_id).is_empty() and get_orientation(orientation_id) != null:
		return orientation_id
	var d := get_default_orientation()
	if d != null:
		return d.orientation_id
	return orientations[0].orientation_id


# 生效的占地(不含运行时估算兜底;运行时兜底由 DecorationController 调 FootprintEstimator)
func get_footprint(orientation_id: StringName = &"") -> Vector2i:
	var orientation := get_orientation(normalize_orientation_id(orientation_id))
	if orientation != null:
		return orientation.get_footprint()
	if footprint_override.x > 0 and footprint_override.y > 0:
		return footprint_override
	return calculated_footprint


# 占用格列表(相对 anchor):未显式配置时按 footprint 矩形展开
func get_occupied_cells(orientation_id: StringName = &"") -> Array[Vector2i]:
	var orientation := get_orientation(normalize_orientation_id(orientation_id))
	if orientation != null:
		return orientation.get_occupied_cells()
	if not occupied_cells.is_empty():
		return occupied_cells
	var out: Array[Vector2i] = []
	var fp := get_footprint()
	for y in fp.y:
		for x in fp.x:
			out.append(Vector2i(x, y) - anchor_cell)
	return out


func get_blocked_cells(orientation_id: StringName = &"") -> Array[Vector2i]:
	var orientation := get_orientation(normalize_orientation_id(orientation_id))
	if orientation != null:
		return orientation.blocked_cells
	return blocked_cells


func get_interaction_points(orientation_id: StringName = &"") -> Array[Vector2]:
	var orientation := get_orientation(normalize_orientation_id(orientation_id))
	if orientation != null:
		return orientation.interaction_points
	var out: Array[Vector2] = []
	for c in interaction_cells:
		out.append(Vector2(c))
	return out


func get_entrance_cells(orientation_id: StringName = &"") -> Array[Vector2i]:
	var orientation := get_orientation(normalize_orientation_id(orientation_id))
	if orientation != null:
		return orientation.entrance_cells
	return entrance_cells


func get_visual_offset(orientation_id: StringName = &"") -> Vector2:
	var orientation := get_orientation(normalize_orientation_id(orientation_id))
	if orientation != null:
		return orientation.visual_offset + orientation.preview_offset
	return placement_offset


# 数据完整性校验,返回错误列表(空 = 合格)。由 PlaceableItemDB 注册时调用
func validate() -> Array[String]:
	var errors: Array[String] = []
	if String(item_id).is_empty():
		errors.append("item_id 为空")
	if scene == null:
		errors.append("scene 丢失(PackedScene 未设置或路径失效)")
	if has_orientations():
		var ids := {}
		var default_count := 0
		for o in orientations:
			if o == null:
				errors.append("orientations 中存在空条目")
				continue
			if ids.has(o.orientation_id):
				errors.append("orientation_id 重复:%s" % o.orientation_id)
			ids[o.orientation_id] = true
			if o.is_default:
				default_count += 1
			errors.append_array(o.validate())
		if not String(default_orientation_id).is_empty() and not ids.has(default_orientation_id):
			errors.append("default_orientation_id 不存在:%s" % default_orientation_id)
		if default_count == 0 and String(default_orientation_id).is_empty():
			errors.append("有方向数据但未设置默认方向")
		if allow_transform_rotation and use_directional_sprites:
			errors.append("像素方向素材不能同时启用 transform 旋转")
	var fp := get_footprint()
	if not auto_calculate_footprint and (fp.x <= 0 or fp.y <= 0):
		errors.append("footprint 无效:关闭了自动估算但 override/calculated 都不是正数 (%s)" % fp)
	if footprint_override != Vector2i.ZERO and (footprint_override.x <= 0 or footprint_override.y <= 0):
		errors.append("footprint_override 必须 X、Y 都为正才生效,当前 %s" % footprint_override)
	if can_rotate and allowed_rotations.is_empty():
		errors.append("can_rotate 开启但 allowed_rotations 为空")
	if has_orientations() and can_rotate and not allow_transform_rotation:
		errors.append("有方向素材时请用 orientations 切换;若确需节点旋转,显式开启 allow_transform_rotation")
	return errors
