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
	# 直接统计当前场景里所有等待区员工
	var dropped_nodes = get_tree().get_nodes_in_group("dropped_employee")
	return dropped_nodes.size()


func spawn_and_drop(employee_data):
	if employee_data == null:
		push_error("spawn_and_drop 收到空员工数据")
		return

	# 先登记到总员工系统（如果已存在，你的 EmployeeManager 会自己拦重复）
	EmployeeManager.hire_employee(employee_data)

	var new_emp = EMPLOYEE_SCENE.instantiate()
	new_emp.add_to_group("dropped_employee")
	employee_container.add_child(new_emp)

	if new_emp.has_method("setup"):
		new_emp.setup(employee_data)
	elif new_emp.has_method("setup_card"):
		new_emp.setup_card(employee_data)

	# 先算终点：相对于 employee_container 的本地坐标
	var target_pos = get_random_drop_position(new_emp)

	# skylight 的全局位置换算成 employee_container 的本地坐标
	var skylight_local_pos = skylight.global_position - employee_container.global_position

	# 垂直掉落：起点和终点用同一个 x，只从上往下掉
	var start_pos = Vector2(target_pos.x, skylight_local_pos.y)
	new_emp.position = start_pos

	print("start_pos:", start_pos, " target_pos:", target_pos)

	var tween = create_tween()
	tween.tween_property(new_emp, "position", target_pos, 0.6) \
		.set_trans(Tween.TRANS_BOUNCE) \
		.set_ease(Tween.EASE_OUT)


func get_random_drop_position(emp_node: Control) -> Vector2:
	var bounds_global_pos = drop_bounds.global_position
	var bounds_size = drop_bounds.size
	var emp_size = emp_node.size

	# DropBounds 的全局坐标换算成 employee_container 的本地坐标
	var bounds_local_pos = bounds_global_pos - employee_container.global_position

	var min_x = bounds_local_pos.x
	var max_x = bounds_local_pos.x + max(bounds_size.x - emp_size.x, 0.0)

	var min_y = bounds_local_pos.y
	var max_y = bounds_local_pos.y + max(bounds_size.y - emp_size.y, 0.0)

	# 防止区域过小
	if max_x <= min_x or max_y <= min_y:
		return Vector2(min_x, min_y)

	var best_pos := Vector2(min_x, min_y)
	var best_score := -1.0

	# 多次随机候选，选择离现有员工最远的位置
	for i in range(DROP_CANDIDATE_COUNT):
		var candidate = Vector2(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y)
		)

		var score = get_distance_to_nearest_employee(candidate)

		# 如果已经足够分散，直接采用
		if score >= MIN_EMPLOYEE_SPACING:
			return candidate

		# 否则记住当前最优解
		if score > best_score:
			best_score = score
			best_pos = candidate

	return best_pos


func get_distance_to_nearest_employee(check_pos: Vector2) -> float:
	var nearest_distance := INF
	var dropped_nodes = get_tree().get_nodes_in_group("dropped_employee")

	if dropped_nodes.is_empty():
		return INF

	for emp in dropped_nodes:
		# 统一使用 employee_container 本地坐标
		var dist = check_pos.distance_to(emp.position)
		if dist < nearest_distance:
			nearest_distance = dist

	return nearest_distance


func send_to_warehouse(employee_data):
	if employee_data == null:
		push_error("send_to_warehouse 收到空员工数据")
		return

	EmployeeManager.hire_employee(employee_data)
	print("员工已直接送入仓库: ", employee_data.employee_name)
