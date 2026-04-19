extends Control

@onready var employee_container = $EmployeeContainer
@onready var skylight = $Skylight

func _ready():
	print("EmployeeDropArea ready")
	print("Gamemanager is: ", Gamemanager)

	if Gamemanager.request_employee_drop.is_connected(_on_hire_received):
		print("signal already connected")
	else:
		Gamemanager.request_employee_drop.connect(_on_hire_received)
		print("signal connected to EmployeeDropArea")

func _on_hire_received(employee_data):
	print("EmployeeDropArea received hire signal: ", employee_data)

	if employee_container.get_child_count() >= 10:
		print("区域已满，员工直接送往仓库")
		send_to_warehouse(employee_data)
		return

	spawn_and_drop(employee_data)

func spawn_and_drop(data):
	print("spawn_and_drop called")

	var new_emp = load("res://scenes/employee/employee.tscn").instantiate()
	employee_container.add_child(new_emp)

	new_emp.position = skylight.position

	var random_x = randf_range(20, 280)
	var target_pos = Vector2(random_x, 320)

	var tween = create_tween()
	tween.tween_property(new_emp, "position", target_pos, 0.6)\
		.set_trans(Tween.TRANS_BOUNCE)\
		.set_ease(Tween.EASE_OUT)

func send_to_warehouse(data):
	print("send_to_warehouse called: ", data)
	pass
