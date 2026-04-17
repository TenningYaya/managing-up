extends Control
class_name DeskSeat

signal upgrade_level_changed(new_level: int)

@export_range(1, 4, 1) var upgrade_level: int = 1

@onready var drop_area: Control = $DropArea
@onready var snap_point: Control = $SnapPoint

@onready var computer: CanvasItem = $Computer as CanvasItem
@onready var coffee_cup: CanvasItem = get_node_or_null("CoffeeCup") as CanvasItem
@onready var advanced_computer: CanvasItem = get_node_or_null("AdvancedComputer") as CanvasItem
@onready var plant: CanvasItem = get_node_or_null("Plant") as CanvasItem

var occupant: Control = null


func _ready() -> void:
	add_to_group("desk_seats")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_upgrade_visuals()


func _draw() -> void:
	var rect: Rect2 = Rect2(drop_area.position, drop_area.size)
	draw_rect(rect, Color(0, 1, 0, 0.3), false, 2.0)
	draw_circle(snap_point.position, 5.0, Color.RED)


func _process(_delta: float) -> void:
	queue_redraw()


func is_free() -> bool:
	return occupant == null


func set_occupant(employee: Control) -> void:
	occupant = employee


func clear_occupant() -> void:
	occupant = null


func get_snap_global_position() -> Vector2:
	return snap_point.global_position


func contains_global_point(point: Vector2) -> bool:
	var rect: Rect2 = Rect2(drop_area.global_position, drop_area.size)
	return rect.has_point(point)


func set_upgrade_level(new_level: int) -> void:
	var clamped_level: int = clampi(new_level, 1, 4)
	if upgrade_level == clamped_level:
		return

	upgrade_level = clamped_level
	_apply_upgrade_visuals()
	upgrade_level_changed.emit(upgrade_level)


func upgrade_one_level() -> void:
	if upgrade_level < 4:
		upgrade_level += 1
		_apply_upgrade_visuals()
		upgrade_level_changed.emit(upgrade_level)


func _apply_upgrade_visuals() -> void:
	# 先重置到默认状态
	if computer != null:
		computer.visible = true

	if coffee_cup != null:
		coffee_cup.visible = false

	if advanced_computer != null:
		advanced_computer.visible = false

	if plant != null:
		plant.visible = false

	# 1级：默认，不做额外修改

	# 2级：显示咖啡杯
	if upgrade_level >= 2:
		if coffee_cup != null:
			coffee_cup.visible = true

	# 3级：普通电脑隐藏，高级电脑显示
	if upgrade_level >= 3:
		if computer != null:
			computer.visible = false
		if advanced_computer != null:
			advanced_computer.visible = true

	# 4级：显示绿植
	if upgrade_level >= 4:
		if plant != null:
			plant.visible = true
