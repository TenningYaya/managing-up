extends Control

@onready var employee_container = $EmployeeContainer
@onready var skylight = $Skylight
@onready var drop_bounds = $DropBounds
@onready var hint_label = $HintLabel
@onready var hint_timer = $HintTimer

const MAX_DROP_EMPLOYEES := 10
const EMPLOYEE_SCENE := preload("res://scenes/employee/employee.tscn")

# 控制“均匀程度”的参数
const DROP_CANDIDATE_COUNT := 20
const MIN_EMPLOYEE_SPACING := 80.0

func _ready():
	print("EmployeeDropArea ready")

	hint_label.hide()
	hint_timer.timeout.connect(_on_hint_timer_timeout)
	
	if not Gamemanager.request_employee_drop.is_connected(_on_hire_received):
		Gamemanager.request_employee_drop.connect(_on_hire_received)
		print("signal connected to EmployeeDropArea")

func show_full_hint():
	hint_label.show()
	hint_timer.start(1.0)

func _on_hint_timer_timeout():
	hint_label.hide()
	
func _on_hire_received(employee_data):
	if get_drop_area_employee_count() >= MAX_DROP_EMPLOYEES:
		send_to_warehouse(employee_data)
		show_full_hint()
		return

	spawn_and_drop(employee_data)

#func get_drop_area_employee_count() -> int:
	#var count := 0
	#for child in employee_container.get_children():
		#if child.is_in_group("dropped_employee"):
			#count += 1
	#return count
func get_drop_area_employee_count() -> int:
	# 只统计“仍在 drop area 里等待”的员工：在掉落组里、但还没坐到工位上的。
	# 已经被拖到工位上的员工 (current_seat != null) 不占用 drop area 名额，
	# 否则场上满 10 人后即使全部就座也无法继续 dispatch。
	var count := 0
	for emp in get_tree().get_nodes_in_group("dropped_employee"):
		if emp.get("current_seat") == null:
			count += 1
	return count

func spawn_and_drop(employee_data):
	if employee_data == null: return
	
	# 登记入职
	EmployeeManager.hire_employee(employee_data) 
	
	var new_emp = employee_data 
	
	# 🌟 解冻员工（如果是从 Recall 状态回来的）
	new_emp.visible = true
	new_emp.process_mode = Node.PROCESS_MODE_INHERIT
	new_emp.mouse_filter = Control.MOUSE_FILTER_STOP
	
	if not new_emp.is_in_group("dropped_employee"):
		new_emp.add_to_group("dropped_employee")

	# 1. 把它加入场景树 (使用安全挂载)
	var main_employees_node = get_tree().root.find_child("employees", true, false)
	var target_parent = main_employees_node if main_employees_node else employee_container
	
	if new_emp.get_parent():
		if new_emp.get_parent() != target_parent:
			new_emp.reparent(target_parent) # 已经在树里了，用移交
	else:
		target_parent.add_child(new_emp) # 不在树里，用添加

	# 2. 设置位置并空投
	new_emp.global_position = skylight.global_position

	var target_global_pos = get_random_drop_position(new_emp)
	
	var tween = create_tween()
	tween.tween_property(new_emp, "global_position", target_global_pos, 0.6) \
		.set_trans(Tween.TRANS_BOUNCE) \
		.set_ease(Tween.EASE_OUT)

func get_random_drop_position(_emp_node: Control) -> Vector2:
	var rect_pos: Vector2 = drop_bounds.global_position
	var rect_size: Vector2 = drop_bounds.size
	
	# 【微调点 1】：内缩边距。值越大，员工越往中间集中，不会出界。
	# 建议设为 60-80 左右。
	var padding: float = 20.0 
	
	# 【微调点 2】：这是你之前用来抵消坐标偏离的修正值
	var offset_fix := Vector2(-50, -50)

	var best_global_pos: Vector2 = rect_pos + rect_size / 2.0
	var best_score: float = -1.0

	for i in range(DROP_CANDIDATE_COUNT):
		# 在内缩后的安全区内随机选点
		var candidate_global = Vector2(
			randf_range(rect_pos.x + padding, rect_pos.x + rect_size.x - padding),
			randf_range(rect_pos.y + padding, rect_pos.y + rect_size.y - padding)
		)

		# 重点：计算间距时，必须用“加上偏移后”的实际落点去比对
		var actual_test_pos = candidate_global + offset_fix
		var score = get_distance_to_nearest_employee(actual_test_pos)

		# 如果离得够远，直接录用这个点
		if score >= MIN_EMPLOYEE_SPACING:
			return actual_test_pos

		if score > best_score:
			best_score = score
			best_global_pos = actual_test_pos

	return best_global_pos

func get_distance_to_nearest_employee(check_pos: Vector2) -> float:
	var nearest_distance := INF
	# 关键：直接抓取全地图所有在场员工
	var dropped_nodes = get_tree().get_nodes_in_group("dropped_employee")
	
	if dropped_nodes.is_empty():
		return INF

	for emp in dropped_nodes:
		# 强制使用全局坐标进行距离计算
		var dist = check_pos.distance_to(emp.global_position)
		if dist < nearest_distance:
			nearest_distance = dist

	return nearest_distance
		
func send_to_warehouse(employee_data):
	if employee_data == null:
		push_error("send_to_warehouse 收到空员工数据")
		return

	EmployeeManager.hire_employee(employee_data)
