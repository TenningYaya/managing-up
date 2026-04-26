extends Control
class_name Employee

enum Rarity { R, SR, SSR }

signal work_progress_changed(progress_percent: float)
signal work_started()
signal work_stopped()

#——————————员工信息————————————
@export var employee_name: String = "Marry"
@export var rarity: Rarity = Rarity.R
@export var efficiency: int = 1
@export var quality: int = 1
@export var experience: int = 1

#——————————员工状态————————————
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

#——————————动画————————————
var _move_tween: Tween = null
var _active_bubble: SpeechBubble = null

#当前生产时间计算公式为
#current_cycle_duration = maxf(2.0, base_file_production_time - (final_eff * base_reduction_time * random_factor))
#对应GDD：
#同事的最终文件生产时间 =（基础文件生产时间-（同事工作效率+同事工作效率补正）*减幅基数*（80-120随机数）%）

var base_kpi_value: int = 50
var base_file_production_time: float = 6.0 # 基础文件生产时间
var base_reduction_time: int = 30 # 减幅基数
var current_cycle_duration: float = 10.0
var current_desk_eff_buff: int = 0
var current_desk_qual_buff: int = 0
@export_range(0.0, 1.0, 0.05) var interrupted_reward_ratio: float = 0.5

const FILE_VFX_SCENE = preload("res://scenes/vfx/folder_vfx.tscn")
const SPEECH_BUBBLE_SCENE = preload("res://scenes/UI/custom/speech_bubble.tscn")
const DOLLAR_BURST_VFX_SCENE = preload("res://scenes/vfx/dollar_bust_vfx.tscn")

func _ready() -> void:
	add_to_group("employees")
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1
	randomize()

	if employee_name == "":
		employee_name = name

func setup_employee(new_rarity: Rarity) -> void:
	rarity = new_rarity
	_generate_attributes()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 1. 鼠标按下：记录位置，打上标记，但不立刻中断工作
				is_pressing = true
				drag_start_mouse_pos = get_global_mouse_position()
				drag_start_position = global_position
				drag_offset = drag_start_mouse_pos - global_position
				accept_event()
			else:
				# 2. 鼠标松开：在这里做最终判决！
				if is_pressing:
					is_pressing = false
					if dragging:
						# 如果已经进入拖拽状态，正常走吸附逻辑
						_end_drag()
					else:
						# 如果到松开为止都没触发拖拽，那就是在原地点击！
						_speed_up_work()
					accept_event()
					
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_on_employee_clicked()
			accept_event()

func _input(event: InputEvent) -> void:
	# 只有在鼠标左键按住的状态下，才处理位移
	if is_pressing and event is InputEventMouseMotion:
		# 如果还没进入拖拽状态，算一下鼠标偏离了按下点多远
		if not dragging:
			var move_dist = get_global_mouse_position().distance_to(drag_start_mouse_pos)
			if move_dist > 10.0:
				# 🌟 移动超过 10 像素，这才是真拖拽，立刻触发中断工作和拿起的逻辑
				_start_drag()
		
		# 如果已经在拖拽中了，就让员工跟着鼠标走
		if dragging:
			global_position = get_global_mouse_position() - drag_offset

func _draw() -> void:
	if dragging:
		var my_center := size / 2.0
		draw_circle(my_center, 8.0, Color.AQUA)
		draw_arc(my_center, snap_distance, 0.0, TAU, 32, Color.AQUA, 1.0)

func _process(delta: float) -> void:
	if dragging:
		queue_redraw()

	if is_working:
		work_elapsed += delta

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
	else:
		# 如果还是找不到，用 push_error 提醒，这比普通的 print 更容易在调试时被发现
		push_error("错误：找不到 EmployeePanel。请检查：1.面板是否在场景里 2.是否加了'employee_panel'组")

func _start_drag() -> void:
	if _move_tween:
		_move_tween.kill()
		_move_tween = null
	
	_clear_all_vfx()
	
	dragging = true
	drag_offset = get_global_mouse_position() - global_position
	drag_start_position = global_position
	drag_start_seat = current_seat
	z_index = 100

	if current_seat != null:
		_calculate_interrupted_reward()
		current_seat.clear_occupant()
		current_seat = null

func _clear_all_vfx() -> void:
	for child in get_children():
		if child is FileVFX: # 这里用到你脚本里定义的 class_name
			child.queue_free()

func _end_drag() -> void:
	dragging = false
	z_index = 1

	var target_seat := _find_valid_seat()

	if target_seat != null:
		snap_to_seat(target_seat, true)
	else:
		_return_to_start()


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
	
	print(employee_name, " 坐到了工位上，准备开工")
	
	# 🌟 这里只负责状态切换和总信号
	is_working = true
	work_started.emit() 
	
	# 🚀 剩下的脏活累活（算属性、算时间）全交给循环函数
	_start_new_work_cycle()

func _start_new_work_cycle():
	# 1. 重置当前进度计时
	work_elapsed = 0.0
	work_progress_changed.emit(0.0)
	
	# 2. 抓取最新的属性（调用我们刚才写的聚合器）
	var final_eff = get_final_efficiency()
	var random_factor = randf_range(0.8, 1.2)
	
	# 3. 锁定这一轮的时长
	current_cycle_duration = maxf(2.0, base_file_production_time - (final_eff * base_reduction_time * random_factor))
	
	print("新周期开始：效率 ", final_eff, " 预计耗时 ", current_cycle_duration)
	
func _stop_work(reset_progress: bool = true) -> void:
	is_working = false

	if reset_progress:
		work_elapsed = 0.0
		work_progress_changed.emit(0.0)

	work_stopped.emit()

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


func _generate_attributes() -> void:
	var target_sum: int = 0

	match rarity:
		Rarity.R:
			target_sum = randi_range(3, 12)
		Rarity.SR:
			target_sum = randi_range(13, 21)
		Rarity.SSR:
			target_sum = randi_range(14, 30)

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

func _finish_and_generate_file():
	# ======= 1. 计算文件质量 =======
	var init_score = randf_range(1.0, 100.0)
	
	# 🌟 修复：必须调用这个，才能把办公室的 Buff 全算进去！
	var total_qual = get_final_quality() 
	
	# 最终评分 = 初始评分 * (100 + 质量*2)%
	var final_score = init_score * (1.0 + (total_qual * 2.0) / 100.0)
	
	var kpi_multiplier = 1.0
	var dollar_reward = 1 
	var file_grade = "Gray"
	
	# 评级判定
	if final_score >= 95.0:
		file_grade = "Gold"
		kpi_multiplier = 2.0
		dollar_reward = 3
	elif final_score >= 71.0:
		file_grade = "Blue"
		kpi_multiplier = 1.5
		dollar_reward = 2
	elif final_score >= 31.0:
		file_grade = "Green"
		kpi_multiplier = 1.2
		dollar_reward = 1
		
	# ======= 2. 兑换 KPI =======
	var final_kpi = int(base_kpi_value * kpi_multiplier)
	
	var gm = _get_game_manager()
	if gm and gm.has_method("add_kpi"):
		gm.add_kpi(final_kpi)
	
	# ======= 3. 概率获得美金 =======
	var dollar_chance = (1.0 + 0.5 * experience) / 100.0
	if randf() <= dollar_chance:
		if gm and gm.has_method("add_dollar"):
			gm.add_dollar(dollar_reward)
		print("爆美金了！品质：", file_grade, " 数量：", dollar_reward)

	# 🌟 新增：触发头顶冒出动画
	_spawn_file_vfx(file_grade)
	
	# 结算完毕，开启下一轮
	_start_new_work_cycle()

# 生成特效的函数
func _spawn_file_vfx(grade: String) -> void:
	var vfx = FILE_VFX_SCENE.instantiate()
	add_child(vfx) # 把特效挂在员工身上
	
	# 设置初始位置：员工头顶正上方
	# 假设员工 size.y 是高度，往上挪一点
	vfx.position = Vector2((size.x - 22) / 2.0, -20.0)
	
	# 调用特效自己的播放逻辑
	vfx.play_vfx(grade)
	
	_spawn_dollar_vfx(vfx)

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
	# 只有在工作状态下点击才有效
	if not is_working:
		return
		
	# ✅ 使用当前这一轮锁定的总时长
	var total_duration = current_cycle_duration
	
	# GDD公式：减少最终生产时间 * 2%
	var speed_up_amount = total_duration * 0.02
	
	# 增加已工作的时间，相当于减少了剩余时间
	work_elapsed += speed_up_amount
	
	print(employee_name, " 被老板敲打了一下，工作进度增加了: ", speed_up_amount, " 秒")
	
	var random_texts = [
		"总感觉怪怪的你再改改",
		"快打包了什么时候做完啊",
		"老师这就是成图了吗"
	]
	var chosen_text = random_texts[randi() % random_texts.size()]
	# 触发冒气泡！
	_spawn_speech_bubble(chosen_text)
	
	# 检查是否点满了
	if get_work_progress_percent() >= 100.0:
		_finish_and_generate_file()


func get_final_efficiency() -> int:
	var total = efficiency
	
	# 来源 1：工位补正
	if current_seat and current_seat.has_method("get_efficiency_buff"):
		total += current_seat.get_efficiency_buff()
		
	total += OfficeManager.culture_efficiency
	
	# 来源 3：未来的全公司 Buff (预留位置)
	# total += Gamemanager.global_efficiency_bonus
	
	return total

# 获取当前的最终工作质量
func get_final_quality() -> int:
	var total = quality
	if current_seat and current_seat.has_method("get_quality_buff"):
		total += current_seat.get_quality_buff()
	total += OfficeManager.culture_quality
	
	## 来源 C：零食增益（之后茶水间会用到）
	#if has_method("get_snack_eff_bonus"): # 预留
		#total += get_snack_eff_bonus()
	
	return total
	
func get_final_experience() -> int:
	var total = experience
	
	# 来源 B：🌟 企业文化洗脑
	total += OfficeManager.culture_experience
	
	return total

func _spawn_speech_bubble(text_content: String) -> void:
	# 🌟 打断机制：如果头上已经有一个气泡了，直接把它干掉
	#if is_instance_valid(_active_bubble):
		#_active_bubble.kill_bubble()
		
	_active_bubble = SPEECH_BUBBLE_SCENE.instantiate()
	add_child(_active_bubble)
	
	_active_bubble.scale = Vector2(0.3, 0.3)
	# 设置层级，保证盖住员工和后面的东西
	_active_bubble.z_index = 3 
	
	# 设置位置：员工头顶稍微偏右一点（假设气泡尾巴在左下角）
	_active_bubble.position = Vector2(-50, -70)
	
	# 呼叫接口，播放内容
	_active_bubble.pop_up(text_content)
