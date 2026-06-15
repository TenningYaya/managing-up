extends Control

var _dragging := false
var _drag_offset := Vector2()

@onready var text_edit: TextEdit = $TextEdit

func _ready() -> void:
	text_edit.text = Gamemanager.sticky_note_text
	text_edit.text_changed.connect(_on_text_changed)

func _on_text_changed() -> void:
	Gamemanager.sticky_note_text = text_edit.text

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var title_rect := Rect2(global_position, Vector2(size.x, 35.0))
			if title_rect.has_point(get_global_mouse_position()):
				_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				get_viewport().set_input_as_handled()
		else:
			_dragging = false
	if event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		get_viewport().set_input_as_handled()
