#seat.gd
extends Control
class_name DeskSeat

@onready var drop_area: Control = $DropArea
@onready var snap_point: Control = $SnapPoint

var occupant: Control = null: 
	set(v):
		occupant = v

func _draw() -> void:
	# 画出 DropArea 的矩形框（绿色）
	var rect = Rect2(Vector2.ZERO, $DropArea.size) # 相对于自身位置
	draw_rect(rect, Color(0, 1, 0, 0.3), false, 2.0)
	
	# 画出吸附中心点（红点）
	draw_circle($SnapPoint.position, 5.0, Color.RED)

func _process(_delta):
	queue_redraw() # 确保每一帧都重绘（如果你的桌子是动的）
	
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
