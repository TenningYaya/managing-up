extends Control

var _dragging := false
var _drag_offset := Vector2()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_global_rect().has_point(get_global_mouse_position()):
				_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				get_viewport().set_input_as_handled()
		else:
			_dragging = false

	if event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		get_viewport().set_input_as_handled()
