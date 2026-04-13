extends Control
class_name DeskSeat

@onready var drop_area: Control = $DropArea
@onready var snap_point: Control = $SnapPoint

var occupant: Control = null

func _ready() -> void:
	add_to_group("desk_seats")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func is_free() -> bool:
	return occupant == null

func set_occupant(employee: Control) -> void:
	occupant = employee

func clear_occupant() -> void:
	occupant = null

func get_snap_global_position() -> Vector2:
	return snap_point.global_position

func contains_global_point(point: Vector2) -> bool:
	var rect := Rect2(drop_area.global_position, drop_area.size)
	return rect.has_point(point)
