extends Control
class_name Employee

# ==========================================
# 1. 数据层：属性与状态 (依据 GDD 设计文档)
# ==========================================
enum Rarity { R, SR, SSR }

var employee_name: String = "Marry"
var rarity: Rarity

var efficiency: int = 1 # 同事工作效率 (1-10)
var quality: int = 1    # 同事工作质量 (1-10)
var experience: int = 1 # 同事工作经验 (1-10)

# ==========================================
# 2. 交互层：拖拽与动画控制参数
# ==========================================
@export var snap_distance: float = 60.0 # 距离多近会自动吸附到椅子上

var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var current_seat: DeskSeat = null
var drag_start_seat: DeskSeat = null
var drag_start_position: Vector2 = Vector2.ZERO

# ==========================================
# 3. 生命周期与初始化
# ==========================================
func _ready() -> void:
	add_to_group("employees") # 加入群组，方便全局查找
	mouse_filter = Control.MOUSE_FILTER_STOP # 确保能接收到鼠标点击
	z_index = 1 # 默认层级
	randomize() # 确保每次生成的随机数不同
	employee_name = name

# 招聘系统调用此函数来初始化新同事
func setup_employee(new_rarity: Rarity) -> void:
	rarity = new_rarity
	_generate_attributes()

# ==========================================
# 4. 核心交互逻辑 (鼠标输入处理)
# ==========================================
# 修改后的核心交互逻辑
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# 按下时，记录起始位置并准备拖拽
			_start_drag()
			accept_event()
		else:
			# 【功能更新】：松开鼠标时，判断是“点击”还是“拖拽结束”
			# 如果位移非常小（比如小于 5 像素），我们就认为玩家只是点了一下，而不是想拖走
			var drag_distance = global_position.distance_to(drag_start_position)
			
			if drag_distance < 5.0:
				_on_employee_clicked()
			
			_end_drag()

# 点击后触发的函数
func _on_employee_clicked() -> void:
	print("点击了同事: ", employee_name)
	
	# 寻找场景中的 EmployeePanel
	# 做法：通过之前建议的 Group 来寻找，或者在主场景中给面板起个固定的名字
	var panel = get_tree().get_first_node_in_group("employee_panel")
	if panel:
		panel.open_panel(self)
	else:
		# 如果没设 Group，也可以尝试直接找路径（假设在主场景根目录下）
		get_tree().root.find_child("EmployeePanel", true, false).open_panel(self)
		print("警告：未找到 EmployeePanel 节点，请检查是否加入了 'employee_panel' 群组")
		
func _input(event: InputEvent) -> void:
	if not dragging:
		return

	if event is InputEventMouseMotion:
		# 拖拽时跟随鼠标
		global_position = get_global_mouse_position() - drag_offset

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_drag()

func _draw() -> void:
	if dragging:
		# 画出同事当前的几何中心（蓝点）
		var my_center = size / 2.0
		draw_circle(my_center, 8.0, Color.AQUA)
		
		# 画出 snap_distance 的判定圆圈
		draw_arc(my_center, snap_distance, 0, TAU, 32, Color.AQUA, 1.0)

func _process(_delta):
	if dragging:
		queue_redraw()
# ==========================================
# 5. 拖拽与吸附逻辑 (融合了生产中断与恢复)
# ==========================================
func _start_drag() -> void:
	dragging = true
	drag_offset = get_global_mouse_position() - global_position
	drag_start_position = global_position
	drag_start_seat = current_seat
	z_index = 100 # 拖拽时置于最顶层，防止穿模

	# 【业务逻辑插入】：如果原本在工作，离开工位意味着打断生产
	if current_seat != null:
		_calculate_interrupted_kpi() # 结算部分 KPI (GDD要求)
		current_seat.clear_occupant() # 释放工位
		current_seat = null

func _end_drag() -> void:
	dragging = false
	z_index = 1 # 恢复正常层级

	var target_seat := _find_valid_seat()

	if target_seat != null:
		snap_to_seat(target_seat, true)
	else:
		_return_to_start()

# 坐下（吸附）到目标工位
func snap_to_seat(seat: DeskSeat, animated: bool = true) -> void:
	if seat == null:
		return

	# 双重保险：确保清除旧座位的占用
	if current_seat != null and current_seat != seat:
		current_seat.clear_occupant()

	# 占领新座位
	current_seat = seat
	current_seat.set_occupant(self)

	# 计算目标中心点位置 (减去 size / 2.0 使立绘居中)
	var target_pos := seat.get_snap_global_position() - size / 2.0

	# 执行平滑移动或直接瞬移
	if animated:
		var tween := create_tween()
		tween.tween_property(self, "global_position", target_pos, 0.12)
		tween.finished.connect(_on_snap_finished) # 动画结束后开始生产
	else:
		global_position = target_pos
		_start_production_timer() # 直接开始生产

# 如果没放到椅子上，弹回原位
func _return_to_start() -> void:
	if drag_start_seat != null:
		snap_to_seat(drag_start_seat, true)
	else:
		var tween := create_tween()
		tween.tween_property(self, "global_position", drag_start_position, 0.12)

# 寻找鼠标周围符合距离的空工位
func _find_valid_seat() -> DeskSeat:
	var mouse_pos := get_global_mouse_position()
	var my_center := global_position + size / 2.0

	var best_seat: DeskSeat = null
	var best_dist := snap_distance

	# 遍历所有工位，寻找最近的空位
	for node in get_tree().get_nodes_in_group("desk_seats"):
		var seat := node as DeskSeat
		#print("正在检查工位: ", seat.name, " | 是否为空: ", seat.is_free())
		#if seat == null or not seat.is_free():
			#continue

		if not seat.contains_global_point(mouse_pos):
			continue

		var d := my_center.distance_to(seat.get_snap_global_position())
		if d < best_dist:
			best_dist = d
			best_seat = seat

	return best_seat

# ==========================================
# 6. GDD 业务算法与逻辑
# ==========================================

# 吸附动画结束的回调
func _on_snap_finished() -> void:
	_start_production_timer()

# 属性洗牌算法 (满足总和区间约束且单项不超10)
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
	
	var current_sum: int = 3
	var remaining_points: int = target_sum - current_sum
	
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

# TODO: 开始生产文件 (计算 600s 基础时间及效率缩减)
func _start_production_timer() -> void:
	#print(employee_name + " 开始在工位上生产了！")
	# 之后在这里实例化你的 Timer 节点
	pass

# TODO: 打断生产结算 (进度百分比 * 50% KPI)
func _calculate_interrupted_kpi() -> void:
	#print("生产被打断，结算补偿 KPI...")
	# 之后在这里获取 Timer 的进度并加钱
	pass
