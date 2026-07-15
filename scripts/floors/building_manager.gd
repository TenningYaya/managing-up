class_name BuildingManager
extends Node
# 楼层管理器:注册楼层、切换显示、解锁条件、楼层存档段。
#
# 按设计定位为 Main 的子节点(非 autoload):楼层都活在 main.tscn 里,
# 普通节点更好配合新游戏/读档/重置。外部通过 group "building_manager" 查找。
#
# 职责边界:
# - 只做"显示/隐藏"级别的楼层切换,不干涉第一层内部经营逻辑;
#   隐藏楼层的 _process 照常运行(Godot 隐藏不停帧),挂机收益天然继续。
# - 第一层(FullGameMode 内容)是包装引用,绝不重构其内部结构。
# - 装修/摆放逻辑属于 DecorationController(阶段 4),不在本类。

signal floor_changed(floor_id: int)
signal floor_unlocked(floor_id: int)
signal decoration_mode_changed(active: bool)

# ---- 第二层解锁统一配置(不要散落到别的脚本里) ----
@export var second_floor_unlock_level: int = 5
@export var second_floor_unlock_cost: int = 0
@export var debug_unlock_second_floor: bool = false  # 调试:直接解锁 2F

# 第一层的视觉节点(只切 visible,不动内部)。相对本节点的路径
@export var floor1_visual_paths: Array[NodePath] = []
# 第一层的固定覆盖件(LeftCover/RightCover):每个新楼层都会原样复制一份,
# 覆盖区域不可装饰。相对本节点的路径
@export var floor_cover_paths: Array[NodePath] = []
# 第二层实例挂到哪个节点下(挂 FullGameMode 下,便签模式的整体显隐自动生效)
@export var floor_parent_path: NodePath
@export var decoratable_floor_scene: PackedScene
# 共享 UI 层(装修菜单等挂这里,随便签模式一起显隐)
@export var ui_layer_path: NodePath

var current_floor_id: int = 1
var _floors := {}  # floor_id -> {"label": String, "visuals": Array, "floor_node": DecoratableFloor 或 null}
var _second_floor_unlocked := false
var _floor_input_snapshots := {}  # floor_id -> instance_id -> prior input state

# 装修物品数据库(启动自动扫描 res://data/placeable_items/,详见 PlaceableItemDB)
var item_db := PlaceableItemDB.new()


func get_item_db() -> PlaceableItemDB:
	return item_db


func get_ui_layer() -> Node:
	return get_node_or_null(ui_layer_path)


# 当前楼层的装修控制器(不可装修楼层返回 null → 第一层永远进不了装修)
func _lift_currency_boards_to_ui_layer() -> void:
	var ui_layer := get_ui_layer()
	if ui_layer == null:
		return
	for board in get_tree().get_nodes_in_group("currency_board"):
		if not is_instance_valid(board) or board.get_parent() == ui_layer:
			continue
		var old_global := Vector2.ZERO
		if board is Control:
			old_global = (board as Control).global_position
		elif board is Node2D:
			old_global = (board as Node2D).global_position
		board.get_parent().remove_child(board)
		ui_layer.add_child(board)
		if board is Control:
			(board as Control).global_position = old_global
		elif board is Node2D:
			(board as Node2D).global_position = old_global


func get_decoration_controller(floor_id: int = -1) -> DecorationController:
	var f := get_floor_node(current_floor_id if floor_id < 0 else floor_id)
	if f == null:
		return null
	return f.get_node_or_null("DecorationController") as DecorationController


func is_decoration_active() -> bool:
	var ctrl := get_decoration_controller()
	return ctrl != null and ctrl.is_active()


func toggle_decoration_mode() -> void:
	var ctrl := get_decoration_controller()
	if ctrl == null:
		return
	if ctrl.is_active():
		ctrl.exit_edit_mode()
	else:
		ctrl.enter_edit_mode()


func _ready() -> void:
	add_to_group("building_manager")
	var item_count := item_db.scan()
	print("[BuildingManager] 装修物品数据库:注册 %d 件" % item_count)

	# 注册第一层:包装现有节点(Background/employees/WalkPoints),不进装修系统
	var visuals: Array = []
	for p in floor1_visual_paths:
		var n := get_node_or_null(p)
		if n == null:
			push_error("BuildingManager:第一层视觉节点路径无效:%s" % p)
		else:
			visuals.append(n)
	_floors[1] = {"label": "1F", "visuals": visuals, "floor_node": null}
	_lift_currency_boards_to_ui_layer()

	# 监听等级变化驱动 2F 解锁
	if Gamemanager.has_signal("level_changed"):
		Gamemanager.level_changed.connect(_on_level_changed)

	# 第二层延迟创建:等第一层地面 TileMapLayer 就绪后以它为网格基准
	call_deferred("_create_second_floor")

	# 自动化测试钩子(正常游玩不带参数,零影响):
	#   --test-floor-switch       无头冒烟测试(切换/挂机/坐标往返)
	#   --test-floor-screenshots  带窗口跑一遍并截图(1F/2F/调试视图/切回/便签模式)
	#   --floor-debug             正常游玩 + 常驻 2F 占地调试视图
	var user_args := OS.get_cmdline_user_args()
	if "--test-floor-switch" in user_args:
		_run_self_test.call_deferred()
	if "--test-floor-screenshots" in user_args:
		_run_screenshot_test.call_deferred()
	if "--floor-debug" in user_args:
		_enable_floor_debug.call_deferred()
	if "--test-floor-click" in user_args:
		_run_click_diagnosis.call_deferred()
	if "--test-item-db" in user_args:
		_run_item_db_test.call_deferred()
	if "--test-placement" in user_args:
		_run_placement_test.call_deferred()
	if "--test-placement-click" in user_args:
		_run_placement_click_test.call_deferred()


func _create_second_floor() -> void:
	if decoratable_floor_scene == null:
		push_error("BuildingManager:未配置 decoratable_floor_scene")
		return
	var parent := get_node_or_null(floor_parent_path)
	if parent == null:
		push_error("BuildingManager:floor_parent_path 无效,第二层无法挂载")
		return
	var ref_tilemap := _find_reference_tilemap()
	if ref_tilemap == null:
		push_error("BuildingManager:找不到第一层地面 TileMapLayer(group floor_tilemap)")
		return

	var covers: Array = []
	for p in floor_cover_paths:
		var c := get_node_or_null(p)
		if c == null:
			push_error("BuildingManager:固定覆盖件路径无效:%s" % p)
		else:
			covers.append(c)

	var floor_node: DecoratableFloor = decoratable_floor_scene.instantiate()
	floor_node.name = "Floor2Decoratable"
	floor_node.floor_id = 2
	floor_node.visible = false
	parent.add_child(floor_node)
	floor_node.setup_from_reference(ref_tilemap, covers)
	_floors[2] = {"label": "2F", "visuals": [floor_node], "floor_node": floor_node}
	_apply_floor_visibility_and_input(2, current_floor_id == 2)

	# 装修模式状态向外转发(楼层切换 UI 据此刷新按钮)
	var ctrl := get_decoration_controller(2)
	if ctrl:
		ctrl.mode_changed.connect(func(active): decoration_mode_changed.emit(active))

	# 读档数据比楼层创建先到:此刻回放
	if _pending_floor_saves.has(2):
		floor_node.load_from_dict(_pending_floor_saves[2], item_db)
		_pending_floor_saves.erase(2)

	floor_changed.emit(current_floor_id)  # 通知 UI 重建按钮列表


# 第一层地面 TileMapLayer:网格与坐标换算的唯一基准
func _find_reference_tilemap() -> TileMapLayer:
	for n in get_tree().get_nodes_in_group("floor_tilemap"):
		if n is TileMapLayer:
			return n
	return null


# ---- 楼层切换 ----
func get_floor_ids() -> Array:
	var ids := _floors.keys()
	ids.sort()
	return ids


func get_floor_label(floor_id: int) -> String:
	return _floors.get(floor_id, {}).get("label", "%dF" % floor_id)


func get_floor_node(floor_id: int) -> DecoratableFloor:
	return _floors.get(floor_id, {}).get("floor_node", null)


func is_floor_decoratable(floor_id: int) -> bool:
	# 第一层永远不可装修;可装修 = 挂了 DecoratableFloor 的楼层
	return get_floor_node(floor_id) != null


func switch_floor(floor_id: int) -> bool:
	if not _floors.has(floor_id):
		return false
	if not is_floor_unlocked(floor_id):
		return false
	if floor_id == current_floor_id:
		return true
	# 离开楼层前先退出装修模式(手里的东西会放回原位)
	var prev_ctrl := get_decoration_controller()
	if prev_ctrl and prev_ctrl.is_active():
		prev_ctrl.exit_edit_mode()
	var prev_floor_id := current_floor_id
	current_floor_id = floor_id
	# 只切 visible:隐藏楼层的 _process/KPI 结算照常运行
	for fid in _floors:
		var show: bool = fid == floor_id
		_apply_floor_visibility_and_input(int(fid), show)
	# 升天幽灵(开除动画)挂在 Main 根上,不在第一层包装节点下,切层时一并显隐。
	# 目前所有员工都属于 1F;阶段 6 引入 2F 员工后改为按 floor_id 判断
	for g in get_tree().get_nodes_in_group("fire_ascend"):
		if g is CanvasItem:
			g.visible = floor_id == 1
	_apply_camera_focus(prev_floor_id, floor_id)
	floor_changed.emit(floor_id)
	return true


# 切层时相机聚焦:记住离开楼层的视角,新楼层有记录则恢复,
# 首次进入可装修楼层则对准其外壳中心(坐标经 DecoratableFloor → TileMapLayer 换算)
func _apply_floor_visibility_and_input(floor_id: int, show: bool) -> void:
	if not _floors.has(floor_id):
		return
	for n in _floors[floor_id].visuals:
		if not is_instance_valid(n):
			continue
		if n is CanvasItem:
			n.visible = show
		if show:
			_restore_floor_input_node(n, floor_id)
		else:
			_disable_floor_input_node(n, floor_id)


func _floor_input_snapshot(floor_id: int) -> Dictionary:
	if not _floor_input_snapshots.has(floor_id):
		_floor_input_snapshots[floor_id] = {}
	return _floor_input_snapshots[floor_id]


func _disable_floor_input_node(node: Node, floor_id: int) -> void:
	var snap := _floor_input_snapshot(floor_id)
	var id := node.get_instance_id()
	if not snap.has(id):
		var state := {
			"process_input": node.is_processing_input(),
			"process_unhandled_input": node.is_processing_unhandled_input(),
		}
		if node is Control:
			state["mouse_filter"] = (node as Control).mouse_filter
		snap[id] = state

	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	for child in node.get_children():
		_disable_floor_input_node(child, floor_id)


func _restore_floor_input_node(node: Node, floor_id: int) -> void:
	var snap := _floor_input_snapshot(floor_id)
	var id := node.get_instance_id()
	if snap.has(id):
		var state: Dictionary = snap[id]
		node.set_process_input(bool(state.get("process_input", false)))
		node.set_process_unhandled_input(bool(state.get("process_unhandled_input", false)))
		if node is Control and state.has("mouse_filter"):
			(node as Control).mouse_filter = int(state["mouse_filter"])
		snap.erase(id)

	for child in node.get_children():
		_restore_floor_input_node(child, floor_id)


func _floor_has_enabled_input(floor_id: int) -> bool:
	if not _floors.has(floor_id):
		return false
	for n in _floors[floor_id].visuals:
		if is_instance_valid(n) and _node_has_enabled_input(n):
			return true
	return false


func _node_has_enabled_input(node: Node) -> bool:
	if node.is_processing_input() or node.is_processing_unhandled_input():
		return true
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return true
	for child in node.get_children():
		if _node_has_enabled_input(child):
			return true
	return false


var _saved_camera_x := {}  # floor_id -> camera.position.x

func _apply_camera_focus(prev_id: int, new_id: int) -> void:
	var cam := get_tree().get_first_node_in_group("main_camera") as Camera2D
	if cam == null:
		return
	_saved_camera_x[prev_id] = cam.position.x
	if _saved_camera_x.has(new_id):
		cam.position.x = _saved_camera_x[new_id]
		return
	var f := get_floor_node(new_id)
	if f != null:
		var b: Rect2i = f.occupancy.bounds
		cam.position.x = f.cell_to_global(b.position + b.size / 2).x


# ---- 解锁 ----
func is_floor_unlocked(floor_id: int) -> bool:
	if floor_id == 1:
		return true
	if floor_id == 2:
		# 实时判定等级,不依赖 level_changed 的触发时序;
		# _second_floor_unlocked 只作为"曾经达成"的持久化记录(为将来解锁花费预留)
		return _second_floor_unlocked or debug_unlock_second_floor \
				or Gamemanager.player_level >= second_floor_unlock_level
	return false


func get_unlock_hint(floor_id: int) -> String:
	if floor_id == 2 and not is_floor_unlocked(2):
		return "达到 %d 级解锁" % second_floor_unlock_level
	return ""


func _on_level_changed(new_level: int) -> void:
	if not _second_floor_unlocked and new_level >= second_floor_unlock_level:
		_second_floor_unlocked = true
		floor_unlocked.emit(2)


# ---- 存档(由 SaveManager 调用,独立段,不碰第一层旧字段) ----
var _pending_floor_saves := {}  # floor_id -> 楼层存档数据(楼层还没建好时暂存)

func to_save_dict() -> Dictionary:
	var floors_data := {}
	for fid in _floors:
		var f := get_floor_node(fid)
		if f != null:
			floors_data[str(fid)] = f.to_save_dict()
	# 楼层还没建好时(极早期存档),把暂存数据原样带回,避免丢失
	for fid in _pending_floor_saves:
		if not floors_data.has(str(fid)):
			floors_data[str(fid)] = _pending_floor_saves[fid]
	return {
		"current_floor_id": current_floor_id,
		"second_floor_unlocked": _second_floor_unlocked,
		"floors": floors_data,
	}


func load_from_dict(data: Dictionary) -> void:
	# 用"或"合并:读档顺序是先恢复等级(可能已触发解锁)再到本段,
	# 老档没有 building 字段时不能把刚达成的解锁盖回 false
	_second_floor_unlocked = _second_floor_unlocked or bool(data.get("second_floor_unlocked", false))

	# 各楼层的装修数据:楼层已建好直接回放,否则暂存等 _create_second_floor 回放
	var floors_data: Dictionary = data.get("floors", {})
	for key in floors_data:
		var fid := int(key)
		var f := get_floor_node(fid)
		if f != null:
			f.load_from_dict(floors_data[key], item_db)
		else:
			_pending_floor_saves[fid] = floors_data[key]

	var target := int(data.get("current_floor_id", 1))
	if target != current_floor_id:
		# 第二层是 call_deferred 创建的,读档时可能还没注册,延迟一帧再切
		if _floors.has(target):
			switch_floor(target)
		else:
			_switch_when_ready(target)


func _switch_when_ready(target: int) -> void:
	await get_tree().process_frame
	if _floors.has(target):
		switch_floor(target)


# ---- 冒烟测试(--test-floor-switch 时运行,打印 PASS/FAIL 供 CI/无头验证) ----
func _run_self_test() -> void:
	await get_tree().process_frame  # 等 _create_second_floor 完成
	var t := func(cond: bool, msg: String):
		print("[FloorTest] %s %s" % ["PASS" if cond else "FAIL", msg])

	t.call(_floors.has(1) and _floors.has(2), "1F/2F 均已注册")
	var f2 := get_floor_node(2)
	t.call(f2 != null and not f2.visible, "初始在 1F,2F 隐藏")
	if f2:
		var b := f2.occupancy.bounds
		print("[FloorTest] 2F 地面 %dx%d 格(origin %s),可建造格 %d,Cover 阻挡格 %d,入口格 %d" % [
			b.size.x, b.size.y, b.position,
			f2.occupancy.buildable.size(), f2.occupancy.fixed_blocked.size(), f2.occupancy.entrance.size()])
	t.call(f2 != null and not f2.occupancy.buildable.is_empty(), "2F 外壳已生成(可建造格 %d 个)" % (f2.occupancy.buildable.size() if f2 else 0))
	t.call(f2 != null and not f2.entrance_cells.is_empty(), "2F 电梯口已生成")
	# 解锁是实时按等级判定的,验证"拒绝"要临时抬高解锁线
	var saved_req := second_floor_unlock_level
	var saved_flag := _second_floor_unlocked
	var saved_dbg := debug_unlock_second_floor
	second_floor_unlock_level = 999
	_second_floor_unlocked = false
	debug_unlock_second_floor = false
	t.call(not switch_floor(2), "未解锁时拒绝切到 2F")
	second_floor_unlock_level = saved_req
	_second_floor_unlocked = saved_flag
	debug_unlock_second_floor = saved_dbg

	debug_unlock_second_floor = true
	t.call(switch_floor(2) and current_floor_id == 2, "解锁后可切到 2F")
	var f1_visuals: Array = _floors[1].visuals
	var f1_hidden := true
	for n in f1_visuals:
		if is_instance_valid(n) and n.visible:
			f1_hidden = false
	t.call(not _floor_has_enabled_input(1), "2F active blocks 1F input")
	t.call(f1_hidden and f2.visible, "切 2F 后:1F 视觉隐藏、2F 显示")

	# 挂机验证:隐藏的第一层 KPI 计时仍在跑(员工 _process 不受 visible 影响)
	var kpi_before: float = Gamemanager.total_time
	await get_tree().create_timer(0.5).timeout
	t.call(Gamemanager.total_time > kpi_before, "1F 隐藏期间全局计时/挂机仍运行")

	t.call(switch_floor(1) and current_floor_id == 1, "可切回 1F")
	var f1_shown := true
	for n in f1_visuals:
		if is_instance_valid(n) and not n.visible:
			f1_shown = false
	t.call(not _floor_has_enabled_input(2), "1F active blocks 2F input")
	t.call(f1_shown and not f2.visible, "切回后:1F 显示、2F 隐藏")

	# 网格换算往返一致性(全部走 TileMapLayer,无硬编码格径)
	if f2:
		var probe: Vector2i = f2.occupancy.bounds.position + Vector2i(2, 2)
		var back := f2.global_to_cell(f2.cell_to_global(probe))
		t.call(back == probe, "格↔像素换算往返一致 (%s → %s)" % [probe, back])
	print("[FloorTest] done")
	get_tree().quit()  # 仅测试模式会走到这里


# ---- 截图测试(--test-floor-screenshots,需带窗口运行) ----
# 输出到项目 test_screenshots/,供人工核对切层显隐效果,跑完自动退出
func _run_screenshot_test() -> void:
	var dir := ProjectSettings.globalize_path("res://test_screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	# 等读档/布局/员工落位稳定再拍
	await get_tree().create_timer(2.0).timeout
	await _capture(dir + "/1_floor1_initial.png")

	debug_unlock_second_floor = true
	switch_floor(2)
	await get_tree().create_timer(0.3).timeout
	await _capture(dir + "/2_floor2.png")

	# 2F 占地调试视图(网格/样例 Room+DeskSlot 的边界与建议占地)
	var f2 := get_floor_node(2)
	if f2:
		f2.enable_debug_view(true)
		await get_tree().create_timer(0.3).timeout
		await _capture(dir + "/3_floor2_debug_overlay.png")
		f2.disable_debug_view()

	# 装修模式:菜单 + 网格 + 放一间房间
	var ctrl := get_decoration_controller(2)
	if ctrl and f2:
		ctrl.enter_edit_mode()
		var room: PlaceableItemData = item_db.get_item(&"room_office")
		if room:
			if room.get_footprint() == Vector2i.ZERO:
				var est: Dictionary = await FootprintEstimator.estimate_scene(room.scene, f2.floor_tilemap, f2)
				room.calculated_footprint = est.footprint
			var b: Rect2i = f2.occupancy.bounds
			var min_x := b.end.x
			for cell in f2.occupancy.buildable:
				min_x = mini(min_x, cell.x)
			f2.place_item(room, Vector2i(min_x + 2, b.position.y + 1))
		await get_tree().create_timer(0.4).timeout
		await _capture(dir + "/6_decoration_mode.png")
		# 清掉演示物品并退出,不影响后续截图/存档
		for iid in f2.placed_items.keys():
			f2.remove_item(iid, false)
		ctrl.exit_edit_mode()

	switch_floor(1)
	await get_tree().create_timer(0.3).timeout
	await _capture(dir + "/4_floor1_back.png")

	# 便签(摸鱼)模式:确认 2F 也随 FullGameMode 一起隐藏
	var main_node := get_parent()
	if main_node and main_node.has_method("_toggle_mode"):
		main_node._toggle_mode()
		await get_tree().create_timer(0.6).timeout
		await _capture(dir + "/5_sticky_mode.png")
		main_node._toggle_mode()
		await get_tree().process_frame
	print("[FloorShots] 截图已保存到 ", dir)
	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[FloorShots] ", path)


# ---- 数据库冒烟测试(--test-item-db):扫描/查询/运行时占地估算 ----
func _run_item_db_test() -> void:
	await get_tree().process_frame  # 等 2F 创建完(估算要用它的 TileMapLayer)
	var t := func(cond: bool, msg: String):
		print("[ItemDB] %s %s" % ["PASS" if cond else "FAIL", msg])

	t.call(item_db.get_all_ids().size() >= 2, "扫描注册 %d 件(≥2)" % item_db.get_all_ids().size())
	t.call(item_db.has_item(&"room_office"), "room_office 已注册")
	t.call(item_db.has_item(&"desk_slot_standard"), "desk_slot_standard 已注册")

	var rooms := item_db.get_by_category(PlaceableItemData.Category.ROOM)
	var desks := item_db.get_by_category(PlaceableItemData.Category.DESK)
	t.call(rooms.size() == 1 and rooms[0].item_id == &"room_office", "ROOM 分类查询正确")
	t.call(desks.size() == 1, "DESK 分类查询正确")
	t.call(item_db.get_unlocked(1).size() >= 2, "按解锁等级筛选正确")
	t.call(item_db.filter_by_tags([&"legacy"]).size() == 2, "按标签筛选正确")

	var room_item := item_db.get_item(&"room_office")
	t.call(room_item.get_footprint() == Vector2i(6, 4) and not room_item.auto_calculate_footprint,
			"初始数据未写死 footprint(待人工确认)")

	# 运行时占地估算(结果仅打印,不落盘)
	var f2 := get_floor_node(2)
	if f2:
		for id in item_db.get_all_ids():
			var item: PlaceableItemData = item_db.get_item(id)
			var est: Dictionary = await FootprintEstimator.estimate_scene(
					item.scene, f2.floor_tilemap, f2.furniture_layer)
			print("[ItemDB] 估算 %s: 来源=%s 像素=%s 建议占地=%s 透明留白=%s" % [
					id, est.source, est.pixel_bounds.size, est.footprint, est.transparent_risk])
			t.call(est.footprint.x > 0 and est.footprint.y > 0, "%s 运行时估算可用" % id)
	print("[ItemDB] done")
	get_tree().quit()


# ---- 摆放系统端到端测试(--test-placement) ----
func _run_placement_test() -> void:
	await get_tree().process_frame
	var t := func(cond: bool, msg: String):
		print("[Placement] %s %s" % ["PASS" if cond else "FAIL", msg])

	debug_unlock_second_floor = true
	switch_floor(2)
	var f2 := get_floor_node(2)
	var ctrl := get_decoration_controller(2)
	t.call(get_decoration_controller(1) == null, "第一层没有装修控制器,进不了装修模式")
	ctrl.enter_edit_mode()
	t.call(ctrl.is_active(), "进入装修模式")

	var room: PlaceableItemData = item_db.get_item(&"room_office")
	var desk: PlaceableItemData = item_db.get_item(&"desk_slot_standard")
	for d in [room, desk]:
		if d.get_footprint() == Vector2i.ZERO:
			var est: Dictionary = await FootprintEstimator.estimate_scene(d.scene, f2.floor_tilemap, f2)
			d.calculated_footprint = est.footprint
	print("[Placement] room fp=", room.get_footprint(), " desk fp=", desk.get_footprint())

	# 起点:入口列右侧一格
	var b: Rect2i = f2.occupancy.bounds
	var min_x := b.end.x
	for cell in f2.occupancy.buildable:
		min_x = mini(min_x, cell.x)
	var origin := Vector2i(min_x + 1, b.position.y + 1)

	var room_cells: Array[Vector2i] = []
	for c in room.get_occupied_cells():
		room_cells.append(origin + c)
	t.call(f2.check_cells(room_cells).ok, "房间起点合法")
	var placed_room := f2.place_item(room, origin)
	t.call(f2.placed_items.size() == 1, "房间已放置登记")
	t.call(f2.occupancy.get_occupant(origin) == placed_room.instance_id, "占用网格记录正确")

	var overlap_cells: Array[Vector2i] = []
	for c in desk.get_occupied_cells():
		overlap_cells.append(origin + c)
	t.call(not f2.check_cells(overlap_cells).ok, "重叠被拒绝")
	var oob: Array[Vector2i] = [b.position - Vector2i(5, 5)]
	t.call(not f2.check_cells(oob).ok, "越界被拒绝")

	var desk_origin := origin + Vector2i(room.get_footprint().x + 1, 0)
	var desk_item := f2.place_item(desk, desk_origin)
	t.call(f2.placed_items.size() == 2, "工位已放置")
	t.call(desk_item.scene_instance.is_in_group("desk_slots"), "2F 工位保留原有 group(不破坏原逻辑)")
	t.call(int(desk_item.scene_instance.get_meta("floor_id", 1)) == 2, "2F 工位带 floor_id 元数据(存档过滤用)")

	# 移动:拿起 → 释放占用 → 放到右移一格处
	f2.lift_item(placed_room.instance_id)
	t.call(f2.occupancy.get_occupant(origin).is_empty(), "拿起后释放占用")
	f2.drop_item(placed_room, origin + Vector2i(1, 0))
	t.call(f2.occupancy.get_occupant(origin + Vector2i(1, 0)) == placed_room.instance_id, "移动后重新登记")

	# 收入仓库
	f2.remove_item(desk_item.instance_id, true)
	t.call(int(f2.inventory.get("desk_slot_standard", 0)) == 1, "收入仓库计数正确")
	t.call(f2.placed_items.size() == 1, "入库后场上剩 1 件")

	# 存档往返 + 未知物品容错
	var snap := to_save_dict()
	t.call(snap.floors["2"].placed_items.size() == 1, "存档含 1 件已放置物品")
	snap.floors["2"].placed_items.append({
		"instance_id": "placed_99999", "item_id": "unknown_item_xyz",
		"origin_cell": [0, 0], "rotation": 0, "parent_room_id": "",
		"local_grid_position": [0, 0], "custom_state": {}})
	load_from_dict(snap)
	t.call(f2.placed_items.size() == 1, "读档恢复 1 件,未知物品跳过不崩溃")
	t.call(int(f2.inventory.get("desk_slot_standard", 0)) == 1, "仓库数量随档恢复")
	var resave := to_save_dict()
	t.call(resave.floors["2"].placed_items.size() == 2, "未知物品再存档时原样保留(不丢数据)")

	ctrl.exit_edit_mode()
	t.call(not ctrl.is_active(), "退出装修模式")
	print("[Placement] done")
	get_tree().quit()


# ---- 放置点击复现(--test-placement-click,需带窗口):模拟玩家真实点击流程 ----
func _run_placement_click_test() -> void:
	await get_tree().create_timer(1.0).timeout
	var t := func(cond: bool, msg: String):
		print("[PlaceClick] %s %s" % ["PASS" if cond else "FAIL", msg])
	debug_unlock_second_floor = true
	switch_floor(2)
	var f2 := get_floor_node(2)
	var ctrl := get_decoration_controller(2)
	ctrl.enter_edit_mode()
	var room: PlaceableItemData = item_db.get_item(&"room_office")
	ctrl.select_item_for_placement(room)
	await get_tree().create_timer(1.0).timeout  # 等占地估算完成
	t.call(ctrl.mode == DecorationController.Mode.PLACING, "已进入放置模式")
	print("[PlaceClick] kpi=", Gamemanager.kpi, " price=", room.price,
			" fp=", room.get_footprint())

	# 鼠标搬到可建造区中部、【顶行】某格中心(用户反馈顶部附近点不了)
	var b: Rect2i = f2.occupancy.bounds
	var target_cell := Vector2i(b.position.x + b.size.x / 2, b.position.y)
	var win: Vector2 = get_viewport().get_screen_transform() * f2.cell_to_global(target_cell)
	Input.warp_mouse(win)
	await get_tree().process_frame
	await get_tree().process_frame
	var cell_read: Vector2i = ctrl._mouse_cell()
	print("[PlaceClick] 目标格=", target_cell, " 实际读到=", cell_read)
	print("[PlaceClick] 预览状态=", ctrl._evaluate(ctrl._cells_at(cell_read)), "(0=绿)")

	# 模拟左键按下+松开:事件坐标取"实际光标所在点"的物理窗口坐标,
	# 保证点击和预览锚点是同一个格(warp 与事件坐标系有偏差,以轮询到的光标为准)
	var click_pos: Vector2 = get_viewport().get_screen_transform() \
			* f2.floor_tilemap.get_global_mouse_position()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = click_pos
		ev.global_position = click_pos
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	t.call(f2.placed_items.size() == 1, "点击后已放置 1 件(实际 %d 件)" % f2.placed_items.size())

	# 对齐验证:落位后的视觉边界左上角 ≈ 目标格角(图二偏差问题)
	if f2.placed_items.size() == 1:
		var item: PlacedFloorItem = f2.placed_items.values()[0]
		var est := FootprintEstimator.estimate_node(item, f2.floor_tilemap)
		var corner: Vector2 = f2.cell_to_global(item.origin_cell) - f2._half_cell()
		var delta: Vector2 = (est.pixel_bounds.position - corner).abs()
		t.call(delta.x < 2.0 and delta.y < 2.0, "落位视觉与网格对齐(偏差 %.1f, %.1f px)" % [delta.x, delta.y])
	ctrl.exit_edit_mode()
	print("[PlaceClick] done")
	get_tree().quit()


# ---- 点击链路诊断(--test-floor-click):模拟真实鼠标点 2F 按钮,排查 UI 遮挡 ----
func _run_click_diagnosis() -> void:
	await get_tree().create_timer(2.0).timeout
	print("[FloorClick] player_level=", Gamemanager.player_level,
		" unlocked_flag=", _second_floor_unlocked,
		" is_floor_unlocked(2)=", is_floor_unlocked(2),
		" floors=", _floors.keys())

	var ui := get_tree().get_first_node_in_group("floor_switch_ui")
	if ui == null:
		# 兜底:按名字找
		ui = get_node_or_null("../CanvasLayer/FloorSwitchUI")
	if ui == null:
		print("[FloorClick] FAIL 找不到 FloorSwitchUI")
		get_tree().quit()
		return
	var btn2: Button = null
	for c in ui.get_children():
		if c is Button and c.text == "2F":
			btn2 = c
	if btn2 == null:
		print("[FloorClick] FAIL 没有 2F 按钮,children=", ui.get_children())
		get_tree().quit()
		return
	var rect: Rect2 = btn2.get_global_rect()
	print("[FloorClick] 2F 按钮 rect=", rect, " visible=", btn2.is_visible_in_tree(),
		" disabled=", btn2.disabled, " modulate=", btn2.modulate)

	# 列出可能遮挡按钮中心的其他 Control(同点重叠且会吃鼠标的)
	var center := rect.get_center()
	_report_overlaps(get_tree().root, center, btn2)

	# 模拟真实点击(窗口坐标 = 屏幕变换 × 画布坐标)
	var xform := get_viewport().get_screen_transform()
	var win_pos: Vector2 = xform * center
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = win_pos
		ev.global_position = win_pos
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	print("[FloorClick] 点击后 current_floor_id=", current_floor_id,
		"(期望 2;若仍是 1 说明点击被拦或未解锁)")
	get_tree().quit()


# 深度遍历:打印覆盖 point 且非 IGNORE 的可见 Control(排除按钮自身及其祖先)
func _report_overlaps(node: Node, point: Vector2, exclude: Control) -> void:
	if node is Control and node.is_visible_in_tree() \
			and node.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and node.get_global_rect().has_point(point) \
			and node != exclude and not node.is_ancestor_of(exclude):
		print("[FloorClick] 覆盖点位: ", node.get_path(), " filter=", node.mouse_filter)
	for c in node.get_children():
		_report_overlaps(c, point, exclude)


# ---- 常驻调试视图(--floor-debug,正常游玩时叠加) ----
func _enable_floor_debug() -> void:
	await get_tree().process_frame  # 等 2F 创建完
	var f2 := get_floor_node(2)
	if f2:
		debug_unlock_second_floor = true
		f2.enable_debug_view(true)
