extends Control
class_name Employee

signal work_progress_changed(progress_percent: float)
signal work_started()
signal work_stopped()
signal work_cycle_completed(reward_amount: int)

enum Rarity { R, SR, SSR }

var employee_name: String = "Marry"
var rarity: Rarity = Rarity.R

var efficiency: int = 1
var quality: int = 1
var experience: int = 1

@export var snap_distance: float = 60.0
@export var base_work_duration: float = 10.0
@export var reward_per_cycle: int = 50
@export var interrupted_reward_ratio: float = 0.5

var dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var current_seat: DeskSeat = null
var drag_start_seat: DeskSeat = null
var drag_start_position: Vector2 = Vector2.ZERO

var is_working: bool = false
var work_elapsed: float = 0.0


func _ready() -> void:
	add_to_group("employees")
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1
	randomize()
	employee_name = name


func setup_employee(new_rarity: Rarity) -> void:
	rarity = new_rarity
	_generate_attributes()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_drag()
		accept_event()


func _input(event: InputEvent) -> void:
	if not dragging:
		return

	if event is InputEventMouseMotion:
		global_position = get_global_mouse_position() - drag_offset

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var drag_distance := global_position.distance_to(drag_start_position)

			if drag_distance < 5.0:
				_on_employee_clicked()

			_end_drag()


func _draw() -> void:
	if dragging:
		var my_center = size / 2.0
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
			_finish_one_work_cycle()


func _on_employee_clicked() -> void:
	print("点击了同事: ", employee_name)

	var panel = get_tree().get_first_node_in_group("employee_panel")
	if panel and panel.has_method("open_panel"):
		panel.open_panel(self)
	else:
		var fallback_panel = get_tree().root.find_child("EmployeePanel", true, false)
		if fallback_panel and fallback_panel.has_method("open_panel"):
			fallback_panel.open_panel(self)
		else:
			print("警告：未找到 EmployeePanel，或它没有 open_panel() 方法")


func _start_drag() -> void:
	dragging = true
	drag_offset = get_global_mouse_position() - global_position
	drag_start_position = global_position
	drag_start_seat = current_seat
	z_index = 100

	if current_seat != null:
		_calculate_interrupted_kpi()
		current_seat.clear_occupant()
		current_seat = null


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
		var tween := create_tween()
		tween.tween_property(self, "global_position", target_pos, 0.12)
		tween.finished.connect(_on_snap_finished)
	else:
		global_position = target_pos
		_start_production_timer()


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
	_start_production_timer()


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


func _start_production_timer() -> void:
	is_working = true
	work_elapsed = 0.0
	work_progress_changed.emit(0.0)
	work_started.emit()
	print(employee_name, " 开始工作")


func _calculate_interrupted_kpi() -> void:
	if not is_working:
		return

	var progress_ratio := clamp(work_elapsed / _get_actual_work_duration(), 0.0, 1.0)
	var partial_reward := int(round(reward_per_cycle * progress_ratio * interrupted_reward_ratio))

	is_working = false
	work_elapsed = 0.0
	work_progress_changed.emit(0.0)
	work_stopped.emit()

	if partial_reward > 0:
		var manager = _get_employee_manager()
		if manager != null and manager.has_method("add_money"):
			manager.add_money(partial_reward)
			print(employee_name, " 工作被打断，结算部分收益: ", partial_reward)


func get_work_progress_percent() -> float:
	var duration := _get_actual_work_duration()
	if duration <= 0.0:
		return 0.0
	return clamp(work_elapsed / duration * 100.0, 0.0, 100.0)


func _get_actual_work_duration() -> float:
	var speed_bonus := float(efficiency - 1) * 0.6
	return max(2.0, base_work_duration - speed_bonus)


func _finish_one_work_cycle() -> void:
	var manager = _get_employee_manager()
	if manager != null and manager.has_method("add_money"):
		manager.add_money(reward_per_cycle)

	print(employee_name, " 完成一轮工作，获得: ", reward_per_cycle)

	work_cycle_completed.emit(reward_per_cycle)
	work_elapsed = 0.0
	work_progress_changed.emit(0.0)


func _get_employee_manager() -> Node:
	return get_tree().root.get_node_or_null("EmployeeManager")
