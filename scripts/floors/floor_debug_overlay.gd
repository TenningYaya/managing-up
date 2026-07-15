class_name FloorDebugOverlay
extends Node2D
# 装修系统调试视图(运行时叠加在 DecoratableFloor 上):
# - 地面网格线、可建造格(绿)、固定阻挡格(红)、入口格(蓝)
# - 样例物件(Room/DeskSlot)的:视觉边界(黄)、建议 footprint(品红)、
#   SnapPoint(青色十字)、建议入口(白框)
# 用途:在正式确定 PlaceableItemData 的 footprint 前做人工校对(阶段 3 前置)。
# 所有格↔像素换算走 DecoratableFloor 的接口(内部是 TileMapLayer 转换),无硬编码格径。

const COL_GRID := Color(1, 1, 1, 0.25)
const COL_BUILDABLE := Color(0.2, 1.0, 0.3, 0.18)
const COL_BLOCKED := Color(1.0, 0.25, 0.2, 0.30)
const COL_ENTRANCE := Color(0.3, 0.6, 1.0, 0.45)
const COL_VISUAL_BOUNDS := Color(1.0, 0.9, 0.1, 0.9)
const COL_FOOTPRINT := Color(1.0, 0.2, 1.0, 0.65)
const COL_SNAP := Color(0.2, 1.0, 1.0, 1.0)
const COL_SUGGEST_ENTRANCE := Color(1, 1, 1, 0.9)
const COL_INFO := Color(1, 1, 1, 0.95)
const COL_INTERACTION := Color(0.1, 0.8, 1.0, 1.0)

var floor_node: DecoratableFloor = null
# 全场格子状态染色:调试模式 true;装修模式 false(只画网格线,
# 状态反馈由 PlacementPreview 只画在物品脚下)
var cell_fills := true
var _samples: Array = []  # [{node, label}]
var _font: Font = null


func _ready() -> void:
	# top_level:直接用世界(画布)坐标绘制,不受 DecoratableFloor 自身变换影响
	top_level = true
	global_position = Vector2.ZERO
	z_index = 950
	z_as_relative = false
	_font = load("res://assets/fonts/standard.tres")
	queue_redraw()


func _process(_dt: float) -> void:
	# 样例是容器布局的 Control,布局在生成后一两帧才稳定;调试视图常开时每帧重绘,
	# 保证边界/占地标注始终是实时值(纯调试开销,正常游玩不挂本节点)
	if not _samples.is_empty():
		queue_redraw()


# 注册一个样例物件(实例已在场景树里),重绘时计算其边界/占地
func add_sample(node: Node, label: String) -> void:
	_samples.append({"node": node, "label": label})
	queue_redraw()


# 生成默认样例:一间现有 Room + 一组现有 DeskSlot(纯视觉假人:
# 移出存档/交互相关 group、禁掉鼠标,避免污染第一层逻辑与存档)
func spawn_default_samples() -> void:
	if floor_node == null or floor_node.occupancy.buildable.is_empty():
		return
	# 起点 = 可建造区最左列的顶行(入口带右侧)
	var b: Rect2i = floor_node.occupancy.bounds
	var min_x := b.end.x
	for cell in floor_node.occupancy.buildable:
		min_x = mini(min_x, cell.x)
	var origin := Vector2i(min_x, b.position.y)

	var room_scene: PackedScene = load("res://scenes/office/office.tscn")
	if room_scene:
		var room: Control = room_scene.instantiate()
		floor_node.room_layer.add_child(room)
		_neutralize(room)
		_place_at_cell(room, origin + Vector2i(1, 0))
		add_sample(room, "Room(office.tscn)")

	var desk_scene: PackedScene = load("res://scenes/office/DeskSlot.tscn")
	if desk_scene:
		var desk: Control = desk_scene.instantiate()
		floor_node.furniture_layer.add_child(desk)
		_neutralize(desk)
		_place_at_cell(desk, origin + Vector2i(9, 0))
		add_sample(desk, "DeskSlot")


# 把 Control 的左上角对齐到某格的左上角(格中心 - 半格)
func _place_at_cell(ctrl: Control, cell: Vector2i) -> void:
	ctrl.global_position = floor_node.cell_to_global(cell) - floor_node._half_cell()


# 调试假人失活:移出会被存档/交互遍历的 group,并递归禁鼠标
func _neutralize(node: Node) -> void:
	for g in ["offices", "desk_slots", "desk_seats", "office_area", "office_1", "tutorial_office"]:
		if node.is_in_group(g):
			node.remove_from_group(g)
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_neutralize(c)


func _draw() -> void:
	if floor_node == null:
		return
	var occ := floor_node.occupancy
	var half := floor_node._half_cell()

	# 1) 格子状态填充(仅调试模式;装修模式只留网格线)
	if cell_fills:
		for cell in occ.buildable:
			_fill_cell(cell, half, COL_BUILDABLE)
		for cell in occ.fixed_blocked:
			_fill_cell(cell, half, COL_BLOCKED)
		for cell in occ.entrance:
			_fill_cell(cell, half, COL_ENTRANCE)

	# 2) 网格线(覆盖整个外壳)
	var b := occ.bounds
	for x in range(b.position.x, b.end.x + 1):
		var top := _cell_corner(Vector2i(x, b.position.y), half)
		var bottom := _cell_corner(Vector2i(x, b.end.y), half)
		draw_line(top, bottom, COL_GRID, 1.0)
	for y in range(b.position.y, b.end.y + 1):
		var left := _cell_corner(Vector2i(b.position.x, y), half)
		var right := _cell_corner(Vector2i(b.end.x, y), half)
		draw_line(left, right, COL_GRID, 1.0)

	# 3) 样例物件标注
	for s in _samples:
		var node: Node = s.node
		if not is_instance_valid(node):
			continue
		var vis := _visual_bounds(node)
		if vis.size == Vector2.ZERO:
			continue
		# 视觉边界(黄)
		draw_rect(vis, COL_VISUAL_BOUNDS, false, 2.0)
		# 建议 footprint(品红):视觉边界覆盖到的格子取整
		var c0 := floor_node.global_to_cell(vis.position + Vector2.ONE)
		var c1 := floor_node.global_to_cell(vis.end - Vector2.ONE)
		var fp_rect := Rect2(_cell_corner(c0, half), _cell_corner(c1 + Vector2i.ONE, half) - _cell_corner(c0, half))
		draw_rect(fp_rect, COL_FOOTPRINT, false, 3.0)
		var fp_cells := c1 - c0 + Vector2i.ONE
		# 建议入口(白):footprint 底边中部 2 格(Room 没有内建门,此为待人工确认的建议)
		var ent_w := mini(2, fp_cells.x)
		var ent_c0 := Vector2i(c0.x + (fp_cells.x - ent_w) / 2, c1.y)
		var ent_rect := Rect2(_cell_corner(ent_c0, half), _cell_corner(ent_c0 + Vector2i(ent_w, 1), half) - _cell_corner(ent_c0, half))
		draw_rect(ent_rect, COL_SUGGEST_ENTRANCE, false, 2.0)
		# SnapPoint(青十字):工位椅位/互动点
		for sp in node.find_children("SnapPoint", "", true, false):
			if sp is CanvasItem or sp is Control:
				var p: Vector2 = sp.global_position
				draw_line(p + Vector2(-6, 0), p + Vector2(6, 0), COL_SNAP, 2.0)
				draw_line(p + Vector2(0, -6), p + Vector2(0, 6), COL_SNAP, 2.0)
		# 标签:名称 + 视觉尺寸 + 建议占地
		if _font:
			var text := "%s  视觉 %dx%d px  建议占地 %dx%d 格" % [s.label, vis.size.x, vis.size.y, fp_cells.x, fp_cells.y]
			draw_string(_font, vis.position + Vector2(0, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_VISUAL_BOUNDS)

	# 4) 预览/已放置家具的方向数据调试
	var info := _current_placeable_debug_info()
	if not info.is_empty():
		_draw_placeable_info(info, half)


func _fill_cell(cell: Vector2i, half: Vector2, color: Color) -> void:
	var corner := _cell_corner(cell, half)
	draw_rect(Rect2(corner, half * 2.0), color, true)


# 某格左上角的世界坐标(格中心 - 半格;换算走 DecoratableFloor → TileMapLayer)
func _cell_corner(cell: Vector2i, half: Vector2) -> Vector2:
	return floor_node.cell_to_global(cell) - half


# 组合可见 CanvasItem 的世界包围盒(与阶段 3 FootprintEstimator 的"可见内容边界"一致)
func _visual_bounds(node: Node) -> Rect2:
	var acc := Rect2()
	var has := false
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not n.visible:
			continue
		var r := Rect2()
		var valid := false
		if n is TextureRect and n.texture != null:
			r = n.get_global_transform() * Rect2(Vector2.ZERO, n.size)
			valid = true
		elif n is Sprite2D and n.texture != null:
			var sz: Vector2 = n.texture.get_size()
			var local := Rect2(-sz / 2.0 if n.centered else Vector2.ZERO, sz)
			local.position += n.offset
			r = n.get_global_transform() * local
			valid = true
		if valid and r.size != Vector2.ZERO:
			acc = r if not has else acc.merge(r)
			has = true
		for c in n.get_children():
			stack.push_back(c)
	return acc


func _current_placeable_debug_info() -> Dictionary:
	var ctrl := floor_node.get_node_or_null("DecorationController") if floor_node != null else null
	if ctrl != null and ctrl.preview != null and ctrl.preview._active:
		return ctrl.preview.get_debug_info()
	if floor_node != null:
		for iid in floor_node.placed_items:
			var item: PlacedFloorItem = floor_node.placed_items[iid]
			if item != null:
				return item.get_debug_info()
	return {}


func _draw_placeable_info(info: Dictionary, half: Vector2) -> void:
	var origin: Vector2i = info.get("origin_cell", Vector2i.ZERO)
	var base := _cell_corner(origin, half)
	var text := "item_id: %s\norientation_id: %s\nregion: %s\nanchor: %s\nvisual_bounds: %s\nfootprint: %s\noccupied: %s\nblocked: %s\ninteraction: %s\norigin_cell: %s\nvalid: %s%s" % [
		info.get("item_id", ""),
		info.get("orientation_id", ""),
		info.get("atlas_region", Rect2i()),
		info.get("placement_anchor", Vector2.ZERO),
		info.get("visual_bounds", Rect2()),
		info.get("footprint", Vector2i.ZERO),
		info.get("occupied_cells", []),
		info.get("blocked_cells", []),
		info.get("interaction_points", []),
		origin,
		str(info.get("is_valid", false)),
		" reason: %s" % info.get("illegal_reason", "") if not bool(info.get("is_valid", false)) else "",
	]
	if _font:
		var pos := base + Vector2(0, -132)
		for line in text.split("\n"):
			draw_string(_font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_INFO)
			pos.y += 15
	for p in info.get("interaction_points", []):
		var wp := base + Vector2(p)
		draw_circle(wp, 5.0, COL_INTERACTION)
		draw_line(wp + Vector2(-8, 0), wp + Vector2(8, 0), COL_INTERACTION, 2.0)
		draw_line(wp + Vector2(0, -8), wp + Vector2(0, 8), COL_INTERACTION, 2.0)
