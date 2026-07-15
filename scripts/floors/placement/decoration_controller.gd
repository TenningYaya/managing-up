class_name DecorationController
extends Node
# 装修模式控制器(每个 DecoratableFloor 一个,挂在其场景里):
#   OFF     未进入装修
#   BROWSE  装修中,未选中任何东西(可点已放置物件拿起)
#   PLACING 从菜单选了新物品,半透明预览跟随鼠标
#   MOVING  拿起了已放置物件,跟随鼠标重新摆放
#
# 操作:左键 确认放置/拿起;右键 取消当前操作;R 旋转(数据允许时);
#       Delete 收入仓库;X 出售;Esc 逐级取消直至退出装修模式。
# 第一层没有 DecorationController,天然进不了装修模式。

enum Mode { OFF, BROWSE, PLACING, MOVING }

signal mode_changed(active: bool)

const LIFTED_TINT := Color(1, 1, 1, 0.55)

var floor_node: DecoratableFloor = null
var preview: PlacementPreview = null
var mode: int = Mode.OFF

var _current_data: PlaceableItemData = null   # PLACING 中的物品数据
var _current_rot := 0
var _current_variant := 0                     # 朝向/花色变体,滚轮切换
var _current_orientation_id: StringName = &""
var _moving_item: PlacedFloorItem = null      # MOVING 中被拿起的物件
var _moving_from_cell := Vector2i.ZERO
var _moving_from_rot := 0
var _moving_from_variant := 0
var _moving_from_orientation_id: StringName = &""
var _menu: Control = null                     # DecorationMenu(懒创建,挂共享 UI 层)
var _estimating := false                      # 防止估算期间重复选择


func _ready() -> void:
	floor_node = get_parent() as DecoratableFloor
	set_process(false)


func is_active() -> bool:
	return mode != Mode.OFF


# ---- 模式开关 ----
func enter_edit_mode() -> void:
	if is_active() or floor_node == null:
		return
	mode = Mode.BROWSE
	# 装修模式只画网格线;格子状态反馈由 PlacementPreview 只画在物品脚下
	floor_node.enable_debug_view(false, false)
	if preview == null:
		preview = PlacementPreview.new()
		preview.floor_node = floor_node
		floor_node.placement_preview_layer.add_child(preview)
	_ensure_menu()
	_menu.open_menu()
	set_process(true)
	mode_changed.emit(true)


func exit_edit_mode() -> void:
	if not is_active():
		return
	_cancel_current()          # 手里有东西先放回去/取消
	preview.clear()
	if _menu:
		_menu.close_menu()
	floor_node.disable_debug_view()
	mode = Mode.OFF
	set_process(false)
	mode_changed.emit(false)


# ---- 菜单回调:选择新物品进入放置 ----
func select_item_for_placement(data: PlaceableItemData) -> void:
	if not is_active() or _estimating:
		return
	_cancel_current()
	# 占地兜底:数据没有确认值时运行时估算一次(结果只驻留内存,不落盘)
	if data.get_footprint() == Vector2i.ZERO:
		if not data.auto_calculate_footprint:
			_hint("「%s」没有可用的占地数据" % data.display_name)
			return
		_estimating = true
		_hint("正在估算占地……")
		var est: Dictionary = await FootprintEstimator.estimate_scene(
				data.scene, floor_node.floor_tilemap, floor_node)
		_estimating = false
		if est.footprint.x <= 0 or est.footprint.y <= 0:
			_hint("「%s」占地估算失败,请在数据里设置 footprint_override" % data.display_name)
			return
		data.calculated_footprint = est.footprint
		data.placement_offset = est.placement_offset
	_current_data = data
	_current_rot = 0
	_current_orientation_id = data.normalize_orientation_id(&"")
	_current_variant = maxi(0, data.get_orientation_index(_current_orientation_id)) if data.has_orientations() else 0
	mode = Mode.PLACING
	preview.begin(data, true, _current_orientation_id)
	var extras := ""
	if _get_orientation_count() > 1:
		extras += " / 滚轮换方向"
	if data.can_rotate and data.allow_transform_rotation:
		extras += " / R 旋转"
	_hint("左键放置 / 右键取消" + extras)


# ---- 每帧:预览跟随鼠标 ----
func _process(_dt: float) -> void:
	if mode != Mode.PLACING and mode != Mode.MOVING:
		return
	var cell := _mouse_cell()
	var cells := _cells_at(cell)
	var status := _evaluate(cells)
	preview.update_preview(cell, cells, status)
	if mode == Mode.MOVING and is_instance_valid(_moving_item):
		_moving_item.global_position = floor_node.cell_to_global(cell) - floor_node._half_cell()


# ---- 输入 ----
# 右键取消要随处生效(包括鼠标悬在装修菜单上时),放 _input 抢在 GUI 之前;
# 左键仍走 _unhandled_input,保证菜单按钮点击优先
func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		if mode == Mode.PLACING or mode == Mode.MOVING:
			_cancel_current()
			_hint("已取消")
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			match mode:
				Mode.PLACING:
					_confirm_place()
				Mode.MOVING:
					_confirm_move()
				Mode.BROWSE:
					_try_pick_up()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _cycle_variant(1):
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _cycle_variant(-1):
				get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_rotate_current()
			KEY_DELETE:
				_store_current()
			KEY_X:
				_sell_current()
			KEY_ESCAPE:
				if mode == Mode.PLACING or mode == Mode.MOVING:
					_cancel_current()
				else:
					exit_edit_mode()
				get_viewport().set_input_as_handled()


# ---- 放置 ----
func _confirm_place() -> void:
	var cell := _mouse_cell()
	var cells := _cells_at(cell)
	# 确认前重新做完整合法性检查,不依赖预览帧的结果
	var check := floor_node.check_cells(cells)
	if not check.ok:
		_float_hint("不能放这里:%s" % check.reason)
		return
	# 结算:仓库有存货优先取用,否则花钱购买
	var key := String(_current_data.item_id)
	var owned := int(floor_node.inventory.get(key, 0))
	if owned > 0:
		floor_node.inventory[key] = owned - 1
	elif _current_data.price > 0:
		if not Gamemanager.spend_kpi(_current_data.price):
			_float_hint("KPI 不足(需要 %d KPI)" % _current_data.price)
			return
	floor_node.place_item(_current_data, cell, _current_rot, _current_variant, "", {}, _current_orientation_id)
	_refresh_menu()
	# 停留在放置模式方便连放,右键/Esc 结束


# ---- 拿起 / 移动 ----
func _try_pick_up() -> void:
	var cell := _mouse_cell()
	var iid := floor_node.occupancy.get_occupant(cell)
	if iid.is_empty():
		return
	var item: PlacedFloorItem = floor_node.placed_items.get(iid, null)
	if item == null:
		return
	_moving_item = item
	_moving_from_cell = item.origin_cell
	_moving_from_rot = item.rotation_deg
	_moving_from_variant = item.variant
	_moving_from_orientation_id = item.orientation_id
	_current_data = item.data
	_current_rot = item.rotation_deg
	_current_variant = item.variant
	_current_orientation_id = item.orientation_id
	floor_node.lift_item(iid)
	item.modulate = LIFTED_TINT
	mode = Mode.MOVING
	preview.begin(item.data, false, _current_orientation_id)  # 移动直接挪原件,不再造幽灵
	var extras := ""
	if _get_orientation_count() > 1:
		extras += " / 滚轮换方向"
	if item.data.can_rotate and item.data.allow_transform_rotation:
		extras += " / R 旋转"
	_hint("左键放下 / 右键放回原位 / Delete 入库 / X 出售" + extras)


func _confirm_move() -> void:
	var cell := _mouse_cell()
	var check := floor_node.check_cells(_cells_at(cell))
	if not check.ok:
		_float_hint("不能放这里:%s" % check.reason)
		return
	_moving_item.set_rotation_deg(_current_rot)
	_moving_item.set_orientation_id(_current_orientation_id)
	floor_node.drop_item(_moving_item, cell)
	_moving_item.modulate = Color.WHITE
	_finish_op()


func _store_current() -> void:
	if mode != Mode.MOVING or not is_instance_valid(_moving_item):
		return
	floor_node.remove_item(_moving_item.instance_id, true)
	_moving_item = null
	_hint("已收入仓库")
	_finish_op()
	_refresh_menu()


func _sell_current() -> void:
	if mode != Mode.MOVING or not is_instance_valid(_moving_item):
		return
	Gamemanager.add_kpi(_moving_item.data.sell_price)
	_hint("已出售 +%d KPI" % _moving_item.data.sell_price)
	floor_node.remove_item(_moving_item.instance_id, false)
	_moving_item = null
	_finish_op()
	_refresh_menu()


# 滚轮切换朝向/花色变体(同一物件的不同方向在菜单里只占一个选项)。
# 返回是否消费了这次滚轮(没变体时放行,让滚轮继续做别的事)
func _cycle_variant(dir: int) -> bool:
	if mode != Mode.PLACING and mode != Mode.MOVING:
		return false
	if _is_mouse_over_menu():
		return false
	var count := _get_orientation_count()
	if count <= 1:
		return false
	_current_variant = posmod(_current_variant + dir, count)
	if _current_data != null and _current_data.has_orientations():
		var orientation := _current_data.get_orientation_by_index(_current_variant)
		_current_orientation_id = orientation.orientation_id if orientation != null else &""
	if mode == Mode.PLACING:
		if _current_data != null and _current_data.has_orientations():
			preview.set_orientation_id(_current_orientation_id)
		else:
			preview.set_variant(_current_variant)
	else:
		if _current_data != null and _current_data.has_orientations():
			_moving_item.set_orientation_id(_current_orientation_id)
		else:
			_moving_item.set_variant(_current_variant)
	return true


func _rotate_current() -> void:
	if _current_data == null or not _current_data.can_rotate:
		if _get_orientation_count() > 1:
			_cycle_variant(1)
		return
	if not _current_data.allow_transform_rotation:
		if _get_orientation_count() > 1:
			_cycle_variant(1)
		return
	var rots := _current_data.allowed_rotations
	if rots.is_empty():
		return
	var idx := rots.find(_current_rot)
	_current_rot = rots[(idx + 1) % rots.size()]
	if mode == Mode.MOVING and is_instance_valid(_moving_item):
		_moving_item.set_rotation_deg(_current_rot)


# 取消当前操作:MOVING 放回原位(含朝向),PLACING 丢弃选择;回到 BROWSE
func _cancel_current() -> void:
	if mode == Mode.MOVING and is_instance_valid(_moving_item):
		_moving_item.set_rotation_deg(_moving_from_rot)
		_moving_item.set_variant(_moving_from_variant)
		_moving_item.set_orientation_id(_moving_from_orientation_id)
		floor_node.drop_item(_moving_item, _moving_from_cell)
		_moving_item.modulate = Color.WHITE
	_moving_item = null
	if mode == Mode.PLACING or mode == Mode.MOVING:
		_finish_op()


func _finish_op() -> void:
	_current_data = null
	_current_orientation_id = &""
	_moving_item = null
	preview.clear()
	if is_active():
		mode = Mode.BROWSE


# ---- 工具 ----
func _mouse_cell() -> Vector2i:
	return floor_node.global_to_cell(floor_node.floor_tilemap.get_global_mouse_position())


func _cells_at(origin_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _current_data == null:
		return out
	var offsets := PlacedFloorItem.rotate_offsets(
			_current_data.get_occupied_cells(_current_orientation_id),
			_current_data.get_footprint(_current_orientation_id),
			_current_rot if _current_data.allow_transform_rotation else 0)
	for c in offsets:
		out.append(origin_cell + c)
	return out


func _get_orientation_count() -> int:
	if _current_data != null and _current_data.has_orientations():
		return _current_data.get_orientation_count() if _current_data.allow_mouse_wheel_rotation else 1
	if mode == Mode.PLACING and preview != null:
		return preview.get_variant_count()
	if mode == Mode.MOVING and is_instance_valid(_moving_item):
		return _moving_item.get_orientation_count()
	return 1


func _is_mouse_over_menu() -> bool:
	if _menu == null or not is_instance_valid(_menu) or not _menu.visible:
		return false
	return _menu.get_global_rect().has_point(_menu.get_global_mouse_position())


func _evaluate(cells: Array[Vector2i]) -> int:
	if cells.is_empty():
		return PlacementPreview.Status.BAD
	if not floor_node.check_cells(cells).ok:
		return PlacementPreview.Status.BAD
	if floor_node.touches_entrance_neighborhood(cells):
		return PlacementPreview.Status.WARN
	return PlacementPreview.Status.OK


func _ensure_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		return
	var bm := get_tree().get_first_node_in_group("building_manager")
	var ui_layer: Node = bm.get_ui_layer() if bm else null
	_menu = DecorationMenu.new()
	_menu.setup(self, bm.get_item_db() if bm else null, floor_node)
	if ui_layer:
		ui_layer.add_child(_menu)
	else:
		push_error("DecorationController:找不到共享 UI 层,装修菜单挂到楼层节点上")
		floor_node.add_child(_menu)


func _refresh_menu() -> void:
	if _menu and is_instance_valid(_menu):
		_menu.refresh()


func _hint(text: String) -> void:
	if _menu and is_instance_valid(_menu):
		_menu.show_hint(text)


# 放置/移动失败的提示直接漂在鼠标位置,菜单角落的提示条太容易漏看
func _float_hint(text: String) -> void:
	_hint(text)
	var label := Label.new()
	var font := load("res://assets/fonts/standard.tres")
	if font:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.text = text
	label.z_index = 980
	floor_node.placement_preview_layer.add_child(label)
	label.global_position = floor_node.floor_tilemap.get_global_mouse_position() + Vector2(12, -28)
	var tw := label.create_tween()
	tw.tween_property(label, "position:y", label.position.y - 30.0, 1.2)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tw.tween_callback(label.queue_free)
