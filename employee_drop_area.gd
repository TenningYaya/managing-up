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

func get_drop_area_employee_count() -> int:
	var count := 0
	for child in employee_container.get_children():
		if child.is_in_group("dropped_employee"):
			count += 1
	return count

func spawn_and_drop(employee_data):
	if employee_data == null: return
	EmployeeManager.hire_employee(employee_data)

	var new_emp = EMPLOYEE_SCENE.instantiate()
	new_emp.add_to_group("dropped_employee")
	new_emp.name = employee_data.employee_name

	# ======= 🛠️ 关键修改区 =======
	# 1. 找到专门放员工的父节点，把新员工加进去
	var main_employees_node = get_tree().root.find_child("employees", true, false)
	if main_employees_node:
		main_employees_node.add_child(new_emp)
	else:
		employee_container.add_child(new_emp) # 备用防报错

	if new_emp.has_method("setup"): new_emp.setup(employee_data)
	elif new_emp.has_method("setup_card"): new_emp.setup_card(employee_data)

	# 2. 因为换了父节点，必须用 global_position (全局坐标)
	new_emp.global_position = skylight.global_position

	# 3. 计算掉落目标点并转换为全局坐标
	var local_target_pos = get_random_drop_position(new_emp)
	var global_target_pos = drop_bounds.global_position + (local_target_pos - drop_bounds.position)

	# 4. 播放动画，注意操作的是 global_position
	var tween = create_tween()
	tween.tween_property(new_emp, "global_position", global_target_pos, 0.6) \
		.set_trans(Tween.TRANS_BOUNCE) \
		.set_ease(Tween.EASE_OUT)
	# ==============================

	print("员工已掉落到 DropArea: ", employee_data.employee_name)
	
#func spawn_and_drop(employee_data):
	#if employee_data == null:
		#push_error("spawn_and_drop 收到空员工数据")
		#return
#
	## 先登记到总员工系统（防止重复添加）
	#EmployeeManager.hire_employee(employee_data)
#
	#var new_emp = EMPLOYEE_SCENE.instantiate()
	#new_emp.add_to_group("dropped_employee")
	#employee_container.add_child(new_emp)
	#new_emp.name = employee_data.employee_name
#
	## 如果你的员工场景有 setup / setup_card / bind_data 之类的方法，这里先接上
	#if new_emp.has_method("setup"):
		#new_emp.setup(employee_data)
	#elif new_emp.has_method("setup_card"):
		#new_emp.setup_card(employee_data)
#
	## 从天窗起始
	#new_emp.position = skylight.position
#
	## 在 DropBounds 范围内更均匀地选择落点
	#var target_pos = get_random_drop_position(new_emp)
	#print("随机掉落终点: ", target_pos)
#
	#var tween = create_tween()
	#tween.tween_property(new_emp, "position", target_pos, 0.6) \
		#.set_trans(Tween.TRANS_BOUNCE) \
		#.set_ease(Tween.EASE_OUT)

func get_random_drop_position(emp_node: Control) -> Vector2:
	var bounds_pos = drop_bounds.position
	var bounds_size = drop_bounds.size
	var emp_size = emp_node.size

	var min_x = bounds_pos.x
	var max_x = bounds_pos.x + max(bounds_size.x - emp_size.x, 0.0)

	var min_y = bounds_pos.y
	var max_y = bounds_pos.y + max(bounds_size.y - emp_size.y, 0.0)

	# 如果区域太小，直接返回左上角
	if max_x <= min_x or max_y <= min_y:
		return Vector2(min_x, min_y)

	var best_pos := Vector2(min_x, min_y)
	var best_score := -1.0

	# 多次随机候选，选一个“离现有员工最远”的位置
	for i in range(DROP_CANDIDATE_COUNT):
		var candidate = Vector2(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y)
		)

		var score = get_distance_to_nearest_employee(candidate)

		# 如果已经足够分散，直接用这个点
		if score >= MIN_EMPLOYEE_SPACING:
			return candidate

		# 否则先记住当前最优解
		if score > best_score:
			best_score = score
			best_pos = candidate

	return best_pos

func get_distance_to_nearest_employee(pos: Vector2) -> float:
	var nearest_distance := INF
	var has_employee := false

	for child in employee_container.get_children():
		if child.is_in_group("dropped_employee"):
			has_employee = true
			var dist = pos.distance_to(child.position)
			if dist < nearest_distance:
				nearest_distance = dist

	# 如果当前还没有别的员工，返回一个超大值
	if not has_employee:
		return INF

	return nearest_distance

func send_to_warehouse(employee_data):
	if employee_data == null:
		push_error("send_to_warehouse 收到空员工数据")
		return

	EmployeeManager.hire_employee(employee_data)
	print("员工已直接送入仓库: ", employee_data.employee_name)
