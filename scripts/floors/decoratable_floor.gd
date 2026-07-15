class_name DecoratableFloor
extends Node2D
# 可复用的"可装修楼层"(第二层及未来楼层共用)。
#
# 楼层结构与第一层一致(2026-07-14 拍板):
# - 两端复制第一层的 LeftCover / RightCover(内容一模一样),这些区域不可装饰;
# - 其余部分整片都是 floor,全部可装饰;
# - 地面范围 = 第一层地砖的使用范围,固定结构生成后不可移动、不可编辑。
# 网格基准:不假设 tile 尺寸!通过 setup_from_reference() 直接复用第一层
# FloorTiles 的 TileSet 与全局变换,保证网格与第一层完全一致;
# 所有格子 ↔ 像素换算只走本层 FloorTileMap 的 map_to_local/local_to_map/to_global/to_local。

@export var floor_id: int = 2
# 入口带:紧贴左侧 Cover 的第一列可通行格,标记为入口(可走、不可建造)
@export var entrance_columns: int = 1

@onready var floor_tilemap: TileMapLayer = $FloorTileMap
@onready var wall_tilemap: TileMapLayer = $WallTileMap
@onready var fixed_structure_layer: Node2D = $FixedStructureLayer
@onready var room_layer: Node2D = $RoomLayer
@onready var furniture_layer: Node2D = $FurnitureLayer
@onready var zone_layer: Node2D = $ZoneLayer
@onready var character_layer: Node2D = $CharacterLayer
@onready var effect_layer: Node2D = $EffectLayer
@onready var placement_preview_layer: Node2D = $PlacementPreviewLayer

var occupancy := OccupancyGrid.new()
var entrance_cells: Array[Vector2i] = []
var _shell_built := false

# ---- 已放置物件 / 楼层仓库 ----
var placed_items := {}            # instance_id(String) -> PlacedFloorItem
var inventory := {}               # item_id(String) -> 数量(收入仓库的物品)
var _unknown_saved_items: Array = []  # 存档里 item_id 未知的条目:警告+原样保留,再存档不丢失
var _next_instance_seq := 1


# 由 BuildingManager 调用:以第一层为模板生成本层。
# ref_tilemap = 第一层 FloorTiles(group "floor_tilemap")
# cover_templates = 第一层的 LeftCover / RightCover 等固定覆盖件,原样复制到本层
func setup_from_reference(ref_tilemap: TileMapLayer, cover_templates: Array = []) -> void:
	if _shell_built:
		return
	# 网格与第一层完全一致:复用 TileSet + 全局变换(缩放/偏移以后改了也自动跟随)
	floor_tilemap.tile_set = ref_tilemap.tile_set
	floor_tilemap.global_transform = ref_tilemap.global_transform

	# 地面范围 = 第一层地砖的使用范围(每层楼与一楼同构)
	var shell := ref_tilemap.get_used_rect()
	occupancy.bounds = shell

	# 地砖样式:取第一层当前地板的 source/atlas,保持观感一致
	var sample := ref_tilemap.get_used_cells()
	var src_id := 0
	var atlas := Vector2i.ZERO
	if not sample.is_empty():
		src_id = ref_tilemap.get_cell_source_id(sample[0])
		atlas = ref_tilemap.get_cell_atlas_coords(sample[0])

	# 复制固定覆盖件(内容与一楼一模一样,不可装饰、不可移动)
	var cover_rects: Array[Rect2] = []
	for tpl in cover_templates:
		if tpl is Control:
			cover_rects.append(tpl.get_global_rect())
			var dup: Control = tpl.duplicate()
			# ⚠️ 整棵子树都要鼠标穿透:玻璃幕墙等子 TextureRect 默认 STOP,
			#    透明下沿会盖住楼层顶行、无声吞掉放置点击
			_set_mouse_ignore_recursive(dup)
			fixed_structure_layer.add_child(dup)
			dup.global_position = tpl.global_position
			dup.size = tpl.size

	_build_ground(shell, src_id, atlas, cover_rects)
	_shell_built = true


# 铺地 + 标记占用数据:被 Cover 盖住的格子 = 固定阻挡(不可装饰),
# 紧贴左 Cover 的 entrance_columns 列 = 入口(可走不可建),其余全部可建造
func _build_ground(shell: Rect2i, src_id: int, atlas: Vector2i, cover_rects: Array[Rect2]) -> void:
	entrance_cells.clear()
	# 第一遍:铺地 + 按格心是否落在 Cover 矩形内区分 阻挡/可建造
	for y in range(shell.position.y, shell.end.y):
		for x in range(shell.position.x, shell.end.x):
			var cell := Vector2i(x, y)
			floor_tilemap.set_cell(cell, src_id, atlas)
			var center := cell_to_global(cell)
			var covered := false
			for r in cover_rects:
				if r.has_point(center):
					covered = true
					break
			if covered:
				occupancy.fixed_blocked[cell] = true
			else:
				occupancy.buildable[cell] = true

	# 第二遍:开放区最左侧 entrance_columns 列标记为入口(楼梯/电梯落脚位)
	if entrance_columns <= 0 or occupancy.buildable.is_empty():
		return
	var min_x := shell.end.x
	for cell in occupancy.buildable:
		min_x = mini(min_x, cell.x)
	for cell in occupancy.buildable.keys():
		if cell.x < min_x + entrance_columns:
			occupancy.buildable.erase(cell)
			occupancy.entrance[cell] = true
			entrance_cells.append(cell)


# 半格尺寸从 TileMapLayer 推导(相邻格中心的【世界】距离的一半,含缩放),
# 避免读 tile_size 常量。⚠️ 必须用 to_global:map_to_local 是局部坐标,
# FloorTiles 有 2 倍缩放,直接用会差一半(格子填充出现间隔、放置偏移 16px 的老 bug)
func _half_cell() -> Vector2:
	return (floor_tilemap.to_global(floor_tilemap.map_to_local(Vector2i.ONE))
			- floor_tilemap.to_global(floor_tilemap.map_to_local(Vector2i.ZERO))).abs() / 2.0


# ---- 对外坐标接口:装修/导航/存档全部经由这两个函数换算 ----
func cell_to_global(cell: Vector2i) -> Vector2:
	return floor_tilemap.to_global(floor_tilemap.map_to_local(cell))


func global_to_cell(global_pos: Vector2) -> Vector2i:
	return floor_tilemap.local_to_map(floor_tilemap.to_local(global_pos))


static func _set_mouse_ignore_recursive(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_set_mouse_ignore_recursive(c)


# ---- 放置 / 移除 / 存档(被 DecorationController 调用) ----
func make_instance_id() -> String:
	var id := "placed_%05d" % _next_instance_seq
	while placed_items.has(id):
		_next_instance_seq += 1
		id = "placed_%05d" % _next_instance_seq
	_next_instance_seq += 1
	return id


# 一组世界格当前是否全部可建造(完整合法性检查的核心;返回失败原因供 UI 反馈)
func check_cells(cells: Array[Vector2i]) -> Dictionary:
	for c in cells:
		if not occupancy.is_inside(c):
			return {"ok": false, "reason": "越界"}
		if occupancy.is_fixed_blocked(c):
			return {"ok": false, "reason": "固定结构(Cover)不可建造"}
		if occupancy.is_entrance(c):
			return {"ok": false, "reason": "入口格不可建造"}
		if not occupancy.is_buildable(c):
			var who := occupancy.get_occupant(c)
			return {"ok": false, "reason": "与 %s 重叠" % who if who else "该格不可建造"}
	return {"ok": true, "reason": ""}


# 风险提示(黄色):合法但贴着楼层入口(可能挡住主要通道)
func touches_entrance_neighborhood(cells: Array[Vector2i]) -> bool:
	for c in cells:
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if occupancy.is_entrance(c + d):
				return true
	return false


# 放置(调用方须先 check_cells 通过)。custom_state/instance_id 供读档恢复
func place_item(data: PlaceableItemData, origin_cell: Vector2i, rot_deg := 0,
		variant := 0, p_instance_id := "", p_custom_state := {},
		p_orientation_id: StringName = &"") -> PlacedFloorItem:
	var item := PlacedFloorItem.new()
	var iid := p_instance_id if not p_instance_id.is_empty() else make_instance_id()
	_layer_for_category(data.category).add_child(item)
	item.setup(data, iid, floor_id)
	item.origin_cell = origin_cell
	item.custom_state = p_custom_state
	item.global_position = cell_to_global(origin_cell) - _half_cell()
	item.set_rotation_deg(rot_deg)
	if data.has_orientations():
		var oid := data.normalize_orientation_id(p_orientation_id)
		if String(oid).is_empty():
			var orientation := data.get_orientation_by_index(variant)
			oid = orientation.orientation_id if orientation != null else &""
		item.set_orientation_id(oid)
	else:
		item.set_variant(variant)
	occupancy.occupy(item.get_world_cells(), iid)
	placed_items[iid] = item
	return item


# 移除:to_inventory=true 收入楼层仓库,false 纯移除(出售等,退款由调用方处理)
func remove_item(instance_id: String, to_inventory: bool) -> void:
	var item: PlacedFloorItem = placed_items.get(instance_id, null)
	if item == null:
		return
	occupancy.release(instance_id)
	placed_items.erase(instance_id)
	if to_inventory:
		var key := String(item.item_id)
		inventory[key] = int(inventory.get(key, 0)) + 1
	item.queue_free()


# 移动前"抬起"(释放占用);确认新位置后重新登记
func lift_item(instance_id: String) -> void:
	occupancy.release(instance_id)


func drop_item(item: PlacedFloorItem, origin_cell: Vector2i) -> void:
	item.origin_cell = origin_cell
	item.global_position = cell_to_global(origin_cell) - _half_cell()
	occupancy.occupy(item.get_world_cells(), item.instance_id)


func _layer_for_category(cat: int) -> Node2D:
	match cat:
		PlaceableItemData.Category.ROOM:
			return room_layer
		PlaceableItemData.Category.ZONE_PREFAB:
			return zone_layer
		_:
			return furniture_layer


# ---- 楼层扩展存档(由 BuildingManager 汇总进 building 段) ----
func to_save_dict() -> Dictionary:
	var items := []
	for iid in placed_items:
		items.append(placed_items[iid].to_save_dict())
	# 未知物品原样带回存档,避免因缺素材丢玩家数据
	items.append_array(_unknown_saved_items)
	return {"placed_items": items, "inventory": inventory.duplicate()}


func load_from_dict(data: Dictionary, item_db: PlaceableItemDB) -> void:
	# 清空当前(读档重建)
	for iid in placed_items.keys():
		remove_item(iid, false)
	occupancy.clear_all_occupants()
	_unknown_saved_items.clear()
	inventory = data.get("inventory", {}).duplicate()

	for entry in data.get("placed_items", []):
		var item_id := StringName(str(entry.get("item_id", "")))
		var item_data := item_db.get_item(item_id)
		if item_data == null:
			push_warning("DecoratableFloor:存档物品 \"%s\" 不在数据库中,已跳过(数据保留,不会丢失)" % item_id)
			_unknown_saved_items.append(entry)
			continue
		var oc: Array = entry.get("origin_cell", [0, 0])
		var cell := Vector2i(int(oc[0]), int(oc[1]))
		var saved_orientation := StringName(str(entry.get("orientation_id", "")))
		if item_data.has_orientations() and String(saved_orientation).is_empty():
			var legacy := item_data.get_orientation_by_index(int(entry.get("variant", 0)))
			saved_orientation = legacy.orientation_id if legacy != null else item_data.normalize_orientation_id(&"")
		elif item_data.has_orientations() and item_data.get_orientation(saved_orientation) == null:
			push_warning("DecoratableFloor:存档物品 \"%s\" 的方向 \"%s\" 不存在,已回退默认方向"
					% [item_id, saved_orientation])
			saved_orientation = item_data.normalize_orientation_id(&"")
		var placed := place_item(item_data, cell, int(entry.get("rotation", 0)),
				int(entry.get("variant", 0)),
				str(entry.get("instance_id", "")), entry.get("custom_state", {}),
				saved_orientation)
		placed.parent_room_id = str(entry.get("parent_room_id", ""))
		var lgp: Array = entry.get("local_grid_position", [0, 0])
		placed.local_grid_position = Vector2i(int(lgp[0]), int(lgp[1]))


# ---- 调试视图(占地校对用,见 FloorDebugOverlay) ----
var _debug_overlay: FloorDebugOverlay = null


func enable_debug_view(spawn_samples := true, cell_fills := true) -> FloorDebugOverlay:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		return _debug_overlay
	_debug_overlay = FloorDebugOverlay.new()
	_debug_overlay.name = "FloorDebugOverlay"
	_debug_overlay.floor_node = self
	_debug_overlay.cell_fills = cell_fills
	add_child(_debug_overlay)
	if spawn_samples:
		_debug_overlay.spawn_default_samples()
	return _debug_overlay


func disable_debug_view() -> void:
	if _debug_overlay and is_instance_valid(_debug_overlay):
		# 样例假人挂在 room/furniture 层,一并清掉
		for s in _debug_overlay._samples:
			if is_instance_valid(s.node):
				s.node.queue_free()
		_debug_overlay.queue_free()
	_debug_overlay = null
