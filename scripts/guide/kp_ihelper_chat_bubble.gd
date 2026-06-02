extends Control
signal dialogue_finished

@onready var label: RichTextLabel = $HBoxContainer/RichTextLabel

const CHAR_SPEED := 0.02

var _lines: Array[String] = []
var _current_index: int = 0
var _is_typing_done := false

# 🌟 改成接收整个数组
func setup(dialogue_lines: Array[String]) -> void:
	_lines = dialogue_lines
	_current_index = 0
	_show_current_line()

func _show_current_line() -> void:
	var text = _lines[_current_index] if _lines.size() > 0 else ""
	label.text = ""
	label.visible_characters = 0
	label.text = text
	_is_typing_done = false
	_play_typewriter()

func _play_typewriter() -> void:
	var total_chars = label.get_total_character_count()
	var tween = create_tween()
	tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_SPEED)
	await tween.finished
	_is_typing_done = true

func _input(event: InputEvent) -> void:
	if not _is_typing_done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_is_typing_done = false
		_current_index += 1
		
		if _current_index < _lines.size():
			# 还有下一句，继续播
			_show_current_line()
		else:
			# 说完了，通知大总管
			emit_signal("dialogue_finished")
