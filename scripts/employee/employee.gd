#employee.gd
extends Control
class_name Employee

enum Rarity { R, SR, SSR }
enum SnackBuff { NONE, MILK_TEA, CAKE, SAUSAGE }

signal work_progress_changed(progress_percent: float)
signal work_started()
signal work_stopped()
signal buff_status_changed
signal work_speed_up_triggered
signal display_name_changed   # 玩家改名后发出：各处显示该员工名字的 UI 监听此信号刷新（不能叫 renamed，会和 Node 内置信号冲突）

#——————————员工信息————————————
@export var employee_name: String = "Marry"
var name_index: int = -1   # NameBank 下标；>=0 时显示名按当前语言实时解析（切语言会变）
var is_custom_named: bool = false   # 玩家手动改过名：固定用 employee_name，不再随语言/NameBank 解析（存档保留）
var hire_time: float = -1.0   # 入职时的玩家总游戏时长（-1=尚未入职）；在职时间 = 当前 total_time - hire_time
@export var rarity: Rarity = Rarity.R
@export var efficiency: int = 1
@export var quality: int = 1
@export var experience: int = 1
# 🌟 新增：用来存储个人长相和装饰索引的基因库
var dna: Dictionary = {}
var is_headhunt: bool = false

#——————————位移————————————
var current_seat: DeskSeat = null
var drag_start_seat: DeskSeat = null
var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var drag_start_position: Vector2 = Vector2.ZERO
var is_pressing: bool = false
var drag_start_mouse_pos: Vector2 = Vector2.ZERO
var is_working: bool = false
var work_elapsed: float = 0.0
@export var snap_distance: float = 60.0

@export_group("Roaming")
@export var roaming_enabled: bool = true
@export_range(5.0, 120.0, 1.0) var roam_check_interval_min: float = 18.0
@export_range(5.0, 120.0, 1.0) var roam_check_interval_max: float = 38.0
@export_range(0.0, 1.0, 0.01) var roam_chance: float = 0.22
@export_range(20.0, 500.0, 5.0) var roam_move_speed: float = 150.0
@export_range(0.0, 20.0, 0.5) var roam_idle_min: float = 2.0
@export_range(0.0, 20.0, 0.5) var roam_idle_max: float = 7.0
var is_roaming: bool = false
var _roam_check_time_left: float = 0.0
var _resume_work_after_roam: bool = false
# [员工吐槽中心]：员工被抓回工位结束漫游 —— 记录“被抓起的那一刻是否正在摸鱼漫游”，落座后据此触发吐槽
var _grabbed_while_roaming: bool = false
# urge 催工气泡完整播放约 3s，之后再补吐槽，避免新气泡把催工气泡顶掉
const DRAGGED_BACK_BANTER_DELAY := 3.0
var _roam_entry_point_pos: Vector2 = Vector2.ZERO
var _roam_corridor_y: float = 0.0
@export_group("")

#——————————生产逻辑————————————
#当前生产时间计算公式为
#current_cycle_duration = maxf(2.0, base_file_production_time - (final_eff * base_reduction_time * random_factor))
#对应GDD：
#同事的最终文件生产时间 =（基础文件生产时间-（同事工作效率+同事工作效率补正）*减幅基数*（80-120随机数）%）
var base_kpi_value: int = 30
var base_file_production_time: float = 300.0 # 基础文件生产时间
var base_reduction_time: int = 30 # 减幅基数
var current_cycle_duration: float = 10.0
@export_range(0.0, 1.0, 0.05) var interrupted_reward_ratio: float = 0.5

#——————————buff————————————
var current_desk_eff_buff: int = 0
var current_desk_qual_buff: int = 0
var current_snack_buff: SnackBuff = SnackBuff.NONE
var is_in_meeting: bool = false
var meet_buff_eff: int = 0
var meet_buff_qual: int = 0
var meet_buff_exp: int = 0

#——————————美术资源————————————
@onready var visual_anchor = $VisualAnchor
var visual_component: Node2D # 挂载的 sr_visual 实例
var portrait: Texture2D      # 核心：生成的静态立绘

#——————————动画————————————
var _move_tween: Tween = null
var _active_bubble = null
const FILE_VFX_SCENE = preload("res://scenes/vfx/folder_vfx.tscn")
const SPEECH_BUBBLE_SCENE = preload("res://scenes/vfx/speech_bubble.tscn")
const URGE_BUBBLE_SCENE = preload("res://scenes/vfx/urge_bubble.tscn")
const DOLLAR_BURST_VFX_SCENE = preload("res://scenes/vfx/dollar_bust_vfx.tscn")
const DOLLAR_REWARD_SCENE = preload("res://scenes/vfx/dollar_reward.tscn")
var is_slacking: bool = false
var active_slacking_bubble = null
const SLACKING_BUBBLE_SCENE = preload("res://scenes/UI/custom/SlackingBubble.tscn")

func _ready() -> void:
	add_to_group("employees")
	# 场景预置员工（教程员工等）只写了英文 employee_name、没有 name_index，
	# 按英文名反查下标，让它们也能随语言显示中文名（老存档里的员工同理）。
	# is_custom_named 的员工是玩家手动改的名，绝不反查 NameBank（否则改成名库里有的英文名会被本地化覆盖）
	if name_index < 0 and employee_name != "" and not is_custom_named:
		name_index = NameBank.index_of(employee_name)
		refresh_name()
	# 第一次进入场景（被真正招进来 / 放到地图上）时记录入职时刻；
	# recall 重新进树时 hire_time 已 ≥0，不会被重置，所以在职时间连续不断。
	if hire_time < 0.0:
		hire_time = Gamemanager.total_time
	if size.x < 10 or size.y < 10:
		custom_minimum_size = Vector2(80, 80)
		size = Vector2(80, 80)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1
	randomize()
	_reset_roam_check_timer()
	if visual_component and visual_component.has_method("play_action"):
		#visual_component.setup_visual()
		if current_seat != null:
			visual_component.play_action("idle") # 有座，坐下敲键盘
		else:
			visual_component.play_action("walk") # 没座，立刻原地踏步
	if employee_name == "":
		employee_name = name
	# 🌟【新增兜底逻辑】：统一给所有出生的员工强行穿衣服、切剪影！

func setup_employee(new_rarity: Rarity) -> void:
	rarity = new_rarity
	_generate_attributes()
	
func _generate_attributes() -> void:
	var target_sum: int = 0

	match rarity:
		Rarity.R:
			target_sum = randi_range(3, 12)
		Rarity.SR:
			target_sum = randi_range(13, 21)
		Rarity.SSR:
			target_sum = randi_range(22, 30)

	efficiency = 1
	quality = 1
	experience = 1

	var remaining_points: int = target_sum - 3

	while remaining_points > 0:
		var stat_to_increase = randi() % 3

		if stat_to_increase == 0 and efficiency < 10:
			efficiency += 1
			remaining_points -= 1
		elif stat_to_increase == 1 and quality < 10:
			quality += 1
			remaining_points -= 1
		elif stat_to_increase == 2 and experience < 10:
			experience += 1
			remaining_points -= 1

# 显示用名字：有 name_index 就按当前语言实时解析，否则用 employee_name（老存档/自定义名兜底）
func get_display_name() -> String:
	if name_index >= 0:
		return NameBank.get_localized_name(name_index)
	return employee_name

# 把缓存的 employee_name 同步成当前语言（供直接读 employee_name 的代码/存档用）
func refresh_name() -> void:
	if name_index >= 0:
		employee_name = NameBank.get_localized_name(name_index)

# 玩家在仓库里手动改名：写回员工数据本身（单一数据源），并广播 renamed 让所有视图刷新。
# 改名后固定使用 employee_name，不再随语言切换或 NameBank 解析。
func set_custom_name(new_name: String) -> void:
	var clean := new_name.strip_edges()
	if clean == "":
		return
	employee_name = clean
	name_index = -1            # 脱离名库，显示名改由 employee_name 决定
	is_custom_named = true     # 永久标记，存档保留，防止 _ready/切语言把名字覆盖回去
	display_name_changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh_name()

func _input(event: InputEvent) -> void:
	if Gamemanager.is_employee_interaction_disabled or is_in_meeting:
		# 如果玩家正在拖拽中，突然被拉了闸，强行帮他松手，防止员工粘在鼠标上
		if is_pressing or dragging:
			is_pressing = false
			dragging = false
			_return_to_start()
		return # 💥 强行拦截！底下的所有点击、拖拽、右键业务代码全部作废！
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 🌟 关键修复：不要用 event.global_position，要用 get_global_mouse_position()
				# 并且：点击点若被展开的手机侧栏盖住，就让侧栏的按钮处理，员工不抢（否则会穿透加速）
				if get_global_rect().has_point(get_global_mouse_position()) and not _is_point_over_blocking_ui(get_viewport().get_mouse_position()):
					is_pressing = true
					drag_start_mouse_pos = get_global_mouse_position() 
					drag_start_position = global_position 
					drag_offset = drag_start_mouse_pos - global_position 
					get_viewport().set_input_as_handled()
			else:
				if is_pressing:
					is_pressing = false
					if dragging:
						_end_drag()
					else:
						if is_slacking and is_instance_valid(active_slacking_bubble):
							active_slacking_bubble.resolve(true)
						else:
							_speed_up_work()
							_on_employee_clicked()
		
		# 右键打开面板，同理也做全局保护
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if get_global_rect().has_point(get_global_mouse_position()) and not _is_point_over_blocking_ui(get_viewport().get_mouse_position()):
				_on_employee_clicked()
				get_viewport().set_input_as_handled()

	# 拖拽的每帧移动
	if is_pressing and event is InputEventMouseMotion:
		if not dragging:
			var move_dist = get_global_mouse_position().distance_to(drag_start_mouse_pos)
			if move_dist > 10.0:
				_start_drag()
		
		if dragging:
			var target_pos := get_global_mouse_position() - drag_offset
			_play_walk_towards(target_pos)
			global_position = target_pos

# 点击点是否被某个"会挡住世界点击"的 UI（如展开的手机侧栏）盖住
func _is_point_over_blocking_ui(screen_pos: Vector2) -> bool:
	for ui in get_tree().get_nodes_in_group("sidebar_panel"):
		if ui.has_method("blocks_point") and ui.blocks_point(screen_pos):
			return true
	return false

func _draw() -> void:
	#if dragging:
		#var my_center := size / 2.0
		#draw_circle(my_center, 8.0, Color.AQUA)
		#draw_arc(my_center, snap_distance, 0.0, TAU, 32, Color.AQUA, 1.0)
	pass
	
func _process(delta: float) -> void:
	if dragging:
		queue_redraw()
		# 保持贴住光标：边缘滚动时鼠标可能不动、只有地图在移动，
		# 靠每帧重新对齐让员工始终跟着光标（否则会脱手，留在原来的世界坐标上）
		global_position = get_global_mouse_position() - drag_offset

	if is_working:
		work_elapsed += delta
		_update_roaming(delta)
		if not is_working:
			return

		var progress := get_work_progress_percent()
		work_progress_changed.emit(progress)

		if progress >= 100.0:
			_finish_and_generate_file()


func _on_employee_clicked() -> void:
	# 1. 优先尝试通过组查找（这是性能最好、最推荐的方式）
	var target_panel = get_tree().get_first_node_in_group("employee_panel")
	
	# 2. 如果组里没找到（比如你还没来得及加组），则尝试直接找节点名字
	if not target_panel:
		target_panel = get_tree().root.find_child("EmployeePanel", true, false)
	
	# 3. 核心执行逻辑
	if target_panel and target_panel.has_method("open_panel"):
		target_panel.open_panel(self)

func _start_drag() -> void:
	if _move_tween:
		_move_tween.kill()
		_move_tween = null

	# [员工吐槽中心]：员工被抓回工位结束漫游 —— 抓起前先记下是否正在摸鱼（下面会把 is_roaming 清掉）
	_grabbed_while_roaming = is_roaming

	if is_roaming:
		is_roaming = false
		_resume_work_after_roam = false
	
	_clear_all_vfx()
	
	dragging = true
	
	if visual_component and visual_component.has_method("play_action"):
		visual_component.play_action("walk")
		
	drag_offset = get_global_mouse_position() - global_position
	drag_start_position = global_position
	drag_start_seat = current_seat
	z_index = 100

	if current_seat != null:
		_calculate_interrupted_reward()
		current_seat.clear_occupant()
		current_seat = null

func _end_drag() -> void:
	dragging = false
	z_index = 1

	# ==========================================
	# 🌟 新增：优先检测是不是扔进了会议室
	# ==========================================
	var offices = get_tree().get_nodes_in_group("offices")
	for office in offices:
		# 判断这个办公室当前是不是会议室，并且加载了逻辑
		if office.current_type == Gamemanager.OfficeType.MEETING_ROOM and office.logic_node != null:
			# 判断鼠标松开时，是不是在会议室的框框里
			if office.get_global_rect().has_point(get_global_mouse_position()):
				if office.logic_node.can_drop_employee(self):
					office.logic_node.drop_employee(self)
					return # 成功进入会议室，直接结束判定！
				else:
					var angry_texts = [
						"No seat, no meeting!",
						"没位置开什么会，先领活！",
						"没名分的会议我不参加..."
					]
					_spawn_speech_bubble(angry_texts[randi() % angry_texts.size()])
					
					_return_to_start() # 骂完之后，乖乖弹回去
					return

	# 如果没扔进会议室，正常走找工位的逻辑
	var target_seat := _find_valid_seat()

	if target_seat != null:
		# [员工吐槽中心]:从等候区被拖动到工位上（drag_start_seat 为空 = 之前不在座位上，即从等候区来的才吐槽）
		var from_waiting := drag_start_seat == null
		snap_to_seat(target_seat, true)
		if from_waiting:
			play_on_seated_banter()
	else:
		_return_to_start()

	# [员工吐槽中心]：员工被抓回工位结束漫游 —— 摸鱼溜达途中被玩家抓回工位坐下，先催工再吐槽
	# （扔进会议室的分支在上面已 return，不会走到这里；从等候区来的 from_waiting 时 _grabbed_while_roaming 必为 false，不会重复冒泡）
	if _grabbed_while_roaming:
		_grabbed_while_roaming = false
		play_on_dragged_back_from_roam()

func snap_to_seat(seat: DeskSeat, animated: bool = true) -> void:
	if seat == null:
		return

	if current_seat != null and current_seat != seat:
		current_seat.clear_occupant()

	current_seat = seat
	current_seat.set_occupant(self)

	var target_pos := seat.get_snap_global_position() - size / 2.0

	if animated:
		# 🌟 如果之前有正在跑的位移动画，先手动停掉它
		if _move_tween:
			_move_tween.kill()
		
		_move_tween = create_tween()
		_move_tween.tween_property(self, "global_position", target_pos, 0.12)
		_move_tween.finished.connect(_on_snap_finished)
	else:
		global_position = target_pos
		_start_work()

func _return_to_start() -> void:
	if drag_start_seat != null:
		snap_to_seat(drag_start_seat, true)
	else:
		var tween := create_tween()
		tween.tween_property(self, "global_position", drag_start_position, 0.12)


func _find_valid_seat() -> DeskSeat:
	var mouse_pos := get_global_mouse_position()
	var my_center := global_position + size / 2.0

	var best_seat: DeskSeat = null
	var best_dist := snap_distance

	for node in get_tree().get_nodes_in_group("desk_seats"):
		var seat := node as DeskSeat
		if seat == null:
			continue

		if not seat.is_free():
			continue

		if not seat.contains_global_point(mouse_pos):
			continue

		var d := my_center.distance_to(seat.get_snap_global_position())
		if d < best_dist:
			best_dist = d
			best_seat = seat

	return best_seat


func _on_snap_finished() -> void:
	_start_work()


func _start_work() -> void:
	if is_working: return # 防止重复触发
	
	# 🌟 这里只负责状态切换和总信号
	is_working = true
	work_started.emit() 
	EmployeeManager.employee_map_status_changed.emit()

	if visual_component and visual_component.has_method("play_action"):
		visual_component.play_action("idle")
		
	_start_new_work_cycle()

func _start_new_work_cycle():
	_reset_roam_check_timer()
	_try_get_snack_buff()
	
	if is_in_meeting:
		meet_buff_qual = randi_range(1, 3)
		meet_buff_exp = randi_range(1, 3)
		# 可以在这里加个打印，方便你观察数值波动
		buff_status_changed.emit()
		
	# 1. 重置当前进度计时
	work_elapsed = 0.0
	work_progress_changed.emit(0.0)
	
	# 2. 抓取最新的属性（调用我们刚才写的聚合器）
	var final_eff = get_final_efficiency()
	var random_factor = randf_range(0.8, 1.2)
	
	var raw_duration = base_file_production_time - (final_eff * base_reduction_time * random_factor)
	# 顺手把保底的最短时间也从 2.0 减半到 1.0秒，防止后期高级员工撞墙卡死
	current_cycle_duration = maxf(1.0, raw_duration * 0.5)
	
func _stop_work(reset_progress: bool = true) -> void:
	is_working = false

	if reset_progress:
		work_elapsed = 0.0
		work_progress_changed.emit(0.0)
		
	_clear_snack_buff()
	work_stopped.emit()

func _pause_work_for_roam() -> void:
	if not is_working:
		return

	is_working = false
	_resume_work_after_roam = true
	_clear_snack_buff()
	work_progress_changed.emit(get_work_progress_percent())
	EmployeeManager.employee_map_status_changed.emit()

func _resume_work_from_roam() -> void:
	if not _resume_work_after_roam:
		return
	if current_seat == null:
		_resume_work_after_roam = false
		return

	_resume_work_after_roam = false
	is_working = true
	_reset_roam_check_timer()
	work_progress_changed.emit(get_work_progress_percent())
	EmployeeManager.employee_map_status_changed.emit()

	if visual_component and visual_component.has_method("play_action"):
		visual_component.play_action("idle")

func _reset_roam_check_timer() -> void:
	_roam_check_time_left = randf_range(roam_check_interval_min, roam_check_interval_max)

func _update_roaming(delta: float) -> void:
	if not _can_try_roam():
		_reset_roam_check_timer()
		return

	_roam_check_time_left -= delta
	if _roam_check_time_left > 0.0:
		return

	_reset_roam_check_timer()
	if randf() <= roam_chance:
		_start_roaming()

func _can_try_roam() -> bool:
	if not roaming_enabled:
		return false
	if is_roaming or dragging or is_pressing or is_slacking or is_in_meeting:
		return false
	if current_seat == null:
		return false
	if not Gamemanager.is_tutorial_completed:
		return false
	return get_tree().get_nodes_in_group("employee_walk_points").size() > 0

func _play_walk_towards(target_pos: Vector2) -> void:
	if visual_component == null:
		return

	var move_delta := target_pos - global_position
	if visual_component.has_method("play_walk_direction"):
		visual_component.play_walk_direction(move_delta)
	elif visual_component.has_method("play_action"):
		visual_component.play_action("walk")

func _set_roam_above_desks() -> void:
	z_index = 90

func _set_roam_under_current_desk() -> void:
	if current_seat != null:
		z_index = current_seat.z_index + 1
	else:
		z_index = 1

func _play_seated_idle() -> void:
	if visual_component and visual_component.has_method("play_action"):
		visual_component.play_action("idle")

func _start_roaming() -> void:
	if not _can_try_roam():
		return

	var route := _build_roam_route()
	if route.is_empty():
		return

	if _move_tween:
		_move_tween.kill()

	is_roaming = true
	_set_roam_above_desks()
	_pause_work_for_roam()

	# 离座时在工位上放一条摸鱼的鱼，提示玩家这个座位有人、只是溜了
	if current_seat != null and current_seat.has_method("show_roaming_icon"):
		current_seat.show_roaming_icon()

	_move_tween = create_tween()
	var cursor_pos := global_position
	for target_pos in route:
		var distance := cursor_pos.distance_to(target_pos)
		var duration := maxf(0.08, distance / maxf(1.0, roam_move_speed))
		_move_tween.tween_callback(_play_walk_towards.bind(target_pos))
		_move_tween.tween_property(self, "global_position", target_pos, duration)
		cursor_pos = target_pos

	var idle_time := randf_range(roam_idle_min, roam_idle_max)
	if idle_time > 0.0:
		if visual_component and visual_component.has_method("play_action"):
			_move_tween.tween_callback(visual_component.play_action.bind("idle"))
		_move_tween.tween_interval(idle_time)

	var return_pos := current_seat.get_snap_global_position() - size / 2.0
	var return_route := _build_roam_return_route(route[route.size() - 1], return_pos)
	var switched_under_for_desk := false
	for target_pos in return_route:
		var distance := cursor_pos.distance_to(target_pos)
		var duration := maxf(0.08, distance / maxf(1.0, roam_move_speed))
		if not switched_under_for_desk and _should_roam_under_desk_for_segment(cursor_pos, target_pos, return_pos):
			_move_tween.tween_callback(_set_roam_under_current_desk)
			switched_under_for_desk = true
		_move_tween.tween_callback(_play_walk_towards.bind(target_pos))
		_move_tween.tween_property(self, "global_position", target_pos, duration)
		cursor_pos = target_pos
	_move_tween.finished.connect(_finish_roaming)

func _build_roam_route() -> Array[Vector2]:
	var walk_points: Array[Node2D] = []
	var destination_points: Array[Node2D] = []
	var turn_points: Array[Node2D] = []
	for point in get_tree().get_nodes_in_group("employee_walk_points"):
		var walk_point := point as Node2D
		if walk_point == null or not walk_point.is_visible_in_tree():
			continue

		walk_points.append(walk_point)
		if _is_roam_turn_point(walk_point):
			turn_points.append(walk_point)
		else:
			destination_points.append(walk_point)

	if walk_points.is_empty():
		return []

	var entry_candidates := _get_same_side_entry_walk_points(walk_points)
	var entry_point := _find_nearest_walk_point(entry_candidates, global_position + size / 2.0)
	if entry_point == null:
		return []

	_roam_entry_point_pos = _walk_point_target_pos(entry_point)
	_roam_corridor_y = _get_roam_corridor_y(turn_points, walk_points)

	var destinations: Array[Node2D] = destination_points.duplicate()
	destinations.erase(entry_point)
	if destinations.is_empty():
		destinations = walk_points.duplicate()
		destinations.erase(entry_point)
		for turn_point in turn_points:
			destinations.erase(turn_point)

	if destinations.is_empty():
		var entry_only_route: Array[Vector2] = []
		_append_orthogonal_path(entry_only_route, global_position, _roam_entry_point_pos, false)
		return entry_only_route

	destinations.shuffle()
	var destination: Node2D = destinations[0]
	var destination_pos := _walk_point_target_pos(destination)

	var route: Array[Vector2] = []
	_append_orthogonal_path(route, global_position, _roam_entry_point_pos, false)
	_append_route_point(route, Vector2(_roam_entry_point_pos.x, _roam_corridor_y))
	_append_route_point(route, Vector2(destination_pos.x, _roam_corridor_y))
	_append_route_point(route, destination_pos)
	return route

func _build_roam_return_route(from_pos: Vector2, return_pos: Vector2) -> Array[Vector2]:
	var route: Array[Vector2] = []
	_append_route_point(route, Vector2(from_pos.x, _roam_corridor_y), from_pos)
	_append_route_point(route, Vector2(_roam_entry_point_pos.x, _roam_corridor_y))
	_append_route_point(route, _roam_entry_point_pos)
	_append_orthogonal_path(route, _roam_entry_point_pos, return_pos, false)
	return route

func _is_roam_turn_point(point: Node2D) -> bool:
	return String(point.name).begins_with("TurnPoint")

func _is_room_walk_point(point: Node2D) -> bool:
	return String(point.name).to_lower().begins_with("room")

func _get_visible_walk_points() -> Array[Node2D]:
	var walk_points: Array[Node2D] = []
	for point in get_tree().get_nodes_in_group("employee_walk_points"):
		var walk_point := point as Node2D
		if walk_point == null or not walk_point.is_visible_in_tree():
			continue
		walk_points.append(walk_point)
	return walk_points

func _get_same_side_entry_walk_points(walk_points: Array[Node2D]) -> Array[Node2D]:
	var usable_points: Array[Node2D] = []
	var fallback_points: Array[Node2D] = []
	for point in walk_points:
		if not _is_roam_turn_point(point):
			fallback_points.append(point)
			if not _is_room_walk_point(point):
				usable_points.append(point)

	if usable_points.is_empty():
		usable_points = fallback_points

	if current_seat == null:
		return usable_points if not usable_points.is_empty() else walk_points

	var seat_parent := current_seat.get_parent()
	var seat_grid := seat_parent as Control
	if seat_grid == null:
		return usable_points if not usable_points.is_empty() else walk_points

	var grid_center_x := seat_grid.get_global_rect().get_center().x
	var seat_center_x := current_seat.get_global_rect().get_center().x
	var use_left_side := seat_center_x < grid_center_x
	var same_side_points: Array[Node2D] = []
	for point in usable_points:
		if use_left_side and point.global_position.x <= grid_center_x:
			same_side_points.append(point)
		elif not use_left_side and point.global_position.x >= grid_center_x:
			same_side_points.append(point)

	return same_side_points if not same_side_points.is_empty() else usable_points

func _find_nearest_room_walk_point(from_pos: Vector2) -> Node2D:
	var room_points: Array[Node2D] = []
	var fallback_points: Array[Node2D] = []
	for point in _get_visible_walk_points():
		if _is_roam_turn_point(point):
			continue
		fallback_points.append(point)
		if _is_room_walk_point(point):
			room_points.append(point)

	if not room_points.is_empty():
		return _find_nearest_walk_point(room_points, from_pos)
	return _find_nearest_walk_point(fallback_points, from_pos)

func _build_meeting_return_route(from_pos: Vector2, return_pos: Vector2) -> Array[Vector2]:
	var walk_points := _get_visible_walk_points()
	if walk_points.is_empty():
		return []

	var turn_points: Array[Node2D] = []
	for point in walk_points:
		if _is_roam_turn_point(point):
			turn_points.append(point)

	var entry_candidates := _get_same_side_entry_walk_points(walk_points)
	var entry_point := _find_nearest_walk_point(entry_candidates, return_pos + size / 2.0)
	if entry_point == null:
		return []

	_roam_entry_point_pos = _walk_point_target_pos(entry_point)
	_roam_corridor_y = _get_roam_corridor_y(turn_points, walk_points)

	return _build_roam_return_route(from_pos, return_pos)

func _find_nearest_walk_point(points: Array[Node2D], from_pos: Vector2) -> Node2D:
	var nearest_point: Node2D = null
	var nearest_distance := INF
	for point in points:
		var distance := from_pos.distance_to(point.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_point = point
	return nearest_point

func _get_roam_corridor_y(turn_points: Array[Node2D], walk_points: Array[Node2D]) -> float:
	var y := -INF
	var source_points: Array[Node2D] = turn_points if not turn_points.is_empty() else walk_points
	for point in source_points:
		y = maxf(y, _walk_point_target_pos(point).y)
	return y

func _walk_point_target_pos(point: Node2D) -> Vector2:
	return point.global_position - size / 2.0

func _append_orthogonal_path(route: Array[Vector2], from_pos: Vector2, to_pos: Vector2, vertical_first: bool) -> void:
	if is_equal_approx(from_pos.x, to_pos.x) or is_equal_approx(from_pos.y, to_pos.y):
		_append_route_point(route, to_pos, from_pos)
		return

	var corner := Vector2(from_pos.x, to_pos.y) if vertical_first else Vector2(to_pos.x, from_pos.y)
	_append_route_point(route, corner, from_pos)
	_append_route_point(route, to_pos)

func _append_route_point(route: Array[Vector2], point: Vector2, previous_override = null) -> void:
	var previous: Vector2 = global_position
	if not route.is_empty():
		previous = route[route.size() - 1]
	elif previous_override is Vector2:
		previous = previous_override

	if previous.distance_to(point) <= 0.5:
		return
	route.append(point)

func _should_roam_under_desk_for_segment(segment_start: Vector2, segment_end: Vector2, return_pos: Vector2) -> bool:
	if segment_end.distance_to(return_pos) <= 0.5:
		return true

	return segment_start.distance_to(_roam_entry_point_pos) <= 0.5 and segment_end.distance_to(_roam_entry_point_pos) > 0.5

func _finish_roaming() -> void:
	is_roaming = false
	_move_tween = null

	if current_seat != null:
		global_position = current_seat.get_snap_global_position() - size / 2.0
		current_seat.set_occupant(self)
		# 员工回到工位，收起鱼图标
		if current_seat.has_method("hide_roaming_icon"):
			current_seat.hide_roaming_icon()

	_resume_work_from_roam()

func _finish_meeting_return() -> void:
	is_roaming = false
	_move_tween = null

	if current_seat != null:
		global_position = current_seat.get_snap_global_position() - size / 2.0
		current_seat.set_occupant(self)
		_set_roam_under_current_desk()
		_play_seated_idle()

	is_working = current_seat != null
	_start_new_work_cycle()

func _calculate_interrupted_reward() -> void:
	if not is_working:
		return

	# 1. 计算当前进度 (0.0 - 1.0)
	var progress_ratio = clampf(work_elapsed / current_cycle_duration, 0.0, 1.0)
	
	# 2. 根据 GDD 公式：保底价值 * 进度 * 50%
	# 假设打断时一律按 Gray 质量（100% 价值基数）计算
	var partial_reward: int = int(base_kpi_value * progress_ratio * 0.5)

	# 3. 停止工作并重置进度
	_stop_work(true) 

	if partial_reward > 0:
		var gm = _get_game_manager()
		if gm and gm.has_method("add_kpi"):
			gm.add_kpi(partial_reward)
			print(employee_name, " 工作被打断，结算补偿 KPI: ", partial_reward)


func get_work_progress_percent() -> float:
	# 只认我们新算的、存在变量里的那个“当前周期时长”
	if current_cycle_duration <= 0.0:
		return 0.0
	return clampf(work_elapsed / current_cycle_duration * 100.0, 0.0, 100.0)

func _get_game_manager() -> Node:
	return get_tree().root.get_node_or_null("Gamemanager")




func _finish_and_generate_file():
	# ======= 1. 计算文件质量 =======
	var init_score = randf_range(1.0, 100.0)
	
	var total_qual = get_final_quality() 
	
	# 最终评分 = 初始评分 * (100 + 质量*2)%
	var final_score = init_score * (1.0 + (total_qual * 2.0) / 100.0)
	
	var kpi_multiplier = 1.0
	var dollar_reward = 1 
	var file_grade = "Gray"
	
	# 评级判定
	if final_score >= 95.0:
		file_grade = "Gold"
		kpi_multiplier = 3.0
		dollar_reward = 10
	elif final_score >= 71.0:
		file_grade = "Blue"
		kpi_multiplier = 2.0
		dollar_reward = 6
	elif final_score >= 31.0:
		file_grade = "Green"
		kpi_multiplier = 1.2
		dollar_reward = 4
		
	# ======= 2. 兑换 KPI =======
	var final_kpi = int(round(base_kpi_value * kpi_multiplier * 0.75))
	
	var gm = _get_game_manager()
	if gm and gm.has_method("add_kpi"):
		gm.add_kpi(final_kpi)
		
	# ======= 3. 概率获得美金 =======
	var dollar_chance = (10.0 + 5.0 * get_final_experience()) / 100.0
	var did_get_dollar = false
	if randf() <= dollar_chance:
		if gm and gm.has_method("add_dollar"):
			gm.add_dollar(dollar_reward)
			did_get_dollar = true

	# 🌟 新增：触发头顶冒出动画
	_spawn_file_vfx(file_grade)
	var file_vfx_node = _spawn_file_vfx(file_grade)
	if did_get_dollar and is_instance_valid(file_vfx_node):
		_spawn_dollar_vfx(file_vfx_node)
	_clear_snack_buff()
	
	if is_in_meeting:
		_start_new_work_cycle()
		return # 直接结束，不走下面的摸鱼随机数
		
	# 结算完毕，开启下一轮
	if not is_in_meeting and randf() <= 0.02:
		is_slacking = true
		if visual_component and visual_component.has_method("play_action"):
			visual_component.play_action("slack")
		is_working = false
		active_slacking_bubble = SLACKING_BUBBLE_SCENE.instantiate()
		add_child(active_slacking_bubble)
		active_slacking_bubble.position = Vector2((size.x - 40) / 2.0, -50.0)
		active_slacking_bubble.slacking_resolved.connect(_on_slacking_resolved)
	else:
		_start_new_work_cycle()

func _on_slacking_resolved(by_click: bool) -> void:
	is_slacking = false
	is_working = true
	if visual_component and visual_component.has_method("play_action"):
		visual_component.play_action("idle")
	if by_click:
		var reward_amount = randi_range(2, 4)
		Gamemanager.add_dollar(reward_amount)
		var spawn_pos: Vector2 = global_position
		if is_instance_valid(active_slacking_bubble):
			spawn_pos = active_slacking_bubble.global_position
		var reward_vfx := DOLLAR_REWARD_SCENE.instantiate()
		get_tree().root.add_child(reward_vfx)
		reward_vfx.global_position = spawn_pos + Vector2(10.0, 0.0)
		reward_vfx.play()

	_start_new_work_cycle()

# 生成特效的函数
func _spawn_file_vfx(grade: String) -> Node:
	var vfx = FILE_VFX_SCENE.instantiate()
	add_child(vfx) # 把特效挂在员工身上
	
	# 设置初始位置：员工头顶正上方
	# 假设员工 size.y 是高度，往上挪一点
	vfx.position = Vector2((size.x - 20) / 2.0, -20.0)
	
	# 调用特效自己的播放逻辑
	vfx.play_vfx(grade)
	return vfx
	
func _spawn_dollar_vfx(vfx) -> void:
# 实例化并播放特效
	var burst_vfx = DOLLAR_BURST_VFX_SCENE.instantiate()

	# 🌟 关键：加在 Main 场景下，而不是员工下，防止员工移动带跑了特效轨迹
	get_tree().root.add_child(burst_vfx)
	
	# 特效初始位置：文件夹图标的位置（即员工头顶）
	# 记得换算成全局坐标
	burst_vfx.global_position = vfx.global_position
	
	# 播放！
	if burst_vfx.has_method("play_burst_vfx"):
		burst_vfx.play_burst_vfx()
	
func _speed_up_work() -> void:
	if not is_working:
		return
		
	Gamemanager.total_speedups += 1   # 催工次数 +1（已过 is_working 判定，只统计真正生效的加速）
	var total_duration = current_cycle_duration
	var speed_up_amount = total_duration * 0.04
	work_elapsed += speed_up_amount
	
	# 🌟 这里的代码变清爽了！
	var chosen_text = SpeedupQuoteSave.get_random_quote()
	_spawn_speech_bubble(chosen_text)
	work_speed_up_triggered.emit()
	
	if get_work_progress_percent() >= 100.0:
		_finish_and_generate_file()
		
func _spawn_speech_bubble(text_content: String) -> void:
	if not Gamemanager.has_selected_avatar:
		return
	# 🌟 打断机制：如果头上已经有一个气泡了，直接把它干掉
	if is_instance_valid(_active_bubble):
		_active_bubble.kill_bubble()
		
	_active_bubble = URGE_BUBBLE_SCENE.instantiate()
	add_child(_active_bubble)
	
	_active_bubble.scale = Vector2(0.3, 0.3)
	# 绝对层级 + 调高：盖住桌子等世界物体（z_index 优先级高于 Y-sort，所以不会再被挡）
	_active_bubble.z_as_relative = false
	_active_bubble.z_index = 1000
	
	# 设置位置：员工头顶稍微偏右一点（假设气泡尾巴在左下角）
	_active_bubble.position = Vector2(20, -47)
	
	# 呼叫接口，播放内容
	_active_bubble.pop_up(text_content)

func _spawn_banter_bubble(text_content: String) -> void:
	# 🌟 打断机制：如果头上已经有一个气泡了，直接把它干掉
	if is_instance_valid(_active_bubble):
		_active_bubble.kill_bubble()
		
	_active_bubble = SPEECH_BUBBLE_SCENE.instantiate()
	add_child(_active_bubble)
	
	_active_bubble.scale = Vector2(0.3, 0.3)
	# 绝对层级 + 调高：盖住桌子等世界物体（z_index 优先级高于 Y-sort，所以不会再被挡）
	_active_bubble.z_as_relative = false
	_active_bubble.z_index = 1000
	
	# 设置位置：员工头顶稍微偏右一点（假设气泡尾巴在左下角）
	_active_bubble.position = Vector2(70, -27)
	
	# 呼叫接口，播放内容
	_active_bubble.pop_up(text_content)

func play_on_hired_banter() -> void:
	# 员工进了仓库而不是 drop area，不在场景树里，无法生成气泡
	if not is_inside_tree():
		return
	var pool = BanterManager.QUOTES["new_hire"]
	var random_key = pool[randi() % pool.size()]
	_spawn_banter_bubble(tr(random_key))

# [员工吐槽中心]:从等候区被拖动到工位上
func play_on_seated_banter() -> void:
	if not is_inside_tree():
		return
	var pool = BanterManager.QUOTES["seated"]
	var random_key = pool[randi() % pool.size()]
	_spawn_banter_bubble(tr(random_key))

# [员工吐槽中心]：员工被抓回工位结束漫游 —— 摸鱼溜达被玩家抓回工位坐下：先来一句催工，催工气泡消失后再补一句吐槽
func play_on_dragged_back_from_roam() -> void:
	if not is_inside_tree():
		return
	# 1. 催工气泡：与在工位上被点击催工时完全一致（老板头像 + 随机催工台词）
	_spawn_speech_bubble(SpeedupQuoteSave.get_random_quote())
	# 2. 等 urge 气泡播放完，再发一句“被抓包摸鱼”的随机吐槽，避免新气泡把催工气泡顶掉
	var pool = BanterManager.QUOTES["drag_back_roam"]
	var random_key = pool[randi() % pool.size()]
	get_tree().create_timer(DRAGGED_BACK_BANTER_DELAY).timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			_spawn_banter_bubble(tr(random_key))
	)
	
func get_final_efficiency() -> int:
	var total = efficiency	
	# 来源 1：工位补正
	if current_seat and current_seat.has_method("get_efficiency_buff"):
		total += current_seat.get_efficiency_buff()
	# 来源 2：文化补正
	total += OfficeManager.culture_efficiency
	# 来源 3：零食补正
	if current_snack_buff == SnackBuff.MILK_TEA:
		total += 2
	# 来源 4：会议室补正
	total += meet_buff_eff
	
	# 🌟 极度重要：确保效率被扣后，最低不能小于 1，否则会导致除数为 0 或反向工作！
	return maxi(1, total)

# 获取当前的最终工作质量
func get_final_quality() -> int:
	var total = quality
	# 来源 1：工位补正
	if current_seat and current_seat.has_method("get_quality_buff"):
		total += current_seat.get_quality_buff()
	# 来源 2：文化补正	
	total += OfficeManager.culture_quality
	# 来源 3：零食补正
	if current_snack_buff == SnackBuff.CAKE:
		total += 3
	# 来源 4：会议室补正
	total += meet_buff_qual
	return total
	
func get_final_experience() -> int:
	var total = experience	
	# 来源 1：文化补正
	total += OfficeManager.culture_experience
	# 来源 2：零食补正
	if current_snack_buff == SnackBuff.SAUSAGE:
		total += 3
	# 来源 3：会议室补正
	total += meet_buff_exp
	return total


func _try_get_snack_buff() -> void:
	# 条件判定：如果已经在吃、或者在摸鱼、或者零食名额满了，就不发
	if current_snack_buff != SnackBuff.NONE: return
	# if is_slacking: return # 假设你有这个摸鱼变量
	if not OfficeManager.can_dispense_snack(): return
	
	# 零食概率：80% 触发，20% 跳过（randf() ∈ [0,1)，>0.8 的概率正好是 0.2）
	if randf() > 0.8: return
	
	# 成功获取！占领一个名额
	OfficeManager.active_snack_buffs += 1
	
	# 随机抽一种零食 (1, 2, 3 代表奶茶, 蛋糕, 烤肠)
	var random_buff = randi() % 3 + 1 
	current_snack_buff = random_buff as SnackBuff
	buff_status_changed.emit()
	
	# TODO: 这里可以播放一个头顶冒出奶茶/蛋糕图标的特效

# 3. 🌟 清理逻辑：工作结束、中断、或者员工被解雇时调用
func _clear_snack_buff() -> void:
	if current_snack_buff != SnackBuff.NONE:
		# 1. 归还名额并清空自己
		OfficeManager.active_snack_buffs -= 1
		current_snack_buff = SnackBuff.NONE
		buff_status_changed.emit()

		# 2. 击鼓传花：立刻让下一个人接盘 Buff
		var tree = Engine.get_main_loop() 
		if tree is SceneTree:
			var all_emps = tree.get_nodes_in_group("employees")
			
			# 🌟【神级补丁】：把数组顺序彻底打乱！打破场景树的阶级固化！
			all_emps.shuffle() 
			
			for emp in all_emps:
				# 条件：不是自己 + 正在打工 + 当前没吃零食
				if emp != self and emp.is_working and emp.current_snack_buff == SnackBuff.NONE:
					emp._try_get_snack_buff()
					# 如果这个人成功吃到了，就立刻结束传递
					if emp.current_snack_buff != SnackBuff.NONE:
						break

# 🌟 超级保险：只要员工被“收回(Recall)”或“开除(Fire)”，必定会触发这个内置函数
func _exit_tree() -> void:
	_clear_snack_buff()

# ==========================================
# 会议室核心逻辑
# ==========================================
func enter_meeting() -> void:
	is_in_meeting = true
	
	# 1. 进度从零开始 (需求：被拖入时清零)
	work_elapsed = 0.0
	work_progress_changed.emit(0.0)
	
	# 2. 结算会议 Buff (效率-1，其余+ 1~3)
	meet_buff_eff = -1
	meet_buff_qual = 0
	meet_buff_exp = 0
	
	# 3. 🌟 霸占原来的工位！
	# 因为你拖拽时 _start_drag 已经清空了 current_seat，这里我们要强行抢回来
	if drag_start_seat != null:
		current_seat = drag_start_seat
		current_seat.set_occupant(self)
		
		# 通知工位变身（显示“会议中”标签）
		if current_seat.has_method("set_meeting_state"):
			current_seat.set_meeting_state(true)
			
		# 把隐形的员工物理位置对齐回工位，防止乱飘挡住别人的鼠标点击
		global_position = current_seat.get_snap_global_position() - size / 2.0
			
	# 4. 隐藏真身，开启后台摸黑工作模式
	if visual_component:
		visual_component.hide()
	
	is_working = true
	_start_new_work_cycle() # 带上新 Buff 重新计算本轮时长

func exit_meeting(meeting_source_pos: Variant = null) -> void:
	is_in_meeting = false
	is_working = false
	
	# 1. 进度再次清零 (需求：解散会议时清零)
	work_elapsed = 0.0
	work_progress_changed.emit(0.0)
	
	# 2. 清除会议 Buff
	meet_buff_eff = 0
	meet_buff_qual = 0
	meet_buff_exp = 0
	
	# 3. 恢复工位状态和真身
	if current_seat != null and current_seat.has_method("set_meeting_state"):
		current_seat.set_meeting_state(false)
		
	if visual_component:
		visual_component.show()

	if meeting_source_pos is Vector2 and current_seat != null:
		var source_pos: Vector2 = meeting_source_pos
		var exit_point := _find_nearest_room_walk_point(source_pos)
		if exit_point != null:
			var start_pos := _walk_point_target_pos(exit_point)
			var return_pos := current_seat.get_snap_global_position() - size / 2.0
			var return_route := _build_meeting_return_route(start_pos, return_pos)
			if not return_route.is_empty():
				if _move_tween:
					_move_tween.kill()

				is_roaming = true
				_set_roam_above_desks()
				global_position = start_pos

				_move_tween = create_tween()
				var cursor_pos := global_position
				var switched_under_for_desk := false
				for target_pos in return_route:
					var distance := cursor_pos.distance_to(target_pos)
					var duration := maxf(0.08, distance / maxf(1.0, roam_move_speed))
					if not switched_under_for_desk and _should_roam_under_desk_for_segment(cursor_pos, target_pos, return_pos):
						_move_tween.tween_callback(_set_roam_under_current_desk)
						switched_under_for_desk = true
					_move_tween.tween_callback(_play_walk_towards.bind(target_pos))
					_move_tween.tween_property(self, "global_position", target_pos, duration)
					cursor_pos = target_pos
				_move_tween.finished.connect(_finish_meeting_return)
				return

	if current_seat != null:
		global_position = current_seat.get_snap_global_position() - size / 2.0
		current_seat.set_occupant(self)
		_set_roam_under_current_desk()
		_play_seated_idle()

	is_working = current_seat != null
	_start_new_work_cycle() # 恢复正常速度继续搬砖

func _clear_all_vfx() -> void:
	for child in get_children():
		if child is FileVFX: # 这里用到你脚本里定义的 class_name
			child.queue_free()

func force_give_snack_buff(buff_type: SnackBuff):
	# 1. 强行先清理一下之前的状态，防止占着名额
	_clear_snack_buff()
	
	# 2. 强行把 Buff 状态塞进去
	current_snack_buff = buff_type
	
	# 3. 告诉 Manager 名额占用（如果是教程，甚至可以不占用名额，看你心情）
	OfficeManager.active_snack_buffs += 1
	
	# 4. 广播状态，UI 立刻刷新图标
	buff_status_changed.emit()
